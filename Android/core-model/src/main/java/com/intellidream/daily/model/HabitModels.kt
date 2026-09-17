package com.intellidream.daily.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.util.Locale
import java.util.UUID

// MARK: - Habit Types

@Serializable
enum class HabitType(
    val id: String,
    val displayName: String,
    val subtitle: String,
    val defaultUnit: String
) {
    @SerialName("water")
    WATER("water", "Bubbles", "Hydration & Liquids", "ml"),

    @SerialName("smokes")
    SMOKES("smokes", "Smokes", "Tobacco Management", "cigs");

    companion object {
        fun fromId(id: String): HabitType = when (id.lowercase()) {
            "smokes" -> SMOKES
            else -> WATER
        }
    }
}

// MARK: - Water Presets

@Serializable
enum class WaterPreset(
    val id: String,
    val displayName: String,
    val defaultAmountMl: Double,
    val hexColor: String,
    val hydrationFactor: Double
) {
    SMALL_WATER("smallWater", "Small", 150.0, "#38BDF8", 1.0),
    LARGE_WATER("largeWater", "Large", 300.0, "#00E5FF", 1.0),
    GLASS("glass", "Glass", 250.0, "#10B981", 1.0),
    BOTTLE("bottle", "Bottle", 500.0, "#06B6D4", 1.0),
    COFFEE("coffee", "Coffee", 100.0, "#F59E0B", 0.80),
    TEA("tea", "Tea", 250.0, "#84CC16", 0.95);

    val amountMl: Double get() = defaultAmountMl
    val colorHex: String get() = hexColor
}

// MARK: - Smoke Presets

@Serializable
enum class SmokePreset(
    val id: String,
    val displayName: String,
    val defaultCount: Int,
    val hexColor: String
) {
    CIGARETTE("cigarette", "Cigarette", 1, "#EF4444"),
    HEATED("heated", "Heated", 1, "#3B82F6"),
    ROLLED("rolled", "Rolled", 1, "#F97316"),
    CIGARILLO("cigarillo", "Cigarillo", 1, "#A855F7");

    val count: Int get() = defaultCount
    val colorHex: String get() = hexColor
}

// MARK: - Habit Log Record

@Serializable
data class HabitLogRecord(
    val id: String = UUID.randomUUID().toString(),
    @SerialName("user_id") val userId: String? = null,
    @SerialName("habit_type") val habitType: String,
    val value: Double,
    val unit: String,
    @SerialName("logged_at") val loggedAt: Long = System.currentTimeMillis(),
    val metadata: String? = null,
    @SerialName("created_at") val createdAt: Long = System.currentTimeMillis(),
    @SerialName("updated_at") val updatedAt: Long = System.currentTimeMillis(),
    @SerialName("is_deleted") val isDeleted: Boolean = false
) {
    val amount: Double get() = value

    val parsedDrink: String?
        get() {
            if (metadata.isNullOrEmpty()) return null
            return try {
                val json = Json.parseToJsonElement(metadata) as? JsonObject
                json?.get("drink")?.jsonPrimitive?.content ?: json?.get("type")?.jsonPrimitive?.content
            } catch (_: Exception) {
                null
            }
        }

    val multiplier: Int
        get() {
            if (metadata.isNullOrEmpty()) return 1
            return try {
                val json = Json.parseToJsonElement(metadata) as? JsonObject
                json?.get("multiplier")?.jsonPrimitive?.content?.toIntOrNull()?.coerceAtLeast(1) ?: 1
            } catch (_: Exception) {
                1
            }
        }

    val drinkType: String
        get() = parsedDrink ?: if (habitType == "water") "Water" else "Cigarette"

    val smokeType: String
        get() = parsedDrink ?: if (habitType == "smokes") "Cigarette" else "Water"

    val displayName: String
        get() = parsedDrink?.takeIf { it.isNotEmpty() }
            ?: habitType.replaceFirstChar { if (it.isLowerCase()) it.titlecase(Locale.US) else it.toString() }

    val displayTitleWithMultiplier: String
        get() {
            val base = displayName
            return if (multiplier > 1) {
                val totalStr = if (habitType == "water") "${value.toInt()} ml" else "${value.toInt()}"
                "${multiplier}× $base (+$totalStr)"
            } else {
                base
            }
        }

    val specificIconColorHex: String
        get() {
            return if (habitType == "water") {
                val d = drinkType.lowercase(Locale.US)
                when {
                    d.contains("coffee") || d.contains("espresso") -> "#F59E0B"
                    d.contains("tea") -> "#84CC16"
                    else -> "#00E5FF"
                }
            } else {
                val s = smokeType.lowercase(Locale.US)
                when {
                    s.contains("heat") || s.contains("vape") -> "#3B82F6"
                    s.contains("roll") -> "#F97316"
                    s.contains("cigarillo") || (s.contains("cigar") && !s.contains("cigarette")) -> "#A855F7"
                    else -> "#EF4444"
                }
            }
        }
}

