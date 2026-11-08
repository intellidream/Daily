package com.intellidream.daily.model

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.ZoneOffset

class SleepModelsTest {

    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

    @Test
    fun testTimestampSerializerParsesIsoWithoutZCorrectly() {
        val rawNoZ = "2026-11-08T00:06:59.000"
        val epochMs = TimestampSerializer.parseIsoToEpoch(rawNoZ)

        val instant = Instant.ofEpochMilli(epochMs).atZone(ZoneOffset.UTC)
        assertEquals(2026, instant.year)
        assertEquals(11, instant.monthValue)
        assertEquals(8, instant.dayOfMonth)
        assertEquals(0, instant.hour)
        assertEquals(6, instant.minute)
        assertEquals(59, instant.second)

        // Ensure it did NOT truncate to midnight
        val midnightMs = TimestampSerializer.parseIsoToEpoch("2026-11-08")
        assertNotEquals(midnightMs, epochMs)
    }

    @Test
    fun testTimestampSerializerParsesSpaceSeparatedIso() {
        val rawSpace = "2026-11-08 07:19:59"
        val epochMs = TimestampSerializer.parseIsoToEpoch(rawSpace)

        val instant = Instant.ofEpochMilli(epochMs).atZone(ZoneOffset.UTC)
        assertEquals(7, instant.hour)
        assertEquals(19, instant.minute)
        assertEquals(59, instant.second)
    }

    @Test
    fun testSleepStageRecordDeserialization() {
        val stageJson = """
            {
                "id": "test-stage-1",
                "stage_type": "Awake",
                "start_time": "2026-11-08T00:06:59.000",
                "end_time": "2026-11-08T00:23:59.000",
                "duration_seconds": 1020,
                "source_device": "Oura Ring"
            }
        """.trimIndent()

        val record = json.decodeFromString<SleepStageRecord>(stageJson)
        assertEquals("test-stage-1", record.id)
        assertEquals(SleepStageType.AWAKE, record.stageType)
        assertTrue(record.startTime > 0)
        assertTrue(record.endTime > record.startTime)
        assertEquals(1020.0, (record.endTime - record.startTime) / 1000.0, 0.001)
        assertEquals(17.0, record.durationMinutes, 0.001)
    }

    @Test
    fun testSleepStageTypeCaseInsensitive() {
        val stageJsonLower = """
            {
                "id": "test-stage-2",
                "stage_type": "rem",
                "start_time": "2026-11-08T01:00:00Z",
                "end_time": "2026-11-08T01:30:00Z"
            }
        """.trimIndent()

        val record = json.decodeFromString<SleepStageRecord>(stageJsonLower)
        assertEquals(SleepStageType.REM, record.stageType)
    }
}
