import Foundation

// MARK: - Health Metric Types

/// Comprehensive metric taxonomy matching Supabase vitals and health_telemetry tables.
public enum HealthMetricType: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    // Activity
    case steps = "steps"
    case activeEnergy = "active_energy"
    case basalEnergy = "basal_energy"
    case distance = "distance"
    case floorsClimbed = "floors_climbed"
    case walkingSpeed = "walking_speed"
    case runningSpeed = "running_speed"
    case cyclingPower = "cycling_power"
    case cyclingCadence = "cycling_cadence"
    case workoutDuration = "workout_duration"
    
    // Cardiovascular & Vitals
    case heartRate = "heart_rate"
    case restingHeartRate = "resting_heart_rate"
    case hrvSdnn = "hrv_sdnn"
    case hrvRmssd = "hrv_rmssd"
    case respiratoryRate = "respiratory_rate"
    case oxygenSaturation = "oxygen_saturation"
    case bloodPressureSystolic = "blood_pressure_systolic"
    case bloodPressureDiastolic = "blood_pressure_diastolic"
    case bloodGlucose = "blood_glucose"
    case bodyTemperature = "body_temperature"
    
    // Sleep
    case sleepDuration = "sleep_duration"
    case sleepDeep = "sleep_deep"
    case sleepRem = "sleep_rem"
    case sleepLight = "sleep_light"
    case sleepAwake = "sleep_awake"
    case napDuration = "nap_duration"
    
    // Body Composition
    case weight = "weight"
    case bodyFatPercentage = "body_fat_percentage"
    case leanBodyMass = "lean_body_mass"
    case height = "height"
    case bmi = "bmi"
    case boneMass = "bone_mass"
    
    // Wellness & Lifestyle
    case hydration = "hydration"
    case mindfulSession = "mindful_session"
    case stress = "stress"
    case pai = "pai"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .steps: return "Steps"
        case .activeEnergy: return "Active Calories"
        case .basalEnergy: return "Resting Energy"
        case .distance: return "Distance"
        case .floorsClimbed: return "Floors Climbed"
        case .walkingSpeed: return "Walking Speed"
        case .runningSpeed: return "Running Speed"
        case .cyclingPower: return "Cycling Power"
        case .cyclingCadence: return "Cycling Cadence"
        case .workoutDuration: return "Workout Duration"
        case .heartRate: return "Heart Rate"
        case .restingHeartRate: return "Resting HR"
        case .hrvSdnn: return "HRV (SDNN)"
        case .hrvRmssd: return "HRV (RMSSD)"
        case .respiratoryRate: return "Respiratory Rate"
        case .oxygenSaturation: return "Blood Oxygen (SpO2)"
        case .bloodPressureSystolic: return "Systolic BP"
        case .bloodPressureDiastolic: return "Diastolic BP"
        case .bloodGlucose: return "Blood Glucose"
        case .bodyTemperature: return "Body Temperature"
        case .sleepDuration: return "Sleep Duration"
        case .sleepDeep: return "Deep Sleep"
        case .sleepRem: return "REM Sleep"
        case .sleepLight: return "Light Sleep"
        case .sleepAwake: return "Awake Time"
        case .napDuration: return "Daytime Naps"
        case .weight: return "Weight"
        case .bodyFatPercentage: return "Body Fat"
        case .leanBodyMass: return "Lean Mass"
        case .height: return "Height"
        case .bmi: return "BMI"
        case .boneMass: return "Bone Mass"
        case .hydration: return "Hydration"
        case .mindfulSession: return "Mindfulness"
        case .stress: return "Stress Score"
        case .pai: return "PAI Score"
        }
    }
    
    public var defaultUnit: String {
        switch self {
        case .steps, .floorsClimbed: return "count"
        case .activeEnergy, .basalEnergy: return "kcal"
        case .distance: return "km"
        case .walkingSpeed, .runningSpeed: return "km/h"
        case .cyclingPower: return "W"
        case .cyclingCadence: return "rpm"
        case .workoutDuration, .sleepDuration, .sleepDeep, .sleepRem, .sleepLight, .sleepAwake, .napDuration, .mindfulSession: return "min"
        case .heartRate, .restingHeartRate: return "bpm"
        case .hrvSdnn, .hrvRmssd: return "ms"
        case .respiratoryRate: return "br/min"
        case .oxygenSaturation, .bodyFatPercentage: return "%"
        case .bloodPressureSystolic, .bloodPressureDiastolic: return "mmHg"
        case .bloodGlucose: return "mg/dL"
        case .bodyTemperature: return "°C"
        case .weight, .leanBodyMass, .boneMass: return "kg"
        case .height: return "cm"
        case .bmi: return "kg/m²"
        case .hydration: return "ml"
        case .stress, .pai: return "pts"
        }
    }
    
    public var systemImage: String {
        switch self {
        case .steps: return "figure.walk"
        case .activeEnergy: return "flame.fill"
        case .basalEnergy: return "bolt.fill"
        case .distance: return "figure.walk.motion"
        case .floorsClimbed: return "stairs"
        case .walkingSpeed, .runningSpeed: return "speedometer"
        case .cyclingPower, .cyclingCadence: return "figure.outdoor.cycle"
        case .workoutDuration: return "stopwatch.fill"
        case .heartRate: return "heart.fill"
        case .restingHeartRate: return "heart.circle.fill"
        case .hrvSdnn, .hrvRmssd: return "waveform.path.ecg"
        case .respiratoryRate: return "lungs.fill"
        case .oxygenSaturation: return "drop.degreesign.fill"
        case .bloodPressureSystolic, .bloodPressureDiastolic: return "cross.case.fill"
        case .bloodGlucose: return "drop.fill"
        case .bodyTemperature: return "thermometer.medium"
        case .sleepDuration, .sleepDeep, .sleepRem, .sleepLight, .sleepAwake, .napDuration: return "bed.double.fill"
        case .weight, .bodyFatPercentage, .leanBodyMass, .bmi, .boneMass: return "scalemass.fill"
        case .height: return "ruler.fill"
        case .hydration: return "drop.fill"
        case .mindfulSession: return "brain.head.profile"
        case .stress: return "gauge.medium"
        case .pai: return "trophy.fill"
        }
    }
    
    /// Normalizes raw string representations from PostgREST/Supabase into standard enum cases.
    public static func from(rawString: String) -> HealthMetricType? {
        let norm = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
        
        switch norm {
        case "steps", "stepcount": return .steps
        case "activeenergy", "activecalories", "calories", "energy": return .activeEnergy
        case "basalenergy", "basalenergyburned", "restingenergy", "restingcalories": return .basalEnergy
        case "distance", "distancewalkingrunning": return .distance
        case "floorsclimbed", "flightsclimbed", "floors": return .floorsClimbed
        case "walkingspeed": return .walkingSpeed
        case "runningspeed": return .runningSpeed
        case "cyclingpower": return .cyclingPower
        case "cyclingcadence": return .cyclingCadence
        case "workoutduration": return .workoutDuration
        case "heartrate", "hr": return .heartRate
        case "restingheartrate", "rhr": return .restingHeartRate
        case "hrv", "hrvsdnn", "heartratevariabilitysdnn", "heartratevariability": return .hrvSdnn
        case "hrvrmssd", "heartratevariabilityrmssd": return .hrvRmssd
        case "respiratoryrate", "resp", "respiration": return .respiratoryRate
        case "oxygensaturation", "spo2", "bloodoxygen": return .oxygenSaturation
        case "bloodpressuresystolic", "systolic": return .bloodPressureSystolic
        case "bloodpressurediastolic", "diastolic": return .bloodPressureDiastolic
        case "bloodglucose", "glucose": return .bloodGlucose
        case "bodytemperature", "temperature", "temp": return .bodyTemperature
        case "sleepduration", "sleep": return .sleepDuration
        case "sleepdeep", "sleepstagedeep": return .sleepDeep
        case "sleeprem", "sleepstagerem": return .sleepRem
        case "sleeplight", "sleepcore", "sleepstagelight", "sleepstagecore": return .sleepLight
        case "sleepawake", "sleepstageawake": return .sleepAwake
        case "napduration", "sleepnap", "nap": return .napDuration
        case "weight", "bodymass": return .weight
        case "bodyfatpercentage", "bodyfat": return .bodyFatPercentage
        case "leanbodymass", "leanmass": return .leanBodyMass
        case "height": return .height
        case "bmi", "bodymassindex": return .bmi
        case "bonemass": return .boneMass
        case "hydration", "water", "dietarywater": return .hydration
        case "mindfulsession", "mindfulness": return .mindfulSession
        case "stress": return .stress
        case "pai": return .pai
        default: return nil
        }
    }
}