// MARK: - Habit Goal Record

@Serializable
data class HabitGoalRecord(
    val id: String = UUID.randomUUID().toString(),
    @SerialName("user_id") val userId: String? = null,
    @SerialName("habit_type") val habitType: String,
    @SerialName("target_value") val targetValue: Double,
    val unit: String,
    @SerialName("updated_at") val updatedAt: Long = System.currentTimeMillis(),
    @SerialName("created_at") val createdAt: Long = System.currentTimeMillis(),
    @SerialName("is_deleted") val isDeleted: Boolean = false
)

// MARK: - Smokes Settings & Financial Metrics

@Serializable
data class SmokesSettings(
    val quitStartDate: Long = System.currentTimeMillis() - (30L * 24 * 60 * 60 * 1000),
    val baselineCigsPerDay: Int = 20,
    val cigsPerPack: Int = 20,
    val costPerPack: Double = 26.50,
    val currency: String = "RON"
) {
    val costPerCig: Double
        get() = costPerPack / cigsPerPack.coerceAtLeast(1).toDouble()

    val baselineDailyCount: Int
        get() = baselineCigsPerDay
}

data class SmokesFinancialMetrics(
    val moneySaved: Double = 0.0,
    val cigsAvoided: Int = 0,
    val daysTracked: Int = 0,
    val costPerCig: Double = 1.325,
    val currency: String = "RON",
    val lastSmokeDate: Long? = null,
    val timeSinceLastSmokeMillis: Long? = null
) {
    val formattedMoneySaved: String
        get() = String.format(Locale.US, "+%.2f", moneySaved)

    val moneySavedFormatted: String
        get() = String.format(Locale.US, "+%.2f %s", moneySaved, currency)

    val cigarettesAvoidedCount: Int
        get() = cigsAvoided

    val lifeRegainedFormatted: String
        get() {
            val totalMinutes = cigsAvoided * 11
            val hours = totalMinutes / 60
            val mins = totalMinutes % 60
            return if (hours > 0) "${hours}h ${mins}m" else "${totalMinutes}m"
        }

    val formattedTimeSinceLastSmoke: String
        get() {
            val millis = timeSinceLastSmokeMillis ?: return "No smokes logged"
            if (millis < 0) return "No smokes logged"
            val mins = (millis / 60000).toInt()
            val hours = mins / 60
            val remainingMins = mins % 60
            return when {
                hours > 0 -> "${hours}h ${remainingMins}m ago"
                mins > 0 -> "${mins}m ago"
                else -> "Just now"
            }
        }
}

// MARK: - Habit Analytics & Visual Models

data class HabitDrinkBreakdown(
    val drink: String,
    val amount: Double,
    val unit: String,
    val percentage: Double,
    val hexColor: String,
    val iconName: String
) {
    val name: String get() = drink
    val amountMl: Double get() = amount
    val colorHex: String get() = hexColor
}

data class HabitTrendDay(
    val date: Long,
    val dayLabel: String,
    val value: Double,
    val goal: Double,
    val isGoalMet: Boolean
) {
    val progressRatio: Double
        get() = if (goal > 0) (value / goal).coerceAtMost(1.5) else 0.0

    val amount: Double get() = value
}

