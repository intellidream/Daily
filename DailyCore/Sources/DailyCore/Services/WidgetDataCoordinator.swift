import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Snapshot model for Bubbles Widget
public struct BubblesWidgetSnapshot: Sendable {
    public let todayMl: Double
    public let goalMl: Double
    public let progressPercent: Double
    public let waterMl: Double
    public let coffeeMl: Double
    public let teaMl: Double
    public let drinkBreakdown: [(name: String, amount: Double, hexColor: String)]
    public let lastLoggedAt: Date?
    
    public init(
        todayMl: Double,
        goalMl: Double,
        progressPercent: Double,
        waterMl: Double,
        coffeeMl: Double,
        teaMl: Double = 0.0,
        drinkBreakdown: [(name: String, amount: Double, hexColor: String)] = [],
        lastLoggedAt: Date? = nil
    ) {
        self.todayMl = todayMl
        self.goalMl = goalMl
        self.progressPercent = progressPercent
        self.waterMl = waterMl
        self.coffeeMl = coffeeMl
        self.teaMl = teaMl
        self.drinkBreakdown = drinkBreakdown
        self.lastLoggedAt = lastLoggedAt
    }
}

/// Snapshot model for Smokes Widget
public struct SmokesWidgetSnapshot: Sendable {
    public let todayTotal: Int
    public let baseline: Int
    public let cigsCount: Int
    public let heatedCount: Int
    public let rolledCount: Int
    public let cigarilloCount: Int
    public let smokeBreakdown: [(name: String, count: Int, hexColor: String)]
    public let lastSmokeDate: Date?
    public let spentTodayLei: Double
    
    public init(
        todayTotal: Int,
        baseline: Int,
        cigsCount: Int,
        heatedCount: Int,
        rolledCount: Int = 0,
        cigarilloCount: Int = 0,
        smokeBreakdown: [(name: String, count: Int, hexColor: String)] = [],
        lastSmokeDate: Date? = nil,
        spentTodayLei: Double = 0.0
    ) {
        self.todayTotal = todayTotal
        self.baseline = baseline
        self.cigsCount = cigsCount
        self.heatedCount = heatedCount
        self.rolledCount = rolledCount
        self.cigarilloCount = cigarilloCount
        self.smokeBreakdown = smokeBreakdown
        self.lastSmokeDate = lastSmokeDate
        self.spentTodayLei = spentTodayLei
    }
}

/// Snapshot model for Money / SmartLedger Widget
public struct MoneyWidgetSnapshot: Sendable {
    public let netWorthLei: Double
    public let netWorthEUR: Double
    public let formattedNetWorth: String
    public let formattedNetWorthEUR: String
    public let incomingTotal: Double
    public let outgoingTotal: Double
    public let depositsTotal: Double
    public let cardAmount: Double
    public let cashAmount: Double
    public let topOutgoingAllocations: [(name: String, amount: Double)]
    
    public init(
        netWorthLei: Double,
        netWorthEUR: Double,
        formattedNetWorth: String,
        formattedNetWorthEUR: String,
        incomingTotal: Double,
        outgoingTotal: Double,
        depositsTotal: Double,
        cardAmount: Double,
        cashAmount: Double,
        topOutgoingAllocations: [(name: String, amount: Double)]
    ) {
        self.netWorthLei = netWorthLei
        self.netWorthEUR = netWorthEUR
        self.formattedNetWorth = formattedNetWorth
        self.formattedNetWorthEUR = formattedNetWorthEUR
        self.incomingTotal = incomingTotal
        self.outgoingTotal = outgoingTotal
        self.depositsTotal = depositsTotal
        self.cardAmount = cardAmount
        self.cashAmount = cashAmount
        self.topOutgoingAllocations = topOutgoingAllocations
    }
}

/// Briefing summary snippet model for the Combined Widget morning mode
public struct BriefingSummarySnippet: Sendable, Codable {
    public let greeting: String
    public let weatherTemp: Double?
    public let weatherCondition: String?
    public let weatherIcon: String?
    public let sleepDurationFormatted: String?
    public let sleepScore: Int?
    public let topFocusText: String?
    public let isAiGenerated: Bool
    
    public init(
        greeting: String,
        weatherTemp: Double? = nil,
        weatherCondition: String? = nil,
        weatherIcon: String? = nil,
        sleepDurationFormatted: String? = nil,
        sleepScore: Int? = nil,
        topFocusText: String? = nil,
        isAiGenerated: Bool = false
    ) {
        self.greeting = greeting
        self.weatherTemp = weatherTemp
        self.weatherCondition = weatherCondition
        self.weatherIcon = weatherIcon
        self.sleepDurationFormatted = sleepDurationFormatted
        self.sleepScore = sleepScore
        self.topFocusText = topFocusText
        self.isAiGenerated = isAiGenerated
    }
}

/// Combined Executive Snapshot encompassing all core pillars + Diurnal Briefing
public struct CombinedWidgetSnapshot: Sendable {
    public let bubbles: BubblesWidgetSnapshot
    public let smokes: SmokesWidgetSnapshot
    public let money: MoneyWidgetSnapshot
    public let sleep: SleepWidgetSnapshot
    public let tagdos: TagdosWidgetSnapshot
    public let stress: StressWidgetSnapshot
    public let morningSummary: BriefingSummarySnippet?
    public let isMorningSlot: Bool
    
