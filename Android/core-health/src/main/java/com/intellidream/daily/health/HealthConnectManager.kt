package com.intellidream.daily.health

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.HeartRateVariabilityRmssdRecord
import androidx.health.connect.client.records.HydrationRecord
import androidx.health.connect.client.records.OxygenSaturationRecord
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.records.RestingHeartRateRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import com.intellidream.daily.model.HealthTelemetryRecord
import com.intellidream.daily.model.SleepStageType
import androidx.health.connect.client.units.Volume
import java.time.Instant
import java.time.ZoneOffset
import java.time.temporal.ChronoUnit
import java.util.Calendar
import java.util.Date
import java.util.Locale
import kotlin.reflect.KClass

/**
 * Manages interactions with Android Health Connect SDK.
 * Gracefully handles scenarios where Health Connect is unavailable or unpermitted,
 * converting Health Connect records into unified [HealthTelemetryRecord] instances.
 */
class HealthConnectManager(private val context: Context) {

    private val healthConnectClient: HealthConnectClient? by lazy {
        if (HealthConnectClient.getSdkStatus(context) == HealthConnectClient.SDK_AVAILABLE) {
            HealthConnectClient.getOrCreate(context)
        } else {
            null
        }
    }

    val isAvailable: Boolean
        get() = HealthConnectClient.getSdkStatus(context) == HealthConnectClient.SDK_AVAILABLE

    val requiredPermissions: Set<String> = setOf(
        HealthPermission.getReadPermission(StepsRecord::class),
        HealthPermission.getReadPermission(HeartRateRecord::class),
        HealthPermission.getReadPermission(RestingHeartRateRecord::class),
        HealthPermission.getReadPermission(HeartRateVariabilityRmssdRecord::class),
        HealthPermission.getReadPermission(SleepSessionRecord::class),
        HealthPermission.getReadPermission(ActiveCaloriesBurnedRecord::class),
        HealthPermission.getReadPermission(OxygenSaturationRecord::class),
        HealthPermission.getReadPermission(HydrationRecord::class),
        HealthPermission.getWritePermission(HydrationRecord::class)
    )

    suspend fun writeHydrationRecord(amountMl: Double, timestamp: Long = System.currentTimeMillis()): Boolean {
        val client = healthConnectClient ?: return false
        return try {
            val instant = Instant.ofEpochMilli(timestamp)
            val record = HydrationRecord(
                startTime = instant,
                endTime = instant.plusSeconds(60),
                startZoneOffset = ZoneOffset.systemDefault().rules.getOffset(instant),
                endZoneOffset = ZoneOffset.systemDefault().rules.getOffset(instant),
                volume = Volume.milliliters(amountMl)
            )
            client.insertRecords(listOf(record))
            true
        } catch (e: Exception) {
            android.util.Log.w("HealthConnectManager", "Failed to write hydration to Health Connect", e)
            false
        }
    }

    suspend fun hasAllPermissions(): Boolean {
        val client = healthConnectClient ?: return false
        val granted = client.permissionController.getGrantedPermissions()
        return granted.containsAll(requiredPermissions)
    }

    suspend fun hasAnyPermissions(): Boolean {
        val client = healthConnectClient ?: return false
        val granted = client.permissionController.getGrantedPermissions()
        return granted.isNotEmpty()
    }

    suspend fun getGrantedPermissions(): Set<String> {
        val client = healthConnectClient ?: return emptySet()
        return client.permissionController.getGrantedPermissions()
    }

    fun getHostPhoneName(): String = getHostPhoneName(context)

    companion object {
        fun getHostPhoneName(context: Context): String {
            try {
                val prefs = context.getSharedPreferences("daily_health_prefs", Context.MODE_PRIVATE)
                val nickname = prefs.getString("device_nickname", null)?.trim()
                if (!nickname.isNullOrEmpty()) return nickname
            } catch (_: Exception) {}

            try {
                val deviceName = android.provider.Settings.Global.getString(context.contentResolver, "device_name")?.trim()
                if (!deviceName.isNullOrEmpty()) return deviceName
            } catch (_: Exception) {}

            try {
                val btName = android.provider.Settings.System.getString(context.contentResolver, "bluetooth_name")?.trim()
                if (!btName.isNullOrEmpty()) return btName
            } catch (_: Exception) {}

            val model = android.os.Build.MODEL?.trim()
            if (!model.isNullOrEmpty()) return model

            return "Android Device"
        }

        fun resolveSensorSourceName(packageName: String): String {
            return when (packageName) {
                "com.fitbit.FitbitMobile" -> "Pixel Watch 5 (Fitbit)"
                "com.sec.android.app.shealth" -> "Samsung Health"
                "com.ouraring.oura" -> "Oura Ring"
                "com.google.android.apps.fitness" -> "Google Fit"
                "com.garmin.android.apps.connectmobile" -> "Garmin Connect"
                "com.whoop.android" -> "WHOOP"
                "com.withings.wiscale2" -> "Withings"
                "com.strava" -> "Strava"
                "com.huawei.health" -> "Huawei Health"
                else -> {
                    if (packageName.isBlank()) {
                        "Health Connect"
                    } else if (packageName.contains(".")) {
                        val clean = packageName.substringAfterLast('.')
                        clean.replaceFirstChar { if (it.isLowerCase()) it.titlecase(Locale.ROOT) else it.toString() }
                    } else {
                        packageName
                    }
                }
            }
        }
    }

