import SwiftUI
import WebKit
import AppKit
import DailyCore

/// Primary Assisted Web & Capture Studio Hub (`daily://prism`) for macOS.
public struct PrismMainView: View {
    public let isInPopOutWindow: Bool
    public let onNavigateBack: () -> Void
    public let onToggleFullResearchMode: (() -> Void)?
    public let isFullResearchModeExternal: Bool

    @StateObject private var engine = PrismWebEngineModel()
    @ObservedObject private var prismStore = PrismStore.shared
    @ObservedObject private var settingsService = SettingsService.shared

    @State private var omniboxText: String = ""
    @FocusState private var isOmniboxFocused: Bool

    @State private var isSideStudioVisible: Bool = false
    @State private var activeStudioTab: PrismStudioTab = .copilot

    @State private var isRegionCropMode: Bool = false
    @State private var cropDragStart: CGPoint? = nil
    @State private var cropDragCurrent: CGPoint? = nil

    @State private var showingAddPinSheet: Bool = false
    @State private var newPinTitle: String = ""
    @State private var newPinUrl: String = ""

    public init(
        isInPopOutWindow: Bool = false,
        defaultResearchSplit: Bool = false,
        isFullResearchModeExternal: Bool = false,
        onToggleFullResearchMode: (() -> Void)? = nil,
        onNavigateBack: @escaping () -> Void
    ) {
        self.isInPopOutWindow = isInPopOutWindow
        self.isFullResearchModeExternal = isFullResearchModeExternal
        self.onToggleFullResearchMode = onToggleFullResearchMode
        self.onNavigateBack = onNavigateBack
        self._isSideStudioVisible = State(initialValue: defaultResearchSplit || isFullResearchModeExternal)
    }

