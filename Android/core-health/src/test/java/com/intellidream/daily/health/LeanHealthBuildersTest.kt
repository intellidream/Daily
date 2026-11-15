package com.intellidream.daily.health

import com.intellidream.daily.model.CanonicalCardiovascularSummary
import com.intellidream.daily.model.CanonicalHeartRateZones
import com.intellidream.daily.model.HealthDailySummaryRecord
import com.intellidream.daily.model.HealthDailyVitalsRecord
import com.intellidream.daily.model.HealthSleepSessionRecord
import com.intellidream.daily.model.HealthSourceRecord
import com.intellidream.daily.model.HealthTelemetryRecord
import com.intellidream.daily.model.HeartRateZone
import com.intellidream.daily.model.HourlyStepBucket
import com.intellidream.daily.model.IntradayHeartRatePoint
import com.intellidream.daily.model.SleepSession
import com.intellidream.daily.model.SleepStageRecord
import com.intellidream.daily.model.SleepStageType
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.util.Calendar
import java.util.Locale

class LeanHealthBuildersTest {

    @Test
    fun testLeanHeartRate5MinBucketing() {
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val baseMs = cal.timeInMillis
        val userId = "test-user-1"
        val dateKey = String.format(
            Locale.US,
            "%04d-%02d-%02d",
            cal.get(Calendar.YEAR),
            cal.get(Calendar.MONTH) + 1,
            cal.get(Calendar.DAY_OF_MONTH)
        )

        // 10:01 (601m), 10:03 (603m), 10:04 (604m) -> bucket 600
        // 10:07 (607m) -> bucket 605
        val samples = listOf(
            HealthTelemetryRecord(
                userId = userId,
                type = "heart_rate",
                value = 60.0,
                unit = "bpm",
                startTime = baseMs + 601 * 60 * 1000L,
                sourceDevice = "Pixel Watch 5"
            ),
            HealthTelemetryRecord(
                userId = userId,
                type = "heart_rate",
                value = 70.0,
                unit = "bpm",
                startTime = baseMs + 603 * 60 * 1000L,
                sourceDevice = "Pixel Watch 5"
            ),
            HealthTelemetryRecord(
                userId = userId,
                type = "heart_rate",
                value = 80.0,
                unit = "bpm",
                startTime = baseMs + 604 * 60 * 1000L,
                sourceDevice = "Pixel Watch 5"
            ),
            HealthTelemetryRecord(
                userId = userId,
                type = "heart_rate",
                value = 65.0,
                unit = "bpm",
                startTime = baseMs + 607 * 60 * 1000L,
                sourceDevice = "Pixel Watch 5"
            )
        )

        val buckets = HealthDataRepository.groupIntradayHeartRateIntoBuckets(
            records = samples,
            userId = userId,
            dateKey = dateKey
        )

        assertEquals(2, buckets.size)
        val b600 = buckets.firstOrNull { it.bucketMinute == 600 }
        assertNotNull(b600)
        assertEquals(70, b600?.bpmAvg) // (60 + 70 + 80) / 3
        assertEquals(60, b600?.bpmMin)
        assertEquals(80, b600?.bpmMax)
        assertEquals(3, b600?.sampleCount)

        val b605 = buckets.firstOrNull { it.bucketMinute == 605 }
        assertNotNull(b605)
        assertEquals(65, b605?.bpmAvg)
        assertEquals(1, b605?.sampleCount)
    }

    @Test
    fun testLeanDailyVitalsBuilder() {
        val userId = "test-user-1"
        val dateKey = "2026-11-02"
        val now = System.currentTimeMillis()

        val telemetry = listOf(
            HealthTelemetryRecord(userId = userId, type = "steps", value = 8500.0, unit = "count", startTime = now, sourceDevice = "Pixel Watch 5"),
            HealthTelemetryRecord(userId = userId, type = "active_energy", value = 450.0, unit = "kcal", startTime = now, sourceDevice = "Pixel Watch 5"),
            HealthTelemetryRecord(userId = userId, type = "resting_heart_rate", value = 54.0, unit = "bpm", startTime = now, sourceDevice = "Pixel Watch 5"),
            HealthTelemetryRecord(userId = userId, type = "oxygen_saturation", value = 98.5, unit = "%", startTime = now, sourceDevice = "Pixel Watch 5")
        )

        val vitals = HealthDataRepository.buildLeanDailyVitalsRecords(
            records = telemetry,
            dateKey = dateKey,
            userId = userId,
            hostName = "Trapper"
        )

        assertEquals(1, vitals.size)
        val v = vitals[0]
        assertEquals(8500, v.steps)
        assertEquals(450.0, v.activeKcal, 0.01)
        assertEquals(54, v.restingHeartRate)
        assertEquals(98.5, v.spo2 ?: 0.0, 0.01)
        assertEquals("Pixel Watch 5", v.sourceDeviceKey)
    }

