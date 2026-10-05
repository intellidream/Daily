// AUTO-GENERATED from HealthSpec/metric_registry.json - DO NOT EDIT MANUALLY
// Generated at: 2026-10-05T13:51:30.205Z

import Foundation

public enum CanonicalHealthMetric: String, CaseIterable, Codable, Sendable {
    case steps = "steps"
    case activeEnergy = "active_energy"
    case basalEnergy = "basal_energy"
    case distance = "distance"
    case floorsClimbed = "floors_climbed"
    case walkingSpeed = "walking_speed"
    case heartRate = "heart_rate"
    case restingHeartRate = "resting_heart_rate"
    case hrvSdnn = "hrv_sdnn"
    case hrvRmssd = "hrv_rmssd"
    case oxygenSaturation = "oxygen_saturation"
    case respiratoryRate = "respiratory_rate"
    case sleepStageDeep = "sleep_stage_deep"
    case sleepStageRem = "sleep_stage_rem"
    case sleepStageLight = "sleep_stage_light"
    case sleepStageAwake = "sleep_stage_awake"
    case sleepDuration = "sleep_duration"
    case stress = "stress"
    case pai = "pai"
    case weight = "weight"
    case hydration = "hydration"
    case caffeine = "caffeine"

    public var displayName: String {
        switch self {
        case .steps: return "Steps"
        case .activeEnergy: return "Active Calories"
        case .basalEnergy: return "Resting Calories"
        case .distance: return "Distance"
        case .floorsClimbed: return "Floors Climbed"
        case .walkingSpeed: return "Walking Speed"
        case .heartRate: return "Heart Rate"
        case .restingHeartRate: return "Resting Heart Rate"
        case .hrvSdnn: return "Heart Rate Variability (SDNN)"
        case .hrvRmssd: return "Heart Rate Variability (RMSSD)"
        case .oxygenSaturation: return "Blood Oxygen (SpO2)"
        case .respiratoryRate: return "Respiratory Rate"
        case .sleepStageDeep: return "Deep Sleep"
        case .sleepStageRem: return "REM Sleep"
        case .sleepStageLight: return "Light / Core Sleep"
        case .sleepStageAwake: return "Awake During Night"
        case .sleepDuration: return "Total Sleep Duration"
        case .stress: return "Stress Score"
        case .pai: return "PAI (Personal Activity Intelligence)"
        case .weight: return "Body Weight"
        case .hydration: return "Water Intake"
        case .caffeine: return "Caffeine Intake"
        }
    }

    public var canonicalUnit: String {
        switch self {
        case .steps: return "count"
        case .activeEnergy: return "kcal"
        case .basalEnergy: return "kcal"
        case .distance: return "m"
        case .floorsClimbed: return "count"
        case .walkingSpeed: return "m/s"
        case .heartRate: return "bpm"
        case .restingHeartRate: return "bpm"
        case .hrvSdnn: return "ms"
        case .hrvRmssd: return "ms"
        case .oxygenSaturation: return "percent"
        case .respiratoryRate: return "count/min"
        case .sleepStageDeep: return "seconds"
        case .sleepStageRem: return "seconds"
        case .sleepStageLight: return "seconds"
        case .sleepStageAwake: return "seconds"
        case .sleepDuration: return "seconds"
        case .stress: return "score_100"
        case .pai: return "score"
        case .weight: return "kg"
        case .hydration: return "ml"
        case .caffeine: return "mg"
        }
    }

