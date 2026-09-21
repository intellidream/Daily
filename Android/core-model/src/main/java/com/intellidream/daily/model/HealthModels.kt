package com.intellidream.daily.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

// MARK: - Health Sub Tabs

enum class HealthSubTab(val displayName: String) {
    OVERVIEW("Overview"),
    SLEEP("Sleep Studio"),
    VITALS("Heart & Vitals"),
    TRENDS("Trends")
}

// MARK: - Health Metric Types

@Serializable
enum class HealthMetricType(val rawKey: String, val displayName: String, val defaultUnit: String) {
    // Activity
    @SerialName("steps") STEPS("steps", "Steps", "count"),
    @SerialName("active_energy") ACTIVE_ENERGY("active_energy", "Active Calories", "kcal"),
    @SerialName("basal_energy") BASAL_ENERGY("basal_energy", "Resting Energy", "kcal"),
    @SerialName("distance") DISTANCE("distance", "Distance", "km"),
    @SerialName("floors_climbed") FLOORS_CLIMBED("floors_climbed", "Floors Climbed", "count"),
    @SerialName("walking_speed") WALKING_SPEED("walking_speed", "Walking Speed", "km/h"),
    @SerialName("running_speed") RUNNING_SPEED("running_speed", "Running Speed", "km/h"),
    @SerialName("cycling_power") CYCLING_POWER("cycling_power", "Cycling Power", "W"),
    @SerialName("cycling_cadence") CYCLING_CADENCE("cycling_cadence", "Cycling Cadence", "rpm"),
    @SerialName("workout_duration") WORKOUT_DURATION("workout_duration", "Workout Duration", "min"),

    // Cardiovascular & Vitals
    @SerialName("heart_rate") HEART_RATE("heart_rate", "Heart Rate", "bpm"),
    @SerialName("resting_heart_rate") RESTING_HEART_RATE("resting_heart_rate", "Resting HR", "bpm"),
    @SerialName("hrv_sdnn") HRV_SDNN("hrv_sdnn", "HRV (SDNN)", "ms"),
    @SerialName("hrv_rmssd") HRV_RMSSD("hrv_rmssd", "HRV (RMSSD)", "ms"),
    @SerialName("respiratory_rate") RESPIRATORY_RATE("respiratory_rate", "Respiratory Rate", "br/min"),
    @SerialName("oxygen_saturation") OXYGEN_SATURATION("oxygen_saturation", "Blood Oxygen (SpO2)", "%"),
    @SerialName("blood_pressure_systolic") BLOOD_PRESSURE_SYSTOLIC("blood_pressure_systolic", "Systolic BP", "mmHg"),
    @SerialName("blood_pressure_diastolic") BLOOD_PRESSURE_DIASTOLIC("blood_pressure_diastolic", "Diastolic BP", "mmHg"),
    @SerialName("blood_glucose") BLOOD_GLUCOSE("blood_glucose", "Blood Glucose", "mg/dL"),
    @SerialName("body_temperature") BODY_TEMPERATURE("body_temperature", "Body Temperature", "°C"),

    // Sleep
    @SerialName("sleep_duration") SLEEP_DURATION("sleep_duration", "Sleep Duration", "min"),
    @SerialName("sleep_deep") SLEEP_DEEP("sleep_deep", "Deep Sleep", "min"),
    @SerialName("sleep_rem") SLEEP_REM("sleep_rem", "REM Sleep", "min"),
    @SerialName("sleep_light") SLEEP_LIGHT("sleep_light", "Light Sleep", "min"),
    @SerialName("sleep_awake") SLEEP_AWAKE("sleep_awake", "Awake Time", "min"),
    @SerialName("nap_duration") NAP_DURATION("nap_duration", "Daytime Naps", "min"),

    // Body Composition
    @SerialName("weight") WEIGHT("weight", "Weight", "kg"),
    @SerialName("body_fat_percentage") BODY_FAT_PERCENTAGE("body_fat_percentage", "Body Fat", "%"),
    @SerialName("lean_body_mass") LEAN_BODY_MASS("lean_body_mass", "Lean Mass", "kg"),
    @SerialName("height") HEIGHT("height", "Height", "cm"),
    @SerialName("bmi") BMI("bmi", "BMI", "kg/m²"),
    @SerialName("bone_mass") BONE_MASS("bone_mass", "Bone Mass", "kg"),