    @Test
    fun testLeanSleepSessionBuilder() {
        val userId = "test-user-1"
        val dateKey = "2026-11-02"
        val now = System.currentTimeMillis()
        val eightHoursAgo = now - 8 * 3600 * 1000L

        val stages = listOf(
            SleepStageRecord(
                id = "s1",
                stageType = SleepStageType.DEEP,
                startTime = eightHoursAgo,
                endTime = eightHoursAgo + 3600 * 1000L,
                durationSeconds = 3600.0
            ),
            SleepStageRecord(
                id = "s2",
                stageType = SleepStageType.REM,
                startTime = eightHoursAgo + 3600 * 1000L,
                endTime = now,
                durationSeconds = 7 * 3600.0
            )
        )

        val session = SleepSession(
            startTime = eightHoursAgo,
            endTime = now,
            stages = stages,
            sourceDevice = "Pixel Watch 5"
        )

        val sleepRecords = HealthDataRepository.buildLeanSleepSessionRecords(
            primarySession = session,
            naps = emptyList(),
            dateKey = dateKey,
            userId = userId,
            hostName = "Trapper"
        )

        assertEquals(1, sleepRecords.size)
        val s = sleepRecords[0]
        assertEquals("primary_sleep", s.sessionType)
        assertEquals("Pixel Watch 5", s.sourceDeviceKey)
        assertEquals(3600, s.deepSeconds)
        assertTrue((s.sleepScore ?: 0) > 0)
    }

    @Test
    fun testRecencyFirstLatestHeartRateMidDayDeviceSwitch() {
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val dayStartMs = cal.timeInMillis
        val morning1100Iso = Instant.ofEpochMilli(dayStartMs + 11 * 3600_000L).toString()
        val afternoon1530Iso = Instant.ofEpochMilli(dayStartMs + 15 * 3600_000L + 30 * 60_000L).toString()

        val vitals = listOf(
            HealthDailyVitalsRecord(
                id = "v_oura",
                userId = "u1",
                localDate = "2026-11-05",
                sourceDeviceKey = "Oura Ring",
                latestHeartRate = 64,
                latestHrAt = morning1100Iso
            ),
            HealthDailyVitalsRecord(
                id = "v_pw5",
                userId = "u1",
                localDate = "2026-11-05",
                sourceDeviceKey = "Pixel Watch 5",
                latestHeartRate = 68,
                latestHrAt = morning1100Iso
            ),
            HealthDailyVitalsRecord(
                id = "v_opw3",
                userId = "u1",
                localDate = "2026-11-05",
                sourceDeviceKey = "OnePlus Watch 3",
                latestHeartRate = 82,
                latestHrAt = afternoon1530Iso
            )
        )

        val winner = HealthDataRepository.arbitrateLatestHeartRate(
            vitals = vitals,
            intradayBuckets = emptyList(),
            targetDateEpochMs = dayStartMs,
            sources = emptyList()
        )
        assertNotNull(winner)
        assertEquals(82.0, winner?.bpm ?: 0.0, 0.01)
        assertEquals("OnePlus Watch 3", winner?.sourceDevice)
    }

