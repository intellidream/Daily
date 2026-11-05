package com.intellidream.daily.health

import com.intellidream.daily.model.HealthDailyVitalsRecord
import com.intellidream.daily.model.HealthSourceRecord
import com.intellidream.daily.model.HealthTelemetryRecord
import com.intellidream.daily.model.HourlyStepBucket
import com.intellidream.daily.model.SleepSession
import com.intellidream.daily.model.SleepStageRecord
import com.intellidream.daily.model.SleepStageType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
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
}
