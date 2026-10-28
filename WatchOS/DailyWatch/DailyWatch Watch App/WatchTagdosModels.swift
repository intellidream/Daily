import Foundation
import SwiftUI

public enum WatchTagDoPillType: String, Codable, Sendable {
    case standard
    case financial
    case urgent
    case temporalOrMetric
    case completed

    public var badgeColor: Color {
        switch self {
        case .standard: return Color(hex: "#00E5FF")         // Neon Cyan
        case .financial: return Color(hex: "#00E676")        // Neon Emerald Green
        case .urgent: return Color(hex: "#FF2D55")           // Glowing Ruby Coral
        case .temporalOrMetric: return Color(hex: "#FFD600") // Neon Amber Yellow
        case .completed: return Color(hex: "#8E8E93")        // Slate Gray
        }
    }
}

public struct WatchTagDoPill: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var rawText: String
    public var type: WatchTagDoPillType
    public var isCompleted: Bool

    public init(id: UUID = UUID(), rawText: String, type: WatchTagDoPillType? = nil, isCompleted: Bool = false) {
        self.id = id
        self.rawText = rawText
        self.isCompleted = isCompleted
        if let type = type {
            self.type = type
        } else {
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

public struct WatchTagDoCluster: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var pills: [WatchTagDoPill]
    public var rawText: String

    public init(id: UUID = UUID(), pills: [WatchTagDoPill], rawText: String) {
        self.id = id
        self.pills = pills
        self.rawText = rawText
    }

    public var activePills: [WatchTagDoPill] {
        pills.filter { !$0.isCompleted }
    }
}

public struct WatchTagDoStream: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var streamNumber: Int
    public var title: String
    public var rawText: String
    public var clusters: [WatchTagDoCluster]
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        streamNumber: Int,
        title: String,
        rawText: String,
        clusters: [WatchTagDoCluster] = [],
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.streamNumber = streamNumber
        self.title = title
        self.rawText = rawText
        self.clusters = clusters
        self.updatedAt = updatedAt
    }

    public var activePills: [WatchTagDoPill] {
        clusters.flatMap { $0.activePills }
    }

    public var drivingPill: WatchTagDoPill? {
        activePills.first
    }

    public var streamShortCode: String {
        switch streamNumber {
        case 1: return "S1"
        case 2: return "S2"
        case 3: return "S3"
        case 4: return "S4"
        case 5: return "S5"
        default: return "S\(streamNumber)"
        }
    }

    public var streamColor: Color {
        switch streamNumber {
        case 1: return Color(hex: "#00E5FF") // Cyan (Ops)
        case 2: return Color(hex: "#38BDF8") // Blue (Work)
        case 3: return Color(hex: "#10B981") // Green (Health)
        case 4: return Color(hex: "#F59E0B") // Amber (Fin)
        case 5: return Color(hex: "#EC4899") // Pink/Purple (Home)
        default: return Color(hex: "#A855F7")
        }
    }
}

public struct WatchTagDoQuickNote: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var content: String
    public var isPinned: Bool
    public var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, content
        case isPinned = "is_pinned"
        case updatedAt = "updated_at"
    }

    public init(id: UUID = UUID(), title: String, content: String, isPinned: Bool = true, updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.content = content
        self.isPinned = isPinned
        self.updatedAt = updatedAt
    }
}

public struct WatchTagdosParser {
    public static let shared = WatchTagdosParser()

    public func parseStream(
        rawText: String,
        title: String,
        streamNumber: Int,
        id: UUID = UUID(),
        existingStream: WatchTagDoStream? = nil
    ) -> WatchTagDoStream {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return WatchTagDoStream(id: id, streamNumber: streamNumber, title: title, rawText: "")
        }

        let rawClusters = trimmed.components(separatedBy: "&")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var parsedClusters: [WatchTagDoCluster] = []
        for rawCluster in rawClusters {
            let rawTokens = rawCluster.components(separatedBy: "/")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            var pills: [WatchTagDoPill] = []
            for token in rawTokens {
                if let existing = existingStream?.clusters.flatMap({ $0.pills }).first(where: { $0.rawText == token }) {
                    pills.append(WatchTagDoPill(id: existing.id, rawText: token, type: existing.type, isCompleted: existing.isCompleted))
                } else {
                    pills.append(WatchTagDoPill(rawText: token))
                }
            }
            if !pills.isEmpty {
                parsedClusters.append(WatchTagDoCluster(pills: pills, rawText: rawCluster))
            }
        }

        return WatchTagDoStream(
            id: id,
            streamNumber: streamNumber,
            title: title,
            rawText: trimmed,
            clusters: parsedClusters,
            updatedAt: Date()
        )
    }
}

// Color Hex Extension helper for watchOS
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
