import Foundation
import Combine
import Supabase
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Reactive centralized store managing TagDoS streams, mental tags, per-stream active memos, attachments, and quick notes.
/// Backed by local App Group storage with Supabase cloud synchronization and live Realtime reflection.
@MainActor
public final class TagdosStore: ObservableObject {
    public static let shared = TagdosStore()

    // MARK: - Published State
    @Published public private(set) var streams: [TagDoStream] = []
    @Published public private(set) var quickNotes: [TagDoQuickNote] = []
    @Published public private(set) var isSyncing: Bool = false
    @Published public private(set) var lastSyncedAt: Date? = nil
    @Published public private(set) var cloudSyncError: String? = nil
    @Published public var pendingNavigation: TagdosNavigationTarget? = nil

    // MARK: - Storage Keys
    private let streamsStorageKey = "daily_tagdos_raw_streams_v1"
    private let dirtyStreamIdsStorageKey = "daily_tagdos_dirty_stream_ids_v1"
    private let notesStorageKey = "daily_tagdos_quick_notes_v1"
    private let legacyNotesKey = "daily_tagdos_quick_notes_legacy_v1"

    // MARK: - Default Starter Streams
    public static let defaultStream1 = "MG/GM/TG & FSH/LDL & C$T/DUB/14 & PL98/PBZ/SPL/CLN/ROT$ & BP/ACTE & VER/CLD/DIV$/CNTR/!MP$/FCT$/STK/BON$ & BIA/€CO & SSD/ELVS/MEIZ & GORN/PICI/CRNA/IOA & CDO/SRN/NLU/NIN/SVS & ITP/CRRvg/Park/Ghis"
    public static let defaultStream2 = "WRK/PRJ/REV & MET/ZOOM/CALL & TKT/BUG/PR & DEPL/REL"
    public static let defaultStream3 = "FIT/GYM/RUN & PROT/CREAT & SLP/REC/HRV"
    public static let defaultStream4 = "FIN/CARD/CASH & INV/STK/CRYP & SUB/UTL/CHL"
    public static let defaultStream5 = "HOM/ORD/CLN & BUY/MKT/GROC & FAM/CALL/VIS"

    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeDebounceTask: Task<Void, Never>?
    private var pushDebounceTask: Task<Void, Never>?
    private var lastLocalPushAt: Date = .distantPast
    private var lastForegroundSyncAt: Date = .distantPast
    private var lastPushedStreamSignatures: [Int: String] = [:]
    private var lastPushedNoteSignatures: [UUID: String] = [:]
    private var dirtyStreamIds: Set<UUID> = []

    private var groupDefaults: UserDefaults {
        UserDefaults(suiteName: GroupDefaults.suiteName) ?? UserDefaults.standard
    }

    private init() {
        loadFromStorage()
        setupLifecycleObservers()
        
        Task {
            await syncWithSupabase()
            await setupRealtimeSubscription()
        }
    }

    // MARK: - Lifecycle & Foreground Observers

