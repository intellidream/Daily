import Foundation
import CryptoKit

// MARK: - Search Engines & URL Resolution

public enum PrismSearchEngine: String, Codable, CaseIterable, Sendable {
    case google = "google"
    case duckDuckGo = "duckduckgo"
    case brave = "brave"
    case perplexity = "perplexity"

    public var displayName: String {
        switch self {
        case .google: return "Google"
        case .duckDuckGo: return "DuckDuckGo"
        case .brave: return "Brave Search"
        case .perplexity: return "Perplexity AI"
        }
    }

    public var iconName: String {
        switch self {
        case .google: return "magnifyingglass.circle.fill"
        case .duckDuckGo: return "shield.lefthalf.filled"
        case .brave: return "flame.fill"
        case .perplexity: return "sparkles"
        }
    }

    public func searchURL(for query: String) -> URL? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        switch self {
        case .google:
            return URL(string: "https://www.google.com/search?q=\(encoded)")
        case .duckDuckGo:
            return URL(string: "https://duckduckgo.com/?q=\(encoded)")
        case .brave:
            return URL(string: "https://search.brave.com/search?q=\(encoded)")
        case .perplexity:
            return URL(string: "https://www.perplexity.ai/search?q=\(encoded)")
        }
    }

    /// Resolves raw Omnibox text into a safe navigable HTTPS/HTTP URL or search query URL.
    /// Strictly rejects dangerous non-web schemes (`javascript:`, `file:`, `data:`, `vbscript:`).
    public static func resolveOmniboxInput(_ rawInput: String, engine: PrismSearchEngine = .google) -> URL? {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()
        let blockedSchemes = ["javascript:", "data:", "file:", "vbscript:", "intent:", "ms-settings:"]
        for blocked in blockedSchemes {
            if lower.hasPrefix(blocked) { return nil }
        }

        if lower.hasPrefix("https://") || lower.hasPrefix("http://") {
            return URL(string: trimmed)
        }

        // Bare domain detection (no spaces, contains a dot with valid TLD or localhost)
        if !trimmed.contains(" ") && !trimmed.contains("\n") {
            if lower.hasPrefix("localhost") || lower.hasPrefix("127.0.0.1") {
                return URL(string: "http://\(trimmed)")
            }
            if let dotIndex = trimmed.firstIndex(of: "."),
               dotIndex != trimmed.startIndex,
               trimmed.index(after: dotIndex) < trimmed.endIndex {
                let candidate = "https://\(trimmed)"
                if let url = URL(string: candidate), let host = url.host, host.contains(".") {
                    return url
                }
            }
        }

        return engine.searchURL(for: trimmed)
    }

    public static func extractCleanDomain(from urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else {
            return urlString
        }
        if host.hasPrefix("www.") {
            return String(host.dropFirst(4))
        }
        return host
    }

    public static func faviconURLString(for urlString: String) -> String {
        let domain = extractCleanDomain(from: urlString)
        guard !domain.isEmpty else { return "" }
        return "https://www.google.com/s2/favicons?domain=\(domain)&sz=128"
    }
}

// MARK: - Prism Clip Types & Cloud Model

public enum PrismClipType: String, Codable, CaseIterable, Sendable {
    case link = "link"
    case quote = "quote"
    case image = "image"
    case aiSummary = "ai_summary"

    public var displayName: String {
        switch self {
        case .link: return "Links"
        case .quote: return "Quotes"
        case .image: return "Images"
        case .aiSummary: return "AI Notes"
        }
    }

    public var singularLabel: String {
        switch self {
        case .link: return "Link"
        case .quote: return "Quote"
        case .image: return "Image"
        case .aiSummary: return "AI Summary"
        }
    }

    public var iconName: String {
        switch self {
        case .link: return "link"
        case .quote: return "text.quote"
        case .image: return "photo.on.rectangle.angled"
        case .aiSummary: return "sparkles"
        }
    }

    public var accentHex: String {
        switch self {
        case .link: return "#00E5FF"
        case .quote: return "#FFB300"
        case .image: return "#10B981"
        case .aiSummary: return "#A855F7"
        }
    }
}