    // Wellness & Lifestyle
    @SerialName("hydration") HYDRATION("hydration", "Hydration", "ml"),
    @SerialName("mindful_session") MINDFUL_SESSION("mindful_session", "Mindfulness", "min"),
    @SerialName("stress") STRESS("stress", "Stress Score", "pts"),
    @SerialName("pai") PAI("pai", "PAI Score", "pts");

    companion object {
        fun from(rawString: String): HealthMetricType? {
            val norm = rawString.trim().lowercase()
                .replace("_", "")
                .replace(" ", "")
                .replace("-", "")

            return when (norm) {
                "steps", "stepcount" -> STEPS
                "activeenergy", "activecalories", "calories", "energy" -> ACTIVE_ENERGY
                "basalenergy", "basalenergyburned", "restingenergy", "restingcalories" -> BASAL_ENERGY
                "distance", "distancewalkingrunning" -> DISTANCE
                "floorsclimbed", "flightsclimbed", "floors" -> FLOORS_CLIMBED
                "walkingspeed" -> WALKING_SPEED
                "runningspeed" -> RUNNING_SPEED
                "cyclingpower" -> CYCLING_POWER
                "cyclingcadence" -> CYCLING_CADENCE
                "workoutduration" -> WORKOUT_DURATION
                "heartrate", "hr" -> HEART_RATE
                "restingheartrate", "rhr" -> RESTING_HEART_RATE
                "hrv", "hrvsdnn", "heartratevariabilitysdnn", "heartratevariability" -> HRV_SDNN
                "hrvrmssd", "heartratevariabilityrmssd" -> HRV_RMSSD
                "respiratoryrate", "resp", "respiration" -> RESPIRATORY_RATE
                "oxygensaturation", "spo2", "bloodoxygen" -> OXYGEN_SATURATION
                "bloodpressuresystolic", "systolic" -> BLOOD_PRESSURE_SYSTOLIC
                "bloodpressurediastolic", "diastolic" -> BLOOD_PRESSURE_DIASTOLIC
                "bloodglucose", "glucose" -> BLOOD_GLUCOSE
                "bodytemperature", "temperature", "temp" -> BODY_TEMPERATURE
                "sleepduration", "sleep" -> SLEEP_DURATION
                "sleepdeep", "sleepstagedeep" -> SLEEP_DEEP
                "sleeprem", "sleepstagerem" -> SLEEP_REM
                "sleeplight", "sleepcore", "sleepstagelight", "sleepstagecore" -> SLEEP_LIGHT
                "sleepawake", "sleepstageawake" -> SLEEP_AWAKE
                "napduration", "sleepnap", "nap" -> NAP_DURATION
                "weight", "bodymass" -> WEIGHT
                "bodyfatpercentage", "bodyfat" -> BODY_FAT_PERCENTAGE
                "leanbodymass", "leanmass" -> LEAN_BODY_MASS
                "height" -> HEIGHT
                "bmi", "bodymassindex" -> BMI
                "bonemass" -> BONE_MASS
                "hydration", "water", "dietarywater" -> HYDRATION
                "mindfulsession", "mindfulness" -> MINDFUL_SESSION
                "stress" -> STRESS
                "pai" -> PAI
                else -> null
            }
        }
    }
}

// MARK: - Supabase Raw Telemetry Record

