// AUTO-GENERATED from HealthSpec/metric_registry.json - DO NOT EDIT MANUALLY
// Generated at: 2026-10-05T13:51:30.207Z

package com.intellidream.daily.model

enum class CanonicalHealthMetric(
    val key: String,
    val displayName: String,
    val canonicalUnit: String,
    val semantics: String,
    val aggregationRule: String
) {
    STEPS("steps", "Steps", "count", "interval_delta", "sum"),
    ACTIVEENERGY("active_energy", "Active Calories", "kcal", "interval_delta", "sum"),
    BASALENERGY("basal_energy", "Resting Calories", "kcal", "interval_delta", "sum"),
    DISTANCE("distance", "Distance", "m", "interval_delta", "sum"),
    FLOORSCLIMBED("floors_climbed", "Floors Climbed", "count", "interval_delta", "sum"),
    WALKINGSPEED("walking_speed", "Walking Speed", "m/s", "spot", "mean"),
    HEARTRATE("heart_rate", "Heart Rate", "bpm", "spot", "mean"),
    RESTINGHEARTRATE("resting_heart_rate", "Resting Heart Rate", "bpm", "spot", "latest"),
    HRVSDNN("hrv_sdnn", "Heart Rate Variability (SDNN)", "ms", "spot", "mean"),
    HRVRMSSD("hrv_rmssd", "Heart Rate Variability (RMSSD)", "ms", "spot", "mean"),
    OXYGENSATURATION("oxygen_saturation", "Blood Oxygen (SpO2)", "percent", "spot", "mean"),
    RESPIRATORYRATE("respiratory_rate", "Respiratory Rate", "count/min", "spot", "mean"),
    SLEEPSTAGEDEEP("sleep_stage_deep", "Deep Sleep", "seconds", "session_stage", "sum"),
    SLEEPSTAGEREM("sleep_stage_rem", "REM Sleep", "seconds", "session_stage", "sum"),
    SLEEPSTAGELIGHT("sleep_stage_light", "Light / Core Sleep", "seconds", "session_stage", "sum"),
    SLEEPSTAGEAWAKE("sleep_stage_awake", "Awake During Night", "seconds", "session_stage", "sum"),
    SLEEPDURATION("sleep_duration", "Total Sleep Duration", "seconds", "session_stage", "sum"),
    STRESS("stress", "Stress Score", "score_100", "spot", "mean"),
    PAI("pai", "PAI (Personal Activity Intelligence)", "score", "spot", "latest"),
    WEIGHT("weight", "Body Weight", "kg", "spot", "latest"),
    HYDRATION("hydration", "Water Intake", "ml", "interval_delta", "sum"),
    CAFFEINE("caffeine", "Caffeine Intake", "mg", "interval_delta", "sum");

    companion object {
        private val aliasMap: Map<String, CanonicalHealthMetric> = buildMap {
            put("steps", STEPS)
            put("Steps", STEPS)
            put("step_count", STEPS)
            put("HKQuantityTypeIdentifierStepCount", STEPS)
            put("active_energy", ACTIVEENERGY)
            put("ActiveEnergy", ACTIVEENERGY)
            put("active_calories", ACTIVEENERGY)
            put("calorie", ACTIVEENERGY)
            put("calories", ACTIVEENERGY)
            put("HKQuantityTypeIdentifierActiveEnergyBurned", ACTIVEENERGY)
            put("basal_energy", BASALENERGY)
            put("BasalEnergyBurned", BASALENERGY)
            put("basal_calories", BASALENERGY)
            put("resting_energy", BASALENERGY)
            put("HKQuantityTypeIdentifierBasalEnergyBurned", BASALENERGY)
            put("distance", DISTANCE)
            put("Distance", DISTANCE)
            put("distance_walking_running", DISTANCE)
            put("HKQuantityTypeIdentifierDistanceWalkingRunning", DISTANCE)
            put("floors_climbed", FLOORSCLIMBED)
            put("FloorsClimbed", FLOORSCLIMBED)
            put("flights_climbed", FLOORSCLIMBED)
            put("HKQuantityTypeIdentifierFlightsClimbed", FLOORSCLIMBED)
            put("walking_speed", WALKINGSPEED)
            put("WalkingSpeed", WALKINGSPEED)
            put("HKQuantityTypeIdentifierWalkingSpeed", WALKINGSPEED)
            put("heart_rate", HEARTRATE)
            put("HeartRate", HEARTRATE)
            put("hr", HEARTRATE)
            put("pulse", HEARTRATE)
            put("HKQuantityTypeIdentifierHeartRate", HEARTRATE)
            put("resting_heart_rate", RESTINGHEARTRATE)
            put("RestingHeartRate", RESTINGHEARTRATE)
            put("rhr", RESTINGHEARTRATE)
            put("HKQuantityTypeIdentifierRestingHeartRate", RESTINGHEARTRATE)
            put("hrv_sdnn", HRVSDNN)
            put("HeartRateVariabilitySDNN", HRVSDNN)
            put("hrv", HRVSDNN)
            put("HKQuantityTypeIdentifierHeartRateVariabilitySDNN", HRVSDNN)
            put("hrv_rmssd", HRVRMSSD)
            put("RMSSD", HRVRMSSD)
            put("HeartRateVariabilityRmssdRecord", HRVRMSSD)
            put("oxygen_saturation", OXYGENSATURATION)
            put("OxygenSaturation", OXYGENSATURATION)
            put("spo2", OXYGENSATURATION)
            put("blood_oxygen", OXYGENSATURATION)
            put("bo", OXYGENSATURATION)
            put("HKQuantityTypeIdentifierOxygenSaturation", OXYGENSATURATION)
            put("respiratory_rate", RESPIRATORYRATE)
            put("RespiratoryRate", RESPIRATORYRATE)
            put("breathing_rate", RESPIRATORYRATE)
            put("HKQuantityTypeIdentifierRespiratoryRate", RESPIRATORYRATE)
            put("sleep_stage_deep", SLEEPSTAGEDEEP)
            put("SleepDeep", SLEEPSTAGEDEEP)
            put("sleep_deep", SLEEPSTAGEDEEP)
            put("deep_sleep", SLEEPSTAGEDEEP)
            put("HKCategoryValueSleepAnalysisAsleepDeep", SLEEPSTAGEDEEP)
            put("sleep_stage_rem", SLEEPSTAGEREM)
            put("SleepREM", SLEEPSTAGEREM)
            put("sleep_rem", SLEEPSTAGEREM)
            put("rem_sleep", SLEEPSTAGEREM)
            put("HKCategoryValueSleepAnalysisAsleepREM", SLEEPSTAGEREM)
            put("sleep_stage_light", SLEEPSTAGELIGHT)
            put("SleepLight", SLEEPSTAGELIGHT)
            put("sleep_light", SLEEPSTAGELIGHT)
            put("light_sleep", SLEEPSTAGELIGHT)
            put("core_sleep", SLEEPSTAGELIGHT)
            put("HKCategoryValueSleepAnalysisAsleepCore", SLEEPSTAGELIGHT)
            put("sleep_stage_awake", SLEEPSTAGEAWAKE)
            put("SleepAwake", SLEEPSTAGEAWAKE)
            put("sleep_awake", SLEEPSTAGEAWAKE)
            put("awake", SLEEPSTAGEAWAKE)
            put("HKCategoryValueSleepAnalysisAwake", SLEEPSTAGEAWAKE)
            put("sleep_duration", SLEEPDURATION)
            put("SleepDuration", SLEEPDURATION)
            put("sleep", SLEEPDURATION)
            put("total_sleep", SLEEPDURATION)
            put("HKCategoryValueSleepAnalysisAsleepUnspecified", SLEEPDURATION)
            put("stress", STRESS)
            put("Stress", STRESS)
            put("stress_score", STRESS)
            put("autonomic_stress", STRESS)
            put("pai", PAI)
            put("PAI", PAI)
            put("pai_score", PAI)
            put("weight", WEIGHT)
            put("Weight", WEIGHT)
            put("body_mass", WEIGHT)
            put("HKQuantityTypeIdentifierBodyMass", WEIGHT)
            put("hydration", HYDRATION)
            put("Hydration", HYDRATION)
            put("water", HYDRATION)
            put("water_intake", HYDRATION)
            put("dietary_water", HYDRATION)
            put("HKQuantityTypeIdentifierDietaryWater", HYDRATION)
            put("caffeine", CAFFEINE)
            put("Caffeine", CAFFEINE)
            put("caffeine_intake", CAFFEINE)
            put("dietary_caffeine", CAFFEINE)
            put("HKQuantityTypeIdentifierDietaryCaffeine", CAFFEINE)
        }

        fun fromAlias(raw: String): CanonicalHealthMetric? = aliasMap[raw]
    }
}