public struct PrismClip: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var userId: String?
    public var clipType: PrismClipType
    public var title: String
    public var sourceUrl: String
    public var domain: String
    public var contentText: String
    public var userNote: String
    public var tags: [String]
    public var previewImageUrl: String?
    public var storagePath: String?
    public var imageWidth: Int?
    public var imageHeight: Int?
    public var isFavorite: Bool
    public var isDeleted: Bool
    public var tagdosNoteId: UUID?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        userId: String? = nil,
        clipType: PrismClipType,
        title: String,
        sourceUrl: String,
        domain: String? = nil,
        contentText: String = "",
        userNote: String = "",
        tags: [String] = [],
        previewImageUrl: String? = nil,
        storagePath: String? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        isFavorite: Bool = false,
        isDeleted: Bool = false,
        tagdosNoteId: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.clipType = clipType
        self.title = title
        self.sourceUrl = sourceUrl
        self.domain = domain ?? PrismSearchEngine.extractCleanDomain(from: sourceUrl)
        self.contentText = contentText
        self.userNote = userNote
        self.tags = tags
        self.previewImageUrl = previewImageUrl
        self.storagePath = storagePath
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.isFavorite = isFavorite
        self.isDeleted = isDeleted
        self.tagdosNoteId = tagdosNoteId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case clipType = "clip_type"
        case title
        case sourceUrl = "source_url"
        case domain
        case contentText = "content_text"
        case userNote = "user_note"
        case tags
        case previewImageUrl = "preview_image_url"
        case storagePath = "storage_path"
        case imageWidth = "image_width"
        case imageHeight = "image_height"
        case isFavorite = "is_favorite"
        case isDeleted = "is_deleted"
        case tagdosNoteId = "tagdos_note_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Cloud-Synced Speed Dial Pinned Sites

public struct PrismPinnedSite: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var userId: String?
    public var title: String
    public var url: String
    public var domain: String
    public var iconUrl: String?
    public var displayOrder: Int
    public var isDeleted: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID? = nil,
        userId: String? = nil,
        title: String,
        url: String,
        domain: String? = nil,
        iconUrl: String? = nil,
        displayOrder: Int = 0,
        isDeleted: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        let resolvedDomain = domain ?? PrismSearchEngine.extractCleanDomain(from: url)
        self.id = id ?? Self.deterministicId(userId: userId ?? "local", url: url)
        self.userId = userId
        self.title = title
        self.url = url
        self.domain = resolvedDomain
        self.iconUrl = iconUrl ?? PrismSearchEngine.faviconURLString(for: url)
        self.displayOrder = displayOrder
        self.isDeleted = isDeleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case url
        case domain
        case iconUrl = "icon_url"
        case displayOrder = "display_order"
        case isDeleted = "is_deleted"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public static func deterministicId(userId: String, url: String) -> UUID {
        let normalized = "\(userId.lowercased()):prism_pin:\(url.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/ ")))"
        let digest = Insecure.MD5.hash(data: Data(normalized.utf8))
        let b = Array(digest)
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }

    public static func defaultStarterSites(userId: String? = nil) -> [PrismPinnedSite] {
        let uid = userId ?? "local"
        return [
            PrismPinnedSite(userId: uid, title: "GitHub", url: "https://github.com", displayOrder: 0),
            PrismPinnedSite(userId: uid, title: "Hacker News", url: "https://news.ycombinator.com", displayOrder: 1),
            PrismPinnedSite(userId: uid, title: "Substack", url: "https://substack.com/inbox", displayOrder: 2),
            PrismPinnedSite(userId: uid, title: "Medium", url: "https://medium.com", displayOrder: 3),
            PrismPinnedSite(userId: uid, title: "Perplexity", url: "https://www.perplexity.ai", displayOrder: 4),
            PrismPinnedSite(userId: uid, title: "Wikipedia", url: "https://en.wikipedia.org", displayOrder: 5)
        ]
    }
}

// MARK: - Local Hibernated Tab State (Single-Active WebView Engine)

public struct PrismTabState: Identifiable, Codable, Equatable, Sendable {
    public static let maxOpenTabs: Int = 8

    public var id: UUID
    public var url: String
    public var title: String
    public var domain: String
    public var faviconUrl: String?
    public var scrollY: Double
    public var isPrivate: Bool
    public var isReaderMode: Bool
    public var detectedRssUrl: String?
    public var detectedRssTitle: String?
    public var lastAccessedAt: Date
    public var isHibernated: Bool