// MARK: - Supabase Raw Telemetry Record

/// High-frequency sensor sample stored in `public.health_telemetry`.
public struct HealthTelemetryRecord: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let userId: String
    public let type: String
    public let value: Double?
    public let unit: String?
    public let startTime: Date
    public let endTime: Date?
    public let sourceDevice: String?
    public let createdAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case type
        case value
        case unit
        case startTime = "start_time"
        case endTime = "end_time"
        case sourceDevice = "source_device"
        case createdAt = "created_at"
    }
    
    public init(
        id: String = UUID().uuidString,
        userId: String,
        type: String,
        value: Double?,
        unit: String?,
        startTime: Date,
        endTime: Date? = nil,
        sourceDevice: String? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.type = type
        self.value = value
        self.unit = unit
        self.startTime = startTime
        self.endTime = endTime
        self.sourceDevice = sourceDevice
        self.createdAt = createdAt
    }
    
    public var normalizedType: String {
        type.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
    }
    
    public var isHeartRate: Bool {
        normalizedType == "heartrate" || normalizedType == "hr"
    }
    
    public var isSteps: Bool {
        normalizedType == "steps" || normalizedType == "stepcount"
    }
    
    public var isSleep: Bool {
        normalizedType.hasPrefix("sleep")
    }
    
    public var isSleepStage: Bool {
        normalizedType.hasPrefix("sleepstage") ||
        normalizedType == "sleepdeep" ||
        normalizedType == "sleeprem" ||
        normalizedType == "sleeplight" ||
        normalizedType == "sleepcore" ||
        normalizedType == "sleepawake"
    }
    
    public var isNap: Bool {
        normalizedType == "sleepnap" || normalizedType == "nap"
    }
    
    /// Normalizes duration into seconds regardless of whether the raw value is hours, minutes, or seconds.
    public var durationSeconds: Double {
        if let v = value, v > 0 {
            let u = unit?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            if u == "hours" || u == "hour" || u == "h" || u == "hr" { return v * 3600.0 }
            if u == "minutes" || u == "minute" || u == "min" || u == "m" { return v * 60.0 }
            if u == "seconds" || u == "sec" || u == "s" { return v }
        }
        if let end = endTime, end > startTime {
            return end.timeIntervalSince(startTime)
        }
        return 0
    }
    
    public var effectiveEndTime: Date {
        if durationSeconds > 0 {
            return startTime.addingTimeInterval(durationSeconds)
        }
        if let end = endTime, end > startTime {
            return end
        }
        return startTime
    }
    
    public var sleepStageType: SleepStageType {
        let norm = normalizedType
        if norm.contains("deep") { return .deep }
        if norm.contains("rem") { return .rem }
        if norm.contains("awake") || norm.contains("wake") { return .awake }
        if norm.contains("light") || norm.contains("core") { return .light }
        return .unknown
    }
}

