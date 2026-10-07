import Foundation

// MARK: - Health Daily Summary Database Record

/// Canonical daily summary record stored in `public.health_daily_summary`.
public struct HealthDailySummaryRecord: Codable, Identifiable, Sendable {
    public let id: String
    public let userId: String
    public let localDate: String
    public let computedAt: Date
    public let engineVersion: String
    public let rawWatermark: Date?
    public let steps: Int?
    public let activeKcal: Double?
    public let sleepAsleepS: Int?
    public let sleepScore: Int?
    public let stressAvg: Int?
    public let rhr: Double?
    public let hrvSdnn: Double?
    public let hrvRmssd: Double?
    public let weight: Double?
    public let spo2: Double?
    public let summary: DailyHealthSummaryPayload
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case localDate = "local_date"
        case computedAt = "computed_at"
        case engineVersion = "engine_version"
        case rawWatermark = "raw_watermark"
        case steps
        case activeKcal = "active_kcal"
        case sleepAsleepS = "sleep_asleep_s"
        case sleepScore = "sleep_score"
        case stressAvg = "stress_avg"
        case rhr
        case hrvSdnn = "hrv_sdnn"
        case hrvRmssd = "hrv_rmssd"
        case weight
        case spo2
        case summary
    }
    
    public init(
        id: String = UUID().uuidString,
        userId: String,
        localDate: String,
        computedAt: Date = Date(),
        engineVersion: String = "1.0",
        rawWatermark: Date? = nil,
        steps: Int? = nil,
        activeKcal: Double? = nil,
        sleepAsleepS: Int? = nil,
        sleepScore: Int? = nil,
        stressAvg: Int? = nil,
        rhr: Double? = nil,
        hrvSdnn: Double? = nil,
        hrvRmssd: Double? = nil,
        weight: Double? = nil,
        spo2: Double? = nil,
        summary: DailyHealthSummaryPayload
    ) {
        self.id = id
        self.userId = userId
        self.localDate = localDate
        self.computedAt = computedAt
        self.engineVersion = engineVersion
        self.rawWatermark = rawWatermark
        self.steps = steps
        self.activeKcal = activeKcal
        self.sleepAsleepS = sleepAsleepS
        self.sleepScore = sleepScore
        self.stressAvg = stressAvg
        self.rhr = rhr
        self.hrvSdnn = hrvSdnn
        self.hrvRmssd = hrvRmssd
        self.weight = weight
        self.spo2 = spo2
        self.summary = summary
    }
}

// MARK: - Daily Health Summary Payload (summary JSONB)

public struct DailyHealthSummaryPayload: Codable, Sendable, Equatable {
    public let date: String
    public let engineVersion: String
    public let computedAt: Date
    public let sleep: CanonicalSleepSummary
    public let activity: CanonicalActivitySummary
    public let cardiovascular: CanonicalCardiovascularSummary
    public let stress: CanonicalStressSummary?
    public let vitals: [String: CanonicalVitalSummaryItem]
    
    enum CodingKeys: String, CodingKey {
        case date
        case engineVersion = "engine_version"
        case computedAt = "computed_at"
        case sleep
        case activity
        case cardiovascular
        case stress
        case vitals
    }
    
    public init(
        date: String,
        engineVersion: String = "1.0",
        computedAt: Date = Date(),
        sleep: CanonicalSleepSummary,
        activity: CanonicalActivitySummary,
        cardiovascular: CanonicalCardiovascularSummary,
        stress: CanonicalStressSummary? = nil,
        vitals: [String: CanonicalVitalSummaryItem] = [:]
    ) {
        self.date = date
        self.engineVersion = engineVersion
        self.computedAt = computedAt
        self.sleep = sleep
        self.activity = activity
        self.cardiovascular = cardiovascular
        self.stress = stress
        self.vitals = vitals
    }
    
    public var isEmpty: Bool {
        activity.totalSteps == 0 &&
        sleep.primarySession == nil &&
        vitals.isEmpty &&
        stress == nil &&
        (cardiovascular.restingBpm == nil || cardiovascular.restingBpm == 0) &&
        cardiovascular.intradayPoints.isEmpty
    }
}

