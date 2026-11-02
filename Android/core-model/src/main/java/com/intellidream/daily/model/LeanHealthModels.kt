package com.intellidream.daily.model

import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonNames

/**
 * Lean Health Architecture Models (Phase 1) on Android.
 * Maps 1:1 with canonical Supabase tables:
 * - health_sources
 * - health_sleep_sessions
 * - health_daily_vitals
 * - health_intraday_heart_rate
 */

@OptIn(ExperimentalSerializationApi::class)
@Serializable
data class HealthSourceRecord(
    val id: String,
    @SerialName("user_id") @JsonNames("userId") val userId: String,
    val platform: String,
    @SerialName("device_kind") @JsonNames("deviceKind") val deviceKind: String,
    val vendor: String? = null,
    val model: String? = null,
    @SerialName("display_name") @JsonNames("displayName") val displayName: String,
    @SerialName("host_device_name") @JsonNames("hostDeviceName") val hostDeviceName: String? = null,
    @SerialName("priority_sleep") @JsonNames("prioritySleep") val prioritySleep: Int = 10,
    @SerialName("priority_activity") @JsonNames("priorityActivity") val priorityActivity: Int = 10,
    val color: String? = "#3897F0",
    @SerialName("created_at") @JsonNames("createdAt") val createdAt: String? = null
)

@OptIn(ExperimentalSerializationApi::class)
@Serializable
data class HealthSleepSessionRecord(
    val id: String,
    @SerialName("user_id") @JsonNames("userId") val userId: String,
    @SerialName("local_date") @JsonNames("localDate") val localDate: String,
    @SerialName("session_type") @JsonNames("sessionType") val sessionType: String = "primary_sleep",
    @SerialName("source_device_key") @JsonNames("sourceDeviceKey") val sourceDeviceKey: String,
    @SerialName("host_device_name") @JsonNames("hostDeviceName") val hostDeviceName: String? = null,
    @Serializable(with = TimestampSerializer::class)
    @SerialName("start_time") @JsonNames("startTime") val startTime: Long,
    @Serializable(with = TimestampSerializer::class)
    @SerialName("end_time") @JsonNames("endTime") val endTime: Long,
    @SerialName("duration_seconds") @JsonNames("durationSeconds") val durationSeconds: Int,
    @SerialName("time_in_bed_seconds") @JsonNames("timeInBedSeconds") val timeInBedSeconds: Int,
    @SerialName("efficiency_percent") @JsonNames("efficiencyPercent") val efficiencyPercent: Double? = null,
    @SerialName("sleep_score") @JsonNames("sleepScore") val sleepScore: Int? = null,
    @SerialName("deep_seconds") @JsonNames("deepSeconds") val deepSeconds: Int = 0,
    @SerialName("rem_seconds") @JsonNames("remSeconds") val remSeconds: Int = 0,
    @SerialName("light_seconds") @JsonNames("lightSeconds") val lightSeconds: Int = 0,
    @SerialName("awake_seconds") @JsonNames("awakeSeconds") val awakeSeconds: Int = 0,
    @SerialName("latency_seconds") @JsonNames("latencySeconds") val latencySeconds: Int = 0,
    @SerialName("quality_rating") @JsonNames("qualityRating") val qualityRating: String? = null,
    val stages: List<SleepStageRecord> = emptyList(),
    @SerialName("source_priority") @JsonNames("sourcePriority") val sourcePriority: Int = 10,
    @SerialName("is_user_selected") @JsonNames("isUserSelected") val isUserSelected: Boolean = false,
    @SerialName("ingested_at") @JsonNames("ingestedAt") val ingestedAt: String? = null
) {
    fun toSleepSession(): SleepSession {
        val canonDevice = DeviceSource.from(sourceDeviceKey).displayName
        val effectiveStages: List<SleepStageRecord> = if (stages.isNotEmpty()) {
            stages.map { it.copy(sourceDevice = canonDevice) }
        } else {
            val synthesized = mutableListOf<SleepStageRecord>()
            var cursorMs = startTime
            fun appendBlock(type: SleepStageType, secs: Int) {
                if (secs <= 0) return
                val endMs = cursorMs + secs * 1000L
                synthesized.add(
                    SleepStageRecord(
                        id = "${id}_${type.rawValue}_$cursorMs",
                        stageType = type,
                        startTime = cursorMs,
                        endTime = endMs,
                        durationSeconds = secs.toDouble(),
                        sourceDevice = canonDevice
                    )
                )
                cursorMs = endMs
            }
            val knownStages = deepSeconds + remSeconds + lightSeconds + awakeSeconds
            if (knownStages > 0) {
                appendBlock(SleepStageType.LIGHT, lightSeconds)
                appendBlock(SleepStageType.DEEP, deepSeconds)
                appendBlock(SleepStageType.REM, remSeconds)
                appendBlock(SleepStageType.AWAKE, awakeSeconds)
            } else if (durationSeconds > 0) {
                appendBlock(SleepStageType.LIGHT, durationSeconds)
            }
            synthesized
        }

        return SleepSession(
            id = id,
            startTime = startTime,
            endTime = endTime,
            isNap = sessionType == "nap",
            stages = effectiveStages,
            sourceDevice = canonDevice,
            hasGranularHypnogram = stages.isNotEmpty()
        )
    }
}

