import Foundation

/// Robust multi-flavor XML parser supporting RSS 2.0, Atom, and RDF feeds.
public final class FeedParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    
    private var articles: [NewsArticle] = []
    private var currentElement = ""
    private var currentTitle = ""
    private var currentLink = ""
    private var currentDescription = ""
    private var currentContentEncoded = ""
    private var currentAuthor = ""
    private var currentPubDateStr = ""
    private var currentImageUrl: String?
    private var channelImageUrl: String?
    
    private var isInsideItem = false
    private var isInsideChannelImage = false
    
    private let feed: FeedSource
    
    public init(feed: FeedSource) {
        self.feed = feed
        super.init()
    }
    
    /// Parses raw XML data into an array of NewsArticle items.
    public func parse(xmlData: Data) -> [NewsArticle] {
        articles = []
        
        // Sanitize XML string (e.g. naked ampersands)
        if let xmlString = String(data: xmlData, encoding: .utf8) ?? String(data: xmlData, encoding: .isoLatin1) {
            let sanitized = sanitizeXml(xmlString)
            if let sanitizedData = sanitized.data(using: .utf8) {
                let parser = XMLParser(data: sanitizedData)
                parser.delegate = self
                parser.shouldProcessNamespaces = true
                parser.shouldReportNamespacePrefixes = true
                parser.parse()
            }
        }
        
        // Fallback: If XMLParser returned 0 items due to malformed XML, use regex parser
        if articles.isEmpty, let xmlString = String(data: xmlData, encoding: .utf8) ?? String(data: xmlData, encoding: .isoLatin1) {
            articles = parseUsingRegex(xmlString: xmlString)
        }
        
        return articles
    }
    
    // MARK: - XMLParserDelegate
    
    public func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = elementName.lowercased()
        currentElement = name
        
        if name == "item" || name == "entry" {
            isInsideItem = true
            currentTitle = ""
            currentLink = ""
            currentDescription = ""
            currentContentEncoded = ""
            currentAuthor = ""
            currentPubDateStr = ""
            currentImageUrl = nil
            return
        }
        
        if !isInsideItem {
            if name == "image" || name == "logo" || name == "icon" {
                isInsideChannelImage = true
            }
            return
        }
        
        // Atom link element: <link href="..." rel="alternate"/>
        if name == "link" {
            if let href = attributeDict["href"] {
                let rel = attributeDict["rel"]?.lowercased()
                if rel == "enclosure" && attributeDict["type"]?.hasPrefix("image/") == true {
                    currentImageUrl = href
                } else if rel == "alternate" || rel == nil || currentLink.isEmpty {
                    currentLink = href
                }
            }
        }
        
        // Media content or thumbnail: <media:content url="...">
        if name == "content" || name == "thumbnail" {
            if let url = attributeDict["url"], isLikelyImage(url: url) {
                if currentImageUrl == nil {
                    currentImageUrl = url
                }
            }
        }
        
        // RSS enclosure: <enclosure url="..." type="image/..."/>
        if name == "enclosure" {
            if let url = attributeDict["url"] {
                let type = attributeDict["type"]?.lowercased() ?? ""
                if type.isEmpty || type.hasPrefix("image/") || isLikelyImage(url: url) {
                    if currentImageUrl == nil {
                        currentImageUrl = url
                    }
                }
            }
        }
    }
    
    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInsideChannelImage && channelImageUrl == nil && currentElement == "url" {
            channelImageUrl = (channelImageUrl ?? "") + string
            return
        }
        
        guard isInsideItem else { return }
        
        switch currentElement {
        case "title":
            currentTitle += string
        case "link":
            if currentLink.isEmpty {
                currentLink += string.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        case "description", "summary":
            currentDescription += string
        case "encoded", "content":
            currentContentEncoded += string
        case "pubdate", "published", "updated", "date":
            currentPubDateStr += string
        case "creator", "author", "name":
            currentAuthor += string
        default:
            break
        }
    }
    
    public func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let str = String(data: CDATABlock, encoding: .utf8) else { return }
        guard isInsideItem else { return }
        
        switch currentElement {
        case "title":
            currentTitle += str
        case "description", "summary":
            currentDescription += str
        case "encoded", "content":
            currentContentEncoded += str
        case "creator", "author", "name":
            currentAuthor += str
        default:
            break
        }
    }
    
    public func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.lowercased()
        
        if name == "image" || name == "logo" || name == "icon" {
            isInsideChannelImage = false
            return
        }
        
        if name == "item" || name == "entry" {
            isInsideItem = false
            
            let title = decodeHtmlEntities(currentTitle.trimmingCharacters(in: .whitespacesAndNewlines))
            let link = currentLink.trimmingCharacters(in: .whitespacesAndNewlines)
            let date = parseDate(currentPubDateStr.trimmingCharacters(in: .whitespacesAndNewlines))
            
            // Extract image from description or content if not found in tags
            if currentImageUrl == nil {
                currentImageUrl = extractFirstImage(from: currentContentEncoded) ?? extractFirstImage(from: currentDescription)
            }
            
            let finalImageUrl = optimizeMediumImageUrl(currentImageUrl ?? channelImageUrl ?? feed.iconUrl)
            
            // Clean description snippet
            var cleanDesc = stripHtmlTags(currentDescription)
            if cleanDesc.isEmpty && !currentContentEncoded.isEmpty {
                let contentClean = stripHtmlTags(currentContentEncoded)
                cleanDesc = contentClean.count > 280 ? String(contentClean.prefix(280)) + "..." : contentClean
            }
            
            // Format Author & Publication
            var authorName = currentAuthor.trimmingCharacters(in: .whitespacesAndNewlines)
            var pubName = feed.name
            if let inRange = authorName.range(of: " in ") {
                pubName = String(authorName[inRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                authorName = String(authorName[..<inRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            let article = NewsArticle(
                id: link.isEmpty ? UUID().uuidString : link,
                title: title.isEmpty ? "No Title" : title,
                link: link,
                publishDate: date,
                imageUrl: finalImageUrl,
                description: cleanDesc,
                content: currentContentEncoded.isEmpty ? currentDescription : currentContentEncoded,
                author: authorName.isEmpty ? nil : authorName,
                publicationName: pubName,
                publicationIconUrl: feed.iconUrl,
                category: feed.category
            )
            
            articles.append(article)
        }
    }
    
    // MARK: - Regex Fallback Parser
    
    private func parseUsingRegex(xmlString: String) -> [NewsArticle] {
        var results: [NewsArticle] = []
        let itemPattern = "<(?:item|entry)[^>]*>([\\s\\S]*?)</(?:item|entry)>"
        guard let itemRegex = try? NSRegularExpression(pattern: itemPattern, options: .caseInsensitive) else { return results }
        
        let nsString = xmlString as NSString
        let matches = itemRegex.matches(in: xmlString, range: NSRange(location: 0, length: nsString.length))
        
        for match in matches {
            let itemContent = nsString.substring(with: match.range(at: 1))
            
            let title = extractTagValue(tag: "title", from: itemContent)
            var link = extractTagValue(tag: "link", from: itemContent)
            if link.isEmpty {
                link = extractAttribute(attribute: "href", tag: "link", from: itemContent)
            }
            let desc = extractTagValue(tag: "description", from: itemContent)
            let content = extractTagValue(tag: "content:encoded", from: itemContent).isEmpty
                ? extractTagValue(tag: "content", from: itemContent)
                : extractTagValue(tag: "content:encoded", from: itemContent)
            let pubDate = extractTagValue(tag: "pubDate", from: itemContent).isEmpty
                ? extractTagValue(tag: "published", from: itemContent)
                : extractTagValue(tag: "pubDate", from: itemContent)
            let author = extractTagValue(tag: "dc:creator", from: itemContent).isEmpty
                ? extractTagValue(tag: "author", from: itemContent)
                : extractTagValue(tag: "dc:creator", from: itemContent)
            
            var imageUrl = extractAttribute(attribute: "url", tag: "media:content", from: itemContent)
            if imageUrl.isEmpty {
                imageUrl = extractAttribute(attribute: "url", tag: "enclosure", from: itemContent)
            }
            if imageUrl.isEmpty {
                imageUrl = extractFirstImage(from: content) ?? extractFirstImage(from: desc) ?? ""
            }
            
            var cleanDesc = stripHtmlTags(desc)
            if cleanDesc.isEmpty && !content.isEmpty {
                let contentClean = stripHtmlTags(content)
                cleanDesc = contentClean.count > 280 ? String(contentClean.prefix(280)) + "..." : contentClean
            }
            
            results.append(NewsArticle(
                id: link.isEmpty ? UUID().uuidString : link,
                title: decodeHtmlEntities(title),
                link: link,
                publishDate: parseDate(pubDate),
                imageUrl: optimizeMediumImageUrl(imageUrl.isEmpty ? feed.iconUrl : imageUrl),
                description: cleanDesc,
                content: content.isEmpty ? desc : content,
                author: author.isEmpty ? nil : author,
                publicationName: feed.name,
                publicationIconUrl: feed.iconUrl,
                category: feed.category
            ))
        }
        
        return results
    }
    
    // MARK: - Helpers
    
    private func sanitizeXml(_ xml: String) -> String {
        // Replace & with &amp; only if not followed by valid entity
        let pattern = "&(?!(?:amp|lt|gt|quot|apos|#\\d+|#[xX][a-fA-F0-9]+);)"
        return xml.replacingOccurrences(of: pattern, with: "&amp;", options: .regularExpression)
    }
    
    private func isLikelyImage(url: String) -> Bool {
        let lower = url.lowercased()
        return lower.contains(".jpg") || lower.contains(".jpeg") || lower.contains(".png") ||
               lower.contains(".webp") || lower.contains(".gif") || lower.contains("image") || lower.contains("miro.medium.com")
    }
    
    private func extractFirstImage(from html: String) -> String? {
        let pattern = #"<img[^>]+src\s*=\s*["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = html as NSString
        guard let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: match.range(at: 1))
    }
    
    private func extractTagValue(tag: String, from xml: String) -> String {
        let pattern = "<\(tag)[^>]*>(?:<!\\[CDATA\\[([\\s\\S]*?)\\]\\]>|([\\s\\S]*?))</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return "" }
        let ns = xml as NSString
        guard let match = regex.firstMatch(in: xml, range: NSRange(location: 0, length: ns.length)) else { return "" }
        if match.range(at: 1).location != NSNotFound {
            return ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if match.range(at: 2).location != NSNotFound {
            return ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }
    
    private func extractAttribute(attribute: String, tag: String, from xml: String) -> String {
        let pattern = "<\(tag)[^>]*\(attribute)\\s*=\\s*[\"']([^\"']+)[\"'][^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return "" }
        let ns = xml as NSString
        guard let match = regex.firstMatch(in: xml, range: NSRange(location: 0, length: ns.length)) else { return "" }
        return ns.substring(with: match.range(at: 1))
    }
    
    private func parseDate(_ str: String) -> Date {
        guard !str.isEmpty else { return Date() }
        
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd HH:mm:ss",
            "EEE, dd MMM yyyy HH:mm zzz"
        ]
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for f in formats {
            formatter.dateFormat = f
            if let date = formatter.date(from: str) {
                return date
            }
        }
        
        if let iso = ISO8601DateFormatter().date(from: str) {
            return iso
        }
        
        return Date()
    }
    
    private func stripHtmlTags(_ str: String) -> String {
        var clean = str
        clean = clean.replacingOccurrences(of: "</p>", with: " ", options: .caseInsensitive)
        clean = clean.replacingOccurrences(of: "<br>", with: " ", options: .caseInsensitive)
        clean = clean.replacingOccurrences(of: "<br/>", with: " ", options: .caseInsensitive)
        clean = clean.replacingOccurrences(of: "<br />", with: " ", options: .caseInsensitive)
        clean = clean.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        clean = decodeHtmlEntities(clean)
        clean = clean.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func decodeHtmlEntities(_ str: String) -> String {
        var decoded = str
        let entities = [
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&nbsp;", " ")
        ]
        for (ent, val) in entities {
            decoded = decoded.replacingOccurrences(of: ent, with: val)
        }
        
        // Handle decimal numeric entities: &#539;
        if let regex = try? NSRegularExpression(pattern: "&#(\\d+);") {
            let ns = decoded as NSString
            let matches = regex.matches(in: decoded, range: NSRange(location: 0, length: ns.length)).reversed()
            var mod = decoded
            for m in matches {
                let numStr = ns.substring(with: m.range(at: 1))
                if let code = UInt32(numStr), let scalar = UnicodeScalar(code) {
                    if let targetRange = Range(m.range, in: mod) {
                        mod.replaceSubrange(targetRange, with: String(scalar))
                    }
                }
            }
            decoded = mod
        }
        
        // Handle hex numeric entities: &#x21b;
        if let regex = try? NSRegularExpression(pattern: "&#[xX]([0-9a-fA-F]+);") {
            let ns = decoded as NSString
            let matches = regex.matches(in: decoded, range: NSRange(location: 0, length: ns.length)).reversed()
            var mod = decoded
            for m in matches {
                let hexStr = ns.substring(with: m.range(at: 1))
                if let code = UInt32(hexStr, radix: 16), let scalar = UnicodeScalar(code) {
                    if let targetRange = Range(m.range, in: mod) {
                        mod.replaceSubrange(targetRange, with: String(scalar))
                    }
                }
            }
            decoded = mod
        }
        
        return decoded
    }
    
    private func optimizeMediumImageUrl(_ url: String) -> String {
        guard url.contains("miro.medium.com") else { return url }
        let pattern = "v2/resize:[^/]+(/format:[^/]+)?"
        return url.replacingOccurrences(of: pattern, with: "v2/resize:fit:800", options: .regularExpression)
    }
}