@Serializable
data class HealthTelemetryRecord(
    val id: String = UUID.randomUUID().toString(),
    @SerialName("user_id") val userId: String = "local_user",
    val type: String,
    val value: Double? = null,
    val unit: String? = null,
    @SerialName("start_time") val startTime: Long, // Epoch ms
    @SerialName("end_time") val endTime: Long? = null, // Epoch ms
    @SerialName("source_device") val sourceDevice: String? = null,
    @SerialName("created_at") val createdAt: Long? = null
) {
    val normalizedType: String
        get() = type.trim().lowercase().replace("_", "").replace(" ", "")

    val isHeartRate: Boolean
        get() = normalizedType == "heartrate" || normalizedType == "hr"

    val isSteps: Boolean
        get() = normalizedType == "steps" || normalizedType == "stepcount"

    val isSleep: Boolean
        get() = normalizedType.startsWith("sleep")

    val isSleepStage: Boolean
        get() = normalizedType.startsWith("sleepstage") ||
                normalizedType == "sleepdeep" ||
                normalizedType == "sleeprem" ||
                normalizedType == "sleeplight" ||
                normalizedType == "sleepcore" ||
                normalizedType == "sleepawake"

    val isNap: Boolean
        get() = normalizedType == "sleepnap" || normalizedType == "nap"

    val durationSeconds: Double
        get() {
            if (value != null && value > 0) {
                val u = unit?.trim()?.lowercase() ?: ""
                if (u in listOf("hours", "hour", "h", "hr")) return value * 3600.0
                if (u in listOf("minutes", "minute", "min", "m")) return value * 60.0
                if (u in listOf("seconds", "sec", "s")) return value
            }
            if (endTime != null && endTime > startTime) {
                return (endTime - startTime) / 1000.0
            }
            return 0.0
        }

    val effectiveEndTime: Long
        get() {
            if (durationSeconds > 0) {
                return startTime + (durationSeconds * 1000).toLong()
            }
            if (endTime != null && endTime > startTime) {
                return endTime
            }
            return startTime
        }

    val sleepStageType: SleepStageType
        get() {
            val norm = normalizedType
            return when {
                norm.contains("deep") -> SleepStageType.DEEP
                norm.contains("rem") -> SleepStageType.REM
                norm.contains("awake") || norm.contains("wake") -> SleepStageType.AWAKE
                norm.contains("light") || norm.contains("core") -> SleepStageType.LIGHT
                else -> SleepStageType.UNKNOWN
            }
        }
}

// MARK: - Supabase Daily Vital Metric Record

@Serializable
data class VitalMetricRecord(
    val id: String = UUID.randomUUID().toString(),
    @SerialName("user_id") val userId: String = "local_user",
    val type: String,
    val value: Double,
    val unit: String? = null,
    val date: String, // ISO date "yyyy-MM-dd"
    @SerialName("source_device") val sourceDevice: String? = null,
    @SerialName("created_at") val createdAt: Long? = null,
    @SerialName("updated_at") val updatedAt: Long? = null,
    @SerialName("synced_at") val syncedAt: Long? = null
) {
    val metricType: HealthMetricType?
        get() = HealthMetricType.from(type)
}

// MARK: - Sleep Stages & Sessions

@Serializable
enum class SleepStageType(val rawValue: String, val hexColor: String, val sortOrder: Int) {
    @SerialName("Awake") AWAKE("Awake", "#FF7043", 0), // Coral Orange
    @SerialName("REM") REM("REM", "#26C6DA", 1),       // Cyan Glow
    @SerialName("Light") LIGHT("Light", "#42A5F5", 2), // Sky Blue
    @SerialName("Deep") DEEP("Deep", "#3949AB", 3),    // Indigo Midnight
    @SerialName("Unknown") UNKNOWN("Unknown", "#78909C", 4) // Muted Slate
}

@Serializable
data class SleepStageRecord(
    val id: String = UUID.randomUUID().toString(),
    val stageType: SleepStageType,
    val startTime: Long, // Epoch ms
    val endTime: Long,   // Epoch ms
    val durationSeconds: Double = max(0.0, (endTime - startTime) / 1000.0),
    val sourceDevice: String? = null
) {
    val durationMinutes: Double
        get() = durationSeconds / 60.0
}