    public init(
        id: UUID = UUID(),
        url: String = "",
        title: String = "New Tab",
        domain: String = "",
        faviconUrl: String? = nil,
        scrollY: Double = 0,
        isPrivate: Bool = false,
        isReaderMode: Bool = false,
        detectedRssUrl: String? = nil,
        detectedRssTitle: String? = nil,
        lastAccessedAt: Date = Date(),
        isHibernated: Bool = false
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.domain = domain.isEmpty && !url.isEmpty ? PrismSearchEngine.extractCleanDomain(from: url) : domain
        self.faviconUrl = faviconUrl ?? (url.isEmpty ? nil : PrismSearchEngine.faviconURLString(for: url))
        self.scrollY = scrollY
        self.isPrivate = isPrivate
        self.isReaderMode = isReaderMode
        self.detectedRssUrl = detectedRssUrl
        self.detectedRssTitle = detectedRssTitle
        self.lastAccessedAt = lastAccessedAt
        self.isHibernated = isHibernated
    }

    public var isStartPage: Bool {
        url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Assisted Exploration (Prism Co-Pilot Models)

public enum PrismCoPilotAction: String, CaseIterable, Identifiable, Sendable {
    case tldr = "tldr"
    case extractTasks = "extract_tasks"
    case keyFacts = "key_facts"
    case explainSelection = "explain_selection"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .tldr: return "TL;DR Summary"
        case .extractTasks: return "Tasks → TagDoS"
        case .keyFacts: return "Key Facts & Numbers"
        case .explainSelection: return "Explain Selection"
        }
    }

    public var iconName: String {
        switch self {
        case .tldr: return "sparkles"
        case .extractTasks: return "checklist"
        case .keyFacts: return "chart.bar.doc.horizontal"
        case .explainSelection: return "text.magnifyingglass"
        }
    }

    public var accentHex: String {
        switch self {
        case .tldr: return "#00E5FF"
        case .extractTasks: return "#FFB300"
        case .keyFacts: return "#10B981"
        case .explainSelection: return "#A855F7"
        }
    }
}

public struct PrismCoPilotTurn: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var prompt: String
    public var responseMarkdown: String
    public var keyBullets: [String]
    public var extractedTasks: [String]
    public var sourceUrl: String
    public var pageTitle: String
    public var isAiGenerated: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        prompt: String,
        responseMarkdown: String,
        keyBullets: [String] = [],
        extractedTasks: [String] = [],
        sourceUrl: String,
        pageTitle: String,
        isAiGenerated: Bool,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.prompt = prompt
        self.responseMarkdown = responseMarkdown
        self.keyBullets = keyBullets
        self.extractedTasks = extractedTasks
        self.sourceUrl = sourceUrl
        self.pageTitle = pageTitle
        self.isAiGenerated = isAiGenerated
        self.createdAt = createdAt
    }
}

// MARK: - Cross-Module Navigation & Share Extension Queue

public struct PrismNavigationRequest: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let url: String
    public let title: String?
    public let openInNewTab: Bool
    public let isPrivate: Bool
    public let autoTriggerCoPilot: PrismCoPilotAction?

    public init(
        id: UUID = UUID(),
        url: String,
        title: String? = nil,
        openInNewTab: Bool = false,
        isPrivate: Bool = false,
        autoTriggerCoPilot: PrismCoPilotAction? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.openInNewTab = openInNewTab
        self.isPrivate = isPrivate
        self.autoTriggerCoPilot = autoTriggerCoPilot
    }
}

public struct PrismPendingShareItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var clipType: PrismClipType
    public var url: String
    public var title: String
    public var text: String
    public var localImageFileName: String?
    public var openImmediatelyInPrism: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        clipType: PrismClipType,
        url: String,
        title: String = "",
        text: String = "",
        localImageFileName: String? = nil,
        openImmediatelyInPrism: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.clipType = clipType
        self.url = url
        self.title = title
        self.text = text
        self.localImageFileName = localImageFileName
        self.openImmediatelyInPrism = openImmediatelyInPrism
        self.createdAt = createdAt
    }
}