    public init(
        bubbles: BubblesWidgetSnapshot,
        smokes: SmokesWidgetSnapshot,
        money: MoneyWidgetSnapshot,
        sleep: SleepWidgetSnapshot,
        tagdos: TagdosWidgetSnapshot,
        stress: StressWidgetSnapshot = .placeholder,
        morningSummary: BriefingSummarySnippet? = nil,
        isMorningSlot: Bool = false
    ) {
        self.bubbles = bubbles
        self.smokes = smokes
        self.money = money
        self.sleep = sleep
        self.tagdos = tagdos
        self.stress = stress
        self.morningSummary = morningSummary
        self.isMorningSlot = isMorningSlot
    }
}

/// Snapshot model for Sleep Studio Widget
public struct SleepWidgetSnapshot: Sendable, Codable {
    public let hasData: Bool
    public let sleepScore: Int
    public let sleepQualityRating: String
    public let totalAsleepFormatted: String
    public let asleepSeconds: Double
    public let durationSeconds: Double
    public let timeInBedFormatted: String
    public let efficiencyPercent: Int
    public let deepSeconds: Double
    public let remSeconds: Double
    public let lightSeconds: Double
    public let awakeSeconds: Double
    public let deepPercent: Int
    public let remPercent: Int
    public let lightPercent: Int
    public let awakePercent: Int
    public let deepFormatted: String
    public let remFormatted: String
    public let lightFormatted: String
    public let awakeFormatted: String
    public let bedtimeFormatted: String
    public let wakeTimeFormatted: String
    public let restorativePercent: Int
    public let restingHeartRate: Double?
    public let hrvMs: Double?
    public let sourceDevice: String
    public let lastUpdated: Date
    
    private enum CodingKeys: String, CodingKey {
        case hasData
        case sleepScore
        case sleepQualityRating
        case totalAsleepFormatted
        case asleepSeconds
        case durationSeconds
        case timeInBedFormatted
        case efficiencyPercent
        case deepSeconds
        case remSeconds
        case lightSeconds
        case awakeSeconds
        case deepPercent
        case remPercent
        case lightPercent
        case awakePercent
        case deepFormatted
        case remFormatted
        case lightFormatted
        case awakeFormatted
        case bedtimeFormatted
        case wakeTimeFormatted
        case restorativePercent
        case restingHeartRate
        case hrvMs
        case sourceDevice
        case lastUpdated
    }

