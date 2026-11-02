package com.intellidream.daily.health

import com.intellidream.daily.model.HealthTelemetryRecord
import com.intellidream.daily.model.SleepSession
import com.intellidream.daily.model.SleepStageRecord
import com.intellidream.daily.model.SleepStageType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Calendar
import java.util.Date

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
        val dateKey = "2026-11-02"

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
}
