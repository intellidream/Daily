import Foundation

// MARK: - Lean Health Architecture Models (Phase 1)
// These models map 1:1 to the canonical lean Supabase tables:
// - health_sources
// - health_sleep_sessions
// - health_daily_vitals
// - health_intraday_heart_rate

/// Canonical hardware device or wearable sensor registered in `health_sources`.
public struct HealthSourceRecord: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let userId: String
    public let platform: String
    public let deviceKind: String
    public let vendor: String?
    public let model: String?
    public let displayName: String
    public let hostDeviceName: String?
    public let prioritySleep: Int
    public let priorityActivity: Int
    public let color: String?
    public let createdAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case platform
        case deviceKind = "device_kind"
        case vendor
        case model
        case displayName = "display_name"
        case hostDeviceName = "host_device_name"
        case prioritySleep = "priority_sleep"
        case priorityActivity = "priority_activity"
        case color
        case createdAt = "created_at"
    }
    
    public init(
        id: String,
        userId: String,
        platform: String,
        deviceKind: String,
        vendor: String? = nil,
        model: String? = nil,
        displayName: String,
        hostDeviceName: String? = nil,
        prioritySleep: Int = 10,
        priorityActivity: Int = 10,
        color: String? = "#3897F0",
        createdAt: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.platform = platform
        self.deviceKind = deviceKind
        self.vendor = vendor
        self.model = model
        self.displayName = displayName
        self.hostDeviceName = hostDeviceName
        self.prioritySleep = prioritySleep
        self.priorityActivity = priorityActivity
        self.color = color
        self.createdAt = createdAt
    }
}

/// Discrete sleep session stored in `health_sleep_sessions`.
public struct HealthSleepSessionRecord: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let userId: String
    public let localDate: String
    public let sessionType: String // 'primary_sleep', 'nap'
    public let sourceDeviceKey: String
    public let hostDeviceName: String?
    public let startTime: Date
    public let endTime: Date
    public let durationSeconds: Int
    public let timeInBedSeconds: Int
    public let efficiencyPercent: Double?
    public let sleepScore: Int?
    public let deepSeconds: Int
    public let remSeconds: Int
    public let lightSeconds: Int
    public let awakeSeconds: Int
    public let latencySeconds: Int
    public let qualityRating: String?
    public let stages: [SleepStageRecord]
    public let sourcePriority: Int
    public let isUserSelected: Bool
    public let ingestedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case localDate = "local_date"
        case sessionType = "session_type"
        case sourceDeviceKey = "source_device_key"
        case hostDeviceName = "host_device_name"
        case startTime = "start_time"
        case endTime = "end_time"
        case durationSeconds = "duration_seconds"
        case timeInBedSeconds = "time_in_bed_seconds"
        case efficiencyPercent = "efficiency_percent"
        case sleepScore = "sleep_score"
        case deepSeconds = "deep_seconds"
        case remSeconds = "rem_seconds"
        case lightSeconds = "light_seconds"
        case awakeSeconds = "awake_seconds"
        case latencySeconds = "latency_seconds"
        case qualityRating = "quality_rating"
        case stages
        case sourcePriority = "source_priority"
        case isUserSelected = "is_user_selected"
        case ingestedAt = "ingested_at"
    }
    
    public init(
        id: String,
        userId: String,
        localDate: String,
        sessionType: String = "primary_sleep",
        sourceDeviceKey: String,
        hostDeviceName: String? = nil,
        startTime: Date,
        endTime: Date,
        durationSeconds: Int,
        timeInBedSeconds: Int,
        efficiencyPercent: Double? = nil,
        sleepScore: Int? = nil,
        deepSeconds: Int = 0,
        remSeconds: Int = 0,
        lightSeconds: Int = 0,
        awakeSeconds: Int = 0,
        latencySeconds: Int = 0,
        qualityRating: String? = nil,
        stages: [SleepStageRecord] = [],
        sourcePriority: Int = 10,
        isUserSelected: Bool = false,
        ingestedAt: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.localDate = localDate
        self.sessionType = sessionType
        self.sourceDeviceKey = sourceDeviceKey
        self.hostDeviceName = hostDeviceName
        self.startTime = startTime
        self.endTime = endTime
        self.durationSeconds = durationSeconds
        self.timeInBedSeconds = timeInBedSeconds
        self.efficiencyPercent = efficiencyPercent
        self.sleepScore = sleepScore
        self.deepSeconds = deepSeconds
        self.remSeconds = remSeconds
        self.lightSeconds = lightSeconds
        self.awakeSeconds = awakeSeconds
        self.latencySeconds = latencySeconds
        self.qualityRating = qualityRating
        self.stages = stages
        self.sourcePriority = sourcePriority
        self.isUserSelected = isUserSelected
        self.ingestedAt = ingestedAt
    }
    
    /// Converts this lean database record directly to the UI-facing `SleepSession`.
    public func toSleepSession() -> SleepSession {
        SleepSession(
            id: id,
            startTime: startTime,
            endTime: endTime,
            isNap: sessionType == "nap",
            stages: stages,
            sourceDevice: sourceDeviceKey,
            hasGranularHypnogram: !stages.isEmpty
        )
    }
}

