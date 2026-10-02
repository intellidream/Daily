package com.intellidream.daily.health

import com.intellidream.daily.model.DeviceSource
import com.intellidream.daily.model.HourlyStepBucket
import com.intellidream.daily.model.IntradayHeartRatePoint
import com.intellidream.daily.model.MonkeyMood
import com.intellidream.daily.model.StressLevel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Calendar
import java.util.Date
import kotlin.math.abs

/**
 * Unit tests verifying clinical stress calculations and parity with iOS StressEngineTests.
 */
class StressAnalysisEngineTest {

    @Test
    fun testHrvSigmoidScoring() {
        val baseline = 45.0

        // Very high HRV (e.g. 80ms) should yield low stress (< 25, Restful)
        val highHrvScore = StressAnalysisEngine.scoreFromHrv(hrv = 80.0, baseline = baseline)
        assertTrue(highHrvScore < 25.0)

        // Exact baseline HRV (45ms) should yield ~50 (neutral midpoint)
        val baselineScore = StressAnalysisEngine.scoreFromHrv(hrv = 45.0, baseline = baseline)
        assertTrue(abs(baselineScore - 50.0) < 0.1)

        // Very low HRV (e.g. 15ms) should yield high stress (> 75, High)
        val lowHrvScore = StressAnalysisEngine.scoreFromHrv(hrv = 15.0, baseline = baseline)
        assertTrue(lowHrvScore > 75.0)
    }

    @Test
    fun testSedentaryHeartRateElevation() {
        val cal = Calendar.getInstance()
        val today = Date()

        // A day with elevated sedentary HR (90 bpm vs 60 bpm baseline) and low steps
        val restingBpm = 60.0
        val hrv = 30.0 // Suppressed HRV

        val hour = cal.get(Calendar.HOUR_OF_DAY)
        val hrPoints = listOf(
            IntradayHeartRatePoint(timestamp = today.time, bpm = 92.0)
        )
        val stepBuckets = listOf(
            HourlyStepBucket(id = hour, hour = hour, steps = 40)
        )

        val calculation = StressAnalysisEngine.calculateStress(
            targetDate = today,
            hrvMs = hrv,
            hrTelemetry = hrPoints,
            hourlySteps = stepBuckets,
            restingBpm = restingBpm,
            priorSleepScore = 65,
            calendar = cal
        )

        assertNotNull(calculation)
        val (result, _) = calculation!!
        assertTrue(result.currentScore > 50)
        assertTrue(result.currentLevel == StressLevel.MODERATE || result.currentLevel == StressLevel.HIGH)
        assertTrue(result.sympatheticPercent > result.parasympatheticPercent)
    }

    @Test
    fun testPeakRecoveryYieldsZenState() {
        val cal = Calendar.getInstance()
        val today = Date()
        val hour = cal.get(Calendar.HOUR_OF_DAY)

        val hrPoints = listOf(
            IntradayHeartRatePoint(timestamp = today.time, bpm = 56.0)
        )
        val stepBuckets = listOf(
            HourlyStepBucket(id = hour, hour = hour, steps = 120)
        )

        val calculation = StressAnalysisEngine.calculateStress(
            targetDate = today,
            hrvMs = 75.0,
            hrTelemetry = hrPoints,
            hourlySteps = stepBuckets,
            restingBpm = 54.0,
            priorSleepScore = 92,
            calendar = cal
        )

        assertNotNull(calculation)
        val (result, _) = calculation!!
        assertTrue(result.currentScore <= 25)
        assertEquals(StressLevel.RESTFUL, result.currentLevel)
        assertEquals(MonkeyMood.ZEN, result.monkeyMood)
        assertTrue(result.parasympatheticPercent >= 75)
    }

    @Test
    fun testMissingBiometricsReturnsNull() {
        val today = Date()

        // No HRV and no intraday heart rate samples
        val calculation = StressAnalysisEngine.calculateStress(
            targetDate = today,
            hrvMs = null,
            hrTelemetry = emptyList(),
            hourlySteps = emptyList(),
            restingBpm = null,
            priorSleepScore = null
        )

        assertNull("Missing biometric telemetry must return null instead of synthesizing fake stress", calculation)
    }

    @Test
    fun testDeviceClassificationAndVirtualEngineFiltering() {
        val appleWatch = DeviceSource.from("Apple Watch Ultra 2")
        assertEquals(DeviceSource.AppleWatch, appleWatch)
        assertFalse(appleWatch.isVirtualEngine)

        val ouraRing = DeviceSource.from("Oura Ring Gen 3")
        assertEquals(DeviceSource.Oura, ouraRing)
        assertFalse(ouraRing.isVirtualEngine)

        val amazfit = DeviceSource.from("Amazfit Balance")
        assertEquals(DeviceSource.Amazfit, amazfit)
        assertFalse(amazfit.isVirtualEngine)

        // Virtual engines (must be flagged as isVirtualEngine)
        assertTrue(DeviceSource.from("StressWatch Model").isVirtualEngine)
        assertTrue(DeviceSource.from("StressWatch").isVirtualEngine)
        assertTrue(DeviceSource.from("Daily Biometric Engine").isVirtualEngine)
        assertTrue(DeviceSource.from("computed").isVirtualEngine)
        assertTrue(DeviceSource.from("bubbles").isVirtualEngine)
        assertTrue(DeviceSource.from("Unknown").isVirtualEngine)
    }
}
