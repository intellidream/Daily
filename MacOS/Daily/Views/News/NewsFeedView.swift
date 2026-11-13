import SwiftUI
import DailyCore

public enum NewsSubTab: String, CaseIterable, Identifiable {
    case live = "Live Feed"
    case perspectives = "Perspectives"
    case readLater = "Read Later"
    case favorites = "Favorites"
    
    public var id: String { rawValue }
}

public enum PerspectivesLens: String, CaseIterable, Identifiable {
    case allClusters = "Multi-Source Stories"
    case blindspots = "Blindspots"
    
    public var id: String { rawValue }
}

/// The signature DayOne News experience with categories, sub-tabs, search, and distraction-free reader integration.
public struct NewsFeedView: View {
    @ObservedObject private var newsService = NewsService.shared
    @ObservedObject private var savedService = SavedArticlesService.shared
    @ObservedObject private var settingsService = SettingsService.shared
    @ObservedObject private var dietStore = MediaDietStore.shared
    
    @State private var activeSubTab: NewsSubTab = .live
    @State private var perspectivesLens: PerspectivesLens = .allClusters
    @State private var searchQuery = ""
    @FocusState private var isSearchFocused: Bool
    @State private var selectedArticleForReader: NewsArticle?
    @State private var selectedClusterForSheet: StoryCluster?
    @State private var inspectedProfileFromCluster: MediaOutletProfile?
    @State private var showManageFeedsSheet = false
    @State private var showMediaDietSheet = false
    @State private var isDiscoveringTopPerspectives = false
    public var onNavigateBack: (() -> Void)? = nil
    @Binding public var isReadingArticle: Bool
    
    public init(onNavigateBack: (() -> Void)? = nil, isReadingArticle: Binding<Bool> = .constant(false)) {
        self.onNavigateBack = onNavigateBack
        self._isReadingArticle = isReadingArticle
        if ProcessInfo.processInfo.arguments.contains("-testOpenRepublicaReader") {
            let republicaArticle = NewsArticle(
                id: "https://republica.ro/se-pare-ca-am-murit",
                title: "Se pare că am murit",
                link: "https://republica.ro/se-pare-ca-am-murit",
                publishDate: Date(),
                imageUrl: "https://assets.republica.ro/20160112/900x600/bc60b65453c3b2f1bde7a2ccf8702886926c32c0.png",
                description: "Circulă pe facebook un clip cu titlul: „Lumânări pentru ziaristul CTP”...",
                author: "Cristian Tudor Popescu",
                publicationName: "Republica"
            )
            self._selectedArticleForReader = State(initialValue: republicaArticle)
        }
    }
    
    private var multiSourceClusters: [StoryCluster] {
        newsService.storyClusters.filter { $0.hasMultipleSources }
    }

    private var displayedClusters: [StoryCluster] {
        let base: [StoryCluster] = perspectivesLens == .blindspots
            ? newsService.blindspotClusters
            : multiSourceClusters

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return base }

