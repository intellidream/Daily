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
    @Published public private(set) var isSyncingSubstack: Bool = false
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
        config.timeoutIntervalForRequest = 8
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            "Accept": "application/rss+xml, application/atom+xml, application/json, text/xml, */*"
        ]
        self.urlSession = URLSession(configuration: config)
        
        loadFeeds()
        Task {
            await syncSubscriptionsWithSupabase()
            if let subUser = SettingsService.shared.settings.newsSubstackUsername, !subUser.isEmpty {
                _ = await syncSubstackSubscriptions()
            }
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
            FeedSource(name: "Recorder", url: "https://recorder.ro/feed/", category: .local, displayOrder: 6),
            
            // 📈 Markets
            FeedSource(name: "CNBC", url: "https://www.cnbc.com/id/100003114/device/rss/rss.html", category: .markets, displayOrder: 7),
            FeedSource(name: "The Economist", url: "https://www.economist.com/finance-and-economics/rss.xml", category: .markets, displayOrder: 8),
            
            // 🌍 World
            FeedSource(name: "BBC News", url: "https://feeds.bbci.co.uk/news/rss.xml", category: .world, displayOrder: 9),
            FeedSource(name: "NPR", url: "https://feeds.npr.org/1001/rss.xml", category: .world, displayOrder: 10),
            FeedSource(name: "Politico Europe", url: "https://www.politico.eu/feed/", category: .world, displayOrder: 11),
            FeedSource(name: "Deutsche Welle", url: "https://rss.dw.com/rdf/rss-en-all", category: .world, displayOrder: 12),
            FeedSource(name: "Google News", url: "https://news.google.com/rss?hl=en-US&gl=US&ceid=US:en", category: .world, displayOrder: 13),
            
            // 💡 Tech
            FeedSource(name: "TechCrunch", url: "https://techcrunch.com/feed/", category: .tech, displayOrder: 14),
            FeedSource(name: "The Verge", url: "https://www.theverge.com/rss/index.xml", category: .tech, displayOrder: 15),
            FeedSource(name: "Ars Technica", url: "https://feeds.arstechnica.com/arstechnica/index", category: .tech, displayOrder: 16),
            FeedSource(name: "Zona IT", url: "https://zonait.ro/wp-json/wp/v2/posts?per_page=20&_embed", type: .wpJson, category: .tech, displayOrder: 17),
            FeedSource(name: "Windows Central", url: "https://www.windowscentral.com/feeds.xml", category: .tech, displayOrder: 18)
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
        if !forceRefresh, let cached = feedCache[feed.url], !cached.articles.isEmpty, Date().timeIntervalSince(cached.timestamp) < cacheDuration {
            self.articles = cached.articles
            self.topHeadline = cached.articles.first
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        let session = self.urlSession
        let mediumUser = SettingsService.shared.settings.newsMediumUsername
        let mediumUrl = SettingsService.shared.settings.newsMediumReadingListUrl
        
        var fetchedArticles: [NewsArticle] = await Task.detached(priority: .userInitiated) {
            do {
                return try await Self.fetchFeedItems(
                    feed,
                    mediumUsername: mediumUser,
                    mediumReadingListUrl: mediumUrl,
                    session: session
                )
            } catch {
                print("[NewsService] Error loading feed \(feed.name): \(error)")
                return []
            }
        }.value
        
        // Fallback for Substack Inbox when browser session is inactive: aggregate synced Substack feeds
        if feed.id == "substack_inbox" && fetchedArticles.isEmpty {
            _ = await syncSubstackSubscriptions()
            let substackFeeds = feeds.filter { f in
                f.url.lowercased().contains("substack.com") ||
                f.iconUrl.lowercased().contains("substack") ||
                f.iconUrl.lowercased().contains("bucketeer-")
            }
            if !substackFeeds.isEmpty {
                fetchedArticles = await Task.detached(priority: .userInitiated) {
                    var combined: [NewsArticle] = []
                    await withTaskGroup(of: [NewsArticle].self) { group in
                        for sf in substackFeeds {
                            group.addTask {
                                (try? await Self.fetchFeedItems(
                                    sf,
                                    mediumUsername: mediumUser,
                                    mediumReadingListUrl: mediumUrl,
                                    session: session
                                )) ?? []
                            }
                        }
                        for await items in group {
                            combined.append(contentsOf: items.prefix(8))
                        }
                    }
                    combined.sort { $0.publishDate > $1.publishDate }
                    return combined
                }.value
            }
        }
        
        if !fetchedArticles.isEmpty {
            feedCache[feed.url] = (articles: fetchedArticles, timestamp: Date())
            self.articles = fetchedArticles
            self.topHeadline = fetchedArticles.first
        } else if self.articles.isEmpty {
            self.errorMessage = "Failed to load \(feed.name)."
        }
        
        isLoading = false
    }
    
    public func loadAllNews(forceRefresh: Bool = false) async {
        if !forceRefresh, let cached = feedCache["all_news"], !cached.articles.isEmpty, Date().timeIntervalSince(cached.timestamp) < cacheDuration {
            self.articles = cached.articles
            self.topHeadline = cached.articles.first
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        var activeFeeds = feeds
        if activeFeeds.isEmpty {
            activeFeeds = Self.defaultFeeds
            self.feeds = Self.defaultFeeds
            saveFeeds()
        }
        
        let session = self.urlSession
        let mediumUser = SettingsService.shared.settings.newsMediumUsername
        let mediumUrl = SettingsService.shared.settings.newsMediumReadingListUrl
        
        let fetchedArticles: [NewsArticle] = await Task.detached(priority: .userInitiated) {
            var aggregated: [NewsArticle] = []
            await withTaskGroup(of: [NewsArticle].self) { group in
                for f in activeFeeds {
                    group.addTask {
                        do {
                            return try await Self.fetchFeedItems(
                                f,
                                mediumUsername: mediumUser,
                                mediumReadingListUrl: mediumUrl,
                                session: session
                            )
                        } catch {
                            return []
                        }
                    }
                }
                
                for await items in group {
                    // Take top 3 from each feed for a rich, balanced briefing
                    let sample = items.prefix(3)
                    aggregated.append(contentsOf: sample)
                }
            }
            
            // Sort chronologically descending
            aggregated.sort { $0.publishDate > $1.publishDate }
            return aggregated
        }.value
        
        if !fetchedArticles.isEmpty {
            feedCache["all_news"] = (articles: fetchedArticles, timestamp: Date())
            self.articles = fetchedArticles
            self.topHeadline = fetchedArticles.first
        } else if self.articles.isEmpty {
            self.errorMessage = "Unable to load latest news briefings."
        }
        
        isLoading = false
    }
    
    // MARK: - Medium Integration (WinUI Parity)
    
    public var mediumReadingListFeedSource: FeedSource? {
        let settings = SettingsService.shared.settings
        guard let username = settings.newsMediumUsername, !username.isEmpty else { return nil }
        let clean = username.trimmingCharacters(in: CharacterSet(charactersIn: "@ \t\n"))
        let url = (settings.newsMediumReadingListUrl?.isEmpty == false)
            ? settings.newsMediumReadingListUrl!
            : "https://medium.com/@\(clean)/list/reading-list"
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
        guard !cleanUser.isEmpty else { return false }
        let feedUrl = "https://medium.com/feed/@\(cleanUser)"
        return feeds.contains(where: { $0.url == feedUrl })
    }
    
    // MARK: - Substack Integration
    
    public var substackInboxFeedSource: FeedSource? {
        let settings = SettingsService.shared.settings
        guard let username = settings.newsSubstackUsername, !username.isEmpty else { return nil }
        return FeedSource(
            id: "substack_inbox",
            name: "Substack Inbox",
            url: "https://substack.com/inbox",
            iconUrl: "https://substack.com/favicon.ico",
            type: .rss,
            category: .tech,
            displayOrder: 998
        )
    }
    
    private static func normalizeSubscriptionUrl(_ url: String) -> String {
        var u = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if u.hasPrefix("http://") {
            u = "https://" + u.dropFirst(7)
        }
        while u.hasSuffix("/") {
            u.removeLast()
        }
        return u
    }
    
    public func subscribeToSubstackPublication(name: String, feedUrl: String, iconUrl: String = "") {
        if isSubscribedToSubstack(feedUrl: feedUrl) { return }
        addFeed(name: name, url: feedUrl, iconUrl: iconUrl, category: .tech)
    }
    
    public func isSubscribedToSubstack(feedUrl: String) -> Bool {
        let target = Self.normalizeSubscriptionUrl(feedUrl)
        guard !target.isEmpty else { return false }
        let targetHost = URL(string: target)?.host?.lowercased().replacingOccurrences(of: "www.", with: "")
        return feeds.contains { existing in
            let norm = Self.normalizeSubscriptionUrl(existing.url)
            if norm == target { return true }
            if let th = targetHost, !th.isEmpty, th != "substack.com", th != "medium.com",
               let eh = URL(string: norm)?.host?.lowercased().replacingOccurrences(of: "www.", with: ""),
               eh == th {
                return true
            }
            return false
        }
    }
    
    /// Discovers and imports the user's existing Substack subscriptions into Daily's feeds list and syncs with Supabase.
    @discardableResult
    public func syncSubstackSubscriptions() async -> Int {
        guard !isSyncingSubstack else { return 0 }
        isSyncingSubstack = true
        defer { isSyncingSubstack = false }
        
        #if canImport(WebKit)
        let handle = SettingsService.shared.settings.newsSubstackUsername
        let subs = await HeadlessReadabilityParser.shared.fetchSubstackUserSubscriptions(handle: handle)
        guard !subs.isEmpty else { return 0 }
        
        var addedCount = 0
        var updatedIcons = false
        for sub in subs {
            if isSubscribedToSubstack(feedUrl: sub.feedUrl) {
                // Upgrade generic favicon to high-res Substack publication logo if available
                if !sub.iconUrl.isEmpty && !sub.iconUrl.contains("favicon"),
                   let idx = feeds.firstIndex(where: { Self.normalizeSubscriptionUrl($0.url) == Self.normalizeSubscriptionUrl(sub.feedUrl) }),
                   (feeds[idx].iconUrl.isEmpty || feeds[idx].iconUrl.contains("google.com/s2/favicons") || feeds[idx].iconUrl.contains("favicon.ico")) {
                    feeds[idx].iconUrl = sub.iconUrl
                    updatedIcons = true
                }
                continue
            }
            let newFeed = FeedSource(
                name: sub.name,
                url: sub.feedUrl,
                iconUrl: sub.iconUrl,
                type: .rss,
                category: .tech,
                displayOrder: feeds.count
            )
            feeds.append(newFeed)
            addedCount += 1
            Task {
                await pushSubscriptionToSupabase(newFeed)
            }
        }
        
        if addedCount > 0 || updatedIcons {
            saveFeeds()
            feedCache.removeValue(forKey: "all_news")
            feedCache.removeValue(forKey: "https://substack.com/inbox")
        }
        return subs.count
        #else
        return 0
        #endif
    }
    
    nonisolated private static func fetchFeedItems(
        _ feed: FeedSource,
        mediumUsername: String?,
        mediumReadingListUrl: String?,
        session: URLSession
    ) async throws -> [NewsArticle] {
        if feed.id == "medium_reading_list" {
            let cleanUser = mediumUsername?.trimmingCharacters(in: CharacterSet(charactersIn: "@ \t\n")) ?? ""
            #if canImport(WebKit)
            let readingListUrl = (mediumReadingListUrl?.isEmpty == false)
                ? mediumReadingListUrl!
                : (!cleanUser.isEmpty ? "https://medium.com/@\(cleanUser)/list/reading-list" : feed.url)
            
            let scraped = await HeadlessReadabilityParser.shared.scrapeMediumReadingList(urlString: readingListUrl)
            if !scraped.isEmpty {
                return scraped
            }
            #endif
            
            var targetUrl = feed.url
            if !targetUrl.contains("/feed/") && !cleanUser.isEmpty {
                targetUrl = "https://medium.com/feed/@\(cleanUser)"
            }
            
            if let url = URL(string: targetUrl) {
                do {
                    let (data, response) = try await session.data(from: url)
                    if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                        let parser = FeedParser(feed: feed)
                        let parsed = parser.parse(xmlData: data)
                        if !parsed.isEmpty {
                            return parsed
                        }
                    }
                } catch {
                    print("[NewsService] Medium RSS fetch fallback error: \(error)")
                }
            }
        }
        
        if feed.id == "substack_inbox" {
            #if canImport(WebKit)
            let scraped = await HeadlessReadabilityParser.shared.scrapeSubstackInbox()
            if !scraped.isEmpty {
                return scraped
            }
            #endif
        }
        
        var targetFeedUrl = feed.url.trimmingCharacters(in: .whitespacesAndNewlines)
        if targetFeedUrl.hasPrefix("http://") {
            targetFeedUrl = "https://" + targetFeedUrl.dropFirst(7)
        }
        guard let url = URL(string: targetFeedUrl) else {
            throw URLError(.badURL)
        }
        
        let (data, response) = try await session.data(from: url)
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
    
    public func addFeed(name: String, url: String, iconUrl: String = "", category: FeedCategory) {
        var safeUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if safeUrl.hasPrefix("http://") {
            safeUrl = "https://" + safeUrl.dropFirst(7)
        }
        // Automatically normalize bare Substack publication URLs (e.g. https://pragmaticengineer.substack.com -> /feed)
        if let parsed = URL(string: safeUrl), let host = parsed.host?.lowercased(),
           host.hasSuffix(".substack.com"), host != "www.substack.com", host != "open.substack.com",
           (parsed.path.isEmpty || parsed.path == "/") {
            safeUrl = "https://\(host)/feed"
        }
        let type: FeedType = safeUrl.contains("wp-json") ? .wpJson : .rss
        let newFeed = FeedSource(
            name: name,
            url: safeUrl,
            iconUrl: iconUrl,
            type: type,
            category: category,
            displayOrder: feeds.count
        )
        feeds.append(newFeed)
        saveFeeds()
        feedCache.removeValue(forKey: "all_news")
        
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
    
    // MARK: - Feed Discovery (Substack Publishers + Feedly + URL Sniffing)
    
    public func discoverFeeds(query: String) async -> [FeedSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        
        // 1. Direct URL Sniffing (and bare Substack subdomain URLs)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") || trimmed.contains(".") {
            var target = trimmed
            if !target.hasPrefix("http://") && !target.hasPrefix("https://") {
                target = "https://" + target
            }
            if let u = URL(string: target), let host = u.host?.lowercased(),
               host.hasSuffix(".substack.com"), host != "www.substack.com", host != "open.substack.com" {
                let slug = String(host.dropLast(".substack.com".count))
                let feedUrl = "https://\(host)/feed"
                if let sniffed = await sniffFeedsFromUrl(target), !sniffed.isEmpty {
                    return sniffed
                }
                return [FeedSearchResult(name: slug, url: feedUrl, iconUrl: "https://substack.com/favicon.ico", website: "https://\(host)")]
            }
            if let sniffed = await sniffFeedsFromUrl(target), !sniffed.isEmpty {
                return sniffed
            }
        }
        
        // 2. Parallel Substack Publication Discovery + Feedly Search API
        let cleanQuery = trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
        async let substackTask = searchSubstackPublications(query: cleanQuery)
        async let feedlyTask = searchFeedlyFeeds(query: trimmed)
        
        let (substackResults, feedlyResults) = await (substackTask, feedlyTask)
        var merged: [FeedSearchResult] = []
        var seen = Set<String>()
        
        for item in substackResults + feedlyResults {
            let norm = Self.normalizeSubscriptionUrl(item.url)
            if !norm.isEmpty && seen.insert(norm).inserted {
                merged.append(item)
            }
        }
        return merged
    }
    
    public static func parseSubstackSearchResponse(_ data: Data) -> [FeedSearchResult] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        var out: [FeedSearchResult] = []
        var seen = Set<String>()
        
        func appendPub(_ pub: [String: Any]) {
            let subdomain = (pub["subdomain"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            let customDomain = (pub["custom_domain"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            let customOptional = (pub["custom_domain_optional"] as? Bool) ?? false
            
            let host: String
            if !customDomain.isEmpty && !customOptional && customDomain.contains(".") {
                host = customDomain
            } else if !subdomain.isEmpty {
                host = "\(subdomain).substack.com"
            } else {
                return
            }
            let feedUrl = "https://\(host)/feed"
            guard seen.insert(feedUrl.lowercased()).inserted else { return }
            let name = (pub["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? subdomain
            let logo = (pub["logo_url"] as? String) ?? (pub["author_photo_url"] as? String) ?? "https://substack.com/favicon.ico"
            out.append(FeedSearchResult(
                name: name.isEmpty ? host : name,
                url: feedUrl,
                iconUrl: logo,
                website: "https://\(host)"
            ))
        }
        
        if let results = json["results"] as? [[String: Any]] {
            for r in results { appendPub(r) }
        }
        if let pubs = json["publications"] as? [[String: Any]] {
            for p in pubs { appendPub(p) }
        }
        if let items = json["items"] as? [[String: Any]] {
            for group in items {
                let groupType = (group["type"] as? String) ?? ""
                guard let results = group["results"] as? [[String: Any]] else { continue }
                if groupType.lowercased().contains("publication") {
                    for r in results { appendPub(r) }
                } else if groupType == "profileSearchResults" {
                    for profile in results {
                        if let pubUsers = profile["publicationUsers"] as? [[String: Any]] {
                            let sorted = pubUsers.sorted {
                                (($0["is_primary"] as? Bool) == true ? 0 : 1) < (($1["is_primary"] as? Bool) == true ? 0 : 1)
                            }
                            for pu in sorted {
                                let role = (pu["role"] as? String) ?? ""
                                if role == "admin" || role == "contributor" || (pu["is_primary"] as? Bool) == true {
                                    if let pub = pu["publication"] as? [String: Any] {
                                        appendPub(pub)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        return out
    }
    
    private func searchSubstackPublications(query: String) async -> [FeedSearchResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://substack.com/api/v1/top/search?query=\(encoded)&page=0") else {
            return []
        }
        do {
            let (data, response) = try await urlSession.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return []
            }
            return Self.parseSubstackSearchResponse(data)
        } catch {
            return []
        }
    }
    
    private func searchFeedlyFeeds(query: String) async -> [FeedSearchResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
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
                .eq("is_deleted", value: false)
                .order("display_order")
                .execute()
            
            let response = try JSONDecoder().decode([RssSubscription].self, from: res.data)
            
            if !response.isEmpty {
                var remoteFeeds = response.filter { !$0.isDeleted }.map { sub -> FeedSource in
                    var fs = sub.toFeedSource()
                    if fs.url.hasPrefix("http://") {
                        fs = FeedSource(
                            id: fs.id,
                            name: fs.name,
                            url: "https://" + fs.url.dropFirst(7),
                            iconUrl: fs.iconUrl,
                            type: fs.type,
                            category: fs.category,
                            displayOrder: fs.displayOrder
                        )
                    }
                    return fs
                }
                // Deduplicate by URL
                var seen = Set<String>()
                remoteFeeds = remoteFeeds.filter { seen.insert($0.url).inserted }
                if !remoteFeeds.isEmpty {
                    self.feeds = remoteFeeds
                    saveFeeds()
                }
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
                .upsert(sub, returning: .minimal)
                .execute()
        } catch {
            print("[NewsService] Supabase subscription push error: \(error)")
        }
    }
}
