import SwiftUI
import DailyCore

public enum NewsSubTab: String, CaseIterable, Identifiable {
    case live = "Live Feed"
    case readLater = "Read Later"
    case favorites = "Favorites"
    
    public var id: String { rawValue }
}

/// The signature DayOne News experience with categories, sub-tabs, search, and distraction-free reader integration.
public struct NewsFeedView: View {
    @ObservedObject private var newsService = NewsService.shared
    @ObservedObject private var savedService = SavedArticlesService.shared
    @ObservedObject private var settingsService = SettingsService.shared
    
    @State private var activeSubTab: NewsSubTab = .live
    @State private var searchQuery = ""
    @FocusState private var isSearchFocused: Bool
    @State private var selectedArticleForReader: NewsArticle?
    @State private var showManageFeedsSheet = false
    public var onNavigateBack: (() -> Void)? = nil
    
    public init(onNavigateBack: (() -> Void)? = nil) {
        self.onNavigateBack = onNavigateBack
    }
    
    // Filtered articles based on sub-tab and search query
    private var displayedArticles: [NewsArticle] {
        let baseList: [NewsArticle]
        switch activeSubTab {
        case .live:
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
            LiquidGlassBackground {
                ScrollView {
                    VStack(spacing: 16) {
                        // Top Glass Header Bar with Search & Category Action
                        headerBar
                        
                        // Sub-Tab Switcher (Live Feed / Read Later / Favorites)
                        subTabSwitcher
                        
                        // Feed Publication Picker (when Live Feed selected)
                        if activeSubTab == .live {
                            feedPickerRow
                        }
                        
                        // Articles Feed
                        if newsService.isLoading && displayedArticles.isEmpty {
                            loadingStateView
                        } else if displayedArticles.isEmpty {
                            emptyStateView
                        } else {
                            LazyVStack(spacing: 14) {
                                ForEach(displayedArticles) { article in
                                    NewsArticleCard(article: article) {
                                        selectedArticleForReader = article
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 110) // Leave room for FloatingGlassCapsule
                }
                .refreshable {
                    await newsService.loadFeed(newsService.selectedFeed, forceRefresh: true)
                    await savedService.syncWithSupabase()
                }
            }
        }
        .sheet(item: $selectedArticleForReader) { article in
            NewsReaderView(
                article: article,
                candidatePool: displayedArticles
            ) {
                selectedArticleForReader = nil
            }
        }
        .sheet(isPresented: $showManageFeedsSheet) {
            NewsFeedsManagementSheet()
        }
        .task {
            await savedService.syncWithSupabase()
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
        .padding(.top, 6)
    }
    
    // MARK: - Category Selector Menu
    
    private var categorySelectorMenu: some View {
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
                .frame(width: 36, height: 36)
                .background(
                    Circle().fill(ThemeColors.accentCyan.opacity(0.15))
                        .overlay(Circle().strokeBorder(ThemeColors.accentCyan.opacity(0.3), lineWidth: 1))
                )
        }
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
                        if tab == .readLater && !savedService.readLaterArticles.isEmpty {
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
            
            Spacer()
            
            Text("\(displayedArticles.count) stories")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(ThemeColors.fgMutedDark)
        }
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
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 20)
    }
}
