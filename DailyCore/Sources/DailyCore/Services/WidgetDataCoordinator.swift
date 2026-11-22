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

/// Atomic App Group bridge payload keeping in-app habit logs/totals and WidgetKit extensions
/// synchronized without UserDefaults/cfprefsd cross-process flush lag.
public struct HabitsWidgetBridgeState: Codable, Sendable {
    public let dateKey: String
    public let waterTotalMl: Double
    public let waterGoalMl: Double
    public let waterLogs: [HabitLogRecord]
    public let smokesTotal: Int
    public let smokesBaseline: Int
    public let smokesLogs: [HabitLogRecord]
    public let deletedIds: [String]
    public let updatedAt: Date

    public init(
        dateKey: String,
        waterTotalMl: Double,
        waterGoalMl: Double,
        waterLogs: [HabitLogRecord],
        smokesTotal: Int,
        smokesBaseline: Int,
        smokesLogs: [HabitLogRecord],
        deletedIds: [String],
        updatedAt: Date = Date()
    ) {
        self.dateKey = dateKey
        self.waterTotalMl = waterTotalMl
        self.waterGoalMl = waterGoalMl
        self.waterLogs = waterLogs
        self.smokesTotal = smokesTotal
        self.smokesBaseline = smokesBaseline
        self.smokesLogs = smokesLogs
        self.deletedIds = deletedIds
        self.updatedAt = updatedAt
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
    public let cosmos: CosmosWidgetSnapshot
    public let morningSummary: BriefingSummarySnippet?
    public let isMorningSlot: Bool
    
    public init(
        bubbles: BubblesWidgetSnapshot,
        smokes: SmokesWidgetSnapshot,
        money: MoneyWidgetSnapshot,
        sleep: SleepWidgetSnapshot,
        tagdos: TagdosWidgetSnapshot,
        stress: StressWidgetSnapshot = .placeholder,
        cosmos: CosmosWidgetSnapshot = .placeholder,
        morningSummary: BriefingSummarySnippet? = nil,
        isMorningSlot: Bool = false
    ) {
        self.bubbles = bubbles
        self.smokes = smokes
        self.money = money
        self.sleep = sleep
        self.tagdos = tagdos
        self.stress = stress
        self.cosmos = cosmos
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

    public static func from(
        session: SleepSession?,
        restingHeartRate: Double? = nil,
        hrvMs: Double? = nil,
        lastUpdated: Date = Date()
    ) -> SleepWidgetSnapshot {
        guard let session, session.asleepSeconds > 0 else {
            return SleepWidgetSnapshot.empty
        }
        let color = DeviceColorPalette.getColor(for: session.sourceDevice)
        return SleepWidgetSnapshot(
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
            lastUpdated: lastUpdated
        )
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
    
    public static var placeholder: CosmosWidgetSnapshot {
        CosmosWidgetSnapshot(
            stargazingScore: 84,
            stargazingVerdict: "Excellent Sky",
            qualityHexColor: "#00E676",
            moonPhaseName: "Waxing Crescent",
            moonIlluminationPercent: 22,
            moonSymbol: "moonphase.waxing.crescent",
            visiblePlanetsCount: 4,
            topPlanetsSummary: "Jupiter · Saturn · Venus · Mars",
            bestWindowLabel: "21:30 – 01:00",
            nextIssPassSummary: "ISS Pass · 21:42 (68°)",
            kpIndex: 2.3,
            bortleClass: 5,
            provenanceBadge: "Live Weather + Ephemeris"
        )
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

private struct SleepWidgetBridgeEnvelope: Codable, Sendable {
    let dateKey: String
    let snapshot: SleepWidgetSnapshot
}

private struct StressWidgetBridgeEnvelope: Codable, Sendable {
    let dateKey: String
    let snapshot: StressWidgetSnapshot
}

private struct WeatherCoordsBridgeEnvelope: Codable, Sendable {
    let latitude: Double
    let longitude: Double
}

/// Central data coordinator managing 0ms read/write between the Main App and WidgetKit Extension.
public final class WidgetDataCoordinator: @unchecked Sendable {
    public enum WidgetKind {
        public static let combined = "com.intellidream.daily.widget.combined"
        public static let bubbles = "com.intellidream.daily.BubblesWidget"
        public static let smokes = "com.intellidream.daily.SmokesWidget"
        public static let money = "com.intellidream.daily.MoneyWidget"
        public static let sleep = "com.intellidream.daily.SleepWidget"
        public static let stress = "com.intellidream.daily.widget.stress"
        public static let tagdos = "com.intellidream.daily.TagdosWidget"
        public static let cosmos = "DailyCosmosWidget"
        public static let weather = "com.intellidream.daily.WeatherWidget"
    }

    public static let shared = WidgetDataCoordinator()
    public static let darwinMutationNotificationName = "com.intellidream.daily.widgetDidMutateData"
    private static let habitsBridgeFilename = "daily_habits_widget_bridge_v1.json"
    private static let sleepBridgeFilename = "daily_sleep_widget_bridge_v1.json"
    private static let stressBridgeFilename = "daily_stress_widget_bridge_v1.json"
    private static let briefingBridgeFilename = "daily_briefing_widget_bridge_v1.json"
    private static let weatherBridgeFilename = "daily_weather_widget_bridge_v1.json"
    private static let weatherCoordsBridgeFilename = "daily_weather_coords_v1.json"
    private static let tagdosBridgeFilename = "daily_tagdos_widget_bridge_v1.json"
    private static let cosmosBridgeFilename = "daily_cosmos_widget_bridge_v1.json"
    private static let moneyBridgeFilename = "daily_money_widget_bridge_v1.txt"

    private let lastRolloverDateKeyStorageKey = "daily_widget_last_rollover_date_v1"
    private let lastRolloverSlotStorageKey = "daily_widget_last_rollover_slot_v1"
    private let userFirstNameStorageKey = "daily_user_first_name_v1"

    private let groupSuiteName = GroupDefaults.suiteName
    private let bridgeLock = NSLock()
    private var lastSemanticDataByKey: [String: Data] = [:]
    private var groupDefaults: UserDefaults {
        UserDefaults(suiteName: groupSuiteName) ?? UserDefaults.standard
    }

    private func appGroupDirectoryURL(directory: URL? = nil) -> URL? {
        directory ?? FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupSuiteName)
    }

    private func bridgeFileURL(filename: String, directory: URL? = nil) -> URL? {
        appGroupDirectoryURL(directory: directory)?.appendingPathComponent(filename)
    }

    public var habitsBridgeFileURL: URL? {
        bridgeFileURL(filename: Self.habitsBridgeFilename)
    }

    public func synchronizeDefaults() {
        groupDefaults.synchronize()
    }

    public func setCachedUserFirstName(_ firstName: String?, defaults: UserDefaults? = nil) {
        let trimmed = firstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return }
        let store = defaults ?? groupDefaults
        store.set(trimmed, forKey: userFirstNameStorageKey)
        store.synchronize()
    }

    public func cachedUserFirstName(defaults: UserDefaults? = nil) -> String {
        let store = defaults ?? groupDefaults
        let stored = store.string(forKey: userFirstNameStorageKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (stored?.isEmpty == false) ? stored! : "Mihai"
    }

    /// Computes a boundary-aware timeline refresh date so WidgetKit transitions promptly at midnight
    /// and diurnal brief cutoffs (e.g. 05:00 / 12:00) instead of drifting past those boundaries.
    public static func nextBoundaryAlignedDate(
        after date: Date = Date(),
        defaultIntervalMinutes: Int,
        boundaryHours: [Int],
        calendar: Calendar = .current
    ) -> Date {
        let defaultNext = calendar.date(byAdding: .minute, value: defaultIntervalMinutes, to: date)
            ?? date.addingTimeInterval(TimeInterval(defaultIntervalMinutes * 60))
        let startOfToday = calendar.startOfDay(for: date)
        var earliestBoundary: Date? = nil
        for dayOffset in 0...1 {
            guard let dayStart = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday) else { continue }
            for hour in boundaryHours {
                guard let candidate = calendar.date(byAdding: .hour, value: hour, to: dayStart),
                      candidate > date.addingTimeInterval(1) else { continue }
                if earliestBoundary == nil || candidate < earliestBoundary! {
                    earliestBoundary = candidate
                }
            }
        }
        if let earliestBoundary, earliestBoundary < defaultNext {
            return earliestBoundary
        }
        return defaultNext
    }

    /// Atomically detects and records whether a calendar day rollover or diurnal BriefingTimeSlot transition
    /// has occurred since widgets were last refreshed on this device, preventing races between service observers.
    @discardableResult
    public func consumePendingWidgetRolloverReload(
        for date: Date = Date(),
        defaults: UserDefaults? = nil
    ) -> (dayChanged: Bool, slotChanged: Bool) {
        let store = defaults ?? groupDefaults
        let dKey = isoDateFormatter.string(from: date)
        let slotKey = "\(dKey)_\(BriefingTimeSlot.current(for: date).rawValue)"
        let prevDay = store.string(forKey: lastRolloverDateKeyStorageKey)
        let prevSlot = store.string(forKey: lastRolloverSlotStorageKey)
        let dayChanged = (prevDay != nil && prevDay != dKey)
        let slotChanged = (prevSlot != nil && prevSlot != slotKey)
        if prevDay != dKey || prevSlot != slotKey {
            store.set(dKey, forKey: lastRolloverDateKeyStorageKey)
            store.set(slotKey, forKey: lastRolloverSlotStorageKey)
            store.synchronize()
        }
        return (dayChanged, slotChanged)
    }

    public func reloadTimelines(kinds: [String]) {
        #if canImport(WidgetKit)
        var seen = Set<String>()
        for kind in kinds where seen.insert(kind).inserted {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
        #endif
    }

    private func writeAtomicBridgeData(_ data: Data, filename: String, directory: URL? = nil) {
        guard let url = bridgeFileURL(filename: filename, directory: directory) else { return }
        bridgeLock.lock()
        defer { bridgeLock.unlock() }
        writeDataLocked(data, to: url)
    }

    private func readAtomicBridgeData(filename: String, directory: URL? = nil) -> Data? {
        guard let url = bridgeFileURL(filename: filename, directory: directory) else { return nil }
        bridgeLock.lock()
        defer { bridgeLock.unlock() }
        return try? Data(contentsOf: url)
    }

    private func removeAtomicBridgeFile(filename: String, directory: URL? = nil) {
        guard let url = bridgeFileURL(filename: filename, directory: directory) else { return }
        bridgeLock.lock()
        defer { bridgeLock.unlock() }
        try? FileManager.default.removeItem(at: url)
        lastSemanticDataByKey.removeValue(forKey: url.path)
    }

    private func writeDataLocked(_ data: Data, to url: URL) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic])
    }

    private func canonicalSemanticData<T: Encodable>(for value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value),
              let obj = (try? JSONSerialization.jsonObject(with: data)) else {
            return nil
        }
        func stripTimestamps(_ node: Any) -> Any {
            if var dict = node as? [String: Any] {
                dict.removeValue(forKey: "lastUpdated")
                dict.removeValue(forKey: "updatedAt")
                for (k, v) in dict {
                    dict[k] = stripTimestamps(v)
                }
                return dict
            } else if let arr = node as? [Any] {
                return arr.map { stripTimestamps($0) }
            }
            return node
        }
        return try? JSONSerialization.data(withJSONObject: stripTimestamps(obj), options: [.sortedKeys])
    }