    public var body: some View {
        VStack(spacing: 0) {
            topNavigationChrome

            tabStripBar

            if engine.isLoading {
                ProgressView(value: max(0.08, min(1.0, engine.estimatedProgress)))
                    .progressViewStyle(.linear)
                    .tint(ThemeColors.accentCyan)
                    .frame(height: 2)
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
            }

            // Main Split Canvas: Live Web (65%) + Assisted Studio (35%) when Studio is active
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ZStack {
                        mainWebOrStartCanvas
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if isSideStudioVisible {
                        Rectangle()
                            .fill(Color.white.opacity(0.10))
                            .frame(width: 1)

                        PrismSideStudioPane(
                            activeStudioTab: $activeStudioTab,
                            engine: engine,
                            onOpenUrlInPrism: { url, title in
                                prismStore.requestOpenInPrism(url: url, title: title)
                            },
                            onClosePane: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                                    isSideStudioVisible = false
                                }
                            }
                        )
                        .frame(width: max(310, min(420, geo.size.width * 0.35)))
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = engine.toastMessage {
                Text(toast)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.82), in: Capsule())
                    .overlay(Capsule().strokeBorder(ThemeColors.accentCyan.opacity(0.45), lineWidth: 1))
                    .padding(.bottom, 22)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            prismStore.inspectClipboardForUrl()
            engine.syncWithActiveTab(prismStore.activeTab)
            omniboxText = prismStore.activeTab?.url ?? ""
            consumePendingNavigationIfNeeded()
            Task { @MainActor in
                await prismStore.syncWithSupabase()
            }
        }
        .onDisappear {
            engine.pauseBackgroundMedia()
        }
        .onChange(of: prismStore.activeTabId) { _, _ in
            engine.syncWithActiveTab(prismStore.activeTab)
            if !isOmniboxFocused {
                omniboxText = prismStore.activeTab?.url ?? ""
            }
        }
        .onChange(of: engine.currentURLString) { _, newUrl in
            if !isOmniboxFocused {
                omniboxText = newUrl
            }
        }
        .onChange(of: prismStore.pendingNavigationRequest) { _, _ in
            consumePendingNavigationIfNeeded()
        }
        .sheet(isPresented: Binding(
            get: { engine.oauthPopupWebView != nil },
            set: { if !$0 { engine.oauthPopupWebView = nil } }
        )) {
            oauthPopupModalSheet
        }
        .sheet(isPresented: $showingAddPinSheet) {
            addPinnedSiteSheet
        }
    }

    private func consumePendingNavigationIfNeeded() {
        guard let req = prismStore.pendingNavigationRequest else { return }
        prismStore.pendingNavigationRequest = nil
        engine.syncWithActiveTab(prismStore.activeTab)
        omniboxText = req.url
        if let autoAction = req.autoTriggerCoPilot {
            isSideStudioVisible = true
            activeStudioTab = .copilot
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                let ctx = await engine.extractPageContext()
                _ = await PrismCoPilotService.shared.runAction(
                    autoAction,
                    pageTitle: ctx.title,
                    pageUrl: req.url,
                    bodyText: ctx.bodyText,
                    apiKey: settingsService.settings.geminiApiKey
                )
            }
        }
    }

    // MARK: - Top Navigation Chrome & Smart Omnibox

    private var topNavigationChrome: some View {
        HStack(spacing: 8) {
            if isInPopOutWindow {
                Spacer().frame(width: 68) // Clearance for macOS traffic lights
            } else {
                Button(action: onNavigateBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Back to Workspace")
            }

            // Back / Forward / Reload Controls
            HStack(spacing: 4) {
                chromeIconButton(icon: "arrow.left", enabled: engine.canGoBack || engine.isReaderModeActive, help: "Back") {
                    engine.goBack()
                }
                chromeIconButton(icon: "arrow.right", enabled: engine.canGoForward, help: "Forward") {
                    engine.goForward()
                }
                chromeIconButton(
                    icon: engine.isLoading ? "xmark" : "arrow.clockwise",
                    enabled: !(prismStore.activeTab?.isStartPage ?? true),
                    help: engine.isLoading ? "Stop" : "Reload"
                ) {
                    engine.reloadOrStop()
                }
            }

            // Smart Omnibox
            smartOmniboxBar

            // Action Controls
            HStack(spacing: 6) {
                if !engine.currentURLString.isEmpty {
                    // Save Link to Vault
                    chromeIconButton(
                        icon: "bookmark.fill",
                        tint: prismStore.clips.contains(where: { $0.clipType == .link && $0.sourceUrl == engine.currentURLString }) ? ThemeColors.accentCyan : .white.opacity(0.85),
                        help: "Save Link to Prism Vault"
                    ) {
                        prismStore.saveLinkClip(
                            url: engine.currentURLString,
                            title: engine.pageTitle,
                            previewImageUrl: engine.ogImageUrl
                        )
                        engine.showToast("Saved Link to Prism Vault")
                    }

                    // 1-Tap Reader Mode
                    chromeIconButton(
                        icon: engine.isReaderModeActive ? "doc.richtext.fill" : "doc.text.magnifyingglass",
                        tint: engine.isReaderModeActive ? ThemeColors.accentCyan : .white.opacity(0.85),
                        help: "Toggle Distraction-Free Reader Mode"
                    ) {
                        engine.toggleReaderMode()
                    }

                    // Viewport Region Crop
                    chromeIconButton(
                        icon: "crop",
                        tint: isRegionCropMode ? Color(hex: "#10B981") : .white.opacity(0.85),
                        help: "Drag to Capture Visual Region / Chart"
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isRegionCropMode.toggle()
                            cropDragStart = nil
                            cropDragCurrent = nil
                        }
                    }
                }

                // Full Research Split Toggle (expands Prism across full window when inside Dual-Pane)
                if let onToggleFullResearchMode = onToggleFullResearchMode {
                    chromeIconButton(
                        icon: isFullResearchModeExternal ? "arrow.down.right.and.arrow.up.left" : "rectangle.split.2x1.fill",
                        tint: isFullResearchModeExternal ? ThemeColors.accentCyan : .white.opacity(0.85),
                        help: isFullResearchModeExternal ? "Restore Master Cockpit" : "Full Research Split (65% Web + 35% Studio)"
                    ) {
                        onToggleFullResearchMode()
                        if !isFullResearchModeExternal {
                            isSideStudioVisible = true
                        }
                    }
                }

                // Assisted Co-Pilot & Vault Studio Toggle
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        isSideStudioVisible.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .bold))
                        Text("Studio")
                            .font(.system(size: 12, weight: .semibold))
                        if !prismStore.clips.isEmpty {
                            Text("\(prismStore.clips.count)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.white.opacity(0.18), in: Capsule())
                        }
                    }
                    .foregroundColor(isSideStudioVisible ? .black : .white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(isSideStudioVisible ? ThemeColors.accentCyan : Color.white.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Toggle Co-Pilot & Vault Studio")

                if !isInPopOutWindow {
                    chromeIconButton(
                        icon: "macwindow.badge.plus",
                        help: "Pop Out Prism Window"
                    ) {
                        PrismWindowManager.shared.openPopOutWindow()
                    }
                }

                if !engine.currentURLString.isEmpty {
                    chromeIconButton(
                        icon: "arrow.up.forward.app",
                        help: "Open in Default System Browser"
                    ) {
                        engine.openInSystemBrowser()
                    }
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
        .padding(.horizontal, 16)
    }

    private var smartOmniboxBar: some View {
        HStack(spacing: 8) {
            // Search Engine Picker
            Menu {
                ForEach(PrismSearchEngine.allCases, id: \.self) { se in
                    Button {
                        settingsService.update { $0.prismSearchEngine = se }
                    } label: {
                        HStack {
                            Text(se.displayName)
                            if settingsService.settings.prismSearchEngine == se {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: settingsService.settings.prismSearchEngine.iconName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(ThemeColors.accentCyan)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Search Engine: \(settingsService.settings.prismSearchEngine.displayName)")

            // Prism Shield Toggle Badge
            Button {
                engine.toggleShieldForCurrentDomain()
            } label: {
                Image(systemName: engine.isShieldActiveForCurrentDomain ? "shield.lefthalf.filled.badge.checkmark" : "shield.slash")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(engine.isShieldActiveForCurrentDomain ? Color(hex: "#10B981") : ThemeColors.fgMutedDark)
            }
            .buttonStyle(.plain)
            .help(engine.isShieldActiveForCurrentDomain ? "Prism Ad/Tracker Shield Active (Click to pause for site)" : "Prism Shield Paused for Site")

            if prismStore.activeTab?.isPrivate == true {
                Text("PRIVATE")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(Color(hex: "#A855F7"))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(hex: "#A855F7").opacity(0.18), in: Capsule())
            }

            TextField("Search with \(settingsService.settings.prismSearchEngine.displayName) or enter URL...", text: $omniboxText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .focused($isOmniboxFocused)
                .onSubmit {
                    isOmniboxFocused = false
                    engine.loadOmniboxInput(omniboxText)
                }

            // Auto-Sniffed RSS / Substack "+ Subscribe in News" Badge
            if let rssUrl = engine.detectedRssUrl {
                let subscribed = prismStore.isFeedSubscribedInNews(feedUrl: rssUrl)
                Button {
                    if !subscribed {
                        prismStore.subscribeFeedInNews(
                            feedUrl: rssUrl,
                            title: engine.detectedRssTitle ?? engine.pageTitle,
                            siteUrl: engine.currentURLString
                        )
                        engine.showToast("Subscribed in News Hub!")
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: subscribed ? "checkmark.circle.fill" : "dot.radiowaves.up.forward")
                            .font(.system(size: 10.5, weight: .bold))
                        Text(subscribed ? "In News" : "+ News RSS")
                            .font(.system(size: 10.5, weight: .bold))
                    }
                    .foregroundColor(subscribed ? .white.opacity(0.65) : Color(hex: "#10B981"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(hex: "#10B981").opacity(subscribed ? 0.08 : 0.18), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            // Pin to Speed Dial Star
            if !engine.currentURLString.isEmpty {
                let pinned = prismStore.isPinned(url: engine.currentURLString)
                Button {
                    prismStore.togglePinSite(title: engine.pageTitle, url: engine.currentURLString)
                    engine.showToast(pinned ? "Removed from Speed Dial" : "Pinned to Speed Dial")
                } label: {
                    Image(systemName: pinned ? "pin.fill" : "pin")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(pinned ? Color(hex: "#FFD166") : .white.opacity(0.55))
                }
                .buttonStyle(.plain)
                .help(pinned ? "Unpin Site" : "Pin Site to Speed Dial")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.08), in: Capsule())
        .overlay(Capsule().strokeBorder(isOmniboxFocused ? ThemeColors.accentCyan.opacity(0.65) : Color.white.opacity(0.14), lineWidth: 1))
    }

    private func chromeIconButton(
        icon: String,
        enabled: Bool = true,
        tint: Color = .white.opacity(0.85),
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(enabled ? tint : .white.opacity(0.25))
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(0.07), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }

    // MARK: - Hibernating Tab Strip

    private var tabStripBar: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(prismStore.tabs) { tab in
                        let isActive = (prismStore.activeTabId == tab.id)
                        HStack(spacing: 6) {
                            Button {
                                prismStore.selectTab(tab.id)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: tab.isPrivate ? "eyeglasses" : (tab.isStartPage ? "sparkles" : "globe"))
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .foregroundColor(tab.isPrivate ? Color(hex: "#A855F7") : (isActive ? ThemeColors.accentCyan : ThemeColors.fgMutedDark))

                                    Text(tab.title.isEmpty ? "Tab" : tab.title)
                                        .font(.system(size: 11.5, weight: isActive ? .semibold : .medium))
                                        .foregroundColor(isActive ? .white : .white.opacity(0.68))
                                        .lineLimit(1)
                                        .frame(maxWidth: 140, alignment: .leading)

                                    if tab.isHibernated && !tab.isStartPage {
                                        Circle()
                                            .fill(Color.white.opacity(0.28))
                                            .frame(width: 5, height: 5)
                                            .help("Hibernated in background (0% CPU)")
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            if prismStore.tabs.count > 1 {
                                Button {
                                    prismStore.closeTab(tab.id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white.opacity(0.5))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            isActive
                            ? ThemeColors.accentBlue.opacity(0.24)
                            : Color.white.opacity(0.05),
                            in: Capsule()
                        )
                        .overlay(
                            Capsule().strokeBorder(
                                isActive ? ThemeColors.accentCyan.opacity(0.45) : Color.white.opacity(0.08),
                                lineWidth: 1
                            )
                        )
                    }
                }
            }

            Button {
                prismStore.openNewTab()
                omniboxText = ""
                isOmniboxFocused = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .help("New Tab")

            Button {
                prismStore.openNewTab(isPrivate: true)
                omniboxText = ""
                isOmniboxFocused = true
            } label: {
                Image(systemName: "eyeglasses")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "#A855F7"))
                    .frame(width: 24, height: 24)
                    .background(Color(hex: "#A855F7").opacity(0.15), in: Circle())
            }
            .buttonStyle(.plain)
            .help("New Ephemeral Private Tab (Zero Cache/History)")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    // MARK: - Start Page vs Live WebView + FloatingOverlays

    @ViewBuilder
    private var mainWebOrStartCanvas: some View {
        if prismStore.activeTab?.isStartPage ?? true {
            prismStartPageView
        } else if engine.isReaderModeActive {
            readerModeCanvas
        } else {
            GeometryReader { webGeo in
                ZStack(alignment: .topLeading) {
                    PrismHostedWebView(webView: engine.activeWebView)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Floating Liquid Glass Selection Pill
                    if let sel = engine.selectionState {
                        floatingSelectionPill(sel: sel, in: webGeo.size)
                    }

                    // Alt+Click Image Quick Save Pill
                    if let img = engine.imageCandidate {
                        quickImageSaveBanner(img)
                    }

                    // Interactive Viewport Region Crop Overlay
                    if isRegionCropMode {
                        regionCropOverlay(in: webGeo.size)
                    }
                }
            }
        }
    }

    private var prismStartPageView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                // Smart Clipboard Detected URL Banner
                if let candidate = prismStore.clipboardCandidateUrl {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.on.clipboard.fill")
                            .foregroundColor(ThemeColors.accentCyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Link detected on Clipboard")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                            Text(candidate)
                                .font(.system(size: 11))
                                .foregroundColor(ThemeColors.fgMutedDark)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("Open") {
                            let target = candidate
                            prismStore.dismissClipboardCandidate()
                            engine.loadOmniboxInput(target)
                        }
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(ThemeColors.accentCyan, in: Capsule())
                        .buttonStyle(.plain)

                        Button("Save Clip") {
                            let target = candidate
                            prismStore.dismissClipboardCandidate()
                            prismStore.saveLinkClip(url: target, title: PrismSearchEngine.extractCleanDomain(from: target))
                            engine.showToast("Saved Clipboard Link to Vault")
                        }
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.10), in: Capsule())
                        .buttonStyle(.plain)

                        Button {
                            prismStore.dismissClipboardCandidate()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(ThemeColors.fgMutedDark)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                    .background(ThemeColors.accentCyan.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(ThemeColors.accentCyan.opacity(0.30), lineWidth: 1))
                }

                // Speed Dial Pinned Sites
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Pinned Speed Dial", systemImage: "pin.fill")
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Spacer()
                        Button {
                            newPinTitle = ""
                            newPinUrl = ""
                            showingAddPinSheet = true
                        } label: {
                            Label("Add Site", systemImage: "plus")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(ThemeColors.accentCyan)
                        }
                        .buttonStyle(.plain)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
                        ForEach(prismStore.pinnedSites) { site in
                            Button {
                                engine.loadOmniboxInput(site.url)
                            } label: {
                                HStack(spacing: 10) {
                                    AsyncImage(url: URL(string: site.iconUrl ?? "")) { phase in
                                        if case .success(let image) = phase {
                                            image.resizable().scaledToFit().frame(width: 20, height: 20).clipShape(RoundedRectangle(cornerRadius: 5))
                                        } else {
                                            Image(systemName: "globe")
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundColor(ThemeColors.accentCyan)
                                                .frame(width: 20, height: 20)
                                        }
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(site.title)
                                            .font(.system(size: 12.5, weight: .semibold))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Text(site.domain)
                                            .font(.system(size: 10))
                                            .foregroundColor(ThemeColors.fgMutedDark)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(12)
                                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    prismStore.deletePinnedSite(site.id)
                                } label: {
                                    Label("Remove from Speed Dial", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                // Recent Clippings Preview
                if !prismStore.clips.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Recent Vault Clippings", systemImage: "tray.full.fill")
                                .font(.system(size: 13.5, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Spacer()
                            Button("Open Vault →") {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                                    activeStudioTab = .vault
                                    isSideStudioVisible = true
                                }
                            }
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(ThemeColors.accentCyan)
                            .buttonStyle(.plain)
                        }

                        ForEach(prismStore.clips.prefix(5)) { clip in
                            Button {
                                engine.loadOmniboxInput(clip.sourceUrl)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: clip.clipType.iconName)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(Color(hex: clip.clipType.accentHex))
                                        .frame(width: 30, height: 30)
                                        .background(Color(hex: clip.clipType.accentHex).opacity(0.15), in: Circle())

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(clip.title)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Text(clip.contentText.isEmpty ? clip.domain : clip.contentText)
                                            .font(.system(size: 11.5))
                                            .foregroundColor(ThemeColors.fgMutedDark)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text(clip.domain)
                                        .font(.system(size: 10.5, weight: .medium))
                                        .foregroundColor(ThemeColors.fgMutedDark)
                                }
                                .padding(12)
                                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private var readerModeCanvas: some View {
        ZStack {
            if engine.isExtractingReader {
                VStack(spacing: 12) {
                    ProgressView().tint(ThemeColors.accentCyan)
                    Text("Extracting Distraction-Free View...")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
            } else if let article = engine.extractedReaderArticle {
                ArticleWebView(article: article, isDark: true, fontSizeMultiplier: 1.0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func floatingSelectionPill(sel: PrismSelectionOverlayState, in size: CGSize) -> some View {
        let clampedX = max(140, min(size.width - 140, sel.centerX))
        let targetY = sel.topY > 54 ? (sel.topY - 26) : min(size.height - 36, sel.bottomY + 26)

        return HStack(spacing: 6) {
            Button {
                prismStore.saveQuoteClip(
                    quoteText: sel.text,
                    sourceUrl: engine.currentURLString,
                    pageTitle: engine.pageTitle
                )
                engine.selectionState = nil
                engine.showToast("Saved Quote to Vault")
            } label: {
                Label("Save Quote", systemImage: "text.quote")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(ThemeColors.accentCyan, in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                let clip = prismStore.saveQuoteClip(
                    quoteText: sel.text,
                    sourceUrl: engine.currentURLString,
                    pageTitle: engine.pageTitle
                )
                _ = prismStore.sendClipToTagdos(clip)
                engine.selectionState = nil
                engine.showToast("Sent Quote to TagDoS (#prism)")
            } label: {
                Label("→ TagDoS", systemImage: "checklist")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#FFB300"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.10), in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                let text = sel.text
                engine.selectionState = nil
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    activeStudioTab = .copilot
                    isSideStudioVisible = true
                }
                Task { @MainActor in
                    let ctx = await engine.extractPageContext()
                    let turn = await PrismCoPilotService.shared.runAction(
                        .explainSelection,
                        pageTitle: engine.pageTitle,
                        pageUrl: engine.currentURLString,
                        bodyText: ctx.bodyText,
                        selectedText: text,
                        apiKey: settingsService.settings.geminiApiKey
                    )
                    _ = prismStore.saveAISummaryClip(turn: turn)
                    engine.showToast("Explained & Saved in Studio")
                }
            } label: {
                Label("Explain", systemImage: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#A855F7"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.10), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(5)
        .background(Color(hex: "#0A1020").opacity(0.95), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.20), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.45), radius: 12, x: 0, y: 4)
        .position(x: clampedX, y: targetY)
    }

    private func quickImageSaveBanner(_ img: PrismImageCandidate) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "photo.badge.plus")
                .foregroundColor(Color(hex: "#10B981"))
            Text(img.alt.isEmpty ? "Save Image to Prism Vault?" : img.alt)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
            Button("Save Image") {
                let captured = img
                engine.imageCandidate = nil
                Task {
                    _ = await prismStore.saveImageClip(
                        rawImageData: nil,
                        remoteImageUrl: captured.src,
                        sourceUrl: engine.currentURLString,
                        title: captured.alt.isEmpty ? engine.pageTitle : captured.alt
                    )
                    engine.showToast("Image Compressed & Saved to Vault")
                }
            }
            .font(.system(size: 11.5, weight: .bold))
            .foregroundColor(.black)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(hex: "#10B981"), in: Capsule())
            .buttonStyle(.plain)

            Button {
                engine.imageCandidate = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(.white.opacity(0.65))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color(hex: "#0A1020").opacity(0.94), in: Capsule())
        .overlay(Capsule().strokeBorder(Color(hex: "#10B981").opacity(0.45), lineWidth: 1))
        .padding(14)
    }

    private func regionCropOverlay(in size: CGSize) -> some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.25)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { val in
                            if cropDragStart == nil {
                                cropDragStart = val.startLocation
                            }
                            cropDragCurrent = val.location
                        }
                        .onEnded { val in
                            guard let start = cropDragStart else { return }
                            let end = val.location
                            let rect = CGRect(
                                x: min(start.x, end.x),
                                y: min(start.y, end.y),
                                width: abs(end.x - start.x),
                                height: abs(end.y - start.y)
                            )
                            isRegionCropMode = false
                            cropDragStart = nil
                            cropDragCurrent = nil
                            guard rect.width > 16, rect.height > 16 else { return }
                            Task {
                                if let jpeg = await engine.captureViewportCrop(rectInView: rect, viewBounds: CGRect(origin: .zero, size: size)) {
                                    _ = await prismStore.saveImageClip(
                                        rawImageData: jpeg,
                                        sourceUrl: engine.currentURLString,
                                        title: "\(engine.pageTitle.isEmpty ? "Visual Crop" : engine.pageTitle) (Snapshot)",
                                        tags: ["snapshot"]
                                    )
                                    engine.showToast("Visual Region Saved to Vault")
                                }
                            }
                        }
                )

            if let start = cropDragStart, let cur = cropDragCurrent {
                let rect = CGRect(
                    x: min(start.x, cur.x),
                    y: min(start.y, cur.y),
                    width: abs(cur.x - start.x),
                    height: abs(cur.y - start.y)
                )
                Rectangle()
                    .fill(ThemeColors.accentCyan.opacity(0.14))
                    .overlay(Rectangle().strokeBorder(ThemeColors.accentCyan, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }

            HStack(spacing: 8) {
                Image(systemName: "crop")
                    .foregroundColor(ThemeColors.accentCyan)
                Text("Drag across any chart, diagram, or region to clip into Vault")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Button("Cancel") {
                    isRegionCropMode = false
                    cropDragStart = nil
                    cropDragCurrent = nil
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(ThemeColors.accentCyan)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.84), in: Capsule())
            .padding(.top, 12)
        }
    }

    private var oauthPopupModalSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Label(engine.oauthPopupTitle, systemImage: "lock.shield.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Button("Close") {
                    engine.oauthPopupWebView = nil
                }
                .foregroundColor(ThemeColors.accentCyan)
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color(hex: "#0D1324"))

            if let popup = engine.oauthPopupWebView {
                PrismHostedWebView(webView: popup)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 560, idealWidth: 640, minHeight: 620, idealHeight: 700)
    }

    private var addPinnedSiteSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pin Site to Speed Dial")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            TextField("Title (e.g. Cloudflare Docs)", text: $newPinTitle)
                .textFieldStyle(.roundedBorder)

            TextField("URL (e.g. developers.cloudflare.com)", text: $newPinUrl)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") { showingAddPinSheet = false }
                Spacer()
                Button("Pin Site") {
                    if let resolved = PrismSearchEngine.resolveOmniboxInput(newPinUrl) {
                        prismStore.togglePinSite(title: newPinTitle, url: resolved.absoluteString)
                    }
                    showingAddPinSheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(newPinUrl.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
        .background(Color(hex: "#121829"))
    }
}
