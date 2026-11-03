import Foundation
#if canImport(WebKit)
import WebKit
#endif

/// Distraction-free article extraction engine providing parity with WinUI,
/// powered by an in-memory Mozilla Readability engine over headless WebKit
/// with a multi-candidate scoring heuristic fallback.
public struct ScrapedMediumItem: Decodable, Sendable {
    public let title: String
    public let url: String
    public let author: String
    public let authorUrl: String
    public let imageUrl: String
    public let description: String

    public init(title: String, url: String, author: String, authorUrl: String, imageUrl: String, description: String) {
        self.title = title
        self.url = url
        self.author = author
        self.authorUrl = authorUrl
        self.imageUrl = imageUrl
        self.description = description
    }
}

/// In-memory cache for extracted full article content to guarantee instant opening on revisits.
public actor ArticleContentCache {
    public static let shared = ArticleContentCache()
    private var cache: [String: NewsArticle] = [:]
    
    public func get(_ key: String) -> NewsArticle? {
        cache[key]
    }
    
    public func set(_ key: String, article: NewsArticle) {
        cache[key] = article
    }
    
    public func clear() {
        cache.removeAll()
    }
}

public final class ArticleExtractor: @unchecked Sendable {
    
    public static let shared = ArticleExtractor()
    
    private let urlSession: URLSession
    
    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
            "Accept-Language": "ro-RO,ro;q=0.9,en-US;q=0.8,en;q=0.7"
        ]
        self.urlSession = URLSession(configuration: config, delegate: SecureRedirectDelegate(), delegateQueue: nil)
    }
    
    /// Determines whether the article content is a Medium teaser/snippet rather than a full story.
    public static func isMediumTeaser(_ content: String) -> Bool {
        let lower = content.lowercased()
        if lower.contains("continue reading on") ||
           lower.contains("medium-feed-link") ||
           lower.contains("medium-feed-item") ||
           lower.contains("medium-feed-snippet") ||
           lower.contains("member-only") ||
           lower.contains("made this story available to medium members") {
            return true
        }
        return false
    }
    
    /// Determines whether the article content is a Substack teaser/preview rather than a full story.
    public static func isSubstackTeaser(_ content: String) -> Bool {
        let lower = content.lowercased()
        if lower.contains("read more") && (lower.contains("substack.com/p/") || lower.contains("paywall")) {
            return true
        }
        if lower.contains("this post is for paid subscribers") ||
           lower.contains("this post is for subscribers") ||
           lower.contains("subscribe to unlock") ||
           lower.contains("subscription-widget-wrap") {
            return true
        }
        return false
    }
    
    /// Returns true when a Medium `uid` cookie represents a real signed-in user rather than a logged-out guest (`lo_*`).
    public static func isAuthenticatedMediumUid(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !trimmed.lowercased().hasPrefix("lo_")
    }
    
    /// Verifies whether a cookie jar contains a live authenticated Medium member session (`uid` != `lo_*` and `sid` present).
    public static func hasAuthenticatedMediumCookies(_ cookies: [HTTPCookie], now: Date = Date()) -> Bool {
        var hasValidUid = false
        var hasValidSid = false
        
        for cookie in cookies {
            let domain = cookie.domain.lowercased()
            guard domain == "medium.com" || domain == ".medium.com" else { continue }
            if let expires = cookie.expiresDate, expires <= now { continue }
            
            if cookie.name == "uid" && isAuthenticatedMediumUid(cookie.value) {
                hasValidUid = true
            } else if cookie.name == "sid" && !cookie.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                hasValidSid = true
            }
        }
        return hasValidUid && hasValidSid
    }
    
    /// Identifies poisoned host-only subdomain cookies (e.g. `malshikay.medium.com` shadowing `.medium.com`)
    /// or stale logged-out (`lo_*`) `uid` cookies that must be purged.
    public static func shouldDeleteMediumCookie(_ cookie: HTTPCookie, hasValidRootUid: Bool) -> Bool {
        let domain = cookie.domain.lowercased()
        let authCookieNames: Set<String> = ["uid", "sid", "xsrf", "cf_clearance"]
        
        // Host-only cookies on custom Medium subdomains (`*.medium.com`) shadow `.medium.com` per RFC 6265 §5.4.
        if domain != "medium.com" && domain != ".medium.com" && domain.hasSuffix(".medium.com") {
            if authCookieNames.contains(cookie.name) {
                return true
            }
        }
        
        // Remove guest `lo_*` uid cookies whenever a real authenticated uid exists, or on subdomains.
        if cookie.name == "uid" && !isAuthenticatedMediumUid(cookie.value) {
            if hasValidRootUid || (domain != "medium.com" && domain != ".medium.com") {
                return true
            }
        }
        
        return false
    }
    
    /// Strips Medium RSS 1x1 tracking pixels (`medium.com/_/stat`) and empty tracking wrappers so reader views
    /// never fire unauthenticated tracking requests or render invisible pixel artifacts.
    public static func stripMediumTrackingAndNoise(_ html: String) -> String {
        var cleaned = html.replacingOccurrences(
            of: "<img[^>]*medium\\.com/_/stat[^>]*>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        cleaned = cleaned.replacingOccurrences(
            of: "<div[^>]*>\\s*Get [^<]{1,80}stories in[^<]{0,40}inbox[\\s\\S]{0,400}?</div>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return cleaned
    }
    
    /// Strips Substack newsletter subscription widgets, like buttons, comment prompts, and footer CTA elements.
    public static func stripSubstackTrackingAndNoise(_ html: String) -> String {
        var clean = html
        clean = clean.replacingOccurrences(
            of: "<div[^>]*class=\"[^\"]*(?:subscription-widget-wrap|subscribe-widget|post-footer)[^\"]*\"[\\s\\S]*?</div>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        clean = clean.replacingOccurrences(
            of: "<div[^>]*class=\"[^\"]*(?:like-button-container|share-dialog|comment-widget)[^\"]*\"[\\s\\S]*?</div>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return clean
    }
    
    nonisolated public static func optimizeSubstackImageUrl(_ url: String) -> String {
        guard url.contains("substackcdn.com") || url.contains("substack-post-media") else { return url }
        if url.contains("w_") {
            let pattern = "w_\\d+"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return url }
            let range = NSRange(location: 0, length: (url as NSString).length)
            return regex.stringByReplacingMatches(in: url, range: range, withTemplate: "w_1200")
        }
        return url
    }
    
    nonisolated public static func hasAuthenticatedSubstackCookies(_ cookies: [HTTPCookie]) -> Bool {
        return cookies.contains { cookie in
            cookie.name == "substack.sid" &&
            !cookie.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    
    public static func clearCache() async {
        await ArticleContentCache.shared.clear()
    }
    
    private func cacheAndReturn(_ article: NewsArticle, for urlString: String) async -> NewsArticle {
        await ArticleContentCache.shared.set(urlString, article: article)
        return article
    }
    
    /// Fetches the raw HTML from the article URL and extracts the clean article content.
    public func extract(from urlString: String, baseArticle: NewsArticle? = nil) async throws -> NewsArticle {
        var safeUrlString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if safeUrlString.hasPrefix("http://") {
            safeUrlString = "https://" + safeUrlString.dropFirst(7)
        }
        guard let url = URL(string: safeUrlString) else {
            throw URLError(.badURL)
        }
        
        // Fast path: Check in-memory extraction cache for instant sub-millisecond retrieval
        if let cached = await ArticleContentCache.shared.get(safeUrlString),
           let content = cached.content, content.count > 250, !Self.isMediumTeaser(content) {
            return cached
        }
        
        let isMedium = safeUrlString.contains("medium.com") ||
                       (baseArticle?.publicationName?.localizedCaseInsensitiveContains("medium") == true) ||
                       Self.isMediumTeaser(baseArticle?.content ?? "") ||
                       Self.isMediumTeaser(baseArticle?.description ?? "")
        
        let hasSubstantialBaseContent = (baseArticle?.content != nil) &&
            (baseArticle!.content!.count > 250) &&
            !Self.isMediumTeaser(baseArticle!.content!)
        
        if isMedium && hasSubstantialBaseContent, var cleanBase = baseArticle {
            if let rawContent = cleanBase.content {
                cleanBase.content = Self.stripMediumTrackingAndNoise(rawContent)
            }
            return await cacheAndReturn(cleanBase, for: safeUrlString)
        }
        
        let isSubstack = safeUrlString.contains("substack.com") ||
                         (baseArticle?.publicationName?.localizedCaseInsensitiveContains("substack") == true) ||
                         Self.isSubstackTeaser(baseArticle?.content ?? "") ||
                         Self.isSubstackTeaser(baseArticle?.description ?? "")
        
        let hasSubstantialSubstackBaseContent = (baseArticle?.content != nil) &&
            (baseArticle!.content!.count > 250) &&
            !Self.isSubstackTeaser(baseArticle!.content!)
        
        if isSubstack && hasSubstantialSubstackBaseContent, var cleanBase = baseArticle {
            if let rawContent = cleanBase.content {
                cleanBase.content = Self.stripSubstackTrackingAndNoise(rawContent)
            }
            return await cacheAndReturn(cleanBase, for: safeUrlString)
        }
        
        #if canImport(WebKit)
        if isMedium {
            if let result = await HeadlessReadabilityParser.shared.extractMediumArticleDetailed(
                url: url,
                baseArticle: baseArticle,
                extractor: self
            ), let content = result.article.content, content.count > 100 {
                // Never cache paywall-truncated guest previews so signing in immediately unlocks full stories
                if result.isPaywallTruncated || Self.isMediumTeaser(content) {
                    return result.article
                }
                return await cacheAndReturn(result.article, for: safeUrlString)
            }
        }
        
        if isSubstack {
            if let result = await HeadlessReadabilityParser.shared.extractSubstackArticle(
                url: url,
                baseArticle: baseArticle,
                extractor: self
            ), let content = result.content, content.count > 100 {
                if Self.isSubstackTeaser(content) {
                    return result
                }
                return await cacheAndReturn(result, for: safeUrlString)
            }
        }
        #endif
        
        let (data, response) = try await urlSession.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        guard let html = String(data: data, encoding: .utf8) ??
                         String(data: data, encoding: .isoLatin1) ??
                         String(data: data, encoding: .windowsCP1252) else {
            throw URLError(.cannotDecodeRawData)
        }
        
        #if canImport(WebKit)
        if let readabilityArticle = await HeadlessReadabilityParser.shared.parse(
            html: html,
            urlString: urlString,
            baseArticle: baseArticle,
            extractor: self
        ), let content = readabilityArticle.content, content.count > 80 {
            // Anti-regression guard: Ensure the extracted body is not a leaked navigation header or menu
            let isMenuArtifact = content.contains("role=\"menu\"") ||
                                 content.contains("role=\"menuitem\"") ||
                                 content.contains("id=\"header\"") ||
                                 content.contains("class=\"menu")
            if !isMenuArtifact {
                return await cacheAndReturn(readabilityArticle, for: safeUrlString)
            }
        }
        #endif
        
        let parsed = parseHtml(html, url: urlString, baseArticle: baseArticle)
        return await cacheAndReturn(parsed, for: safeUrlString)
    }
    
    /// Synchronously parses an HTML string to extract readable article content using heuristic scoring.
    public func parseHtml(_ html: String, url: String, baseArticle: NewsArticle? = nil) -> NewsArticle {
        let ogTitle = extractMetaContent(property: "og:title", from: html) ?? extractTitleTag(from: html)
        let ogImage = extractMetaContent(property: "og:image", from: html) ?? baseArticle?.imageUrl
        let ogDescription = extractMetaContent(property: "og:description", from: html) ?? baseArticle?.description
        var rawAuthor = extractMetaContent(name: "author", from: html)
        if rawAuthor == nil || rawAuthor?.contains("://") == true {
            rawAuthor = extractMetaContent(property: "article:author", from: html)
        }
        if rawAuthor?.contains("://") == true {
            rawAuthor = nil
        }
        if rawAuthor == nil {
            rawAuthor = extractMetaContent(property: "og:article:author", from: html)
        }
        if rawAuthor?.contains("://") == true {
            rawAuthor = nil
        }
        if rawAuthor == nil {
            rawAuthor = extractMetaContent(name: "twitter:creator", from: html) ??
                        extractMetaContent(property: "author", from: html) ??
                        extractBylineFromDom(from: html) ??
                        baseArticle?.author
        }
        if rawAuthor?.contains("://") == true {
            rawAuthor = nil
        }
        
        var author: String? = nil
        // Sanitize author (WinUI parity)
        if let ra = rawAuthor {
            author = sanitizeAuthor(ra)
        }
        
        // Extract body content with multi-candidate scoring
        var content = extractMainContent(from: html)
        if content.isEmpty {
            content = baseArticle?.content ?? baseArticle?.description ?? ""
        }
        
        // Deduplicate featured image (WinUI parity)
        if let featImg = ogImage, !content.isEmpty {
            content = deduplicateFeaturedImage(content: content, featuredImage: featImg)
        }
        
        // Optimize Medium CDN images
        content = optimizeMediumImagesInHtml(content)
        
        let title = ogTitle ?? baseArticle?.title ?? "Untitled Article"
        
        return NewsArticle(
            id: baseArticle?.id ?? url,
            title: decodeHtmlEntities(title),
            link: url,
            publishDate: baseArticle?.publishDate ?? Date(),
            imageUrl: ogImage,
            description: decodeHtmlEntities(ogDescription ?? ""),
            content: content,
            author: author,
            publicationName: baseArticle?.publicationName,
            publicationIconUrl: baseArticle?.publicationIconUrl,
            category: baseArticle?.category
        )
    }
    
    func extractBylineFromDom(from html: String) -> String? {
        let patterns = [
            "<[^>]+(?:class|itemprop)=[\"'][^\"']*(?:author|byline|article-author)[^\"']*[\"'][^>]*>([^<]+)</",
            "<a[^>]+rel=[\"']author[\"'][^>]*>([^<]+)</a>"
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: (html as NSString).length)) {
                let author = (html as NSString).substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                if author.count > 2 && author.count < 80 && !author.lowercased().contains("http") {
                    return author
                }
            }
        }
        return nil
    }
    
    // MARK: - Multi-Candidate Scoring Readability Heuristics
    
    private struct ContainerCandidate {
        let openingTag: String
        let content: String
    }
    
    private func extractMainContent(from html: String) -> String {
        // Step 1: Remove heavy noise tags
        var cleaned = html
        let stripTags = ["script", "style", "noscript", "iframe", "svg", "nav", "header", "footer", "form", "aside"]
        for tag in stripTags {
            let pattern = "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>"
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        
        // Step 2: Evaluate candidate semantic containers with balanced tag depth
        let candidates = findContainerCandidates(in: cleaned)
        var bestCandidate = ""
        var bestScore = 0
        
        for candidate in candidates {
            let cleanContainer = sanitizeBodyHtml(candidate.content)
            let charCount = cleanContainer.count
            let pCount = countOccurrences(of: "<p>", in: cleanContainer)
            let commaCount = countOccurrences(of: ",", in: cleanContainer)
            
            var semanticBonus = 0
            let lowerTag = candidate.openingTag.lowercased()
            if lowerTag.contains("articlebody") {
                semanticBonus = 1500
            } else if lowerTag.hasPrefix("<article") {
                semanticBonus = 500
            } else if lowerTag.contains("text-content") || lowerTag.contains("articlecontent") {
                semanticBonus = 400
            }
            
            let score = charCount + (pCount * 60) + (commaCount * 5) + semanticBonus
            if score > bestScore && (charCount > 80 || pCount >= 1) {
                bestScore = score
                bestCandidate = cleanContainer
            }
        }
        
        if !bestCandidate.isEmpty {
            return bestCandidate
        }
        
        // Step 3: Extract paragraphs fallback
        return extractParagraphBlocks(from: cleaned)
    }
    
    private func findMatchingClosingTag(in html: String, openTagStart: Int, tagName: String) -> Int? {
        let openPrefix = "<\(tagName)"
        let closePrefix = "</\(tagName)>"
        var depth = 1
        
        let startIdx = html.index(html.startIndex, offsetBy: openTagStart)
        guard let openCloseRange = html.range(of: ">", range: startIdx..<html.endIndex) else {
            return nil
        }
        var searchIndex = openCloseRange.upperBound
        
        while searchIndex < html.endIndex && depth > 0 {
            let nextOpen = html.range(of: openPrefix, options: .caseInsensitive, range: searchIndex..<html.endIndex)
            let nextClose = html.range(of: closePrefix, options: .caseInsensitive, range: searchIndex..<html.endIndex)
            
            guard let close = nextClose else { return nil }
            
            if let open = nextOpen, open.lowerBound < close.lowerBound {
                let charAfter = open.upperBound < html.endIndex ? html[open.upperBound] : Character(" ")
                if charAfter.isWhitespace || charAfter == ">" || charAfter == "/" {
                    if let closeBracket = html.range(of: ">", range: open.upperBound..<html.endIndex) {
                        let prevChar = html[html.index(before: closeBracket.lowerBound)]
                        if prevChar != "/" {
                            depth += 1
                        }
                        searchIndex = closeBracket.upperBound
                        continue
                    }
                }
                searchIndex = open.upperBound
                continue
            } else {
                depth -= 1
                if depth == 0 {
                    return html.distance(from: html.startIndex, to: close.lowerBound)
                }
                searchIndex = close.upperBound
            }
        }
        return nil
    }
    
    private func findContainerCandidates(in html: String) -> [ContainerCandidate] {
        var candidates: [ContainerCandidate] = []
        let junkClasses = [
            "marketing", "upnext", "up-next", "card-marketing", "teaser", "related",
            "recommendation", "social", "ad-", "advertisement", "newsletter", "promo", "comment"
        ]
        
        // 1. Check <article> tags
        var idx = 0
        while idx < html.count {
            guard let range = html.range(of: "<article", options: .caseInsensitive, range: html.index(html.startIndex, offsetBy: idx)..<html.endIndex) else { break }
            let openIdx = html.distance(from: html.startIndex, to: range.lowerBound)
            let charAfter = range.upperBound < html.endIndex ? html[range.upperBound] : Character(" ")
            if !charAfter.isWhitespace && charAfter != ">" {
                idx = openIdx + 8
                continue
            }
            guard let openCloseRange = html.range(of: ">", range: range.upperBound..<html.endIndex) else { break }
            let openCloseIdx = html.distance(from: html.startIndex, to: openCloseRange.lowerBound)
            if let closeIdx = findMatchingClosingTag(in: html, openTagStart: openIdx, tagName: "article") {
                let contentStart = html.index(html.startIndex, offsetBy: openCloseIdx + 1)
                let contentEnd = html.index(html.startIndex, offsetBy: closeIdx)
                let tagHeader = String(html[range.lowerBound...openCloseRange.lowerBound])
                candidates.append(ContainerCandidate(openingTag: tagHeader, content: String(html[contentStart..<contentEnd])))
                idx = closeIdx + 10
            } else {
                idx = openCloseIdx + 1
            }
        }
        
        // 2. Check <main> tags
        idx = 0
        while idx < html.count {
            guard let range = html.range(of: "<main", options: .caseInsensitive, range: html.index(html.startIndex, offsetBy: idx)..<html.endIndex) else { break }
            let openIdx = html.distance(from: html.startIndex, to: range.lowerBound)
            let charAfter = range.upperBound < html.endIndex ? html[range.upperBound] : Character(" ")
            if !charAfter.isWhitespace && charAfter != ">" {
                idx = openIdx + 5
                continue
            }
            guard let openCloseRange = html.range(of: ">", range: range.upperBound..<html.endIndex) else { break }
            let openCloseIdx = html.distance(from: html.startIndex, to: openCloseRange.lowerBound)
            if let closeIdx = findMatchingClosingTag(in: html, openTagStart: openIdx, tagName: "main") {
                let contentStart = html.index(html.startIndex, offsetBy: openCloseIdx + 1)
                let contentEnd = html.index(html.startIndex, offsetBy: closeIdx)
                let tagHeader = String(html[range.lowerBound...openCloseRange.lowerBound])
                candidates.append(ContainerCandidate(openingTag: tagHeader, content: String(html[contentStart..<contentEnd])))
                idx = closeIdx + 7
            } else {
                idx = openCloseIdx + 1
            }
        }
        
        // 3. Check <div> tags with candidate classes or itemprop="articleBody"
        idx = 0
        let candidateKeywords = [
            "articlebody", "article-body", "article_body", "entry-content",
            "post-content", "story-body", "article__content", "article-text",
            "articlecontent", "single__content", "single-content", "single-content-content", "wp-block-post-content",
            "pagebuilder-article", "text-content", "articleintro",
            "article-intro", "content-article", "story-content", "articledetail"
        ]
        
        while idx < html.count {
            guard let range = html.range(of: "<div", options: .caseInsensitive, range: html.index(html.startIndex, offsetBy: idx)..<html.endIndex) else { break }
            let openIdx = html.distance(from: html.startIndex, to: range.lowerBound)
            guard let openCloseRange = html.range(of: ">", range: range.upperBound..<html.endIndex) else { break }
            let openCloseIdx = html.distance(from: html.startIndex, to: openCloseRange.lowerBound)
            let tagHeader = String(html[range.lowerBound...openCloseRange.lowerBound]).lowercased()
            
            let isCandidate = candidateKeywords.contains { tagHeader.contains($0) }
            let isJunk = junkClasses.contains { tagHeader.contains($0) }
            
            if isCandidate && !isJunk {
                if let closeIdx = findMatchingClosingTag(in: html, openTagStart: openIdx, tagName: "div") {
                    let contentStart = html.index(html.startIndex, offsetBy: openCloseIdx + 1)
                    let contentEnd = html.index(html.startIndex, offsetBy: closeIdx)
                    candidates.append(ContainerCandidate(openingTag: tagHeader, content: String(html[contentStart..<contentEnd])))
                    idx = closeIdx + 6
                    continue
                }
            }
            idx = openCloseIdx + 1
        }
        
        return candidates
    }
    
    private func countOccurrences(of substring: String, in string: String) -> Int {
        var count = 0
        var searchRange: Range<String.Index>?
        while let found = string.range(of: substring, options: .caseInsensitive, range: searchRange) {
            count += 1
            searchRange = found.upperBound..<string.endIndex
        }
        return count
    }
    
    private func extractParagraphBlocks(from html: String) -> String {
        let pattern = "<p[^>]*>([\\s\\S]*?)</p>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return "" }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        
        var paragraphs: [String] = []
        for match in matches {
            let pText = ns.substring(with: match.range(at: 1))
            let stripped = pText.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            if stripped.count > 30 {
                paragraphs.append("<p>\(pText)</p>")
            }
        }
        
        return paragraphs.joined(separator: "\n")
    }
    
    private func sanitizeBodyHtml(_ html: String) -> String {
        var clean = html
        // Remove class, style, id, and event handlers
        clean = clean.replacingOccurrences(of: "\\s*(?:class|style|id|onclick|onload|data-[\\w-]+)=[\"'][^\"']*[\"']", with: "", options: .regularExpression)
        // Remove comments
        clean = clean.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: "", options: .regularExpression)
        // Strip empty tags
        clean = clean.replacingOccurrences(of: "<(div|span|p|section)[^>]*>\\s*</\\1>", with: "", options: [.regularExpression, .caseInsensitive])
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - WinUI Parity: Featured Image Deduplication
    
    public func deduplicateFeaturedImage(content: String, featuredImage: String) -> String {
        guard !featuredImage.isEmpty else { return content }
        
        let pattern = "<img[^>]+src\\s*=\\s*[\"']([^\"']+)[\"'][^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return content }
        let ns = content as NSString
        
        guard let match = regex.firstMatch(in: content, range: NSRange(location: 0, length: ns.length)) else {
            return content
        }
        
        let foundSrc = ns.substring(with: match.range(at: 1))
        let s1 = normalizeImageUrl(foundSrc)
        let s2 = normalizeImageUrl(featuredImage)
        
        var shouldRemove = false
        if !s1.isEmpty && !s2.isEmpty {
            if s1.contains(s2) || s2.contains(s1) {
                shouldRemove = true
            } else if s1.count > 15 && s2.count > 15 {
                let f1 = s1.components(separatedBy: "/").last ?? ""
                let f2 = s2.components(separatedBy: "/").last ?? ""
                if !f1.isEmpty && f1.caseInsensitiveCompare(f2) == .orderedSame {
                    shouldRemove = true
                }
            }
        }
        
        if shouldRemove {
            var modified = ns.replacingCharacters(in: match.range, with: "")
            // Cleanup empty wrapper tags surrounding the image spot
            let cleanWrapperPattern = "<(?:figure|div|p)[^>]*>\\s*</(?:figure|div|p)>"
            modified = modified.replacingOccurrences(of: cleanWrapperPattern, with: "", options: [.regularExpression, .caseInsensitive])
            return modified.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return content
    }
    
    private func normalizeImageUrl(_ url: String) -> String {
        guard let u = URL(string: url) else { return url.lowercased() }
        let host = u.host?.lowercased() ?? ""
        let path = u.path.lowercased()
        return host + path
    }
    
    // MARK: - Medium Miro CDN Optimization
    
    public func optimizeMediumImagesInHtml(_ html: String) -> String {
        guard html.contains("miro.medium.com") else { return html }
        let pattern = "https://miro\\.medium\\.com/v2/resize:[^/]+(/format:[^/]+)?"
        return html.replacingOccurrences(of: pattern, with: "https://miro.medium.com/v2/resize:fit:800", options: .regularExpression)
    }
    
    // MARK: - WinUI Parity: Author Sanitization
    
    public func sanitizeAuthor(_ raw: String) -> String {
        var author = raw
        if let firstLine = author.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            author = firstLine
        }
        let junkPhrases = ["Social Links", "NavigationContributor", "Navigation", "See all articles"]
        for junk in junkPhrases {
            author = author.replacingOccurrences(of: junk, with: "", options: .caseInsensitive)
        }
        
        // Separate concatenated titles (e.g. "Jane DoeSenior Editor" -> "Jane Doe, Senior Editor")
        let titlePattern = "(?<=[a-z])\\s*(?<!,\\s)(Senior Editor|Executive Editor|Deals Editor|Managing Editor|Editor|Contributor|Freelance Writer|Freelance|Staff Writer|Staff|Writer|Journalist)"
        author = author.replacingOccurrences(of: titlePattern, with: ", $1", options: [.regularExpression, .caseInsensitive])
        
        author = author.trimmingCharacters(in: .whitespacesAndNewlines)
        author = author.trimmingCharacters(in: CharacterSet(charactersIn: ",.-|"))
        author = author.replacingOccurrences(of: "\\s+,", with: ",", options: .regularExpression)
        return author.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Meta Tag Extractors
    
    public func extractMetaContent(property: String, from html: String) -> String? {
        let pattern = "<meta[^>]+property=[\"']\(property)[\"'][^>]+content=[\"']([^\"']+)[\"'][^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = html as NSString
        if let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)) {
            return ns.substring(with: match.range(at: 1))
        }
        return nil
    }
    
    public func extractMetaContent(name: String, from html: String) -> String? {
        let pattern = "<meta[^>]+name=[\"']\(name)[\"'][^>]+content=[\"']([^\"']+)[\"'][^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = html as NSString
        if let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)) {
            return ns.substring(with: match.range(at: 1))
        }
        return nil
    }
    
    public func extractTitleTag(from html: String) -> String? {
        let pattern = "<title[^>]*>([\\s\\S]*?)</title>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = html as NSString
        if let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)) {
            return ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
    
    public func decodeHtmlEntities(_ str: String) -> String {
        var decoded = str
        let entities = [
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&#8216;", "'"),
            ("&#8217;", "'"),
            ("&#8220;", "\""),
            ("&#8221;", "\""),
            ("&#8211;", "–"),
            ("&#8212;", "—"),
            ("&nbsp;", " ")
        ]
        for (ent, val) in entities {
            decoded = decoded.replacingOccurrences(of: ent, with: val)
        }
        return decoded
    }
}

