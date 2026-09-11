import Foundation
import Supabase

/// Central news management service coordinating feeds, parallel loading, caching, article extraction, and feed discovery.
@MainActor
public final class NewsService: ObservableObject {
    public static let shared = NewsService()
    
    @Published public private(set) var feeds: [FeedSource] = []
    @Published public var selectedFeed: FeedSource
    @Published public var selectedCategory: FeedCategory = .all
    @Published public private(set) var articles: [NewsArticle] = []
    @Published public private(set) var topHeadline: NewsArticle?
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var errorMessage: String?
    
    public let allNewsFeedSource = FeedSource(
        id: "all_news",
        name: "All News",
        url: "all_news",
        iconUrl: "",
        type: .rss,
        category: .all,
        displayOrder: -1
    )
    
    private var feedCache: [String: (articles: [NewsArticle], timestamp: Date)] = [:]
    private let cacheDuration: TimeInterval = 15 * 60 // 15 minutes
    private let feedsStorageKey = "dayone_custom_feeds_cache_v1"
    private let urlSession: URLSession
    
    public init() {
        self.selectedFeed = allNewsFeedSource
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            "Accept": "application/rss+xml, application/atom+xml, application/json, text/xml, */*"
        ]
        self.urlSession = URLSession(configuration: config)
        
