import Foundation

public enum FeedType: String, Codable, Sendable {
    case rss
    case wpJson
}

public enum FeedCategory: String, CaseIterable, Codable, Sendable {
    case all
    case local
    case markets
    case world
    case tech
    case coding
    case space
    case other
    
    public var displayName: String {
        switch self {
        case .all: return "All News"
        case .local: return "🇷🇴 Local"
        case .markets: return "📈 Markets"
        case .world: return "🌍 World"
        case .tech: return "💡 Tech"
        case .coding: return "💻 Coding"
        case .space: return "🚀 Space"
        case .other: return "📰 Other"
        }
    }
    
    public var systemIcon: String {
        switch self {
        case .all: return "newspaper"
        case .local: return "mappin.and.ellipse"
        case .markets: return "chart.line.uptrend.xyaxis"
        case .world: return "globe.europe.africa.fill"
        case .tech: return "cpu"
        case .coding: return "chevron.left.forwardslash.chevron.right"
        case .space: return "sparkles"
        case .other: return "tray.full"
        }
    }
}

public struct FeedSource: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var name: String
    public var url: String
    public var iconUrl: String
    public var type: FeedType
    public var category: FeedCategory
    public var displayOrder: Int
    
    public init(
        id: String = UUID().uuidString,
        name: String,
        url: String,
        iconUrl: String = "",
        type: FeedType = .rss,
        category: FeedCategory = .tech,
        displayOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.iconUrl = iconUrl.isEmpty ? "https://www.google.com/s2/favicons?domain=\(URL(string: url)?.host ?? "rss.com")&sz=64" : iconUrl
        self.type = type
        self.category = category
        self.displayOrder = displayOrder
    }
}

public struct NewsArticle: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var title: String
    public var link: String
    public var publishDate: Date
    public var imageUrl: String?
    public var description: String?
    public var content: String?
    public var author: String?
    public var publicationName: String?
    public var publicationIconUrl: String?
    public var category: FeedCategory?
    
    public init(
        id: String? = nil,
        title: String,
        link: String,
        publishDate: Date = Date(),
        imageUrl: String? = nil,
        description: String? = nil,
        content: String? = nil,
        author: String? = nil,
        publicationName: String? = nil,
        publicationIconUrl: String? = nil,
        category: FeedCategory? = nil
    ) {
        self.id = id ?? link
        self.title = title
        self.link = link
        self.publishDate = publishDate
        self.imageUrl = imageUrl
        self.description = description
        self.content = content
        self.author = author
        self.publicationName = publicationName
        self.publicationIconUrl = publicationIconUrl
        self.category = category
    }
    
    public var isMediumItem: Bool {
        publicationName?.contains("Medium") == true || link.contains("medium.com")
    }
    
    public var relativeTimeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: publishDate, relativeTo: Date())
    }
}

public enum SavedArticleType: String, Codable, Sendable {
    case readLater = "ReadLater"
    case favorite = "Favorite"
}

public struct SavedArticle: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var userId: String
    public var articleUrl: String
    public var title: String
    public var imageUrl: String?
    public var description: String?
    public var author: String?
    public var publicationName: String
    public var publicationIconUrl: String?
    public var articleType: String
    public var articleDate: Date
    public var createdAt: Date
    public var updatedAt: Date?
    public var isDeleted: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case articleUrl = "article_url"
        case title
        case imageUrl = "image_url"
        case description
        case author
        case publicationName = "publication_name"
        case publicationIconUrl = "publication_icon_url"
        case articleType = "article_type"
        case articleDate = "article_date"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case isDeleted = "is_deleted"
    }
    
    public init(
        id: String,
        userId: String,
        articleUrl: String,
        title: String,
        imageUrl: String? = nil,
        description: String? = nil,
        author: String? = nil,
        publicationName: String,
        publicationIconUrl: String? = nil,
        articleType: SavedArticleType,
        articleDate: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        isDeleted: Bool = false
    ) {
        self.id = id
        self.userId = userId
        self.articleUrl = articleUrl
        self.title = title
        self.imageUrl = imageUrl
        self.description = description
        self.author = author
        self.publicationName = publicationName
        self.publicationIconUrl = publicationIconUrl
        self.articleType = articleType.rawValue
        self.articleDate = articleDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.userId = (try? container.decode(String.self, forKey: .userId)) ?? ""
        self.articleUrl = try container.decode(String.self, forKey: .articleUrl)
        self.title = (try? container.decode(String.self, forKey: .title)) ?? ""
        self.imageUrl = try? container.decodeIfPresent(String.self, forKey: .imageUrl)
        self.description = try? container.decodeIfPresent(String.self, forKey: .description)
        self.author = try? container.decodeIfPresent(String.self, forKey: .author)
        self.publicationName = (try? container.decode(String.self, forKey: .publicationName)) ?? "News"
        self.publicationIconUrl = try? container.decodeIfPresent(String.self, forKey: .publicationIconUrl)
        self.articleType = (try? container.decode(String.self, forKey: .articleType)) ?? SavedArticleType.readLater.rawValue
        
        if let d = try? container.decode(Date.self, forKey: .articleDate) {
            self.articleDate = d
        } else if let s = try? container.decode(String.self, forKey: .articleDate), let d = HabitDateParser.parse(s) {
            self.articleDate = d
        } else {
            self.articleDate = Date()
        }
        
        if let d = try? container.decode(Date.self, forKey: .createdAt) {
            self.createdAt = d
        } else if let s = try? container.decode(String.self, forKey: .createdAt), let d = HabitDateParser.parse(s) {
            self.createdAt = d
        } else {
            self.createdAt = Date()
        }
        
        if let d = try? container.decodeIfPresent(Date.self, forKey: .updatedAt) {
            self.updatedAt = d
        } else if let s = try? container.decodeIfPresent(String.self, forKey: .updatedAt), let d = HabitDateParser.parse(s) {
            self.updatedAt = d
        } else {
            self.updatedAt = nil
        }
        
        self.isDeleted = (try? container.decode(Bool.self, forKey: .isDeleted)) ?? false
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(articleUrl, forKey: .articleUrl)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(imageUrl, forKey: .imageUrl)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(author, forKey: .author)
        try container.encode(publicationName, forKey: .publicationName)
        try container.encodeIfPresent(publicationIconUrl, forKey: .publicationIconUrl)
        try container.encode(articleType, forKey: .articleType)
        
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try container.encode(f.string(from: articleDate), forKey: .articleDate)
        try container.encode(f.string(from: createdAt), forKey: .createdAt)
        if let u = updatedAt {
            try container.encode(f.string(from: u), forKey: .updatedAt)
        }
        try container.encode(isDeleted, forKey: .isDeleted)
    }
    
    public func toNewsArticle() -> NewsArticle {
        NewsArticle(
            id: articleUrl,
            title: title,
            link: articleUrl,
            publishDate: articleDate,
            imageUrl: imageUrl,
            description: description,
            author: author,
            publicationName: publicationName,
            publicationIconUrl: publicationIconUrl
        )
    }
}

