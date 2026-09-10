import Foundation

// MARK: - Habit Types

public enum HabitType: String, CaseIterable, Codable, Sendable, Identifiable {
    case water = "water"
    case smokes = "smokes"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .water: return "Bubbles"
        case .smokes: return "Smokes"
        }
    }
    
    public var subtitle: String {
        switch self {
        case .water: return "Hydration & Liquids"
        case .smokes: return "Tobacco Management"
        }
    }
    
    public var systemImage: String {
        switch self {
        case .water: return "drop.fill"
        case .smokes: return "flame.fill"
        }
    }
    
    public var defaultUnit: String {
        switch self {
        case .water: return "ml"
        case .smokes: return "cigs"
        }
    }
}

// MARK: - Habit Date Parser

public enum HabitDateParser {
    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    nonisolated(unsafe) private static let isoStandard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    
    private static let posixWithMillis: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
        return f
    }()

    private static let posixStandard: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        return f
    }()

    public static func parse(_ raw: String) -> Date? {
        if let d = isoFractional.date(from: raw) { return d }
        if let d = isoStandard.date(from: raw) { return d }
        let tString = raw.replacingOccurrences(of: " ", with: "T")
        if let d = isoFractional.date(from: tString) { return d }
        if let d = isoStandard.date(from: tString) { return d }
        if let d = posixWithMillis.date(from: tString) { return d }
        if let d = posixStandard.date(from: tString) { return d }
        return nil
    }
}

// MARK: - Habit Log Record (Supabase `habits_logs`)

public struct HabitLogRecord: Identifiable, Codable, Sendable {
    public var id: UUID
    public var userId: UUID?
    public var habitType: String
    public var value: Double
    public var unit: String
    public var loggedAt: Date
    public var metadata: String?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var isDeleted: Bool
    
    public var amount: Double { value }
    
    public var formattedTime: String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df.string(from: loggedAt)
    }
    
    public var parsedDrink: String? {
        guard let metadata = metadata,
              let data = metadata.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return (dict["drink"] as? String) ?? (dict["type"] as? String)
    }
    
    public var displayName: String {
        if let d = parsedDrink, !d.isEmpty {
            return d
        }
        return habitType.capitalized
    }
    
    enum CodingKeys: String, CodingKey {

        case id
        case userId = "user_id"
        case habitType = "habit_type"
        case value
        case unit
        case loggedAt = "logged_at"
        case metadata
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case isDeleted = "is_deleted"
    }
    
    public init(
        id: UUID = UUID(),
        userId: UUID? = nil,
        habitType: String,
        value: Double,
        unit: String,
        loggedAt: Date = Date(),
        metadata: String? = nil,
        createdAt: Date? = Date(),
        updatedAt: Date? = Date(),
        isDeleted: Bool = false
    ) {
        self.id = id
        self.userId = userId
        self.habitType = habitType
        self.value = value
        self.unit = unit
        self.loggedAt = loggedAt
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.userId = try container.decodeIfPresent(UUID.self, forKey: .userId)
        self.habitType = try container.decode(String.self, forKey: .habitType)
        
        // Handle value as Double or Int
        if let d = try? container.decode(Double.self, forKey: .value) {
            self.value = d
        } else if let i = try? container.decode(Int.self, forKey: .value) {
            self.value = Double(i)
        } else if let s = try? container.decode(String.self, forKey: .value), let d = Double(s) {
            self.value = d
        } else {
            self.value = 0.0
        }
        
        self.unit = try container.decodeIfPresent(String.self, forKey: .unit) ?? "ml"
        
        // Handle loggedAt as Date or ISO8601 String
        if let date = try? container.decode(Date.self, forKey: .loggedAt) {
            self.loggedAt = date
        } else if let dateStr = try? container.decode(String.self, forKey: .loggedAt) {
            self.loggedAt = HabitDateParser.parse(dateStr) ?? Date()
        } else {
            self.loggedAt = Date()
        }
        
        // Metadata can be String, JSON object, or nil
        if let str = try? container.decode(String.self, forKey: .metadata) {
            self.metadata = str
        } else if let dict = try? container.decode([String: String].self, forKey: .metadata) {
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
               let jsonString = String(data: data, encoding: .utf8) {
                self.metadata = jsonString
            } else {
                self.metadata = nil
            }
        } else {
            self.metadata = nil
        }
        
        self.createdAt = try? container.decodeIfPresent(Date.self, forKey: .createdAt)
        self.updatedAt = try? container.decodeIfPresent(Date.self, forKey: .updatedAt)
        self.isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(userId, forKey: .userId)
        try container.encode(habitType, forKey: .habitType)
        try container.encode(value, forKey: .value)
        try container.encode(unit, forKey: .unit)
        
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try container.encode(f.string(from: loggedAt), forKey: .loggedAt)
        
        try container.encodeIfPresent(metadata, forKey: .metadata)
        if let c = createdAt { try container.encode(f.string(from: c), forKey: .createdAt) }
        if let u = updatedAt { try container.encode(f.string(from: u), forKey: .updatedAt) }
        try container.encode(isDeleted, forKey: .isDeleted)
    }
    
    // MARK: - Metadata Helpers
    
    public var parsedMetadata: [String: String]? {
        guard let meta = metadata, let data = meta.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: []) as? [String: String]
    }
    
    public var drinkType: String {
        parsedMetadata?["drink"] ?? (habitType == "water" ? "Water" : "Cigarette")
    }
    
    public var smokeType: String {
        parsedMetadata?["type"] ?? (habitType == "smokes" ? "Cigarette" : "Water")
    }
}