    private func persistBridgeValue<T: Encodable>(
        _ value: T,
        defaultsKey: String,
        bridgeFilename: String,
        reloadingKinds kinds: [String],
        directory: URL? = nil,
        defaults: UserDefaults? = nil
    ) {
        persistBridgeValue(
            value,
            envelopeDefaultsKey: nil,
            legacyDefaultsValue: value,
            defaultsKey: defaultsKey,
            bridgeFilename: bridgeFilename,
            reloadingKinds: kinds,
            directory: directory,
            defaults: defaults
        )
    }

    /// Writes an atomic App Group container file plus synchronized UserDefaults payloads,
    /// deduplicating semantically identical updates to preserve WidgetKit reload budget while
    /// keeping legacy flat snapshot keys compatible across macOS/iOS widget extension restarts.
    private func persistBridgeValue<T: Encodable, L: Encodable>(
        _ value: T,
        envelopeDefaultsKey: String?,
        legacyDefaultsValue: L,
        defaultsKey: String,
        bridgeFilename: String,
        reloadingKinds kinds: [String],
        directory: URL? = nil,
        defaults: UserDefaults? = nil
    ) {
        let store = defaults ?? groupDefaults
        guard let encoded = try? JSONEncoder().encode(value),
              let legacyEncoded = try? JSONEncoder().encode(legacyDefaultsValue) else { return }
        let url = bridgeFileURL(filename: bridgeFilename, directory: directory)
        let cacheKey = url?.path ?? envelopeDefaultsKey ?? defaultsKey
        let semanticData = canonicalSemanticData(for: value) ?? encoded

        bridgeLock.lock()
        let fileExists = url.map { FileManager.default.fileExists(atPath: $0.path) } ?? true
        if lastSemanticDataByKey[cacheKey] == semanticData && fileExists {
            bridgeLock.unlock()
            return
        }
        lastSemanticDataByKey[cacheKey] = semanticData
        if let url {
            writeDataLocked(encoded, to: url)
        }
        bridgeLock.unlock()

        if let envelopeDefaultsKey {
            store.set(encoded, forKey: envelopeDefaultsKey)
        }
        store.set(legacyEncoded, forKey: defaultsKey)
        store.synchronize()
        if defaults == nil {
            if let envelopeDefaultsKey {
                UserDefaults.standard.set(encoded, forKey: envelopeDefaultsKey)
            }
            UserDefaults.standard.set(legacyEncoded, forKey: defaultsKey)
        }
        reloadTimelines(kinds: kinds)
    }