    @Test
    fun testSimultaneousWearHeartRateTieBreakAndCustomPriority() {
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val dayStartMs = cal.timeInMillis
        // Within 15-minute simultaneous window (15:25 vs 15:30)
        val t1525Iso = Instant.ofEpochMilli(dayStartMs + 15 * 3600_000L + 25 * 60_000L).toString()
        val t1530Iso = Instant.ofEpochMilli(dayStartMs + 15 * 3600_000L + 30 * 60_000L).toString()

        val vitals = listOf(
            HealthDailyVitalsRecord(
                id = "v_oura",
                userId = "u1",
                localDate = "2026-11-05",
                sourceDeviceKey = "Oura Ring",
                latestHeartRate = 71,
                latestHrAt = t1525Iso
            ),
            HealthDailyVitalsRecord(
                id = "v_opw3",
                userId = "u1",
                localDate = "2026-11-05",
                sourceDeviceKey = "OnePlus Watch 3",
                latestHeartRate = 74,
                latestHrAt = t1530Iso
            )
        )

        // Default priority: Oura Ring (#1) wins tie within 15-min simultaneous window
        val defaultWinner = HealthDataRepository.arbitrateLatestHeartRate(
            vitals = vitals,
            intradayBuckets = emptyList(),
            targetDateEpochMs = dayStartMs,
            sources = emptyList()
        )
        assertEquals("Oura Ring", defaultWinner?.sourceDevice)
        assertEquals(71.0, defaultWinner?.bpm ?: 0.0, 0.01)

        // Custom priority: OnePlus Watch 3 (#1), Oura Ring (#2)
        val customSources = listOf(
            HealthSourceRecord(
                id = "oneplus_watch_3",
                userId = "u1",
                platform = "Android",
                deviceKind = "watch",
                displayName = "OnePlus Watch 3",
                prioritySleep = 1,
                priorityActivity = 1,
                isCustomPriority = true
            ),
            HealthSourceRecord(
                id = "oura_ring",
                userId = "u1",
                platform = "iOS",
                deviceKind = "ring",
                displayName = "Oura Ring",
                prioritySleep = 2,
                priorityActivity = 2,
                isCustomPriority = true
            )
        )
        val customWinner = HealthDataRepository.arbitrateLatestHeartRate(
            vitals = vitals,
            intradayBuckets = emptyList(),
            targetDateEpochMs = dayStartMs,
            sources = customSources
        )
        assertEquals("OnePlus Watch 3", customWinner?.sourceDevice)
        assertEquals(74.0, customWinner?.bpm ?: 0.0, 0.01)
    }

    @Test
    fun testHourlyActivityEnvelopeMidDaySwitchVsSimultaneousWear() {
        // Hour 9: Oura (520) + Pixel Watch 5 (500) worn simultaneously -> Oura (#1) wins 520 (no double-counting!)
        // Hour 10: Pixel Watch 5 (1200)
        // Hour 15: OnePlus Watch 3 (2300) worn in afternoon while morning devices sit on desk (0 steps)
        val vitals = listOf(
            HealthDailyVitalsRecord(
                id = "v_oura",
                userId = "u1",
                localDate = "2026-11-05",
                sourceDeviceKey = "Oura Ring",
                steps = 520,
                activeKcal = 25.0,
                hourlySteps = listOf(HourlyStepBucket(9, 9, 520))
            ),
            HealthDailyVitalsRecord(
                id = "v_pw5",
                userId = "u1",
                localDate = "2026-11-05",
                sourceDeviceKey = "Pixel Watch 5",
                steps = 1700,
                activeKcal = 80.0,
                hourlySteps = listOf(HourlyStepBucket(9, 9, 500), HourlyStepBucket(10, 10, 1200))
            ),
            HealthDailyVitalsRecord(
                id = "v_opw3",
                userId = "u1",
                localDate = "2026-11-05",
                sourceDeviceKey = "OnePlus Watch 3",
                steps = 2300,
                activeKcal = 110.0,
                hourlySteps = listOf(HourlyStepBucket(15, 15, 2300))
            )
        )

        val res = HealthDataRepository.arbitrateHourlyActivity(vitals, emptyList())
        // 520 (h9) + 1200 (h10) + 2300 (h15) = 4020 steps!
        assertEquals(4020, res.totalSteps)
        assertEquals("OnePlus Watch 3", res.sourceDevice)
    }

    @Test
    fun testRecencyFirstSpotVitalsSpo2() {
        val vitals = listOf(
            HealthDailyVitalsRecord(
                id = "v_oura",
                userId = "u1",
                localDate = "2026-11-05",
                sourceDeviceKey = "Oura Ring",
                spo2 = 97.5,
                vitalsTimestamps = mapOf("spo2" to "2026-11-05T07:00:00Z")
            ),
            HealthDailyVitalsRecord(
                id = "v_opw3",
                userId = "u1",
                localDate = "2026-11-05",
                sourceDeviceKey = "OnePlus Watch 3",
                spo2 = 99.0,
                vitalsTimestamps = mapOf("spo2" to "2026-11-05T16:10:00Z")
            )
        )

        val winner = HealthDataRepository.arbitrateSpotVital(vitals, "spo2", emptyList()) { it.spo2 }
        assertNotNull(winner)
        assertEquals(99.0, winner?.value ?: 0.0, 0.01)
        assertEquals("OnePlus Watch 3", winner?.sourceDevice)
    }