@Serializable
data class SleepSession(
    val id: String = UUID.randomUUID().toString(),
    val startTime: Long,
    val endTime: Long,
    val isNap: Boolean = false,
    val stages: List<SleepStageRecord> = emptyList(),
    val sourceDevice: String = "Unknown",
    val hasGranularHypnogram: Boolean = false
) {
    val deepSeconds: Double
        get() = stages.filter { it.stageType == SleepStageType.DEEP }.sumOf { it.durationSeconds }

    val remSeconds: Double
        get() = stages.filter { it.stageType == SleepStageType.REM }.sumOf { it.durationSeconds }

    val lightSeconds: Double
        get() = stages.filter { it.stageType == SleepStageType.LIGHT }.sumOf { it.durationSeconds }

    val awakeSeconds: Double
        get() = stages.filter { it.stageType == SleepStageType.AWAKE }.sumOf { it.durationSeconds }

    val asleepSeconds: Double
        get() {
            val asleepStages = deepSeconds + remSeconds + lightSeconds
            if (asleepStages > 0) return asleepStages
            return max(0.0, durationSeconds - awakeSeconds)
        }

    val durationSeconds: Double
        get() {
            val totalStages = deepSeconds + remSeconds + lightSeconds + awakeSeconds
            val span = max(0.0, (endTime - startTime) / 1000.0)
            if (totalStages > 0 && span > totalStages * 1.35) {
                return totalStages
            }
            return max(span, totalStages)
        }

    val awakeCount: Int
        get() = stages.count { it.stageType == SleepStageType.AWAKE }

    val deepPercent: Int
        get() = if (asleepSeconds > 0) ((deepSeconds / asleepSeconds) * 100).roundToInt() else 0

    val remPercent: Int
        get() = if (asleepSeconds > 0) ((remSeconds / asleepSeconds) * 100).roundToInt() else 0

    val lightPercent: Int
        get() = if (asleepSeconds > 0) ((lightSeconds / asleepSeconds) * 100).roundToInt() else 0

    val awakePercent: Int
        get() = if (durationSeconds > 0) ((awakeSeconds / durationSeconds) * 100).roundToInt() else 0

    val restorativePercent: Int
        get() = deepPercent + remPercent

    val efficiencyPercent: Int
        get() {
            if (durationSeconds <= 0) return 85
            val raw = ((asleepSeconds / durationSeconds) * 100).roundToInt()
            return min(max(raw, 10), 100)
        }

    val sleepScore: Int
        get() {
            if (asleepSeconds <= 0) return 0
            val asleepHours = asleepSeconds / 3600.0

            // 1. Duration score (max 40 pts, benchmark 7.5h - 9.0h)
            val durationScore = when {
                asleepHours in 7.5..9.0 -> 38.0 + min((asleepHours - 7.5) / 1.5 * 2.0, 2.0)
                asleepHours > 9.0 -> max(34.0, 40.0 - (asleepHours - 9.0) * 2.0)
                asleepHours >= 7.0 -> 34.0 + (asleepHours - 7.0) / 0.5 * 4.0
                asleepHours >= 6.0 -> 24.0 + (asleepHours - 6.0) * 10.0
                asleepHours >= 5.0 -> 14.0 + (asleepHours - 5.0) * 10.0
                else -> max(0.0, (asleepHours / 5.0) * 14.0)
            }

            // 2. Efficiency score (max 25 pts, clinical baseline >= 88%)
            val eff = efficiencyPercent.toDouble()
            val effScore = when {
                eff >= 95.0 -> 25.0
                eff >= 90.0 -> 21.0 + ((eff - 90.0) / 5.0) * 4.0
                eff >= 85.0 -> 16.0 + ((eff - 85.0) / 5.0) * 5.0
                eff >= 80.0 -> 10.0 + ((eff - 80.0) / 5.0) * 6.0
                else -> max(0.0, (eff / 80.0) * 10.0)
            }

            // 3. Restorative Architecture (max 25 pts: Deep up to 13, REM up to 12)
            val dp = deepPercent.toDouble()
            val deepScore = when {
                dp >= 16.0 -> 11.0 + min(((dp - 16.0) / 6.0) * 2.0, 2.0)
                dp >= 10.0 -> 6.0 + ((dp - 10.0) / 6.0) * 5.0
                else -> max(0.0, (dp / 10.0) * 6.0)
            }

            val rp = remPercent.toDouble()
            val remScore = when {
                rp >= 20.0 -> 10.0 + min(((rp - 20.0) / 5.0) * 2.0, 2.0)
                rp >= 14.0 -> 5.0 + ((rp - 14.0) / 6.0) * 5.0
                else -> max(0.0, (rp / 14.0) * 5.0)
            }
            val qualScore = deepScore + remScore

            // 4. Restfulness & Sleep Continuity (max 10 pts)
            val awakeCount = stages.count { it.stageType == SleepStageType.AWAKE }
            val awakeMinutes = awakeSeconds / 60.0

            val awakeCountPenalty = when {
                awakeCount <= 2 -> 0.0
                awakeCount <= 4 -> 1.5
                else -> min(1.5 + (awakeCount - 4) * 0.75, 5.0)
            }

            val awakeDurationPenalty = if (awakeMinutes <= 25.0) {
                0.0
            } else {
                min(((awakeMinutes - 25.0) / 10.0) * 1.0, 5.0)
            }

            val restfulnessScore = max(1.0, 10.0 - awakeCountPenalty - awakeDurationPenalty)

            val total = (durationScore + effScore + qualScore + restfulnessScore).roundToInt()
            return min(max(total, 0), 100)
        }

    val sleepQualityRating: String
        get() = when (sleepScore) {
            in 85..100 -> "Optimal"
            in 75 until 85 -> "Good"
            in 60 until 75 -> "Fair"
            in 1 until 60 -> "Restless"
            else -> "No Data"
        }

    val totalAsleepFormatted: String
        get() = formatTimeSpan(asleepSeconds)

    val timeInBedFormatted: String
        get() = formatTimeSpan(durationSeconds)

    val deepFormatted: String
        get() = formatTimeSpan(deepSeconds)

    val remFormatted: String
        get() = formatTimeSpan(remSeconds)

    val lightFormatted: String
        get() = formatTimeSpan(lightSeconds)

    val awakeFormatted: String
        get() = formatTimeSpan(awakeSeconds)

    val bedtimeFormatted: String
        get() = timeFormatter.format(Date(startTime))

    val wakeTimeFormatted: String
        get() = timeFormatter.format(Date(endTime))

    companion object {
        private val timeFormatter = SimpleDateFormat("HH:mm", Locale.getDefault())

        fun formatTimeSpan(seconds: Double): String {
            if (seconds <= 0) return "--"
            val totalMin = (seconds / 60.0).roundToInt()
            val hours = totalMin / 60
            val mins = totalMin % 60
            return if (hours > 0) "${hours}h ${mins}m" else "${mins}m"
        }
    }
}