// MARK: - Supabase Daily Vital Metric Record

/// Daily aggregate row stored in `public.vitals` or `public.health_vitals`.
public struct VitalMetricRecord: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let userId: String
    public let type: String
    public let value: Double
    public let unit: String?
    public let date: String // ISO date "yyyy-MM-dd"
    public let sourceDevice: String?
    public let createdAt: Date?
    public let updatedAt: Date?
    public let syncedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case type
        case value
        case unit
        case date
        case sourceDevice = "source_device"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case syncedAt = "synced_at"
    }
    
    public init(
        id: String = UUID().uuidString,
        userId: String,
        type: String,
        value: Double,
        unit: String? = nil,
        date: String,
        sourceDevice: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        syncedAt: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.type = type
        self.value = value
        self.unit = unit
        self.date = date
        self.sourceDevice = sourceDevice
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncedAt = syncedAt
    }
    
    public var metricType: HealthMetricType? {
        HealthMetricType.from(rawString: type)
    }
}

// MARK: - Sleep Stages & Sessions

public enum SleepStageType: String, Codable, CaseIterable, Hashable, Sendable {
    case awake = "Awake"
    case rem = "REM"
    case light = "Light"
    case deep = "Deep"
    case unknown = "Unknown"
    
    public var hexColor: String {
        switch self {
        case .awake: return "#FF7043" // Coral Orange
        case .rem: return "#26C6DA"   // Cyan Glow
        case .light: return "#42A5F5" // Sky Blue
        case .deep: return "#3949AB"  // Indigo Midnight
        case .unknown: return "#78909C" // Muted Slate
        }
    }
    