    public static func from(alias: String) -> CanonicalHealthMetric? {
        if let direct = CanonicalHealthMetric(rawValue: alias) {
            return direct
        }
        switch alias {
        case "Steps": return .steps
        case "step_count": return .steps
        case "HKQuantityTypeIdentifierStepCount": return .steps
        case "ActiveEnergy": return .activeEnergy
        case "active_calories": return .activeEnergy
        case "calorie": return .activeEnergy
        case "calories": return .activeEnergy
        case "HKQuantityTypeIdentifierActiveEnergyBurned": return .activeEnergy
        case "BasalEnergyBurned": return .basalEnergy
        case "basal_calories": return .basalEnergy
        case "resting_energy": return .basalEnergy
        case "HKQuantityTypeIdentifierBasalEnergyBurned": return .basalEnergy
        case "Distance": return .distance
        case "distance_walking_running": return .distance
        case "HKQuantityTypeIdentifierDistanceWalkingRunning": return .distance
        case "FloorsClimbed": return .floorsClimbed
        case "flights_climbed": return .floorsClimbed
        case "HKQuantityTypeIdentifierFlightsClimbed": return .floorsClimbed
        case "WalkingSpeed": return .walkingSpeed
        case "HKQuantityTypeIdentifierWalkingSpeed": return .walkingSpeed
        case "HeartRate": return .heartRate
        case "hr": return .heartRate
        case "pulse": return .heartRate
        case "HKQuantityTypeIdentifierHeartRate": return .heartRate
        case "RestingHeartRate": return .restingHeartRate
        case "rhr": return .restingHeartRate
        case "HKQuantityTypeIdentifierRestingHeartRate": return .restingHeartRate
        case "HeartRateVariabilitySDNN": return .hrvSdnn
        case "hrv": return .hrvSdnn
        case "HKQuantityTypeIdentifierHeartRateVariabilitySDNN": return .hrvSdnn
        case "RMSSD": return .hrvRmssd
        case "HeartRateVariabilityRmssdRecord": return .hrvRmssd
        case "OxygenSaturation": return .oxygenSaturation
        case "spo2": return .oxygenSaturation
        case "blood_oxygen": return .oxygenSaturation
        case "bo": return .oxygenSaturation
        case "HKQuantityTypeIdentifierOxygenSaturation": return .oxygenSaturation
        case "RespiratoryRate": return .respiratoryRate
        case "breathing_rate": return .respiratoryRate
        case "HKQuantityTypeIdentifierRespiratoryRate": return .respiratoryRate
        case "SleepDeep": return .sleepStageDeep
        case "sleep_deep": return .sleepStageDeep
        case "deep_sleep": return .sleepStageDeep
        case "HKCategoryValueSleepAnalysisAsleepDeep": return .sleepStageDeep
        case "SleepREM": return .sleepStageRem
        case "sleep_rem": return .sleepStageRem
        case "rem_sleep": return .sleepStageRem
        case "HKCategoryValueSleepAnalysisAsleepREM": return .sleepStageRem
        case "SleepLight": return .sleepStageLight
        case "sleep_light": return .sleepStageLight
        case "light_sleep": return .sleepStageLight
        case "core_sleep": return .sleepStageLight
        case "HKCategoryValueSleepAnalysisAsleepCore": return .sleepStageLight
        case "SleepAwake": return .sleepStageAwake
        case "sleep_awake": return .sleepStageAwake
        case "awake": return .sleepStageAwake
        case "HKCategoryValueSleepAnalysisAwake": return .sleepStageAwake
        case "SleepDuration": return .sleepDuration
        case "sleep": return .sleepDuration
        case "total_sleep": return .sleepDuration
        case "HKCategoryValueSleepAnalysisAsleepUnspecified": return .sleepDuration
        case "Stress": return .stress
        case "stress_score": return .stress
        case "autonomic_stress": return .stress
        case "PAI": return .pai
        case "pai_score": return .pai
        case "Weight": return .weight
        case "body_mass": return .weight
        case "HKQuantityTypeIdentifierBodyMass": return .weight
        case "Hydration": return .hydration
        case "water": return .hydration
        case "water_intake": return .hydration
        case "dietary_water": return .hydration
        case "HKQuantityTypeIdentifierDietaryWater": return .hydration
        case "Caffeine": return .caffeine
        case "caffeine_intake": return .caffeine
        case "dietary_caffeine": return .caffeine
        case "HKQuantityTypeIdentifierDietaryCaffeine": return .caffeine
        default:
            return nil
        }
    }
}
