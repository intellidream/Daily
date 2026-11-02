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
import kotlin.math.round
import kotlin.math.roundToInt
import kotlin.math.tanh

/**
 * Autonomic nervous system (ANS) stress estimation engine v2.0 modeled after clinical HRV algorithms
 * and mobile biometric standards.
 * Unified 1:1 with Supabase `health-engine` and Apple `DailyCore.StressAnalysisEngine`.
 */
object StressAnalysisEngine {

    /** Default population benchmarks for healthy adults when personal longitudinal history is sparse. */
    const val DEFAULT_BASELINE_HRV: Double = 45.0 // ms SDNN (Apple Watch / clinical short-term SDNN)
    const val DEFAULT_BASELINE_HRV_SDNN: Double = 45.0
    const val DEFAULT_BASELINE_HRV_RMSSD: Double = 62.0 // ms RMSSD (Wear OS / Fitbit / Oura nocturnal RMSSD)
    const val DEFAULT_BASELINE_RHR: Double = 60.0 // bpm

    /**
     * Evaluates physiological telemetry and produces a unified [StressAnalysisResult]
     * along with an intraday hourly curve, or null if no biometric telemetry is available for the day.
     */
    fun calculateStress(
        targetDate: Date,
        hrvMs: Double?,
        isRmssd: Boolean = false,
        hrTelemetry: List<IntradayHeartRatePoint>,
        hourlySteps: List<HourlyStepBucket>,
        restingBpm: Double?,
        priorSleepScore: Int?,
        personalBaselineHrv: Double? = null,
        personalBaselineRhr: Double? = null,
        calendar: Calendar = Calendar.getInstance()
    ): Pair<StressAnalysisResult, List<IntradayStressPoint>>? {

        val validHrv = hrvMs?.takeIf { it > 0.0 }

        // Guard against missing biometric telemetry:
        // Valid stress calculation requires at least one genuine physiological signal (HRV or heart rate samples).
        if (validHrv == null && hrTelemetry.isEmpty()) {
            return null
        }

        val metricDefaultHrv = if (isRmssd) DEFAULT_BASELINE_HRV_RMSSD else DEFAULT_BASELINE_HRV_SDNN
        val baselineHrv = personalBaselineHrv?.takeIf { it > 0.0 }?.let { round(it * 10.0) / 10.0 }
            ?: metricDefaultHrv

        val derivedRhr = deriveNocturnalRhr(hrTelemetry, targetDate, calendar)
        val baselineRhr = restingBpm?.takeIf { it > 0.0 }
            ?: derivedRhr
            ?: personalBaselineRhr?.takeIf { it > 0.0 }
            ?: DEFAULT_BASELINE_RHR

        val sleepScore = priorSleepScore?.takeIf { it > 0 } ?: 80

        // 1. Build Hourly Map of Steps (to isolate physical movement vs sedentary arousal)
        val stepsByHour = mutableMapOf<Int, Int>()
        for (b in hourlySteps) {
            stepsByHour[b.hour] = b.steps
        }

        // 2. Group Heart Rate telemetry by hour of the day
        val calTarget = (calendar.clone() as Calendar).apply { time = targetDate }
        val hrByHour = mutableMapOf<Int, MutableList<Double>>()
        for (pt in hrTelemetry) {
            val calPt = (calendar.clone() as Calendar).apply { timeInMillis = pt.timestamp }
            if (isSameDay(calPt, calTarget)) {
                val hour = calPt.get(Calendar.HOUR_OF_DAY)
                hrByHour.getOrPut(hour) { mutableListOf() }.add(pt.bpm)
            }
        }

        // 3. Compute Hourly Intraday Stress Points (0 to current hour or full 24h if past date)
        val intraday = mutableListOf<IntradayStressPoint>()
        val calNow = (calendar.clone() as Calendar).apply { timeInMillis = System.currentTimeMillis() }
        val isToday = isSameDay(calNow, calTarget)
        val currentHour = calNow.get(Calendar.HOUR_OF_DAY)
        val maxHourToEvaluate = if (isToday) currentHour else 23

        val sleepPenalty = max(0.0, min(100.0, 100.0 - sleepScore.toDouble()))
        val dayHrvScore: Double? = validHrv?.let { scoreFromHrv(hrv = it, baseline = baselineHrv) }
        var lastSedentaryHrScore: Double? = null
        var latestSedentaryHrBpm: Double? = null

        for (hour in 0..maxHourToEvaluate) {
            val steps = stepsByHour[hour] ?: 0
            val isSedentary = steps < 300 // Exclude hours with brisk walking/running

            val hrSamples = hrByHour[hour] ?: emptyList()
            // Only generate an intraday point if this hour had actual biometric samples
            if (hrSamples.isEmpty() && (validHrv == null || steps == 0)) {
                continue
            }
            val avgHr: Double? = if (hrSamples.isNotEmpty()) hrSamples.sum() / hrSamples.size.toDouble() else null

            // B. Calibrated Sedentary HR Arousal Component (with inertia carry-forward during movement hours)
            val hrScore: Double = when {
                avgHr != null && isSedentary -> {
                    val s = scoreFromSedentaryHr(avgHr = avgHr, baselineRhr = baselineRhr)
                    lastSedentaryHrScore = s
                    latestSedentaryHrBpm = avgHr
                    s
                }
                lastSedentaryHrScore != null -> 0.85 * lastSedentaryHrScore!! + 0.15 * 32.0
                dayHrvScore != null -> 0.70 * dayHrvScore + 0.30 * 32.0
                else -> 32.0
            }

            // C. Blended hourly stress (honest re-normalization when device has no HRV, e.g. Oura via HealthKit)
            val rawHourlyStress = if (dayHrvScore != null) {
                (0.45 * dayHrvScore) + (0.35 * hrScore) + (0.20 * sleepPenalty)
            } else {
                (0.70 * hrScore) + (0.30 * sleepPenalty)
            }

            val finalHourlyScore = min(max(rawHourlyStress.roundToInt(), 5), 98)
            val level = StressLevel.from(finalHourlyScore)

            val hourCal = (calendar.clone() as Calendar).apply {
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
                    hrvMs = validHrv,
                    heartRateBpm = avgHr?.let { round(it * 10.0) / 10.0 },
                    isSedentary = isSedentary
                )
            )
        }

