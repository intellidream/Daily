import Foundation
import Combine
import Supabase
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Centralized reactive store for Prism (Assisted Web & Capture Studio).
/// Orchestrates:
/// 1. Local-first + Lean Supabase cloud sync (`updated_at` watermarks & `returning: .minimal`) for `prism_clips` and `prism_pinned_sites`.
/// 2. Single-Active-Engine Tab Hibernation (up to 8 local tabs; background tabs release WebView memory).
/// 3. App Group Share Extension queue ingestion & Smart Clipboard URL detection.
/// 4. 1-Tap bridges to `TagdosStore` (`#prism`), `SavedArticlesService` (Read Later), and `NewsService` (+Subscribe RSS).
@MainActor
public final class PrismStore: ObservableObject {
    public static let shared = PrismStore()

    // MARK: - Published State
    @Published public private(set) var allClips: [PrismClip] = []
    @Published public private(set) var allPinnedSites: [PrismPinnedSite] = []
    @Published public private(set) var tabs: [PrismTabState] = []
    @Published public var activeTabId: UUID?
    @Published public private(set) var isSyncing: Bool = false
    @Published public var pendingNavigationRequest: PrismNavigationRequest? = nil
    @Published public var clipboardCandidateUrl: String? = nil

    // MARK: - Active Computed Collections
    public var clips: [PrismClip] {
        allClips
            .filter { !$0.isDeleted }
            .sorted {
                if $0.isFavorite != $1.isFavorite { return $0.isFavorite && !$1.isFavorite }
                return $0.createdAt > $1.createdAt
            }
    }

    public var pinnedSites: [PrismPinnedSite] {
        allPinnedSites
            .filter { !$0.isDeleted }
            .sorted { $0.displayOrder < $1.displayOrder }
    }

    public var activeTab: PrismTabState? {
        if let activeId = activeTabId, let match = tabs.first(where: { $0.id == activeId }) {
            return match
        }
        return tabs.first
    }

    // MARK: - Storage Keys
    private let clipsStorageKey = "daily_prism_clips_v1"
    private let pinsStorageKey = "daily_prism_pinned_sites_v1"
    private let tabsStorageKey = "daily_prism_open_tabs_v1"
    private let activeTabStorageKey = "daily_prism_active_tab_id_v1"
    private let clipsWatermarkKey = "daily_prism_clips_watermark_v1"
    private let pinsWatermarkKey = "daily_prism_pins_watermark_v1"
    private let lastDismissedClipboardKey = "daily_prism_last_clipboard_url_v1"
    public static let pendingSharesStorageKey = "daily_prism_pending_shares_v1"

    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeDebounceTask: Task<Void, Never>?
    private var lastLocalPushAt: Date = .distantPast
    private var lastForegroundSyncAt: Date = .distantPast

    private var defaults: UserDefaults {
        UserDefaults(suiteName: GroupDefaults.suiteName) ?? .standard
    }

    private init() {
        loadFromLocalStorage()
        ensureAtLeastOneTab()
        consumePendingSharedItems()
        setupLifecycleObservers()

        Task {
            await syncWithSupabase()
            await setupRealtimeSubscription()
        }
    }

    // MARK: - Lifecycle & Clipboard Inspection