@Serializable
data class NapSession(
    val id: String = UUID.randomUUID().toString(),
    val startTime: Long,
    val endTime: Long,
    val durationSeconds: Double = max(0.0, (endTime - startTime) / 1000.0),
    val sourceDevice: String = "Unknown"
) {
    val formattedDuration: String
        get() = SleepSession.formatTimeSpan(durationSeconds)

    val timeRangeFormatted: String
        get() {
            val f = SimpleDateFormat("HH:mm", Locale.getDefault())
            return "${f.format(Date(startTime))} - ${f.format(Date(endTime))}"
        }
}

// MARK: - Cardiovascular & Zones

@Serializable
enum class HeartRateZone(val displayName: String, val bpmRangeText: String, val hexColor: String) {
    RESTING("Resting", "< 100 bpm", "#42A5F5"), // Blue
    FAT_BURN("Fat Burn", "100 - 119 bpm", "#66BB6A"), // Green
    CARDIO("Cardio", "120 - 149 bpm", "#FFA726"), // Orange
    PEAK("Peak", "≥ 150 bpm", "#EF5350"); // Red

    companion object {
        fun zoneFor(bpm: Double): HeartRateZone = when {
            bpm < 100 -> RESTING
            bpm < 120 -> FAT_BURN
            bpm < 150 -> CARDIO
            else -> PEAK
        }
    }
}

@Serializable
data class IntradayHeartRatePoint(
    val id: String = UUID.randomUUID().toString(),
    val timestamp: Long,
    val bpm: Double,
    val zone: HeartRateZone = HeartRateZone.zoneFor(bpm),
    val sourceDevice: String? = null
)

