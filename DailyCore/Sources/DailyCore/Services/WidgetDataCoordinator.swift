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
    public let sourceColor: String?
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
        case sourceColor
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
        sourceColor: String? = nil,
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
        self.sourceColor = sourceColor ?? DeviceColorPalette.getColor(for: sourceDevice)
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
        let dev = try container.decodeIfPresent(String.self, forKey: .sourceDevice) ?? "Apple Watch"
        self.sourceDevice = dev
        self.sourceColor = try container.decodeIfPresent(String.self, forKey: .sourceColor) ?? DeviceColorPalette.getColor(for: dev)
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
        try container.encodeIfPresent(sourceColor, forKey: .sourceColor)
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

/// Snapshot model for Cosmos & Night Sky Observatory Widget
public struct CosmosWidgetSnapshot: Sendable, Codable {
    public let stargazingScore: Int
    public let stargazingVerdict: String
    public let qualityHexColor: String
    public let moonPhaseName: String
    public let moonIlluminationPercent: Int
    public let moonSymbol: String
    public let visiblePlanetsCount: Int
    public let topPlanetsSummary: String
    public let bestWindowLabel: String
    public let nextIssPassSummary: String?
    public let kpIndex: Double?
    public let bortleClass: Int
    public let provenanceBadge: String
    public let lastUpdated: Date

    public init(
        stargazingScore: Int,
        stargazingVerdict: String,
        qualityHexColor: String,
        moonPhaseName: String,
        moonIlluminationPercent: Int,
        moonSymbol: String,
        visiblePlanetsCount: Int,
        topPlanetsSummary: String,
        bestWindowLabel: String,
        nextIssPassSummary: String? = nil,
        kpIndex: Double? = nil,
        bortleClass: Int = 5,
        provenanceBadge: String = "Offline Ephemeris",
        lastUpdated: Date = Date()
    ) {
        self.stargazingScore = stargazingScore
        self.stargazingVerdict = stargazingVerdict
        self.qualityHexColor = qualityHexColor
        self.moonPhaseName = moonPhaseName
        self.moonIlluminationPercent = moonIlluminationPercent
        self.moonSymbol = moonSymbol
        self.visiblePlanetsCount = visiblePlanetsCount
        self.topPlanetsSummary = topPlanetsSummary
        self.bestWindowLabel = bestWindowLabel
        self.nextIssPassSummary = nextIssPassSummary
        self.kpIndex = kpIndex
        self.bortleClass = bortleClass
        self.provenanceBadge = provenanceBadge
        self.lastUpdated = lastUpdated
    }
}

/// Hourly forecast item for Weather Widget
public struct WeatherWidgetHourlyItem: Sendable, Codable {
    public let timeLabel: String
    public let temp: Double
    public let iconCode: String
    public let popPercent: Int

    public init(timeLabel: String, temp: Double, iconCode: String, popPercent: Int = 0) {
        self.timeLabel = timeLabel
        self.temp = temp
        self.iconCode = iconCode
        self.popPercent = popPercent
    }
}

/// Daily forecast item for Weather Widget
public struct WeatherWidgetDailyItem: Sendable, Codable {
    public let dayName: String
    public let tempMin: Double
    public let tempMax: Double
    public let iconCode: String
    public let popPercent: Int

    public init(dayName: String, tempMin: Double, tempMax: Double, iconCode: String, popPercent: Int = 0) {
        self.dayName = dayName
        self.tempMin = tempMin
        self.tempMax = tempMax
        self.iconCode = iconCode
        self.popPercent = popPercent
    }
}

/// Snapshot model for Weather & Atmospheric Forecast Widget
public struct WeatherWidgetSnapshot: Sendable, Codable {
    public let hasData: Bool
    public let cityName: String
    public let temp: Double
    public let feelsLike: Double
    public let tempMin: Double
    public let tempMax: Double
    public let conditionText: String
    public let iconCode: String
    public let humidityPercent: Int
    public let windSpeed: Double
    public let windUnit: String
    public let hourly: [WeatherWidgetHourlyItem]
    public let daily: [WeatherWidgetDailyItem]
    public let lastUpdated: Date

