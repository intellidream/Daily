package com.intellidream.daily.model

import kotlinx.serialization.Serializable
import java.util.Locale
import java.util.UUID

// MARK: - Stress Level Categorization

/**
 * Four-tier clinical stress classification mirroring autonomic nervous system (ANS) tone.
 * 1:1 Kotlin port of iOS DailyCore's StressLevel.
 */
@Serializable
enum class StressLevel(
    val id: String,
    val displayName: String,
    val hexColor: String,
    val gradientHex: List<String>,
    val clinicalDescription: String
) {
    RESTFUL(
        id = "Restful",
        displayName = "Restful",
        hexColor = "#00E5FF", // Neon cyan / mint
        gradientHex = listOf("#00E5FF", "#7B2CBF"),
        clinicalDescription = "Parasympathetic dominance. Deep physiological recovery and high neural adaptability."
    ),
    CALM(
        id = "Calm",
        displayName = "Calm",
        hexColor = "#00FFB2", // Teal / spring green
        gradientHex = listOf("#00FFB2", "#00B4D8"),
        clinicalDescription = "Balanced autonomic tone. Stable heart rhythm with healthy cognitive focus."
    ),
    MODERATE(
        id = "Moderate",
        displayName = "Moderate",
        hexColor = "#FFA726", // Warm amber
        gradientHex = listOf("#FFA726", "#FF7043"),
        clinicalDescription = "Elevated sympathetic activation. Mild physiological strain or sustained task fatigue."
    ),
    HIGH(
        id = "High",
        displayName = "High",
        hexColor = "#FF5252", // Coral / bright red
        gradientHex = listOf("#FF5252", "#D00000"),
        clinicalDescription = "Acute sympathetic dominance. High physiological arousal; recovery protocols recommended."
    );

    val scoreRange: IntRange
        get() = when (this) {
            RESTFUL -> 0..25
            CALM -> 26..50
            MODERATE -> 51..75
            HIGH -> 76..100
        }

    companion object {
        fun from(score: Int): StressLevel = when (score) {
            in 0..25 -> RESTFUL
            in 26..50 -> CALM
            in 51..75 -> MODERATE
            else -> HIGH
        }
    }
}

// MARK: - Stylized Monkey Mascot Persona

/**
 * Expressive monkey character moods corresponding to autonomic stress states.
 * 1:1 Kotlin port of iOS DailyCore's MonkeyMood.
 */
@Serializable
enum class MonkeyMood(
    val displayName: String,
    val iconSymbol: String,
    val emoji: String,
    val adviceQuote: String,
    val quickActionTitle: String
) {
    ZEN(
        displayName = "Zen Monkey",
        iconSymbol = "leaf.fill",
        emoji = "🧘‍♂️",
        adviceQuote = "You're in peak recovery mode! Perfect balance of mind and body — ideal for creative breakthroughs.",
        quickActionTitle = "Deepen Focus"
    ),
    CURIOUS(
        displayName = "Curious Monkey",
        iconSymbol = "sparkles",
        emoji = "🐵",
        adviceQuote = "Autonomic tone is nice and steady. Keep up this calm rhythm with a fresh sip of water!",
        quickActionTitle = "Stay Hydrated"
    ),
    BUSY(
        displayName = "Busy Monkey",
        iconSymbol = "flame",
        emoji = "🐒",
        adviceQuote = "Tension is gently creeping up. Step back for 3 minutes and try Box Breathing (4s In, 4s Hold, 4s Out, 4s Hold).",
        quickActionTitle = "Box Breathing"
    ),
    OVERHEATED(
        displayName = "Overheated Monkey",
        iconSymbol = "thermometer.sun.fill",
        emoji = "🙈",
        adviceQuote = "High sympathetic arousal detected! Do 3 Physiological Sighs right now: two quick nose inhales, one long slow exhale.",
        quickActionTitle = "Physiological Sigh"
    );

    companion object {
        fun fromLevel(level: StressLevel): MonkeyMood = when (level) {
            StressLevel.RESTFUL -> ZEN
            StressLevel.CALM -> CURIOUS
            StressLevel.MODERATE -> BUSY
            StressLevel.HIGH -> OVERHEATED
        }
    }
}