#if canImport(WebKit)
public struct MediumExtractionResult: Sendable {
    public let article: NewsArticle
    public let isPaywallTruncated: Bool
    
    public init(article: NewsArticle, isPaywallTruncated: Bool) {
        self.article = article
        self.isPaywallTruncated = isPaywallTruncated
    }
}

/// Headless WebKit engine hosting Mozilla Readability for distraction-free DOM parsing.
@MainActor
public final class HeadlessReadabilityParser: NSObject, WKNavigationDelegate {
    public static let shared = HeadlessReadabilityParser()
    
    #if os(macOS)
    public static let mediumSafariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Safari/605.1.15"
    #else
    public static let mediumSafariUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Mobile/15E148 Safari/604.1"
    #endif
    
    private var webView: WKWebView?
    
    override init() {
        super.init()
    }
    
    private func getOrCreateWebView() -> WKWebView {
        if let existing = self.webView {
            return existing
        }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs
        let wv = WKWebView(frame: .zero, configuration: config)
        self.webView = wv
        return wv
    }
    
    public func parse(
        html: String,
        urlString: String,
        baseArticle: NewsArticle?,
        extractor: ArticleExtractor
    ) async -> NewsArticle? {
        guard let url = URL(string: urlString) else { return nil }
        
        // Strip scripts and noscripts before loading into headless WebKit
        // to prevent third-party cookie banners, trackers, and ad scripts from executing
        // and injecting synthetic cookie consent tables into the DOM.
        var sanitizedHtml = html.replacingOccurrences(
            of: "<script[^>]*>[\\s\\S]*?</script>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        sanitizedHtml = sanitizedHtml.replacingOccurrences(
            of: "<noscript[^>]*>[\\s\\S]*?</noscript>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        
        let wv = getOrCreateWebView()
        wv.loadHTMLString(sanitizedHtml, baseURL: url)
        
        // Give WebKit a short tick to begin parsing the HTML string
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        let startTime = Date()
        while wv.isLoading && Date().timeIntervalSince(startTime) < 2.5 {
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        
        let js = """
        \(ReadabilityScript.js)
        
        (function() {
            try {
                var doc = document.cloneNode(true);
                
                // 1. Check for explicit high-confidence article body containers FIRST
                var explicitSelectors = [
                    "[itemprop='articleBody']",
                    ".text-content",
                    ".articleContent",
                    ".single__content",
                    ".entry-content",
                    ".article-body",
                    ".wp-block-post-content",
                    ".pagebuilder-article",
                    ".articlecontent",
                    ".articleIntro"
                ];
                
                var explicitNode = null;
                for (var s = 0; s < explicitSelectors.length; s++) {
                    var found = doc.querySelector(explicitSelectors[s]);
                    if (found && (found.textContent || "").trim().length > 100) {
                        explicitNode = found;
                        break;
                    }
                }
                
                if (explicitNode) {
                    // Clean junk child elements inside the explicit container
                    var junkChildren = explicitNode.querySelectorAll("script, style, iframe, form, [id*='adocean'], [class*='adocean'], .recommendations, .bong, .social, .utils");
                    for (var j = 0; j < junkChildren.length; j++) {
                        junkChildren[j].remove();
                    }
                    
                    var h1 = doc.querySelector("h1");
                    var artTitle = h1 ? h1.textContent.trim() : (doc.title || "");
                    var bylineEl = doc.querySelector("[rel='author'], [itemprop='author'], .author, .byline, .author-name, .article-author");
                    var nameEl = bylineEl ? bylineEl.querySelector("[itemprop='name']") : null;
                    var artByline = (nameEl || bylineEl) ? (nameEl || bylineEl).textContent.trim() : "";
                    
                    return JSON.stringify({
                        title: artTitle,
                        byline: artByline,
                        excerpt: "",
                        content: explicitNode.innerHTML || ""
                    });
                }
                
                // 2. Prune tracking, navigation, cookie consent, and advertising noise containers
                var junkSelectors = [
                    "header", "#header", ".header", "nav", ".menu", ".band",
                    "footer", "#footer", ".footer",
                    "[id*='cookie']", "[class*='cookie']",
                    "[id*='consent']", "[class*='consent']",
                    "[id*='gdpr']", "[class*='gdpr']",
                    ".card-marketing", ".cookie-script",
                    "[id*='adocean']", "[class*='adocean']",
                    ".recommendations", ".recomandam",
                    "[class*='newsletter']", "[id*='newsletter']",
                    "[class*='subscribe']", "[id*='subscribe']",
                    ".box-article-newsletter", ".card-articles",
                    ".bong", ".carousel", ".crossFooterBody"
                ];
                junkSelectors.forEach(function(sel) {
                    try {
                        var els = doc.querySelectorAll(sel);
                        for (var i = 0; i < els.length; i++) {
                            els[i].remove();
                        }
                    } catch(e) {}
                });
                
                // Prune standalone recommendation or newsletter boxes that don't contain article body paragraphs
                try {
                    var boxes = doc.querySelectorAll(".box, aside");
                    for (var b = 0; b < boxes.length; b++) {
                        var box = boxes[b];
                        var txt = (box.textContent || "").toLowerCase();
                        if ((txt.includes("recomand") || txt.includes("newsletter") || txt.includes("abonează-te")) && 
                            box.querySelectorAll("p").length < 3) {
                            box.remove();
                        }
                    }
                } catch(e) {}
                
                var article = new Readability(doc, { charThreshold: 40, keepClasses: true }).parse();
                if (article && article.content) {
                    var finalContent = article.content;
                    try {
                        var tempDiv = doc.createElement("div");
                        tempDiv.innerHTML = article.content;
                        var explicitBody = tempDiv.querySelector("[itemprop='articleBody'], .articleContent, .single__content, .entry-content, .article-body, .wp-block-post-content, .articlecontent, .text-content, .articleIntro");
                        if (explicitBody && explicitBody.textContent.trim().length > 40) {
                            finalContent = explicitBody.innerHTML;
                        }
                    } catch(e) {}
                    
                    return JSON.stringify({
                        title: article.title || "",
                        byline: article.byline || "",
                        excerpt: article.excerpt || "",
                        content: finalContent || ""
                    });
                }
            } catch(e) {
                return JSON.stringify({ error: e.toString() });
            }
            return null;
        })();
        """
        
        do {
            let evalResult = try await wv.evaluateJavaScript(js)
            if let str = evalResult as? String {
                if str.contains("\"error\"") {
                    print("[HeadlessReadabilityParser] JS Error: \(str)")
                }
            } else {
                print("[HeadlessReadabilityParser] evalResult not a string: \(String(describing: evalResult))")
            }
            guard let jsonStr = evalResult as? String,
                  let data = jsonStr.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  var content = dict["content"] as? String,
                  content.count > 50 else {
                return nil
            }
            
            let readTitle = dict["title"] as? String
            let readByline = dict["byline"] as? String
            let readExcerpt = dict["excerpt"] as? String
            
            let ogTitle = extractor.extractMetaContent(property: "og:title", from: html) ?? extractor.extractTitleTag(from: html)
            let ogImage = extractor.extractMetaContent(property: "og:image", from: html) ?? baseArticle?.imageUrl
            let ogDescription = extractor.extractMetaContent(property: "og:description", from: html) ?? readExcerpt ?? baseArticle?.description
            
            var author: String? = nil
            var rawAuthor = extractor.extractMetaContent(name: "author", from: html)
            if rawAuthor == nil || rawAuthor?.contains("://") == true {
                rawAuthor = extractor.extractMetaContent(property: "article:author", from: html)
            }
            if rawAuthor?.contains("://") == true {
                rawAuthor = nil
            }
            if rawAuthor == nil {
                rawAuthor = extractor.extractMetaContent(property: "og:article:author", from: html)
            }
            if rawAuthor == nil, let b = readByline?.trimmingCharacters(in: .whitespacesAndNewlines), !b.isEmpty {
                rawAuthor = b
            }
            if rawAuthor == nil {
                rawAuthor = extractor.extractBylineFromDom(from: html)
            }
            author = rawAuthor ?? baseArticle?.author
            if let rawAuthor = author {
                author = extractor.sanitizeAuthor(rawAuthor)
            }
            
            // Deduplicate featured image
            if let featImg = ogImage, !content.isEmpty {
                content = extractor.deduplicateFeaturedImage(content: content, featuredImage: featImg)
            }
            
            // Clean empty wrapper tags or empty links left after image deduplication
            content = content.replacingOccurrences(of: "<a[^>]*>\\s*</a>", with: "", options: .regularExpression)
            content = content.replacingOccurrences(of: "<p>\\s*</p>", with: "", options: .regularExpression)
            content = content.replacingOccurrences(of: "(?:<hr\\s*/?>\\s*)+$", with: "", options: [.regularExpression, .caseInsensitive])
            content = content.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Optimize Miro Medium CDN images inside the content
            content = extractor.optimizeMediumImagesInHtml(content)
            
            let cleanReadTitle = (readTitle?.isEmpty == false) ? readTitle : nil
            let title = cleanReadTitle ?? ogTitle ?? baseArticle?.title ?? "Untitled Article"
            
            return NewsArticle(
                id: baseArticle?.id ?? urlString,
                title: extractor.decodeHtmlEntities(title),
                link: urlString,
                publishDate: baseArticle?.publishDate ?? Date(),
                imageUrl: ogImage,
                description: extractor.decodeHtmlEntities(ogDescription ?? ""),
                content: content,
                author: author,
                publicationName: baseArticle?.publicationName,
                publicationIconUrl: baseArticle?.publicationIconUrl,
                category: baseArticle?.category
            )
        } catch {
            print("[ArticleExtractor] Readability evaluation error: \(error)")
            return nil
        }
    }
    
    // MARK: - Medium WebKit Extraction & Scraper (WinUI Parity)
    
    private final class NavigationObserver: NSObject, WKNavigationDelegate {
        var onFinished: (@MainActor (Bool) -> Void)?
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                self.onFinished?(true)
                self.onFinished = nil
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                self.onFinished?(false)
                self.onFinished = nil
            }
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                self.onFinished?(false)
                self.onFinished = nil
            }
        }
    }
    
    private func createAuthenticatedWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 900), configuration: config)
        wv.customUserAgent = Self.mediumSafariUserAgent
        return wv
    }
    
    /// Purges poisoned host-only subdomain cookies (e.g. `malshikay.medium.com` shadowing `.medium.com`)
    /// and ensures authenticated parent cookies (`uid`, `sid`) apply across `medium.com` and `*.medium.com`.
    public func sanitizeMediumCookies() async {
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        let allCookies = await cookieStore.allCookies()
        
        let hasValidRootUid = allCookies.contains { cookie in
            let d = cookie.domain.lowercased()
            return (d == "medium.com" || d == ".medium.com") &&
                   cookie.name == "uid" &&
                   ArticleExtractor.isAuthenticatedMediumUid(cookie.value)
        }
        
        var hasDotMediumUid = false
        var hasDotMediumSid = false
        for cookie in allCookies where cookie.domain.lowercased() == ".medium.com" {
            if cookie.name == "uid" && ArticleExtractor.isAuthenticatedMediumUid(cookie.value) {
                hasDotMediumUid = true
            } else if cookie.name == "sid" && !cookie.value.isEmpty {
                hasDotMediumSid = true
            }
        }
        
        for cookie in allCookies {
            if ArticleExtractor.shouldDeleteMediumCookie(cookie, hasValidRootUid: hasValidRootUid) {
                await cookieStore.deleteCookie(cookie)
                continue
            }
            
            // If an authenticated cookie was stored on host-only `medium.com`, mirror it to `.medium.com`
            // so custom author subdomains (`*.medium.com`) receive it automatically.
            if cookie.domain.lowercased() == "medium.com" {
                let shouldPromoteUid = (cookie.name == "uid" && ArticleExtractor.isAuthenticatedMediumUid(cookie.value) && !hasDotMediumUid)
                let shouldPromoteSid = (cookie.name == "sid" && !cookie.value.isEmpty && !hasDotMediumSid)
                if shouldPromoteUid || shouldPromoteSid {
                    var props = cookie.properties ?? [:]
                    props[.domain] = ".medium.com"
                    if let wildcardCookie = HTTPCookie(properties: props) {
                        await cookieStore.setCookie(wildcardCookie)
                    }
                }
            }
        }
    }
    
    /// Checks whether `WKWebsiteDataStore.default()` currently holds a valid signed-in Medium session.
    public func hasAuthenticatedMediumSession() async -> Bool {
        await sanitizeMediumCookies()
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        return ArticleExtractor.hasAuthenticatedMediumCookies(cookies)
    }
    
    private func loadURL(_ targetUrl: URL, in wv: WKWebView, observer: NavigationObserver, timeoutNanoseconds: UInt64 = 12_000_000_000) async -> Bool {
        await withCheckedContinuation { continuation in
            var finished = false
            observer.onFinished = { success in
                if !finished {
                    finished = true
                    continuation.resume(returning: success)
                }
            }
            wv.load(URLRequest(url: targetUrl))
            
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                if !finished {
                    finished = true
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    public func extractMediumArticle(
        url: URL,
        baseArticle: NewsArticle?,
        extractor: ArticleExtractor
    ) async -> NewsArticle? {
        await extractMediumArticleDetailed(url: url, baseArticle: baseArticle, extractor: extractor)?.article
    }
    
    public func extractMediumArticleDetailed(
        url: URL,
        baseArticle: NewsArticle?,
        extractor: ArticleExtractor
    ) async -> MediumExtractionResult? {
        await sanitizeMediumCookies()
        let hasActiveCookies = ArticleExtractor.hasAuthenticatedMediumCookies(
            await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        )
        
        let wv = createAuthenticatedWebView()
        let observer = NavigationObserver()
        wv.navigationDelegate = observer
        
        _ = await loadURL(url, in: wv, observer: observer)
        
        let cleanupScript = """
        (function(){
            var selectors=['#cmp-app-container','.cookie-banner','#cookie-consent','.gdpr-modal',
            '[class*="cookie"]','[id*="cookie"]','[class*="consent"]','[class*="paywall"]',
            '[id*="consent"]','[class*="overlay"]','[id*="piano"]'];
            selectors.forEach(function(s){
                document.querySelectorAll(s).forEach(function(e){
                    if(e.tagName==='ARTICLE'||e.tagName==='MAIN'||e.tagName==='SECTION') return;
                    if(e.querySelectorAll('p').length>=2||(e.innerText||'').length>300) return;
                    e.remove();
                });
            });
            var upsells=['.meteredContentUpsell','[data-testid="paywall-dialog"]','[data-testid="upgrade-banner"]','[data-testid="postPaywallBanner"]'];
            upsells.forEach(function(s){
                document.querySelectorAll(s).forEach(function(e){
                    if(e.querySelectorAll('p').length<2&&(e.innerText||'').length<300) e.remove();
                });
            });
            document.body.style.overflow='auto';document.documentElement.style.overflow='auto';
            var main=document.querySelector('article')||document.querySelector('main')||document.querySelector('[role="main"]');
            if(main){main.style.display='block';main.style.visibility='visible';main.style.opacity='1';}
        })()
        """
        
        let stateCheckJs = """
        (function() {
            var s = window.__APOLLO_STATE__ || {};
            var rq = s.ROOT_QUERY || {};
            var hasViewer = Boolean(rq.viewer);
            var postKey = Object.keys(s).find(function(k) { return k.indexOf('Post:') === 0; });
            var post = postKey ? s[postKey] : null;
            var postId = (post && post.id) ? String(post.id) : (postKey ? postKey.slice(5) : '');
            var isLocked = post ? Boolean(post.isLocked) : false;
            var expectedWords = (post && typeof post.wordCount === 'number') ? post.wordCount : 0;
            var apolloParagraphs = Object.keys(s).filter(function(k) { return k.indexOf('Paragraph:') === 0; }).length;
            var el = document.querySelector('article') || document.querySelector('main') || document.body;
            var text = (el && el.innerText) ? el.innerText.trim() : '';
            var words = text ? text.split(/\\s+/).length : 0;
            var domBlocks = el ? el.querySelectorAll('p, h1, h2, h3, h4, pre, li, blockquote').length : 0;
            return JSON.stringify({
                hasViewer: hasViewer,
                postId: postId,
                isLocked: isLocked,
                expectedWords: expectedWords,
                apolloParagraphs: apolloParagraphs,
                domWords: words,
                domChars: text.length,
                domBlocks: domBlocks
            });
        })()
        """
        
        let extractScript = """
        (function(){
            var selectors='article, main, [itemprop="articleBody"], .article-body, .article-content, .post-content, .entry-content, .layout-article-body';
            var el=document.querySelector(selectors);
            if(el && el.innerText && el.innerText.length > 200) {
                var clone = el.cloneNode(true);
                var junk = clone.querySelectorAll(
                    'button, [data-testid*="clap"], [data-testid*="response"], .responsesStream, [data-testid="postSidebar"], ' +
                    '[data-testid="authorPhoto"], img[src*="resize:fill:48:48"], img[src*="resize:fill:64:64"], img[src*="resize:fill:88:88"]'
                );
                junk.forEach(function(j){ j.remove(); });
                clone.querySelectorAll('div, aside, section').forEach(function(box) {
                    if (box.tagName === 'ARTICLE') return;
                    var txt = (box.innerText || '').trim();
                    if (txt.length > 0 && txt.length < 360 && box.querySelectorAll('p').length <= 3) {
                        var lower = txt.toLowerCase();
                        if (lower.indexOf('stories in your inbox') !== -1 ||
                            (lower.indexOf('stories in ') !== -1 && lower.indexOf('inbox') !== -1) ||
                            lower.indexOf('get updates from this writer') !== -1) {
                            box.remove();
                        }
                    }
                });
                var headMeta = Array.from(document.querySelectorAll('title, meta[property^="og:"], meta[name="author"], meta[property*="author"]'))
                    .map(function(m){ return m.outerHTML; }).join('');
                return '<html><head><meta charset="utf-8"/>' + headMeta + '</head><body>' + clone.outerHTML + '</body></html>';
            }
            if(document.body && document.body.innerText && document.body.innerText.length > 500) {
                return document.documentElement.outerHTML;
            }
            return null;
        })()
        """
        
        var extractedHtml: String? = nil
        var isPaywallTruncated = false
        var didAttemptIdentityHandshake = false
        var lastChars = 0
        var stableCount = 0
        
        for iteration in 0..<12 {
            try? await Task.sleep(nanoseconds: iteration == 0 ? 500_000_000 : 400_000_000)
            
            var hasViewer = false
            var postId = ""
            var isLocked = false
            var expectedWords = 0
            var apolloParagraphs = 0
            var domWords = 0
            var domChars = 0
            var domBlocks = 0
            
            if let stateJson = try? await wv.evaluateJavaScript(stateCheckJs) as? String,
               let stateData = stateJson.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: stateData) as? [String: Any] {
                hasViewer = (dict["hasViewer"] as? Bool) ?? false
                postId = (dict["postId"] as? String) ?? ""
                isLocked = (dict["isLocked"] as? Bool) ?? false
                expectedWords = (dict["expectedWords"] as? Int) ?? 0
                apolloParagraphs = (dict["apolloParagraphs"] as? Int) ?? 0
                domWords = (dict["domWords"] as? Int) ?? 0
                domChars = (dict["domChars"] as? Int) ?? 0
                domBlocks = (dict["domBlocks"] as? Int) ?? 0
            }
            
            // If user has valid `.medium.com` cookies, is visiting a custom publication domain where viewer
            // has not hydrated yet, route once through `medium.com/p/<postId>` / `global-identity-2` to attach session.
            if iteration == 0 && isLocked && !hasViewer && hasActiveCookies && !didAttemptIdentityHandshake {
                let currentHost = wv.url?.host?.lowercased() ?? url.host?.lowercased() ?? ""
                let isDirectMediumHost = currentHost == "medium.com" || currentHost == "www.medium.com"
                if !isDirectMediumHost && !postId.isEmpty, let canonicalPostUrl = URL(string: "https://medium.com/p/\(postId)") {
                    didAttemptIdentityHandshake = true
                    _ = await loadURL(canonicalPostUrl, in: wv, observer: observer, timeoutNanoseconds: 10_000_000_000)
                    continue
                }
            }
            
            // Fast exit when all expected words/paragraphs are already rendered in the DOM
            let hasFullExpectedWords = expectedWords > 0 && domWords >= Int(Double(expectedWords) * 0.68)
            let hasAllUnlockedBlocks = !isLocked && apolloParagraphs > 0 && domBlocks >= Int(Double(apolloParagraphs) * 0.85) && domChars > 350
            
            if hasFullExpectedWords || hasAllUnlockedBlocks {
                // Quick scroll sweep to ensure lazy `<figure>` images hydrate their full-res `src`
                _ = try? await wv.evaluateJavaScript("window.scrollTo(0, document.body.scrollHeight / 2);")
                try? await Task.sleep(nanoseconds: 120_000_000)
                _ = try? await wv.evaluateJavaScript("window.scrollTo(0, document.body.scrollHeight);")
                try? await Task.sleep(nanoseconds: 120_000_000)
                _ = try? await wv.evaluateJavaScript("window.scrollTo(0, 0);")
                _ = try? await wv.evaluateJavaScript(cleanupScript)
                
                if let result = try? await wv.evaluateJavaScript(extractScript) as? String, !result.isEmpty {
                    extractedHtml = result
                    isPaywallTruncated = false
                    break
                }
            }
            
            // Fast exit when article is member-locked and Medium has no signed-in viewer:
            // Medium's server never transmitted the locked paragraphs, so don't stall for 10 seconds.
            if iteration >= 1 && isLocked && !hasViewer && (expectedWords == 0 || domWords < Int(Double(expectedWords) * 0.55)) {
                _ = try? await wv.evaluateJavaScript(cleanupScript)
                if let result = try? await wv.evaluateJavaScript(extractScript) as? String, !result.isEmpty {
                    extractedHtml = result
                }
                isPaywallTruncated = true
                break
            }
            
            // Progressive scroll hydration when signed in and waiting for GraphQL/React member body
            if iteration % 3 == 0 {
                _ = try? await wv.evaluateJavaScript("window.scrollTo(0, document.body.scrollHeight / 2);")
            } else if iteration % 3 == 1 {
                _ = try? await wv.evaluateJavaScript("window.scrollTo(0, document.body.scrollHeight);")
            } else {
                _ = try? await wv.evaluateJavaScript("window.scrollTo(0, 0);")
            }
            
            if domChars > 300 {
                if domChars == lastChars {
                    stableCount += 1
                } else {
                    stableCount = 0
                    lastChars = domChars
                }
                
                if (domChars > 3000 && stableCount >= 2) || (iteration >= 6 && stableCount >= 2) {
                    _ = try? await wv.evaluateJavaScript(cleanupScript)
                    if let result = try? await wv.evaluateJavaScript(extractScript) as? String, !result.isEmpty {
                        extractedHtml = result
                        if isLocked && expectedWords > 250 && domWords < Int(Double(expectedWords) * 0.55) {
                            isPaywallTruncated = true
                        }
                        break
                    }
                }
            }
        }
        
        if extractedHtml == nil {
            _ = try? await wv.evaluateJavaScript(cleanupScript)
            if let result = try? await wv.evaluateJavaScript(extractScript) as? String, !result.isEmpty {
                extractedHtml = result
            } else if let fullHtml = try? await wv.evaluateJavaScript("document.documentElement.outerHTML") as? String, fullHtml.count > 500 {
                extractedHtml = fullHtml
            }
        }
        
        guard let rawHtml = extractedHtml else { return nil }
        let html = ArticleExtractor.stripMediumTrackingAndNoise(rawHtml)
        
        // Attempt parsing with Mozilla Readability engine
        if var readabilityArticle = await self.parse(html: html, urlString: url.absoluteString, baseArticle: baseArticle, extractor: extractor),
           let content = readabilityArticle.content, content.count > 300 {
            readabilityArticle.content = ArticleExtractor.stripMediumTrackingAndNoise(content)
            return MediumExtractionResult(article: readabilityArticle, isPaywallTruncated: isPaywallTruncated)
        }
        
        // Fallback: Use multi-candidate heuristic container extractor on the sanitized DOM
        var fallbackArticle = extractor.parseHtml(html, url: url.absoluteString, baseArticle: baseArticle)
        if let content = fallbackArticle.content {
            fallbackArticle.content = ArticleExtractor.stripMediumTrackingAndNoise(content)
        }
        return MediumExtractionResult(article: fallbackArticle, isPaywallTruncated: isPaywallTruncated)
    }
    
    public func scrapeMediumReadingList(urlString: String) async -> [NewsArticle] {
        guard let url = URL(string: urlString) else { return [] }
        await sanitizeMediumCookies()
        let wv = createAuthenticatedWebView()
        let observer = NavigationObserver()
        wv.navigationDelegate = observer
        
        _ = await withCheckedContinuation { continuation in
            var finished = false
            observer.onFinished = { success in
                if !finished {
                    finished = true
                    continuation.resume(returning: success)
                }
            }
            wv.load(URLRequest(url: url))
            
            Task {
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                await MainActor.run {
                    if !finished {
                        finished = true
                        continuation.resume(returning: false)
                    }
                }
            }
        }
        
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        
        for _ in 0..<6 {
            if let count = try? await wv.evaluateJavaScript("document.querySelectorAll('article').length") as? Int, count > 0 {
                break
            }
            try? await Task.sleep(nanoseconds: 600_000_000)
        }
        
        let script = """
        (function() {
            var articles = [];
            var items = document.querySelectorAll('article');
            
            function getStoryUrl(item) {
                var titleEl = item.querySelector('h2');
                if (titleEl) {
                    var a = titleEl.querySelector('a') || titleEl.closest('a');
                    if (a && a.href) return a.href;
                }
                var links = item.querySelectorAll('a');
                for (var i = 0; i < links.length; i++) {
                    var href = links[i].href;
                    if (!href) continue;
                    var urlObj;
                    try { urlObj = new URL(href); } catch(e) { continue; }
                    var pathname = urlObj.pathname;
                    if (pathname.includes('/tag/') || pathname.includes('/tagged/') || pathname.includes('/me') || pathname === '/' || pathname === '') continue;
                    var parts = pathname.split('/').filter(Boolean);
                    if (parts.length === 1 && parts[0].startsWith('@')) continue;
                    if (pathname.includes('/p/') || parts.length >= 2 || (parts.length === 1 && !parts[0].startsWith('@'))) return href;
                }
                return '';
            }

            function getAuthorInfo(item) {
                var links = item.querySelectorAll('a');
                for (var i = 0; i < links.length; i++) {
                    var href = links[i].href;
                    if (!href) continue;
                    try {
                        var urlObj = new URL(href);
                        if (urlObj.hostname === 'medium.com' && urlObj.pathname.startsWith('/@')) {
                            var parts = urlObj.pathname.split('/').filter(Boolean);
                            if (parts.length === 1) {
                                return { url: href, name: (links[i].innerText || links[i].textContent || '').trim() };
                            }
                        }
                        if (urlObj.hostname.endsWith('.medium.com') && urlObj.hostname.split('.').length === 3) {
                            var sub = urlObj.hostname.split('.')[0];
                            if (sub !== 'www' && sub !== 'api' && urlObj.pathname === '/') {
                                return { url: href, name: (links[i].innerText || links[i].textContent || '').trim() };
                            }
                        }
                    } catch(e) {}
                }
                return null;
            }

            items.forEach(function(item) {
                try {
                    var titleEl = item.querySelector('h2');
                    var title = titleEl ? titleEl.innerText : '';
                    var storyUrl = getStoryUrl(item);
                    var authorInfo = getAuthorInfo(item);
                    var authorName = authorInfo ? authorInfo.name : '';
                    var authorUrl = authorInfo ? authorInfo.url : '';
                    if (!authorName) {
                        var authorEl = item.querySelector('p');
                        if (authorEl) authorName = authorEl.innerText;
                    }
                    var description = '';
                    var h3El = item.querySelector('h3');
                    if (h3El) {
                        description = h3El.innerText;
                    } else {
                        var pElements = item.querySelectorAll('p');
                        pElements.forEach(function(p) {
                            var txt = p.innerText || '';
                            if (txt.length > 30 && !txt.includes('min read') && !txt.includes('member-only')) {
                                description = txt;
                            }
                        });
                    }
                    var img = item.querySelector('img');
                    var imageUrl = img ? img.src : '';
                    title = title.trim();
                    authorName = (authorName || '').trim();
                    description = (description || '').trim();
                    if (title && storyUrl) {
                        articles.push({
                            title: title,
                            url: storyUrl,
                            author: authorName || 'Medium',
                            authorUrl: authorUrl || '',
                            imageUrl: imageUrl,
                            description: description
                        });
                    }
                } catch(e) {}
            });
            return JSON.stringify(articles);
        })();
        """
        
        guard let jsonString = try? await wv.evaluateJavaScript(script) as? String,
              let data = jsonString.data(using: .utf8),
              let scraped = try? JSONDecoder().decode([ScrapedMediumItem].self, from: data),
              !scraped.isEmpty else {
            return []
        }
        
        return scraped.map { item in
            var author = item.author
            var pubName = "Medium"
            if let range = author.range(of: " in ") {
                pubName = String(author[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                author = String(author[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            let optImg = Self.optimizeMediumImageUrl(item.imageUrl)
            return NewsArticle(
                id: UUID().uuidString,
                title: item.title,
                link: item.url,
                publishDate: Date(),
                imageUrl: optImg.isEmpty ? nil : optImg,
                description: item.description.isEmpty ? "Author: \(author). Read this story on Medium." : item.description,
                content: nil,
                author: author,
                publicationName: pubName,
                publicationIconUrl: "https://www.google.com/s2/favicons?domain=medium.com&sz=64",
                category: .tech
            )
        }
    }
    
    nonisolated public static func optimizeMediumImageUrl(_ url: String) -> String {
        guard url.contains("miro.medium.com") else { return url }
        let pattern = "v2/resize:[^/]+(/format:[^/]+)?"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return url }
        let range = NSRange(location: 0, length: (url as NSString).length)
        return regex.stringByReplacingMatches(in: url, range: range, withTemplate: "v2/resize:fit:800")
    }
    
    // MARK: - Substack Helper & Inbox Methods
    
    public func hasAuthenticatedSubstackSession() async -> Bool {
        let cookies = await getAuthenticatedSubstackCookies()
        return ArticleExtractor.hasAuthenticatedSubstackCookies(cookies)
    }
    
    public func getAuthenticatedSubstackCookies() async -> [HTTPCookie] {
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        let allCookies = await cookieStore.allCookies()
        return allCookies.filter { c in
            let d = c.domain.lowercased()
            return d == "substack.com" || d.hasSuffix(".substack.com")
        }
    }
    
    public func scrapeSubstackInbox() async -> [NewsArticle] {
        let wv = createAuthenticatedWebView()
        let observer = NavigationObserver()
        wv.navigationDelegate = observer
        
        guard let inboxUrl = URL(string: "https://substack.com/inbox") else { return [] }
        
        _ = await withCheckedContinuation { continuation in
            var finished = false
            observer.onFinished = { success in
                if !finished {
                    finished = true
                    continuation.resume(returning: success)
                }
            }
            wv.load(URLRequest(url: inboxUrl))
            
            Task {
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                await MainActor.run {
                    if !finished {
                        finished = true
                        continuation.resume(returning: false)
                    }
                }
            }
        }
        
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        
        for _ in 0..<6 {
            if let count = try? await wv.evaluateJavaScript("document.querySelectorAll('article, [data-testid*=\"post\"], a[href*=\"/p/\"]').length") as? Int, count > 0 {
                break
            }
            try? await Task.sleep(nanoseconds: 600_000_000)
        }
        
        let script = """
        (function() {
            var items = [];
            var seen = {};
            var cards = document.querySelectorAll('article, [data-testid*=\"post\"], div[class*=\"reader-post\"]');
            if (cards.length === 0) {
                cards = document.querySelectorAll('a[href*=\"/p/\"]');
            }
            
            cards.forEach(function(card) {
                var a = card.tagName === 'A' ? card : (card.querySelector('a[href*=\"/p/\"]') || card.querySelector('a'));
                if (!a || !a.href) return;
                var href = a.href;
                if (seen[href]) return;
                seen[href] = true;
                
                var titleEl = card.querySelector('h1, h2, h3, [class*=\"title\"]') || a;
                var title = titleEl ? (titleEl.innerText || '').trim() : '';
                if (!title) return;
                
                var pubEl = card.querySelector('[class*=\"publication\"], [class*=\"pub-name\"], a[href*=\"substack.com\"]:not([href*=\"/p/\"])');
                var pubName = pubEl ? (pubEl.innerText || '').trim() : '';
                
                var authorEl = card.querySelector('[class*=\"byline\"], [class*=\"author\"]');
                var author = authorEl ? (authorEl.innerText || '').trim() : '';
                
                var descEl = card.querySelector('p, [class*=\"subtitle\"], [class*=\"description\"]');
                var desc = descEl ? (descEl.innerText || '').trim() : '';
                
                var imgEl = card.querySelector('img');
                var imgUrl = imgEl ? (imgEl.src || imgEl.getAttribute('data-src') || '') : '';
                
                items.push({
                    title: title,
                    url: href,
                    publication: pubName,
                    author: author,
                    imageUrl: imgUrl,
                    description: desc,
                    date: null
                });
            });
            return JSON.stringify(items);
        })()
        """
        
        guard let jsonStr = try? await wv.evaluateJavaScript(script) as? String,
              let data = jsonStr.data(using: .utf8),
              let scraped = try? JSONDecoder().decode([ScrapedSubstackItem].self, from: data),
              !scraped.isEmpty else {
            return []
        }
        
        return scraped.map { item in
            let optImg = Self.optimizeSubstackImageUrl(item.imageUrl)
            return NewsArticle(
                id: item.url,
                title: item.title,
                link: item.url,
                publishDate: Date(),
                imageUrl: optImg.isEmpty ? nil : optImg,
                description: item.description.isEmpty ? "Substack Post from \(item.publication.isEmpty ? "Substack" : item.publication)" : item.description,
                content: nil,
                author: item.author.isEmpty ? nil : item.author,
                publicationName: item.publication.isEmpty ? "Substack" : item.publication,
                publicationIconUrl: "https://substack.com/favicon.ico",
                category: .tech
            )
        }
    }
    
    public func extractSubstackArticle(
        url: URL,
        baseArticle: NewsArticle?,
        extractor: ArticleExtractor
    ) async -> NewsArticle? {
        let wv = createAuthenticatedWebView()
        let observer = NavigationObserver()
        wv.navigationDelegate = observer
        
        _ = await withCheckedContinuation { continuation in
            var finished = false
            observer.onFinished = { success in
                if !finished {
                    finished = true
                    continuation.resume(returning: success)
                }
            }
            wv.load(URLRequest(url: url))
            
            Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                await MainActor.run {
                    if !finished {
                        finished = true
                        continuation.resume(returning: false)
                    }
                }
            }
        }
        
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        
        let cleanupScript = """
        (function() {
            var junk = document.querySelectorAll('.subscription-widget-wrap, .subscribe-widget, .post-footer, .like-button-container, .share-dialog, .comment-widget');
            junk.forEach(function(el) { el.remove(); });
            
            var article = document.querySelector('article, [itemprop="articleBody"], .post, .entry-content, main');
            if (article && (article.innerText || '').length > 200) {
                return article.outerHTML;
            }
            return document.body ? document.body.innerHTML : null;
        })()
        """
        
        guard let extractedHtml = try? await wv.evaluateJavaScript(cleanupScript) as? String,
              extractedHtml.count > 200 else {
            return nil
        }
        
        let cleanedHtml = ArticleExtractor.stripSubstackTrackingAndNoise(extractedHtml)
        if let parsed = await parse(html: cleanedHtml, urlString: url.absoluteString, baseArticle: baseArticle, extractor: extractor) {
            var art = parsed
            if let content = art.content {
                art.content = ArticleExtractor.stripSubstackTrackingAndNoise(content)
            }
            return art
        }
        
        if var fallback = baseArticle {
            fallback.content = cleanedHtml
            return fallback
        }
        return nil
    }
    
    nonisolated public static func optimizeSubstackImageUrl(_ url: String) -> String {
        guard url.contains("substackcdn.com") || url.contains("substack-post-media") else { return url }
        if url.contains("w_") {
            let pattern = "w_\\d+"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return url }
            let range = NSRange(location: 0, length: (url as NSString).length)
            return regex.stringByReplacingMatches(in: url, range: range, withTemplate: "w_1200")
        }
        return url
    }
}

public struct ScrapedSubstackItem: Codable, Sendable {
    public let title: String
    public let url: String
    public let publication: String
    public let author: String
    public let imageUrl: String
    public let description: String
    public let date: String?
}
#endif

// MARK: - Insecure HTTP to HTTPS Auto-Upgrade Delegate (ATS Compliance)
private final class SecureRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        var upgradedRequest = request
        if let url = request.url, url.scheme?.lowercased() == "http" {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
            components?.scheme = "https"
            if let upgradedUrl = components?.url {
                upgradedRequest.url = upgradedUrl
            }
        }
        completionHandler(upgradedRequest)
    }
}
