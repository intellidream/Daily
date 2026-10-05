package com.intellidream.daily.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement

/**
 * Android Kotlin models mapping to Supabase canonical Health & Vitals daily summary schema (version 1).
 * 1:1 mathematical and architectural parity with iOS DailyCore's HealthDailySummaryModels.swift
 * and Supabase Edge Function health-engine.
 */

@Serializable
data class HealthDailySummaryRecord(
    val id: String = "",
    @SerialName("user_id") val userId: String,
    @SerialName("local_date") val localDate: String, // "yyyy-MM-dd"
    @SerialName("computed_at") val computedAt: String? = null,
    @SerialName("engine_version") val engineVersion: String = "1.0",
    @SerialName("raw_watermark") val rawWatermark: String? = null,
    val steps: Int? = null,
    @SerialName("active_kcal") val activeKcal: Double? = null,
    @SerialName("sleep_asleep_s") val sleepAsleepS: Int? = null,
    @SerialName("sleep_score") val sleepScore: Int? = null,
    @SerialName("stress_avg") val stressAvg: Int? = null,
    val rhr: Double? = null,
    @SerialName("hrv_sdnn") val hrvSdnn: Double? = null,
    @SerialName("hrv_rmssd") val hrvRmssd: Double? = null,
    val weight: Double? = null,
    val spo2: Double? = null,
    val summary: DailyHealthSummaryPayload? = null
)

@Serializable
data class DailyHealthSummaryPayload(
    val date: String,
    @SerialName("computed_at") val computedAt: String? = null,
    val sources: List<String> = emptyList(),
    val sleep: CanonicalSleepSummary? = null,
    val activity: CanonicalActivitySummary? = null,
    val cardiovascular: CanonicalCardiovascularSummary? = null,
    val stress: CanonicalStressSummary? = null,
    val vitals: Map<String, CanonicalVitalSummaryItem> = emptyMap()
)

@Serializable
data class CanonicalSleepSummary(
    @SerialName("primary_session") val primarySession: SleepSession? = null,
    val naps: List<NapSession> = emptyList(),
    val guidance: CanonicalSleepGuidance? = null,
    @SerialName("tracker_priority_order") val trackerPriorityOrder: List<String> = emptyList()
)

@Serializable
data class CanonicalSleepGuidance(
    val verdict: CanonicalSleepVerdict? = null,
    val tips: List<CanonicalSleepTip> = emptyList(),
    @SerialName("ai_context") val aiContext: CanonicalSleepAIContext? = null
)

@Serializable
data class CanonicalSleepVerdict(
    val status: String,
    val headline: String,
    val narrative: String,
    @SerialName("readiness_score") val readinessScore: Int,
    @SerialName("physical_repair_rating") val physicalRepairRating: String,
    @SerialName("cognitive_restore_rating") val cognitiveRestoreRating: String,
    @SerialName("sleep_continuity_rating") val sleepContinuityRating: String
) {
    fun toDomain(): SleepRecoveryVerdict {
        val st = when (status.lowercase()) {
            "optimal", "optimal recovery" -> SleepRecoveryStatus.OPTIMAL
            "great", "great recharging" -> SleepRecoveryStatus.GREAT
            "fair", "moderate recovery" -> SleepRecoveryStatus.FAIR
            else -> SleepRecoveryStatus.DEFICIT
        }
        return SleepRecoveryVerdict(
            status = st,
            headline = headline,
            narrative = narrative,
            readinessScore = readinessScore,
            physicalRepairRating = physicalRepairRating,
            cognitiveRestoreRating = cognitiveRestoreRating,
            sleepContinuityRating = sleepContinuityRating
        )
    }
}

@Serializable
data class CanonicalSleepTip(
    val category: String,
    val title: String,
    val advice: String,
    @SerialName("scientific_rationale") val scientificRationale: String
) {
    fun toDomain(): SleepActionableTip {
        val cat = when (category.lowercase()) {
            "circadian", "circadian rhythm" -> SleepTipCategory.CIRCADIAN
            "environment", "bedroom climate" -> SleepTipCategory.ENVIRONMENT
            "nutrition", "evening nutrition" -> SleepTipCategory.NUTRITION
            else -> SleepTipCategory.WIND_DOWN
        }
        return SleepActionableTip(
            category = cat,
            title = title,
            advice = advice,
            scientificRationale = scientificRationale
        )
    }
}

@Serializable
data class CanonicalSleepAIContext(
    @SerialName("narrative_synthesis") val narrativeSynthesis: String,
    @SerialName("suggested_prompts") val suggestedPrompts: List<String> = emptyList()
) {
    fun toDomain(): SleepAIContext = SleepAIContext(
        narrativeSynthesis = narrativeSynthesis,
        suggestedPrompts = suggestedPrompts
    )
}

@Serializable
data class CanonicalActivitySummary(
    @SerialName("total_steps") val totalSteps: Int,
    @SerialName("active_calories_kcal") val activeCaloriesKcal: Double,
    @SerialName("hourly_steps") val hourlySteps: List<HourlyStepBucket> = emptyList(),
    @SerialName("tracker_priority_order") val trackerPriorityOrder: List<String> = emptyList()
)