// MARK: - Canonical Sub-Payloads

public struct CanonicalSleepSummary: Codable, Sendable, Equatable {
    public let primarySession: SleepSession?
    public let allSessions: [SleepSession]
    public let naps: [NapSession]
    public let guidance: CanonicalSleepGuidance?
    
    enum CodingKeys: String, CodingKey {
        case primarySession = "primary_session"
        case allSessions = "all_sessions"
        case naps
        case guidance
    }
    
    public init(
        primarySession: SleepSession? = nil,
        allSessions: [SleepSession] = [],
        naps: [NapSession] = [],
        guidance: CanonicalSleepGuidance? = nil
    ) {
        self.primarySession = primarySession
        self.allSessions = allSessions
        self.naps = naps
        self.guidance = guidance
    }
}

public struct CanonicalSleepGuidance: Codable, Sendable, Equatable {
    public let verdict: SleepRecoveryVerdict
    public let tips: [SleepActionableTip]
    public let aiContext: SleepAIContext
    
    enum CodingKeys: String, CodingKey {
        case verdict
        case tips
        case aiContext = "ai_context"
    }
    
    public init(
        verdict: SleepRecoveryVerdict,
        tips: [SleepActionableTip] = [],
        aiContext: SleepAIContext
    ) {
        self.verdict = verdict
        self.tips = tips
        self.aiContext = aiContext
    }
}

public struct CanonicalActivitySummary: Codable, Sendable, Equatable {
    public let totalSteps: Int
    public let activeCalories: Double
    public let sourceDevice: String?
    public let hourlySteps: [HourlyStepBucket]
    
    enum CodingKeys: String, CodingKey {
        case totalSteps = "total_steps"
        case activeCalories = "active_calories"
        case sourceDevice = "source_device"
        case hourlySteps = "hourly_steps"
    }
    
    public init(
        totalSteps: Int,
        activeCalories: Double,
        sourceDevice: String? = nil,
        hourlySteps: [HourlyStepBucket] = []
    ) {
        self.totalSteps = totalSteps
        self.activeCalories = activeCalories
        self.sourceDevice = sourceDevice
        self.hourlySteps = hourlySteps
    }
}

public struct CanonicalCardiovascularSummary: Codable, Sendable, Equatable {
    public let averageBpm: Double?
    public let restingBpm: Double?
    public let minBpm: Double?
    public let maxBpm: Double?
    public let zones: CanonicalHeartRateZones
    public let intradayPoints: [IntradayHeartRatePoint]
    
    enum CodingKeys: String, CodingKey {
        case averageBpm = "average_bpm"
        case restingBpm = "resting_bpm"
        case minBpm = "min_bpm"
        case maxBpm = "max_bpm"
        case zones
        case intradayPoints = "intraday_points"
    }
    
    public init(
        averageBpm: Double? = nil,
        restingBpm: Double? = nil,
        minBpm: Double? = nil,
        maxBpm: Double? = nil,
        zones: CanonicalHeartRateZones,
        intradayPoints: [IntradayHeartRatePoint] = []
    ) {
        self.averageBpm = averageBpm
        self.restingBpm = restingBpm
        self.minBpm = minBpm
        self.maxBpm = maxBpm
        self.zones = zones
        self.intradayPoints = intradayPoints
    }
}

public struct CanonicalHeartRateZones: Codable, Sendable, Equatable {
    public let resting: Int
    public let fatBurn: Int
    public let cardio: Int
    public let peak: Int
    
    enum CodingKeys: String, CodingKey {
        case resting
        case fatBurn = "fat_burn"
        case cardio
        case peak
    }
    
    public init(resting: Int = 0, fatBurn: Int = 0, cardio: Int = 0, peak: Int = 0) {
        self.resting = resting
        self.fatBurn = fatBurn
        self.cardio = cardio
        self.peak = peak
    }
}

