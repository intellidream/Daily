import Foundation
#if canImport(WebKit)
import WebKit
#endif

/// Distraction-free article extraction engine providing parity with WinUI,
/// powered by an in-memory Mozilla Readability engine over headless WebKit
/// with a multi-candidate scoring heuristic fallback.
public final class ArticleExtractor: @unchecked Sendable {
    
    public static let shared = ArticleExtractor()
    
    private let urlSession: URLSession
    
    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9,ro;q=0.8"
        ]
        self.urlSession = URLSession(configuration: config)
    }
    
    /// Fetches the raw HTML from the article URL and extracts the clean article content.
    public func extract(from urlString: String, baseArticle: NewsArticle? = nil) async throws -> NewsArticle {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
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
        ) {
            return readabilityArticle
        }
        #endif
        
        return parseHtml(html, url: urlString, baseArticle: baseArticle)
    }
    
    /// Synchronously parses an HTML string to extract readable article content using heuristic scoring.
    public func parseHtml(_ html: String, url: String, baseArticle: NewsArticle? = nil) -> NewsArticle {
        let ogTitle = extractMetaContent(property: "og:title", from: html) ?? extractTitleTag(from: html)
        let ogImage = extractMetaContent(property: "og:image", from: html) ?? baseArticle?.imageUrl
        let ogDescription = extractMetaContent(property: "og:description", from: html) ?? baseArticle?.description
        var author = extractMetaContent(name: "author", from: html) ?? baseArticle?.author
        
        // Sanitize author (WinUI parity)
        if let rawAuthor = author {
            author = sanitizeAuthor(rawAuthor)
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
    
    // MARK: - Multi-Candidate Scoring Readability Heuristics
    
    private func extractMainContent(from html: String) -> String {
        // Step 1: Remove heavy noise tags
        var cleaned = html
        let stripTags = ["script", "style", "noscript", "iframe", "svg", "nav", "header", "footer", "form", "aside"]
        for tag in stripTags {
            let pattern = "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>"
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        
        // Step 2: Evaluate candidate semantic containers
        let articlePatterns = [
            "<article[^>]*>([\\s\\S]*?)</article>",
            "<div[^>]+itemprop=[\"']articleBody[\"'][^>]*>([\\s\\S]*?)</div>",
            "<div[^>]+class=[\"'][^\"']*(?:article[-_]body|entry[-_]content|post[-_]content|story[-_]body|article__content|article-text)[^\"']*[\"'][^>]*>([\\s\\S]*?)</div>",
            "<main[^>]*>([\\s\\S]*?)</main>"
        ]
        
        var bestCandidate = ""
        var bestScore = 0
        
        let junkClassPatterns = [
            "marketing", "upnext", "up-next", "card-marketing", "teaser", "related",
            "recommendation", "social", "ad-", "advertisement", "newsletter", "promo", "comment"
        ]
        
        for pattern in articlePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let ns = cleaned as NSString
                let matches = regex.matches(in: cleaned, range: NSRange(location: 0, length: ns.length))
                
                for match in matches {
                    let fullTag = ns.substring(with: match.range)
                    let openingTag = fullTag.components(separatedBy: ">").first?.lowercased() ?? ""
                    
                    // Skip marketing, upnext, ad containers
                    var isJunk = false
                    for junk in junkClassPatterns {
                        if openingTag.contains(junk) {
                            isJunk = true
                            break
                        }
                    }
                    if isJunk { continue }
                    
                    let containerHtml = ns.substring(with: match.range(at: 1))
                    let cleanContainer = sanitizeBodyHtml(containerHtml)
                    
                    // Score candidate
                    let charCount = cleanContainer.count
                    let pCount = countOccurrences(of: "<p>", in: cleanContainer)
                    let commaCount = countOccurrences(of: ",", in: cleanContainer)
                    let score = charCount + (pCount * 60) + (commaCount * 5)
                    
                    if score > bestScore && charCount > 300 {
                        bestScore = score
                        bestCandidate = cleanContainer
                    }
                }
            }
        }
        
        if !bestCandidate.isEmpty {
            return bestCandidate
        }
        
        // Step 3: Extract paragraphs fallback
        return extractParagraphBlocks(from: cleaned)
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
/// Headless WebKit engine hosting Mozilla Readability for distraction-free DOM parsing.
@MainActor
public final class HeadlessReadabilityParser: NSObject, WKNavigationDelegate {
    public static let shared = HeadlessReadabilityParser()
    
    private var webView: WKWebView?
    
    override init() {
        super.init()
    }
    
    private func getOrCreateWebView() -> WKWebView {
        if let existing = self.webView {
            return existing
        }
        let config = WKWebViewConfiguration()
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
        let wv = getOrCreateWebView()
        wv.loadHTMLString(html, baseURL: url)
        
        let startTime = Date()
        while wv.isLoading && Date().timeIntervalSince(startTime) < 2.5 {
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        
        let js = """
        \(ReadabilityScript.js)
        
        (function() {
            try {
                var doc = document.cloneNode(true);
                var article = new Readability(doc).parse();
                if (article && article.content) {
                    return JSON.stringify({
                        title: article.title || "",
                        byline: article.byline || "",
                        excerpt: article.excerpt || "",
                        content: article.content || ""
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
            guard let jsonStr = evalResult as? String,
                  let data = jsonStr.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  var content = dict["content"] as? String,
                  content.count > 150 else {
                return nil
            }
            
            let readTitle = dict["title"] as? String
            let readByline = dict["byline"] as? String
            let readExcerpt = dict["excerpt"] as? String
            
            let ogTitle = extractor.extractMetaContent(property: "og:title", from: html) ?? extractor.extractTitleTag(from: html)
            let ogImage = extractor.extractMetaContent(property: "og:image", from: html) ?? baseArticle?.imageUrl
            let ogDescription = extractor.extractMetaContent(property: "og:description", from: html) ?? readExcerpt ?? baseArticle?.description
            
            var author = readByline ?? extractor.extractMetaContent(name: "author", from: html) ?? baseArticle?.author
            if let rawAuthor = author {
                author = extractor.sanitizeAuthor(rawAuthor)
            }
            
            // Deduplicate featured image
            if let featImg = ogImage, !content.isEmpty {
                content = extractor.deduplicateFeaturedImage(content: content, featuredImage: featImg)
            }
            
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
            print("[ArticleExtractor] Readability evaluation error: \\(error)")
            return nil
        }
    }
}
#endif