    public init(
        hasData: Bool = true,
        sleepScore: Int,
        sleepQualityRating: String,
        totalAsleepFormatted: String,
        asleepSeconds: Double,
        durationSeconds: Double,
        timeInBedFormatted: String,
        efficiencyPercent: Int,
        deepSeconds: Double,
        remSeconds: Double,
        lightSeconds: Double,
        awakeSeconds: Double,
        deepPercent: Int,
        remPercent: Int,
        lightPercent: Int,
        awakePercent: Int,
        deepFormatted: String,
        remFormatted: String,
        lightFormatted: String,
        awakeFormatted: String,
        bedtimeFormatted: String,
        wakeTimeFormatted: String,
        restorativePercent: Int,
        restingHeartRate: Double? = nil,
        hrvMs: Double? = nil,
        sourceDevice: String = "Apple Watch",
        lastUpdated: Date = Date()
    ) {
        self.hasData = hasData
        self.sleepScore = sleepScore
        self.sleepQualityRating = sleepQualityRating
        self.totalAsleepFormatted = totalAsleepFormatted
        self.asleepSeconds = asleepSeconds
        self.durationSeconds = durationSeconds
        self.timeInBedFormatted = timeInBedFormatted
        self.efficiencyPercent = efficiencyPercent
        self.deepSeconds = deepSeconds
        self.remSeconds = remSeconds
        self.lightSeconds = lightSeconds
        self.awakeSeconds = awakeSeconds
        self.deepPercent = deepPercent
        self.remPercent = remPercent
        self.lightPercent = lightPercent
        self.awakePercent = awakePercent
        self.deepFormatted = deepFormatted
        self.remFormatted = remFormatted
        self.lightFormatted = lightFormatted
        self.awakeFormatted = awakeFormatted
        self.bedtimeFormatted = bedtimeFormatted
        self.wakeTimeFormatted = wakeTimeFormatted
        self.restorativePercent = restorativePercent
        self.restingHeartRate = restingHeartRate
        self.hrvMs = hrvMs
        self.sourceDevice = sourceDevice
        self.lastUpdated = lastUpdated
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sleepScore = try container.decode(Int.self, forKey: .sleepScore)
        let bedtimeFormatted = try container.decode(String.self, forKey: .bedtimeFormatted)
        let wakeTimeFormatted = try container.decode(String.self, forKey: .wakeTimeFormatted)
        let asleepSeconds = try container.decode(Double.self, forKey: .asleepSeconds)

        let decodedHasData = try container.decodeIfPresent(Bool.self, forKey: .hasData)
        if let explicit = decodedHasData {
            self.hasData = explicit
        } else {
            // Old snapshot migration: exclude legacy hardcoded mock placeholder
            let isOldHardcodedMock = (sleepScore == 84 && bedtimeFormatted == "23:14" && wakeTimeFormatted == "07:26")
            self.hasData = !isOldHardcodedMock && (asleepSeconds > 0)
        }

        self.sleepScore = sleepScore
        self.sleepQualityRating = try container.decode(String.self, forKey: .sleepQualityRating)
        self.totalAsleepFormatted = try container.decode(String.self, forKey: .totalAsleepFormatted)
        self.asleepSeconds = asleepSeconds
        self.durationSeconds = try container.decode(Double.self, forKey: .durationSeconds)
        self.timeInBedFormatted = try container.decode(String.self, forKey: .timeInBedFormatted)
        self.efficiencyPercent = try container.decode(Int.self, forKey: .efficiencyPercent)
        self.deepSeconds = try container.decode(Double.self, forKey: .deepSeconds)
        self.remSeconds = try container.decode(Double.self, forKey: .remSeconds)
        self.lightSeconds = try container.decode(Double.self, forKey: .lightSeconds)
        self.awakeSeconds = try container.decode(Double.self, forKey: .awakeSeconds)
        self.deepPercent = try container.decode(Int.self, forKey: .deepPercent)
        self.remPercent = try container.decode(Int.self, forKey: .remPercent)
        self.lightPercent = try container.decode(Int.self, forKey: .lightPercent)
        self.awakePercent = try container.decode(Int.self, forKey: .awakePercent)
        self.deepFormatted = try container.decode(String.self, forKey: .deepFormatted)
        self.remFormatted = try container.decode(String.self, forKey: .remFormatted)
        self.lightFormatted = try container.decode(String.self, forKey: .lightFormatted)
        self.awakeFormatted = try container.decode(String.self, forKey: .awakeFormatted)
        self.bedtimeFormatted = bedtimeFormatted
        self.wakeTimeFormatted = wakeTimeFormatted
        self.restorativePercent = try container.decode(Int.self, forKey: .restorativePercent)
        self.restingHeartRate = try container.decodeIfPresent(Double.self, forKey: .restingHeartRate)
        self.hrvMs = try container.decodeIfPresent(Double.self, forKey: .hrvMs)
        self.sourceDevice = try container.decodeIfPresent(String.self, forKey: .sourceDevice) ?? "Apple Watch"
        self.lastUpdated = try container.decodeIfPresent(Date.self, forKey: .lastUpdated) ?? Date()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hasData, forKey: .hasData)
        try container.encode(sleepScore, forKey: .sleepScore)
        try container.encode(sleepQualityRating, forKey: .sleepQualityRating)
        try container.encode(totalAsleepFormatted, forKey: .totalAsleepFormatted)
        try container.encode(asleepSeconds, forKey: .asleepSeconds)
        try container.encode(durationSeconds, forKey: .durationSeconds)
        try container.encode(timeInBedFormatted, forKey: .timeInBedFormatted)
        try container.encode(efficiencyPercent, forKey: .efficiencyPercent)
        try container.encode(deepSeconds, forKey: .deepSeconds)
        try container.encode(remSeconds, forKey: .remSeconds)
        try container.encode(lightSeconds, forKey: .lightSeconds)
        try container.encode(awakeSeconds, forKey: .awakeSeconds)
        try container.encode(deepPercent, forKey: .deepPercent)
        try container.encode(remPercent, forKey: .remPercent)
        try container.encode(lightPercent, forKey: .lightPercent)
        try container.encode(awakePercent, forKey: .awakePercent)
        try container.encode(deepFormatted, forKey: .deepFormatted)
        try container.encode(remFormatted, forKey: .remFormatted)
        try container.encode(lightFormatted, forKey: .lightFormatted)
        try container.encode(awakeFormatted, forKey: .awakeFormatted)
        try container.encode(bedtimeFormatted, forKey: .bedtimeFormatted)
        try container.encode(wakeTimeFormatted, forKey: .wakeTimeFormatted)
        try container.encode(restorativePercent, forKey: .restorativePercent)
        try container.encodeIfPresent(restingHeartRate, forKey: .restingHeartRate)
        try container.encodeIfPresent(hrvMs, forKey: .hrvMs)
        try container.encode(sourceDevice, forKey: .sourceDevice)
        try container.encode(lastUpdated, forKey: .lastUpdated)
    }
}

extension SleepWidgetSnapshot {
    public static var empty: SleepWidgetSnapshot {
        SleepWidgetSnapshot(
            hasData: false,
            sleepScore: 0,
            sleepQualityRating: "No Data",
            totalAsleepFormatted: "--",
            asleepSeconds: 0,
            durationSeconds: 0,
            timeInBedFormatted: "--",
            efficiencyPercent: 0,
            deepSeconds: 0,
            remSeconds: 0,
            lightSeconds: 0,
            awakeSeconds: 0,
            deepPercent: 0,
            remPercent: 0,
            lightPercent: 0,
            awakePercent: 0,
            deepFormatted: "--",
            remFormatted: "--",
            lightFormatted: "--",
            awakeFormatted: "--",
            bedtimeFormatted: "--:--",
            wakeTimeFormatted: "--:--",
            restorativePercent: 0,
            restingHeartRate: nil,
            hrvMs: nil,
            sourceDevice: "Apple Watch",
            lastUpdated: Date()
        )
    }