data class HabitConsistencyCell(
    val date: Long,
    val dateKey: String,
    val value: Double,
    val intensityLevel: Int, // 0..4
    val tooltip: String,
    val isGoalMet: Boolean = false
) {
    val amount: Double get() = value
}

// MARK: - Guidance Models

data class CircadianHydrationSlot(
    val timeRange: String,
    val title: String,
    val recommendedVolumeMl: Int,
    val rationale: String,
    val iconName: String
)

data class DrinkHydrationInfo(
    val name: String,
    val indexScore: Double,
    val description: String,
    val proTip: String,
    val iconName: String,
    val hexColor: String
)

data class UrineColorLevel(
    val level: Int,
    val status: String,
    val hexColor: String,
    val recommendation: String
)

data class CravingProtocolStep(
    val letter: String,
    val action: String,
    val explanation: String,
    val durationText: String,
    val iconName: String,
    val stepNumber: Int
)

data class RecoveryMilestone(
    val timeframe: String,
    val benefit: String,
    val physiologicalChange: String,
    val iconName: String,
    val hexColor: String
)

object HabitsGuidance {
    val circadianSlots = listOf(
        CircadianHydrationSlot(
            timeRange = "07:00 – 09:00",
            title = "Morning Kickstart",
            recommendedVolumeMl = 450,
            rationale = "Rehydrate brain and vital organs after 7-8h of nocturnal sleep. Wakes up gastrointestinal motility.",
            iconName = "sunrise"
        ),
        CircadianHydrationSlot(
            timeRange = "10:00 – 12:00",
            title = "Cognitive Focus Peak",
            recommendedVolumeMl = 300,
            rationale = "Maintains optimal cerebral blood flow. A 1% drop in body water degrades working memory and alertness.",
            iconName = "psychology"
        ),
        CircadianHydrationSlot(
            timeRange = "30m Pre-Meal",
            title = "Digestive Preparation",
            recommendedVolumeMl = 250,
            rationale = "Primes digestive enzymes and stimulates natural satiety. Avoid drinking large volumes during meals to maintain stomach acid concentration.",
            iconName = "restaurant"
        ),
        CircadianHydrationSlot(
            timeRange = "14:00 – 16:00",
            title = "Afternoon Energy Boost",
            recommendedVolumeMl = 350,
            rationale = "Combats postprandial lethargy. Midday fatigue is commonly mild dehydration rather than actual lack of sleep.",
            iconName = "bolt"
        ),
        CircadianHydrationSlot(
            timeRange = "Post 20:00",
            title = "Night Taper",
            recommendedVolumeMl = 100,
            rationale = "Limit water intake to small sips before bed to prevent nocturia, protecting uninterrupted Deep and REM sleep cycles.",
            iconName = "bedtime"
        )
    )

    val drinkHydrationIndex = listOf(
        DrinkHydrationInfo(
            name = "Pure Water",
            indexScore = 1.0,
            description = "The gold standard for cellular osmosis and body temperature regulation.",
            proTip = "Room temperature or slightly cool water absorbs faster than iced water.",
            iconName = "water_drop",
            hexColor = "#00E5FF"
        ),
        DrinkHydrationInfo(
            name = "Herbal & Green Tea",
            indexScore = 0.95,
            description = "High antioxidant polyphenol profile with excellent cellular fluid retention.",
            proTip = "Chamomile in the evening relaxes nerves without any diuretic impact.",
            iconName = "emoji_food_beverage",
            hexColor = "#84CC16"
        ),
        DrinkHydrationInfo(
            name = "Black Coffee",
            indexScore = 0.80,
            description = "Mild diuretic due to adenosine antagonism, but still net positive fluid balance.",
            proTip = "Drink a 250ml glass of water alongside each espresso to offset fluid loss.",
            iconName = "coffee",
            hexColor = "#F59E0B"
        ),
        DrinkHydrationInfo(
            name = "Electrolyte Water",
            indexScore = 1.15,
            description = "Sodium + Potassium + Magnesium enables superior cellular fluid retention.",
            proTip = "Ideal post-workout or in hot weather when losing electrolytes through sweat.",
            iconName = "auto_awesome",
            hexColor = "#10B981"
        )
    )

