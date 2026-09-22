package com.intellidream.daily.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.util.Calendar
import java.util.UUID

/**
 * Contextual temporal slots dividing the 24-hour cycle for Smart Briefings.
 * Forensic match with iOS DailyCore BriefingTimeSlot.
 */
@Serializable
enum class BriefingTimeSlot(
    val value: String,
    val displayName: String,
    val timeRangeString: String,
    val auraGradientHex: List<String>,
    val greetingPrefix: String,
    val defaultClosingWish: String,
    val defaultClosingIcon: String
) {
    @SerialName("morning")
    MORNING(
        value = "morning",
        displayName = "Morning Briefing",
        timeRangeString = "05:00 – 11:59",
        auraGradientHex = listOf("#FF9A3D", "#FF5E62", "#7B2CBF"),
        greetingPrefix = "Good morning",
        defaultClosingWish = "Have a great day!",
        defaultClosingIcon = "sun.horizon.fill"
    ),

    @SerialName("intraday")
    INTRADAY(
        value = "intraday",
        displayName = "Intra-day Briefing",
        timeRangeString = "12:00 – 16:59",
        auraGradientHex = listOf("#00F5D4", "#00BBF9", "#4361EE"),
        greetingPrefix = "Good afternoon",
        defaultClosingWish = "Have a productive day!",
        defaultClosingIcon = "sun.max.fill"
    ),

    @SerialName("evening")
    EVENING(
        value = "evening",
        displayName = "Evening Review",
        timeRangeString = "17:00 – 21:59",
        auraGradientHex = listOf("#F72585", "#7209B7", "#3A0CA3"),
        greetingPrefix = "Good evening",
        defaultClosingWish = "Enjoy a restful evening!",
        defaultClosingIcon = "sunset.fill"
    ),

    @SerialName("nightly")
    NIGHTLY(
        value = "nightly",
        displayName = "Nightly Wind-Down",
        timeRangeString = "22:00 – 04:59",
        auraGradientHex = listOf("#3F37C9", "#480CA8", "#03071E"),
        greetingPrefix = "Peaceful night",
        defaultClosingWish = "Sleep tight & rest well!",
        defaultClosingIcon = "bed.double.fill"
    );

    fun diurnalGreeting(name: String): String {
        return when (this) {
            MORNING -> "Good morning, $name!"
            INTRADAY -> "Have a wonderful day, $name!"
            EVENING -> "Good evening, $name!"
            NIGHTLY -> "Time to rest, $name"
        }
    }

    companion object {
        fun current(calendar: Calendar = Calendar.getInstance()): BriefingTimeSlot {
            val hour = calendar.get(Calendar.HOUR_OF_DAY)
            return when (hour) {
                in 5..11 -> MORNING
                in 12..16 -> INTRADAY
                in 17..21 -> EVENING
                else -> NIGHTLY
            }
        }

        fun fromRaw(value: String): BriefingTimeSlot {
            return entries.firstOrNull { it.value.equals(value, ignoreCase = true) } ?: MORNING
        }
    }
}

/**
 * Structured multi-hub narrative text components forming the briefing body.
 */
@Serializable
data class SmartBriefingNarrative(
    val greeting: String = "",
    val weatherText: String = "",
    val healthText: String = "",
    val stressText: String = "",
    val habitsText: String = "",
    val financeText: String = "",
    val tagdosText: String = "",
    val newsText: String = "",
    val outroText: String = "",
    val closingWish: String? = null,
    val closingIcon: String? = null
) {
    val fullConcatenatedText: String
        get() {
            return listOf(
                greeting,
                weatherText,
                healthText,
                stressText,
                habitsText,
                financeText,
                tagdosText,
                newsText,
                outroText
            ).filter { it.isNotBlank() }
                .joinToString("\n\n")
        }
}

/**
 * Numerical and telemetry snapshot backing the visual mini-cards in the briefing.
 */
@Serializable
data class SmartBriefingMetrics(
    val weatherTemp: Double? = null,
    val weatherCondition: String? = null,
    val weatherIcon: String? = null,
    val weatherCity: String? = null,
    val sleepScore: Int? = null,
    val sleepDurationHours: Double? = null,
    val sleepDurationFormatted: String? = null,
    val restingBpm: Double? = null,
    val totalStepsToday: Int = 0,
    val waterMlToday: Double = 0.0,
    val waterGoalMl: Double = 2000.0,
    val smokesToday: Int = 0,
    val smokesBaseline: Int = 10,
    val netWorth: Double = 0.0,
    val daySpend: Double = 0.0,
    val activeStreamCount: Int = 0,
    val activeMemoCount: Int = 0,
    val topNewsTitle: String? = null,
    val stressScore: Int? = null,
    val stressStatus: String? = null,
    val monkeyMood: String? = null
)

/**
 * Persisted record model mapping directly to Supabase `public.daily_smart_summaries`.
 */
@Serializable
data class SmartBriefingRecord(
    val id: String = UUID.randomUUID().toString(),
    @SerialName("user_id") val userId: String = "",
    @SerialName("time_slot") val timeSlot: String = BriefingTimeSlot.MORNING.value,
    @SerialName("data_hash") val dataHash: String = "",
    val narrative: SmartBriefingNarrative = SmartBriefingNarrative(),
    val metrics: SmartBriefingMetrics = SmartBriefingMetrics(),
    @SerialName("is_ai_generated") val isAiGenerated: Boolean = false,
    @SerialName("created_at") val createdAt: Long = System.currentTimeMillis(),
    @SerialName("updated_at") val updatedAt: Long = System.currentTimeMillis()
) {
    val slot: BriefingTimeSlot
        get() = BriefingTimeSlot.fromRaw(timeSlot)
}

/**
 * Labeled card item for the structured visual presentation in SmartBriefingBottomSheet.
 */
data class BriefingCardItem(
    val id: String,
    val iconName: String,
    val title: String,
    val badgeText: String? = null,
    val badgeColorHex: String? = null,
    val text: String,
    val accentColorHex: String = "#00F5D4"
)