        loadFeeds()
        Task {
            await syncSubscriptionsWithSupabase()
            await loadFeed(selectedFeed)
        }
    }
    
    // MARK: - Default Seed Feeds (WinUI Parity)
    
    public static var defaultFeeds: [FeedSource] {
        [
            // 🇷🇴 Local
            FeedSource(name: "Republica", url: "https://republica.ro/rss", category: .local, displayOrder: 0),
            FeedSource(name: "Digi24", url: "https://www.digi24.ro/rss", category: .local, displayOrder: 1),
            FeedSource(name: "Ziarul Financiar", url: "https://www.zf.ro/rss/", category: .local, displayOrder: 2),
            FeedSource(name: "HotNews", url: "https://www.hotnews.ro/rss", category: .local, displayOrder: 3),
            FeedSource(name: "Biziday", url: "https://www.biziday.ro/feed/", category: .local, displayOrder: 4),
            FeedSource(name: "Economica.net", url: "https://www.economica.net/rss", category: .local, displayOrder: 5),
            
            // 📈 Markets
            FeedSource(name: "CNBC", url: "https://www.cnbc.com/id/100003114/device/rss/rss.html", category: .markets, displayOrder: 6),
            FeedSource(name: "The Economist", url: "https://www.economist.com/finance-and-economics/rss.xml", category: .markets, displayOrder: 7),
            
            // 🌍 World
            FeedSource(name: "BBC News", url: "https://feeds.bbci.co.uk/news/rss.xml", category: .world, displayOrder: 8),
            FeedSource(name: "NPR", url: "https://feeds.npr.org/1001/rss.xml", category: .world, displayOrder: 9),
            FeedSource(name: "Politico Europe", url: "https://www.politico.eu/feed/", category: .world, displayOrder: 10),
            FeedSource(name: "Deutsche Welle", url: "https://rss.dw.com/rdf/rss-en-all", category: .world, displayOrder: 11),
            FeedSource(name: "Google News", url: "https://news.google.com/rss?hl=en-US&gl=US&ceid=US:en", category: .world, displayOrder: 12),
            
            // 💡 Tech
            FeedSource(name: "TechCrunch", url: "https://techcrunch.com/feed/", category: .tech, displayOrder: 13),
            FeedSource(name: "The Verge", url: "https://www.theverge.com/rss/index.xml", category: .tech, displayOrder: 14),
            FeedSource(name: "Ars Technica", url: "https://feeds.arstechnica.com/arstechnica/index", category: .tech, displayOrder: 15),
            FeedSource(name: "Zona IT", url: "https://zonait.ro/wp-json/wp/v2/posts?per_page=20&_embed", type: .wpJson, category: .tech, displayOrder: 16),
            FeedSource(name: "Windows Central", url: "https://www.windowscentral.com/feeds.xml", category: .tech, displayOrder: 17)
        ]
    }
    
    // MARK: - Feed Loading
    
    public func selectFeed(_ feed: FeedSource) async {
        selectedFeed = feed
        await loadFeed(feed)
    }
    
    public func selectCategory(_ category: FeedCategory) async {
        selectedCategory = category
        if category == .all {
            selectedFeed = allNewsFeedSource
            await loadFeed(allNewsFeedSource)
        } else {
            // Pick first feed matching category, or filter All News
            if let matchingFeed = feeds.first(where: { $0.category == category }) {
                selectedFeed = matchingFeed
                await loadFeed(matchingFeed)
            } else {
                await loadFeed(allNewsFeedSource)
            }
        }
    }
    
    public func loadFeed(_ feed: FeedSource, forceRefresh: Bool = false) async {
        if feed.url == "all_news" {
            await loadAllNews(forceRefresh: forceRefresh)
            return
        }
        
        // Cache check
        if !forceRefresh, let cached = feedCache[feed.url], Date().timeIntervalSince(cached.timestamp) < cacheDuration {
            self.articles = cached.articles
            self.topHeadline = cached.articles.first
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let fetched = try await fetchFeedItems(feed)
            feedCache[feed.url] = (articles: fetched, timestamp: Date())
            self.articles = fetched
            self.topHeadline = fetched.first
        } catch {
            print("[NewsService] Error loading feed \(feed.name): \(error)")
            self.errorMessage = "Failed to load \(feed.name)."
            // Keep existing articles if available
        }
        
        isLoading = false
    }
    
    public func loadAllNews(forceRefresh: Bool = false) async {
        if !forceRefresh, let cached = feedCache["all_news"], Date().timeIntervalSince(cached.timestamp) < cacheDuration {
            self.articles = cached.articles
            self.topHeadline = cached.articles.first
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        var aggregated: [NewsArticle] = []
        let activeFeeds = feeds
        
        await withTaskGroup(of: [NewsArticle].self) { group in
            for f in activeFeeds {
                group.addTask {
                    do {
                        return try await self.fetchFeedItems(f)
                    } catch {
                        return []
                    }
                }
            }
            
            for await items in group {
                // Take top 2 from each feed (WinUI fairness rule)
                let sample = items.prefix(2)
                aggregated.append(contentsOf: sample)
            }
        }
        
        // Sort chronologically descending
        aggregated.sort { $0.publishDate > $1.publishDate }
        
        feedCache["all_news"] = (articles: aggregated, timestamp: Date())
        self.articles = aggregated
        self.topHeadline = aggregated.first
        isLoading = false
    }
    
    // MARK: - Medium Integration (WinUI Parity)
    
    public var mediumReadingListFeedSource: FeedSource? {
        let settings = SettingsService.shared.settings
        guard let username = settings.newsMediumUsername, !username.isEmpty else { return nil }
        let url = settings.newsMediumReadingListUrl ?? "https://medium.com/feed/@\(username)"
        return FeedSource(
            id: "medium_reading_list",
            name: "Medium Reading List",
            url: url,
            iconUrl: "https://cdn-static-1.medium.com/_/fp/icons/favicon-rebrand-medium.37877227.png",
            type: .rss,
            category: .tech,
            displayOrder: 999
        )
    }
    
    public func subscribeToMediumAuthor(username: String, authorName: String? = nil) {
        let cleanUser = username.trimmingCharacters(in: CharacterSet(charactersIn: "@ \t\n"))
        guard !cleanUser.isEmpty else { return }
        let feedUrl = "https://medium.com/feed/@\(cleanUser)"
        if feeds.contains(where: { $0.url == feedUrl }) { return }
        let displayName = authorName ?? "@\(cleanUser)"
        addFeed(name: "Medium: \(displayName)", url: feedUrl, category: .tech)
    }
    
    public func isSubscribedToMediumAuthor(username: String) -> Bool {
        let cleanUser = username.trimmingCharacters(in: CharacterSet(charactersIn: "@ \t\n"))
        let feedUrl = "https://medium.com/feed/@\(cleanUser)"
        return feeds.contains(where: { $0.url == feedUrl })
    }
    
    private func fetchFeedItems(_ feed: FeedSource) async throws -> [NewsArticle] {
        if feed.id == "medium_reading_list" {
            let settings = SettingsService.shared.settings
            let username = settings.newsMediumUsername ?? ""
            
            var targetUrl = feed.url
            if !targetUrl.contains("/feed/") && !username.isEmpty {
                targetUrl = "https://medium.com/feed/@\(username)"
            }
            
            if let url = URL(string: targetUrl) {
                do {
                    let (data, response) = try await urlSession.data(from: url)
                    if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                        let parser = FeedParser(feed: feed)
                        let parsed = parser.parse(xmlData: data)
                        if !parsed.isEmpty {
                            return parsed
                        }
                    }
                } catch {
                    print("[NewsService] Medium RSS fetch error: \(error)")
                }
            }
        }
        
        guard let url = URL(string: feed.url) else {
            throw URLError(.badURL)
        }
        
        let (data, response) = try await urlSession.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        if feed.type == .wpJson {
            let parser = WpJsonParser(feed: feed)
            return parser.parse(jsonData: data)
        } else {
            let parser = FeedParser(feed: feed)
            return parser.parse(xmlData: data)
        }
    }
    
    // MARK: - Full Article Readability Extraction
    
    public func fetchFullArticle(article: NewsArticle) async -> NewsArticle {
        do {
            let extracted = try await ArticleExtractor.shared.extract(from: article.link, baseArticle: article)
            return extracted
        } catch {
            print("[NewsService] Fast-path extraction error: \(error)")
            return article
        }
    }
    
    // MARK: - Feed Management & Persistence
    
    private func loadFeeds() {
        if let data = GroupDefaults.shared.userDefaults.data(forKey: feedsStorageKey),
           let saved = try? JSONDecoder().decode([FeedSource].self, from: data), !saved.isEmpty {
            self.feeds = saved
        } else {
            self.feeds = Self.defaultFeeds
            saveFeeds()
        }
    }
    
    private func saveFeeds() {
        if let data = try? JSONEncoder().encode(feeds) {
            GroupDefaults.shared.userDefaults.set(data, forKey: feedsStorageKey)
        }
    }
    
    public func addFeed(name: String, url: String, category: FeedCategory) {
        let type: FeedType = url.contains("wp-json") ? .wpJson : .rss
        let newFeed = FeedSource(
            name: name,
            url: url,
            type: type,
            category: category,
            displayOrder: feeds.count
        )
        feeds.append(newFeed)
        saveFeeds()
        
        Task {
            await pushSubscriptionToSupabase(newFeed)
        }
    }
    
    public func deleteFeed(id: String) {
        feeds.removeAll { $0.id == id }
        saveFeeds()
    }
    
    public func reorderFeeds(newOrder: [FeedSource]) {
        for (idx, _) in newOrder.enumerated() {
            var updated = newOrder[idx]
            updated.displayOrder = idx
        }
        self.feeds = newOrder
        saveFeeds()
    }
    
    // MARK: - Feed Discovery (Feedly + URL Sniffing)
    
    public func discoverFeeds(query: String) async -> [FeedSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        
        // 1. Direct URL Sniffing
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") || trimmed.contains(".") {
            var target = trimmed
            if !target.hasPrefix("http://") && !target.hasPrefix("https://") {
                target = "https://" + target
            }
            if let sniffed = await sniffFeedsFromUrl(target), !sniffed.isEmpty {
                return sniffed
            }
        }
        
        // 2. Feedly Search API
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let feedlyUrl = URL(string: "https://cloud.feedly.com/v3/search/feeds?query=\(encoded)") else {
            return []
        }
        
        do {
            let (data, _) = try await urlSession.data(from: feedlyUrl)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]] else {
                return []
            }
            
            return results.compactMap { item -> FeedSearchResult? in
                guard var feedId = item["feedId"] as? String ?? item["id"] as? String, !feedId.isEmpty else { return nil }
                if feedId.hasPrefix("feed/") {
                    feedId = String(feedId.dropFirst(5))
                }
                let name = item["title"] as? String ?? "Unnamed Feed"
                var icon = item["iconUrl"] as? String ?? item["visualUrl"] as? String ?? ""
                if icon.isEmpty, let host = URL(string: feedId)?.host {
                    icon = "https://www.google.com/s2/favicons?domain=\(host)&sz=64"
                }
                let website = item["website"] as? String ?? ""
                return FeedSearchResult(name: name, url: feedId, iconUrl: icon, website: website)
            }
        } catch {
            print("[NewsService] Feedly search error: \(error)")
            return []
        }
    }
    
    private func sniffFeedsFromUrl(_ urlString: String) async -> [FeedSearchResult]? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, _) = try await urlSession.data(from: url)
            guard let html = String(data: data, encoding: .utf8) else { return nil }
            
            let linkPattern = "<link[^>]+(?:type=[\"'](application/rss\\+xml|application/atom\\+xml|application/json)[\"']|rel=[\"']alternate[\"'])[^>]*>"
            guard let regex = try? NSRegularExpression(pattern: linkPattern, options: .caseInsensitive) else { return nil }
            let ns = html as NSString
            let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
            
            var results: [FeedSearchResult] = []
            for match in matches {
                let tag = ns.substring(with: match.range)
                let hrefPattern = "href=[\"']([^\"']+)[\"']"
                let titlePattern = "title=[\"']([^\"']+)[\"']"
                
                if let hrefRegex = try? NSRegularExpression(pattern: hrefPattern, options: .caseInsensitive),
                   let hrefMatch = hrefRegex.firstMatch(in: tag, range: NSRange(location: 0, length: (tag as NSString).length)) {
                    var href = (tag as NSString).substring(with: hrefMatch.range(at: 1))
                    if !href.hasPrefix("http://") && !href.hasPrefix("https://") {
                        if let resolved = URL(string: href, relativeTo: url) {
                            href = resolved.absoluteString
                        }
                    }
                    var feedTitle = url.host ?? "Discovered Feed"
                    if let titleRegex = try? NSRegularExpression(pattern: titlePattern, options: .caseInsensitive),
                       let titleMatch = titleRegex.firstMatch(in: tag, range: NSRange(location: 0, length: (tag as NSString).length)) {
                        feedTitle = (tag as NSString).substring(with: titleMatch.range(at: 1))
                    }
                    
                    let icon = "https://www.google.com/s2/favicons?domain=\(url.host ?? "")&sz=64"
                    results.append(FeedSearchResult(name: feedTitle, url: href, iconUrl: icon, website: urlString))
                }
            }
            return results
        } catch {
            return nil
        }
    }
    
    // MARK: - Supabase Subscriptions Sync
    
    private func syncSubscriptionsWithSupabase() async {
        guard let user = AuthService.shared.currentUser else { return }
        do {
            let client = SupabaseService.shared.client
            let res = try await client
                .from("rss_subscriptions")
                .select()
                .eq("user_id", value: user.id)
                .order("display_order")
                .execute()
            
            let response = try JSONDecoder().decode([RssSubscription].self, from: res.data)
            
            if !response.isEmpty {
                var remoteFeeds = response.filter { !$0.isDeleted }.map { $0.toFeedSource() }
                // Deduplicate by URL
                var seen = Set<String>()
                remoteFeeds = remoteFeeds.filter { seen.insert($0.url).inserted }
                self.feeds = remoteFeeds
                saveFeeds()
            }
        } catch {
            print("[NewsService] Supabase subscriptions pull error: \(error)")
        }
    }
    
    private func pushSubscriptionToSupabase(_ feed: FeedSource) async {
        guard let user = AuthService.shared.currentUser else { return }
        let sub = RssSubscription(
            id: UUID().uuidString,
            userId: user.id,
            name: feed.name,
            url: feed.url,
            iconUrl: feed.iconUrl,
            category: feed.category.rawValue,
            displayOrder: feed.displayOrder
        )
        do {
            let client = SupabaseService.shared.client
            try await client
                .from("rss_subscriptions")
                .upsert(sub)
                .execute()
        } catch {
            print("[NewsService] Supabase subscription push error: \(error)")
        }
    }
}
