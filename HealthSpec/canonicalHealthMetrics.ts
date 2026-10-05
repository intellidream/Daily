// AUTO-GENERATED from HealthSpec/metric_registry.json - DO NOT EDIT MANUALLY
// Generated at: 2026-10-05T13:51:30.199Z

export type HealthMetricType =
  | 'steps'
  | 'active_energy'
  | 'basal_energy'
  | 'distance'
  | 'floors_climbed'
  | 'walking_speed'
  | 'heart_rate'
  | 'resting_heart_rate'
  | 'hrv_sdnn'
  | 'hrv_rmssd'
  | 'oxygen_saturation'
  | 'respiratory_rate'
  | 'sleep_stage_deep'
  | 'sleep_stage_rem'
  | 'sleep_stage_light'
  | 'sleep_stage_awake'
  | 'sleep_duration'
  | 'stress'
  | 'pai'
  | 'weight'
  | 'hydration'
  | 'caffeine';

export interface MetricDefinition {
  canonicalKey: HealthMetricType;
  displayName: string;
  category: string;
  canonicalUnit: string;
  semantics: 'spot' | 'interval_delta' | 'cumulative_daily' | 'session_stage';
  aggregationRule: 'sum' | 'mean' | 'latest' | 'min' | 'max_of_cumulative';
  attributionWindow: 'calendar_day' | 'sleep_window';
  aliases: string[];
}