// MARK: - Activity & Trends

@Serializable
data class HourlyStepBucket(
    val id: Int, // 0 - 23 hour of day
    val hour: Int,
    val steps: Int
) {
    val hourFormatted: String
        get() = String.format(Locale.getDefault(), "%02d:00", hour)
}

@Serializable
data class DailyMetricTrendPoint(
    val id: String = UUID.randomUUID().toString(),
    val date: Long,
    val value: Double,
    val target: Double? = null,
    val isCompleteDay: Boolean = true
) {
    val dayName: String
        get() = SimpleDateFormat("EEE", Locale.getDefault()).format(Date(date))

    val shortDateFormatted: String
        get() = SimpleDateFormat("d MMM", Locale.getDefault()).format(Date(date))
}

// MARK: - Device Classification

sealed class DeviceSource(val displayName: String, val identifier: String) {
    object AppleWatch : DeviceSource("Apple Watch", "applewatch")
    object Amazfit : DeviceSource("Amazfit Balance", "amazfit")
    object OnePlus : DeviceSource("OnePlus Watch 3", "oneplus")
    object Huawei : DeviceSource("Huawei Watch GT 5 Pro", "huawei")
    object HealthKit : DeviceSource("Apple Health", "healthkit")
    object HealthConnect : DeviceSource("Health Connect", "healthconnect")
    object Manual : DeviceSource("Manual Entry", "manual")
    data class Other(val name: String) : DeviceSource(name, name)

    companion object {
        fun from(name: String?): DeviceSource {
            val clean = name?.trim() ?: return Other("Unknown")
            if (clean.isEmpty()) return Other("Unknown")
            val lower = clean.lowercase()
            return when {
                lower.contains("healthkit") || lower.contains("apple health") || lower == "ios" -> HealthKit
                lower.contains("apple") || lower.contains("watchos") -> AppleWatch
                lower.contains("zepp") || lower.contains("amazfit") || lower.contains("balance") -> Amazfit
                lower.contains("oneplus") || lower.contains("wearos") -> OnePlus
                lower.contains("huawei") || lower.contains("harmony") || lower.contains("gt5") -> Huawei
                lower.contains("health connect") || lower.contains("healthconnect") || lower == "android" -> HealthConnect
                lower.contains("manual") -> Manual
                else -> Other(clean)
            }
        }
    }
}

// MARK: - Sleep Recovery Status & Guidance

@Serializable
enum class SleepRecoveryStatus(val displayName: String, val hexColor: String) {
    OPTIMAL("Optimal Recovery", "#00E5FF"), // Electric Cyan
    GREAT("Great Recharging", "#00E676"),   // Emerald Green
    FAIR("Moderate Recovery", "#FFD600"),   // Amber Gold
    DEFICIT("Recovery Deficit", "#FF5252")  // Coral Crimson
}

data class SleepRecoveryVerdict(
    val id: String = UUID.randomUUID().toString(),
    val status: SleepRecoveryStatus,
    val headline: String,
    val narrative: String,
    val readinessScore: Int, // 0 - 100
    val physicalRepairRating: String, // "High", "Adequate", "Low"
    val cognitiveRestoreRating: String, // "High", "Adequate", "Low"
    val sleepContinuityRating: String // "Continuous", "Fragmented"
)

enum class SleepTipCategory(val displayName: String, val hexColor: String) {
    CIRCADIAN("Circadian Rhythm", "#FFB300"), // Amber Sun
    ENVIRONMENT("Bedroom Climate", "#40C4FF"), // Ice Blue
    NUTRITION("Evening Nutrition", "#FF8A80"), // Warm Coral
    WIND_DOWN("Vagal Wind-Down", "#B388FF")    // Soft Lavender
}

data class SleepActionableTip(
    val id: String = UUID.randomUUID().toString(),
    val category: SleepTipCategory,
    val title: String,
    val advice: String,
    val scientificRationale: String
)

data class SleepAIContext(
    val narrativeSynthesis: String,
    val suggestedPrompts: List<String>
)
