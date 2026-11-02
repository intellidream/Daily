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

    @Test
    fun testRmssdAndActiveHourStabilityAndOuraParity() {
        val cal = Calendar.getInstance(java.util.TimeZone.getTimeZone("UTC")).apply {
            set(2026, Calendar.OCTOBER, 15, 12, 0, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val pastDay = cal.time

        fun tsAt(hour: Int, minute: Int = 15): Long {
            val c = (cal.clone() as Calendar).apply {
                set(Calendar.HOUR_OF_DAY, hour)
                set(Calendar.MINUTE, minute)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            return c.timeInMillis
        }

        val pwHr = listOf(
            IntradayHeartRatePoint(timestamp = tsAt(14), bpm = 82.0),
            IntradayHeartRatePoint(timestamp = tsAt(15), bpm = 81.0),
            IntradayHeartRatePoint(timestamp = tsAt(16), bpm = 105.0)
        )
        val steps = listOf(
            HourlyStepBucket(id = 14, hour = 14, steps = 90),
            HourlyStepBucket(id = 15, hour = 15, steps = 110),
            HourlyStepBucket(id = 16, hour = 16, steps = 550)
        )

        val pwCalc = StressAnalysisEngine.calculateStress(
            targetDate = pastDay,
            hrvMs = 70.0,
            isRmssd = true,
            hrTelemetry = pwHr,
            hourlySteps = steps,
            restingBpm = 61.0,
            priorSleepScore = 92,
            calendar = cal
        )
        assertNotNull(pwCalc)
        val pwResult = pwCalc!!.first
        assertTrue("Pixel Watch RMSSD 70ms must stay Calm (25..42), got ${pwResult.currentScore}", pwResult.currentScore in 25..42)

        val ouraHr = listOf(
            IntradayHeartRatePoint(timestamp = tsAt(4, 0), bpm = 55.0),
            IntradayHeartRatePoint(timestamp = tsAt(5, 0), bpm = 56.0),
            IntradayHeartRatePoint(timestamp = tsAt(6, 0), bpm = 55.0),
            IntradayHeartRatePoint(timestamp = tsAt(14), bpm = 82.0),
            IntradayHeartRatePoint(timestamp = tsAt(15), bpm = 81.0)
        )
        val ouraCalc = StressAnalysisEngine.calculateStress(
            targetDate = pastDay,
            hrvMs = null,
            isRmssd = false,
            hrTelemetry = ouraHr,
            hourlySteps = steps,
            restingBpm = null,
            priorSleepScore = 75,
            calendar = cal
        )
        assertNotNull(ouraCalc)
        val ouraResult = ouraCalc!!.first
        assertTrue(abs((ouraResult.restingHeartRateBpm ?: 0.0) - 61.0) <= 1.0)
        assertTrue("Oura Ring stress must stay Calm (25..44), got ${ouraResult.currentScore}", ouraResult.currentScore in 25..44)
        assertTrue("Oura and Pixel Watch must converge within 8 pts", abs(ouraResult.currentScore - pwResult.currentScore) <= 8)
    }
}