    public init(
        hasData: Bool = true,
        cityName: String,
        temp: Double,
        feelsLike: Double,
        tempMin: Double,
        tempMax: Double,
        conditionText: String,
        iconCode: String,
        humidityPercent: Int,
        windSpeed: Double,
        windUnit: String = "m/s",
        hourly: [WeatherWidgetHourlyItem] = [],
        daily: [WeatherWidgetDailyItem] = [],
        lastUpdated: Date = Date()
    ) {
        self.hasData = hasData
        self.cityName = cityName
        self.temp = temp
        self.feelsLike = feelsLike
        self.tempMin = tempMin
        self.tempMax = tempMax
        self.conditionText = conditionText
        self.iconCode = iconCode
        self.humidityPercent = humidityPercent
        self.windSpeed = windSpeed
        self.windUnit = windUnit
        self.hourly = hourly
        self.daily = daily
        self.lastUpdated = lastUpdated
    }

    public static var placeholder: WeatherWidgetSnapshot {
        WeatherWidgetSnapshot(
            hasData: true,
            cityName: "Bucharest",
            temp: 19,
            feelsLike: 18,
            tempMin: 12,
            tempMax: 22,
            conditionText: "Clear Sky",
            iconCode: "01d",
            humidityPercent: 52,
            windSpeed: 2.8,
            windUnit: "m/s",
            hourly: [
                WeatherWidgetHourlyItem(timeLabel: "Now", temp: 19, iconCode: "01d"),
                WeatherWidgetHourlyItem(timeLabel: "15:00", temp: 21, iconCode: "01d"),
                WeatherWidgetHourlyItem(timeLabel: "18:00", temp: 18, iconCode: "02d"),
                WeatherWidgetHourlyItem(timeLabel: "21:00", temp: 15, iconCode: "01n")
            ],
            daily: [
                WeatherWidgetDailyItem(dayName: "Today", tempMin: 12, tempMax: 22, iconCode: "01d"),
                WeatherWidgetDailyItem(dayName: "Sat", tempMin: 11, tempMax: 20, iconCode: "02d"),
                WeatherWidgetDailyItem(dayName: "Sun", tempMin: 10, tempMax: 18, iconCode: "10d", popPercent: 40)
            ]
        )
    }

    public static var empty: WeatherWidgetSnapshot {
        WeatherWidgetSnapshot(
            hasData: false,
            cityName: "Local Area",
            temp: 0,
            feelsLike: 0,
            tempMin: 0,
            tempMax: 0,
            conditionText: "Syncing Weather",
            iconCode: "02d",
            humidityPercent: 0,
            windSpeed: 0
        )
    }
}

/// Central data coordinator managing 0ms read/write between the Main App and WidgetKit Extension.
public final class WidgetDataCoordinator: @unchecked Sendable {
    public static let shared = WidgetDataCoordinator()
    public static let darwinMutationNotificationName = "com.intellidream.daily.widgetDidMutateData"
    
    private let groupSuiteName = "group.com.intellidream.daily"
    private var groupDefaults: UserDefaults {
        UserDefaults(suiteName: groupSuiteName) ?? UserDefaults.standard
    }