    private fun deterministicId(userId: String, uniqueKey: String): String =
        java.util.UUID.nameUUIDFromBytes("$userId:$uniqueKey".toByteArray(Charsets.UTF_8)).toString()

    /**
     * Reads all local health telemetry from Health Connect for a specific target date.
     * Uses strictly split query filters (00:00-23:59 for daytime activity/vitals, D-1 18:00 for sleep)
     * and tags all records with compound source attributes ([Host Phone] - [Sensor/Wearable]).
     */
    suspend fun fetchTelemetryForDate(targetDate: Date, userId: String = "local_user"): List<HealthTelemetryRecord> {
        val client = healthConnectClient ?: return emptyList()

        val cal = Calendar.getInstance().apply {
            time = targetDate
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }

        val tz = java.util.TimeZone.getDefault()
        val tzOffsetMin = tz.getOffset(targetDate.time) / 60000
        val recordDateFormatter = java.text.SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
            timeZone = tz
        }

        // 1. Daytime filter: strictly D 00:00:00 to D 23:59:59 (for activity, vitals, steps, energy, hydration)
        val dayStart = Instant.ofEpochMilli(cal.timeInMillis)
        val dayEnd = Instant.ofEpochMilli(cal.timeInMillis).plus(1, ChronoUnit.DAYS)
        val daytimeFilter = TimeRangeFilter.between(dayStart, dayEnd)

        // 2. Sleep filter: D-1 18:00 to D 18:00 (to catch nocturnal sleep onset from the previous evening)
        val sleepStart = Instant.ofEpochMilli(cal.timeInMillis).minus(6, ChronoUnit.HOURS)
        val sleepEnd = Instant.ofEpochMilli(cal.timeInMillis).plus(18, ChronoUnit.HOURS)
        val sleepFilter = TimeRangeFilter.between(sleepStart, sleepEnd)

        val hostName = getHostPhoneName(context)
        val telemetry = mutableListOf<HealthTelemetryRecord>()

        fun buildRecord(
            type: String,
            value: Double?,
            unit: String?,
            startTime: Long,
            endTime: Long?,
            rawPackage: String,
            extId: String?,
            semantics: String?
        ): HealthTelemetryRecord {
            val sensorName = resolveSensorSourceName(rawPackage)
            val sourceKey = "$hostName - $sensorName"
            val sourceColor = com.intellidream.daily.model.DeviceColorPalette.getColorForSource(sourceKey)
            val recordLocalDate = recordDateFormatter.format(Date(startTime))
            val deterministicExtId = extId ?: "${type}_${userId}_$startTime"
            return HealthTelemetryRecord(
                id = deterministicId(userId, "${type}_$deterministicExtId"),
                userId = userId,
                type = type,
                value = value,
                unit = unit,
                startTime = startTime,
                endTime = endTime,
                sourceDevice = sourceKey,
                externalId = deterministicExtId,
                semantics = semantics,
                hostDeviceName = hostName,
                sensorSourceName = sensorName,
                sourceDeviceKey = sourceKey,
                sourceColor = sourceColor,
                tzOffsetMin = tzOffsetMin,
                localDate = recordLocalDate
            )
        }

