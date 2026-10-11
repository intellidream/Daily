import SwiftUI
import DailyCore

/// Modal sheet for managing subscribed feeds, discovering feeds via Feedly, and adding custom RSS / WP-JSON feeds.
public struct NewsFeedsManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var newsService = NewsService.shared
    
    @State private var searchQuery = ""
    @State private var searchResults: [FeedSearchResult] = []
    @State private var isSearching = false
    
    // Custom Feed Add State
    @State private var isAddingCustom = false
    @State private var customName = ""
    @State private var customUrl = ""
    @State private var customCategory: FeedCategory = .tech
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassBackground {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Search Bar for Discovery
                            discoverySearchBar
                            
                            // Discovery Results
                            if isSearching {
                                ProgressView("Searching Feedly & Websites...")
                                    .tint(ThemeColors.accentCyan)
                                    .foregroundColor(.white)
                                    .padding(.vertical, 20)
                            } else if !searchResults.isEmpty {
                                searchResultsSection
                            }
                            
                            // Custom Feed Quick Add Card
                            customFeedSection
                            
                            // Current Subscriptions List
                            subscriptionsSection
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle("Manage Feeds")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(ThemeColors.accentCyan)
                }
            }
        }
    }
    
    private var discoverySearchBar: some View {
        GlassCard(cornerRadius: 16, padding: 8) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(ThemeColors.fgMutedDark)
                
                TextField("Search feeds or enter URL...", text: $searchQuery)
                    .foregroundColor(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit {
                        performSearch()
                    }
                
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                        searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                }
                
                Button("Search") {
                    performSearch()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ThemeColors.accentCyan)
            }
            .padding(.horizontal, 8)
        }
    }
    
    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DISCOVERED FEEDS")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(ThemeColors.accentCyan)
                .tracking(0.6)
            
            ForEach(searchResults) { result in
                GlassCard(cornerRadius: 14, padding: 12) {
                    HStack(spacing: 12) {
                        if let url = URL(string: result.iconUrl) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable()
                                        .scaledToFill()
                                        .frame(width: 28, height: 28)
                                        .clipShape(Circle())
                                default:
                                    Image(systemName: "rss")
                                        .frame(width: 28, height: 28)
                                        .foregroundColor(ThemeColors.accentCyan)
                                }
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(result.url)
                                .font(.system(size: 11))
                                .foregroundColor(ThemeColors.fgMutedDark)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        let isSubscribed = newsService.feeds.contains { $0.url == result.url }
                        if isSubscribed {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(ThemeColors.success)
                        } else {
                            Button("Subscribe") {
                                newsService.addFeed(name: result.name, url: result.url, category: .other)
                            }
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(ThemeColors.accentCyan)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(ThemeColors.accentCyan.opacity(0.15))
                            )
                        }
                    }
                }
            }
        }
    }
    
    private var customFeedSection: some View {
        GlassCard(cornerRadius: 16, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Add Custom Feed", systemImage: "plus.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(ThemeColors.accentBlue)
                    Spacer()
                    Button(isAddingCustom ? "Cancel" : "Open") {
                        withAnimation { isAddingCustom.toggle() }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ThemeColors.accentCyan)
                }
                
                if isAddingCustom {
                    VStack(spacing: 12) {
                        TextField("Feed Name (e.g. Tech Weekly)", text: $customName)
                            .padding(10)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(10)
                            .foregroundColor(.white)
                        
                        TextField("Feed or WP-JSON URL", text: $customUrl)
                            .padding(10)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(10)
                            .foregroundColor(.white)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        
                        Picker("Category", selection: $customCategory) {
                            ForEach(FeedCategory.allCases.filter { $0 != .all }, id: \.self) { cat in
                                Text(cat.displayName).tag(cat)
                            }
                        }
                        .pickerStyle(.menu)
                        
                        Button {
                            guard !customName.isEmpty, !customUrl.isEmpty else { return }
                            newsService.addFeed(name: customName, url: customUrl, category: customCategory)
                            customName = ""
                            customUrl = ""
                            withAnimation { isAddingCustom = false }
                        } label: {
                            Text("Save Feed Subscription")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    LinearGradient(
                                        colors: [ThemeColors.accentBlue, ThemeColors.accentCyan],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(12)
                        }
                    }
                    .padding(.top, 6)
                }
            }
        }
    }
    
    private var subscriptionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("YOUR SUBSCRIPTIONS (\(newsService.feeds.count))")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(ThemeColors.accentCyan)
                    .tracking(0.6)
                Spacer()
            }
            
            ForEach(newsService.feeds) { feed in
                GlassCard(cornerRadius: 14, padding: 12) {
                    HStack(spacing: 12) {
                        if let url = URL(string: feed.iconUrl) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable()
                                        .scaledToFill()
                                        .frame(width: 24, height: 24)
                                        .clipShape(Circle())
                                default:
                                    Image(systemName: "newspaper")
                                        .font(.system(size: 14))
                                        .foregroundColor(ThemeColors.accentCyan)
                                }
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feed.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            
                            HStack(spacing: 6) {
                                Text(feed.category.displayName)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(ThemeColors.accentCyan)
                                Text("•")
                                    .foregroundColor(ThemeColors.fgMutedDark)
                                Text(feed.type == .wpJson ? "WordPress JSON" : "RSS / Atom")
                                    .font(.system(size: 10))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                            }
                        }
                        
                        Spacer()
                        
                        // Delete Button
                        Button {
                            withAnimation {
                                newsService.deleteFeed(id: feed.id)
                            }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 13))
                                .foregroundColor(ThemeColors.error.opacity(0.8))
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(Color.white.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    private func performSearch() {
        guard !searchQuery.isEmpty else { return }
        isSearching = true
        Task {
            let res = await newsService.discoverFeeds(query: searchQuery)
            await MainActor.run {
                self.searchResults = res
                self.isSearching = false
            }
        }
    }
}