        return base.filter { cluster in
            cluster.leadArticle.title.lowercased().contains(query) ||
            cluster.items.contains { $0.profile.name.lowercased().contains(query) || $0.article.title.lowercased().contains(query) }
        }
    }

    // Filtered articles based on sub-tab and search query
    private var displayedArticles: [NewsArticle] {
        let baseList: [NewsArticle]
        switch activeSubTab {
        case .live, .perspectives:
            baseList = newsService.articles
        case .readLater:
            baseList = savedService.readLaterArticles.map { $0.toNewsArticle() }
        case .favorites:
            baseList = savedService.favoriteArticles.map { $0.toNewsArticle() }
        }
        
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return baseList }
        
        return baseList.filter {
            $0.title.lowercased().contains(query) ||
            ($0.description?.lowercased().contains(query) ?? false) ||
            ($0.author?.lowercased().contains(query) ?? false)
        }
    }
    
    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Pinned Header Section aligned with companion & hub headers
                VStack(spacing: 12) {
                    headerBar
                    subTabSwitcher
                    if activeSubTab == .live {
                        feedPickerRow
                    } else if activeSubTab == .perspectives {
                        perspectivesLensBar
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
                
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 14) {
                        if activeSubTab == .perspectives {
                            perspectivesContentSection
                        } else if newsService.isLoading && displayedArticles.isEmpty {
                            loadingStateView
                        } else if displayedArticles.isEmpty {
                            emptyStateView
                        } else {
                            LazyVStack(spacing: 14) {
                                ForEach(displayedArticles) { article in
                                    NewsArticleCard(
                                        article: article,
                                        onOpenPerspectives: { _, cluster in
                                            selectedClusterForSheet = cluster
                                        }
                                    ) {
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            selectedArticleForReader = article
                                            isReadingArticle = true
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 110) // Leave room for FloatingGlassCapsule
                }
                .scrollBounceBehavior(.always, axes: .vertical)
                .refreshable {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    #endif
                    if activeSubTab == .live || activeSubTab == .perspectives {
                        await newsService.loadFeed(newsService.selectedFeed, forceRefresh: true)
                    } else {
                        await savedService.syncWithSupabase()
                    }
                    #if canImport(UIKit)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    #endif
                }
            }
            
            // In-Place Distraction-Free Article Reader
            if let article = selectedArticleForReader {
                NewsReaderView(
                    article: article,
                    candidatePool: displayedArticles,
                    isInSeparateWindow: false,
                    onOpenInSeparateWindow: {
                        let articleToOpen = article
                        let pool = displayedArticles
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedArticleForReader = nil
                            isReadingArticle = false
                        }
                        ArticleWindowManager.shared.open(article: articleToOpen, candidatePool: pool)
                    },
                    onDismiss: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            selectedArticleForReader = nil
                            isReadingArticle = false
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
                .zIndex(10)
            }
        }
        .onChange(of: selectedArticleForReader) { _, newArticle in
            isReadingArticle = (newArticle != nil)
        }
        .onAppear {
            if selectedArticleForReader != nil {
                isReadingArticle = true
            }
        }
        .sheet(isPresented: $showManageFeedsSheet) {
            NewsFeedsManagementSheet()
                .frame(minWidth: 540, idealWidth: 620, minHeight: 480, idealHeight: 620)
        }
        .sheet(isPresented: $showMediaDietSheet) {
            MediaDietSheet {
                showMediaDietSheet = false
            }
        }
        .sheet(item: $selectedClusterForSheet) { cluster in
            PerspectivesComparisonPane(
                cluster: cluster,
                isSplitPane: false,
                onSelectArticle: { chosenArticle in
                    selectedClusterForSheet = nil
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selectedArticleForReader = chosenArticle
                        isReadingArticle = true
                    }
                },
                onOpenInPrism: { chosenArticle in
                    selectedClusterForSheet = nil
                    PrismStore.shared.requestOpenInPrism(url: chosenArticle.link, title: chosenArticle.title)
                    NotificationCenter.default.post(name: .dailySelectTab, object: NavigationTab.prism)
                },
                onClose: {
                    selectedClusterForSheet = nil
                }
            )
            .frame(minWidth: 560, idealWidth: 660, minHeight: 540, idealHeight: 680)
        }
        .popover(item: $inspectedProfileFromCluster) { profile in
            SourceTransparencyPopover(profile: profile) {
                inspectedProfileFromCluster = nil
            }
        }
        .task {
            if newsService.articles.isEmpty {
                await newsService.loadFeed(newsService.selectedFeed)
            }
            await savedService.syncWithSupabase()
            await MediaIntelligenceRegistry.shared.syncDeltasIfNeeded()
            await dietStore.syncWithSupabaseIfNeeded()
        }
    }
    
    // MARK: - Header Bar
    
    private var headerBar: some View {
        HStack(alignment: .center, spacing: 8) {
            // Left Back Button
            Button {
                if isSearchFocused {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        isSearchFocused = false
                    }
                } else {
                    onNavigateBack?()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(Color.white.opacity(0.08))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
            
            // Expanding Search Field in the Header
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSearchFocused ? ThemeColors.accentCyan : ThemeColors.fgMutedDark)
                
                TextField("Search articles...", text: $searchQuery)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white)
                    .focused($isSearchFocused)
                    .autocorrectionDisabled()
                
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.06))
                    .overlay(Capsule().strokeBorder(isSearchFocused ? ThemeColors.accentCyan : Color.white.opacity(0.1), lineWidth: 1))
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isSearchFocused)
            
            // Right Actions
            if isSearchFocused {
                Button("Cancel") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        isSearchFocused = false
                        searchQuery = ""
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ThemeColors.accentCyan)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
                HStack(spacing: 8) {
                    // Personal Media Diet Balance Ring
                    MediaDietHeaderButton(snapshot: dietStore.currentSnapshot) {
                        showMediaDietSheet = true
                    }

                    // Manage Feeds Button (where Refresh button used to be)
                    Button {
                        showManageFeedsSheet = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(width: 36, height: 36)
                            .background(
                                Circle().fill(Color.white.opacity(0.08))
                                    .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                            )
                    }
                    .buttonStyle(.plain)
                    
                    // Category Selector Menu Button
                    categorySelectorMenu
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
    }
    
    // MARK: - Category Selector Menu
    
    private var categorySelectorMenu: some View {
        ZStack {
            Circle()
                .fill(ThemeColors.accentCyan.opacity(0.15))
                .overlay(Circle().strokeBorder(ThemeColors.accentCyan.opacity(0.3), lineWidth: 1))
            
            Menu {
                ForEach(FeedCategory.allCases, id: \.self) { category in
                    Button {
                        Task {
                            await newsService.selectCategory(category)
                        }
                    } label: {
                        HStack {
                            Label(category.displayName, systemImage: category.systemIcon)
                            if newsService.selectedCategory == category {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: newsService.selectedCategory.systemIcon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(ThemeColors.accentCyan)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            #if os(macOS)
            .menuStyle(.borderlessButton)
            #endif
            .menuIndicator(.hidden)
        }
        .frame(width: 36, height: 36)
        .contentShape(Circle())
    }
    
    // MARK: - Sub-Tab Switcher
    
    private var subTabSwitcher: some View {
        HStack(spacing: 8) {
            ForEach(NewsSubTab.allCases) { tab in
                let isSelected = activeSubTab == tab
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        activeSubTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                        
                        // Badge count
                        if tab == .perspectives && !multiSourceClusters.isEmpty {
                            Text("\(multiSourceClusters.count)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(ThemeColors.accentPurple))
                        } else if tab == .readLater && !savedService.readLaterArticles.isEmpty {
                            Text("\(savedService.readLaterArticles.count)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(ThemeColors.accentCyan))
                        } else if tab == .favorites && !savedService.favoriteArticles.isEmpty {
                            Text("\(savedService.favoriteArticles.count)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color(red: 1.0, green: 0.8, blue: 0.2)))
                        }
                    }
                    .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(isSelected ? Color.white.opacity(0.15) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.06))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        )
    }
    
    // MARK: - Feed Publication Picker
    
    private var feedPickerRow: some View {
        HStack {
            Menu {
                Button("All News (Consolidated)") {
                    Task {
                        await newsService.selectFeed(newsService.allNewsFeedSource)
                    }
                }
                
                if let mediumFeed = newsService.mediumReadingListFeedSource {
                    Divider()
                    Button {
                        Task {
                            await newsService.selectFeed(mediumFeed)
                        }
                    } label: {
                        Label("Medium Reading List", systemImage: "book.pages.fill")
                    }
                }
                
                if let substackFeed = newsService.substackInboxFeedSource {
                    Divider()
                    Button {
                        Task {
                            await newsService.selectFeed(substackFeed)
                        }
                    } label: {
                        Label("Substack Inbox", systemImage: "tray.full.fill")
                    }
                }
                
                Divider()
                
                ForEach(newsService.feeds) { feed in
                    Button(feed.name) {
                        Task {
                            await newsService.selectFeed(feed)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundColor(ThemeColors.accentCyan)
                    Text("Source: \(newsService.selectedFeed.name)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                )
            }
            #if os(macOS)
            .menuStyle(.borderlessButton)
            #endif
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            
            Spacer()
            
            Text("\(displayedArticles.count) stories")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(ThemeColors.fgMutedDark)
        }
    }
    
    // MARK: - Perspectives & Blindspots Sub-Tab Views

    private var perspectivesLensBar: some View {
        HStack(spacing: 10) {
            ForEach(PerspectivesLens.allCases) { lens in
                let isSelected = perspectivesLens == lens
                let count = lens == .blindspots ? newsService.blindspotClusters.count : multiSourceClusters.count
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        perspectivesLens = lens
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: lens == .blindspots ? "eye.trianglebadge.exclamationmark" : "scale.3d")
                            .font(.system(size: 11, weight: .bold))
                        Text(lens.rawValue)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        if count > 0 {
                            Text("\(count)")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(Color.white.opacity(0.16)))
                        }
                    }
                    .foregroundColor(isSelected ? .white : .white.opacity(0.65))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(isSelected ? ThemeColors.accentCyan.opacity(0.20) : Color.white.opacity(0.06))
                            .overlay(
                                Capsule()
                                    .strokeBorder(isSelected ? ThemeColors.accentCyan.opacity(0.45) : Color.white.opacity(0.10), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button {
                Task {
                    await discoverCrossSpectrumForTopStories()
                }
            } label: {
                HStack(spacing: 5) {
                    if isDiscoveringTopPerspectives {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(ThemeColors.accentCyan)
                    } else {
                        Image(systemName: "globe.europe.africa.fill")
                            .font(.system(size: 11, weight: .bold))
                    }
                    Text(isDiscoveringTopPerspectives ? "Scanning..." : "Expand Cross-Spectrum")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                }
                .foregroundColor(ThemeColors.accentCyan)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(ThemeColors.accentCyan.opacity(0.12))
                        .overlay(Capsule().strokeBorder(ThemeColors.accentCyan.opacity(0.28), lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
            .disabled(isDiscoveringTopPerspectives)
        }
    }

    @ViewBuilder
    private var perspectivesContentSection: some View {
        if newsService.isLoading && newsService.storyClusters.isEmpty {
            loadingStateView
        } else if displayedClusters.isEmpty {
            GlassCard(cornerRadius: 18, padding: 28) {
                VStack(spacing: 12) {
                    Image(systemName: perspectivesLens == .blindspots ? "eye.trianglebadge.exclamationmark" : "scale.3d")
                        .font(.system(size: 38))
                        .foregroundColor(ThemeColors.accentCyan.opacity(0.8))

                    Text(perspectivesLens == .blindspots ? "No Asymmetric Blindspots Detected Yet" : "Discover Multi-Source Perspectives")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text(newsService.selectedFeed.id != newsService.allNewsFeedSource.id
                         ? "You are currently viewing a single feed (\(newsService.selectedFeed.name)). Switch to All News or tap Expand Cross-Spectrum to compare how other outlets cover today's top stories."
                         : "Tap Expand Cross-Spectrum to pull 15–25 global and Romanian perspectives across Left, Center, and Right newsrooms for your top headlines.")
                        .font(.system(size: 13))
                        .foregroundColor(ThemeColors.fgMutedDark)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 10) {
                        if newsService.selectedFeed.id != newsService.allNewsFeedSource.id {
                            Button {
                                Task {
                                    await newsService.selectFeed(newsService.allNewsFeedSource)
                                }
                            } label: {
                                Text("Switch to All News")
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Capsule().fill(Color.white.opacity(0.12)))
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            Task {
                                await discoverCrossSpectrumForTopStories()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 12, weight: .bold))
                                Text(isDiscoveringTopPerspectives ? "Expanding..." : "Expand Cross-Spectrum")
                                    .font(.system(size: 12.5, weight: .bold))
                            }
                            .foregroundColor(ThemeColors.accentCyan)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(ThemeColors.accentCyan.opacity(0.14))
                                    .overlay(Capsule().strokeBorder(ThemeColors.accentCyan.opacity(0.32), lineWidth: 1))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isDiscoveringTopPerspectives)
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 12)
        } else {
            LazyVStack(spacing: 14) {
                ForEach(displayedClusters) { cluster in
                    StoryClusterCard(
                        cluster: cluster,
                        onOpenLeadArticle: { article in
                            withAnimation(.easeInOut(duration: 0.25)) {
                                selectedArticleForReader = article
                                isReadingArticle = true
                            }
                        },
                        onOpenPerspectives: { tappedCluster in
                            selectedClusterForSheet = tappedCluster
                        },
                        onInspectProfile: { profile in
                            inspectedProfileFromCluster = profile
                        }
                    )
                }
            }
        }
    }

    private func discoverCrossSpectrumForTopStories() async {
        guard !isDiscoveringTopPerspectives else { return }
        isDiscoveringTopPerspectives = true
        let candidates = Array(newsService.storyClusters.prefix(5))
        for base in candidates {
            let expanded = await NewsPerspectiveService.shared.expandCoverage(for: base)
            newsService.updateCluster(expanded)
        }
        isDiscoveringTopPerspectives = false
    }

    // MARK: - Loading & Empty States
    
    private var loadingStateView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(ThemeColors.accentCyan)
            Text("Fetching latest briefings from sources...")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(ThemeColors.fgMutedDark)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    private var emptyStateView: some View {
        GlassCard(cornerRadius: 18, padding: 32) {
            VStack(spacing: 12) {
                Image(systemName: activeSubTab == .readLater ? "bookmark.slash" : (activeSubTab == .favorites ? "star.slash" : "newspaper"))
                    .font(.system(size: 42))
                    .foregroundColor(ThemeColors.accentCyan.opacity(0.7))
                
                Text(activeSubTab == .readLater ? "No Read Later Articles" : (activeSubTab == .favorites ? "No Favorites Saved" : "No Articles Available"))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text(activeSubTab == .live ? "Try selecting another feed or pulling to refresh." : "Save articles while reading by tapping the bookmark or star button.")
                    .font(.system(size: 13))
                    .foregroundColor(ThemeColors.fgMutedDark)
                    .multilineTextAlignment(.center)
                
                if activeSubTab == .live {
                    Button {
                        Task {
                            await newsService.loadFeed(newsService.selectedFeed, forceRefresh: true)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .bold))
                            Text("Refresh Feed")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(ThemeColors.accentCyan)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(ThemeColors.accentCyan.opacity(0.12))
                                .overlay(Capsule().strokeBorder(ThemeColors.accentCyan.opacity(0.25), lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 20)
    }
}