    private func setupLifecycleObservers() {
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.consumePendingSharedItems()
                self.inspectClipboardForUrl()
                guard Date().timeIntervalSince(self.lastForegroundSyncAt) >= 90 else { return }
                self.lastForegroundSyncAt = Date()
                await self.syncWithSupabase()
            }
        }
        #elseif canImport(AppKit)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.consumePendingSharedItems()
                self.inspectClipboardForUrl()
                guard Date().timeIntervalSince(self.lastForegroundSyncAt) >= 90 else { return }
                self.lastForegroundSyncAt = Date()
                await self.syncWithSupabase()
            }
        }
        #endif
    }

    public func inspectClipboardForUrl() {
        guard SettingsService.shared.settings.prismClipboardDetectEnabled else {
            clipboardCandidateUrl = nil
            return
        }

        var rawString: String? = nil
        #if canImport(UIKit)
        if UIPasteboard.general.hasURLs || UIPasteboard.general.hasStrings {
            rawString = UIPasteboard.general.url?.absoluteString ?? UIPasteboard.general.string
        }
        #elseif canImport(AppKit)
        rawString = NSPasteboard.general.string(forType: .string)
        #endif

        guard let candidate = rawString?.trimmingCharacters(in: .whitespacesAndNewlines),
              (candidate.hasPrefix("https://") || candidate.hasPrefix("http://")),
              !candidate.contains(" "),
              URL(string: candidate)?.host != nil else {
            return
        }

        let lastHandled = defaults.string(forKey: lastDismissedClipboardKey)
        let alreadyOpen = tabs.contains { $0.url == candidate }
        let alreadyClipped = clips.contains { $0.sourceUrl == candidate }
        if candidate != lastHandled && !alreadyOpen && !alreadyClipped {
            clipboardCandidateUrl = candidate
        }
    }

    public func dismissClipboardCandidate() {
        if let current = clipboardCandidateUrl {
            defaults.set(current, forKey: lastDismissedClipboardKey)
        }
        clipboardCandidateUrl = nil
    }

    // MARK: - Local Persistence

    private func makeEncoder() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return enc
    }

    private func makeDecoder() -> JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }

    private func loadFromLocalStorage() {
        let decoder = makeDecoder()

        if let data = defaults.data(forKey: clipsStorageKey),
           let decoded = try? decoder.decode([PrismClip].self, from: data) {
            self.allClips = decoded
        }

        if let data = defaults.data(forKey: pinsStorageKey),
           let decoded = try? decoder.decode([PrismPinnedSite].self, from: data),
           !decoded.isEmpty {
            self.allPinnedSites = decoded
        } else {
            self.allPinnedSites = PrismPinnedSite.defaultStarterSites(userId: AuthService.shared.currentUser?.id)
            savePinsLocally()
        }

        if let data = defaults.data(forKey: tabsStorageKey),
           let decoded = try? decoder.decode([PrismTabState].self, from: data) {
            // Never restore ephemeral private tabs from disk
            self.tabs = decoded.filter { !$0.isPrivate }
        }

        if let activeIdStr = defaults.string(forKey: activeTabStorageKey),
           let uuid = UUID(uuidString: activeIdStr),
           tabs.contains(where: { $0.id == uuid }) {
            self.activeTabId = uuid
        } else {
            self.activeTabId = tabs.first?.id
        }
    }

    private func saveClipsLocally() {
        if let data = try? makeEncoder().encode(allClips) {
            defaults.set(data, forKey: clipsStorageKey)
        }
    }

    private func savePinsLocally() {
        if let data = try? makeEncoder().encode(allPinnedSites) {
            defaults.set(data, forKey: pinsStorageKey)
        }
    }

    private func saveTabsLocally() {
        let persistentTabs = tabs.filter { !$0.isPrivate }
        if let data = try? makeEncoder().encode(persistentTabs) {
            defaults.set(data, forKey: tabsStorageKey)
        }
        if let activeId = activeTabId {
            defaults.set(activeId.uuidString, forKey: activeTabStorageKey)
        }
    }

    // MARK: - Single-Active-Engine Tab & Hibernation Management

    private func ensureAtLeastOneTab() {
        if tabs.isEmpty {
            let startTab = PrismTabState(title: "Start Page")
            tabs = [startTab]
            activeTabId = startTab.id
        } else if activeTabId == nil || !tabs.contains(where: { $0.id == activeTabId }) {
            activeTabId = tabs.first?.id
        }
        enforceHibernationPolicy()
    }

    /// Ensures ONLY the active tab keeps a live WebView (`isHibernated = false`);
    /// all background tabs hibernate (`isHibernated = true`) for 0.0% idle CPU and minimal RAM.
    public func enforceHibernationPolicy() {
        for idx in tabs.indices {
            let isCurrent = (tabs[idx].id == activeTabId)
            tabs[idx].isHibernated = !isCurrent
            if isCurrent {
                tabs[idx].lastAccessedAt = Date()
            }
        }
        saveTabsLocally()
    }

    public func selectTab(_ tabId: UUID) {
        guard tabs.contains(where: { $0.id == tabId }) else { return }
        activeTabId = tabId
        enforceHibernationPolicy()
    }

    @discardableResult
    public func openNewTab(url: String = "", title: String? = nil, isPrivate: Bool = false) -> PrismTabState {
        if tabs.count >= PrismTabState.maxOpenTabs {
            // Evict least-recently-used background tab cleanly
            if let oldestIdx = tabs
                .enumerated()
                .filter({ $0.element.id != activeTabId })
                .min(by: { $0.element.lastAccessedAt < $1.element.lastAccessedAt })?.offset {
                tabs.remove(at: oldestIdx)
            }
        }

        let resolvedTitle = title ?? (url.isEmpty ? (isPrivate ? "Private Tab" : "Start Page") : PrismSearchEngine.extractCleanDomain(from: url))
        let newTab = PrismTabState(
            url: url,
            title: resolvedTitle,
            isPrivate: isPrivate,
            isHibernated: false
        )
        tabs.append(newTab)
        activeTabId = newTab.id
        enforceHibernationPolicy()
        return newTab
    }

    public func closeTab(_ tabId: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        let wasActive = (activeTabId == tabId)
        tabs.remove(at: idx)
        if tabs.isEmpty {
            let fresh = PrismTabState(title: "Start Page")
            tabs = [fresh]
            activeTabId = fresh.id
        } else if wasActive {
            let nextIdx = min(idx, tabs.count - 1)
            activeTabId = tabs[nextIdx].id
        }
        enforceHibernationPolicy()
    }

    public func updateActiveTabMetadata(
        url: String? = nil,
        title: String? = nil,
        scrollY: Double? = nil,
        isReaderMode: Bool? = nil,
        detectedRssUrl: String?? = nil,
        detectedRssTitle: String?? = nil
    ) {
        guard let activeId = activeTabId,
              let idx = tabs.firstIndex(where: { $0.id == activeId }) else { return }

        if let url = url, !url.isEmpty {
            tabs[idx].url = url
            tabs[idx].domain = PrismSearchEngine.extractCleanDomain(from: url)
            tabs[idx].faviconUrl = PrismSearchEngine.faviconURLString(for: url)
        }
        if let title = title, !title.isEmpty {
            tabs[idx].title = title
        }
        if let scrollY = scrollY {
            tabs[idx].scrollY = scrollY
        }
        if let isReaderMode = isReaderMode {
            tabs[idx].isReaderMode = isReaderMode
        }
        if let rssOpt = detectedRssUrl {
            tabs[idx].detectedRssUrl = rssOpt
        }
        if let rssTitleOpt = detectedRssTitle {
            tabs[idx].detectedRssTitle = rssTitleOpt
        }
        saveTabsLocally()
    }

    public func requestOpenInPrism(
        url: String,
        title: String? = nil,
        openInNewTab: Bool = false,
        isPrivate: Bool = false,
        autoTriggerCoPilot: PrismCoPilotAction? = nil
    ) {
        guard let safeUrl = PrismSearchEngine.resolveOmniboxInput(url, engine: SettingsService.shared.settings.prismSearchEngine) else {
            return
        }
        let finalUrl = safeUrl.absoluteString
        if openInNewTab || activeTab?.isPrivate != isPrivate {
            openNewTab(url: finalUrl, title: title, isPrivate: isPrivate)
        } else if let activeId = activeTabId, let idx = tabs.firstIndex(where: { $0.id == activeId }) {
            tabs[idx].url = finalUrl
            tabs[idx].domain = PrismSearchEngine.extractCleanDomain(from: finalUrl)
            tabs[idx].faviconUrl = PrismSearchEngine.faviconURLString(for: finalUrl)
            if let title = title, !title.isEmpty {
                tabs[idx].title = title
            }
            tabs[idx].isReaderMode = false
            saveTabsLocally()
        }
        pendingNavigationRequest = PrismNavigationRequest(
            url: finalUrl,
            title: title,
            openInNewTab: openInNewTab,
            isPrivate: isPrivate,
            autoTriggerCoPilot: autoTriggerCoPilot
        )
    }

    // MARK: - Vault Clipping Operations (Links, Quotes, Images/Crops, AI Summaries)

    @discardableResult
    public func saveLinkClip(
        url: String,
        title: String,
        previewImageUrl: String? = nil,
        userNote: String = "",
        tags: [String] = []
    ) -> PrismClip {
        if let existingIdx = allClips.firstIndex(where: { !$0.isDeleted && $0.clipType == .link && $0.sourceUrl == url }) {
            allClips[existingIdx].title = title.isEmpty ? allClips[existingIdx].title : title
            if !userNote.isEmpty { allClips[existingIdx].userNote = userNote }
            if !tags.isEmpty { allClips[existingIdx].tags = Array(Set(allClips[existingIdx].tags + tags)).sorted() }
            allClips[existingIdx].updatedAt = Date()
            saveClipsLocally()
            let updated = allClips[existingIdx]
            Task { await pushClipToSupabase(updated) }
            return updated
        }

        let clip = PrismClip(
            userId: AuthService.shared.currentUser?.id,
            clipType: .link,
            title: title.isEmpty ? PrismSearchEngine.extractCleanDomain(from: url) : title,
            sourceUrl: url,
            userNote: userNote,
            tags: tags,
            previewImageUrl: previewImageUrl
        )
        allClips.insert(clip, at: 0)
        saveClipsLocally()
        Task { await pushClipToSupabase(clip) }
        return clip
    }

    @discardableResult
    public func saveQuoteClip(
        quoteText: String,
        sourceUrl: String,
        pageTitle: String,
        userNote: String = "",
        tags: [String] = []
    ) -> PrismClip {
        let clip = PrismClip(
            userId: AuthService.shared.currentUser?.id,
            clipType: .quote,
            title: pageTitle.isEmpty ? PrismSearchEngine.extractCleanDomain(from: sourceUrl) : pageTitle,
            sourceUrl: sourceUrl,
            contentText: quoteText.trimmingCharacters(in: .whitespacesAndNewlines),
            userNote: userNote,
            tags: tags
        )
        allClips.insert(clip, at: 0)
        saveClipsLocally()
        Task { await pushClipToSupabase(clip) }
        return clip
    }

    @discardableResult
    public func saveAISummaryClip(
        turn: PrismCoPilotTurn,
        tags: [String] = ["ai"]
    ) -> PrismClip {
        var mdLines: [String] = [turn.responseMarkdown]
        if !turn.keyBullets.isEmpty {
            mdLines.append("")
            for b in turn.keyBullets {
                mdLines.append("• \(b)")
            }
        }
        let clip = PrismClip(
            userId: AuthService.shared.currentUser?.id,
            clipType: .aiSummary,
            title: turn.pageTitle.isEmpty ? turn.prompt : "\(turn.pageTitle) — \(turn.prompt)",
            sourceUrl: turn.sourceUrl,
            contentText: mdLines.joined(separator: "\n"),
            tags: tags
        )
        allClips.insert(clip, at: 0)
        saveClipsLocally()
        Task { await pushClipToSupabase(clip) }
        return clip
    }

    @discardableResult
    public func saveImageClip(
        rawImageData: Data?,
        remoteImageUrl: String? = nil,
        sourceUrl: String,
        title: String,
        tags: [String] = []
    ) async -> PrismClip {
        let clipId = UUID()
        var compressedPayload: PrismAttachmentManager.CompressedImagePayload? = nil
        var resolvedRawData = rawImageData

        if resolvedRawData == nil, let imgUrlStr = remoteImageUrl, let imgUrl = URL(string: imgUrlStr) {
            if let (downloaded, _) = try? await URLSession.shared.data(from: imgUrl) {
                resolvedRawData = downloaded
            }
        }

        if let data = resolvedRawData {
            compressedPayload = PrismAttachmentManager.shared.compressImageData(data)
            if let payload = compressedPayload {
                _ = try? PrismAttachmentManager.shared.saveLocalImageData(payload.data, for: clipId, ext: payload.fileExtension)
            } else {
                _ = try? PrismAttachmentManager.shared.saveLocalImageData(data, for: clipId, ext: "jpg")
            }
        }

        var clip = PrismClip(
            id: clipId,
            userId: AuthService.shared.currentUser?.id,
            clipType: .image,
            title: title.isEmpty ? PrismSearchEngine.extractCleanDomain(from: sourceUrl) : title,
            sourceUrl: sourceUrl,
            tags: tags,
            previewImageUrl: remoteImageUrl,
            imageWidth: compressedPayload?.width,
            imageHeight: compressedPayload?.height
        )

        if let userId = await effectiveUserIdAsync(),
           let uploadBytes = compressedPayload?.data ?? resolvedRawData {
            if let storagePath = try? await PrismAttachmentManager.shared.uploadClipImage(
                clipId: clipId,
                data: uploadBytes,
                mimeType: compressedPayload?.mimeType ?? "image/jpeg",
                ext: compressedPayload?.fileExtension ?? "jpg",
                userId: userId
            ) {
                clip.storagePath = storagePath
            }
        }

        allClips.insert(clip, at: 0)
        saveClipsLocally()
        await pushClipToSupabase(clip)
        return clip
    }

    public func toggleFavoriteClip(_ clipId: UUID) {
        guard let idx = allClips.firstIndex(where: { $0.id == clipId }) else { return }
        allClips[idx].isFavorite.toggle()
        allClips[idx].updatedAt = Date()
        saveClipsLocally()
        let updated = allClips[idx]
        Task { await pushClipToSupabase(updated) }
    }

    public func updateClipTagsAndNote(_ clipId: UUID, userNote: String, tags: [String]) {
        guard let idx = allClips.firstIndex(where: { $0.id == clipId }) else { return }
        allClips[idx].userNote = userNote
        allClips[idx].tags = tags
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "# \t\n")).lowercased() }
            .filter { !$0.isEmpty }
        allClips[idx].updatedAt = Date()
        saveClipsLocally()
        let updated = allClips[idx]
        Task { await pushClipToSupabase(updated) }
    }

    public func deleteClip(_ clipId: UUID) {
        guard let idx = allClips.firstIndex(where: { $0.id == clipId }) else { return }
        allClips[idx].isDeleted = true
        allClips[idx].updatedAt = Date()
        let removed = allClips[idx]
        saveClipsLocally()
        Task {
            await PrismAttachmentManager.shared.deleteClipAssets(for: removed)
            await pushClipToSupabase(removed)
        }
    }

    // MARK: - Pinned Speed Dial Operations

    public func isPinned(url: String) -> Bool {
        let domain = PrismSearchEngine.extractCleanDomain(from: url)
        return pinnedSites.contains { $0.url.caseInsensitiveCompare(url) == .orderedSame || $0.domain == domain }
    }

    public func togglePinSite(title: String, url: String) {
        let cleanTitle = title.isEmpty ? PrismSearchEngine.extractCleanDomain(from: url) : title
        if let idx = allPinnedSites.firstIndex(where: { !$0.isDeleted && $0.url.caseInsensitiveCompare(url) == .orderedSame }) {
            allPinnedSites[idx].isDeleted = true
            allPinnedSites[idx].updatedAt = Date()
            let updated = allPinnedSites[idx]
            savePinsLocally()
            Task { await pushPinToSupabase(updated) }
        } else {
            let pin = PrismPinnedSite(
                userId: AuthService.shared.currentUser?.id,
                title: cleanTitle,
                url: url,
                displayOrder: pinnedSites.count
            )
            allPinnedSites.append(pin)
            savePinsLocally()
            Task { await pushPinToSupabase(pin) }
        }
    }

    public func deletePinnedSite(_ pinId: UUID) {
        guard let idx = allPinnedSites.firstIndex(where: { $0.id == pinId }) else { return }
        allPinnedSites[idx].isDeleted = true
        allPinnedSites[idx].updatedAt = Date()
        let updated = allPinnedSites[idx]
        savePinsLocally()
        Task { await pushPinToSupabase(updated) }
    }

    // MARK: - 1-Tap Bridges to TagDoS & News

    @discardableResult
    public func sendClipToTagdos(_ clip: PrismClip) -> TagDoQuickNote {
        var lines: [String] = []
        if !clip.contentText.isEmpty {
            lines.append("> \(clip.contentText.replacingOccurrences(of: "\n", with: "\n> "))")
            lines.append("")
        }
        if !clip.userNote.isEmpty {
            lines.append(clip.userNote)
            lines.append("")
        }
        lines.append("🔗 [\(clip.domain.isEmpty ? clip.sourceUrl : clip.domain)](\(clip.sourceUrl))")

        let mergedTags = Array(Set(["prism"] + clip.tags)).sorted()
        let tagLine = mergedTags.map { "#\($0)" }.joined(separator: " ")
        lines.append(tagLine)

        let note = TagdosStore.shared.createQuickNote(
            title: "💎 \(clip.title)",
            content: lines.joined(separator: "\n"),
            tags: mergedTags
        )

        if let idx = allClips.firstIndex(where: { $0.id == clip.id }) {
            allClips[idx].tagdosNoteId = note.id
            allClips[idx].updatedAt = Date()
            saveClipsLocally()
            let updated = allClips[idx]
            Task { await pushClipToSupabase(updated) }
        }
        return note
    }

    public func sendTasksToTagdosQuickNote(tasks: [String], pageTitle: String, sourceUrl: String) {
        guard !tasks.isEmpty else { return }
        var lines = tasks.map { "- [ ] \($0)" }
        lines.append("")
        lines.append("🔗 [\(pageTitle.isEmpty ? sourceUrl : pageTitle)](\(sourceUrl))")
        lines.append("#prism #tasks")

        _ = TagdosStore.shared.createQuickNote(
            title: "🎯 Tasks: \(pageTitle.isEmpty ? PrismSearchEngine.extractCleanDomain(from: sourceUrl) : pageTitle)",
            content: lines.joined(separator: "\n"),
            tags: ["prism", "tasks"]
        )
    }

    public func saveUrlToNewsReadLater(url: String, title: String, previewImageUrl: String? = nil, summary: String = "") {
        let article = NewsArticle(
            title: title.isEmpty ? PrismSearchEngine.extractCleanDomain(from: url) : title,
            link: url,
            publishDate: Date(),
            imageUrl: previewImageUrl ?? "",
            description: summary,
            publicationName: PrismSearchEngine.extractCleanDomain(from: url),
            publicationIconUrl: PrismSearchEngine.faviconURLString(for: url)
        )
        if !SavedArticlesService.shared.isReadLater(url: url) {
            SavedArticlesService.shared.toggleReadLater(for: article)
        }
    }

    public func isFeedSubscribedInNews(feedUrl: String) -> Bool {
        NewsService.shared.feeds.contains { $0.url.caseInsensitiveCompare(feedUrl) == .orderedSame }
    }

    public func subscribeFeedInNews(feedUrl: String, title: String, siteUrl: String) {
        guard !isFeedSubscribedInNews(feedUrl: feedUrl) else { return }
        let cleanName = title.isEmpty ? PrismSearchEngine.extractCleanDomain(from: siteUrl) : title
        NewsService.shared.addFeed(
            name: cleanName,
            url: feedUrl,
            iconUrl: PrismSearchEngine.faviconURLString(for: siteUrl),
            category: .tech
        )
    }

    // MARK: - Share Extension App Group Queue Ingestion

    public static func enqueueSharedItem(_ item: PrismPendingShareItem) {
        let suite = UserDefaults(suiteName: GroupDefaults.suiteName) ?? .standard
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        var queue: [PrismPendingShareItem] = []
        if let existing = suite.data(forKey: pendingSharesStorageKey),
           let decoded = try? decoder.decode([PrismPendingShareItem].self, from: existing) {
            queue = decoded
        }
        queue.append(item)
        if let encoded = try? encoder.encode(queue) {
            suite.set(encoded, forKey: pendingSharesStorageKey)
        }
    }

    public func consumePendingSharedItems() {
        guard let data = defaults.data(forKey: Self.pendingSharesStorageKey),
              let pending = try? makeDecoder().decode([PrismPendingShareItem].self, from: data),
              !pending.isEmpty else {
            return
        }
        defaults.removeObject(forKey: Self.pendingSharesStorageKey)

        for item in pending {
            switch item.clipType {
            case .quote:
                saveQuoteClip(
                    quoteText: item.text,
                    sourceUrl: item.url.isEmpty ? "https://shared.local" : item.url,
                    pageTitle: item.title.isEmpty ? "Shared Quote" : item.title,
                    tags: ["shared"]
                )
            case .image:
                if let fileName = item.localImageFileName {
                    let fileUrl = PrismAttachmentManager.shared.cacheDirectoryURL.appendingPathComponent(fileName)
                    let imgData = try? Data(contentsOf: fileUrl)
                    try? FileManager.default.removeItem(at: fileUrl)
                    Task {
                        await saveImageClip(
                            rawImageData: imgData,
                            sourceUrl: item.url.isEmpty ? "https://shared.local" : item.url,
                            title: item.title.isEmpty ? "Shared Image" : item.title,
                            tags: ["shared"]
                        )
                    }
                }
            case .link, .aiSummary:
                if !item.url.isEmpty {
                    saveLinkClip(
                        url: item.url,
                        title: item.title,
                        userNote: item.text,
                        tags: ["shared"]
                    )
                    if item.openImmediatelyInPrism {
                        requestOpenInPrism(url: item.url, title: item.title, openInNewTab: true)
                    }
                }
            }
        }
    }

    // MARK: - Lean Supabase Cloud Synchronization (`updated_at` Watermark + Realtime)

    private func effectiveUserIdAsync() async -> String? {
        if let id = AuthService.shared.currentUser?.id, id != "guest" {
            return id.lowercased()
        }
        if let stored = GroupDefaults.shared.userDefaults.string(forKey: "supabase_user_id"), stored != "guest" {
            return stored.lowercased()
        }
        if let session = try? await SupabaseService.shared.client.auth.session {
            let uid = session.user.id.uuidString.lowercased()
            if uid != "guest" { return uid }
        }
        return nil
    }

    public func syncWithSupabase(forceFullPull: Bool = false) async {
        guard SettingsService.shared.settings.cloudSyncEnabled,
              let userId = await effectiveUserIdAsync() else { return }

        isSyncing = true
        defer { isSyncing = false }

        let client = SupabaseService.shared.client
        let decoder = makeDecoder()

        // 1. Incremental Delta Pull for `prism_clips`
        do {
            let lastClipWatermark = forceFullPull ? nil : defaults.string(forKey: clipsWatermarkKey)
            let response: PostgrestResponse<Data>
            if let wm = lastClipWatermark, !wm.isEmpty {
                response = try await client
                    .from("prism_clips")
                    .select()
                    .eq("user_id", value: userId)
                    .gt("updated_at", value: wm)
                    .order("updated_at", ascending: false)
                    .limit(200)
                    .execute()
            } else {
                response = try await client
                    .from("prism_clips")
                    .select()
                    .eq("user_id", value: userId)
                    .eq("is_deleted", value: false)
                    .order("updated_at", ascending: false)
                    .limit(200)
                    .execute()
            }

            if let remoteClips = try? decoder.decode([PrismClip].self, from: response.data) {
                var merged = allClips
                var newestDate: Date? = nil
                for rc in remoteClips {
                    if newestDate == nil || rc.updatedAt > newestDate! {
                        newestDate = rc.updatedAt
                    }
                    if let idx = merged.firstIndex(where: { $0.id == rc.id }) {
                        if rc.updatedAt >= merged[idx].updatedAt {
                            merged[idx] = rc
                        }
                    } else if !rc.isDeleted {
                        merged.append(rc)
                    }
                }
                allClips = merged
                saveClipsLocally()
                if let maxDate = newestDate {
                    defaults.set(ISO8601DateFormatter().string(from: maxDate), forKey: clipsWatermarkKey)
                }
            }
        } catch {
            // Gracefully preserve local-first cache on transient network issues
        }

        // 2. Incremental Delta Pull for `prism_pinned_sites`
        do {
            let lastPinWatermark = forceFullPull ? nil : defaults.string(forKey: pinsWatermarkKey)
            let response: PostgrestResponse<Data>
            if let wm = lastPinWatermark, !wm.isEmpty {
                response = try await client
                    .from("prism_pinned_sites")
                    .select()
                    .eq("user_id", value: userId)
                    .gt("updated_at", value: wm)
                    .order("updated_at", ascending: false)
                    .execute()
            } else {
                response = try await client
                    .from("prism_pinned_sites")
                    .select()
                    .eq("user_id", value: userId)
                    .eq("is_deleted", value: false)
                    .order("display_order", ascending: true)
                    .execute()
            }

            if let remotePins = try? decoder.decode([PrismPinnedSite].self, from: response.data), !remotePins.isEmpty {
                var merged = allPinnedSites
                var newestDate: Date? = nil
                for rp in remotePins {
                    if newestDate == nil || rp.updatedAt > newestDate! {
                        newestDate = rp.updatedAt
                    }
                    if let idx = merged.firstIndex(where: { $0.id == rp.id || $0.url.caseInsensitiveCompare(rp.url) == .orderedSame }) {
                        if rp.updatedAt >= merged[idx].updatedAt {
                            merged[idx] = rp
                        }
                    } else if !rp.isDeleted {
                        merged.append(rp)
                    }
                }
                allPinnedSites = merged
                savePinsLocally()
                if let maxDate = newestDate {
                    defaults.set(ISO8601DateFormatter().string(from: maxDate), forKey: pinsWatermarkKey)
                }
            }
        } catch {}
    }

    private func pushClipToSupabase(_ clip: PrismClip) async {
        guard SettingsService.shared.settings.cloudSyncEnabled,
              let userId = await effectiveUserIdAsync() else { return }
        var payload = clip
        payload.userId = userId
        lastLocalPushAt = Date()
        _ = try? await SupabaseService.shared.client
            .from("prism_clips")
            .upsert(payload, onConflict: "id", returning: .minimal)
            .execute()
    }

    private func pushPinToSupabase(_ pin: PrismPinnedSite) async {
        guard SettingsService.shared.settings.cloudSyncEnabled,
              let userId = await effectiveUserIdAsync() else { return }
        var payload = pin
        payload.userId = userId
        payload.id = PrismPinnedSite.deterministicId(userId: userId, url: pin.url)
        lastLocalPushAt = Date()
        _ = try? await SupabaseService.shared.client
            .from("prism_pinned_sites")
            .upsert(payload, onConflict: "id", returning: .minimal)
            .execute()
    }

    private func scheduleRealtimeSync() {
        guard Date().timeIntervalSince(lastLocalPushAt) >= 6.0 else { return }
        realtimeDebounceTask?.cancel()
        realtimeDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let self = self, !Task.isCancelled else { return }
            guard Date().timeIntervalSince(self.lastLocalPushAt) >= 6.0 else { return }
            await self.syncWithSupabase()
        }
    }

    private func setupRealtimeSubscription() async {
        guard let userId = await effectiveUserIdAsync() else { return }
        if realtimeChannel != nil { return }

        let client = SupabaseService.shared.client
        let channel = client.channel("daily_prism_\(userId)")

        let clipChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "prism_clips",
            filter: .eq("user_id", value: userId)
        )

        let pinChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "prism_pinned_sites",
            filter: .eq("user_id", value: userId)
        )

        do {
            try await channel.subscribeWithError()
            self.realtimeChannel = channel

            Task { [weak self] in
                for await _ in clipChanges {
                    self?.scheduleRealtimeSync()
                }
            }
            Task { [weak self] in
                for await _ in pinChanges {
                    self?.scheduleRealtimeSync()
                }
            }
        } catch {}
    }
}
