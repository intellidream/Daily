import Foundation

/// Parser for WordPress REST API posts (`/wp-json/wp/v2/posts?_embed`).
public final class WpJsonParser: @unchecked Sendable {
    
    private let feed: FeedSource
    
    public init(feed: FeedSource) {
        self.feed = feed
    }
    
    public func parse(jsonData: Data) -> [NewsArticle] {
        guard let jsonArray = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
            return []
        }
        
        var articles: [NewsArticle] = []
        let isoFormatter = ISO8601DateFormatter()
        let fallbackFormatter = DateFormatter()
        fallbackFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        
        for post in jsonArray {
            let titleObj = post["title"] as? [String: Any]
            var title = titleObj?["rendered"] as? String ?? "No Title"
            title = decodeHtmlEntities(title)
            
            let link = post["link"] as? String ?? ""
            let dateStr = post["date"] as? String ?? ""
            let date = isoFormatter.date(from: dateStr) ?? fallbackFormatter.date(from: dateStr) ?? Date()
            
            let contentObj = post["content"] as? [String: Any]
            let content = contentObj?["rendered"] as? String
            
            let excerptObj = post["excerpt"] as? [String: Any]
            let excerpt = excerptObj?["rendered"] as? String
            
            var cleanDesc = stripHtmlTags(excerpt ?? "")
            if cleanDesc.isEmpty && content != nil {
                let contentClean = stripHtmlTags(content ?? "")
                cleanDesc = contentClean.count > 280 ? String(contentClean.prefix(280)) + "..." : contentClean
            }
            
            var authorName: String?
            var imageUrl: String?
            
            if let embedded = post["_embedded"] as? [String: Any] {
                // Author
                if let authors = embedded["author"] as? [[String: Any]], let firstAuthor = authors.first {
                    authorName = firstAuthor["name"] as? String
                }
                
                // Featured Media
                if let mediaList = embedded["wp:featuredmedia"] as? [[String: Any]], let firstMedia = mediaList.first {
                    imageUrl = firstMedia["source_url"] as? String
                    if let details = firstMedia["media_details"] as? [String: Any],
                       let sizes = details["sizes"] as? [String: Any],
                       let medium = sizes["medium"] as? [String: Any],
                       let mediumUrl = medium["source_url"] as? String {
                        imageUrl = mediumUrl
                    }
                }
            }
            
            articles.append(NewsArticle(
                id: link.isEmpty ? UUID().uuidString : link,
                title: title,
                link: link,
                publishDate: date,
                imageUrl: imageUrl ?? feed.iconUrl,
                description: cleanDesc,
                content: content,
                author: authorName,
                publicationName: feed.name,
                publicationIconUrl: feed.iconUrl,
                category: feed.category
            ))
        }
        
        return articles
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
}
