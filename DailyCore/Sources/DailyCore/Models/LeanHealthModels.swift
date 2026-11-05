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
    public let isCustomPriority: Bool
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
        case isCustomPriority = "is_custom_priority"
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
        isCustomPriority: Bool = false,
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
        self.isCustomPriority = isCustomPriority
        self.color = color
        self.createdAt = createdAt
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.userId = try container.decode(String.self, forKey: .userId)
        self.platform = try container.decodeIfPresent(String.self, forKey: .platform) ?? "iOS"
        self.deviceKind = try container.decodeIfPresent(String.self, forKey: .deviceKind) ?? "watch"
        self.vendor = try container.decodeIfPresent(String.self, forKey: .vendor)
        self.model = try container.decodeIfPresent(String.self, forKey: .model)
        self.displayName = try container.decode(String.self, forKey: .displayName)
        self.hostDeviceName = try container.decodeIfPresent(String.self, forKey: .hostDeviceName)
        self.prioritySleep = try container.decodeIfPresent(Int.self, forKey: .prioritySleep) ?? 10
        self.priorityActivity = try container.decodeIfPresent(Int.self, forKey: .priorityActivity) ?? self.prioritySleep
        self.isCustomPriority = try container.decodeIfPresent(Bool.self, forKey: .isCustomPriority) ?? false
        self.color = try container.decodeIfPresent(String.self, forKey: .color)
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
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
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.userId = try container.decodeIfPresent(String.self, forKey: .userId) ?? ""
        self.localDate = try container.decode(String.self, forKey: .localDate)
        self.sessionType = try container.decodeIfPresent(String.self, forKey: .sessionType) ?? "primary_sleep"
        self.sourceDeviceKey = try container.decode(String.self, forKey: .sourceDeviceKey)
        self.hostDeviceName = try container.decodeIfPresent(String.self, forKey: .hostDeviceName)
        self.startTime = try container.decodeIfPresent(Date.self, forKey: .startTime) ?? Date()
        let decodedDuration = try container.decodeIfPresent(Int.self, forKey: .durationSeconds) ?? 0
        self.endTime = try container.decodeIfPresent(Date.self, forKey: .endTime) ?? self.startTime.addingTimeInterval(Double(decodedDuration))
        self.durationSeconds = decodedDuration
        self.timeInBedSeconds = try container.decodeIfPresent(Int.self, forKey: .timeInBedSeconds) ?? decodedDuration
        self.efficiencyPercent = try container.decodeIfPresent(Double.self, forKey: .efficiencyPercent)
        self.sleepScore = try container.decodeIfPresent(Int.self, forKey: .sleepScore)
        self.deepSeconds = try container.decodeIfPresent(Int.self, forKey: .deepSeconds) ?? 0
        self.remSeconds = try container.decodeIfPresent(Int.self, forKey: .remSeconds) ?? 0
        self.lightSeconds = try container.decodeIfPresent(Int.self, forKey: .lightSeconds) ?? 0
        self.awakeSeconds = try container.decodeIfPresent(Int.self, forKey: .awakeSeconds) ?? 0
        self.latencySeconds = try container.decodeIfPresent(Int.self, forKey: .latencySeconds) ?? 0
        self.qualityRating = try container.decodeIfPresent(String.self, forKey: .qualityRating)
        self.stages = try container.decodeIfPresent([SleepStageRecord].self, forKey: .stages) ?? []
        self.sourcePriority = try container.decodeIfPresent(Int.self, forKey: .sourcePriority) ?? 10
        self.isUserSelected = try container.decodeIfPresent(Bool.self, forKey: .isUserSelected) ?? false
        self.ingestedAt = try container.decodeIfPresent(Date.self, forKey: .ingestedAt)
    }
    
    /// True when granular REM/Deep/Light architecture exists (even when the `stages` JSONB array was omitted in scalar Trends projections).
    public var hasGranularSleepStages: Bool {
        !stages.isEmpty || (deepSeconds + remSeconds + lightSeconds) > 0
    }
    
    /// Converts this lean database record directly to the UI-facing `SleepSession`.
    public func toSleepSession() -> SleepSession {
        let canonDevice = DeviceSource.from(name: sourceDeviceKey).displayName
        var effectiveStages = stages
        if effectiveStages.isEmpty && (deepSeconds + remSeconds + lightSeconds + awakeSeconds) > 0 {
            var cursor = startTime
            if deepSeconds > 0 {
                let end = cursor.addingTimeInterval(Double(deepSeconds))
                effectiveStages.append(SleepStageRecord(id: "\(id)_deep", stageType: .deep, startTime: cursor, endTime: end, durationSeconds: Double(deepSeconds), sourceDevice: canonDevice))
                cursor = end
            }
            if remSeconds > 0 {
                let end = cursor.addingTimeInterval(Double(remSeconds))
                effectiveStages.append(SleepStageRecord(id: "\(id)_rem", stageType: .rem, startTime: cursor, endTime: end, durationSeconds: Double(remSeconds), sourceDevice: canonDevice))
                cursor = end
            }
            if lightSeconds > 0 {
                let end = cursor.addingTimeInterval(Double(lightSeconds))
                effectiveStages.append(SleepStageRecord(id: "\(id)_light", stageType: .light, startTime: cursor, endTime: end, durationSeconds: Double(lightSeconds), sourceDevice: canonDevice))
                cursor = end
            }
            if awakeSeconds > 0 {
                let end = cursor.addingTimeInterval(Double(awakeSeconds))
                effectiveStages.append(SleepStageRecord(id: "\(id)_awake", stageType: .awake, startTime: cursor, endTime: end, durationSeconds: Double(awakeSeconds), sourceDevice: canonDevice))
            }
        }
        return SleepSession(
            id: id,
            startTime: startTime,
            endTime: endTime,
            isNap: sessionType == "nap",
            stages: effectiveStages,
            sourceDevice: canonDevice,
            hasGranularHypnogram: hasGranularSleepStages
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
    public let latestHeartRate: Int?
    public let latestHrAt: Date?
    public let vitalsTimestamps: [String: String]?
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
        case latestHeartRate = "latest_heart_rate"
        case latestHrAt = "latest_hr_at"
        case vitalsTimestamps = "vitals_timestamps"
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
        latestHeartRate: Int? = nil,
        latestHrAt: Date? = nil,
        vitalsTimestamps: [String: String]? = nil,
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
        self.latestHeartRate = latestHeartRate
        self.latestHrAt = latestHrAt
        self.vitalsTimestamps = vitalsTimestamps
        self.updatedAt = updatedAt
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.userId = try container.decode(String.self, forKey: .userId)
        self.localDate = try container.decode(String.self, forKey: .localDate)
        self.sourceDeviceKey = try container.decode(String.self, forKey: .sourceDeviceKey)
        self.hostDeviceName = try container.decodeIfPresent(String.self, forKey: .hostDeviceName)
        self.steps = try container.decodeIfPresent(Int.self, forKey: .steps) ?? 0
        self.activeKcal = try container.decodeIfPresent(Double.self, forKey: .activeKcal) ?? 0.0
        self.restingHeartRate = try container.decodeIfPresent(Int.self, forKey: .restingHeartRate)
        self.spo2 = try container.decodeIfPresent(Double.self, forKey: .spo2)
        self.respiratoryRate = try container.decodeIfPresent(Double.self, forKey: .respiratoryRate)
        self.skinTempCelsius = try container.decodeIfPresent(Double.self, forKey: .skinTempCelsius)
        self.weightKg = try container.decodeIfPresent(Double.self, forKey: .weightKg)
        self.hrvSdnnNightly = try container.decodeIfPresent(Double.self, forKey: .hrvSdnnNightly)
        self.hrvRmssdNightly = try container.decodeIfPresent(Double.self, forKey: .hrvRmssdNightly)
        self.hourlySteps = try container.decodeIfPresent([HourlyStepBucket].self, forKey: .hourlySteps)
        self.latestHeartRate = try container.decodeIfPresent(Int.self, forKey: .latestHeartRate)
        self.latestHrAt = try container.decodeIfPresent(Date.self, forKey: .latestHrAt)
        self.vitalsTimestamps = try container.decodeIfPresent([String: String].self, forKey: .vitalsTimestamps)
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
    
    public var hasSignal: Bool {
        steps > 0 ||
        activeKcal > 0 ||
        (latestHeartRate ?? 0) > 0 ||
        (restingHeartRate ?? 0) > 0 ||
        (spo2 ?? 0) > 0 ||
        (respiratoryRate ?? 0) > 0 ||
        skinTempCelsius != nil ||
        (weightKg ?? 0) > 0 ||
        (hrvSdnnNightly ?? 0) > 0 ||
        (hrvRmssdNightly ?? 0) > 0
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
            id: id,
            timestamp: timestamp,
            bpm: Double(bpmAvg),
            sourceDevice: DeviceSource.from(name: sourceDeviceKey).displayName
        )
    }
}

/// Lightweight scalar projection of `health_daily_summary` omitting the heavy `summary` JSONB column (~50 B/row vs ~35 KB/row).
public struct HealthDailySummaryScalarRow: Codable, Hashable, Sendable {
    public let localDate: String
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
    
    enum CodingKeys: String, CodingKey {
        case localDate = "local_date"
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
    }
}
