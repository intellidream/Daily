package com.intellidream.daily.model

import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNames

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
data class DeviceMetricItem(
    val value: Double = 0.0,
    @SerialName("source_key") val sourceKey: String = "",
    @SerialName("source_color") val sourceColor: String = "#3897F0",
    val unit: String? = null,
    val timestamp: String? = null,
    val score: Int? = null
)

@Serializable
data class DailyHealthSummaryPayload(
    val date: String,
    @SerialName("computed_at") val computedAt: String? = null,
    val sources: List<String> = emptyList(),
    @SerialName("all_devices_view") val allDevicesView: Map<String, DeviceMetricItem> = emptyMap(),
    @SerialName("sources_breakdown") val sourcesBreakdown: Map<String, Map<String, Double>> = emptyMap(),
    val sleep: CanonicalSleepSummary? = null,
    val activity: CanonicalActivitySummary? = null,
    val cardiovascular: CanonicalCardiovascularSummary? = null,
    val stress: CanonicalStressSummary? = null,
    val vitals: Map<String, CanonicalVitalSummaryItem> = emptyMap()
) {
    fun isEmpty(): Boolean {
        val noSteps = activity == null || activity.totalSteps == 0
        val noSleep = sleep == null || sleep.primarySession == null
        val noVitals = vitals.isEmpty()
        val noStress = stress == null
        val noCardio = cardiovascular == null || ((cardiovascular.restingHeartRateBpm == null || cardiovascular.restingHeartRateBpm == 0.0) && cardiovascular.intradayHeartRate.isEmpty())
        return noSteps && noSleep && noVitals && noStress && noCardio
    }
}