    private func setupLifecycleObservers() {
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let hadDirtyBefore = self.dirtyStreamIds
                self.loadFromStorage()
                if self.dirtyStreamIds != hadDirtyBefore && !self.dirtyStreamIds.isEmpty {
                    self.scheduleCloudPush()
                }
                guard Date().timeIntervalSince(self.lastForegroundSyncAt) >= 120 else { return }
                self.lastForegroundSyncAt = Date()
                await self.syncWithSupabase()
            }
        }
        #endif

        // Listen for cross-process Widget AppIntent mutations so in-app state & Supabase push stay live
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let name = CFNotificationName(WidgetDataCoordinator.darwinMutationNotificationName as CFString)
        CFNotificationCenterAddObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque(),
            { _, _, _, _, _ in
                DispatchQueue.main.async {
                    Task { @MainActor in
                        TagdosStore.shared.reloadFromWidgetMutation()
                    }
                }
            },
            name.rawValue,
            nil,
            .deliverImmediately
        )
    }

    public func reloadFromWidgetMutation() {
        loadFromStorage()
        if !dirtyStreamIds.isEmpty {
            scheduleCloudPush()
        }
    }

    // MARK: - Deep Link & Navigation Routing

    public func handleDeepLink(url: URL) {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let items = comps.queryItems ?? []
        let q = Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.value.map { (item.name, $0) }
        })

        let streamId = q["streamId"].flatMap { UUID(uuidString: $0) }
        let clusterIdx = q["clusterIndex"].flatMap { Int($0) }
        let pillId = q["pillId"].flatMap { UUID(uuidString: $0) }
        let openEdit = q["edit"] == "1" || pillId != nil

        if streamId != nil || clusterIdx != nil || pillId != nil {
            pendingNavigation = TagdosNavigationTarget(
                streamId: streamId,
                clusterIndex: clusterIdx,
                pillId: pillId,
                openPillEditor: openEdit
            )
        }
    }

    public func requestEditPill(streamId: UUID, pillId: UUID) {
        pendingNavigation = TagdosNavigationTarget(
            streamId: streamId,
            clusterIndex: nil,
            pillId: pillId,
            openPillEditor: true
        )
    }

    public func consumePendingNavigation() {
        pendingNavigation = nil
    }

    // MARK: - Persistence & Hydration

    public func reloadFromStorage() {
        loadFromStorage()
    }

    public func loadFromStorage() {
        let savedDirtyStrings = groupDefaults.stringArray(forKey: dirtyStreamIdsStorageKey)
            ?? UserDefaults.standard.stringArray(forKey: dirtyStreamIdsStorageKey)
            ?? []
        self.dirtyStreamIds = Set(savedDirtyStrings.compactMap { UUID(uuidString: $0) })

        // 1. Load Quick Notes (TagDoQuickNote)
        if let data = groupDefaults.data(forKey: notesStorageKey),
           let decoded = try? JSONDecoder().decode([TagDoQuickNote].self, from: data) {
            self.quickNotes = decoded
        } else if let data = UserDefaults.standard.data(forKey: notesStorageKey),
                  let decoded = try? JSONDecoder().decode([TagDoQuickNote].self, from: data) {
            self.quickNotes = decoded
        } else {
            // Migrate legacy string notes if any
            let legacyStrings = groupDefaults.stringArray(forKey: legacyNotesKey)
                ?? UserDefaults.standard.stringArray(forKey: legacyNotesKey)
                ?? [
                    "Concert Tickets: book 2x passes and confirm budget",
                    "Car Maintenance: refuel 98 octane and schedule interior clean"
                ]
            self.quickNotes = legacyStrings.map { text in
                TagDoQuickNote(
                    title: text.components(separatedBy: ":").first ?? "Note",
                    content: text
                )
            }
        }

        // 2. Load Streams Data
        if let data = groupDefaults.data(forKey: streamsStorageKey),
           let decoded = try? JSONDecoder().decode([TagDoStream].self, from: data),
           !decoded.isEmpty {
            self.streams = decoded
            syncWithWidgets()
            TagdosNotificationManager.shared.rescheduleIfAuthorized(streams: decoded)
            return
        }

        if let data = UserDefaults.standard.data(forKey: streamsStorageKey),
           let decoded = try? JSONDecoder().decode([TagDoStream].self, from: data),
           !decoded.isEmpty {
            self.streams = decoded
            syncWithWidgets()
            TagdosNotificationManager.shared.rescheduleIfAuthorized(streams: decoded)
            return
        }

        // Seed Default 5 Streams
        let parser = TagdosParser.shared
        let defaultStreams: [TagDoStream] = [
            parser.parseStream(rawText: Self.defaultStream1, title: "Stream 1: Daily Ops", orderIndex: 0),
            parser.parseStream(rawText: Self.defaultStream2, title: "Stream 2: Work & Code", orderIndex: 1),
            parser.parseStream(rawText: Self.defaultStream3, title: "Stream 3: Health & Fitness", orderIndex: 2),
            parser.parseStream(rawText: Self.defaultStream4, title: "Stream 4: Finances & Bills", orderIndex: 3),
            parser.parseStream(rawText: Self.defaultStream5, title: "Stream 5: Home & Life", orderIndex: 4)
        ]

        self.streams = defaultStreams
        save()
    }

    private func persistDirtyStreamIds() {
        let dirtyArray = dirtyStreamIds.map { $0.uuidString }
        groupDefaults.set(dirtyArray, forKey: dirtyStreamIdsStorageKey)
        UserDefaults.standard.set(dirtyArray, forKey: dirtyStreamIdsStorageKey)
    }

    public func save(triggerCloudSync: Bool = true) {
        // Encode Streams
        if let data = try? JSONEncoder().encode(streams) {
            groupDefaults.set(data, forKey: streamsStorageKey)
            UserDefaults.standard.set(data, forKey: streamsStorageKey)
        }

        // Save Quick Notes
        if let notesData = try? JSONEncoder().encode(quickNotes) {
            groupDefaults.set(notesData, forKey: notesStorageKey)
            UserDefaults.standard.set(notesData, forKey: notesStorageKey)
        }

        persistDirtyStreamIds()
        syncWithWidgets()

        if triggerCloudSync {
            scheduleCloudPush()
        }
    }

    // MARK: - Stream Mutations

    public func updateStreamRawText(streamId: UUID, newRawText: String) {
        guard let index = streams.firstIndex(where: { $0.id == streamId }) else { return }
        let existing = streams[index]
        var updated = TagdosParser.shared.parseStream(
            rawText: newRawText,
            title: existing.customTitle ?? existing.title,
            id: existing.id,
            streamReminder: existing.streamReminder,
            orderIndex: existing.orderIndex,
            existingStream: existing
        )
        updated.customTitle = existing.customTitle
        if existing.customTitle == nil || existing.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            updated.title = updated.autoDetectedTitle
        }
        updated.activeMemos = existing.activeMemos
        updated.attachments = existing.attachments
        updated.updatedAt = Date()
        streams[index] = updated
        dirtyStreamIds.insert(streamId)
        save()
    }

    public func updateStreamTitle(streamId: UUID, newTitle: String?) {
        guard let index = streams.firstIndex(where: { $0.id == streamId }) else { return }
        let clean = newTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let clean = clean, !clean.isEmpty {
            // User explicitly set a custom title
            streams[index].customTitle = clean
            streams[index].title = clean
        } else {
            // User cleared the title -> re-detect title from stream content
            streams[index].customTitle = nil
            streams[index].title = streams[index].autoDetectedTitle
        }
        streams[index].updatedAt = Date()
        dirtyStreamIds.insert(streamId)
        save()
    }

    public func setStreamReminder(streamId: UUID, date: Date?) {
        guard let index = streams.firstIndex(where: { $0.id == streamId }) else { return }
        streams[index].streamReminder = date
        streams[index].updatedAt = Date()
        dirtyStreamIds.insert(streamId)
        save()
        if date != nil {
            TagdosNotificationManager.shared.requestAuthorizationAndReschedule(streams: streams)
        } else {
            TagdosNotificationManager.shared.rescheduleIfAuthorized(streams: streams)
        }
    }

    public func setClusterReminder(streamId: UUID, clusterIndex: Int, date: Date?) {
        guard let index = streams.firstIndex(where: { $0.id == streamId }),
              streams[index].clusters.indices.contains(clusterIndex) else { return }
        streams[index].clusters[clusterIndex].reminderDate = date
        streams[index].updatedAt = Date()
        dirtyStreamIds.insert(streamId)
        save()
        if date != nil {
            TagdosNotificationManager.shared.requestAuthorizationAndReschedule(streams: streams)
        } else {
            TagdosNotificationManager.shared.rescheduleIfAuthorized(streams: streams)
        }
    }

    public func updateStreamMemos(streamId: UUID, memos: String) {
        guard let index = streams.firstIndex(where: { $0.id == streamId }) else { return }
        streams[index].activeMemos = memos
        streams[index].updatedAt = Date()
        dirtyStreamIds.insert(streamId)
        save()
    }

    public func recyclePillToBack(streamId: UUID, pillId: UUID) {
        guard let index = streams.firstIndex(where: { $0.id == streamId }) else { return }
        var updated = TagdosParser.shared.recyclePillToBack(in: streams[index], pillId: pillId)
        updated.activeMemos = streams[index].activeMemos
        updated.attachments = streams[index].attachments
        updated.updatedAt = Date()
        streams[index] = updated
        dirtyStreamIds.insert(streamId)
        save()
    }

    public func togglePillCompletion(streamId: UUID, pillId: UUID) {
        guard let index = streams.firstIndex(where: { $0.id == streamId }) else { return }
        var updated = TagdosParser.shared.togglePillCompletion(in: streams[index], pillId: pillId)
        updated.activeMemos = streams[index].activeMemos
        updated.attachments = streams[index].attachments
        updated.updatedAt = Date()
        streams[index] = updated
        dirtyStreamIds.insert(streamId)
        save()
    }

    public func removePill(streamId: UUID, pillId: UUID) {
        guard let index = streams.firstIndex(where: { $0.id == streamId }) else { return }
        var updated = TagdosParser.shared.removePill(in: streams[index], pillId: pillId)
        updated.activeMemos = streams[index].activeMemos
        updated.attachments = streams[index].attachments
        updated.updatedAt = Date()
        streams[index] = updated
        dirtyStreamIds.insert(streamId)
        save()
    }

    public func movePillToFront(streamId: UUID, pillId: UUID) {
        guard let index = streams.firstIndex(where: { $0.id == streamId }) else { return }
        var updated = TagdosParser.shared.movePillToFront(in: streams[index], pillId: pillId)
        updated.activeMemos = streams[index].activeMemos
        updated.attachments = streams[index].attachments
        updated.updatedAt = Date()
        streams[index] = updated
        dirtyStreamIds.insert(streamId)
        save()
    }

    public func addPill(streamId: UUID, clusterIndex: Int, text: String) {
        guard let index = streams.firstIndex(where: { $0.id == streamId }) else { return }
        var updated = TagdosParser.shared.addPill(in: streams[index], clusterIndex: clusterIndex, text: text)
        updated.activeMemos = streams[index].activeMemos
        updated.attachments = streams[index].attachments
        updated.updatedAt = Date()
        streams[index] = updated
        dirtyStreamIds.insert(streamId)
        save()
    }

    public func updatePillText(streamId: UUID, pillId: UUID, newText: String) {
        guard let index = streams.firstIndex(where: { $0.id == streamId }) else { return }
        var updated = TagdosParser.shared.updatePillText(in: streams[index], pillId: pillId, newText: newText)
        updated.activeMemos = streams[index].activeMemos
        updated.attachments = streams[index].attachments
        updated.updatedAt = Date()
        streams[index] = updated
        dirtyStreamIds.insert(streamId)
        save()
    }

    @discardableResult
    public func createStream(title: String? = nil, rawText: String = "", activeMemos: String = "") -> TagDoStream {
        let stream = buildNewStream(title: title, rawText: rawText, activeMemos: activeMemos, orderIndex: (streams.map { $0.orderIndex }.max() ?? -1) + 1)
        streams.append(stream)
        dirtyStreamIds.insert(stream.id)
        save()
        return stream
    }

    private func buildNewStream(title: String?, rawText: String, activeMemos: String, orderIndex: Int) -> TagDoStream {
        let cleanTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultTitle = "Stream \(orderIndex + 1)"
        var stream = TagdosParser.shared.parseStream(
            rawText: rawText,
            title: cleanTitle?.isEmpty == false ? cleanTitle! : defaultTitle,
            orderIndex: orderIndex
        )
        if let cleanTitle, !cleanTitle.isEmpty {
            stream.customTitle = cleanTitle
            stream.title = cleanTitle
        } else {
            stream.customTitle = nil
            stream.title = stream.autoDetectedTitle
        }
        stream.activeMemos = activeMemos
        stream.updatedAt = Date()
        return stream
    }

    public func moveStream(fromIndex: Int, toIndex: Int) {
        guard streams.indices.contains(fromIndex),
              streams.indices.contains(toIndex),
              fromIndex != toIndex else { return }
        var reordered = streams
        let item = reordered.remove(at: fromIndex)
        reordered.insert(item, at: toIndex)
        applyReorderedStreams(reordered)
    }

    public func reorderStreams(orderedIds: [UUID]) {
        var byId = Dictionary(uniqueKeysWithValues: streams.map { ($0.id, $0) })
        var reordered: [TagDoStream] = []
        for id in orderedIds {
            if let s = byId.removeValue(forKey: id) {
                reordered.append(s)
            }
        }
        for s in streams where byId[s.id] != nil {
            reordered.append(s)
        }
        guard reordered.map(\.id) != streams.map(\.id) else { return }
        applyReorderedStreams(reordered)
    }

    private func applyReorderedStreams(_ reordered: [TagDoStream]) {
        var updated = reordered
        let now = Date()
        for idx in updated.indices {
            updated[idx].orderIndex = idx
            if updated[idx].customTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                updated[idx].title = updated[idx].autoDetectedTitle
            } else if let custom = updated[idx].customTitle?.trimmingCharacters(in: .whitespacesAndNewlines) {
                updated[idx].title = custom
            }
            updated[idx].updatedAt = now
            dirtyStreamIds.insert(updated[idx].id)
        }
        streams = updated
        lastPushedStreamSignatures = [:]
        save()
        TagdosNotificationManager.shared.rescheduleIfAuthorized(streams: streams)
    }

    public func deleteStream(streamId: UUID) {
        guard streams.count > 1,
              let removeIdx = streams.firstIndex(where: { $0.id == streamId }) else { return }

        streams.remove(at: removeIdx)
        dirtyStreamIds.remove(streamId)
        for idx in 0..<streams.count {
            if streams[idx].orderIndex != idx {
                streams[idx].orderIndex = idx
                if streams[idx].customTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                    streams[idx].title = streams[idx].autoDetectedTitle
                }
                streams[idx].updatedAt = Date()
                dirtyStreamIds.insert(streams[idx].id)
            }
            if idx >= removeIdx {
                lastPushedStreamSignatures.removeValue(forKey: idx + 1)
            }
        }
        let newCount = streams.count
        lastPushedStreamSignatures = lastPushedStreamSignatures.filter { $0.key <= newCount }
        save()
        TagdosNotificationManager.shared.rescheduleIfAuthorized(streams: streams)

        if let userId = getEffectiveUserId() {
            lastLocalPushAt = Date()
            Task {
                let client = SupabaseService.shared.client
                _ = try? await client
                    .from("tagdos_streams")
                    .delete(returning: .minimal)
                    .eq("user_id", value: userId)
                    .gt("stream_number", value: newCount)
                    .execute()
            }
        }
    }

    public enum TagdosImportDestinationMode: String, CaseIterable, Sendable {
        case appendToStream
        case replaceStream
        case createNewStream
    }

    public enum TagdosTaskImportTarget: Equatable, Hashable, Sendable {
        case replaceStream(UUID)
        case appendToStream(UUID)
        case newStream(title: String)
    }

    public struct TagdosTaskImportItem: Sendable {
        public let dslOrTag: String
        public let memoLine: String?
        public let target: TagdosTaskImportTarget

        public init(dslOrTag: String, memoLine: String?, target: TagdosTaskImportTarget) {
            self.dslOrTag = dslOrTag
            self.memoLine = memoLine
            self.target = target
        }
    }

    @discardableResult
    public func importExternalTaskBatch(_ items: [TagdosTaskImportItem]) -> UUID? {
        guard !items.isEmpty else { return nil }

        var firstAffectedId: UUID? = nil

        // 1. Replace Stream targets (preserving first-seen stream order)
        var replaceOrder: [UUID] = []
        var replaceGroups: [UUID: [TagdosTaskImportItem]] = [:]
        for item in items {
            if case .replaceStream(let streamId) = item.target {
                if replaceGroups[streamId] == nil { replaceOrder.append(streamId) }
                replaceGroups[streamId, default: []].append(item)
            }
        }

        for streamId in replaceOrder {
            guard let group = replaceGroups[streamId],
                  let index = streams.firstIndex(where: { $0.id == streamId }) else { continue }
            let combinedDsl = Self.combineImportedDslChunks(group.map(\.dslOrTag))
            let combinedMemos = group.compactMap { $0.memoLine?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            let existing = streams[index]
            var updated = TagdosParser.shared.parseStream(
                rawText: combinedDsl,
                title: existing.customTitle ?? existing.title,
                id: existing.id,
                streamReminder: existing.streamReminder,
                orderIndex: existing.orderIndex,
                existingStream: nil
            )
            updated.customTitle = existing.customTitle
            if let custom = existing.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
                updated.title = custom
            } else {
                updated.title = updated.autoDetectedTitle
            }
            updated.activeMemos = combinedMemos
            updated.attachments = existing.attachments
            updated.updatedAt = Date()
            streams[index] = updated
            dirtyStreamIds.insert(updated.id)
            if firstAffectedId == nil { firstAffectedId = updated.id }
        }

        // 2. Append Stream targets
        var appendOrder: [UUID] = []
        var appendGroups: [UUID: [TagdosTaskImportItem]] = [:]
        for item in items {
            if case .appendToStream(let streamId) = item.target {
                if appendGroups[streamId] == nil { appendOrder.append(streamId) }
                appendGroups[streamId, default: []].append(item)
            }
        }

        for streamId in appendOrder {
            guard let group = appendGroups[streamId],
                  let index = streams.firstIndex(where: { $0.id == streamId }) else { continue }
            let combinedDsl = Self.combineImportedDslChunks(group.map(\.dslOrTag))
            let combinedMemos = group.compactMap { $0.memoLine?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            let existing = streams[index]
            let existingRaw = existing.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            let newRaw: String
            if existingRaw.isEmpty {
                newRaw = combinedDsl
            } else if combinedDsl.isEmpty {
                newRaw = existingRaw
            } else {
                newRaw = "\(existingRaw) & \(combinedDsl)"
            }
            let existingMemos = existing.activeMemos.trimmingCharacters(in: .whitespacesAndNewlines)
            let mergedMemos: String
            if existingMemos.isEmpty {
                mergedMemos = combinedMemos
            } else if combinedMemos.isEmpty {
                mergedMemos = existingMemos
            } else {
                mergedMemos = "\(existingMemos)\n\(combinedMemos)"
            }
            var updated = TagdosParser.shared.parseStream(
                rawText: newRaw,
                title: existing.customTitle ?? existing.title,
                id: existing.id,
                streamReminder: existing.streamReminder,
                orderIndex: existing.orderIndex,
                existingStream: existing
            )
            updated.customTitle = existing.customTitle
            if let custom = existing.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
                updated.title = custom
            } else {
                updated.title = updated.autoDetectedTitle
            }
            updated.activeMemos = mergedMemos
            updated.attachments = existing.attachments
            updated.updatedAt = Date()
            streams[index] = updated
            dirtyStreamIds.insert(updated.id)
            if firstAffectedId == nil { firstAffectedId = updated.id }
        }

        // 3. New Stream targets (named entries grouped by exact title; blank titles become separate streams)
        var namedOrder: [String] = []
        var namedGroups: [String: [TagdosTaskImportItem]] = [:]
        var unnamedItems: [TagdosTaskImportItem] = []

        for item in items {
            if case .newStream(let rawTitle) = item.target {
                let clean = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if clean.isEmpty {
                    unnamedItems.append(item)
                } else {
                    if namedGroups[clean] == nil { namedOrder.append(clean) }
                    namedGroups[clean, default: []].append(item)
                }
            }
        }

        for titleKey in namedOrder {
            guard let group = namedGroups[titleKey] else { continue }
            let combinedDsl = Self.combineImportedDslChunks(group.map(\.dslOrTag))
            let combinedMemos = group.compactMap { $0.memoLine?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            let nextIdx = (streams.map { $0.orderIndex }.max() ?? -1) + 1
            let created = buildNewStream(title: titleKey, rawText: combinedDsl, activeMemos: combinedMemos, orderIndex: nextIdx)
            streams.append(created)
            dirtyStreamIds.insert(created.id)
            if firstAffectedId == nil { firstAffectedId = created.id }
        }

        for item in unnamedItems {
            let combinedDsl = Self.combineImportedDslChunks([item.dslOrTag])
            let memo = item.memoLine?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let nextIdx = (streams.map { $0.orderIndex }.max() ?? -1) + 1
            let created = buildNewStream(title: nil, rawText: combinedDsl, activeMemos: memo, orderIndex: nextIdx)
            streams.append(created)
            dirtyStreamIds.insert(created.id)
            if firstAffectedId == nil { firstAffectedId = created.id }
        }

        save()
        return firstAffectedId
    }

    @discardableResult
    public func importExternalTasks(
        mode: TagdosImportDestinationMode,
        targetStreamId: UUID?,
        newStreamTitle: String?,
        rawDslChunks: [String],
        memoLines: [String]
    ) -> TagDoStream {
        let combinedDsl = Self.combineImportedDslChunks(rawDslChunks)
        let combinedMemos = memoLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        let target: TagdosTaskImportTarget
        switch mode {
        case .createNewStream:
            target = .newStream(title: newStreamTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        case .replaceStream:
            if let targetId = targetStreamId, streams.contains(where: { $0.id == targetId }) {
                target = .replaceStream(targetId)
            } else {
                target = .newStream(title: newStreamTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            }
        case .appendToStream:
            if let targetId = targetStreamId, streams.contains(where: { $0.id == targetId }) {
                target = .appendToStream(targetId)
            } else {
                target = .newStream(title: newStreamTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            }
        }

        let affectedId = importExternalTaskBatch([
            TagdosTaskImportItem(dslOrTag: combinedDsl, memoLine: combinedMemos.isEmpty ? nil : combinedMemos, target: target)
        ])
        if let affectedId, let found = streams.first(where: { $0.id == affectedId }) {
            return found
        }
        return streams.last ?? createStream(title: newStreamTitle, rawText: combinedDsl, activeMemos: combinedMemos)
    }

    private static func combineImportedDslChunks(_ chunks: [String]) -> String {
        let cleaned = chunks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return "" }

        var singleTags: [String] = []
        var complexClusters: [String] = []

        for chunk in cleaned {
            if chunk.contains("&") || chunk.contains("/") {
                complexClusters.append(chunk)
            } else {
                singleTags.append(chunk)
            }
        }

        var parts: [String] = []
        if !singleTags.isEmpty {
            parts.append(singleTags.joined(separator: "/"))
        }
        parts.append(contentsOf: complexClusters)
        return parts.joined(separator: " & ")
    }

    // MARK: - Per-Stream Attachment Operations

    public func addAttachment(
        streamId: UUID,
        data: Data,
        fileName: String,
        mimeType: String
    ) async throws {
        guard let index = streams.firstIndex(where: { $0.id == streamId }) else { return }
        let streamNumber = streams[index].orderIndex + 1

        let attachment = TagDoAttachment(
            streamNumber: streamNumber,
            fileName: fileName,
            fileType: mimeType,
            fileSizeBytes: Int64(data.count)
        )

        // 1. Save to local disk cache immediately
        _ = try TagdosAttachmentManager.shared.saveLocalData(data, for: attachment)

        // 2. Add to stream in memory and save locally
        streams[index].attachments.append(attachment)
        streams[index].updatedAt = Date()
        dirtyStreamIds.insert(streamId)
        save()

        // 3. Upload to Supabase Storage in background if authenticated
        if let userId = getEffectiveUserId() {
            Task {
                do {
                    let remotePath = try await TagdosAttachmentManager.shared.uploadAttachment(
                        attachment,
                        data: data,
                        userId: userId
                    )
                    await MainActor.run {
                        if let sIdx = self.streams.firstIndex(where: { $0.id == streamId }),
                           let aIdx = self.streams[sIdx].attachments.firstIndex(where: { $0.id == attachment.id }) {
                            self.streams[sIdx].attachments[aIdx].remotePath = remotePath
                            self.dirtyStreamIds.insert(streamId)
                            self.save()
                        }
                    }
                } catch {
                    print("[TagdosStore] Attachment upload warning: \(error.localizedDescription)")
                }
            }
        }
    }

    public func downloadAttachment(_ attachment: TagDoAttachment) async throws -> URL {
        let localURL = try await TagdosAttachmentManager.shared.downloadAttachment(attachment)
        objectWillChange.send()
        return localURL
    }

    public func deleteAttachment(streamId: UUID, attachmentId: UUID) async {
        guard let sIdx = streams.firstIndex(where: { $0.id == streamId }),
              let aIdx = streams[sIdx].attachments.firstIndex(where: { $0.id == attachmentId }) else { return }
        
        let attachment = streams[sIdx].attachments[aIdx]
        streams[sIdx].attachments.remove(at: aIdx)
        streams[sIdx].updatedAt = Date()
        dirtyStreamIds.insert(streamId)
        save()

        await TagdosAttachmentManager.shared.deleteAttachment(attachment)
    }

    // MARK: - Quick Notes Mutations

    @discardableResult
    public func createQuickNote(title: String = "", content: String = "", tags: [String] = []) -> TagDoQuickNote {
        let note = TagDoQuickNote(
            userId: getEffectiveUserId(),
            title: title,
            content: content,
            tags: tags
        )
        quickNotes.insert(note, at: 0)
        save()
        return note
    }

    public func updateQuickNote(id: UUID, title: String, content: String) {
        guard let index = quickNotes.firstIndex(where: { $0.id == id }) else { return }
        quickNotes[index].title = title
        quickNotes[index].content = content
        quickNotes[index].updatedAt = Date()
        save()
    }

    public func togglePinQuickNote(id: UUID) {
        guard let index = quickNotes.firstIndex(where: { $0.id == id }) else { return }
        quickNotes[index].isPinned.toggle()
        quickNotes[index].updatedAt = Date()
        // Sort pinned first
        quickNotes.sort {
            if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
            return $0.updatedAt > $1.updatedAt
        }
        save()
    }

    public func deleteQuickNote(id: UUID) {
        quickNotes.removeAll { $0.id == id }
        lastPushedNoteSignatures.removeValue(forKey: id)
        save(triggerCloudSync: false)
        
        // Also delete from Supabase if authenticated
        if let userId = getEffectiveUserId() {
            lastLocalPushAt = Date()
            Task {
                let client = SupabaseService.shared.client
                _ = try? await client
                    .from("tagdos_quick_notes")
                    .delete(returning: .minimal)
                    .eq("id", value: id.uuidString.lowercased())
                    .eq("user_id", value: userId)
                    .execute()
            }
        }
    }

    // MARK: - Supabase Cloud Synchronization

    private func getEffectiveUserId() -> String? {
        if let currentId = AuthService.shared.currentUser?.id, currentId != "guest" {
            return currentId.lowercased()
        }
        if let storedId = GroupDefaults.shared.userDefaults.string(forKey: "supabase_user_id"), storedId != "guest" {
            return storedId.lowercased()
        }
        return nil
    }

    private func getEffectiveUserIdAsync() async -> String? {
        if let id = getEffectiveUserId() {
            return id
        }
        if let session = try? await SupabaseService.shared.client.auth.session {
            let uid = session.user.id.uuidString.lowercased()
            if uid != "guest" { return uid }
        }
        return nil
    }

    public func syncWithSupabase() async {
        guard let userId = await getEffectiveUserIdAsync() else {
            print("[TagdosStore] No authenticated user session, staying offline.")
            return
        }

        isSyncing = true
        cloudSyncError = nil
        defer { isSyncing = false }

        let client = SupabaseService.shared.client

        // 1. Pull & Merge Streams
        do {
            let res = try await client
                .from("tagdos_streams")
                .select()
                .eq("user_id", value: userId)
                .execute()

            struct RemoteStreamDTO: Codable {
                let id: UUID
                let user_id: UUID
                let stream_number: Int
                let title: String
                let raw_syntax: String
                let reminder_time: String?
                let active_memos: String?
                let attachments: [TagDoAttachment]?
                let updated_at: Date
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let remoteStreams = try decoder.decode([RemoteStreamDTO].self, from: res.data)

            if !remoteStreams.isEmpty {
                var merged = self.streams
                let parser = TagdosParser.shared
                let remoteNumbers = Set(remoteStreams.map { $0.stream_number })
                let maxRemoteNum = remoteStreams.map { $0.stream_number }.max() ?? 0

                // Prune only clean, previously pushed overflow streams removed remotely; never drop dirty/unpushed streams
                merged.removeAll { local in
                    let streamNum = local.orderIndex + 1
                    guard streamNum > maxRemoteNum else { return false }
                    guard !self.dirtyStreamIds.contains(local.id) else { return false }
                    let sig = self.streamSignature(local)
                    return self.lastPushedStreamSignatures[streamNum] == sig
                }

                for remote in remoteStreams {
                    let orderIdx = max(0, remote.stream_number - 1)
                    let decodedSpec = Self.decodeReminderSpec(remote.reminder_time)
                    let reminderDate = decodedSpec.streamReminder

                    if let localIdx = merged.firstIndex(where: { $0.orderIndex == orderIdx }) {
                        let local = merged[localIdx]
                        if self.dirtyStreamIds.contains(local.id) && local.updatedAt >= remote.updated_at {
                            continue
                        }
                        if remote.updated_at >= local.updatedAt {
                            var updated = parser.parseStream(
                                rawText: remote.raw_syntax,
                                title: remote.title,
                                id: local.id,
                                streamReminder: reminderDate,
                                orderIndex: orderIdx,
                                existingStream: local
                            )
                            for cIdx in updated.clusters.indices {
                                updated.clusters[cIdx].reminderDate = decodedSpec.clusterReminders[cIdx]
                            }
                            let trimmedRemoteTitle = remote.title.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmedRemoteTitle.isEmpty && trimmedRemoteTitle != updated.autoDetectedTitle {
                                updated.customTitle = trimmedRemoteTitle
                                updated.title = trimmedRemoteTitle
                            } else {
                                updated.customTitle = nil
                                updated.title = updated.autoDetectedTitle
                            }
                            updated.activeMemos = remote.active_memos ?? ""
                            updated.attachments = remote.attachments ?? []
                            updated.updatedAt = remote.updated_at
                            merged[localIdx] = updated
                            self.dirtyStreamIds.remove(local.id)
                        }
                    } else {
                        var newStream = parser.parseStream(
                            rawText: remote.raw_syntax,
                            title: remote.title,
                            streamReminder: reminderDate,
                            orderIndex: orderIdx
                        )
                        for cIdx in newStream.clusters.indices {
                            newStream.clusters[cIdx].reminderDate = decodedSpec.clusterReminders[cIdx]
                        }
                        let trimmedRemoteTitle = remote.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmedRemoteTitle.isEmpty && trimmedRemoteTitle != newStream.autoDetectedTitle {
                            newStream.customTitle = trimmedRemoteTitle
                            newStream.title = trimmedRemoteTitle
                        }
                        newStream.activeMemos = remote.active_memos ?? ""
                        newStream.attachments = remote.attachments ?? []
                        newStream.updatedAt = remote.updated_at
                        merged.append(newStream)
                    }
                }

                merged.sort { $0.orderIndex < $1.orderIndex }
                self.streams = merged
                TagdosNotificationManager.shared.rescheduleIfAuthorized(streams: merged)
                self.lastPushedStreamSignatures = [:]
                var hasDirtyOrMissing = false
                for s in merged {
                    let streamNum = s.orderIndex + 1
                    if self.dirtyStreamIds.contains(s.id) || !remoteNumbers.contains(streamNum) {
                        hasDirtyOrMissing = true
                    } else {
                        self.lastPushedStreamSignatures[streamNum] = self.streamSignature(s)
                    }
                }
                self.save(triggerCloudSync: false)

                if hasDirtyOrMissing {
                    let missingNumbers = Set(merged.map { $0.orderIndex + 1 }).subtracting(remoteNumbers)
                    await pushAllStreamsToSupabase(userId: userId, forceMissingNumbers: missingNumbers)
                }
            } else {
                // Remote has no streams yet: push local initial streams up!
                await pushAllStreamsToSupabase(userId: userId, forceAll: true)
            }
        } catch {
            print("[TagdosStore] Supabase streams sync notice: \(error.localizedDescription)")
            self.cloudSyncError = error.localizedDescription
        }

        // 2. Pull & Merge Quick Notes
        do {
            let resNotes = try await client
                .from("tagdos_quick_notes")
                .select()
                .eq("user_id", value: userId)
                .order("updated_at", ascending: false)
                .execute()

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let remoteNotes = try decoder.decode([TagDoQuickNote].self, from: resNotes.data)

            if !remoteNotes.isEmpty {
                var mergedNotes = self.quickNotes
                for rNote in remoteNotes {
                    if let idx = mergedNotes.firstIndex(where: { $0.id == rNote.id }) {
                        if rNote.updatedAt >= mergedNotes[idx].updatedAt {
                            mergedNotes[idx] = rNote
                        }
                    } else {
                        mergedNotes.append(rNote)
                    }
                }
                mergedNotes.sort {
                    if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
                    return $0.updatedAt > $1.updatedAt
                }
                self.quickNotes = mergedNotes
                for n in mergedNotes {
                    self.lastPushedNoteSignatures[n.id] = self.noteSignature(n)
                }
                self.save(triggerCloudSync: false)
            }
        } catch {
            print("[TagdosStore] Supabase quick notes sync notice: \(error.localizedDescription)")
        }

        self.lastSyncedAt = Date()
    }

    private func streamSignature(_ stream: TagDoStream) -> String {
        let remSpec = Self.encodeReminderSpec(for: stream) ?? ""
        let doneMask = stream.allPills.map { $0.isCompleted ? "1" : "0" }.joined()
        return "\(stream.title)|\(stream.rawText)|\(doneMask)|\(stream.activeMemos)|\(remSpec)|\(stream.attachments.count)"
    }

    public static func encodeReminderSpec(for stream: TagDoStream) -> String? {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let streamPart = stream.streamReminder.map { formatter.string(from: $0) } ?? ""
        var clusterParts: [String] = []
        for (idx, cluster) in stream.clusters.enumerated() {
            if let cDate = cluster.reminderDate {
                clusterParts.append("\(idx)=\(formatter.string(from: cDate))")
            }
        }

        if streamPart.isEmpty && clusterParts.isEmpty {
            return nil
        }
        if clusterParts.isEmpty {
            return streamPart
        }
        return "\(streamPart)|\(clusterParts.joined(separator: ","))"
    }

    public static func decodeReminderSpec(_ raw: String?) -> (streamReminder: Date?, clusterReminders: [Int: Date]) {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return (nil, [:])
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let sections = raw.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let streamToken = String(sections[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        let streamDate = streamToken.isEmpty ? nil : formatter.date(from: streamToken)

        var clusterMap: [Int: Date] = [:]
        if sections.count > 1 {
            let pairs = String(sections[1]).split(separator: ",")
            for pair in pairs {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2,
                   let idx = Int(kv[0].trimmingCharacters(in: .whitespacesAndNewlines)),
                   let date = formatter.date(from: String(kv[1]).trimmingCharacters(in: .whitespacesAndNewlines)) {
                    clusterMap[idx] = date
                }
            }
        }
        return (streamDate, clusterMap)
    }

    private func noteSignature(_ note: TagDoQuickNote) -> String {
        "\(note.title)|\(note.content)|\(note.isPinned)|\(note.tags.joined(separator: ","))"
    }

    private func scheduleCloudPush() {
        pushDebounceTask?.cancel()
        pushDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms debounce
            guard !Task.isCancelled else { return }
            guard let userId = await getEffectiveUserIdAsync() else { return }
            await pushAllStreamsToSupabase(userId: userId)
            await pushAllQuickNotesToSupabase(userId: userId)
        }
    }

    private func pushAllStreamsToSupabase(
        userId: String,
        forceAll: Bool = false,
        forceMissingNumbers: Set<Int> = []
    ) async {
        let client = SupabaseService.shared.client

        struct StreamPayload: Codable {
            let user_id: String
            let stream_number: Int
            let title: String
            let raw_syntax: String
            let reminder_time: String?
            let active_memos: String
            let attachments: [TagDoAttachment]
            let updated_at: String
        }

        let isoFormatter = ISO8601DateFormatter()

        var pushedAny = false
        for stream in streams {
            let streamNum = stream.orderIndex + 1
            let sig = streamSignature(stream)
            let isDirty = dirtyStreamIds.contains(stream.id)
            let isMissingRemote = forceMissingNumbers.contains(streamNum)
            if !forceAll && !isDirty && !isMissingRemote && lastPushedStreamSignatures[streamNum] == sig {
                continue
            }

            let reminderStr = Self.encodeReminderSpec(for: stream)
            let payload = StreamPayload(
                user_id: userId,
                stream_number: streamNum,
                title: stream.displayTitle,
                raw_syntax: stream.rawText,
                reminder_time: reminderStr,
                active_memos: stream.activeMemos,
                attachments: stream.attachments,
                updated_at: isoFormatter.string(from: stream.updatedAt)
            )

            do {
                self.lastLocalPushAt = Date()
                _ = try await client
                    .from("tagdos_streams")
                    .upsert(payload, onConflict: "user_id,stream_number", returning: .minimal)
                    .execute()
                lastPushedStreamSignatures[streamNum] = sig
                if let current = streams.first(where: { $0.id == stream.id }),
                   streamSignature(current) == sig {
                    dirtyStreamIds.remove(stream.id)
                    pushedAny = true
                }
                self.lastLocalPushAt = Date()
            } catch {
                print("[TagdosStore] Failed to upsert stream \(streamNum): \(error.localizedDescription)")
            }
        }
        if pushedAny {
            persistDirtyStreamIds()
        }
    }

    private func pushAllQuickNotesToSupabase(userId: String, forceAll: Bool = false) async {
        let client = SupabaseService.shared.client
        for note in quickNotes {
            let sig = noteSignature(note)
            if !forceAll, lastPushedNoteSignatures[note.id] == sig {
                continue
            }
            var n = note
            n.userId = userId
            do {
                self.lastLocalPushAt = Date()
                _ = try await client
                    .from("tagdos_quick_notes")
                    .upsert(n, returning: .minimal)
                    .execute()
                lastPushedNoteSignatures[note.id] = sig
                self.lastLocalPushAt = Date()
            } catch {
                print("[TagdosStore] Failed to upsert quick note: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Supabase Realtime Subscription

    private func scheduleRealtimeSync() {
        // Ignore self-echo events arriving right after our own cloud push
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
        guard let userId = await getEffectiveUserIdAsync() else { return }
        if realtimeChannel != nil { return }
        
        let client = SupabaseService.shared.client
        let channelName = "daily_tagdos_\(userId)"
        let channel = client.channel(channelName)

        let streamUpdates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "tagdos_streams",
            filter: "user_id=eq.\(userId)"
        )

        let streamInserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "tagdos_streams",
            filter: "user_id=eq.\(userId)"
        )

        do {
            try await channel.subscribeWithError()
            self.realtimeChannel = channel

            Task { [weak self] in
                for await _ in streamUpdates {
                    self?.scheduleRealtimeSync()
                }
            }

            Task { [weak self] in
                for await _ in streamInserts {
                    self?.scheduleRealtimeSync()
                }
            }
        } catch {
            print("[TagdosStore] Realtime subscription notice: \(error.localizedDescription)")
        }
    }

    // MARK: - Widget Synchronization

    public func syncWithWidgets() {
        let snapshot = Self.buildWidgetSnapshot(from: streams)
        WidgetDataCoordinator.shared.updateTagdosSnapshot(snapshot)
    }

    public nonisolated static func buildWidgetSnapshot(from streams: [TagDoStream]) -> TagdosWidgetSnapshot {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        let snapshotStreams = streams.map { stream in
            let driving = stream.drivingPill
            let earliestClusterRem = stream.clusters.compactMap(\.reminderDate).sorted().first
            let effectiveRem = stream.streamReminder ?? earliestClusterRem
            let reminderStr = effectiveRem.map { formatter.string(from: $0) }

            let snapshotPills = stream.allPills.prefix(10).map { pill in
                TagdosWidgetSnapshotPill(
                    id: pill.id.uuidString,
                    text: pill.rawText,
                    typeRaw: pill.type.rawValue,
                    isCompleted: pill.isCompleted
                )
            }

            let memosPreview = stream.activeMemos.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : String(stream.activeMemos.prefix(60))

            return TagdosWidgetSnapshotStream(
                id: stream.id.uuidString,
                title: stream.displayTitle,
                drivingPillId: driving?.id.uuidString,
                drivingPillText: driving?.rawText,
                drivingPillType: driving?.type.rawValue,
                activePillsCount: stream.activePills.count,
                reminderTimeFormatted: reminderStr,
                pills: Array(snapshotPills),
                activeMemosPreview: memosPreview
            )
        }

        let totalActive = streams.reduce(0) { $0 + $1.activePills.count }

        var allReminderDates: [Date] = []
        for s in streams {
            if let sr = s.streamReminder { allReminderDates.append(sr) }
            allReminderDates.append(contentsOf: s.clusters.compactMap(\.reminderDate))
        }
        let nextReminderStr = allReminderDates.sorted().first.map { formatter.string(from: $0) }

        return TagdosWidgetSnapshot(
            streams: snapshotStreams,
            totalActivePills: totalActive,
            nextReminderFormatted: nextReminderStr,
            lastUpdated: Date()
        )
    }
}