        // 4. Resolve Current / Master Stress Score from genuine sedentary tone (immune to active-hour step collapse)
        val recentHr = hrTelemetry.lastOrNull()?.bpm
        val effectiveSedentaryBpm = latestSedentaryHrBpm ?: recentHr
        val currentHrElevation: Double? = effectiveSedentaryBpm?.let { max(0.0, it - baselineRhr) }

        val sedentaryPoints = intraday.filter { it.isSedentary && it.heartRateBpm != null }
        val currentScore: Int = when {
            sedentaryPoints.size >= 2 -> {
                val lastSed = sedentaryPoints[sedentaryPoints.size - 1].score.toDouble()
                val prevSed = sedentaryPoints[sedentaryPoints.size - 2].score.toDouble()
                (0.70 * lastSed + 0.30 * prevSed).roundToInt()
            }
            sedentaryPoints.size == 1 -> sedentaryPoints[0].score
            intraday.isNotEmpty() -> intraday.last().score
            else -> {
                val fallbackHrScore = when {
                    effectiveSedentaryBpm != null -> scoreFromSedentaryHr(effectiveSedentaryBpm, baselineRhr)
                    dayHrvScore != null -> 0.70 * dayHrvScore + 0.30 * 32.0
                    else -> 32.0
                }
                val blended = if (dayHrvScore != null) {
                    (0.45 * dayHrvScore) + (0.35 * fallbackHrScore) + (0.20 * sleepPenalty)
                } else {
                    (0.70 * fallbackHrScore) + (0.30 * sleepPenalty)
                }
                min(max(blended.roundToInt(), 8), 95)
            }
        }

        val currentLevel = StressLevel.from(currentScore)