export const METRIC_REGISTRY: Record<HealthMetricType, MetricDefinition> = {
  'steps': {
    canonicalKey: 'steps',
    displayName: "Steps",
    category: "activity",
    canonicalUnit: "count",
    semantics: "interval_delta",
    aggregationRule: "sum",
    attributionWindow: "calendar_day",
    aliases: ["Steps","step_count","HKQuantityTypeIdentifierStepCount"]
  },
  'active_energy': {
    canonicalKey: 'active_energy',
    displayName: "Active Calories",
    category: "activity",
    canonicalUnit: "kcal",
    semantics: "interval_delta",
    aggregationRule: "sum",
    attributionWindow: "calendar_day",
    aliases: ["ActiveEnergy","active_calories","calorie","calories","HKQuantityTypeIdentifierActiveEnergyBurned"]
  },
  'basal_energy': {
    canonicalKey: 'basal_energy',
    displayName: "Resting Calories",
    category: "activity",
    canonicalUnit: "kcal",
    semantics: "interval_delta",
    aggregationRule: "sum",
    attributionWindow: "calendar_day",
    aliases: ["BasalEnergyBurned","basal_calories","resting_energy","HKQuantityTypeIdentifierBasalEnergyBurned"]
  },
  'distance': {
    canonicalKey: 'distance',
    displayName: "Distance",
    category: "activity",
    canonicalUnit: "m",
    semantics: "interval_delta",
    aggregationRule: "sum",
    attributionWindow: "calendar_day",
    aliases: ["Distance","distance_walking_running","HKQuantityTypeIdentifierDistanceWalkingRunning"]
  },
  'floors_climbed': {
    canonicalKey: 'floors_climbed',
    displayName: "Floors Climbed",
    category: "activity",
    canonicalUnit: "count",
    semantics: "interval_delta",
    aggregationRule: "sum",
    attributionWindow: "calendar_day",
    aliases: ["FloorsClimbed","flights_climbed","HKQuantityTypeIdentifierFlightsClimbed"]
  },
  'walking_speed': {
    canonicalKey: 'walking_speed',
    displayName: "Walking Speed",
    category: "activity",
    canonicalUnit: "m/s",
    semantics: "spot",
    aggregationRule: "mean",
    attributionWindow: "calendar_day",
    aliases: ["WalkingSpeed","HKQuantityTypeIdentifierWalkingSpeed"]
  },
  'heart_rate': {
    canonicalKey: 'heart_rate',
    displayName: "Heart Rate",
    category: "cardiac",
    canonicalUnit: "bpm",
    semantics: "spot",
    aggregationRule: "mean",
    attributionWindow: "calendar_day",
    aliases: ["HeartRate","hr","pulse","HKQuantityTypeIdentifierHeartRate"]
  },
  'resting_heart_rate': {
    canonicalKey: 'resting_heart_rate',
    displayName: "Resting Heart Rate",
    category: "cardiac",
    canonicalUnit: "bpm",
    semantics: "spot",
    aggregationRule: "latest",
    attributionWindow: "calendar_day",
    aliases: ["RestingHeartRate","rhr","HKQuantityTypeIdentifierRestingHeartRate"]
  },
  'hrv_sdnn': {
    canonicalKey: 'hrv_sdnn',
    displayName: "Heart Rate Variability (SDNN)",
    category: "cardiac",
    canonicalUnit: "ms",
    semantics: "spot",
    aggregationRule: "mean",
    attributionWindow: "calendar_day",
    aliases: ["HeartRateVariabilitySDNN","hrv","hrv_sdnn","HKQuantityTypeIdentifierHeartRateVariabilitySDNN"]
  },
  'hrv_rmssd': {
    canonicalKey: 'hrv_rmssd',
    displayName: "Heart Rate Variability (RMSSD)",
    category: "cardiac",
    canonicalUnit: "ms",
    semantics: "spot",
    aggregationRule: "mean",
    attributionWindow: "calendar_day",
    aliases: ["hrv_rmssd","RMSSD","HeartRateVariabilityRmssdRecord"]
  },
  'oxygen_saturation': {
    canonicalKey: 'oxygen_saturation',
    displayName: "Blood Oxygen (SpO2)",
    category: "respiratory",
    canonicalUnit: "percent",
    semantics: "spot",
    aggregationRule: "mean",
    attributionWindow: "calendar_day",
    aliases: ["OxygenSaturation","spo2","blood_oxygen","bo","HKQuantityTypeIdentifierOxygenSaturation"]
  },
  'respiratory_rate': {
    canonicalKey: 'respiratory_rate',
    displayName: "Respiratory Rate",
    category: "respiratory",
    canonicalUnit: "count/min",
    semantics: "spot",
    aggregationRule: "mean",
    attributionWindow: "calendar_day",
    aliases: ["RespiratoryRate","breathing_rate","HKQuantityTypeIdentifierRespiratoryRate"]
  },
  'sleep_stage_deep': {
    canonicalKey: 'sleep_stage_deep',
    displayName: "Deep Sleep",
    category: "sleep",
    canonicalUnit: "seconds",
    semantics: "session_stage",
    aggregationRule: "sum",
    attributionWindow: "sleep_window",
    aliases: ["SleepDeep","sleep_deep","deep_sleep","HKCategoryValueSleepAnalysisAsleepDeep"]
  },
  'sleep_stage_rem': {
    canonicalKey: 'sleep_stage_rem',
    displayName: "REM Sleep",
    category: "sleep",
    canonicalUnit: "seconds",
    semantics: "session_stage",
    aggregationRule: "sum",
    attributionWindow: "sleep_window",
    aliases: ["SleepREM","sleep_rem","rem_sleep","HKCategoryValueSleepAnalysisAsleepREM"]
  },
  'sleep_stage_light': {
    canonicalKey: 'sleep_stage_light',
    displayName: "Light / Core Sleep",
    category: "sleep",
    canonicalUnit: "seconds",
    semantics: "session_stage",
    aggregationRule: "sum",
    attributionWindow: "sleep_window",
    aliases: ["SleepLight","sleep_light","light_sleep","core_sleep","HKCategoryValueSleepAnalysisAsleepCore"]
  },
  'sleep_stage_awake': {
    canonicalKey: 'sleep_stage_awake',
    displayName: "Awake During Night",
    category: "sleep",
    canonicalUnit: "seconds",
    semantics: "session_stage",
    aggregationRule: "sum",
    attributionWindow: "sleep_window",
    aliases: ["SleepAwake","sleep_awake","awake","HKCategoryValueSleepAnalysisAwake"]
  },
  'sleep_duration': {
    canonicalKey: 'sleep_duration',
    displayName: "Total Sleep Duration",
    category: "sleep",
    canonicalUnit: "seconds",
    semantics: "session_stage",
    aggregationRule: "sum",
    attributionWindow: "sleep_window",
    aliases: ["SleepDuration","sleep","total_sleep","HKCategoryValueSleepAnalysisAsleepUnspecified"]
  },
  'stress': {
    canonicalKey: 'stress',
    displayName: "Stress Score",
    category: "stress",
    canonicalUnit: "score_100",
    semantics: "spot",
    aggregationRule: "mean",
    attributionWindow: "calendar_day",
    aliases: ["Stress","stress_score","autonomic_stress"]
  },
  'pai': {
    canonicalKey: 'pai',
    displayName: "PAI (Personal Activity Intelligence)",
    category: "activity",
    canonicalUnit: "score",
    semantics: "spot",
    aggregationRule: "latest",
    attributionWindow: "calendar_day",
    aliases: ["PAI","pai_score"]
  },
  'weight': {
    canonicalKey: 'weight',
    displayName: "Body Weight",
    category: "body",
    canonicalUnit: "kg",
    semantics: "spot",
    aggregationRule: "latest",
    attributionWindow: "calendar_day",
    aliases: ["Weight","body_mass","HKQuantityTypeIdentifierBodyMass"]
  },
  'hydration': {
    canonicalKey: 'hydration',
    displayName: "Water Intake",
    category: "nutrition",
    canonicalUnit: "ml",
    semantics: "interval_delta",
    aggregationRule: "sum",
    attributionWindow: "calendar_day",
    aliases: ["Hydration","water","water_intake","dietary_water","HKQuantityTypeIdentifierDietaryWater"]
  },
  'caffeine': {
    canonicalKey: 'caffeine',
    displayName: "Caffeine Intake",
    category: "nutrition",
    canonicalUnit: "mg",
    semantics: "interval_delta",
    aggregationRule: "sum",
    attributionWindow: "calendar_day",
    aliases: ["Caffeine","caffeine_intake","dietary_caffeine","HKQuantityTypeIdentifierDietaryCaffeine"]
  }
};