@OptIn(ExperimentalSerializationApi::class)
@Serializable
data class HealthDailyVitalsRecord(
    val id: String,
    @SerialName("user_id") @JsonNames("userId") val userId: String,
    @SerialName("local_date") @JsonNames("localDate") val localDate: String,
    @SerialName("source_device_key") @JsonNames("sourceDeviceKey") val sourceDeviceKey: String,
    @SerialName("host_device_name") @JsonNames("hostDeviceName") val hostDeviceName: String? = null,
    val steps: Int = 0,
    @SerialName("active_kcal") @JsonNames("activeKcal") val activeKcal: Double = 0.0,
    @SerialName("resting_heart_rate") @JsonNames("restingHeartRate") val restingHeartRate: Int? = null,
    val spo2: Double? = null,
    @SerialName("respiratory_rate") @JsonNames("respiratoryRate") val respiratoryRate: Double? = null,
    @SerialName("skin_temp_celsius") @JsonNames("skinTempCelsius") val skinTempCelsius: Double? = null,
    @SerialName("weight_kg") @JsonNames("weightKg") val weightKg: Double? = null,
    @SerialName("hrv_sdnn_nightly") @JsonNames("hrvSdnnNightly") val hrvSdnnNightly: Double? = null,
    @SerialName("hrv_rmssd_nightly") @JsonNames("hrvRmssdNightly") val hrvRmssdNightly: Double? = null,
    @SerialName("hourly_steps") @JsonNames("hourlySteps") val hourlySteps: List<HourlyStepBucket>? = null,
    @SerialName("updated_at") @JsonNames("updatedAt") val updatedAt: String? = null
) {
    val hasSignal: Boolean
        get() = steps > 0 ||
                activeKcal > 0.0 ||
                (restingHeartRate ?: 0) > 0 ||
                (spo2 ?: 0.0) > 0.0 ||
                (respiratoryRate ?: 0.0) > 0.0 ||
                skinTempCelsius != null ||
                (weightKg ?: 0.0) > 0.0 ||
                (hrvSdnnNightly ?: 0.0) > 0.0 ||
                (hrvRmssdNightly ?: 0.0) > 0.0
}

@OptIn(ExperimentalSerializationApi::class)
@Serializable
data class HealthIntradayHeartRateRecord(
    val id: String,
    @SerialName("user_id") @JsonNames("userId") val userId: String,
    @SerialName("local_date") @JsonNames("localDate") val localDate: String,
    @SerialName("source_device_key") @JsonNames("sourceDeviceKey") val sourceDeviceKey: String,
    @SerialName("bucket_minute") @JsonNames("bucketMinute") val bucketMinute: Int,
    @SerialName("bpm_avg") @JsonNames("bpmAvg") val bpmAvg: Int,
    @SerialName("bpm_min") @JsonNames("bpmMin") val bpmMin: Int,
    @SerialName("bpm_max") @JsonNames("bpmMax") val bpmMax: Int,
    @SerialName("sample_count") @JsonNames("sampleCount") val sampleCount: Int = 1,
    @SerialName("updated_at") @JsonNames("updatedAt") val updatedAt: String? = null
) {
    fun toPoint(targetDateEpochMs: Long): IntradayHeartRatePoint {
        val cal = java.util.Calendar.getInstance().apply {
            timeInMillis = targetDateEpochMs
            set(java.util.Calendar.HOUR_OF_DAY, bucketMinute / 60)
            set(java.util.Calendar.MINUTE, bucketMinute % 60)
            set(java.util.Calendar.SECOND, 0)
            set(java.util.Calendar.MILLISECOND, 0)
        }
        return IntradayHeartRatePoint(
            timestamp = cal.timeInMillis,
            bpm = bpmAvg.toDouble(),
            sourceDevice = DeviceSource.from(sourceDeviceKey).displayName
        )
    }
}