    @Test
    fun testArchivedCardiovascularCurvePreservedAfter7DayIntradayPrune() {
        val archivedCardio = CanonicalCardiovascularSummary(
            intradayHeartRate = listOf(
                IntradayHeartRatePoint(timestamp = 1_761_638_400_000L, bpm = 58.0, sourceDevice = "Oura Ring"),
                IntradayHeartRatePoint(timestamp = 1_761_652_800_000L, bpm = 74.0, sourceDevice = "Pixel Watch 5"),
                IntradayHeartRatePoint(timestamp = 1_761_667_200_000L, bpm = 92.0, sourceDevice = "Pixel Watch 5")
            ),
            restingHeartRateBpm = 54.0,
            averageHeartRateBpm = 75.0,
            maxHeartRateBpm = 92.0,
            minHeartRateBpm = 58.0,
            latestBpm = 92.0,
            latestSourceDevice = "Pixel Watch 5",
            heartRateZones = CanonicalHeartRateZones(restingMinutes = 600, fatBurnMinutes = 40, cardioMinutes = 5, peakMinutes = 0)
        )

        // All Devices mode: preserves full archived curve & stats when intraday buckets are empty
        val allDevices = HealthDataRepository.resolveArchivedCardiovascularFallback(archivedCardio, null)
        assertNotNull(allDevices)
        assertEquals(3, allDevices?.points?.size)
        assertEquals(75.0, allDevices?.averageBpm ?: 0.0, 0.01)
        assertEquals(58.0, allDevices?.minBpm ?: 0.0, 0.01)
        assertEquals(92.0, allDevices?.maxBpm ?: 0.0, 0.01)
        assertEquals(600, allDevices?.zones?.get(HeartRateZone.RESTING))
        assertEquals(54.0, allDevices?.restingBpm ?: 0.0, 0.01)

        // Per-device filter: preserves points recorded by Pixel Watch 5 and recalculates device stats
        val pw5Only = HealthDataRepository.resolveArchivedCardiovascularFallback(archivedCardio, "Pixel Watch 5")
        assertNotNull(pw5Only)
        assertEquals(2, pw5Only?.points?.size)
        assertEquals(83.0, pw5Only?.averageBpm ?: 0.0, 0.01)
        assertEquals(74.0, pw5Only?.minBpm ?: 0.0, 0.01)
        assertEquals(92.0, pw5Only?.maxBpm ?: 0.0, 0.01)

        // Device with zero archived points returns null cleanly
        val missingDevice = HealthDataRepository.resolveArchivedCardiovascularFallback(archivedCardio, "OnePlus Watch 3")
        assertNull(missingDevice)
    }

    @Test
    fun testScalarSleepAndSummaryProjectionsDecodeCleanly() {
        val json = Json { ignoreUnknownKeys = true }
        val scalarSleepJson = """
            {
              "id": "sleep_u1_2026-11-01_primary_sleep_oura_ring",
              "local_date": "2026-11-01",
              "session_type": "primary_sleep",
              "source_device_key": "Oura Ring",
              "start_time": "2026-10-31T22:30:00Z",
              "end_time": "2026-11-01T06:30:00Z",
              "duration_seconds": 26400,
              "sleep_score": 88,
              "deep_seconds": 5400,
              "rem_seconds": 6000,
              "light_seconds": 15000,
              "awake_seconds": 1800,
              "source_priority": 1,
              "is_user_selected": false
            }
        """.trimIndent()
        val sleep = json.decodeFromString<HealthSleepSessionRecord>(scalarSleepJson)
        assertTrue(sleep.stages.isEmpty())
        assertTrue(sleep.hasGranularSleepStages)
        assertTrue(sleep.toSleepSession().hasGranularHypnogram)

        val scalarSummaryJson = """
            {
              "id": "sum_1",
              "user_id": "u1",
              "local_date": "2026-11-01",
              "steps": 10420,
              "active_kcal": 480.5,
              "sleep_asleep_s": 26400,
              "sleep_score": 88,
              "stress_avg": 24,
              "rhr": 53.0,
              "hrv_sdnn": 51.2
            }
        """.trimIndent()
        val summary = json.decodeFromString<HealthDailySummaryRecord>(scalarSummaryJson)
        assertNull(summary.summary)
        assertEquals(10420, summary.steps)
        assertEquals(24, summary.stressAvg)
    }