public struct CanonicalStressSummary: Codable, Sendable, Equatable {
    public let currentScore: Int
    public let currentLevel: StressLevel
    public let dailyAverage: Int
    public let peakHour: Int?
    public let peakScore: Int?
    public let lowestHour: Int?
    public let lowestScore: Int?
    public let parasympatheticPercent: Int
    public let sympatheticPercent: Int
    public let baselineHrvMs: Double
    public let currentHrvMs: Double?
    public let hrvDeltaPercent: Double?
    public let restingHeartRateBpm: Double?
    public let currentSedentaryBpm: Double?
    public let heartRateElevationBpm: Double?
    public let monkeyMood: MonkeyMood
    public let adviceQuote: String
    public let recommendedBreathing: String
    public let intradayPoints: [IntradayStressPoint]
    
    enum CodingKeys: String, CodingKey {
        case currentScore = "current_score"
        case currentLevel = "current_level"
        case dailyAverage = "daily_average"
        case peakHour = "peak_hour"
        case peakScore = "peak_score"
        case lowestHour = "lowest_hour"
        case lowestScore = "lowest_score"
        case parasympatheticPercent = "parasympathetic_percent"
        case sympatheticPercent = "sympathetic_percent"
        case baselineHrvMs = "baseline_hrv_ms"
        case currentHrvMs = "current_hrv_ms"
        case hrvDeltaPercent = "hrv_delta_percent"
        case restingHeartRateBpm = "resting_heart_rate_bpm"
        case currentSedentaryBpm = "current_sedentary_bpm"
        case heartRateElevationBpm = "heart_rate_elevation_bpm"
        case monkeyMood = "monkey_mood"
        case adviceQuote = "advice_quote"
        case recommendedBreathing = "recommended_breathing"
        case intradayPoints = "intraday_points"
    }
    
    public init(
        currentScore: Int,
        currentLevel: StressLevel,
        dailyAverage: Int,
        peakHour: Int? = nil,
        peakScore: Int? = nil,
        lowestHour: Int? = nil,
        lowestScore: Int? = nil,
        parasympatheticPercent: Int,
        sympatheticPercent: Int,
        baselineHrvMs: Double,
        currentHrvMs: Double? = nil,
        hrvDeltaPercent: Double? = nil,
        restingHeartRateBpm: Double? = nil,
        currentSedentaryBpm: Double? = nil,
        heartRateElevationBpm: Double? = nil,
        monkeyMood: MonkeyMood,
        adviceQuote: String,
        recommendedBreathing: String,
        intradayPoints: [IntradayStressPoint] = []
    ) {
        self.currentScore = currentScore
        self.currentLevel = currentLevel
        self.dailyAverage = dailyAverage
        self.peakHour = peakHour
        self.peakScore = peakScore
        self.lowestHour = lowestHour
        self.lowestScore = lowestScore
        self.parasympatheticPercent = parasympatheticPercent
        self.sympatheticPercent = sympatheticPercent
        self.baselineHrvMs = baselineHrvMs
        self.currentHrvMs = currentHrvMs
        self.hrvDeltaPercent = hrvDeltaPercent
        self.restingHeartRateBpm = restingHeartRateBpm
        self.currentSedentaryBpm = currentSedentaryBpm
        self.heartRateElevationBpm = heartRateElevationBpm
        self.monkeyMood = monkeyMood
        self.adviceQuote = adviceQuote
        self.recommendedBreathing = recommendedBreathing
        self.intradayPoints = intradayPoints
    }
}

public struct CanonicalVitalSummaryItem: Codable, Sendable, Equatable {
    public let type: String
    public let value: Double
    public let unit: String
    public let sourceDevice: String?
    public let timestamp: Date
    
    enum CodingKeys: String, CodingKey {
        case type
        case value
        case unit
        case sourceDevice = "source_device"
        case timestamp
    }
    
    public init(
        type: String,
        value: Double,
        unit: String,
        sourceDevice: String? = nil,
        timestamp: Date = Date()
    ) {
        self.type = type
        self.value = value
        self.unit = unit
        self.sourceDevice = sourceDevice
        self.timestamp = timestamp
    }
}
