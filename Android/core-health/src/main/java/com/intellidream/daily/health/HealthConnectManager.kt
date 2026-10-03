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

    /**
     * Reads all local health telemetry from Health Connect for a specific target date.
     * Captures steps, intraday heart rate samples, sleep stages, active calories, SpO2, and HRV.
     */
    suspend fun fetchTelemetryForDate(targetDate: Date): List<HealthTelemetryRecord> {
        val client = healthConnectClient ?: return emptyList()

        val cal = Calendar.getInstance().apply {
            time = targetDate
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }

        // Window: D-1 18:00 to D 23:59:59 (covers nocturnal sleep onset from previous evening)
        val startTime = Instant.ofEpochMilli(cal.timeInMillis).minus(6, ChronoUnit.HOURS)
        val endTime = Instant.ofEpochMilli(cal.timeInMillis).plus(24, ChronoUnit.HOURS)
        val timeFilter = TimeRangeFilter.between(startTime, endTime)

        val telemetry = mutableListOf<HealthTelemetryRecord>()

        try {
            // 1. Steps
            val stepsResponse = client.readRecords(
                ReadRecordsRequest(
                    recordType = StepsRecord::class,
                    timeRangeFilter = timeFilter
                )
            )
            for (record in stepsResponse.records) {
                telemetry.add(
                    HealthTelemetryRecord(
                        userId = "local_health_connect",
                        type = "steps",
                        value = record.count.toDouble(),
                        unit = "count",
                        startTime = record.startTime.toEpochMilli(),
                        endTime = record.endTime.toEpochMilli(),
                        sourceDevice = record.metadata.dataOrigin.packageName
                    )
                )
            }

            // 2. Heart Rate
            val hrResponse = client.readRecords(
                ReadRecordsRequest(
                    recordType = HeartRateRecord::class,
                    timeRangeFilter = timeFilter
                )
            )
            for (record in hrResponse.records) {
                for (sample in record.samples) {
                    telemetry.add(
                        HealthTelemetryRecord(
                            userId = "local_health_connect",
                            type = "heart_rate",
                            value = sample.beatsPerMinute.toDouble(),
                            unit = "bpm",
                            startTime = sample.time.toEpochMilli(),
                            endTime = sample.time.toEpochMilli(),
                            sourceDevice = record.metadata.dataOrigin.packageName
                        )
                    )
                }
            }

            // 3. Resting Heart Rate
            val rhrResponse = client.readRecords(
                ReadRecordsRequest(
                    recordType = RestingHeartRateRecord::class,
                    timeRangeFilter = timeFilter
                )
            )
            for (record in rhrResponse.records) {
                telemetry.add(
                    HealthTelemetryRecord(
                        userId = "local_health_connect",
                        type = "resting_heart_rate",
                        value = record.beatsPerMinute.toDouble(),
                        unit = "bpm",
                        startTime = record.time.toEpochMilli(),
                        endTime = record.time.toEpochMilli(),
                        sourceDevice = record.metadata.dataOrigin.packageName
                    )
                )
            }

            // 4. Sleep Sessions & Granular Stages
            val sleepResponse = client.readRecords(
                ReadRecordsRequest(
                    recordType = SleepSessionRecord::class,
                    timeRangeFilter = timeFilter
                )
            )
            for (record in sleepResponse.records) {
                val dev = record.metadata.dataOrigin.packageName
                // If granular stages are present
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
                        val durMin = ChronoUnit.MINUTES.between(stage.startTime, stage.endTime).toDouble()
                        telemetry.add(
                            HealthTelemetryRecord(
                                userId = "local_health_connect",
                                type = stageTypeStr,
                                value = durMin,
                                unit = "minutes",
                                startTime = stage.startTime.toEpochMilli(),
                                endTime = stage.endTime.toEpochMilli(),
                                sourceDevice = dev
                            )
                        )
                    }
                } else {
                    // Aggregate sleep session record
                    val durMin = ChronoUnit.MINUTES.between(record.startTime, record.endTime).toDouble()
                    telemetry.add(
                        HealthTelemetryRecord(
                            userId = "local_health_connect",
                            type = "sleep",
                            value = durMin,
                            unit = "minutes",
                            startTime = record.startTime.toEpochMilli(),
                            endTime = record.endTime.toEpochMilli(),
                            sourceDevice = dev
                        )
                    )
                }
            }

            // 5. Active Calories Burned
            val calResponse = client.readRecords(
                ReadRecordsRequest(
                    recordType = ActiveCaloriesBurnedRecord::class,
                    timeRangeFilter = timeFilter
                )
            )
            for (record in calResponse.records) {
                telemetry.add(
                    HealthTelemetryRecord(
                        userId = "local_health_connect",
                        type = "active_energy",
                        value = record.energy.inKilocalories,
                        unit = "kcal",
                        startTime = record.startTime.toEpochMilli(),
                        endTime = record.endTime.toEpochMilli(),
                        sourceDevice = record.metadata.dataOrigin.packageName
                    )
                )
            }

            // 6. Oxygen Saturation (SpO2)
            val spo2Response = client.readRecords(
                ReadRecordsRequest(
                    recordType = OxygenSaturationRecord::class,
                    timeRangeFilter = timeFilter
                )
            )
            for (record in spo2Response.records) {
                telemetry.add(
                    HealthTelemetryRecord(
                        userId = "local_health_connect",
                        type = "oxygen_saturation",
                        value = record.percentage.value,
                        unit = "%",
                        startTime = record.time.toEpochMilli(),
                        endTime = record.time.toEpochMilli(),
                        sourceDevice = record.metadata.dataOrigin.packageName
                    )
                )
            }

            // 7. Heart Rate Variability (RMSSD)
            val hrvResponse = client.readRecords(
                ReadRecordsRequest(
                    recordType = HeartRateVariabilityRmssdRecord::class,
                    timeRangeFilter = timeFilter
                )
            )
            for (record in hrvResponse.records) {
                telemetry.add(
                    HealthTelemetryRecord(
                        userId = "local_health_connect",
                        type = "hrv_rmssd",
                        value = record.heartRateVariabilityMillis,
                        unit = "ms",
                        startTime = record.time.toEpochMilli(),
                        endTime = record.time.toEpochMilli(),
                        sourceDevice = record.metadata.dataOrigin.packageName
                    )
                )
            }

            // 8. Hydration
            val hydResponse = client.readRecords(
                ReadRecordsRequest(
                    recordType = HydrationRecord::class,
                    timeRangeFilter = timeFilter
                )
            )
            for (record in hydResponse.records) {
                telemetry.add(
                    HealthTelemetryRecord(
                        userId = "local_health_connect",
                        type = "hydration",
                        value = record.volume.inMilliliters,
                        unit = "ml",
                        startTime = record.startTime.toEpochMilli(),
                        endTime = record.endTime.toEpochMilli(),
                        sourceDevice = record.metadata.dataOrigin.packageName
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

        try {
            // Steps
            val steps = client.readRecords(ReadRecordsRequest(StepsRecord::class, timeFilter))
            for (record in steps.records) {
                telemetry.add(
                    HealthTelemetryRecord(
                        userId = "local_health_connect",
                        type = "steps",
                        value = record.count.toDouble(),
                        unit = "count",
                        startTime = record.startTime.toEpochMilli(),
                        endTime = record.endTime.toEpochMilli(),
                        sourceDevice = record.metadata.dataOrigin.packageName
                    )
                )
            }
            // Sleep Sessions
            val sleep = client.readRecords(ReadRecordsRequest(SleepSessionRecord::class, timeFilter))
            for (record in sleep.records) {
                val durMin = ChronoUnit.MINUTES.between(record.startTime, record.endTime).toDouble()
                telemetry.add(
                    HealthTelemetryRecord(
                        userId = "local_health_connect",
                        type = "sleep",
                        value = durMin,
                        unit = "minutes",
                        startTime = record.startTime.toEpochMilli(),
                        endTime = record.endTime.toEpochMilli(),
                        sourceDevice = record.metadata.dataOrigin.packageName
                    )
                )
            }
            // Active Calories
            val cals = client.readRecords(ReadRecordsRequest(ActiveCaloriesBurnedRecord::class, timeFilter))
            for (record in cals.records) {
                telemetry.add(
                    HealthTelemetryRecord(
                        userId = "local_health_connect",
                        type = "active_energy",
                        value = record.energy.inKilocalories,
                        unit = "kcal",
                        startTime = record.startTime.toEpochMilli(),
                        endTime = record.endTime.toEpochMilli(),
                        sourceDevice = record.metadata.dataOrigin.packageName
                    )
                )
            }
            // Heart Rate
            val hr = client.readRecords(ReadRecordsRequest(HeartRateRecord::class, timeFilter))
            for (record in hr.records) {
                for (sample in record.samples) {
                    telemetry.add(
                        HealthTelemetryRecord(
                            userId = "local_health_connect",
                            type = "heart_rate",
                            value = sample.beatsPerMinute.toDouble(),
                            unit = "bpm",
                            startTime = sample.time.toEpochMilli(),
                            endTime = sample.time.toEpochMilli(),
                            sourceDevice = record.metadata.dataOrigin.packageName
                        )
                    )
                }
            }
            // Hydration
            val hyd = client.readRecords(ReadRecordsRequest(HydrationRecord::class, timeFilter))
            for (record in hyd.records) {
                telemetry.add(
                    HealthTelemetryRecord(
                        userId = "local_health_connect",
                        type = "hydration",
                        value = record.volume.inMilliliters,
                        unit = "ml",
                        startTime = record.startTime.toEpochMilli(),
                        endTime = record.endTime.toEpochMilli(),
                        sourceDevice = record.metadata.dataOrigin.packageName
                    )
                )
            }
        } catch (e: Exception) {
            android.util.Log.w("HealthConnectManager", "Error querying date range Health Connect records", e)
        }
        return telemetry
    }
}