    public var sortOrder: Int {
        switch self {
        case .awake: return 0
        case .rem: return 1
        case .light: return 2
        case .deep: return 3
        case .unknown: return 4
        }
    }
}

/// A discrete chronological sleep stage block with exact start and end boundaries.
public struct SleepStageRecord: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let stageType: SleepStageType
    public let startTime: Date
    public let endTime: Date
    public let durationSeconds: Double
    public let sourceDevice: String?
    
    public init(
        id: String = UUID().uuidString,
        stageType: SleepStageType,
        startTime: Date,
        endTime: Date,
        durationSeconds: Double? = nil,
        sourceDevice: String? = nil
    ) {
        self.id = id
        self.stageType = stageType
        self.startTime = startTime
        self.endTime = endTime
        self.durationSeconds = durationSeconds ?? max(0, endTime.timeIntervalSince(startTime))
        self.sourceDevice = sourceDevice
    }
    
    public var durationMinutes: Double {
        durationSeconds / 60.0
    }
}

/// Complete nocturnal sleep or nap session.
public struct SleepSession: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let startTime: Date
    public let endTime: Date
    public let isNap: Bool
    public let stages: [SleepStageRecord]
    public let sourceDevice: String
    public let hasGranularHypnogram: Bool
    
    public init(
        id: String = UUID().uuidString,
        startTime: Date,
        endTime: Date,
        isNap: Bool = false,
        stages: [SleepStageRecord] = [],
        sourceDevice: String = "Unknown",
        hasGranularHypnogram: Bool = false
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.isNap = isNap
        self.stages = stages
        self.sourceDevice = sourceDevice
        self.hasGranularHypnogram = hasGranularHypnogram
    }
    
    // Duration Computations
    public var deepSeconds: Double {
        stages.filter { $0.stageType == .deep }.reduce(0) { $0 + $1.durationSeconds }
    }
    
    public var remSeconds: Double {
        stages.filter { $0.stageType == .rem }.reduce(0) { $0 + $1.durationSeconds }
    }
    
    public var lightSeconds: Double {
        stages.filter { $0.stageType == .light }.reduce(0) { $0 + $1.durationSeconds }
    }
    
    public var awakeSeconds: Double {
        stages.filter { $0.stageType == .awake }.reduce(0) { $0 + $1.durationSeconds }
    }
    
    public var asleepSeconds: Double {
        let asleepStages = deepSeconds + remSeconds + lightSeconds
        if asleepStages > 0 { return asleepStages }
        return max(0, durationSeconds - awakeSeconds)
    }
    
    public var durationSeconds: Double {
        let totalStages = deepSeconds + remSeconds + lightSeconds + awakeSeconds
        let span = max(0, endTime.timeIntervalSince(startTime))
        if totalStages > 0 && span > totalStages * 1.35 {
            return totalStages
        }
        return max(span, totalStages)
    }
    
    public var awakeCount: Int {
        stages.filter { $0.stageType == .awake }.count
    }
    
    // Proportions
    public var deepPercent: Int {
        asleepSeconds > 0 ? Int(round((deepSeconds / asleepSeconds) * 100)) : 0
    }
    
    public var remPercent: Int {
        asleepSeconds > 0 ? Int(round((remSeconds / asleepSeconds) * 100)) : 0
    }
    
    public var lightPercent: Int {
        asleepSeconds > 0 ? Int(round((lightSeconds / asleepSeconds) * 100)) : 0
    }
    
    public var awakePercent: Int {
        durationSeconds > 0 ? Int(round((awakeSeconds / durationSeconds) * 100)) : 0
    }
    
    public var restorativePercent: Int {
        deepPercent + remPercent
    }
    
    public var efficiencyPercent: Int {
        guard durationSeconds > 0 else { return 85 }
        let raw = Int(round((asleepSeconds / durationSeconds) * 100))
        return min(max(raw, 10), 100)
    }
    
    // Clinical Sleep Score (0 - 100)
    public var sleepScore: Int {
        guard asleepSeconds > 0 else { return 0 }
        // 1. Duration score (up to 50 pts based on 8-hour target)
        let durationScore = min((asleepSeconds / (8.0 * 3600.0)) * 50.0, 50.0)
        // 2. Efficiency score (up to 30 pts)
        let effScore = (Double(efficiencyPercent) / 100.0) * 30.0
        // 3. Restorative score (up to 20 pts based on 40% Deep+REM target)
        let qualScore = min((Double(restorativePercent) / 40.0) * 20.0, 20.0)
        
        let total = Int(round(durationScore + effScore + qualScore))
        return min(max(total, 0), 100)
    }
    
    public var sleepQualityRating: String {
        switch sleepScore {
        case 85...100: return "Optimal"
        case 75..<85: return "Good"
        case 60..<75: return "Fair"
        case 1..<60: return "Restless"
        default: return "No Data"
        }
    }
    
    // Formatted Strings
    public var totalAsleepFormatted: String { Self.formatTimeSpan(asleepSeconds) }
    public var timeInBedFormatted: String { Self.formatTimeSpan(durationSeconds) }
    public var deepFormatted: String { Self.formatTimeSpan(deepSeconds) }
    public var remFormatted: String { Self.formatTimeSpan(remSeconds) }
    public var lightFormatted: String { Self.formatTimeSpan(lightSeconds) }
    public var awakeFormatted: String { Self.formatTimeSpan(awakeSeconds) }
    
    public var bedtimeFormatted: String {
        Self.timeFormatter.string(from: startTime)
    }
    
    public var wakeTimeFormatted: String {
        Self.timeFormatter.string(from: endTime)
    }
    
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
    
    public static func formatTimeSpan(_ seconds: Double) -> String {
        guard seconds > 0 else { return "--" }
        let totalMin = Int(round(seconds / 60.0))
        let hours = totalMin / 60
        let mins = totalMin % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        } else {
            return "\(mins)m"
        }
    }
}