public struct RssSubscription: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var userId: String
    public var name: String
    public var url: String
    public var iconUrl: String
    public var category: String
    public var displayOrder: Int
    public var createdAt: Date
    public var updatedAt: Date?
    public var isDeleted: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case url
        case iconUrl = "icon_url"
        case category
        case displayOrder = "display_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case isDeleted = "is_deleted"
    }
    
    public init(
        id: String,
        userId: String,
        name: String,
        url: String,
        iconUrl: String,
        category: String,
        displayOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        isDeleted: Bool = false
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.url = url
        self.iconUrl = iconUrl
        self.category = category
        self.displayOrder = displayOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.userId = (try? container.decode(String.self, forKey: .userId)) ?? ""
        self.name = (try? container.decode(String.self, forKey: .name)) ?? ""
        self.url = try container.decode(String.self, forKey: .url)
        self.iconUrl = (try? container.decode(String.self, forKey: .iconUrl)) ?? ""
        self.category = (try? container.decode(String.self, forKey: .category)) ?? "tech"
        self.displayOrder = (try? container.decode(Int.self, forKey: .displayOrder)) ?? 0
        
        if let d = try? container.decode(Date.self, forKey: .createdAt) {
            self.createdAt = d
        } else if let s = try? container.decode(String.self, forKey: .createdAt), let d = HabitDateParser.parse(s) {
            self.createdAt = d
        } else {
            self.createdAt = Date()
        }
        
        if let d = try? container.decodeIfPresent(Date.self, forKey: .updatedAt) {
            self.updatedAt = d
        } else if let s = try? container.decodeIfPresent(String.self, forKey: .updatedAt), let d = HabitDateParser.parse(s) {
            self.updatedAt = d
        } else {
            self.updatedAt = nil
        }
        
        self.isDeleted = (try? container.decode(Bool.self, forKey: .isDeleted)) ?? false
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(name, forKey: .name)
        try container.encode(url, forKey: .url)
        try container.encode(iconUrl, forKey: .iconUrl)
        try container.encode(category, forKey: .category)
        try container.encode(displayOrder, forKey: .displayOrder)
        
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try container.encode(f.string(from: createdAt), forKey: .createdAt)
        if let u = updatedAt {
            try container.encode(f.string(from: u), forKey: .updatedAt)
        }
        try container.encode(isDeleted, forKey: .isDeleted)
    }
    
    public func toFeedSource() -> FeedSource {
        let cat = FeedCategory(rawValue: category.lowercased()) ?? .tech
        let type: FeedType = url.contains("wp-json") ? .wpJson : .rss
        return FeedSource(
            id: id,
            name: name,
            url: url,
            iconUrl: iconUrl,
            type: type,
            category: cat,
            displayOrder: displayOrder
        )
    }
}

public struct FeedSearchResult: Identifiable, Hashable, Codable, Sendable {
    public var id: String { url }
    public var name: String
    public var url: String
    public var iconUrl: String
    public var website: String
    
    public init(name: String, url: String, iconUrl: String = "", website: String = "") {
        self.name = name
        self.url = url
        self.iconUrl = iconUrl
        self.website = website
    }
}