    private let iso8601SummaryDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let ts = try? container.decode(Double.self) {
                return Date(timeIntervalSinceReferenceDate: ts)
            }
            let str = try container.decode(String.self)
            let f1 = ISO8601DateFormatter()
            f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f1.date(from: str) { return date }
            let f2 = ISO8601DateFormatter()
            f2.formatOptions = [.withInternetDateTime]
            if let date = f2.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(str)")
        }
        return d
    }()

    public func writeHabitsBridgeState(_ state: HabitsWidgetBridgeState, bridgeFileURL: URL? = nil) {
        guard let url = bridgeFileURL ?? habitsBridgeFileURL else { return }
        bridgeLock.lock()
        defer { bridgeLock.unlock() }
        writeHabitsBridgeStateLocked(state, to: url)
    }

    public func readHabitsBridgeState(for dateKey: String, bridgeFileURL: URL? = nil) -> HabitsWidgetBridgeState? {
        guard let url = bridgeFileURL ?? habitsBridgeFileURL else { return nil }
        bridgeLock.lock()
        defer { bridgeLock.unlock() }
        return readHabitsBridgeStateLocked(for: dateKey, from: url)
    }

    private func writeHabitsBridgeStateLocked(_ state: HabitsWidgetBridgeState, to url: URL) {
        if let data = try? JSONEncoder().encode(state) {
            writeDataLocked(data, to: url)
        }
    }

    private func readHabitsBridgeStateLocked(for dateKey: String, from url: URL) -> HabitsWidgetBridgeState? {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(HabitsWidgetBridgeState.self, from: data),
              state.dateKey == dateKey else {
            return nil
        }
        return state
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
    
    // MARK: - Shared Habit Cache Helpers

    private func mergedDeletedIds(store: UserDefaults, bridge: HabitsWidgetBridgeState?) -> Set<String> {
        var ids = Set(store.stringArray(forKey: "deleted_habit_log_ids") ?? [])
        if let bridgeDeleted = bridge?.deletedIds {
            ids.formUnion(bridgeDeleted)
        }
        return ids
    }

    private func cachedWaterGoal(store: UserDefaults, bridge: HabitsWidgetBridgeState?) -> Double {
        if let bg = bridge?.waterGoalMl, bg > 0 { return bg }
        let goalStr = store.string(forKey: "water_goal") ?? "2000"
        return Double(goalStr) ?? (store.value(forKey: "water_goal") as? Double ?? 2000)
    }

    private func cachedSmokesBaseline(store: UserDefaults, bridge: HabitsWidgetBridgeState?) -> Int {
        if let bb = bridge?.smokesBaseline, bb > 0 { return bb }
        let baselineStr = store.string(forKey: "smokes_baseline") ?? "20"
        return Int(baselineStr) ?? (store.value(forKey: "smokes_baseline") as? Int ?? 20)
    }

    private func cachedWaterTotal(store: UserDefaults, key: String) -> Double {
        if let wData = store.data(forKey: "habits_water_daily_totals"),
           let dict = try? JSONDecoder().decode([String: Double].self, from: wData),
           let val = dict[key] {
            return val
        }
        if store.string(forKey: "cached_habits_date") == key || store.string(forKey: "cached_habits_date") == nil {
            return Double(store.integer(forKey: "cached_water_total"))
        }
        return 0
    }

    private func cachedSmokesTotal(store: UserDefaults, key: String) -> Int {
        if let sData = store.data(forKey: "habits_smokes_daily_totals"),
           let dict = try? JSONDecoder().decode([String: Int].self, from: sData),
           let val = dict[key] {
            return val
        }
        if store.string(forKey: "cached_habits_date") == key || store.string(forKey: "cached_habits_date") == nil {
            return store.integer(forKey: "cached_smokes_total")
        }
        return 0
    }

    private func appendOfflineHabitQueue(_ record: HabitLogRecord, store: UserDefaults) {
        var queue: [HabitLogRecord] = []
        if let qData = store.data(forKey: "offline_habits_queue"),
           let decoded = try? JSONDecoder().decode([HabitLogRecord].self, from: qData) {
            queue = decoded
        }
        queue.append(record)
        if let encoded = try? JSONEncoder().encode(queue) {
            store.set(encoded, forKey: "offline_habits_queue")
        }
    }

    // MARK: - Bubbles (Hydration)

    public func fetchBubblesSnapshot() -> BubblesWidgetSnapshot {
        fetchBubblesSnapshot(bridgeFileURL: nil, defaults: nil)
    }

    public func fetchBubblesSnapshot(bridgeFileURL: URL?, defaults: UserDefaults?) -> BubblesWidgetSnapshot {
        let store = defaults ?? groupDefaults
        store.synchronize()
        let key = todayKey
        let targetBridgeURL = bridgeFileURL ?? habitsBridgeFileURL
        let bridge = readHabitsBridgeState(for: key, bridgeFileURL: targetBridgeURL)
        let deletedIds = mergedDeletedIds(store: store, bridge: bridge)
        let goal = cachedWaterGoal(store: store, bridge: bridge)

        let totalMl: Double
        let activeLogs: [HabitLogRecord]?
        if let bridge {
            totalMl = bridge.waterTotalMl
            activeLogs = bridge.waterLogs.filter { !deletedIds.contains($0.id.uuidString) }
        } else {
            totalMl = cachedWaterTotal(store: store, key: key)
            if let logsData = store.data(forKey: "local_water_logs_\(key)"),
               let logs = try? JSONDecoder().decode([HabitLogRecord].self, from: logsData) {
                activeLogs = logs.filter { !deletedIds.contains($0.id.uuidString) }
            } else {
                activeLogs = nil
            }
        }

        return buildBubblesSnapshot(totalMl: totalMl, goal: goal, activeLogs: activeLogs)
    }

    private func buildBubblesSnapshot(
        totalMl: Double,
        goal: Double,
        activeLogs: [HabitLogRecord]?
    ) -> BubblesWidgetSnapshot {
        var waterMl = 0.0
        var coffeeMl = 0.0
        var teaMl = 0.0
        var otherDrinks: [String: Double] = [:]
        var lastLogged: Date? = nil

        if let activeLogs {
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
        let store = groupDefaults

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

        bridgeLock.lock()
        store.synchronize()
        let existingBridge = habitsBridgeFileURL.flatMap { readHabitsBridgeStateLocked(for: key, from: $0) }
        let deletedSet = mergedDeletedIds(store: store, bridge: existingBridge)

        // 1. Update daily totals
        var totals: [String: Double] = [:]
        if let wData = store.data(forKey: "habits_water_daily_totals"),
           let decoded = try? JSONDecoder().decode([String: Double].self, from: wData) {
            totals = decoded
        }
        let baseTotal = existingBridge?.waterTotalMl ?? cachedWaterTotal(store: store, key: key)
        let newWaterTotal = baseTotal + amountMl
        totals[key] = newWaterTotal
        if let encoded = try? JSONEncoder().encode(totals) {
            store.set(encoded, forKey: "habits_water_daily_totals")
        }
        store.set(Int(newWaterTotal), forKey: "cached_water_total")
        store.set(key, forKey: "cached_habits_date")

        // 2. Append to local logs
        var logs: [HabitLogRecord] = existingBridge?.waterLogs ?? {
            if let logsData = store.data(forKey: "local_water_logs_\(key)"),
               let decoded = try? JSONDecoder().decode([HabitLogRecord].self, from: logsData) {
                return decoded
            }
            return []
        }()
        logs.removeAll { deletedSet.contains($0.id.uuidString) }
        logs.insert(newRecord, at: 0)
        if let encoded = try? JSONEncoder().encode(logs) {
            store.set(encoded, forKey: "local_water_logs_\(key)")
        }

        // 3. Queue for Supabase background sync & synchronize defaults
        appendOfflineHabitQueue(newRecord, store: store)
        store.synchronize()

        // 4. Write atomic App Group bridge preserving sibling Smokes state
        if let url = habitsBridgeFileURL {
            let smokesLogs: [HabitLogRecord] = existingBridge?.smokesLogs ?? {
                if let sData = store.data(forKey: "local_smokes_logs_\(key)"),
                   let decoded = try? JSONDecoder().decode([HabitLogRecord].self, from: sData) {
                    return decoded.filter { !deletedSet.contains($0.id.uuidString) }
                }
                return []
            }()
            let bridgeState = HabitsWidgetBridgeState(
                dateKey: key,
                waterTotalMl: newWaterTotal,
                waterGoalMl: cachedWaterGoal(store: store, bridge: existingBridge),
                waterLogs: logs,
                smokesTotal: existingBridge?.smokesTotal ?? cachedSmokesTotal(store: store, key: key),
                smokesBaseline: cachedSmokesBaseline(store: store, bridge: existingBridge),
                smokesLogs: smokesLogs,
                deletedIds: Array(deletedSet),
                updatedAt: now
            )
            writeHabitsBridgeStateLocked(bridgeState, to: url)
        }
        bridgeLock.unlock()

        // 5. Reload Widget Timelines & notify running app process
        reloadTimelines(kinds: [WidgetKind.bubbles, WidgetKind.combined])
        postCrossProcessMutationNotification()
    }

    // MARK: - Smokes (Tobacco & Cessation)

    public func fetchSmokesSnapshot() -> SmokesWidgetSnapshot {
        fetchSmokesSnapshot(bridgeFileURL: nil, defaults: nil)
    }

    public func fetchSmokesSnapshot(bridgeFileURL: URL?, defaults: UserDefaults?) -> SmokesWidgetSnapshot {
        let store = defaults ?? groupDefaults
        store.synchronize()
        let key = todayKey
        let targetBridgeURL = bridgeFileURL ?? habitsBridgeFileURL
        let bridge = readHabitsBridgeState(for: key, bridgeFileURL: targetBridgeURL)
        let deletedIds = mergedDeletedIds(store: store, bridge: bridge)
        let baseline = cachedSmokesBaseline(store: store, bridge: bridge)

        let totalSmokes: Int
        let activeLogs: [HabitLogRecord]?
        if let bridge {
            totalSmokes = bridge.smokesTotal
            activeLogs = bridge.smokesLogs.filter { !deletedIds.contains($0.id.uuidString) }
        } else {
            totalSmokes = cachedSmokesTotal(store: store, key: key)
            if let logsData = store.data(forKey: "local_smokes_logs_\(key)"),
               let logs = try? JSONDecoder().decode([HabitLogRecord].self, from: logsData) {
                activeLogs = logs.filter { !deletedIds.contains($0.id.uuidString) }
            } else {
                activeLogs = nil
            }
        }

        return buildSmokesSnapshot(totalSmokes: totalSmokes, baseline: baseline, activeLogs: activeLogs)
    }

    private func buildSmokesSnapshot(
        totalSmokes: Int,
        baseline: Int,
        activeLogs: [HabitLogRecord]?
    ) -> SmokesWidgetSnapshot {
        var cigsCount = 0
        var heatedCount = 0
        var rolledCount = 0
        var cigarilloCount = 0
        var lastSmokeDate: Date? = nil

        if let activeLogs {
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
        let store = groupDefaults

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

        bridgeLock.lock()
        store.synchronize()
        let existingBridge = habitsBridgeFileURL.flatMap { readHabitsBridgeStateLocked(for: key, from: $0) }
        let deletedSet = mergedDeletedIds(store: store, bridge: existingBridge)

        // 1. Update daily totals
        var totals: [String: Int] = [:]
        if let sData = store.data(forKey: "habits_smokes_daily_totals"),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: sData) {
            totals = decoded
        }
        let baseTotal = existingBridge?.smokesTotal ?? cachedSmokesTotal(store: store, key: key)
        let newSmokesTotal = baseTotal + 1
        totals[key] = newSmokesTotal
        if let encoded = try? JSONEncoder().encode(totals) {
            store.set(encoded, forKey: "habits_smokes_daily_totals")
        }
        store.set(newSmokesTotal, forKey: "cached_smokes_total")
        store.set(key, forKey: "cached_habits_date")

        // 2. Append to local logs
        var logs: [HabitLogRecord] = existingBridge?.smokesLogs ?? {
            if let logsData = store.data(forKey: "local_smokes_logs_\(key)"),
               let decoded = try? JSONDecoder().decode([HabitLogRecord].self, from: logsData) {
                return decoded
            }
            return []
        }()
        logs.removeAll { deletedSet.contains($0.id.uuidString) }
        logs.insert(newRecord, at: 0)
        if let encoded = try? JSONEncoder().encode(logs) {
            store.set(encoded, forKey: "local_smokes_logs_\(key)")
        }

        // 3. Queue for Supabase background sync & synchronize defaults
        appendOfflineHabitQueue(newRecord, store: store)
        store.synchronize()

        // 4. Write atomic App Group bridge preserving sibling Water state
        if let url = habitsBridgeFileURL {
            let waterLogs: [HabitLogRecord] = existingBridge?.waterLogs ?? {
                if let wData = store.data(forKey: "local_water_logs_\(key)"),
                   let decoded = try? JSONDecoder().decode([HabitLogRecord].self, from: wData) {
                    return decoded.filter { !deletedSet.contains($0.id.uuidString) }
                }
                return []
            }()
            let bridgeState = HabitsWidgetBridgeState(
                dateKey: key,
                waterTotalMl: existingBridge?.waterTotalMl ?? cachedWaterTotal(store: store, key: key),
                waterGoalMl: cachedWaterGoal(store: store, bridge: existingBridge),
                waterLogs: waterLogs,
                smokesTotal: newSmokesTotal,
                smokesBaseline: cachedSmokesBaseline(store: store, bridge: existingBridge),
                smokesLogs: logs,
                deletedIds: Array(deletedSet),
                updatedAt: now
            )
            writeHabitsBridgeStateLocked(bridgeState, to: url)
        }
        bridgeLock.unlock()

        // 5. Reload Widget Timelines & notify running app process
        reloadTimelines(kinds: [WidgetKind.smokes, WidgetKind.combined])
        postCrossProcessMutationNotification()
    }
    
    // MARK: - Money (SmartLedger)
    
    private let ledgerStorageKey = "daily_smart_ledger_raw_text_v1"
    private let ledgerLocalModifiedKey = "daily_smart_ledger_local_modified_at_v1"

    public func updateMoneyLedgerBridge(_ rawText: String, reloadWidgets: Bool = true) {
        updateMoneyLedgerBridge(rawText, reloadWidgets: reloadWidgets, bridgeDirectoryURL: nil, defaults: nil)
    }

    public func updateMoneyLedgerBridge(
        _ rawText: String,
        reloadWidgets: Bool,
        bridgeDirectoryURL: URL?,
        defaults: UserDefaults?
    ) {
        let store = defaults ?? groupDefaults
        if let data = rawText.data(using: .utf8) {
            writeAtomicBridgeData(data, filename: Self.moneyBridgeFilename, directory: bridgeDirectoryURL)
        }
        store.set(rawText, forKey: ledgerStorageKey)
        store.set(Date().timeIntervalSince1970, forKey: ledgerLocalModifiedKey)
        store.synchronize()
        if defaults == nil {
            UserDefaults.standard.set(rawText, forKey: ledgerStorageKey)
        }
        if reloadWidgets {
            reloadTimelines(kinds: [WidgetKind.money, WidgetKind.combined])
        }
    }

    public func readMoneyLedgerText(bridgeDirectoryURL: URL? = nil, defaults: UserDefaults? = nil) -> String {
        let store = defaults ?? groupDefaults
        store.synchronize()
        if let data = readAtomicBridgeData(filename: Self.moneyBridgeFilename, directory: bridgeDirectoryURL),
           let bridgeText = String(data: data, encoding: .utf8),
           !bridgeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return bridgeText
        }
        return store.string(forKey: ledgerStorageKey) ?? SmartLedgerStore.defaultLedgerText
    }

    public func fetchMoneySnapshot() -> MoneyWidgetSnapshot {
        fetchMoneySnapshot(bridgeDirectoryURL: nil, defaults: nil)
    }

    public func fetchMoneySnapshot(bridgeDirectoryURL: URL?, defaults: UserDefaults?) -> MoneyWidgetSnapshot {
        let rawText = readMoneyLedgerText(bridgeDirectoryURL: bridgeDirectoryURL, defaults: defaults)
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

    private func applyLedgerAdjustment(accountName: String, deltaAmount: Double, isRealAmount: Bool) {
        let rawText = readMoneyLedgerText()
        let ledger = SmartLedgerParser.shared.parse(rawText)
        
        guard let incoming = ledger.sections.first(where: { $0.name.caseInsensitiveCompare("Incoming") == .orderedSame }),
              let item = incoming.items.first(where: { $0.key.caseInsensitiveCompare(accountName) == .orderedSame }) else {
            return
        }
        
        // In scaled sections (e.g. Incoming where 1 unit = 100 Lei), deltaRaw = deltaReal / 100.0
        let deltaRaw = (isRealAmount && item.isScaled) ? (deltaAmount / 100.0) : deltaAmount
        let updatedText = SmartLedgerParser.shared.adjustItemAmount(in: rawText, lineIndex: item.lineIndex, deltaRaw: deltaRaw)
        updateMoneyLedgerBridge(updatedText, reloadWidgets: true)
        postCrossProcessMutationNotification()
    }

    /// Adjusts an account amount by a real currency amount (e.g. -100 Lei or +100 Lei).
    /// Automatically converts to DSL units if the underlying section is scaled (1 unit = 100 Lei).
    public func adjustLedgerAmount(accountName: String, deltaReal: Double) {
        applyLedgerAdjustment(accountName: accountName, deltaAmount: deltaReal, isRealAmount: true)
    }
    
    public func adjustLedgerAmount(accountName: String, deltaRaw: Double) {
        applyLedgerAdjustment(accountName: accountName, deltaAmount: deltaRaw, isRealAmount: false)
    }
    
    // MARK: - Sleep (Sleep Studio)
    
    private let sleepSnapshotKey = "daily_sleep_widget_snapshot_v1"
    private let sleepEnvelopeKey = "daily_sleep_widget_envelope_v1"
    
    public func updateSleepSnapshot(from session: SleepSession?, restingHeartRate: Double? = nil, hrvMs: Double? = nil) {
        updateSleepSnapshot(
            from: session,
            restingHeartRate: restingHeartRate,
            hrvMs: hrvMs,
            bridgeDirectoryURL: nil,
            defaults: nil,
            now: Date()
        )
    }

    public func updateSleepSnapshot(
        from session: SleepSession?,
        restingHeartRate: Double?,
        hrvMs: Double?,
        bridgeDirectoryURL: URL?,
        defaults: UserDefaults?,
        now: Date
    ) {
        let snapshot = SleepWidgetSnapshot.from(
            session: session,
            restingHeartRate: restingHeartRate,
            hrvMs: hrvMs,
            lastUpdated: now
        )
        let envelope = SleepWidgetBridgeEnvelope(
            dateKey: isoDateFormatter.string(from: now),
            snapshot: snapshot
        )
        persistBridgeValue(
            envelope,
            envelopeDefaultsKey: sleepEnvelopeKey,
            legacyDefaultsValue: snapshot,
            defaultsKey: sleepSnapshotKey,
            bridgeFilename: Self.sleepBridgeFilename,
            reloadingKinds: [WidgetKind.sleep, WidgetKind.combined],
            directory: bridgeDirectoryURL,
            defaults: defaults
        )
    }
    
    public func fetchSleepSnapshot() -> SleepWidgetSnapshot {
        fetchSleepSnapshot(bridgeDirectoryURL: nil, defaults: nil, now: Date())
    }

    public func fetchSleepSnapshot(bridgeDirectoryURL: URL?, defaults: UserDefaults?, now: Date) -> SleepWidgetSnapshot {
        let store = defaults ?? groupDefaults
        store.synchronize()
        let key = isoDateFormatter.string(from: now)
        let decoder = JSONDecoder()

        func decodeEnvelopeOrLegacy(from data: Data?) -> SleepWidgetSnapshot? {
            guard let data else { return nil }
            if let envelope = try? decoder.decode(SleepWidgetBridgeEnvelope.self, from: data) {
                return envelope.dateKey == key ? envelope.snapshot : nil
            }
            if let legacy = try? decoder.decode(SleepWidgetSnapshot.self, from: data),
               Calendar.current.isDate(legacy.lastUpdated, inSameDayAs: now),
               legacy.hasData {
                return legacy
            }
            return nil
        }

        // 1. Atomic App Group container bridge (bypasses cross-process cfprefsd lag)
        if let bridgeSnap = decodeEnvelopeOrLegacy(
            from: readAtomicBridgeData(filename: Self.sleepBridgeFilename, directory: bridgeDirectoryURL)
        ) {
            return bridgeSnap
        }

        // 2. Date-scoped Envelope in synchronized App Group UserDefaults
        if let envelopeSnap = decodeEnvelopeOrLegacy(from: store.data(forKey: sleepEnvelopeKey)) {
            return envelopeSnap
        }

        // 3. Flat legacy snapshot key in synchronized App Group UserDefaults
        if let defaultsSnap = decodeEnvelopeOrLegacy(from: store.data(forKey: sleepSnapshotKey)) {
            return defaultsSnap
        }
        
        // 3. Resilient fallback: inspect Today's canonical health summary ONLY (ISO-8601 decoded)
        if let summaryData = store.data(forKey: "health_daily_summary_\(key)"),
           let summary = try? iso8601SummaryDecoder.decode(DailyHealthSummaryPayload.self, from: summaryData),
           let session = summary.sleep.primarySession, session.asleepSeconds > 0 {
            return SleepWidgetSnapshot.from(
                session: session,
                restingHeartRate: summary.vitals["resting_heart_rate"]?.value,
                hrvMs: summary.vitals["hrv_sdnn"]?.value ?? summary.stress?.currentHrvMs,
                lastUpdated: now
            )
        }
        return SleepWidgetSnapshot.empty
    }
    
    // MARK: - Tagdos & Notes
    
    private let tagdosSnapshotKey = "daily_tagdos_widget_snapshot_v1"
    
    public func updateTagdosSnapshot(_ snapshot: TagdosWidgetSnapshot) {
        updateTagdosSnapshot(snapshot, bridgeDirectoryURL: nil, defaults: nil)
    }

    public func updateTagdosSnapshot(_ snapshot: TagdosWidgetSnapshot, bridgeDirectoryURL: URL?, defaults: UserDefaults?) {
        persistBridgeValue(
            snapshot,
            defaultsKey: tagdosSnapshotKey,
            bridgeFilename: Self.tagdosBridgeFilename,
            reloadingKinds: [WidgetKind.tagdos, WidgetKind.combined],
            directory: bridgeDirectoryURL,
            defaults: defaults
        )
    }
    
    public func fetchTagdosSnapshot() -> TagdosWidgetSnapshot {
        fetchTagdosSnapshot(bridgeDirectoryURL: nil, defaults: nil)
    }

    public func fetchTagdosSnapshot(bridgeDirectoryURL: URL?, defaults: UserDefaults?) -> TagdosWidgetSnapshot {
        let store = defaults ?? groupDefaults
        store.synchronize()
        if let data = readAtomicBridgeData(filename: Self.tagdosBridgeFilename, directory: bridgeDirectoryURL),
           let snapshot = try? JSONDecoder().decode(TagdosWidgetSnapshot.self, from: data) {
            return snapshot
        }

        if let data = store.data(forKey: tagdosSnapshotKey),
           let snapshot = try? JSONDecoder().decode(TagdosWidgetSnapshot.self, from: data),
           !snapshot.streams.isEmpty {
            return snapshot
        }
        
        // Resilient fallback: decode raw streams if snapshot has not yet been triggered
        if let streamsData = store.data(forKey: "daily_tagdos_raw_streams_v1") ?? store.data(forKey: "daily_tagdos_streams_v1"),
           let streams = try? JSONDecoder().decode([TagDoStream].self, from: streamsData),
           !streams.isEmpty {
            return TagdosStore.buildWidgetSnapshot(from: streams)
        }
        
        return TagdosWidgetSnapshot.empty
    }

    /// Executes an interactive pill action ("done" or "recycle") directly from WidgetKit AppIntents.
    public func performTagdosPillAction(streamId: String, pillId: String, action: String) {
        guard let targetStreamUUID = UUID(uuidString: streamId),
              let targetPillUUID = UUID(uuidString: pillId) else { return }

        let store = groupDefaults
        bridgeLock.lock()
        store.synchronize()

        guard let rawData = store.data(forKey: "daily_tagdos_raw_streams_v1")
                ?? UserDefaults.standard.data(forKey: "daily_tagdos_raw_streams_v1"),
              var streams = try? JSONDecoder().decode([TagDoStream].self, from: rawData),
              let sIdx = streams.firstIndex(where: { $0.id == targetStreamUUID }) else {
            bridgeLock.unlock()
            return
        }

        let parser = TagdosParser.shared
        let existing = streams[sIdx]
        var updated: TagDoStream
        if action == "recycle" {
            updated = parser.recyclePillToBack(in: existing, pillId: targetPillUUID)
        } else {
            updated = parser.togglePillCompletion(in: existing, pillId: targetPillUUID)
        }
        updated.activeMemos = existing.activeMemos
        updated.attachments = existing.attachments
        updated.updatedAt = Date()
        streams[sIdx] = updated

        if let encoded = try? JSONEncoder().encode(streams) {
            store.set(encoded, forKey: "daily_tagdos_raw_streams_v1")
        }

        var dirtySet = Set(store.stringArray(forKey: "daily_tagdos_dirty_stream_ids_v1") ?? [])
        dirtySet.insert(targetStreamUUID.uuidString)
        store.set(Array(dirtySet), forKey: "daily_tagdos_dirty_stream_ids_v1")
        store.synchronize()
        bridgeLock.unlock()

        let snapshot = TagdosStore.buildWidgetSnapshot(from: streams)
        updateTagdosSnapshot(snapshot, bridgeDirectoryURL: nil, defaults: store)
        postCrossProcessMutationNotification()
    }

    // MARK: - Stress Level & Monkey Mascot
    
    private let stressSnapshotKey = "daily_stress_widget_snapshot_v1"
    private let stressEnvelopeKey = "daily_stress_widget_envelope_v1"

    private func persistStressSnapshot(
        _ snapshot: StressWidgetSnapshot,
        bridgeDirectoryURL: URL?,
        defaults: UserDefaults?,
        now: Date
    ) {
        let envelope = StressWidgetBridgeEnvelope(
            dateKey: isoDateFormatter.string(from: now),
            snapshot: snapshot
        )
        persistBridgeValue(
            envelope,
            envelopeDefaultsKey: stressEnvelopeKey,
            legacyDefaultsValue: snapshot,
            defaultsKey: stressSnapshotKey,
            bridgeFilename: Self.stressBridgeFilename,
            reloadingKinds: [WidgetKind.stress, WidgetKind.combined],
            directory: bridgeDirectoryURL,
            defaults: defaults
        )
    }
    
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
        updateStressSnapshot(
            score: score,
            level: level,
            monkeyMood: monkeyMood,
            advice: advice,
            hrvMs: hrvMs,
            restingHeartRate: restingHeartRate,
            parasympathetic: parasympathetic,
            sympathetic: sympathetic,
            bridgeDirectoryURL: nil,
            defaults: nil,
            now: Date()
        )
    }

    public func updateStressSnapshot(
        score: Int,
        level: StressLevel,
        monkeyMood: MonkeyMood,
        advice: String,
        hrvMs: Double?,
        restingHeartRate: Double?,
        parasympathetic: Int,
        sympathetic: Int,
        bridgeDirectoryURL: URL?,
        defaults: UserDefaults?,
        now: Date
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
            lastUpdated: now
        )
        persistStressSnapshot(snapshot, bridgeDirectoryURL: bridgeDirectoryURL, defaults: defaults, now: now)
    }
    
    public func clearStressSnapshot() {
        clearStressSnapshot(bridgeDirectoryURL: nil, defaults: nil, now: Date())
    }

    public func clearStressSnapshot(bridgeDirectoryURL: URL?, defaults: UserDefaults?, now: Date) {
        persistStressSnapshot(StressWidgetSnapshot.empty, bridgeDirectoryURL: bridgeDirectoryURL, defaults: defaults, now: now)
    }
    
    public func fetchStressSnapshot() -> StressWidgetSnapshot {
        fetchStressSnapshot(bridgeDirectoryURL: nil, defaults: nil, now: Date())
    }

    public func fetchStressSnapshot(bridgeDirectoryURL: URL?, defaults: UserDefaults?, now: Date) -> StressWidgetSnapshot {
        let store = defaults ?? groupDefaults
        store.synchronize()
        let key = isoDateFormatter.string(from: now)
        let decoder = JSONDecoder()

        func decodeEnvelopeOrLegacy(from data: Data?) -> StressWidgetSnapshot? {
            guard let data else { return nil }
            if let envelope = try? decoder.decode(StressWidgetBridgeEnvelope.self, from: data) {
                return envelope.dateKey == key ? envelope.snapshot : nil
            }
            if let legacy = try? decoder.decode(StressWidgetSnapshot.self, from: data),
               Calendar.current.isDate(legacy.lastUpdated, inSameDayAs: now),
               legacy.hasData {
                return legacy
            }
            return nil
        }

        if let bridgeSnap = decodeEnvelopeOrLegacy(
            from: readAtomicBridgeData(filename: Self.stressBridgeFilename, directory: bridgeDirectoryURL)
        ) {
            return bridgeSnap
        }

        if let envelopeSnap = decodeEnvelopeOrLegacy(from: store.data(forKey: stressEnvelopeKey)) {
            return envelopeSnap
        }

        if let defaultsSnap = decodeEnvelopeOrLegacy(from: store.data(forKey: stressSnapshotKey)) {
            return defaultsSnap
        }
        
        // Resilient fallback: inspect Today's canonical health summary ONLY (ISO-8601 decoded)
        if let summaryData = store.data(forKey: "health_daily_summary_\(key)"),
           let summary = try? iso8601SummaryDecoder.decode(DailyHealthSummaryPayload.self, from: summaryData),
           let stress = summary.stress, stress.currentScore > 0 {
            let level = stress.currentLevel
            return StressWidgetSnapshot(
                hasData: true,
                stressScore: Int(stress.currentScore),
                levelRaw: level.rawValue,
                monkeyMoodRaw: stress.monkeyMood.rawValue,
                adviceSnippet: stress.adviceQuote,
                hrvMs: stress.currentHrvMs,
                restingHeartRate: summary.vitals["resting_heart_rate"]?.value,
                parasympatheticPercent: stress.parasympatheticPercent,
                sympatheticPercent: stress.sympatheticPercent,
                lastUpdated: now
            )
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

        persistBridgeValue(
            snapshot,
            defaultsKey: cosmosSnapshotKey,
            bridgeFilename: Self.cosmosBridgeFilename,
            reloadingKinds: [WidgetKind.cosmos, WidgetKind.combined]
        )
    }

    public func fetchCosmosSnapshot() -> CosmosWidgetSnapshot {
        fetchCosmosSnapshot(bridgeDirectoryURL: nil, defaults: nil, now: Date())
    }

    public func fetchCosmosSnapshot(bridgeDirectoryURL: URL?, defaults: UserDefaults?, now: Date) -> CosmosWidgetSnapshot {
        let store = defaults ?? groupDefaults
        store.synchronize()

        var lat = store.object(forKey: "weather_cached_lat") as? Double ?? 44.4268
        var lon = store.object(forKey: "weather_cached_lon") as? Double ?? 26.1025
        if let coordsData = readAtomicBridgeData(filename: Self.weatherCoordsBridgeFilename, directory: bridgeDirectoryURL),
           let coords = try? JSONDecoder().decode(WeatherCoordsBridgeEnvelope.self, from: coordsData) {
            lat = coords.latitude
            lon = coords.longitude
        }

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

        let rawData = readAtomicBridgeData(filename: Self.cosmosBridgeFilename, directory: bridgeDirectoryURL)
            ?? store.data(forKey: cosmosSnapshotKey)
        if let data = rawData,
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
        if let coordsData = try? JSONEncoder().encode(WeatherCoordsBridgeEnvelope(latitude: latitude, longitude: longitude)) {
            writeAtomicBridgeData(coordsData, filename: Self.weatherCoordsBridgeFilename)
        }
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

        persistBridgeValue(
            snapshot,
            defaultsKey: weatherSnapshotKey,
            bridgeFilename: Self.weatherBridgeFilename,
            reloadingKinds: [WidgetKind.weather, WidgetKind.combined]
        )
    }

    public func fetchWeatherSnapshot() -> WeatherWidgetSnapshot {
        fetchWeatherSnapshot(bridgeDirectoryURL: nil, defaults: nil)
    }

    public func fetchWeatherSnapshot(bridgeDirectoryURL: URL?, defaults: UserDefaults?) -> WeatherWidgetSnapshot {
        let store = defaults ?? groupDefaults
        store.synchronize()
        let rawData = readAtomicBridgeData(filename: Self.weatherBridgeFilename, directory: bridgeDirectoryURL)
            ?? store.data(forKey: weatherSnapshotKey)
        if let data = rawData,
           let snapshot = try? JSONDecoder().decode(WeatherWidgetSnapshot.self, from: data) {
            return snapshot
        }
        return WeatherWidgetSnapshot.empty
    }

    // MARK: - Smart Briefing Bridge

    private let briefingCacheKey = "daily_smart_summary_cache_v4"

    public func updateBriefingSnapshot(_ record: SmartBriefingRecord) {
        updateBriefingSnapshot(record, bridgeDirectoryURL: nil, defaults: nil)
    }

    public func updateBriefingSnapshot(
        _ record: SmartBriefingRecord,
        bridgeDirectoryURL: URL?,
        defaults: UserDefaults?
    ) {
        persistBridgeValue(
            record,
            defaultsKey: briefingCacheKey,
            bridgeFilename: Self.briefingBridgeFilename,
            reloadingKinds: [WidgetKind.combined],
            directory: bridgeDirectoryURL,
            defaults: defaults
        )
    }

    public func clearBriefingSnapshot(bridgeDirectoryURL: URL? = nil, defaults: UserDefaults? = nil) {
        let store = defaults ?? groupDefaults
        removeAtomicBridgeFile(filename: Self.briefingBridgeFilename, directory: bridgeDirectoryURL)
        store.removeObject(forKey: briefingCacheKey)
        store.synchronize()
        reloadTimelines(kinds: [WidgetKind.combined])
    }

    // MARK: - Combined Executive Snapshot (5 Core Pillars + Briefing)

    public func fetchCombinedSnapshot() -> CombinedWidgetSnapshot {
        fetchCombinedSnapshot(bridgeDirectoryURL: nil, defaults: nil, now: Date())
    }

    public func fetchCombinedSnapshot(
        bridgeDirectoryURL: URL?,
        defaults: UserDefaults?,
        now: Date
    ) -> CombinedWidgetSnapshot {
        let store = defaults ?? groupDefaults
        store.synchronize()

        let habitsURL = bridgeFileURL(filename: Self.habitsBridgeFilename, directory: bridgeDirectoryURL)
        let bubbles = fetchBubblesSnapshot(bridgeFileURL: habitsURL, defaults: store)
        let smokes = fetchSmokesSnapshot(bridgeFileURL: habitsURL, defaults: store)
        let money = fetchMoneySnapshot(bridgeDirectoryURL: bridgeDirectoryURL, defaults: store)
        let sleep = fetchSleepSnapshot(bridgeDirectoryURL: bridgeDirectoryURL, defaults: store, now: now)
        let tagdos = fetchTagdosSnapshot(bridgeDirectoryURL: bridgeDirectoryURL, defaults: store)
        let stress = fetchStressSnapshot(bridgeDirectoryURL: bridgeDirectoryURL, defaults: store, now: now)
        let cosmos = fetchCosmosSnapshot(bridgeDirectoryURL: bridgeDirectoryURL, defaults: store, now: now)
        let weather = fetchWeatherSnapshot(bridgeDirectoryURL: bridgeDirectoryURL, defaults: store)

        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let currentSlot = BriefingTimeSlot.current(for: now, calendar: cal)
        let isMorning = (hour >= 5 && hour < 12)
        let firstName = cachedUserFirstName(defaults: store)

        let weatherIsFresh = weather.hasData && (
            cal.isDate(weather.lastUpdated, inSameDayAs: now) ||
            abs(now.timeIntervalSince(weather.lastUpdated)) < 4 * 3600
        )
        let primaryPill = tagdos.streams.first?.drivingPillText

        let rawBriefingData = readAtomicBridgeData(filename: Self.briefingBridgeFilename, directory: bridgeDirectoryURL)
            ?? store.data(forKey: briefingCacheKey)

        let snippet: BriefingSummarySnippet
        if let data = rawBriefingData,
           let record = try? JSONDecoder().decode(SmartBriefingRecord.self, from: data),
           cal.isDate(record.createdAt, inSameDayAs: now),
           record.slot == currentSlot {
            let m = record.metrics
            let n = record.narrative

            let focus: String? = {
                if !n.tagdosText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return n.tagdosText
                } else if !n.healthText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return n.healthText
                } else if let primaryPill, !primaryPill.isEmpty {
                    return "Focus: \(primaryPill)"
                } else {
                    return nil
                }
            }()

            // Overlay fresher live Weather and Sleep snapshots onto today's briefing snippet
            snippet = BriefingSummarySnippet(
                greeting: currentSlot.diurnalGreeting(for: firstName),
                weatherTemp: weatherIsFresh ? weather.temp : m.weatherTemp,
                weatherCondition: weatherIsFresh ? weather.conditionText : m.weatherCondition,
                weatherIcon: weatherIsFresh ? weather.iconCode : m.weatherIcon,
                sleepDurationFormatted: sleep.hasData ? sleep.totalAsleepFormatted : m.sleepDurationFormatted,
                sleepScore: sleep.hasData ? sleep.sleepScore : m.sleepScore,
                topFocusText: focus,
                isAiGenerated: record.isAiGenerated
            )
        } else {
            snippet = BriefingSummarySnippet(
                greeting: isMorning ? "Good Morning, \(firstName)" : currentSlot.diurnalGreeting(for: firstName),
                weatherTemp: weatherIsFresh ? weather.temp : nil,
                weatherCondition: weatherIsFresh ? weather.conditionText : nil,
                weatherIcon: weatherIsFresh ? weather.iconCode : nil,
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
            cosmos: cosmos,
            morningSummary: snippet,
            isMorningSlot: isMorning
        )
    }
}

