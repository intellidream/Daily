package com.intellidream.daily.health

import com.intellidream.daily.model.BreathingProtocol
import com.intellidream.daily.model.HourlyStepBucket
import com.intellidream.daily.model.IntradayHeartRatePoint
import com.intellidream.daily.model.IntradayStressPoint
import com.intellidream.daily.model.MonkeyMood
import com.intellidream.daily.model.StressAnalysisResult
import com.intellidream.daily.model.StressLevel
import java.util.Calendar
import java.util.Date
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.tanh

/**
 * Autonomic nervous system (ANS) stress estimation engine modeled after clinical HRV algorithms
 * and mobile biometric standards.
 * 1:1 Kotlin port of iOS DailyCore's StressAnalysisEngine.
 */
object StressAnalysisEngine {

    /** Default population benchmarks for healthy adults when personal longitudinal history is sparse. */
    const val DEFAULT_BASELINE_HRV: Double = 45.0 // ms SDNN
    const val DEFAULT_BASELINE_RHR: Double = 62.0 // bpm

    /**
     * Evaluates physiological telemetry and produces a unified [StressAnalysisResult]
     * along with an intraday hourly curve.
     */
    fun calculateStress(
        targetDate: Date,
        hrvMs: Double?,
        hrTelemetry: List<IntradayHeartRatePoint>,
        hourlySteps: List<HourlyStepBucket>,
        restingBpm: Double?,
        priorSleepScore: Int?,
        personalBaselineHrv: Double? = null,
        personalBaselineRhr: Double? = null,
        calendar: Calendar = Calendar.getInstance()
    ): Pair<StressAnalysisResult, List<IntradayStressPoint>> {

        val baselineHrv = personalBaselineHrv ?: DEFAULT_BASELINE_HRV
        val baselineRhr = restingBpm ?: personalBaselineRhr ?: DEFAULT_BASELINE_RHR
        val sleepScore = priorSleepScore ?: 80

        // 1. Build Hourly Map of Steps (to isolate physical movement vs sedentary arousal)
        val stepsByHour = mutableMapOf<Int, Int>()
        for (b in hourlySteps) {
            stepsByHour[b.hour] = b.steps
        }

        // 2. Group Heart Rate telemetry by hour of the day
        val calTarget = Calendar.getInstance().apply { time = targetDate }
        val hrByHour = mutableMapOf<Int, MutableList<Double>>()
        for (pt in hrTelemetry) {
            val calPt = Calendar.getInstance().apply { timeInMillis = pt.timestamp }
            if (isSameDay(calPt, calTarget)) {
                val hour = calPt.get(Calendar.HOUR_OF_DAY)
                hrByHour.getOrPut(hour) { mutableListOf() }.add(pt.bpm)
            }
        }

        // 3. Compute Hourly Intraday Stress Points (0 to current hour or full 24h if past date)
        val intraday = mutableListOf<IntradayStressPoint>()
        val calNow = Calendar.getInstance()
        val isToday = isSameDay(calNow, calTarget)
        val currentHour = calNow.get(Calendar.HOUR_OF_DAY)
        val maxHourToEvaluate = if (isToday) currentHour else 23

        val sleepPenalty = max(0.0, min(100.0, 100.0 - sleepScore.toDouble()))

        for (hour in 0..maxHourToEvaluate) {
            val steps = stepsByHour[hour] ?: 0
            val isSedentary = steps < 300 // Exclude hours with brisk walking/running

            val hrSamples = hrByHour[hour] ?: emptyList()
            val avgHr: Double? = if (hrSamples.isNotEmpty()) hrSamples.sum() / hrSamples.size.toDouble() else null

            // Hourly HRV estimation: if daytime samples exist or fallback to day baseline
            val hourHrv = hrvMs ?: baselineHrv

            // A. HRV Component (50% weight): High HRV -> Low Stress, Low HRV -> High Stress
            val hrvScore = scoreFromHrv(hrv = hourHrv, baseline = baselineHrv)

            // B. Heart Rate Elevation Component (30% weight)
            val hrScore: Double = if (avgHr != null && isSedentary) {
                val delta = max(0.0, avgHr - baselineRhr)
                min(100.0, (delta / 25.0) * 100.0)
            } else {
                hrvScore * 0.8
            }

            // C. Recovery factor (20% weight)
            val rawHourlyStress = (0.50 * hrvScore) + (0.30 * hrScore) + (0.20 * sleepPenalty)
            val finalHourlyScore = min(max(rawHourlyStress.roundToInt(), 5), 98)
            val level = StressLevel.from(finalHourlyScore)

            val hourCal = Calendar.getInstance().apply {
                time = targetDate
                set(Calendar.HOUR_OF_DAY, hour)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }

            intraday.add(
                IntradayStressPoint(
                    timestamp = hourCal.timeInMillis,
                    hour = hour,
                    score = finalHourlyScore,
                    level = level,
                    hrvMs = hourHrv,
                    heartRateBpm = avgHr,
                    isSedentary = isSedentary
                )
            )
        }

        // 4. Resolve Current / Master Stress Score
        val currentHrv = hrvMs ?: baselineHrv
        val currentHrvScore = scoreFromHrv(hrv = currentHrv, baseline = baselineHrv)

        // Derive recent sedentary HR
        val recentHr = hrTelemetry.lastOrNull()?.bpm
        val currentHrElevation: Double?
        val currentHrScore: Double
        if (recentHr != null) {
            val elevation = max(0.0, recentHr - baselineRhr)
            currentHrElevation = elevation
            currentHrScore = min(100.0, (elevation / 25.0) * 100.0)
        } else {
            currentHrElevation = null
            currentHrScore = currentHrvScore * 0.8
        }

        val currentScore: Int = if (intraday.isNotEmpty()) {
            intraday.last().score
        } else {
            val blended = (0.50 * currentHrvScore) + (0.30 * currentHrScore) + (0.20 * sleepPenalty)
            min(max(blended.roundToInt(), 10), 95)
        }

        val currentLevel = StressLevel.from(currentScore)

        // 5. Daily Aggregates
        val dailyAverage: Int = if (intraday.isNotEmpty()) {
            val sum = intraday.map { it.score }.sum()
            (sum.toDouble() / intraday.size).roundToInt()
        } else {
            currentScore
        }

        val peakPoint = intraday.maxByOrNull { it.score }
        val lowestPoint = intraday.minByOrNull { it.score }

        // 6. Autonomic Balance
        val parasympathetic = min(max(100 - currentScore, 10), 90)
        val sympathetic = 100 - parasympathetic

        // 7. HRV Delta Percentage
        val hrvDeltaPercent = if (hrvMs != null && baselineHrv > 0) {
            ((hrvMs - baselineHrv) / baselineHrv) * 100.0
        } else null

        // 8. Persona Mood & Guidance
        val mood = MonkeyMood.fromLevel(currentLevel)
        val breathing = BreathingProtocol.defaultForLevel(currentLevel)

        val result = StressAnalysisResult(
            currentScore = currentScore,
            currentLevel = currentLevel,
            dailyAverageScore = dailyAverage,
            peakHour = peakPoint?.hour,
            peakScore = peakPoint?.score,
            lowestHour = lowestPoint?.hour,
            lowestScore = lowestPoint?.score,
            parasympatheticPercent = parasympathetic,
            sympatheticPercent = sympathetic,
            baselineHrvMs = baselineHrv,
            currentHrvMs = hrvMs,
            hrvDeltaPercent = hrvDeltaPercent,
            restingHeartRateBpm = baselineRhr,
            currentSedentaryBpm = recentHr,
            heartRateElevationBpm = currentHrElevation,
            monkeyMood = mood,
            adviceQuote = mood.adviceQuote,
            recommendedBreathing = breathing,
            lastUpdated = System.currentTimeMillis()
        )

        return Pair(result, intraday)
    }

    // MARK: - Mathematical Sub-routines

    /**
     * Normalizes HRV using a sigmoid/tanh transfer function around baseline.
     * High HRV yields lower stress (< 30), while depressed HRV yields high stress (> 70).
     */
    fun scoreFromHrv(hrv: Double, baseline: Double): Double {
        if (baseline <= 0) return 50.0
        val z = (hrv - baseline) / 16.0
        // tanh(z) ranges from -1 to +1.
        // When z is +2 (high HRV, +32ms above baseline), tanh is ~0.96 -> Score = 50 - 45 = 5 (Deep Rest)
        // When z is -2 (low HRV, -32ms below baseline), tanh is ~ -0.96 -> Score = 50 + 45 = 95 (High Stress)
        val normalized = 50.0 - (tanh(z) * 45.0)
        return min(max(normalized, 0.0), 100.0)
    }

    private fun isSameDay(c1: Calendar, c2: Calendar): Boolean {
        return c1.get(Calendar.YEAR) == c2.get(Calendar.YEAR) &&
                c1.get(Calendar.DAY_OF_YEAR) == c2.get(Calendar.DAY_OF_YEAR)
    }
}