    @Test
    fun testMultiPassRecencyAwareStageDeduplicationAndCoalescing() {
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val today = cal.time
        val bedtimeMs = cal.timeInMillis - 3600_000L // 23:00
        val pass1At = cal.timeInMillis + 3600_000L
        val pass2At = cal.timeInMillis + 18000_000L

        val telemetry = listOf(
            HealthTelemetryRecord(
                id = "p1_block",
                userId = "u1",
                type = "sleep_stage_light",
                value = 300.0 * 60.0,
                unit = "seconds",
                startTime = bedtimeMs,
                endTime = bedtimeMs + 5 * 3600_000L,
                sourceDevice = "Oura Ring",
                createdAt = pass1At
            ),
            HealthTelemetryRecord(
                id = "p2_deep",
                userId = "u1",
                type = "sleep_stage_deep",
                value = 2700.0,
                unit = "seconds",
                startTime = bedtimeMs + 3600_000L,
                endTime = bedtimeMs + 3600_000L + 2700_000L,
                sourceDevice = "Oura Ring",
                createdAt = pass2At
            ),
            HealthTelemetryRecord(
                id = "p2_rem_1",
                userId = "u1",
                type = "sleep_stage_rem",
                value = 2700.0,
                unit = "seconds",
                startTime = bedtimeMs + 3600_000L + 2700_000L,
                endTime = bedtimeMs + 3600_000L + 5400_000L,
                sourceDevice = "Oura Ring",
                createdAt = pass2At
            ),
            HealthTelemetryRecord(
                id = "p2_rem_2",
                userId = "u1",
                type = "sleep_stage_rem",
                value = 1800.0,
                unit = "seconds",
                startTime = bedtimeMs + 3600_000L + 5400_000L,
                endTime = bedtimeMs + 3600_000L + 7200_000L,
                sourceDevice = "Oura Ring",
                createdAt = pass2At
            ),
            HealthTelemetryRecord(
                id = "p2_light_tail",
                userId = "u1",
                type = "sleep_stage_light",
                value = 7200.0,
                unit = "seconds",
                startTime = bedtimeMs + 3600_000L + 7200_000L,
                endTime = bedtimeMs + 5 * 3600_000L,
                sourceDevice = "Oura Ring",
                createdAt = pass2At
            )
        )

        val result = SleepClusteringEngine.clusterSleep(targetDate = today, telemetry = telemetry)
        val primary = result.primarySession
        assertNotNull(primary)
        assertEquals(2700.0, primary!!.deepSeconds, 0.1)
        assertEquals(4500.0, primary.remSeconds, 0.1)
        assertEquals(10800.0, primary.lightSeconds, 0.1)
        assertEquals(4, primary.stages.size)
    }

    @Test
    fun testMergeLeanSleepSessionsAllowsReclassificationWhenFreshLocal() {
        val start = 1794704641000L
        val end = start + 38670_000L
        val remoteStages = (0 until 81).map { i ->
            SleepStageRecord(id = "r_$i", stageType = SleepStageType.LIGHT, startTime = start, endTime = start + 60_000L)
        }
        val localStages = (0 until 75).map { i ->
            SleepStageRecord(id = "l_$i", stageType = if (i < 20) SleepStageType.DEEP else SleepStageType.REM, startTime = start, endTime = start + 60_000L)
        }
        val remote = HealthSleepSessionRecord(
            id = "sleep_u1_2026-11-15_primary_sleep_oura_ring",
            userId = "u1",
            localDate = "2026-11-15",
            sessionType = "primary_sleep",
            sourceDeviceKey = "Oura Ring",
            hostDeviceName = "Schmitz",
            startTime = start,
            endTime = end,
            durationSeconds = 35460,
            timeInBedSeconds = 38670,
            deepSeconds = 5310,
            remSeconds = 5490,
            lightSeconds = 24660,
            awakeSeconds = 3210,
            stages = remoteStages,
            sourcePriority = 1,
            isUserSelected = true
        )
        val reclassifiedLocal = remote.copy(
            deepSeconds = 6480,
            remSeconds = 6420,
            lightSeconds = 22560,
            stages = localStages,
            isUserSelected = false
        )

        val merged = HealthDataRepository.mergeLeanSleepSessions(
            remote = listOf(remote),
            local = listOf(reclassifiedLocal),
            preferFreshLocal = true
        )
        assertEquals(1, merged.size)
        assertEquals(6480, merged[0].deepSeconds)
        assertEquals(6420, merged[0].remSeconds)
        assertEquals(75, merged[0].stages.size)
        assertTrue(merged[0].isUserSelected)

        // Guard against transient 13m partial read
        val truncatedLocal = remote.copy(durationSeconds = 780, stages = listOf(localStages.first()))
        val guarded = HealthDataRepository.mergeLeanSleepSessions(
            remote = listOf(remote),
            local = listOf(truncatedLocal),
            preferFreshLocal = true
        )
        assertEquals(35460, guarded[0].durationSeconds)
        assertEquals(81, guarded[0].stages.size)
    }
}
