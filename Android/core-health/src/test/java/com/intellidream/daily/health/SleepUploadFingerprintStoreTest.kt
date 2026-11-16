package com.intellidream.daily.health

import com.intellidream.daily.model.HealthSleepSessionRecord
import com.intellidream.daily.model.SleepStageRecord
import com.intellidream.daily.model.SleepStageType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.TimeZone

class SleepUploadFingerprintStoreTest {

    @Test
    fun testPersistenceUserIsolationPruningAndStageReclassification() {
        val utc = TimeZone.getTimeZone("UTC")
        val refMs = 1_794_744_000_000L // 2026-11-15T12:00:00Z
        val startMs = 1_794_704_640_000L
        val midMs = startMs + 3_600_000L
        val endMs = startMs + 7_200_000L

        val sessionA = HealthSleepSessionRecord(
            id = "sleep_u1_2026-11-15_primary_sleep_pixel_watch_5",
            userId = "user-a",
            localDate = "2026-11-15",
            sessionType = "primary_sleep",
            sourceDeviceKey = "Pixel Watch 5",
            hostDeviceName = "Trapper",
            startTime = startMs,
            endTime = endMs,
            durationSeconds = 7200,
            timeInBedSeconds = 7200,
            deepSeconds = 3600,
            remSeconds = 0,
            lightSeconds = 3600,
            awakeSeconds = 0,
            stages = listOf(
                SleepStageRecord(id = "s1", stageType = SleepStageType.DEEP, startTime = startMs, endTime = midMs),
                SleepStageRecord(id = "s2", stageType = SleepStageType.LIGHT, startTime = midMs, endTime = endMs)
            ),
            sourcePriority = 1
        )

        val fp1 = SleepUploadFingerprintStore.computeFingerprint(listOf(sessionA))
        assertTrue(fp1.startsWith("v2|"))
        assertEquals(fp1, SleepUploadFingerprintStore.computeFingerprint(listOf(sessionA)))

        // Saving today + stale 20-day-old entry prunes the stale entry immediately
        val (savedMap, persistedJson) = SleepUploadFingerprintStore.saveEntryToJson(
            dateKey = "2026-11-15",
            fingerprint = fp1,
            existing = mapOf("2026-10-20" to "v2|stale"),
            userId = "User-A",
            referenceTimeMs = refMs,
            timeZone = utc
        )
        assertEquals(fp1, savedMap["2026-11-15"])
        assertNull(savedMap["2026-10-20"])
        assertTrue(!persistedJson.isNullOrBlank())

        // Simulated cold launch loads persisted fingerprint for matching user (case-insensitive)
        val (reloadedMap, _) = SleepUploadFingerprintStore.loadFromJson(
            rawJson = persistedJson,
            userId = "user-a",
            referenceTimeMs = refMs,
            timeZone = utc
        )
        assertEquals(fp1, reloadedMap["2026-11-15"])

        // User isolation: switching users discards cached entries
        val (otherMap, otherJson) = SleepUploadFingerprintStore.loadFromJson(
            rawJson = persistedJson,
            userId = "user-b",
            referenceTimeMs = refMs,
            timeZone = utc
        )
        assertTrue(otherMap.isEmpty())
        assertNull(otherJson)

        // Stage reclassification invalidates fingerprint even with identical duration & stage count
        val reclassified = sessionA.copy(
            remSeconds = 3600,
            lightSeconds = 0,
            stages = listOf(
                SleepStageRecord(id = "s1", stageType = SleepStageType.DEEP, startTime = startMs, endTime = midMs),
                SleepStageRecord(id = "s2", stageType = SleepStageType.REM, startTime = midMs, endTime = endMs)
            )
        )
        val fp2 = SleepUploadFingerprintStore.computeFingerprint(listOf(reclassified))
        assertNotEquals(fp1, fp2)

        // Removing the sole entry yields an empty map and null JSON payload
        val (afterRemove, afterRemoveJson) = SleepUploadFingerprintStore.removeEntryToJson(
            dateKey = "2026-11-15",
            existing = reloadedMap,
            userId = "user-a",
            referenceTimeMs = refMs,
            timeZone = utc
        )
        assertTrue(afterRemove.isEmpty())
        assertNull(afterRemoveJson)
    }

    @Test
    fun testShouldInvalidateStaleRemoteSleep() {
        val startMs = 1_794_787_560_000L // 2026-11-16T00:06:00Z
        val staleEndMs = startMs + 25_680_000L
        val fullEndMs = startMs + 29_160_000L

        val fullLocal = HealthSleepSessionRecord(
            id = "sleep_u1_2026-11-16_primary_sleep_pixel_watch_5",
            userId = "u1",
            localDate = "2026-11-16",
            sessionType = "primary_sleep",
            sourceDeviceKey = "Pixel Watch 5",
            hostDeviceName = "Trapper",
            startTime = startMs,
            endTime = fullEndMs,
            durationSeconds = 28200,
            timeInBedSeconds = 29160,
            deepSeconds = 3660,
            remSeconds = 7380,
            lightSeconds = 17160,
            awakeSeconds = 960,
            stages = listOf(
                SleepStageRecord(id = "s1", stageType = SleepStageType.DEEP, startTime = startMs, endTime = startMs + 3660_000L),
                SleepStageRecord(id = "s2", stageType = SleepStageType.REM, startTime = startMs + 3660_000L, endTime = fullEndMs)
            ),
            sourcePriority = 2
        )

        val staleRemote = fullLocal.copy(
            hostDeviceName = "Radar",
            endTime = staleEndMs,
            durationSeconds = 24540,
            timeInBedSeconds = 25680,
            deepSeconds = 3600,
            remSeconds = 5700,
            lightSeconds = 15240,
            awakeSeconds = 1140,
            stages = listOf(
                SleepStageRecord(id = "r1", stageType = SleepStageType.LIGHT, startTime = startMs, endTime = staleEndMs)
            )
        )

        // Exact match -> false (zero redundant uploads)
        assertFalse(SleepUploadFingerprintStore.shouldInvalidateStaleRemoteSleep(listOf(fullLocal), listOf(fullLocal)))
        // Network error (null) -> false
        assertFalse(SleepUploadFingerprintStore.shouldInvalidateStaleRemoteSleep(listOf(fullLocal), null))
        // Empty remote -> true
        assertTrue(SleepUploadFingerprintStore.shouldInvalidateStaleRemoteSleep(listOf(fullLocal), emptyList()))
        // Remote truncated by peer device (1h35m vs 2h3m) -> true (self-heal)
        assertTrue(SleepUploadFingerprintStore.shouldInvalidateStaleRemoteSleep(listOf(fullLocal), listOf(staleRemote)))
    }
}
