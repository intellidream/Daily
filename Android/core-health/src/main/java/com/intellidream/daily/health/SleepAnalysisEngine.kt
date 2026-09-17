package com.intellidream.daily.health

import com.intellidream.daily.model.SleepAIContext
import com.intellidream.daily.model.SleepActionableTip
import com.intellidream.daily.model.SleepRecoveryStatus
import com.intellidream.daily.model.SleepRecoveryVerdict
import com.intellidream.daily.model.SleepSession
import com.intellidream.daily.model.SleepTipCategory
import kotlin.math.max
import kotlin.math.min

/**
 * Result data class for sleep analysis operations.
 */
data class SleepAnalysisResult(
    val verdict: SleepRecoveryVerdict,
    val tips: List<SleepActionableTip>,
    val aiContext: SleepAIContext
)

/**
 * Pure deterministic clinical intelligence engine for evaluating sleep architecture,
 * recovery readiness, physical/cognitive restoration, and generating actionable science-backed tips.
 * 1:1 Kotlin port of iOS DailyCore's SleepAnalysisEngine.
 */
object SleepAnalysisEngine {

    /**
     * Evaluates a nocturnal sleep session and generates recovery verdict, science tips, and AI context.
     */
    fun analyze(
        session: SleepSession,
        nocturnalRestingBpm: Double? = null,
        nocturnalHrvMs: Double? = null
    ): SleepAnalysisResult {
        val score = session.sleepScore
        val deepPct = session.deepPercent
        val remPct = session.remPercent
        val effPct = session.efficiencyPercent
        val awakeCount = session.awakeCount
        val durationHours = session.asleepSeconds / 3600.0

        // 1. Determine Status & Readiness Score
        val status: SleepRecoveryStatus
        val readiness: Int

        if (score >= 85 && effPct >= 85 && deepPct >= 14) {
            status = SleepRecoveryStatus.OPTIMAL
            readiness = min(100, 85 + (((score - 85).toDouble() / 15.0) * 15.0).toInt())
        } else if (score >= 72) {
            status = SleepRecoveryStatus.GREAT
            readiness = min(84, 70 + (((score - 72).toDouble() / 13.0) * 14.0).toInt())
        } else if (score >= 55) {
            status = SleepRecoveryStatus.FAIR
            readiness = min(69, 50 + (((score - 55).toDouble() / 17.0) * 19.0).toInt())
        } else {
            status = SleepRecoveryStatus.DEFICIT
            readiness = max(20, min(49, score))
        }

        // 2. Physical & Cognitive Ratings
        val physicalRating: String = if (deepPct >= 18 || session.deepSeconds >= 4500) {
            "High"
        } else if (deepPct >= 12 || session.deepSeconds >= 2700) {
            "Adequate"
        } else {
            "Low"
        }

        val cognitiveRating: String = if (remPct >= 20 || session.remSeconds >= 5400) {
            "High"
        } else if (remPct >= 14 || session.remSeconds >= 3600) {
            "Adequate"
        } else {
            "Low"
        }

        val continuityRating: String = if (awakeCount <= 2 && effPct >= 88) "Continuous" else "Fragmented"

        // 3. Headline & Narrative Synthesis
        val headline: String
        val narrative: String

        when (status) {
            SleepRecoveryStatus.OPTIMAL -> {
                headline = "Completely Recharged & Peak Readiness"
                narrative = "Your sleep architecture was deeply restorative (${session.totalAsleepFormatted} asleep, ${session.restorativePercent}% Deep+REM). Growth hormone release and muscular repair peaked during your ${session.deepFormatted} of deep sleep. Your central nervous system is primed for peak physical and cognitive output today."
            }
            SleepRecoveryStatus.GREAT -> {
                headline = "Well-Rested with Solid Recovery"
                narrative = "You achieved a balanced sleep window with ${session.totalAsleepFormatted} of sleep and $effPct% efficiency. Both physical cellular restoration (${session.deepFormatted} Deep) and memory consolidation (${session.remFormatted} REM) were sufficient to handle full daily demands."
            }
            SleepRecoveryStatus.FAIR -> {
                if (durationHours < 6.5) {
                    headline = "Moderate Rest • Short Sleep Duration"
                    narrative = "Sleep efficiency remained stable at $effPct%, but total sleep duration was limited to ${session.totalAsleepFormatted}. Your body accumulated mild recovery load. Consider a brief 20-minute afternoon power nap to stay sharp."
                } else {
                    headline = "Moderate Rest • Light Architecture"
                    narrative = "You spent ${session.timeInBedFormatted} in bed, but lighter sleep stages dominated. Deep slow-wave sleep (${session.deepFormatted}) was slightly restricted, meaning physical repair was partial."
                }
            }
            SleepRecoveryStatus.DEFICIT -> {
                headline = "Recovery Deficit • Prioritize Rest Today"
                narrative = "Significant sleep disruption detected ($awakeCount awakenings, $effPct% efficiency). High recovery load will elevate physiological strain today. Defer heavy physical strain and focus on hydration and an early bedtime tonight."
            }
        }

        val verdict = SleepRecoveryVerdict(
            status = status,
            headline = headline,
            narrative = narrative,
            readinessScore = readiness,
            physicalRepairRating = physicalRating,
            cognitiveRestoreRating = cognitiveRating,
            sleepContinuityRating = continuityRating
        )

        // 4. Generate Contextual Clinical Tips
        val tips = mutableListOf<SleepActionableTip>()

        // A. Deep sleep optimization
        if (deepPct < 15) {
            tips.add(
                SleepActionableTip(
                    category = SleepTipCategory.ENVIRONMENT,
                    title = "Cool Bedroom to 18–20°C",
                    advice = "Lower your thermostat or ventilate your room 30 minutes before sleep.",
                    scientificRationale = "Thermoregulation drop triggers slow-wave NREM sleep, directly expanding deep sleep duration."
                )
            )
        }

        // B. REM sleep optimization
        if (remPct < 18) {
            tips.add(
                SleepActionableTip(
                    category = SleepTipCategory.NUTRITION,
                    title = "Cut Evening Alcohol & Heavy Carbs",
                    advice = "Finish dinner at least 3 hours before bed and avoid alcohol.",
                    scientificRationale = "Ethanol metabolism suppresses REM sleep cycles in the first half of the night, reducing dream and memory processing."
                )
            )
        }

        // C. Continuity & Awakenings
        if (awakeCount >= 3 || effPct < 85) {
            tips.add(
                SleepActionableTip(
                    category = SleepTipCategory.WIND_DOWN,
                    title = "5-Minute Vagal Box Breathing",
                    advice = "Inhale 4s, hold 4s, exhale 4s, hold 4s right before turning off the lights.",
                    scientificRationale = "Stimulates the parasympathetic vagal nerve, lowering heart rate and minimizing midnight micro-arousals."
                )
            )
        }

        // D. Circadian anchor tip (always relevant)
        tips.add(
            SleepActionableTip(
                category = SleepTipCategory.CIRCADIAN,
                title = "Morning Sunlight Exposure",
                advice = "Spend 15–20 minutes outside in natural daylight within 1 hour of waking.",
                scientificRationale = "Suppresses melatonin release, synchronizes your central circadian clock, and programs natural sleep onset 16 hours later."
            )
        )

        val topTips = tips.take(3)

        // 5. Build AI Context & Prompts
        val suggestedPrompts = listOf(
            "De ce am avut Deep Sleep scăzut azi noapte?",
            "Este recomandat un antrenament cardio intens azi?",
            "Cum îmi pot îmbunătăți somnul REM și HRV-ul nocturn?",
            "Ce rutină de seară mă ajută să reduc trezirile nocturne?"
        )

        val aiContext = SleepAIContext(
            narrativeSynthesis = narrative,
            suggestedPrompts = suggestedPrompts
        )

        return SleepAnalysisResult(verdict, topTips, aiContext)
    }
}