    public static var placeholder: SleepWidgetSnapshot {
        empty
    }
}

/// Snapshot model for Stress Level & Monkey Mascot Widget
public struct StressWidgetSnapshot: Sendable, Codable {
    public let hasData: Bool
    public let stressScore: Int
    public let levelRaw: String
    public let monkeyMoodRaw: String
    public let adviceSnippet: String
    public let hrvMs: Double?
    public let restingHeartRate: Double?
    public let parasympatheticPercent: Int
    public let sympatheticPercent: Int
    public let lastUpdated: Date
    
    public init(
        hasData: Bool = true,
        stressScore: Int = 38,
        levelRaw: String = "Calm",
        monkeyMoodRaw: String = "Curious Monkey",
        adviceSnippet: String = "Autonomic tone is balanced. Keep up this steady groove!",
        hrvMs: Double? = 48,
        restingHeartRate: Double? = 62,
        parasympatheticPercent: Int = 62,
        sympatheticPercent: Int = 38,
        lastUpdated: Date = Date()
    ) {
        self.hasData = hasData
        self.stressScore = stressScore
        self.levelRaw = levelRaw
        self.monkeyMoodRaw = monkeyMoodRaw
        self.adviceSnippet = adviceSnippet
        self.hrvMs = hrvMs
        self.restingHeartRate = restingHeartRate
        self.parasympatheticPercent = parasympatheticPercent
        self.sympatheticPercent = sympatheticPercent
        self.lastUpdated = lastUpdated
    }
    
    public var level: StressLevel {
        StressLevel(rawValue: levelRaw) ?? .calm
    }
    
    public var monkeyMood: MonkeyMood {
        MonkeyMood(rawValue: monkeyMoodRaw) ?? .curious
    }
    
    public static var empty: StressWidgetSnapshot {
        StressWidgetSnapshot(
            hasData: false,
            stressScore: 35,
            levelRaw: "Calm",
            monkeyMoodRaw: "Curious Monkey",
            adviceSnippet: "Wear your Apple Watch to track real-time stress and HRV.",
            hrvMs: nil,
            restingHeartRate: nil,
            parasympatheticPercent: 65,
            sympatheticPercent: 35,
            lastUpdated: Date()
        )
    }
    
    public static var placeholder: StressWidgetSnapshot {
        StressWidgetSnapshot(
            hasData: true,
            stressScore: 32,
            levelRaw: "Calm",
            monkeyMoodRaw: "Curious Monkey",
            adviceSnippet: "Autonomic system is well balanced. Keep this steady groove going!",
            hrvMs: 52,
            restingHeartRate: 59,
            parasympatheticPercent: 68,
            sympatheticPercent: 32,
            lastUpdated: Date()
        )
    }
}

/// Central data coordinator managing 0ms read/write between the Main App and WidgetKit Extension.
public final class WidgetDataCoordinator: @unchecked Sendable {
    public static let shared = WidgetDataCoordinator()
    
    private let groupSuiteName = "group.com.intellidream.daily"
    private var groupDefaults: UserDefaults {
        UserDefaults(suiteName: groupSuiteName) ?? UserDefaults.standard
    }
    
    private let isoDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    
    private var todayKey: String {
        isoDateFormatter.string(from: Date())
    }
    
    // MARK: - Bubbles (Hydration)
    
