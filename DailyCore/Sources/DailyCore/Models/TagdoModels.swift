import Foundation

/// Semantic classification for a TagDoS pill based on embedded glyphs and tokens.
public enum TagDoPillType: String, Codable, Sendable {
    case standard          // Standard action / place (e.g. MG, GM, TG, CLN)
    case financial         // Financial implication / debt / cost (contains $ or €)
    case urgent            // Critical urgency / alert (contains !)
    case temporalOrMetric  // Contains digits for dates or metrics (e.g. 14, 98, PL98)
    case completed         // Marked completed / dimmed

    public var badgeColorHex: String {
        switch self {
        case .standard: return "#00E5FF"         // Neon Cyan
        case .financial: return "#00E676"        // Neon Emerald Green
        case .urgent: return "#FF2D55"           // Glowing Ruby Coral
        case .temporalOrMetric: return "#FFD600" // Neon Amber Yellow
        case .completed: return "#8E8E93"        // Dimmed Slate Gray
        }
    }
}

/// Represents an individual mental tag / action unit within a cluster.
public struct TagDoPill: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var rawText: String
    public var type: TagDoPillType
    public var isCompleted: Bool
    public var customReminderDate: Date?
    public var decodedNote: String?

    public init(
        id: UUID = UUID(),
        rawText: String,
        type: TagDoPillType? = nil,
        isCompleted: Bool = false,
        customReminderDate: Date? = nil,
        decodedNote: String? = nil
    ) {
        self.id = id
        self.rawText = rawText
        self.isCompleted = isCompleted
        self.customReminderDate = customReminderDate
        self.decodedNote = decodedNote
        
        if let type = type {
            self.type = type
        } else {
            // Auto-detect type from string content
            if rawText.contains("$") || rawText.contains("€") {
                self.type = .financial
            } else if rawText.contains("!") {
                self.type = .urgent
            } else if rawText.rangeOfCharacter(from: .decimalDigits) != nil {
                self.type = .temporalOrMetric
            } else {
                self.type = .standard
            }
        }
    }
}

/// A cluster of related sequential actions separated by `/`, grouped under ` & `.
public struct TagDoCluster: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var pills: [TagDoPill]
    public var rawText: String

    public init(id: UUID = UUID(), pills: [TagDoPill], rawText: String) {
        self.id = id
        self.pills = pills
        self.rawText = rawText
    }

    public var activePills: [TagDoPill] {
        pills.filter { !$0.isCompleted }
    }

    public var completedPills: [TagDoPill] {
        pills.filter { $0.isCompleted }
    }
}

/// Represents a file, document, or image attachment bound to a specific Tagdos stream.
public struct TagDoAttachment: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var streamNumber: Int
    public var fileName: String
    public var fileType: String // MIME type, e.g. "image/jpeg", "application/pdf"
    public var fileSizeBytes: Int64
    public var remotePath: String? // Supabase Storage path: "{userId}/stream_{streamNumber}/{id}_{fileName}"
    public var localFileName: String? // Local cache filename inside TagdosAttachments cache
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        streamNumber: Int,
        fileName: String,
        fileType: String,
        fileSizeBytes: Int64,
        remotePath: String? = nil,
        localFileName: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.streamNumber = streamNumber
        self.fileName = fileName
        self.fileType = fileType
        self.fileSizeBytes = fileSizeBytes
        self.remotePath = remotePath
        self.localFileName = localFileName ?? "\(id.uuidString)_\(fileName)"
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var isImage: Bool {
        fileType.lowercased().contains("image") ||
        ["jpg", "jpeg", "png", "heic", "webp", "gif"].contains((fileName as NSString).pathExtension.lowercased())
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }
}