/// Independent daytime nap session.
public struct NapSession: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let startTime: Date
    public let endTime: Date
    public let durationSeconds: Double
    public let sourceDevice: String
    
    public init(
        id: String = UUID().uuidString,
        startTime: Date,
        endTime: Date,
        durationSeconds: Double? = nil,
        sourceDevice: String = "Unknown"
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.durationSeconds = durationSeconds ?? max(0, endTime.timeIntervalSince(startTime))
        self.sourceDevice = sourceDevice
    }
    
    public var formattedDuration: String {
        SleepSession.formatTimeSpan(durationSeconds)
    }
    
    public var timeRangeFormatted: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return "\(f.string(from: startTime)) - \(f.string(from: endTime))"
    }
}

// MARK: - Cardiovascular & Zones

public enum HeartRateZone: String, Codable, CaseIterable, Hashable, Sendable {
    case resting = "Resting"
    case fatBurn = "Fat Burn"
    case cardio = "Cardio"
    case peak = "Peak"
    
    public var bpmRangeText: String {
        switch self {
        case .resting: return "< 100 bpm"
        case .fatBurn: return "100 - 119 bpm"
        case .cardio: return "120 - 149 bpm"
        case .peak: return "≥ 150 bpm"
        }
    }
    
    public var hexColor: String {
        switch self {
        case .resting: return "#42A5F5" // Blue
        case .fatBurn: return "#66BB6A" // Green
        case .cardio: return "#FFA726"  // Orange
        case .peak: return "#EF5350"    // Red
        }
    }
    