    public func fetchBubblesSnapshot() -> BubblesWidgetSnapshot {
        let key = todayKey
        
        // 1. Goal
        let goalStr = groupDefaults.string(forKey: "water_goal") ?? "2000"
        let goal = Double(goalStr) ?? (groupDefaults.value(forKey: "water_goal") as? Double ?? 2000)
        
        // 2. Today's total
        var totalMl = 0.0
        if let wData = groupDefaults.data(forKey: "habits_water_daily_totals"),
           let dict = try? JSONDecoder().decode([String: Double].self, from: wData) {
            totalMl = dict[key] ?? 0
        }
        
        // 3. Breakdown from local logs
        var waterMl = 0.0
        var coffeeMl = 0.0
        var teaMl = 0.0
        var otherDrinks: [String: Double] = [:]
        var lastLogged: Date? = nil
        
        let deletedIds = Set(groupDefaults.stringArray(forKey: "deleted_habit_log_ids") ?? [])
        if let logsData = groupDefaults.data(forKey: "local_water_logs_\(key)"),
           let logs = try? JSONDecoder().decode([HabitLogRecord].self, from: logsData) {
            let activeLogs = logs.filter { !deletedIds.contains($0.id.uuidString) }
            lastLogged = activeLogs.first?.loggedAt
            for log in activeLogs {
                let drink = (log.parsedDrink ?? "").lowercased()
                if drink.contains("coffee") || drink.contains("espresso") || drink.contains("latte") {
                    coffeeMl += log.value
                } else if drink.contains("tea") || drink.contains("matcha") || drink.contains("infusion") {
                    teaMl += log.value
                } else if drink.contains("water") || drink.contains("glass") || drink.contains("bottle") || drink.isEmpty {
                    waterMl += log.value
                } else {
                    let dName = log.parsedDrink ?? "Other"
                    otherDrinks[dName, default: 0] += log.value
                }
            }
        } else {
            waterMl = totalMl
        }
        
        var breakdown: [(name: String, amount: Double, hexColor: String)] = []
        if waterMl > 0 { breakdown.append(("Water", waterMl, "#00E5FF")) }
        if coffeeMl > 0 { breakdown.append(("Coffee", coffeeMl, "#F59E0B")) }
        if teaMl > 0 { breakdown.append(("Tea", teaMl, "#84CC16")) }
        for (name, amt) in otherDrinks.sorted(by: { $0.value > $1.value }) {
            breakdown.append((name, amt, "#EC4899"))
        }
        if breakdown.isEmpty && totalMl > 0 {
            breakdown.append(("Water", totalMl, "#00E5FF"))
        }
        
        let progress = goal > 0 ? min(max(totalMl / goal, 0.0), 1.0) : 0.0
        return BubblesWidgetSnapshot(
            todayMl: totalMl,
            goalMl: goal,
            progressPercent: progress,
            waterMl: waterMl,
            coffeeMl: coffeeMl,
            teaMl: teaMl,
            drinkBreakdown: breakdown,
            lastLoggedAt: lastLogged
        )
    }
    
    private var cachedUserId: UUID? {
        if let idStr = groupDefaults.string(forKey: "authenticated_user_id") ?? groupDefaults.string(forKey: "current_user_id") {
            return UUID(uuidString: idStr)
        }
        return nil
    }
    