// MARK: - Habit Goal Record (Supabase `habits_goals`)

public struct HabitGoalRecord: Identifiable, Codable, Sendable {
    public var id: UUID
    public var userId: UUID?
    public var habitType: String
    public var targetValue: Double
    public var unit: String
    public var updatedAt: Date?
    public var createdAt: Date?
    public var isDeleted: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case habitType = "habit_type"
        case targetValue = "target_value"
        case unit
        case updatedAt = "updated_at"
        case createdAt = "created_at"
        case isDeleted = "is_deleted"
    }
    
    public init(
        id: UUID = UUID(),
        userId: UUID? = nil,
        habitType: String,
        targetValue: Double,
        unit: String,
        updatedAt: Date? = Date(),
        createdAt: Date? = Date(),
        isDeleted: Bool = false
    ) {
        self.id = id
        self.userId = userId
        self.habitType = habitType
        self.targetValue = targetValue
        self.unit = unit
        self.updatedAt = updatedAt
        self.createdAt = createdAt
        self.isDeleted = isDeleted
    }
}

// MARK: - Water Presets

public enum WaterPreset: String, CaseIterable, Identifiable, Sendable {
    case smallWater = "Small Water"
    case largeWater = "Large Water"
    case glass = "Glass"
    case bottle = "Bottle"
    case coffee = "Coffee"
    case tea = "Tea"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .smallWater: return "Small"
        case .largeWater: return "Large"
        case .glass: return "Glass"
        case .bottle: return "Bottle"
        case .coffee: return "Coffee"
        case .tea: return "Tea"
        }
    }
    
    public var defaultAmountMl: Double {
        switch self {
        case .smallWater: return 150
        case .largeWater: return 300
        case .glass: return 250
        case .bottle: return 500
        case .coffee: return 100
        case .tea: return 250
        }
    }
    
    public var systemImage: String {
        switch self {
        case .smallWater: return "drop"
        case .largeWater: return "drop.fill"
        case .glass: return "waterbottle"
        case .bottle: return "flask.fill"
        case .coffee: return "cup.and.saucer.fill"
        case .tea: return "mug.fill"
        }
    }
    
    public var hexColor: String {
        switch self {
        case .smallWater: return "#38BDF8" // Light Sky Blue
        case .largeWater: return "#00E5FF" // Neon Cyan
        case .glass: return "#10B981"      // Mint Green
        case .bottle: return "#06B6D4"     // Teal
        case .coffee: return "#F59E0B"     // Amber / Warm Orange
        case .tea: return "#84CC16"        // Lime / Herbal Green
        }
    }
    
    public var hydrationFactor: Double {
        switch self {
        case .smallWater, .largeWater, .glass, .bottle: return 1.0
        case .tea: return 0.95
        case .coffee: return 0.80
        }
    }
    
    public static var defaults: [WaterPreset] { Array(allCases) }
    public var name: String { displayName }
    public var amountMl: Double { defaultAmountMl }
    public var iconName: String { systemImage }
    public var colorHex: String { hexColor }
}

// MARK: - Smoke Presets

public enum SmokePreset: String, CaseIterable, Identifiable, Sendable {
    case cigarette = "Cigarette"
    case heated = "Heated Tobacco"
    case rolled = "Rolled"
    case cigarillo = "Cigarillo"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .cigarette: return "Cigarette"
        case .heated: return "Heated"
        case .rolled: return "Rolled"
        case .cigarillo: return "Cigarillo"
        }
    }
    
    public var defaultCount: Int { 1 }
    
    public var systemImage: String {
        switch self {
        case .cigarette: return "flame.fill"
        case .heated: return "bolt.fill"
        case .rolled: return "leaf.fill"
        case .cigarillo: return "flame"
        }
    }
    
    public var hexColor: String {
        switch self {
        case .cigarette: return "#EF4444" // Crimson Red
        case .heated: return "#3B82F6"    // Electric Blue
        case .rolled: return "#F97316"    // Orange
        case .cigarillo: return "#A855F7" // Purple
        }
    }
    
    public static var defaults: [SmokePreset] { Array(allCases) }
    public var name: String { displayName }
    public var iconName: String { systemImage }
    public var colorHex: String { hexColor }
}