    public static func zone(for bpm: Double) -> HeartRateZone {
        if bpm < 100 { return .resting }
        if bpm < 120 { return .fatBurn }
        if bpm < 150 { return .cardio }
        return .peak
    }
}

public struct IntradayHeartRatePoint: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let timestamp: Date
    public let bpm: Double
    public let zone: HeartRateZone
    public let sourceDevice: String?
    
    public init(
        id: String = UUID().uuidString,
        timestamp: Date,
        bpm: Double,
        sourceDevice: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.bpm = bpm
        self.zone = HeartRateZone.zone(for: bpm)
        self.sourceDevice = sourceDevice
    }
}

// MARK: - Activity & Trends

public struct HourlyStepBucket: Identifiable, Codable, Hashable, Sendable {
    public let id: Int // 0 - 23 hour of day
    public let hour: Int
    public let steps: Int
    
    public init(hour: Int, steps: Int) {
        self.id = hour
        self.hour = hour
        self.steps = steps
    }
    
    public var hourFormatted: String {
        String(format: "%02d:00", hour)
    }
}

public struct DailyMetricTrendPoint: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let date: Date
    public let value: Double
    public let target: Double?
    public let isCompleteDay: Bool
    
    public init(
        id: String = UUID().uuidString,
        date: Date,
        value: Double,
        target: Double? = nil,
        isCompleteDay: Bool = true
    ) {
        self.id = id
        self.date = date
        self.value = value
        self.target = target
        self.isCompleteDay = isCompleteDay
    }
    
    public var dayName: String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date)
    }
    
    public var shortDateFormatted: String {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f.string(from: date)
    }
}

// MARK: - Device Classification

public enum DeviceSource: Hashable, Sendable, Identifiable, Comparable {
    case appleWatch
    case amazfit
    case oneplus
    case huawei
    case healthKit
    case healthConnect
    case manual
    case other(String)
    
    public var id: String { displayName }
    
    public static func < (lhs: DeviceSource, rhs: DeviceSource) -> Bool {
        lhs.displayName < rhs.displayName
    }
    
    public static func from(name: String?) -> DeviceSource {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return .other("Unknown")
        }
        let lower = name.lowercased()
        if lower.contains("healthkit") || lower.contains("apple health") || lower == "ios" { return .healthKit }
        if lower.contains("apple") || lower.contains("watchos") { return .appleWatch }
        if lower.contains("zepp") || lower.contains("amazfit") || lower.contains("balance") { return .amazfit }
        if lower.contains("oneplus") || lower.contains("wearos") { return .oneplus }
        if lower.contains("huawei") || lower.contains("harmony") || lower.contains("gt5") { return .huawei }
        if lower.contains("health connect") || lower.contains("healthconnect") || lower == "android" { return .healthConnect }
        if lower.contains("manual") { return .manual }
        return .other(name)
    }
    
    public var displayName: String {
        switch self {
        case .appleWatch: return "Apple Watch"
        case .amazfit: return "Amazfit Balance"
        case .oneplus: return "OnePlus Watch 3"
        case .huawei: return "Huawei Watch GT 5 Pro"
        case .healthKit: return "Apple Health"
        case .healthConnect: return "Health Connect"
        case .manual: return "Manual Entry"
        case .other(let name): return name
        }
    }
    
    public var systemImage: String {
        switch self {
        case .appleWatch, .amazfit, .oneplus, .huawei: return "applewatch"
        case .healthKit, .healthConnect: return "heart.text.square.fill"
        case .manual: return "hand.tap.fill"
        case .other: return "sensor.fill"
        }
    }
}