@Serializable
data class CanonicalSleepSummary(
    @SerialName("primary_session") val primarySession: SleepSession? = null,
    @SerialName("all_sessions") val allSessions: List<SleepSession> = emptyList(),
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

@OptIn(ExperimentalSerializationApi::class)
@Serializable
data class CanonicalActivitySummary(
    @SerialName("total_steps") val totalSteps: Int = 0,
    @JsonNames("active_calories", "active_calories_kcal")
    @SerialName("active_calories") val activeCaloriesKcal: Double = 0.0,
    @SerialName("source_device") val sourceDevice: String? = null,
    @SerialName("hourly_steps") val hourlySteps: List<HourlyStepBucket> = emptyList(),
    @SerialName("tracker_priority_order") val trackerPriorityOrder: List<String> = emptyList()
)

@OptIn(ExperimentalSerializationApi::class)
@Serializable
data class CanonicalCardiovascularSummary(
    @JsonNames("intraday_points", "intraday_heart_rate")
    @SerialName("intraday_points") val intradayHeartRate: List<IntradayHeartRatePoint> = emptyList(),
    @JsonNames("resting_bpm", "resting_heart_rate_bpm")
    @SerialName("resting_bpm") val restingHeartRateBpm: Double? = null,
    @JsonNames("average_bpm", "average_heart_rate_bpm")
    @SerialName("average_bpm") val averageHeartRateBpm: Double? = null,
    @JsonNames("max_bpm", "max_heart_rate_bpm")
    @SerialName("max_bpm") val maxHeartRateBpm: Double? = null,
    @JsonNames("min_bpm", "min_heart_rate_bpm")
    @SerialName("min_bpm") val minHeartRateBpm: Double? = null,
    @JsonNames("zones", "heart_rate_zones")
    @SerialName("zones") val heartRateZones: CanonicalHeartRateZones? = null
)

@OptIn(ExperimentalSerializationApi::class)
@Serializable
data class CanonicalHeartRateZones(
    @JsonNames("resting", "resting_minutes")
    @SerialName("resting") val restingMinutes: Int = 0,
    @JsonNames("fat_burn", "fat_burn_minutes")
    @SerialName("fat_burn") val fatBurnMinutes: Int = 0,
    @JsonNames("cardio", "cardio_minutes")
    @SerialName("cardio") val cardioMinutes: Int = 0,
    @JsonNames("peak", "peak_minutes")
    @SerialName("peak") val peakMinutes: Int = 0
) {
    fun toMap(): Map<HeartRateZone, Int> = mapOf(
        HeartRateZone.RESTING to restingMinutes,
        HeartRateZone.FAT_BURN to fatBurnMinutes,
        HeartRateZone.CARDIO to cardioMinutes,
        HeartRateZone.PEAK to peakMinutes
    )
}

@OptIn(ExperimentalSerializationApi::class)
@Serializable
data class CanonicalStressSummary(
    @JsonNames("daily_average", "daily_average_score")
    @SerialName("daily_average") val dailyAverageScore: Int = 50,
    @SerialName("current_score") val currentScore: Int = 50,
    @SerialName("current_level") val currentLevel: String = "Calm",
    @SerialName("peak_hour") val peakHour: Int? = null,
    @SerialName("peak_score") val peakScore: Int? = null,
    @SerialName("lowest_hour") val lowestHour: Int? = null,
    @SerialName("lowest_score") val lowestScore: Int? = null,
    @SerialName("parasympathetic_percent") val parasympatheticPercent: Int = 50,
    @SerialName("sympathetic_percent") val sympatheticPercent: Int = 50,
    @SerialName("baseline_hrv_ms") val baselineHrvMs: Double = 45.0,
    @SerialName("current_hrv_ms") val currentHrvMs: Double? = null,
    @SerialName("hrv_delta_percent") val hrvDeltaPercent: Double? = null,
    @SerialName("resting_heart_rate_bpm") val restingHeartRateBpm: Double? = null,
    @SerialName("current_sedentary_bpm") val currentSedentaryBpm: Double? = null,
    @SerialName("heart_rate_elevation_bpm") val heartRateElevationBpm: Double? = null,
    @SerialName("monkey_mood") val monkeyMood: String? = null,
    @SerialName("advice_quote") val adviceQuote: String? = null,
    @SerialName("recommended_breathing") val recommendedBreathing: String? = null,
    @JsonNames("intraday_points", "intraday_stress")
    @SerialName("intraday_points") val intradayStress: List<IntradayStressPoint> = emptyList()
) {
    val autonomicBalance: CanonicalAutonomicBalance
        get() = CanonicalAutonomicBalance(sympatheticPercent, parasympatheticPercent)

    val biometricDrivers: CanonicalStressDrivers
        get() = CanonicalStressDrivers(
            baselineHrvMs = baselineHrvMs,
            currentHrvMs = currentHrvMs,
            restingHeartRateBpm = restingHeartRateBpm,
            currentSedentaryBpm = currentSedentaryBpm
        )

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
        val sym = sympatheticPercent
        val para = parasympatheticPercent
        val baseHrv = baselineHrvMs
        val curHrv = currentHrvMs
        val rhr = restingHeartRateBpm
        val sedBpm = currentSedentaryBpm

        return StressAnalysisResult(
            currentScore = currentScore,
            currentLevel = level,
            dailyAverageScore = dailyAverageScore,
            parasympatheticPercent = para,
            sympatheticPercent = sym,
            baselineHrvMs = baseHrv,
            currentHrvMs = curHrv,
            hrvDeltaPercent = hrvDeltaPercent ?: if (curHrv != null && baseHrv > 0) ((curHrv - baseHrv) / baseHrv) * 100.0 else null,
            restingHeartRateBpm = rhr,
            currentSedentaryBpm = sedBpm,
            heartRateElevationBpm = heartRateElevationBpm ?: if (sedBpm != null && rhr != null) (sedBpm - rhr) else null,
            monkeyMood = mood,
            adviceQuote = adviceQuote ?: mood.adviceQuote,
            recommendedBreathing = recommendedBreathing?.let {
                BreathingProtocol.entries.find { b -> b.id.equals(it, ignoreCase = true) || b.title.equals(it, ignoreCase = true) }
            } ?: BreathingProtocol.defaultForLevel(level)
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