// MARK: - Smokes Settings & Financial Metrics

public struct SmokesSettings: Codable, Sendable, Equatable {
    public var quitStartDate: Date
    public var baselineCigsPerDay: Int
    public var cigsPerPack: Int
    public var costPerPack: Double
    public var currency: String
    
    public init(
        quitStartDate: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date(),
        baselineCigsPerDay: Int = 20,
        cigsPerPack: Int = 20,
        costPerPack: Double = 26.50,
        currency: String = "RON"
    ) {
        self.quitStartDate = quitStartDate
        self.baselineCigsPerDay = baselineCigsPerDay
        self.cigsPerPack = max(cigsPerPack, 1)
        self.costPerPack = max(costPerPack, 0)
        self.currency = currency
    }
    
    public var costPerCig: Double {
        costPerPack / Double(cigsPerPack)
    }
    
    public var baselineDailyCount: Int {
        get { baselineCigsPerDay }
        set { baselineCigsPerDay = newValue }
    }
}

public struct SmokesFinancialMetrics: Sendable {
    public var moneySaved: Double
    public var cigsAvoided: Int
    public var daysTracked: Int
    public var costPerCig: Double
    public var lastSmokeDate: Date?
    public var timeSinceLastSmoke: TimeInterval?
    
    public init(
        moneySaved: Double = 0,
        cigsAvoided: Int = 0,
        daysTracked: Int = 0,
        costPerCig: Double = 1.325,
        lastSmokeDate: Date? = nil,
        timeSinceLastSmoke: TimeInterval? = nil
    ) {
        self.moneySaved = moneySaved
        self.cigsAvoided = cigsAvoided
        self.daysTracked = daysTracked
        self.costPerCig = costPerCig
        self.lastSmokeDate = lastSmokeDate
        self.timeSinceLastSmoke = timeSinceLastSmoke
    }
    
    public var formattedMoneySaved: String {
        String(format: "+%.2f", moneySaved)
    }
    
    public var moneySavedFormatted: String {
        String(format: "+%.2f RON", moneySaved)
    }
    
    public var cigarettesAvoidedCount: Int {
        cigsAvoided
    }
    
    public var lifeRegainedFormatted: String {
        let totalMinutes = cigsAvoided * 11
        let hours = totalMinutes / 60
        let mins = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        } else {
            return "\(totalMinutes)m"
        }
    }
    
    public var formattedTimeSinceLastSmoke: String {
        guard let interval = timeSinceLastSmoke, interval >= 0 else { return "No smokes logged" }
        let mins = Int(interval / 60)
        let hours = mins / 60
        let remainingMins = mins % 60
        if hours > 0 {
            return "\(hours)h \(remainingMins)m ago"
        } else {
            return "\(mins)m ago"
        }
    }
}

// MARK: - Habit Analytics & Visual Models

public struct HabitDrinkBreakdown: Identifiable, Sendable {
    public var id: String { drink }
    public var drink: String
    public var amount: Double
    public var unit: String
    public var percentage: Double
    public var hexColor: String
    public var iconName: String
    
    public var name: String { drink }
    public var amountMl: Double { amount }
    public var colorHex: String { hexColor }

    
    public init(
        drink: String,
        amount: Double,
        unit: String,
        percentage: Double,
        hexColor: String,
        iconName: String
    ) {
        self.drink = drink
        self.amount = amount
        self.unit = unit
        self.percentage = percentage
        self.hexColor = hexColor
        self.iconName = iconName
    }
}

public struct HabitTrendDay: Identifiable, Sendable {
    public var id: String { dayLabel }
    public var date: Date
    public var dayLabel: String
    public var value: Double
    public var goal: Double
    public var isGoalMet: Bool
    
    public init(
        date: Date,
        dayLabel: String,
        value: Double,
        goal: Double,
        isGoalMet: Bool
    ) {
        self.date = date
        self.dayLabel = dayLabel
        self.value = value
        self.goal = goal
        self.isGoalMet = isGoalMet
    }
    
    public var progressRatio: Double {
        goal > 0 ? min(value / goal, 1.5) : 0
    }
    
    public var amount: Double { value }
}

public struct HabitConsistencyCell: Identifiable, Sendable {
    public var id: String { dateKey }
    public var date: Date
    public var dateKey: String
    public var value: Double
    public var intensityLevel: Int // 0 (empty) to 4 (max)
    public var tooltip: String
    
    public var amount: Double { value }
    public var isGoalMet: Bool { intensityLevel >= 4 }
    public var dateFormatted: String { tooltip }
    
    public init(
        date: Date,
        dateKey: String,
        value: Double,
        intensityLevel: Int,
        tooltip: String
    ) {
        self.date = date
        self.dateKey = dateKey
        self.value = value
        self.intensityLevel = max(0, min(intensityLevel, 4))
        self.tooltip = tooltip
    }
}