@Serializable
data class CanonicalCardiovascularSummary(
    @SerialName("intraday_heart_rate") val intradayHeartRate: List<IntradayHeartRatePoint> = emptyList(),
    @SerialName("resting_heart_rate_bpm") val restingHeartRateBpm: Double? = null,
    @SerialName("average_heart_rate_bpm") val averageHeartRateBpm: Double? = null,
    @SerialName("max_heart_rate_bpm") val maxHeartRateBpm: Double? = null,
    @SerialName("min_heart_rate_bpm") val minHeartRateBpm: Double? = null,
    @SerialName("heart_rate_zones") val heartRateZones: CanonicalHeartRateZones? = null
)

@Serializable
data class CanonicalHeartRateZones(
    @SerialName("resting_minutes") val restingMinutes: Int = 0,
    @SerialName("fat_burn_minutes") val fatBurnMinutes: Int = 0,
    @SerialName("cardio_minutes") val cardioMinutes: Int = 0,
    @SerialName("peak_minutes") val peakMinutes: Int = 0
) {
    fun toMap(): Map<HeartRateZone, Int> = mapOf(
        HeartRateZone.RESTING to restingMinutes,
        HeartRateZone.FAT_BURN to fatBurnMinutes,
        HeartRateZone.CARDIO to cardioMinutes,
        HeartRateZone.PEAK to peakMinutes
    )
}

@Serializable
data class CanonicalStressSummary(
    @SerialName("daily_average_score") val dailyAverageScore: Int,
    @SerialName("current_score") val currentScore: Int,
    @SerialName("current_level") val currentLevel: String,
    @SerialName("autonomic_balance") val autonomicBalance: CanonicalAutonomicBalance? = null,
    @SerialName("biometric_drivers") val biometricDrivers: CanonicalStressDrivers? = null,
    @SerialName("monkey_mood") val monkeyMood: String? = null,
    @SerialName("intraday_stress") val intradayStress: List<IntradayStressPoint> = emptyList()
) {
    fun toDomainLevel(): StressLevel = when (currentLevel.lowercase()) {
        "restful" -> StressLevel.RESTFUL
        "calm" -> StressLevel.CALM
        "moderate" -> StressLevel.MODERATE
        else -> StressLevel.HIGH
    }

    fun toDomainMood(): MonkeyMood = when (monkeyMood?.lowercase()) {
        "zen", "zen monkey" -> MonkeyMood.ZEN
        "curious", "curious monkey" -> MonkeyMood.CURIOUS
        "busy", "busy monkey" -> MonkeyMood.BUSY
        "overheated", "overheated monkey" -> MonkeyMood.OVERHEATED
        else -> MonkeyMood.fromLevel(toDomainLevel())
    }

    fun toDomainAnalysis(): StressAnalysisResult {
        val level = toDomainLevel()
        val mood = toDomainMood()
        val sym = autonomicBalance?.sympatheticPercent ?: 50
        val para = autonomicBalance?.parasympatheticPercent ?: 50
        val baseHrv = biometricDrivers?.baselineHrvMs ?: 45.0
        val curHrv = biometricDrivers?.currentHrvMs
        val rhr = biometricDrivers?.restingHeartRateBpm
        val sedBpm = biometricDrivers?.currentSedentaryBpm

        return StressAnalysisResult(
            currentScore = currentScore,
            currentLevel = level,
            dailyAverageScore = dailyAverageScore,
            parasympatheticPercent = para,
            sympatheticPercent = sym,
            baselineHrvMs = baseHrv,
            currentHrvMs = curHrv,
            hrvDeltaPercent = if (curHrv != null && baseHrv > 0) ((curHrv - baseHrv) / baseHrv) * 100.0 else null,
            restingHeartRateBpm = rhr,
            currentSedentaryBpm = sedBpm,
            heartRateElevationBpm = if (sedBpm != null && rhr != null) (sedBpm - rhr) else null,
            monkeyMood = mood,
            adviceQuote = mood.adviceQuote,
            recommendedBreathing = BreathingProtocol.defaultForLevel(level)
        )
    }
}

@Serializable
data class CanonicalAutonomicBalance(
    @SerialName("sympathetic_percent") val sympatheticPercent: Int = 50,
    @SerialName("parasympathetic_percent") val parasympatheticPercent: Int = 50
)

@Serializable
data class CanonicalStressDrivers(
    @SerialName("baseline_hrv_ms") val baselineHrvMs: Double = 45.0,
    @SerialName("current_hrv_ms") val currentHrvMs: Double? = null,
    @SerialName("resting_heart_rate_bpm") val restingHeartRateBpm: Double? = null,
    @SerialName("current_sedentary_bpm") val currentSedentaryBpm: Double? = null
)

@Serializable
data class CanonicalVitalSummaryItem(
    val value: Double,
    val unit: String? = null,
    @SerialName("source_device") val sourceDevice: String? = null,
    @SerialName("age_label") val ageLabel: String? = null,
    val timestamp: String? = null
)