    val armstrongUrineScale = listOf(
        UrineColorLevel(
            level = 1,
            status = "Optimal Hydration",
            hexColor = "#F8FAF0",
            recommendation = "Pale straw to crystal clear. Your body is fully hydrated."
        ),
        UrineColorLevel(
            level = 2,
            status = "Good Hydration",
            hexColor = "#FDE047",
            recommendation = "Light yellow. Maintain current cadence of fluid intake."
        ),
        UrineColorLevel(
            level = 3,
            status = "Mild Dehydration",
            hexColor = "#EAB308",
            recommendation = "Bright or medium yellow. Drink a 300ml glass of water within the next hour."
        ),
        UrineColorLevel(
            level = 4,
            status = "Moderate Dehydration",
            hexColor = "#CA8A04",
            recommendation = "Amber or honey tone. Drink 500ml of water immediately."
        )
    )

    val fourDsCravingProtocol = listOf(
        CravingProtocolStep(
            letter = "D",
            action = "Delay",
            explanation = "Cravings are neurochemical waves peaking in 3–5 minutes before fading. Wait 10 minutes before reacting.",
            durationText = "5–10 mins",
            iconName = "timer",
            stepNumber = 1
        ),
        CravingProtocolStep(
            letter = "D",
            action = "Deep Breathe",
            explanation = "Breathe in for 4 seconds, hold 4 seconds, exhale 4 seconds. Triggers parasympathetic nerve calming and lowers cortisol.",
            durationText = "1–2 mins",
            iconName = "air",
            stepNumber = 2
        ),
        CravingProtocolStep(
            letter = "D",
            action = "Drink Water",
            explanation = "Sip cold water slowly. Occupies the oral fixation trigger while accelerating metabolic toxin clearance.",
            durationText = "2 mins",
            iconName = "water_drop",
            stepNumber = 3
        ),
        CravingProtocolStep(
            letter = "D",
            action = "Distract",
            explanation = "Shift physical location or engage your hands in a concrete task (walk, message a friend, stretch).",
            durationText = "5–10 mins",
            iconName = "directions_walk",
            stepNumber = 4
        )
    )

    val recoveryMilestones = listOf(
        RecoveryMilestone(
            timeframe = "20 Minutes",
            benefit = "Heart Rate & BP Drop",
            physiologicalChange = "Pulse and peripheral blood pressure return toward baseline resting levels.",
            iconName = "favorite",
            hexColor = "#EF4444"
        ),
        RecoveryMilestone(
            timeframe = "12 Hours",
            benefit = "Carbon Monoxide Cleared",
            physiologicalChange = "Blood carbon monoxide (CO) drops by 50%+, restoring red blood cell oxygen carrying capacity.",
            iconName = "air",
            hexColor = "#3B82F6"
        ),
        RecoveryMilestone(
            timeframe = "48 Hours",
            benefit = "Nerve Endings Regenerate",
            physiologicalChange = "All nicotine eliminated from the body. Taste buds and olfactory receptors begin sharp recovery.",
            iconName = "auto_awesome",
            hexColor = "#10B981"
        ),
        RecoveryMilestone(
            timeframe = "72 Hours",
            benefit = "Bronchial Tubes Relax",
            physiologicalChange = "Breathing eases noticeably as bronchial airway spasm diminishes; total lung capacity expands.",
            iconName = "air",
            hexColor = "#00E5FF"
        ),
        RecoveryMilestone(
            timeframe = "2–4 Weeks",
            benefit = "Physical Addiction Ended",
            physiologicalChange = "Nicotine withdrawal symptoms fully subside. Peripheral vascular circulation significantly improves.",
            iconName = "verified_user",
            hexColor = "#8B5CF6"
        ),
        RecoveryMilestone(
            timeframe = "1 Year",
            benefit = "Cardiovascular Risk Halved",
            physiologicalChange = "Excess risk of coronary heart disease drops by 50% compared to a continuing smoker.",
            iconName = "emoji_events",
            hexColor = "#F59E0B"
        )
    )
}