    private func postCrossProcessMutationNotification() {
        #if os(macOS) || os(iOS)
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName(Self.darwinMutationNotificationName as CFString),
            nil,
            nil,
            true
        )
        #endif
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
                let rawDrink = log.parsedDrink ?? ""
                let drink = rawDrink.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if drink.contains("coffee") || drink.contains("espresso") || drink.contains("latte") || drink.contains("cappuccino") || drink.contains("cafea") {
                    coffeeMl += log.value
                } else if drink.contains("tea") || drink.contains("matcha") || drink.contains("infusion") || drink.contains("ceai") {
                    teaMl += log.value
                } else if drink.contains("water") || drink.contains("apa") || drink.contains("apă") ||
                          drink.contains("glass") || drink.contains("bottle") ||
                          drink.contains("small") || drink.contains("large") ||
                          drink.contains("pahar") || drink.contains("sticla") || drink.contains("sticlă") ||
                          drink.contains("sparkling") || drink.contains("still") ||
                          drink.contains("drop") || drink.isEmpty {
                    waterMl += log.value
                } else if let matched = WaterPreset.matching(rawDrink) {
                    if matched == .coffee {
                        coffeeMl += log.value
                    } else if matched == .tea {
                        teaMl += log.value
                    } else {
                        waterMl += log.value
                    }
                } else {
                    let dName = rawDrink.isEmpty ? "Water" : rawDrink
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
            let matched = WaterPreset.matching(name)
            let color = matched?.hexColor ?? "#00E5FF"
            breakdown.append((name, amt, color))
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
        for key in ["supabase_user_id", "authenticated_user_id", "current_user_id"] {
            if let idStr = groupDefaults.string(forKey: key), !idStr.isEmpty, idStr.lowercased() != "guest",
               let uuid = UUID(uuidString: idStr) {
                return uuid
            }
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
        
        // 4. Reload Widget Timelines & notify running app process
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        postCrossProcessMutationNotification()
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
        
        // 4. Reload Widget Timelines & notify running app process
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        postCrossProcessMutationNotification()
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
    
    private let ledgerLocalModifiedKey = "daily_smart_ledger_local_modified_at_v1"

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
        groupDefaults.set(Date().timeIntervalSince1970, forKey: ledgerLocalModifiedKey)
        UserDefaults.standard.set(updatedText, forKey: ledgerStorageKey)
        
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        postCrossProcessMutationNotification()
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
        groupDefaults.set(Date().timeIntervalSince1970, forKey: ledgerLocalModifiedKey)
        UserDefaults.standard.set(updatedText, forKey: ledgerStorageKey)
        
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        postCrossProcessMutationNotification()
    }
    
    // MARK: - Sleep (Sleep Studio)
    
    private let sleepSnapshotKey = "daily_sleep_widget_snapshot_v1"
    
    public func updateSleepSnapshot(from session: SleepSession?, restingHeartRate: Double? = nil, hrvMs: Double? = nil) {
        let snapshot: SleepWidgetSnapshot
        if let session = session, session.asleepSeconds > 0 {
            let color = DeviceColorPalette.getColor(for: session.sourceDevice)
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
                sourceColor: color,
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
    
    public func clearStressSnapshot() {
        let snapshot = StressWidgetSnapshot.empty
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
        return StressWidgetSnapshot.empty
    }

    // MARK: - Cosmos & Night Sky Observatory

    private let cosmosSnapshotKey = "daily_cosmos_widget_snapshot_v1"

    public func updateCosmosSnapshot(
        latitude: Double,
        longitude: Double,
        stargazing: StargazingConditions?,
        nextIssPass: SatellitePass?,
        spaceWeather: SpaceWeatherReport?
    ) {
        let now = Date()
        let obs = (latitude: latitude, longitude: longitude)
        let obs3 = (latitude: latitude, longitude: longitude, elevation: 50.0)
        let moon = AstronomyService.shared.moonPhase(at: now, observer: obs)
        let cond = stargazing ?? AstronomyService.shared.evaluateStargazingConditions(
            observer: obs,
            date: now,
            cloudCoverTotal: nil,
            cloudCoverLow: nil,
            cloudCoverMid: nil,
            cloudCoverHigh: nil
        )

        var visibleNames: [String] = []
        for p in [CelestialBody.venus, .jupiter, .saturn, .mars, .mercury, .uranus, .neptune] {
            if AstronomyService.shared.coordinates(of: p, for: obs3, at: now).altitudeDegrees > 0.0 {
                visibleNames.append(p.displayName)
            }
        }
        let topSummary = visibleNames.isEmpty ? "Solar bodies below horizon" : visibleNames.prefix(3).joined(separator: " · ")

        let issText: String? = nextIssPass.map { pass in
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.dateFormat = "HH:mm"
            return "ISS \(fmt.string(from: pass.startTime)) (\(Int(pass.maxAltitudeDegrees.rounded()))°)"
        }

        let snapshot = CosmosWidgetSnapshot(
            stargazingScore: cond.score,
            stargazingVerdict: cond.quality.displayName,
            qualityHexColor: cond.quality.colorHex,
            moonPhaseName: moon.quarter.displayName,
            moonIlluminationPercent: Int((moon.illuminatedFraction * 100.0).rounded()),
            moonSymbol: moon.quarter.sfSymbol,
            visiblePlanetsCount: visibleNames.count,
            topPlanetsSummary: topSummary,
            bestWindowLabel: cond.bestWindowDescription ?? "Calculated at dusk",
            nextIssPassSummary: issText,
            kpIndex: spaceWeather?.kpIndex,
            bortleClass: cond.bortleClass,
            provenanceBadge: cond.provenance.badgeLabel,
            lastUpdated: now
        )

        if let data = try? JSONEncoder().encode(snapshot) {
            groupDefaults.set(data, forKey: cosmosSnapshotKey)
            UserDefaults.standard.set(data, forKey: cosmosSnapshotKey)
        }

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    public func fetchCosmosSnapshot() -> CosmosWidgetSnapshot {
        let now = Date()
        let lat = groupDefaults.object(forKey: "weather_cached_lat") as? Double ?? 44.4268
        let lon = groupDefaults.object(forKey: "weather_cached_lon") as? Double ?? 26.1025
        let obs = (latitude: lat, longitude: lon)
        let obs3 = (latitude: lat, longitude: lon, elevation: 50.0)
        let moon = AstronomyService.shared.moonPhase(at: now, observer: obs)
        var visibleNames: [String] = []
        for p in [CelestialBody.venus, .jupiter, .saturn, .mars, .mercury, .uranus, .neptune] {
            if AstronomyService.shared.coordinates(of: p, for: obs3, at: now).altitudeDegrees > 0.0 {
                visibleNames.append(p.displayName)
            }
        }
        let topSummary = visibleNames.isEmpty ? "Solar bodies below horizon" : visibleNames.prefix(3).joined(separator: " · ")

        if let data = groupDefaults.data(forKey: cosmosSnapshotKey),
           let snapshot = try? JSONDecoder().decode(CosmosWidgetSnapshot.self, from: data) {
            // If cached snapshot exists (< 24 hours), preserve honest weather/seeing score and Bortle
            // while recalculating real-time celestial positions (moon and visible planets).
            if abs(now.timeIntervalSince(snapshot.lastUpdated)) < 86400 {
                return CosmosWidgetSnapshot(
                    stargazingScore: snapshot.stargazingScore,
                    stargazingVerdict: snapshot.stargazingVerdict,
                    qualityHexColor: snapshot.qualityHexColor,
                    moonPhaseName: moon.quarter.displayName,
                    moonIlluminationPercent: Int((moon.illuminatedFraction * 100.0).rounded()),
                    moonSymbol: moon.quarter.sfSymbol,
                    visiblePlanetsCount: visibleNames.count,
                    topPlanetsSummary: topSummary,
                    bestWindowLabel: snapshot.bestWindowLabel,
                    nextIssPassSummary: snapshot.nextIssPassSummary,
                    kpIndex: snapshot.kpIndex,
                    bortleClass: snapshot.bortleClass,
                    provenanceBadge: snapshot.provenanceBadge,
                    lastUpdated: snapshot.lastUpdated
                )
            }
        }

        // Deterministic live astronomical calculation when cache is completely cold
        let bortle = CosmosCatalogService.shared.bortleClass(latitude: lat, longitude: lon)
        let cond = AstronomyService.shared.evaluateStargazingConditions(
            observer: obs,
            date: now,
            cloudCoverTotal: nil,
            cloudCoverLow: nil,
            cloudCoverMid: nil,
            cloudCoverHigh: nil,
            bortleClass: bortle
        )
        return CosmosWidgetSnapshot(
            stargazingScore: cond.score,
            stargazingVerdict: cond.quality.displayName,
            qualityHexColor: cond.quality.colorHex,
            moonPhaseName: moon.quarter.displayName,
            moonIlluminationPercent: Int((moon.illuminatedFraction * 100.0).rounded()),
            moonSymbol: moon.quarter.sfSymbol,
            visiblePlanetsCount: visibleNames.count,
            topPlanetsSummary: topSummary,
            bestWindowLabel: cond.bestWindowDescription ?? "Calculated at dusk",
            nextIssPassSummary: nil,
            kpIndex: nil,
            bortleClass: cond.bortleClass,
            provenanceBadge: cond.provenance.badgeLabel,
            lastUpdated: now
        )
    }

    // MARK: - Weather & Atmospheric Forecast

    private let weatherSnapshotKey = "daily_weather_widget_snapshot_v1"

    public func updateWeatherSnapshot(
        cityName: String,
        current: WeatherResponse,
        hourlyItems: [ForecastItem],
        dailyItems: [DailyForecastSummary],
        latitude: Double,
        longitude: Double,
        isImperial: Bool = false
    ) {
        groupDefaults.set(latitude, forKey: "weather_cached_lat")
        groupDefaults.set(longitude, forKey: "weather_cached_lon")

        let hourFmt = DateFormatter()
        hourFmt.locale = Locale(identifier: "en_US_POSIX")
        hourFmt.dateFormat = "HH:mm"

        let hourly: [WeatherWidgetHourlyItem] = hourlyItems.prefix(6).enumerated().map { idx, item in
            WeatherWidgetHourlyItem(
                timeLabel: idx == 0 ? "Now" : hourFmt.string(from: item.date),
                temp: item.main.temp,
                iconCode: item.weather.first?.icon ?? "01d",
                popPercent: Int(((item.pop ?? 0) * 100).rounded())
            )
        }

        let daily: [WeatherWidgetDailyItem] = dailyItems.prefix(5).map { d in
            WeatherWidgetDailyItem(
                dayName: d.dayName,
                tempMin: d.tempMin,
                tempMax: d.tempMax,
                iconCode: d.iconCode,
                popPercent: Int((d.popMax * 100).rounded())
            )
        }

        let todayMin = dailyItems.first?.tempMin ?? current.main.tempMin
        let todayMax = dailyItems.first?.tempMax ?? current.main.tempMax
        let condText = current.weather.first?.description.capitalized ?? "Clear"
        let iconCode = current.weather.first?.icon ?? "01d"

        let snapshot = WeatherWidgetSnapshot(
            hasData: true,
            cityName: cityName.isEmpty ? (current.name.isEmpty ? "Local Area" : current.name) : cityName,
            temp: current.main.temp,
            feelsLike: current.main.feelsLike,
            tempMin: todayMin,
            tempMax: todayMax,
            conditionText: condText,
            iconCode: iconCode,
            humidityPercent: current.main.humidity,
            windSpeed: current.wind?.speed ?? 0,
            windUnit: isImperial ? "mph" : "m/s",
            hourly: hourly,
            daily: daily,
            lastUpdated: Date()
        )

        if let data = try? JSONEncoder().encode(snapshot) {
            groupDefaults.set(data, forKey: weatherSnapshotKey)
            UserDefaults.standard.set(data, forKey: weatherSnapshotKey)
        }

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    public func fetchWeatherSnapshot() -> WeatherWidgetSnapshot {
        if let data = groupDefaults.data(forKey: weatherSnapshotKey),
           let snapshot = try? JSONDecoder().decode(WeatherWidgetSnapshot.self, from: data) {
            return snapshot
        }
        return WeatherWidgetSnapshot.empty
    }

    // MARK: - Combined Executive Snapshot (5 Core Pillars + Briefing)

    public func fetchCombinedSnapshot() -> CombinedWidgetSnapshot {
        let bubbles = fetchBubblesSnapshot()
        let smokes = fetchSmokesSnapshot()
        let money = fetchMoneySnapshot()
        let sleep = fetchSleepSnapshot()
        let tagdos = fetchTagdosSnapshot()
        let stress = fetchStressSnapshot()
        let weather = fetchWeatherSnapshot()

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
                weatherTemp: m.weatherTemp ?? (weather.hasData ? weather.temp : nil),
                weatherCondition: m.weatherCondition ?? (weather.hasData ? weather.conditionText : nil),
                weatherIcon: m.weatherIcon ?? (weather.hasData ? weather.iconCode : nil),
                sleepDurationFormatted: m.sleepDurationFormatted,
                sleepScore: m.sleepScore,
                topFocusText: focus,
                isAiGenerated: record.isAiGenerated
            )
        } else {
            let primaryPill = tagdos.streams.first?.drivingPillText
            snippet = BriefingSummarySnippet(
                greeting: isMorning ? "Good Morning, Mihai" : "Welcome back, Mihai",
                weatherTemp: weather.hasData ? weather.temp : nil,
                weatherCondition: weather.hasData ? weather.conditionText : nil,
                weatherIcon: weather.hasData ? weather.iconCode : nil,
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