/// A single TagDoS line / stream representing a prioritized execution queue.
public struct TagDoStream: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var customTitle: String?
    public var rawText: String
    public var clusters: [TagDoCluster]
    public var streamReminder: Date?
    public var orderIndex: Int
    public var activeMemos: String
    public var attachments: [TagDoAttachment]
    public var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, customTitle, rawText, clusters, streamReminder, orderIndex, activeMemos, attachments, updatedAt
    }

    public init(
        id: UUID = UUID(),
        title: String,
        customTitle: String? = nil,
        rawText: String,
        clusters: [TagDoCluster] = [],
        streamReminder: Date? = nil,
        orderIndex: Int = 0,
        activeMemos: String = "",
        attachments: [TagDoAttachment] = [],
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.customTitle = customTitle
        self.rawText = rawText
        self.clusters = clusters
        self.streamReminder = streamReminder
        self.orderIndex = orderIndex
        self.activeMemos = activeMemos
        self.attachments = attachments
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.title = try container.decode(String.self, forKey: .title)
        self.customTitle = try container.decodeIfPresent(String.self, forKey: .customTitle)
        self.rawText = try container.decode(String.self, forKey: .rawText)
        self.clusters = try container.decodeIfPresent([TagDoCluster].self, forKey: .clusters) ?? []
        self.streamReminder = try container.decodeIfPresent(Date.self, forKey: .streamReminder)
        self.orderIndex = try container.decodeIfPresent(Int.self, forKey: .orderIndex) ?? 0
        self.activeMemos = try container.decodeIfPresent(String.self, forKey: .activeMemos) ?? ""
        self.attachments = try container.decodeIfPresent([TagDoAttachment].self, forKey: .attachments) ?? []
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    /// Resolved display title: uses explicit custom user title if set; otherwise falls back to auto-detected title.
    public var displayTitle: String {
        if let custom = customTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            return custom
        }
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        return autoDetectedTitle
    }

    /// Automatically detects a meaningful stream title from tags, keywords, and stream order.
    public var autoDetectedTitle: String {
        let streamNum = orderIndex + 1
        let upperText = rawText.uppercased()

        // 1. Domain detection from known keywords
        if upperText.contains("WRK") || upperText.contains("PRJ") || upperText.contains("CODE") || upperText.contains("BUG") || upperText.contains("DEV") || upperText.contains("MET") {
            return "Stream \(streamNum): Work & Code"
        }
        if upperText.contains("FIT") || upperText.contains("GYM") || upperText.contains("RUN") || upperText.contains("PROT") || upperText.contains("SLP") || upperText.contains("CREAT") {
            return "Stream \(streamNum): Health & Fitness"
        }
        if upperText.contains("FIN") || upperText.contains("CARD") || upperText.contains("CASH") || upperText.contains("INV") || upperText.contains("STK") || upperText.contains("C$T") || upperText.contains("EUR") {
            return "Stream \(streamNum): Finances & Bills"
        }
        if upperText.contains("HOM") || upperText.contains("ORD") || upperText.contains("CLN") || upperText.contains("BUY") || upperText.contains("MKT") || upperText.contains("GROC") {
            return "Stream \(streamNum): Home & Life"
        }
        if upperText.contains("MG") || upperText.contains("GM") || upperText.contains("TG") || upperText.contains("FSH") || upperText.contains("LDL") {
            return "Stream \(streamNum): Daily Ops"
        }

        // 2. Fallback to driving pill tag if present
        if let driving = drivingPill?.rawText, !driving.isEmpty {
            return "Stream \(streamNum): \(driving) Focus"
        }

        // 3. Slot default fallback
        switch streamNum {
        case 1: return "Stream 1: Daily Ops"
        case 2: return "Stream 2: Work & Code"
        case 3: return "Stream 3: Health & Fitness"
        case 4: return "Stream 4: Finances & Bills"
        case 5: return "Stream 5: Home & Life"
        default: return "Stream \(streamNum)"
        }
    }

    /// All pills flattened across all clusters in this stream.
    public var allPills: [TagDoPill] {
        clusters.flatMap { $0.pills }
    }

    /// All uncompleted pills in execution order.
    public var activePills: [TagDoPill] {
        clusters.flatMap { $0.activePills }
    }

    /// The primary pill currently leading this stream (drives current reminder).
    public var drivingPill: TagDoPill? {
        activePills.first
    }
}

/// Standalone Quick Note with Markdown content, pinning, and tags.
public struct TagDoQuickNote: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var userId: String?
    public var title: String
    public var content: String
    public var isPinned: Bool
    public var tags: [String]
    public var createdAt: Date
    public var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, content, tags
        case userId = "user_id"
        case isPinned = "is_pinned"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        id: UUID = UUID(),
        userId: String? = nil,
        title: String = "",
        content: String = "",
        isPinned: Bool = false,
        tags: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.title = title
        self.content = content
        self.isPinned = isPinned
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var displayTitle: String {
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        let firstLine = content.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        if let line = firstLine {
            let clean = line.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.isEmpty ? "Untitled Note" : clean
        }
        return "Untitled Note"
    }

    public var previewSnippet: String {
        let lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if lines.count > 1 {
            return lines.dropFirst().joined(separator: " ")
        }
        return content
    }
}

/// Lightweight snapshot for WidgetKit and fast UI rendering.
public struct TagdosWidgetSnapshotPill: Codable, Sendable {
    public let text: String
    public let typeRaw: String
    public let isCompleted: Bool

    public init(text: String, typeRaw: String, isCompleted: Bool) {
        self.text = text
        self.typeRaw = typeRaw
        self.isCompleted = isCompleted
    }
}

public struct TagdosWidgetSnapshotStream: Codable, Sendable {
    public let id: String
    public let title: String
    public let drivingPillText: String?
    public let drivingPillType: String?
    public let activePillsCount: Int
    public let reminderTimeFormatted: String?
    public let pills: [TagdosWidgetSnapshotPill]
    public let activeMemosPreview: String?

    public init(
        id: String,
        title: String,
        drivingPillText: String?,
        drivingPillType: String?,
        activePillsCount: Int,
        reminderTimeFormatted: String?,
        pills: [TagdosWidgetSnapshotPill],
        activeMemosPreview: String? = nil
    ) {
        self.id = id
        self.title = title
        self.drivingPillText = drivingPillText
        self.drivingPillType = drivingPillType
        self.activePillsCount = activePillsCount
        self.reminderTimeFormatted = reminderTimeFormatted
        self.pills = pills
        self.activeMemosPreview = activeMemosPreview
    }
}

public struct TagdosWidgetSnapshot: Codable, Sendable {
    public let streams: [TagdosWidgetSnapshotStream]
    public let totalActivePills: Int
    public let nextReminderFormatted: String?
    public let lastUpdated: Date

    public init(
        streams: [TagdosWidgetSnapshotStream],
        totalActivePills: Int,
        nextReminderFormatted: String?,
        lastUpdated: Date = Date()
    ) {
        self.streams = streams
        self.totalActivePills = totalActivePills
        self.nextReminderFormatted = nextReminderFormatted
        self.lastUpdated = lastUpdated
    }

    public static let empty = TagdosWidgetSnapshot(
        streams: [],
        totalActivePills: 0,
        nextReminderFormatted: nil,
        lastUpdated: Date()
    )
}
