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

/// A single TagDoS line / stream representing a prioritized execution queue.
public struct TagDoStream: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var rawText: String
    public var clusters: [TagDoCluster]
    public var streamReminder: Date?
    public var orderIndex: Int

    public init(
        id: UUID = UUID(),
        title: String,
        rawText: String,
        clusters: [TagDoCluster] = [],
        streamReminder: Date? = nil,
        orderIndex: Int = 0
    ) {
        self.id = id
        self.title = title
        self.rawText = rawText
        self.clusters = clusters
        self.streamReminder = streamReminder
        self.orderIndex = orderIndex
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

    public init(
        id: String,
        title: String,
        drivingPillText: String?,
        drivingPillType: String?,
        activePillsCount: Int,
        reminderTimeFormatted: String?,
        pills: [TagdosWidgetSnapshotPill]
    ) {
        self.id = id
        self.title = title
        self.drivingPillText = drivingPillText
        self.drivingPillType = drivingPillType
        self.activePillsCount = activePillsCount
        self.reminderTimeFormatted = reminderTimeFormatted
        self.pills = pills
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
