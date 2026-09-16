import Foundation

/// Contextual temporal slots dividing the 24-hour cycle for Smart Briefings.
public enum BriefingTimeSlot: String, CaseIterable, Codable, Sendable, Identifiable {
    case morning = "morning"
    case intraday = "intraday"
    case evening = "evening"
    case nightly = "nightly"

    public var id: String { rawValue }

    /// Resolves active time slot based on current local hour (24-hour clock).
    public static func current(for date: Date = Date(), calendar: Calendar = .current) -> BriefingTimeSlot {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<12:
            return .morning
        case 12..<17:
            return .intraday
        case 17..<22:
            return .evening
        default:
            return .nightly
        }
    }

    public var displayName: String {
        switch self {
        case .morning: return "Morning Briefing"
        case .intraday: return "Intra-day Briefing"
        case .evening: return "Evening Review"
        case .nightly: return "Nightly Wind-Down"
        }
    }

    public var systemImage: String {
        switch self {
        case .morning: return "sun.horizon.fill"
        case .intraday: return "sun.max.fill"
        case .evening: return "sunset.fill"
        case .nightly: return "moon.stars.fill"
        }
    }

    public var timeRangeString: String {
        switch self {
        case .morning: return "05:00 – 11:59"
        case .intraday: return "12:00 – 16:59"
        case .evening: return "17:00 – 21:59"
        case .nightly: return "22:00 – 04:59"
        }
    }

    public var auraGradientHex: [String] {
        switch self {
        case .morning:
            return ["#FF9A3D", "#FF5E62", "#7B2CBF"] // Warm sunrise amber to violet
        case .intraday:
            return ["#00F5D4", "#00BBF9", "#4361EE"] // High-energy cyan to electric blue
        case .evening:
            return ["#F72585", "#7209B7", "#3A0CA3"] // Sunset magenta to deep twilight
        case .nightly:
            return ["#3F37C9", "#480CA8", "#03071E"] // Deep cosmic indigo to midnight
        }
    }

    public var greetingPrefix: String {
        switch self {
        case .morning: return "Good morning"
        case .intraday: return "Good afternoon"
        case .evening: return "Good evening"
        case .nightly: return "Peaceful night"
        }
    }

    public var actionButtonIcon: String {
        switch self {
        case .morning: return "sun.horizon.fill"
        case .intraday: return "sun.max.fill"
        case .evening: return "sunset.fill"
        case .nightly: return "bed.double.fill"
        }
    }
}

/// Structured multi-hub narrative text components forming the briefing body.
public struct SmartBriefingNarrative: Codable, Equatable, Sendable {
    public var greeting: String
    public var weatherText: String
    public var healthText: String
    public var habitsText: String
    public var financeText: String
    public var tagdosText: String
    public var newsText: String
    public var outroText: String

    public init(
        greeting: String = "",
        weatherText: String = "",
        healthText: String = "",
        habitsText: String = "",
        financeText: String = "",
        tagdosText: String = "",
        newsText: String = "",
        outroText: String = ""
    ) {
        self.greeting = greeting
        self.weatherText = weatherText
        self.healthText = healthText
        self.habitsText = habitsText
        self.financeText = financeText
        self.tagdosText = tagdosText
        self.newsText = newsText
        self.outroText = outroText
    }

    /// Full concatenated narrative for the unified fading typewriter animation.
    public var fullConcatenatedText: String {
        let parts = [
            greeting,
            weatherText,
            healthText,
            habitsText,
            financeText,
            tagdosText,
            newsText,
            outroText
        ].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return parts.joined(separator: "\n\n")
    }

    /// Array of labeled paragraphs with icons for structured cards and readers.
    public var structuredSections: [(icon: String, title: String, text: String)] {
        var list: [(icon: String, title: String, text: String)] = []
        if !weatherText.isEmpty {
            list.append(("cloud.sun.fill", "Weather & Atmosphere", weatherText))
        }
        if !healthText.isEmpty {
            list.append(("heart.fill", "Health & Recovery", healthText))
        }
        if !habitsText.isEmpty {
            list.append(("drop.fill", "Habits & Cravings", habitsText))
        }
        if !financeText.isEmpty {
            list.append(("creditcard.fill", "Financial Overview", financeText))
        }
        if !tagdosText.isEmpty {
            list.append(("tag.fill", "TagDoS Focus", tagdosText))
        }
        if !newsText.isEmpty {
            list.append(("newspaper.fill", "Headlines Radar", newsText))
        }
        return list
    }
}

/// Numerical and telemetry snapshot backing the visual mini-charts in the briefing.
public struct SmartBriefingMetrics: Codable, Equatable, Sendable {
    public var weatherTemp: Double?
    public var weatherCondition: String?
    public var weatherIcon: String?
    public var weatherCity: String?
    public var sleepScore: Int?
    public var sleepDurationHours: Double?
    public var restingBpm: Double?
    public var totalStepsToday: Int
    public var waterMlToday: Double
    public var waterGoalMl: Double
    public var smokesToday: Int
    public var smokesBaseline: Int
    public var netWorth: Double
    public var daySpend: Double
    public var activeStreamCount: Int
    public var activeMemoCount: Int
    public var topNewsTitle: String?

    public init(
        weatherTemp: Double? = nil,
        weatherCondition: String? = nil,
        weatherIcon: String? = nil,
        weatherCity: String? = nil,
        sleepScore: Int? = nil,
        sleepDurationHours: Double? = nil,
        restingBpm: Double? = nil,
        totalStepsToday: Int = 0,
        waterMlToday: Double = 0,
        waterGoalMl: Double = 2000,
        smokesToday: Int = 0,
        smokesBaseline: Int = 10,
        netWorth: Double = 0,
        daySpend: Double = 0,
        activeStreamCount: Int = 0,
        activeMemoCount: Int = 0,
        topNewsTitle: String? = nil
    ) {
        self.weatherTemp = weatherTemp
        self.weatherCondition = weatherCondition
        self.weatherIcon = weatherIcon
        self.weatherCity = weatherCity
        self.sleepScore = sleepScore
        self.sleepDurationHours = sleepDurationHours
        self.restingBpm = restingBpm
        self.totalStepsToday = totalStepsToday
        self.waterMlToday = waterMlToday
        self.waterGoalMl = waterGoalMl
        self.smokesToday = smokesToday
        self.smokesBaseline = smokesBaseline
        self.netWorth = netWorth
        self.daySpend = daySpend
        self.activeStreamCount = activeStreamCount
        self.activeMemoCount = activeMemoCount
        self.topNewsTitle = topNewsTitle
    }
}

/// Persisted record model mapping directly to Supabase `public.daily_smart_summaries`.
public struct SmartBriefingRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var userId: String
    public var timeSlot: String
    public var dataHash: String
    public var narrative: SmartBriefingNarrative
    public var metrics: SmartBriefingMetrics
    public var isAiGenerated: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        userId: String = "",
        timeSlot: String = BriefingTimeSlot.morning.rawValue,
        dataHash: String = "",
        narrative: SmartBriefingNarrative = SmartBriefingNarrative(),
        metrics: SmartBriefingMetrics = SmartBriefingMetrics(),
        isAiGenerated: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.timeSlot = timeSlot
        self.dataHash = dataHash
        self.narrative = narrative
        self.metrics = metrics
        self.isAiGenerated = isAiGenerated
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case timeSlot = "time_slot"
        case dataHash = "data_hash"
        case narrative
        case metrics
        case isAiGenerated = "is_ai_generated"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public var slot: BriefingTimeSlot {
        BriefingTimeSlot(rawValue: timeSlot) ?? .morning
    }
}