// MARK: - Breathing Protocols

/**
 * Clinically validated down-regulation breathing protocols.
 * 1:1 Kotlin port of iOS DailyCore's BreathingProtocol.
 */
@Serializable
enum class BreathingProtocol(
    val id: String,
    val title: String,
    val description: String,
    val cyclesRecommended: Int
) {
    PHYSIOLOGICAL_SIGH(
        id = "Physiological Sigh",
        title = "Physiological Sigh",
        description = "Stanford Huberman protocol: Two rapid inhales through the nose, followed by a long, slow sigh through the mouth. Fastest way to downregulate autonomic arousal.",
        cyclesRecommended = 3
    ),
    BOX_BREATHING(
        id = "Box Breathing (4-4-4-4)",
        title = "Box Breathing (4-4-4-4)",
        description = "Navy SEAL reset: 4 seconds inhale, 4 seconds hold, 4 seconds exhale, 4 seconds hold. Restores executive composure.",
        cyclesRecommended = 4
    ),
    RESONANCE_FLOW(
        id = "Resonance Flow (5.5s)",
        title = "Resonance Flow (5.5s)",
        description = "Heart-Rate Variability maximizer: 5.5 seconds in, 5.5 seconds out (approx. 5.5 breaths/min). Synchronizes vagal nerve tone.",
        cyclesRecommended = 6
    ),
    RELAX_478(
        id = "Relaxing 4-7-8",
        title = "Relaxing 4-7-8",
        description = "Parasympathetic primer: 4 seconds inhale, 7 seconds hold, 8 seconds exhale. Relaxes nervous system before sleep or rest.",
        cyclesRecommended = 4
    );

    companion object {
        fun defaultForLevel(level: StressLevel): BreathingProtocol = when (level) {
            StressLevel.RESTFUL -> RESONANCE_FLOW
            StressLevel.CALM -> RELAX_478
            StressLevel.MODERATE -> BOX_BREATHING
            StressLevel.HIGH -> PHYSIOLOGICAL_SIGH
        }
    }
}

// MARK: - Intraday & Analysis Models

/**
 * Hourly point tracking stress fluctuation throughout the 24-hour cycle.
 */
@Serializable
data class IntradayStressPoint(
    val id: String = UUID.randomUUID().toString(),
    val timestamp: Long,
    val hour: Int,
    val score: Int,
    val level: StressLevel,
    val hrvMs: Double? = null,
    val heartRateBpm: Double? = null,
    val isSedentary: Boolean = true
) {
    val hourFormatted: String
        get() = String.format(Locale.US, "%02d:00", hour)
}

/**
 * Comprehensive daily stress analysis snapshot.
 */
@Serializable
data class StressAnalysisResult(
    val currentScore: Int,
    val currentLevel: StressLevel,
    val dailyAverageScore: Int,
    val peakHour: Int? = null,
    val peakScore: Int? = null,
    val lowestHour: Int? = null,
    val lowestScore: Int? = null,

    // Autonomic balance indices
    val parasympatheticPercent: Int, // Rest & Digest (0 - 100)
    val sympatheticPercent: Int,     // Fight or Flight (0 - 100)

    // Biometric drivers
    val baselineHrvMs: Double,
    val currentHrvMs: Double? = null,
    val hrvDeltaPercent: Double? = null,
    val restingHeartRateBpm: Double? = null,
    val currentSedentaryBpm: Double? = null,
    val heartRateElevationBpm: Double? = null,

    // Persona & Guidance
    val monkeyMood: MonkeyMood,
    val adviceQuote: String,
    val recommendedBreathing: BreathingProtocol,
    val lastUpdated: Long = System.currentTimeMillis()
) {
    val stressScore: Int get() = currentScore
    val stressLevel: StressLevel get() = currentLevel
}