    public func logWater(amountMl: Double, drinkType: String = "Water") {
        let key = todayKey
        let now = Date()
        
        // 1. Update daily totals
        var totals: [String: Double] = [:]
        if let wData = groupDefaults.data(forKey: "habits_water_daily_totals"),
           let decoded = try? JSONDecoder().decode([String: Double].self, from: wData) {
            totals = decoded
        }
        totals[key, default: 0] += amountMl
        if let encoded = try? JSONEncoder().encode(totals) {
            groupDefaults.set(encoded, forKey: "habits_water_daily_totals")
        }
        groupDefaults.set(Int(totals[key] ?? 0), forKey: "cached_water_total")
        
        // 2. Append to local logs
        let metaDict = ["drink": drinkType]
        let metaJson = (try? JSONSerialization.data(withJSONObject: metaDict, options: []))
            .flatMap { String(data: $0, encoding: .utf8) }
        
        let newRecord = HabitLogRecord(
            id: UUID(),
            userId: cachedUserId,
            habitType: "water",
            value: amountMl,
            unit: "ml",
            loggedAt: now,
            metadata: metaJson,
            createdAt: now,
            updatedAt: now,
            isDeleted: false
        )
        
        var logs: [HabitLogRecord] = []
        if let logsData = groupDefaults.data(forKey: "local_water_logs_\(key)"),
           let decoded = try? JSONDecoder().decode([HabitLogRecord].self, from: logsData) {
            logs = decoded
        }
        logs.insert(newRecord, at: 0)
        if let encoded = try? JSONEncoder().encode(logs) {
            groupDefaults.set(encoded, forKey: "local_water_logs_\(key)")
        }
        
        // 3. Queue for Supabase background sync
        var queue: [HabitLogRecord] = []
        if let qData = groupDefaults.data(forKey: "offline_habits_queue"),
           let decoded = try? JSONDecoder().decode([HabitLogRecord].self, from: qData) {
            queue = decoded
        }
        queue.append(newRecord)
        if let encoded = try? JSONEncoder().encode(queue) {
            groupDefaults.set(encoded, forKey: "offline_habits_queue")
        }
        
        // 4. Reload Widget Timelines
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
    
    // MARK: - Smokes (Tobacco & Cessation)
    
    public func fetchSmokesSnapshot() -> SmokesWidgetSnapshot {
        let key = todayKey
        
        // 1. Baseline
        let baselineStr = groupDefaults.string(forKey: "smokes_baseline") ?? "20"
        let baseline = Int(baselineStr) ?? (groupDefaults.value(forKey: "smokes_baseline") as? Int ?? 20)
        
        // 2. Today's total
        var totalSmokes = 0
        if let sData = groupDefaults.data(forKey: "habits_smokes_daily_totals"),
           let dict = try? JSONDecoder().decode([String: Int].self, from: sData) {
            totalSmokes = dict[key] ?? 0
        }
        
        // 3. Breakdown from local logs
        var cigsCount = 0
        var heatedCount = 0
        var rolledCount = 0
        var cigarilloCount = 0
        var lastSmokeDate: Date? = nil
        
        let deletedIds = Set(groupDefaults.stringArray(forKey: "deleted_habit_log_ids") ?? [])
        if let logsData = groupDefaults.data(forKey: "local_smokes_logs_\(key)"),
           let logs = try? JSONDecoder().decode([HabitLogRecord].self, from: logsData) {
            let activeLogs = logs.filter { !deletedIds.contains($0.id.uuidString) }
            lastSmokeDate = activeLogs.first?.loggedAt
            for log in activeLogs {
                let type = (log.smokeType).lowercased()
                let count = Int(log.value)
                if type.contains("cigarette") || type == "cig" || type.contains("standard") {
                    cigsCount += count
                } else if type.contains("heat") || type.contains("iqos") {
                    heatedCount += count
                } else if type.contains("cigarillo") || (type.contains("cigar") && !type.contains("cigarette")) {
                    cigarilloCount += count
                } else if type.contains("roll") {
                    rolledCount += count
                } else {
                    cigsCount += count
                }
            }
        } else {
            cigsCount = totalSmokes
        }
        
        var breakdown: [(name: String, count: Int, hexColor: String)] = []
        if cigsCount > 0 { breakdown.append(("Cigarette", cigsCount, "#EF4444")) }
        if heatedCount > 0 { breakdown.append(("Heated", heatedCount, "#3B82F6")) }
        if rolledCount > 0 { breakdown.append(("Rolled", rolledCount, "#F97316")) }
        if cigarilloCount > 0 { breakdown.append(("Cigarillo", cigarilloCount, "#A855F7")) }
        if breakdown.isEmpty && totalSmokes > 0 {
            breakdown.append(("Cigarette", totalSmokes, "#EF4444"))
        }
        
        // Standard pack price ~25 Lei for 20 sticks = 1.25 Lei per smoke
        let spent = Double(totalSmokes) * 1.25
        
        return SmokesWidgetSnapshot(
            todayTotal: totalSmokes,
            baseline: baseline,
            cigsCount: cigsCount,
            heatedCount: heatedCount,
            rolledCount: rolledCount,
            cigarilloCount: cigarilloCount,
            smokeBreakdown: breakdown,
            lastSmokeDate: lastSmokeDate,
            spentTodayLei: spent
        )
    }
    
    public func logSmoke(preset: SmokePreset = .cigarette) {
        let key = todayKey
        let now = Date()
        
        // 1. Update daily totals
        var totals: [String: Int] = [:]
        if let sData = groupDefaults.data(forKey: "habits_smokes_daily_totals"),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: sData) {
            totals = decoded
        }
        totals[key, default: 0] += 1
        if let encoded = try? JSONEncoder().encode(totals) {
            groupDefaults.set(encoded, forKey: "habits_smokes_daily_totals")
        }
        groupDefaults.set(totals[key] ?? 0, forKey: "cached_smokes_total")
        
        // 2. Append to local logs
        let metaDict = ["type": preset.rawValue]
        let metaJson = (try? JSONSerialization.data(withJSONObject: metaDict, options: []))
            .flatMap { String(data: $0, encoding: .utf8) }
        
        let newRecord = HabitLogRecord(
            id: UUID(),
            userId: cachedUserId,
            habitType: "smokes",
            value: 1.0,
            unit: "cigs",
            loggedAt: now,
            metadata: metaJson,
            createdAt: now,
            updatedAt: now,
            isDeleted: false
        )
        
        var logs: [HabitLogRecord] = []
        if let logsData = groupDefaults.data(forKey: "local_smokes_logs_\(key)"),
           let decoded = try? JSONDecoder().decode([HabitLogRecord].self, from: logsData) {
            logs = decoded
        }
        logs.insert(newRecord, at: 0)
        if let encoded = try? JSONEncoder().encode(logs) {
            groupDefaults.set(encoded, forKey: "local_smokes_logs_\(key)")
        }
        
        // 3. Queue for Supabase background sync
        var queue: [HabitLogRecord] = []
        if let qData = groupDefaults.data(forKey: "offline_habits_queue"),
           let decoded = try? JSONDecoder().decode([HabitLogRecord].self, from: qData) {
            queue = decoded
        }
        queue.append(newRecord)
        if let encoded = try? JSONEncoder().encode(queue) {
            groupDefaults.set(encoded, forKey: "offline_habits_queue")
        }
        
        // 4. Reload Widget Timelines
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
    
    // MARK: - Money (SmartLedger)
    
    private let ledgerStorageKey = "daily_smart_ledger_raw_text_v1"
    
    public func fetchMoneySnapshot() -> MoneyWidgetSnapshot {
        let rawText = groupDefaults.string(forKey: ledgerStorageKey) ?? SmartLedgerStore.defaultLedgerText
        let ledger = SmartLedgerParser.shared.parse(rawText)
        
        var card = 0.0
        var cash = 0.0
        if let incoming = ledger.sections.first(where: { $0.name.caseInsensitiveCompare("Incoming") == .orderedSame }) {
            if let cardItem = incoming.items.first(where: { $0.key.caseInsensitiveCompare("Card") == .orderedSame }) {
                card = cardItem.calculatedAmount
            }
            if let cashItem = incoming.items.first(where: { $0.key.caseInsensitiveCompare("Cash") == .orderedSame }) {
                cash = cashItem.calculatedAmount
            }
        }
        
        var topOutgoing: [(name: String, amount: Double)] = []
        if let outgoing = ledger.sections.first(where: { $0.name.caseInsensitiveCompare("Outgoing") == .orderedSame }) {
            topOutgoing = outgoing.items
                .filter { !$0.isPureNote && $0.calculatedAmount > 0 }
                .sorted { $0.calculatedAmount > $1.calculatedAmount }
                .prefix(3)
                .map { (name: $0.displayName, amount: $0.calculatedAmount) }
        }
        
        return MoneyWidgetSnapshot(
            netWorthLei: ledger.netWorth,
            netWorthEUR: ledger.netWorthEUR,
            formattedNetWorth: ledger.formattedNetWorth,
            formattedNetWorthEUR: ledger.formattedNetWorthEUR,
            incomingTotal: ledger.incomingTotal,
            outgoingTotal: ledger.outgoingTotal,
            depositsTotal: ledger.depositTotal,
            cardAmount: card,
            cashAmount: cash,
            topOutgoingAllocations: topOutgoing
        )
    }
    
    /// Adjusts an account amount by a real currency amount (e.g. -100 Lei or +100 Lei).
    /// Automatically converts to DSL units if the underlying section is scaled (1 unit = 100 Lei).
    public func adjustLedgerAmount(accountName: String, deltaReal: Double) {
        let rawText = groupDefaults.string(forKey: ledgerStorageKey) ?? SmartLedgerStore.defaultLedgerText
        let ledger = SmartLedgerParser.shared.parse(rawText)
        
        guard let incoming = ledger.sections.first(where: { $0.name.caseInsensitiveCompare("Incoming") == .orderedSame }),
              let item = incoming.items.first(where: { $0.key.caseInsensitiveCompare(accountName) == .orderedSame }) else {
            return
        }
        
        // In scaled sections (e.g. Incoming where 1 unit = 100 Lei), deltaRaw = deltaReal / 100.0
        let deltaRaw = item.isScaled ? (deltaReal / 100.0) : deltaReal
        let updatedText = SmartLedgerParser.shared.adjustItemAmount(in: rawText, lineIndex: item.lineIndex, deltaRaw: deltaRaw)
        groupDefaults.set(updatedText, forKey: ledgerStorageKey)
        UserDefaults.standard.set(updatedText, forKey: ledgerStorageKey)
        
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
    
    public func adjustLedgerAmount(accountName: String, deltaRaw: Double) {
        let rawText = groupDefaults.string(forKey: ledgerStorageKey) ?? SmartLedgerStore.defaultLedgerText
        let ledger = SmartLedgerParser.shared.parse(rawText)
        
        guard let incoming = ledger.sections.first(where: { $0.name.caseInsensitiveCompare("Incoming") == .orderedSame }),
              let item = incoming.items.first(where: { $0.key.caseInsensitiveCompare(accountName) == .orderedSame }) else {
            return
        }
        
        let updatedText = SmartLedgerParser.shared.adjustItemAmount(in: rawText, lineIndex: item.lineIndex, deltaRaw: deltaRaw)
        groupDefaults.set(updatedText, forKey: ledgerStorageKey)
        UserDefaults.standard.set(updatedText, forKey: ledgerStorageKey)
        
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
    
    // MARK: - Sleep (Sleep Studio)
    
    private let sleepSnapshotKey = "daily_sleep_widget_snapshot_v1"
    
    public func updateSleepSnapshot(from session: SleepSession?, restingHeartRate: Double? = nil, hrvMs: Double? = nil) {
        let snapshot: SleepWidgetSnapshot
        if let session = session, session.asleepSeconds > 0 {
            snapshot = SleepWidgetSnapshot(
                hasData: true,
                sleepScore: session.sleepScore,
                sleepQualityRating: session.sleepQualityRating,
                totalAsleepFormatted: session.totalAsleepFormatted,
                asleepSeconds: session.asleepSeconds,
                durationSeconds: session.durationSeconds,
                timeInBedFormatted: session.timeInBedFormatted,
                efficiencyPercent: session.efficiencyPercent,
                deepSeconds: session.deepSeconds,
                remSeconds: session.remSeconds,
                lightSeconds: session.lightSeconds,
                awakeSeconds: session.awakeSeconds,
                deepPercent: session.deepPercent,
                remPercent: session.remPercent,
                lightPercent: session.lightPercent,
                awakePercent: session.awakePercent,
                deepFormatted: session.deepFormatted,
                remFormatted: session.remFormatted,
                lightFormatted: session.lightFormatted,
                awakeFormatted: session.awakeFormatted,
                bedtimeFormatted: session.bedtimeFormatted,
                wakeTimeFormatted: session.wakeTimeFormatted,
                restorativePercent: session.restorativePercent,
                restingHeartRate: restingHeartRate,
                hrvMs: hrvMs,
                sourceDevice: session.sourceDevice,
                lastUpdated: Date()
            )
        } else {
            snapshot = SleepWidgetSnapshot.empty
        }
        
        if let data = try? JSONEncoder().encode(snapshot) {
            groupDefaults.set(data, forKey: sleepSnapshotKey)
            UserDefaults.standard.set(data, forKey: sleepSnapshotKey)
        }
        
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
    
    public func fetchSleepSnapshot() -> SleepWidgetSnapshot {
        if let data = groupDefaults.data(forKey: sleepSnapshotKey),
           let snapshot = try? JSONDecoder().decode(SleepWidgetSnapshot.self, from: data) {
            return snapshot
        }
        return SleepWidgetSnapshot.empty
    }
    
    // MARK: - Tagdos & Notes
    
    private let tagdosSnapshotKey = "daily_tagdos_widget_snapshot_v1"
    
    public func updateTagdosSnapshot(_ snapshot: TagdosWidgetSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            groupDefaults.set(data, forKey: tagdosSnapshotKey)
            UserDefaults.standard.set(data, forKey: tagdosSnapshotKey)
        }
        
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
    
    public func fetchTagdosSnapshot() -> TagdosWidgetSnapshot {
        if let data = groupDefaults.data(forKey: tagdosSnapshotKey),
           let snapshot = try? JSONDecoder().decode(TagdosWidgetSnapshot.self, from: data) {
            return snapshot
        }
        return TagdosWidgetSnapshot.empty
    }

    // MARK: - Stress Level & Monkey Mascot
    
    private let stressSnapshotKey = "daily_stress_widget_snapshot_v1"
    
    public func updateStressSnapshot(
        score: Int,
        level: StressLevel,
        monkeyMood: MonkeyMood,
        advice: String,
        hrvMs: Double?,
        restingHeartRate: Double?,
        parasympathetic: Int,
        sympathetic: Int
    ) {
        let snapshot = StressWidgetSnapshot(
            hasData: true,
            stressScore: score,
            levelRaw: level.rawValue,
            monkeyMoodRaw: monkeyMood.rawValue,
            adviceSnippet: advice,
            hrvMs: hrvMs,
            restingHeartRate: restingHeartRate,
            parasympatheticPercent: parasympathetic,
            sympatheticPercent: sympathetic,
            lastUpdated: Date()
        )
        
        if let data = try? JSONEncoder().encode(snapshot) {
            groupDefaults.set(data, forKey: stressSnapshotKey)
            UserDefaults.standard.set(data, forKey: stressSnapshotKey)
        }
        
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
    
    public func fetchStressSnapshot() -> StressWidgetSnapshot {
        if let data = groupDefaults.data(forKey: stressSnapshotKey),
           let snapshot = try? JSONDecoder().decode(StressWidgetSnapshot.self, from: data) {
            return snapshot
        }
        return StressWidgetSnapshot.placeholder
    }

    // MARK: - Combined Executive Snapshot (5 Core Pillars + Briefing)

    public func fetchCombinedSnapshot() -> CombinedWidgetSnapshot {
        let bubbles = fetchBubblesSnapshot()
        let smokes = fetchSmokesSnapshot()
        let money = fetchMoneySnapshot()
        let sleep = fetchSleepSnapshot()
        let tagdos = fetchTagdosSnapshot()
        let stress = fetchStressSnapshot()

        let hour = Calendar.current.component(.hour, from: Date())
        let isMorning = (hour >= 5 && hour < 12)

        var snippet: BriefingSummarySnippet? = nil
        let briefingCacheKey = "daily_smart_summary_cache_v4"
        if let data = groupDefaults.data(forKey: briefingCacheKey),
           let record = try? JSONDecoder().decode(SmartBriefingRecord.self, from: data) {
            let m = record.metrics
            let n = record.narrative

            let focus: String? = {
                if !n.tagdosText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return n.tagdosText
                } else if !n.healthText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return n.healthText
                } else {
                    return nil
                }
            }()

            snippet = BriefingSummarySnippet(
                greeting: BriefingTimeSlot.current().diurnalGreeting(for: "Mihai"),
                weatherTemp: m.weatherTemp,
                weatherCondition: m.weatherCondition,
                weatherIcon: m.weatherIcon,
                sleepDurationFormatted: m.sleepDurationFormatted,
                sleepScore: m.sleepScore,
                topFocusText: focus,
                isAiGenerated: record.isAiGenerated
            )
        } else {
            let primaryPill = tagdos.streams.first?.drivingPillText
            snippet = BriefingSummarySnippet(
                greeting: isMorning ? "Good Morning, Mihai" : "Welcome back, Mihai",
                weatherTemp: nil,
                weatherCondition: nil,
                weatherIcon: nil,
                sleepDurationFormatted: sleep.hasData ? sleep.totalAsleepFormatted : nil,
                sleepScore: sleep.hasData ? sleep.sleepScore : nil,
                topFocusText: primaryPill != nil ? "Focus: \(primaryPill!)" : nil,
                isAiGenerated: false
            )
        }

        return CombinedWidgetSnapshot(
            bubbles: bubbles,
            smokes: smokes,
            money: money,
            sleep: sleep,
            tagdos: tagdos,
            stress: stress,
            morningSummary: snippet,
            isMorningSlot: isMorning
        )
    }
}

