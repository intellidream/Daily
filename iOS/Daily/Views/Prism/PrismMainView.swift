import SwiftUI
import WebKit
import UIKit
import DailyCore

/// Adaptive Assisted Web & Capture Studio Hub (`daily://prism`) for iOS (iPhone & Foldable `SimulaDuo`).
public struct PrismMainView: View {
    public let isFullResearchModeExternal: Bool
    public let onToggleFullResearchMode: (() -> Void)?
    public let onNavigateBack: () -> Void

    @StateObject private var engine = PrismWebEngineModel()
    @ObservedObject private var prismStore = PrismStore.shared
    @ObservedObject private var settingsService = SettingsService.shared

    @State private var omniboxText: String = ""
    @FocusState private var isOmniboxFocused: Bool

    @State private var showingStudioSheet: Bool = false
    @State private var isWideSideStudioVisible: Bool = false
    @State private var activeStudioTab: PrismStudioTab = .copilot

    @State private var isRegionCropMode: Bool = false
    @State private var cropDragStart: CGPoint? = nil
    @State private var cropDragCurrent: CGPoint? = nil

    @State private var showingAddPinSheet: Bool = false
    @State private var newPinTitle: String = ""
    @State private var newPinUrl: String = ""

    public init(
        isFullResearchModeExternal: Bool = false,
        onToggleFullResearchMode: (() -> Void)? = nil,
        onNavigateBack: @escaping () -> Void
    ) {
        self.isFullResearchModeExternal = isFullResearchModeExternal
        self.onToggleFullResearchMode = onToggleFullResearchMode
        self.onNavigateBack = onNavigateBack
        self._isWideSideStudioVisible = State(initialValue: isFullResearchModeExternal)
    }