export const ALIAS_TO_CANONICAL: Record<string, HealthMetricType> = {
  "steps": 'steps',
  "Steps": 'steps',
  "step_count": 'steps',
  "HKQuantityTypeIdentifierStepCount": 'steps',
  "active_energy": 'active_energy',
  "ActiveEnergy": 'active_energy',
  "active_calories": 'active_energy',
  "calorie": 'active_energy',
  "calories": 'active_energy',
  "HKQuantityTypeIdentifierActiveEnergyBurned": 'active_energy',
  "basal_energy": 'basal_energy',
  "BasalEnergyBurned": 'basal_energy',
  "basal_calories": 'basal_energy',
  "resting_energy": 'basal_energy',
  "HKQuantityTypeIdentifierBasalEnergyBurned": 'basal_energy',
  "distance": 'distance',
  "Distance": 'distance',
  "distance_walking_running": 'distance',
  "HKQuantityTypeIdentifierDistanceWalkingRunning": 'distance',
  "floors_climbed": 'floors_climbed',
  "FloorsClimbed": 'floors_climbed',
  "flights_climbed": 'floors_climbed',
  "HKQuantityTypeIdentifierFlightsClimbed": 'floors_climbed',
  "walking_speed": 'walking_speed',
  "WalkingSpeed": 'walking_speed',
  "HKQuantityTypeIdentifierWalkingSpeed": 'walking_speed',
  "heart_rate": 'heart_rate',
  "HeartRate": 'heart_rate',
  "hr": 'heart_rate',
  "pulse": 'heart_rate',
  "HKQuantityTypeIdentifierHeartRate": 'heart_rate',
  "resting_heart_rate": 'resting_heart_rate',
  "RestingHeartRate": 'resting_heart_rate',
  "rhr": 'resting_heart_rate',
  "HKQuantityTypeIdentifierRestingHeartRate": 'resting_heart_rate',
  "hrv_sdnn": 'hrv_sdnn',
  "HeartRateVariabilitySDNN": 'hrv_sdnn',
  "hrv": 'hrv_sdnn',
  "HKQuantityTypeIdentifierHeartRateVariabilitySDNN": 'hrv_sdnn',
  "hrv_rmssd": 'hrv_rmssd',
  "RMSSD": 'hrv_rmssd',
  "HeartRateVariabilityRmssdRecord": 'hrv_rmssd',
  "oxygen_saturation": 'oxygen_saturation',
  "OxygenSaturation": 'oxygen_saturation',
  "spo2": 'oxygen_saturation',
  "blood_oxygen": 'oxygen_saturation',
  "bo": 'oxygen_saturation',
  "HKQuantityTypeIdentifierOxygenSaturation": 'oxygen_saturation',
  "respiratory_rate": 'respiratory_rate',
  "RespiratoryRate": 'respiratory_rate',
  "breathing_rate": 'respiratory_rate',
  "HKQuantityTypeIdentifierRespiratoryRate": 'respiratory_rate',
  "sleep_stage_deep": 'sleep_stage_deep',
  "SleepDeep": 'sleep_stage_deep',
  "sleep_deep": 'sleep_stage_deep',
  "deep_sleep": 'sleep_stage_deep',
  "HKCategoryValueSleepAnalysisAsleepDeep": 'sleep_stage_deep',
  "sleep_stage_rem": 'sleep_stage_rem',
  "SleepREM": 'sleep_stage_rem',
  "sleep_rem": 'sleep_stage_rem',
  "rem_sleep": 'sleep_stage_rem',
  "HKCategoryValueSleepAnalysisAsleepREM": 'sleep_stage_rem',
  "sleep_stage_light": 'sleep_stage_light',
  "SleepLight": 'sleep_stage_light',
  "sleep_light": 'sleep_stage_light',
  "light_sleep": 'sleep_stage_light',
  "core_sleep": 'sleep_stage_light',
  "HKCategoryValueSleepAnalysisAsleepCore": 'sleep_stage_light',
  "sleep_stage_awake": 'sleep_stage_awake',
  "SleepAwake": 'sleep_stage_awake',
  "sleep_awake": 'sleep_stage_awake',
  "awake": 'sleep_stage_awake',
  "HKCategoryValueSleepAnalysisAwake": 'sleep_stage_awake',
  "sleep_duration": 'sleep_duration',
  "SleepDuration": 'sleep_duration',
  "sleep": 'sleep_duration',
  "total_sleep": 'sleep_duration',
  "HKCategoryValueSleepAnalysisAsleepUnspecified": 'sleep_duration',
  "stress": 'stress',
  "Stress": 'stress',
  "stress_score": 'stress',
  "autonomic_stress": 'stress',
  "pai": 'pai',
  "PAI": 'pai',
  "pai_score": 'pai',
  "weight": 'weight',
  "Weight": 'weight',
  "body_mass": 'weight',
  "HKQuantityTypeIdentifierBodyMass": 'weight',
  "hydration": 'hydration',
  "Hydration": 'hydration',
  "water": 'hydration',
  "water_intake": 'hydration',
  "dietary_water": 'hydration',
  "HKQuantityTypeIdentifierDietaryWater": 'hydration',
  "caffeine": 'caffeine',
  "Caffeine": 'caffeine',
  "caffeine_intake": 'caffeine',
  "dietary_caffeine": 'caffeine',
  "HKQuantityTypeIdentifierDietaryCaffeine": 'caffeine'
};

export function normalizeMetricType(raw: string): HealthMetricType | null {
  return ALIAS_TO_CANONICAL[raw] || null;
}