        try {
            // 1. Steps (strictly daytime window)
            val stepsResponse = client.readRecords(
                ReadRecordsRequest(
                    recordType = StepsRecord::class,
                    timeRangeFilter = daytimeFilter
                )
            )
            for (record in stepsResponse.records) {
                telemetry.add(
                    buildRecord(
                        type = "steps",
                        value = record.count.toDouble(),
                        unit = "count",
                        startTime = record.startTime.toEpochMilli(),
                        endTime = record.endTime.toEpochMilli(),
                        rawPackage = record.metadata.dataOrigin.packageName,
                        extId = record.metadata.id,
                        semantics = "interval_delta"
                    )
                )
            }

            // 2. Heart Rate (strictly daytime window, downsampled to 5-minute buckets)
            val hrResponse = client.readRecords(
                ReadRecordsRequest(
                    recordType = HeartRateRecord::class,
                    timeRangeFilter = daytimeFilter
                )
            )
            val fiveMinMs = 5 * 60 * 1000L
            val rawHrSamples = mutableListOf<Triple<Long, Double, String>>()

            for (record in hrResponse.records) {
                val dev = record.metadata.dataOrigin.packageName
                for (sample in record.samples) {
                    val bpm = sample.beatsPerMinute.toDouble()
                    if (bpm in 30.0..240.0) {
                        rawHrSamples.add(Triple(sample.time.toEpochMilli(), bpm, dev))
                    }
                }
            }

            val hrBuckets = rawHrSamples.groupBy {
                (it.first / fiveMinMs) * fiveMinMs
            }

            for ((bucketEpoch, samplesInBucket) in hrBuckets) {
                val primaryRawDevice = samplesInBucket.first().third
                val avgBpm = Math.round((samplesInBucket.map { it.second }.average()) * 10.0) / 10.0
                val extId = "hr_${userId}_$bucketEpoch"
                telemetry.add(
                    buildRecord(
                        type = "heart_rate",
                        value = avgBpm,
                        unit = "bpm",
                        startTime = bucketEpoch,
                        endTime = bucketEpoch + fiveMinMs,
                        rawPackage = primaryRawDevice,
                        extId = extId,
                        semantics = "interval_avg"
                    )
                )
            }

            // 3. Resting Heart Rate (strictly daytime window)
            val rhrResponse = client.readRecords(
                ReadRecordsRequest(
                    recordType = RestingHeartRateRecord::class,
                    timeRangeFilter = daytimeFilter
                )
            )
            for (record in rhrResponse.records) {
                telemetry.add(
                    buildRecord(
                        type = "resting_heart_rate",
                        value = record.beatsPerMinute.toDouble(),
                        unit = "bpm",
                        startTime = record.time.toEpochMilli(),
                        endTime = record.time.toEpochMilli(),
                        rawPackage = record.metadata.dataOrigin.packageName,
                        extId = record.metadata.id,
                        semantics = "spot"
                    )
                )
            }

            // 4. Sleep Sessions & Granular Stages (uses sleepFilter: D-1 18:00 to D 18:00)
            val sleepResponse = client.readRecords(
                ReadRecordsRequest(
                    recordType = SleepSessionRecord::class,
                    timeRangeFilter = sleepFilter
                )
            )
            for (record in sleepResponse.records) {
                val dev = record.metadata.dataOrigin.packageName
                if (record.stages.isNotEmpty()) {
                    for (stage in record.stages) {
                        val stageTypeStr = when (stage.stage) {
                            SleepSessionRecord.STAGE_TYPE_DEEP -> "sleep_stage_deep"
                            SleepSessionRecord.STAGE_TYPE_REM -> "sleep_stage_rem"
                            SleepSessionRecord.STAGE_TYPE_LIGHT -> "sleep_stage_light"
                            SleepSessionRecord.STAGE_TYPE_AWAKE,
                            SleepSessionRecord.STAGE_TYPE_AWAKE_IN_BED,
                            SleepSessionRecord.STAGE_TYPE_OUT_OF_BED -> "sleep_stage_awake"
                            else -> "sleep_stage_light"
                        }
                        val durSec = ChronoUnit.SECONDS.between(stage.startTime, stage.endTime).toDouble()
                        val stageStartEpoch = stage.startTime.toEpochMilli()
                        val stageExtId = "${record.metadata.id}_$stageStartEpoch"
                        telemetry.add(
                            buildRecord(
                                type = stageTypeStr,
                                value = durSec,
                                unit = "seconds",
                                startTime = stageStartEpoch,
                                endTime = stage.endTime.toEpochMilli(),
                                rawPackage = dev,
                                extId = stageExtId,
                                semantics = "session_stage"
                            )
                        )
                    }
                } else {
                    val durSec = ChronoUnit.SECONDS.between(record.startTime, record.endTime).toDouble()
                    telemetry.add(
                        buildRecord(
                            type = "sleep_duration",
                            value = durSec,
                            unit = "seconds",
                            startTime = record.startTime.toEpochMilli(),
                            endTime = record.endTime.toEpochMilli(),
                            rawPackage = dev,
                            extId = record.metadata.id,
                            semantics = "session_stage"
                        )
                    )
                }
            }

            // 5. Active Calories Burned (strictly daytime window)
            val calResponse = client.readRecords(
                ReadRecordsRequest(
                    recordType = ActiveCaloriesBurnedRecord::class,
                    timeRangeFilter = daytimeFilter
                )
            )
            for (record in calResponse.records) {
                telemetry.add(
                    buildRecord(
                        type = "active_energy",
                        value = record.energy.inKilocalories,
                        unit = "kcal",
                        startTime = record.startTime.toEpochMilli(),
                        endTime = record.endTime.toEpochMilli(),
                        rawPackage = record.metadata.dataOrigin.packageName,
                        extId = record.metadata.id,
                        semantics = "interval_delta"
                    )
                )
            }

            // 6. Oxygen Saturation (SpO2) (strictly daytime window)
            val spo2Response = client.readRecords(
                ReadRecordsRequest(
                    recordType = OxygenSaturationRecord::class,
                    timeRangeFilter = daytimeFilter
                )
            )
            for (record in spo2Response.records) {
                telemetry.add(
                    buildRecord(
                        type = "oxygen_saturation",
                        value = record.percentage.value,
                        unit = "%",
                        startTime = record.time.toEpochMilli(),
                        endTime = record.time.toEpochMilli(),
                        rawPackage = record.metadata.dataOrigin.packageName,
                        extId = record.metadata.id,
                        semantics = "spot"
                    )
                )
            }

            // 7. Heart Rate Variability (RMSSD) (strictly daytime window)
            val hrvResponse = client.readRecords(
                ReadRecordsRequest(
                    recordType = HeartRateVariabilityRmssdRecord::class,
                    timeRangeFilter = daytimeFilter
                )
            )
            for (record in hrvResponse.records) {
                telemetry.add(
                    buildRecord(
                        type = "hrv_rmssd",
                        value = record.heartRateVariabilityMillis,
                        unit = "ms",
                        startTime = record.time.toEpochMilli(),
                        endTime = record.time.toEpochMilli(),
                        rawPackage = record.metadata.dataOrigin.packageName,
                        extId = record.metadata.id,
                        semantics = "spot"
                    )
                )
            }

            // 8. Hydration (strictly daytime window)
            val hydResponse = client.readRecords(
                ReadRecordsRequest(
                    recordType = HydrationRecord::class,
                    timeRangeFilter = daytimeFilter
                )
            )
            for (record in hydResponse.records) {
                telemetry.add(
                    buildRecord(
                        type = "hydration",
                        value = record.volume.inMilliliters,
                        unit = "ml",
                        startTime = record.startTime.toEpochMilli(),
                        endTime = record.endTime.toEpochMilli(),
                        rawPackage = record.metadata.dataOrigin.packageName,
                        extId = record.metadata.id,
                        semantics = "interval_delta"
                    )
                )
            }
        } catch (e: Exception) {
            android.util.Log.w("HealthConnectManager", "Error querying Health Connect records", e)
        }