/// Consolidated daily vitals row stored in `health_daily_vitals`.
public struct HealthDailyVitalsRecord: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let userId: String
    public let localDate: String
    public let sourceDeviceKey: String
    public let hostDeviceName: String?
    public let steps: Int
    public let activeKcal: Double
    public let restingHeartRate: Int?
    public let spo2: Double?
    public let respiratoryRate: Double?
    public let skinTempCelsius: Double?
    public let weightKg: Double?
    public let hrvSdnnNightly: Double?
    public let hrvRmssdNightly: Double?
    public let hourlySteps: [HourlyStepBucket]?
    public let updatedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case localDate = "local_date"
        case sourceDeviceKey = "source_device_key"
        case hostDeviceName = "host_device_name"
        case steps
        case activeKcal = "active_kcal"
        case restingHeartRate = "resting_heart_rate"
        case spo2
        case respiratoryRate = "respiratory_rate"
        case skinTempCelsius = "skin_temp_celsius"
        case weightKg = "weight_kg"
        case hrvSdnnNightly = "hrv_sdnn_nightly"
        case hrvRmssdNightly = "hrv_rmssd_nightly"
        case hourlySteps = "hourly_steps"
        case updatedAt = "updated_at"
    }
    
    public init(
        id: String,
        userId: String,
        localDate: String,
        sourceDeviceKey: String,
        hostDeviceName: String? = nil,
        steps: Int = 0,
        activeKcal: Double = 0.0,
        restingHeartRate: Int? = nil,
        spo2: Double? = nil,
        respiratoryRate: Double? = nil,
        skinTempCelsius: Double? = nil,
        weightKg: Double? = nil,
        hrvSdnnNightly: Double? = nil,
        hrvRmssdNightly: Double? = nil,
        hourlySteps: [HourlyStepBucket]? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.localDate = localDate
        self.sourceDeviceKey = sourceDeviceKey
        self.hostDeviceName = hostDeviceName
        self.steps = steps
        self.activeKcal = activeKcal
        self.restingHeartRate = restingHeartRate
        self.spo2 = spo2
        self.respiratoryRate = respiratoryRate
        self.skinTempCelsius = skinTempCelsius
        self.weightKg = weightKg
        self.hrvSdnnNightly = hrvSdnnNightly
        self.hrvRmssdNightly = hrvRmssdNightly
        self.hourlySteps = hourlySteps
        self.updatedAt = updatedAt
    }
}

/// 5-minute bucketed heart rate record stored in `health_intraday_heart_rate`.
public struct HealthIntradayHeartRateRecord: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let userId: String
    public let localDate: String
    public let sourceDeviceKey: String
    public let bucketMinute: Int // 0, 5, 10, ..., 1435
    public let bpmAvg: Int
    public let bpmMin: Int
    public let bpmMax: Int
    public let sampleCount: Int
    public let updatedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case localDate = "local_date"
        case sourceDeviceKey = "source_device_key"
        case bucketMinute = "bucket_minute"
        case bpmAvg = "bpm_avg"
        case bpmMin = "bpm_min"
        case bpmMax = "bpm_max"
        case sampleCount = "sample_count"
        case updatedAt = "updated_at"
    }
    
    public init(
        id: String,
        userId: String,
        localDate: String,
        sourceDeviceKey: String,
        bucketMinute: Int,
        bpmAvg: Int,
        bpmMin: Int,
        bpmMax: Int,
        sampleCount: Int = 1,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.localDate = localDate
        self.sourceDeviceKey = sourceDeviceKey
        self.bucketMinute = bucketMinute
        self.bpmAvg = bpmAvg
        self.bpmMin = bpmMin
        self.bpmMax = bpmMax
        self.sampleCount = sampleCount
        self.updatedAt = updatedAt
    }
    
    /// Converts to the UI `IntradayHeartRatePoint` given a base date.
    public func toPoint(for date: Date) -> IntradayHeartRatePoint {
        let calendar = Calendar.current
        var comps = calendar.dateComponents([.year, .month, .day], from: date)
        comps.hour = bucketMinute / 60
        comps.minute = bucketMinute % 60
        comps.second = 0
        let timestamp = calendar.date(from: comps) ?? date
        return IntradayHeartRatePoint(
            timestamp: timestamp,
            bpm: Double(bpmAvg),
            sourceDevice: sourceDeviceKey
        )
    }
}