    public var body: some View {
        GeometryReader { rootGeo in
            let isWideLayout = rootGeo.size.width >= 680

            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    if isWideLayout {
                        wideTopHeaderBar
                    } else {
                        compactPhoneTopHeaderBar
                    }

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

                    // Main Content Area (Split 65% / 35% on Wide Foldable when Studio active, or Full Bleed on Phone)
                    HStack(spacing: 0) {
                        ZStack {
                            mainWebOrStartCanvas(isWideLayout: isWideLayout)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if isWideLayout && isWideSideStudioVisible {
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
                                        isWideSideStudioVisible = false
                                    }
                                }
                            )
                            .frame(width: max(300, min(400, rootGeo.size.width * 0.36)))
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                }

                // Ergonomic Bottom Thumb Liquid Glass Omnibox on Compact Phones
                if !isWideLayout {
                    compactBottomThumbOmnibox
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                }

                if let toast = engine.toastMessage {
                    Text(toast)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.86), in: Capsule())
                        .overlay(Capsule().strokeBorder(ThemeColors.accentCyan.opacity(0.45), lineWidth: 1))
                        .padding(.bottom, isWideLayout ? 24 : 74)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .onAppear {
            prismStore.consumePendingSharedItems()
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
        .sheet(isPresented: $showingStudioSheet) {
            PrismSideStudioPane(
                activeStudioTab: $activeStudioTab,
                engine: engine,
                onOpenUrlInPrism: { url, title in
                    prismStore.requestOpenInPrism(url: url, title: title)
                },
                onClosePane: {
                    showingStudioSheet = false
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: Binding(
            get: { engine.oauthPopupWebView != nil },
            set: { if !$0 { engine.oauthPopupWebView = nil } }
        )) {
            NavigationStack {
                Group {
                    if let popup = engine.oauthPopupWebView {
                        PrismHostedWebView(webView: popup)
                    }
                }
                .navigationTitle(engine.oauthPopupTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { engine.oauthPopupWebView = nil }
                    }
                }
            }
            .presentationDetents([.large])
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
    }

    // MARK: - Compact Phone Top Bar & Bottom Liquid Glass Omnibox

    private var compactPhoneTopHeaderBar: some View {
        HStack(spacing: 8) {
            Button(action: onNavigateBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)

            // Scrollable Tab Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(prismStore.tabs) { tab in
                        let isActive = (prismStore.activeTabId == tab.id)
                        HStack(spacing: 5) {
                            Button {
                                prismStore.selectTab(tab.id)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: tab.isPrivate ? "eyeglasses" : (tab.isStartPage ? "sparkles" : "globe"))
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(tab.isPrivate ? Color(hex: "#A855F7") : (isActive ? ThemeColors.accentCyan : ThemeColors.fgMutedDark))
                                    Text(tab.title.isEmpty ? "Tab" : tab.title)
                                        .font(.system(size: 11.5, weight: isActive ? .semibold : .medium))
                                        .foregroundColor(isActive ? .white : .white.opacity(0.68))
                                        .lineLimit(1)
                                        .frame(maxWidth: 96, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)

                            if prismStore.tabs.count > 1 && isActive {
                                Button {
                                    prismStore.closeTab(tab.id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white.opacity(0.55))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(isActive ? ThemeColors.accentBlue.opacity(0.26) : Color.white.opacity(0.05), in: Capsule())
                        .contextMenu {
                            Button {
                                prismStore.duplicateTab(tab.id)
                            } label: {
                                Label("Duplicate Tab", systemImage: "plus.square.on.square")
                            }

                            Button {
                                prismStore.openNewTab()
                            } label: {
                                Label("New Tab", systemImage: "plus")
                            }

                            Button {
                                prismStore.openNewTab(isPrivate: true)
                            } label: {
                                Label("New Private Tab", systemImage: "eyeglasses")
                            }

                            Divider()

                            if prismStore.tabs.count > 1 {
                                Button(role: .destructive) {
                                    prismStore.closeTab(tab.id)
                                } label: {
                                    Label("Close Tab", systemImage: "xmark")
                                }

                                Button(role: .destructive) {
                                    prismStore.closeOtherTabs(except: tab.id)
                                } label: {
                                    Label("Close Other Tabs", systemImage: "xmark.circle")
                                }
                            }
                        }
                    }
                }
            }

            // New Tab / Private Tab / Tools Menu
            Menu {
                Button {
                    prismStore.openNewTab()
                    omniboxText = ""
                    isOmniboxFocused = true
                } label: {
                    Label("New Tab", systemImage: "plus")
                }

                Button {
                    prismStore.openNewTab(isPrivate: true)
                    omniboxText = ""
                    isOmniboxFocused = true
                } label: {
                    Label("New Private Tab", systemImage: "eyeglasses")
                }

                if !engine.currentURLString.isEmpty {
                    Divider()

                    Button {
                        engine.toggleReaderMode()
                    } label: {
                        Label(engine.isReaderModeActive ? "Exit Reader Mode" : "Reader Mode", systemImage: "doc.text.magnifyingglass")
                    }

                    Button {
                        isRegionCropMode.toggle()
                    } label: {
                        Label("Capture Visual Region", systemImage: "crop")
                    }

                    Button {
                        prismStore.togglePinSite(title: engine.pageTitle, url: engine.currentURLString)
                    } label: {
                        Label(prismStore.isPinned(url: engine.currentURLString) ? "Unpin from Speed Dial" : "Pin to Speed Dial", systemImage: "pin")
                    }

                    Button {
                        engine.openInSystemBrowser()
                    } label: {
                        Label("Open in Safari", systemImage: "safari")
                    }
                }

                Divider()
                Menu("Search Engine (\(settingsService.settings.prismSearchEngine.displayName))") {
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
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white.opacity(0.88))
                    .frame(width: 34, height: 34)
            }

            if let rssUrl = engine.detectedRssUrl, !prismStore.isFeedSubscribedInNews(feedUrl: rssUrl) {
                Button {
                    prismStore.subscribeFeedInNews(
                        feedUrl: rssUrl,
                        title: engine.detectedRssTitle ?? engine.pageTitle,
                        siteUrl: engine.currentURLString
                    )
                    engine.showToast("Subscribed in News!")
                } label: {
                    Text("+RSS")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(Color(hex: "#10B981"))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(Color(hex: "#10B981").opacity(0.18), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var compactBottomThumbOmnibox: some View {
        if engine.isBottomOmniboxCollapsed && !isOmniboxFocused && !engine.currentURLString.isEmpty {
            // Auto-Collapsed Minimal Domain Capsule on Downward Scroll
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    engine.isBottomOmniboxCollapsed = false
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: engine.isShieldActiveForCurrentDomain ? "shield.lefthalf.filled" : "globe")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(ThemeColors.accentCyan)
                    Text(PrismSearchEngine.extractCleanDomain(from: engine.currentURLString))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color(hex: "#080E1C").opacity(0.88), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 8) {
                Button {
                    engine.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundColor((engine.canGoBack || engine.isReaderModeActive) ? .white : .white.opacity(0.28))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(!engine.canGoBack && !engine.isReaderModeActive)

                Button {
                    engine.toggleShieldForCurrentDomain()
                } label: {
                    Image(systemName: engine.isShieldActiveForCurrentDomain ? "shield.lefthalf.filled.badge.checkmark" : "shield.slash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(engine.isShieldActiveForCurrentDomain ? Color(hex: "#10B981") : ThemeColors.fgMutedDark)
                }
                .buttonStyle(.plain)

                TextField("Search or enter URL...", text: $omniboxText)
                    .font(.system(size: 13.5))
                    .foregroundColor(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.webSearch)
                    .submitLabel(.go)
                    .focused($isOmniboxFocused)
                    .onSubmit {
                        isOmniboxFocused = false
                        engine.loadOmniboxInput(omniboxText)
                    }

                if !engine.currentURLString.isEmpty && !isOmniboxFocused {
                    Button {
                        prismStore.saveLinkClip(
                            url: engine.currentURLString,
                            title: engine.pageTitle,
                            previewImageUrl: engine.ogImageUrl
                        )
                        engine.showToast("Saved Link to Vault")
                    } label: {
                        Image(systemName: prismStore.clips.contains(where: { $0.clipType == .link && $0.sourceUrl == engine.currentURLString }) ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundColor(ThemeColors.accentCyan)
                    }
                    .buttonStyle(.plain)

                    Button {
                        engine.reloadOrStop()
                    } label: {
                        Image(systemName: engine.isLoading ? "xmark" : "arrow.clockwise")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }

                // 1-Tap Studio Sheet Launcher (safeguarded against vertical stretching)
                Button {
                    isOmniboxFocused = false
                    showingStudioSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .bold))
                        if !prismStore.clips.isEmpty {
                            Text("\(prismStore.clips.count)")
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                .lineLimit(1)
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(ThemeColors.accentCyan, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(hex: "#070D1B").opacity(0.94), in: Capsule())
            .overlay(Capsule().strokeBorder(isOmniboxFocused ? ThemeColors.accentCyan.opacity(0.65) : Color.white.opacity(0.16), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.45), radius: 14, x: 0, y: 6)
        }
    }

    // MARK: - Unfolded Foldable / Tablet Top Bar (`SimulaDuo`)

    private var wideTopHeaderBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button(action: onNavigateBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)

                Button { engine.goBack() } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(engine.canGoBack ? .white : .white.opacity(0.28))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .disabled(!engine.canGoBack)

                Button { engine.reloadOrStop() } label: {
                    Image(systemName: engine.isLoading ? "xmark" : "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)

                // Omnibox
                HStack(spacing: 8) {
                    Button {
                        engine.toggleShieldForCurrentDomain()
                    } label: {
                        Image(systemName: engine.isShieldActiveForCurrentDomain ? "shield.lefthalf.filled.badge.checkmark" : "shield.slash")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(engine.isShieldActiveForCurrentDomain ? Color(hex: "#10B981") : ThemeColors.fgMutedDark)
                    }
                    .buttonStyle(.plain)

                    TextField("Search with \(settingsService.settings.prismSearchEngine.displayName) or enter URL...", text: $omniboxText)
                        .font(.system(size: 13.5))
                        .foregroundColor(.white)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.go)
                        .focused($isOmniboxFocused)
                        .onSubmit {
                            isOmniboxFocused = false
                            engine.loadOmniboxInput(omniboxText)
                        }

                    if let rssUrl = engine.detectedRssUrl, !prismStore.isFeedSubscribedInNews(feedUrl: rssUrl) {
                        Button {
                            prismStore.subscribeFeedInNews(
                                feedUrl: rssUrl,
                                title: engine.detectedRssTitle ?? engine.pageTitle,
                                siteUrl: engine.currentURLString
                            )
                            engine.showToast("Subscribed in News!")
                        } label: {
                            Text("+ News RSS")
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundColor(Color(hex: "#10B981"))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(hex: "#10B981").opacity(0.18), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.08), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))

                if !engine.currentURLString.isEmpty {
                    Button {
                        prismStore.saveLinkClip(url: engine.currentURLString, title: engine.pageTitle, previewImageUrl: engine.ogImageUrl)
                        engine.showToast("Saved Link to Vault")
                    } label: {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(ThemeColors.accentCyan)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        engine.toggleReaderMode()
                    } label: {
                        Image(systemName: engine.isReaderModeActive ? "doc.richtext.fill" : "doc.text.magnifyingglass")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(engine.isReaderModeActive ? ThemeColors.accentCyan : .white)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        isRegionCropMode.toggle()
                    } label: {
                        Image(systemName: "crop")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(isRegionCropMode ? Color(hex: "#10B981") : .white)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                if let onToggleFullResearchMode = onToggleFullResearchMode {
                    Button {
                        onToggleFullResearchMode()
                        if !isFullResearchModeExternal {
                            isWideSideStudioVisible = true
                        }
                    } label: {
                        Image(systemName: isFullResearchModeExternal ? "arrow.down.right.and.arrow.up.left" : "rectangle.split.2x1.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(isFullResearchModeExternal ? ThemeColors.accentCyan : .white)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        isWideSideStudioVisible.toggle()
                    }
                } label: {
                    ViewThatFits(in: .horizontal) {
                        // Full width: Icon + "Studio" + badge
                        HStack(spacing: 5) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12, weight: .bold))
                            Text("Studio")
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                            if !prismStore.clips.isEmpty {
                                Text("\(prismStore.clips.count)")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .lineLimit(1)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.white.opacity(0.18), in: Capsule())
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)

                        // Compact fallback: Icon + badge only, omitting "Studio" text to prevent 2-line expansion
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12, weight: .bold))
                            if !prismStore.clips.isEmpty {
                                Text("\(prismStore.clips.count)")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .lineLimit(1)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.white.opacity(0.18), in: Capsule())
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .foregroundColor(isWideSideStudioVisible ? .black : .white)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(isWideSideStudioVisible ? ThemeColors.accentCyan : Color.white.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            // Wide Tab Strip
            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(prismStore.tabs) { tab in
                            let isActive = (prismStore.activeTabId == tab.id)
                            HStack(spacing: 5) {
                                Button {
                                    prismStore.selectTab(tab.id)
                                } label: {
                                    Text(tab.title.isEmpty ? "Tab" : tab.title)
                                        .font(.system(size: 11.5, weight: isActive ? .semibold : .medium))
                                        .foregroundColor(isActive ? .white : .white.opacity(0.68))
                                        .lineLimit(1)
                                        .frame(maxWidth: 130)
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
                            .background(isActive ? ThemeColors.accentBlue.opacity(0.24) : Color.white.opacity(0.05), in: Capsule())
                            .contextMenu {
                                Button {
                                    prismStore.duplicateTab(tab.id)
                                } label: {
                                    Label("Duplicate Tab", systemImage: "plus.square.on.square")
                                }

                                Button {
                                    prismStore.openNewTab()
                                } label: {
                                    Label("New Tab", systemImage: "plus")
                                }

                                Button {
                                    prismStore.openNewTab(isPrivate: true)
                                } label: {
                                    Label("New Private Tab", systemImage: "eyeglasses")
                                }

                                Divider()

                                if prismStore.tabs.count > 1 {
                                    Button(role: .destructive) {
                                        prismStore.closeTab(tab.id)
                                    } label: {
                                        Label("Close Tab", systemImage: "xmark")
                                    }

                                    Button(role: .destructive) {
                                        prismStore.closeOtherTabs(except: tab.id)
                                    } label: {
                                        Label("Close Other Tabs", systemImage: "xmark.circle")
                                    }
                                }
                            }
                        }
                    }
                }

                Button {
                    prismStore.openNewTab()
                    omniboxText = ""
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)

                Button {
                    prismStore.openNewTab(isPrivate: true)
                    omniboxText = ""
                } label: {
                    Image(systemName: "eyeglasses")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: "#A855F7"))
                        .frame(width: 24, height: 24)
                        .background(Color(hex: "#A855F7").opacity(0.15), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
        }
    }

    // MARK: - Main Canvas & Floating Overlays

    @ViewBuilder
    private func mainWebOrStartCanvas(isWideLayout: Bool) -> some View {
        if prismStore.activeTab?.isStartPage ?? true {
            prismStartPageView(isWideLayout: isWideLayout)
        } else if engine.isReaderModeActive {
            ZStack {
                if engine.isExtractingReader {
                    VStack(spacing: 12) {
                        ProgressView().tint(ThemeColors.accentCyan)
                        Text("Extracting Distraction-Free View...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                } else if let article = engine.extractedReaderArticle {
                    ArticleWebView(article: article, isDark: true, fontSizeMultiplier: 1.0)
                }
            }
        } else {
            GeometryReader { webGeo in
                ZStack(alignment: .topLeading) {
                    PrismHostedWebView(webView: engine.activeWebView)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if let sel = engine.selectionState {
                        floatingSelectionPill(sel: sel, in: webGeo.size, isWideLayout: isWideLayout)
                    }

                    if let img = engine.imageCandidate {
                        quickImageSaveBanner(img)
                    }

                    if isRegionCropMode {
                        regionCropOverlay(in: webGeo.size)
                    }
                }
            }
        }
    }

    private func prismStartPageView(isWideLayout: Bool) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                if let candidate = prismStore.clipboardCandidateUrl {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.on.clipboard.fill")
                            .foregroundColor(ThemeColors.accentCyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Copied Link Detected")
                                .font(.system(size: 12.5, weight: .bold))
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
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(ThemeColors.accentCyan, in: Capsule())
                        .buttonStyle(.plain)

                        Button("Clip") {
                            let target = candidate
                            prismStore.dismissClipboardCandidate()
                            prismStore.saveLinkClip(url: target, title: PrismSearchEngine.extractCleanDomain(from: target))
                            engine.showToast("Saved Clipboard Link")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
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

                // Speed Dial
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Pinned Speed Dial", systemImage: "pin.fill")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Spacer()
                        Button {
                            newPinTitle = ""
                            newPinUrl = ""
                            showingAddPinSheet = true
                        } label: {
                            Label("Add", systemImage: "plus")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(ThemeColors.accentCyan)
                        }
                        .buttonStyle(.plain)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 10)], spacing: 10) {
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
                                            .font(.system(size: 13, weight: .semibold))
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

                if !prismStore.clips.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Recent Vault Clippings", systemImage: "tray.full.fill")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Spacer()
                            Button("All Clips →") {
                                activeStudioTab = .vault
                                if isWideLayout {
                                    isWideSideStudioVisible = true
                                } else {
                                    showingStudioSheet = true
                                }
                            }
                            .font(.system(size: 12, weight: .semibold))
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

                                    VStack(alignment: .leading, spacing: 2) {
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
                                }
                                .padding(12)
                                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, isWideLayout ? 32 : 96)
        }
    }

    private func floatingSelectionPill(sel: PrismSelectionOverlayState, in size: CGSize, isWideLayout: Bool) -> some View {
        let clampedX = max(135, min(size.width - 135, sel.centerX))
        let targetY = sel.topY > 68 ? (sel.topY - 34) : min(size.height - 90, sel.bottomY + 34)

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
                Label("Quote", systemImage: "text.quote")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
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
                engine.showToast("Sent to TagDoS (#prism)")
            } label: {
                Label("TagDoS", systemImage: "checklist")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(Color(hex: "#FFB300"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.10), in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                let text = sel.text
                engine.selectionState = nil
                activeStudioTab = .copilot
                if isWideLayout {
                    isWideSideStudioVisible = true
                } else {
                    showingStudioSheet = true
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
                }
            } label: {
                Label("Explain", systemImage: "sparkles")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(Color(hex: "#A855F7"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.10), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(5)
        .background(Color(hex: "#0A1020").opacity(0.96), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.45), radius: 12, x: 0, y: 4)
        .position(x: clampedX, y: targetY)
    }

    private func quickImageSaveBanner(_ img: PrismImageCandidate) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "photo.badge.plus")
                .foregroundColor(Color(hex: "#10B981"))
            Text("Save Image to Prism Vault?")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
            Button("Save") {
                let captured = img
                engine.imageCandidate = nil
                Task {
                    _ = await prismStore.saveImageClip(
                        rawImageData: nil,
                        remoteImageUrl: captured.src,
                        sourceUrl: engine.currentURLString,
                        title: captured.alt.isEmpty ? engine.pageTitle : captured.alt
                    )
                    engine.showToast("Image Saved to Vault")
                }
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.black)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Color(hex: "#10B981"), in: Capsule())
            .buttonStyle(.plain)

            Button {
                engine.imageCandidate = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.65))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color(hex: "#0A1020").opacity(0.95), in: Capsule())
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
                            if cropDragStart == nil { cropDragStart = val.startLocation }
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
                Text("Drag region to capture")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white)
                Button("Cancel") {
                    isRegionCropMode = false
                    cropDragStart = nil
                    cropDragCurrent = nil
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(ThemeColors.accentCyan)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.86), in: Capsule())
            .padding(.top, 12)
        }
    }

    private var addPinnedSiteSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                TextField("Title (e.g. Hacker News)", text: $newPinTitle)
                    .padding(12)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundColor(.white)

                TextField("URL (e.g. news.ycombinator.com)", text: $newPinUrl)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .padding(12)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundColor(.white)

                Spacer()
            }
            .padding(20)
            .background(Color(hex: "#0D1324").ignoresSafeArea())
            .navigationTitle("Pin to Speed Dial")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingAddPinSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pin") {
                        if let resolved = PrismSearchEngine.resolveOmniboxInput(newPinUrl) {
                            prismStore.togglePinSite(title: newPinTitle, url: resolved.absoluteString)
                        }
                        showingAddPinSheet = false
                    }
                    .bold()
                    .disabled(newPinUrl.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