        return telemetry
    }

    /**
     * Reads local health telemetry from Health Connect between two dates.
     * Efficiently captures steps, sleep, active energy, heart rate, and hydration across multi-day ranges for Trends.
     */
    suspend fun fetchTelemetryForDateRange(startDate: Date, endDate: Date): List<HealthTelemetryRecord> {
        val client = healthConnectClient ?: return emptyList()
        val startTime = Instant.ofEpochMilli(startDate.time)
        val endTime = Instant.ofEpochMilli(endDate.time)
        val timeFilter = TimeRangeFilter.between(startTime, endTime)
        val telemetry = mutableListOf<HealthTelemetryRecord>()

        val hostName = getHostPhoneName(context)
        val tz = java.util.TimeZone.getDefault()
        val tzOffsetMin = tz.getOffset(startDate.time) / 60000
        val recordDateFormatter = java.text.SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
            timeZone = tz
        }

        fun buildRangeRecord(
            type: String,
            value: Double?,
            unit: String?,
            recStartTime: Long,
            recEndTime: Long?,
            rawPackage: String,
            extId: String?,
            semantics: String? = null
        ): HealthTelemetryRecord {
            val sensorName = resolveSensorSourceName(rawPackage)
            val sourceKey = "$hostName - $sensorName"
            val sourceColor = com.intellidream.daily.model.DeviceColorPalette.getColorForSource(sourceKey)
            val recordLocalDate = recordDateFormatter.format(Date(recStartTime))
            val deterministicExtId = extId ?: "range_${type}_$recStartTime"
            return HealthTelemetryRecord(
                id = deterministicId("local_health_connect", "range_${type}_$deterministicExtId"),
                userId = "local_health_connect",
                type = type,
                value = value,
                unit = unit,
                startTime = recStartTime,
                endTime = recEndTime,
                sourceDevice = sourceKey,
                externalId = deterministicExtId,
                semantics = semantics,
                hostDeviceName = hostName,
                sensorSourceName = sensorName,
                sourceDeviceKey = sourceKey,
                sourceColor = sourceColor,
                tzOffsetMin = tzOffsetMin,
                localDate = recordLocalDate
            )
        }

        try {
            // Steps
            val steps = client.readRecords(ReadRecordsRequest(StepsRecord::class, timeFilter))
            for (record in steps.records) {
                telemetry.add(
                    buildRangeRecord(
                        type = "steps",
                        value = record.count.toDouble(),
                        unit = "count",
                        recStartTime = record.startTime.toEpochMilli(),
                        recEndTime = record.endTime.toEpochMilli(),
                        rawPackage = record.metadata.dataOrigin.packageName,
                        extId = record.metadata.id,
                        semantics = "interval_delta"
                    )
                )
            }
            // Sleep Sessions
            val sleep = client.readRecords(ReadRecordsRequest(SleepSessionRecord::class, timeFilter))
            for (record in sleep.records) {
                val durSec = ChronoUnit.SECONDS.between(record.startTime, record.endTime).toDouble()
                telemetry.add(
                    buildRangeRecord(
                        type = "sleep_duration",
                        value = durSec,
                        unit = "seconds",
                        recStartTime = record.startTime.toEpochMilli(),
                        recEndTime = record.endTime.toEpochMilli(),
                        rawPackage = record.metadata.dataOrigin.packageName,
                        extId = record.metadata.id,
                        semantics = "session_stage"
                    )
                )
            }
            // Active Calories
            val cals = client.readRecords(ReadRecordsRequest(ActiveCaloriesBurnedRecord::class, timeFilter))
            for (record in cals.records) {
                telemetry.add(
                    buildRangeRecord(
                        type = "active_energy",
                        value = record.energy.inKilocalories,
                        unit = "kcal",
                        recStartTime = record.startTime.toEpochMilli(),
                        recEndTime = record.endTime.toEpochMilli(),
                        rawPackage = record.metadata.dataOrigin.packageName,
                        extId = record.metadata.id,
                        semantics = "interval_delta"
                    )
                )
            }
            // Heart Rate (5-minute downsampled)
            val hr = client.readRecords(ReadRecordsRequest(HeartRateRecord::class, timeFilter))
            val rawLocalHr = mutableListOf<Triple<Long, Double, String>>()
            for (record in hr.records) {
                val dev = record.metadata.dataOrigin.packageName
                for (sample in record.samples) {
                    val bpm = sample.beatsPerMinute.toDouble()
                    if (bpm in 30.0..240.0) {
                        rawLocalHr.add(Triple(sample.time.toEpochMilli(), bpm, dev))
                    }
                }
            }
            val fiveMinMs = 5 * 60 * 1000L
            val localHrBuckets = rawLocalHr.groupBy {
                (it.first / fiveMinMs) * fiveMinMs
            }
            for ((bucketEpoch, samplesInBucket) in localHrBuckets) {
                val primaryRawDevice = samplesInBucket.first().third
                val avgBpm = Math.round((samplesInBucket.map { it.second }.average()) * 10.0) / 10.0
                val extId = "hr_local_${primaryRawDevice}_$bucketEpoch"
                telemetry.add(
                    buildRangeRecord(
                        type = "heart_rate",
                        value = avgBpm,
                        unit = "bpm",
                        recStartTime = bucketEpoch,
                        recEndTime = bucketEpoch + fiveMinMs,
                        rawPackage = primaryRawDevice,
                        extId = extId,
                        semantics = "interval_avg"
                    )
                )
            }
            // Hydration
            val hyd = client.readRecords(ReadRecordsRequest(HydrationRecord::class, timeFilter))
            for (record in hyd.records) {
                telemetry.add(
                    buildRangeRecord(
                        type = "hydration",
                        value = record.volume.inMilliliters,
                        unit = "ml",
                        recStartTime = record.startTime.toEpochMilli(),
                        recEndTime = record.endTime.toEpochMilli(),
                        rawPackage = record.metadata.dataOrigin.packageName,
                        extId = record.metadata.id,
                        semantics = "interval_delta"
                    )
                )
            }
        } catch (e: Exception) {
            android.util.Log.w("HealthConnectManager", "Error querying date range Health Connect records", e)
        }
        return telemetry
    }
}