        // 5. Daily Aggregates
        val dailyAverage: Int = if (intraday.isNotEmpty()) {
            val sum = intraday.sumOf { it.score }
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
        val hrvDeltaPercent = if (validHrv != null && baselineHrv > 0) {
            ((validHrv - baselineHrv) / baselineHrv) * 100.0
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
            currentHrvMs = validHrv,
            hrvDeltaPercent = hrvDeltaPercent,
            restingHeartRateBpm = round(baselineRhr),
            currentSedentaryBpm = effectiveSedentaryBpm?.let { round(it) },
            heartRateElevationBpm = currentHrElevation?.let { round(it * 10.0) / 10.0 },
            monkeyMood = mood,
            adviceQuote = mood.adviceQuote,
            recommendedBreathing = breathing,
            lastUpdated = System.currentTimeMillis()
        )

        return Pair(result, intraday)
    }

    // MARK: - Mathematical Sub-routines

    /**
     * Normalizes HRV using a metric-calibrated sigmoid/tanh transfer function around baseline.
     * High HRV yields lower stress (< 25), baseline yields 50, depressed HRV yields high stress (> 75).
     */
    fun scoreFromHrv(hrv: Double, baseline: Double): Double {
        if (baseline <= 0) return 50.0
        val scale = max(14.0, baseline * 0.35)
        val z = (hrv - baseline) / scale
        val normalized = 50.0 - (tanh(z) * 45.0)
        return min(max(normalized, 0.0), 100.0)
    }

    /**
     * Calibrated sedentary waking HR arousal curve relative to clinical resting heart rate.
     */
    fun scoreFromSedentaryHr(avgHr: Double, baselineRhr: Double): Double {
        val delta = avgHr - baselineRhr
        val z = (delta - 22.0) / 16.0
        val score = 46.0 + (tanh(z) * 44.0)
        return min(max(score, 6.0), 95.0)
    }

    /**
     * Derives a clinical resting HR baseline from nocturnal 5-min HR buckets when a wearable
     * (e.g. Oura Ring via HealthKit) does not export a standalone RHR metric.
     */
    fun deriveNocturnalRhr(
        hrTelemetry: List<IntradayHeartRatePoint>,
        targetDate: Date,
        calendar: Calendar = Calendar.getInstance()
    ): Double? {
        val calTarget = (calendar.clone() as Calendar).apply { time = targetDate }
        val nocturnalBpms = mutableListOf<Double>()
        val daytimeBpms = mutableListOf<Double>()

        for (pt in hrTelemetry) {
            if (pt.bpm <= 35.0 || pt.bpm >= 220.0) continue
            val calPt = (calendar.clone() as Calendar).apply { timeInMillis = pt.timestamp }
            if (!isSameDay(calPt, calTarget)) continue
            val h = calPt.get(Calendar.HOUR_OF_DAY)
            if (h < 8 && pt.bpm <= 95.0) {
                nocturnalBpms.add(pt.bpm)
            } else if (h >= 8) {
                daytimeBpms.add(pt.bpm)
            }
        }

        if (nocturnalBpms.size >= 3) {
            nocturnalBpms.sort()
            val mid = nocturnalBpms.size / 2
            val nocturnalMedian = if (nocturnalBpms.size % 2 == 1) {
                nocturnalBpms[mid]
            } else {
                (nocturnalBpms[mid - 1] + nocturnalBpms[mid]) / 2.0
            }
            val clinicalRhr = nocturnalMedian + 5.5
            return round(min(max(clinicalRhr, 45.0), 85.0))
        }

        val minDay = daytimeBpms.takeIf { it.size >= 3 }?.minOrNull()
        if (minDay != null) {
            return round(min(max(minDay - 2.0, 48.0), 72.0))
        }

        return null
    }

    private fun isSameDay(c1: Calendar, c2: Calendar): Boolean {
        return c1.get(Calendar.YEAR) == c2.get(Calendar.YEAR) &&
                c1.get(Calendar.DAY_OF_YEAR) == c2.get(Calendar.DAY_OF_YEAR)
    }
}
