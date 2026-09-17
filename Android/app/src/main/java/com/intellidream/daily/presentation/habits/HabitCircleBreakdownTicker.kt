package com.intellidream.daily.presentation.habits

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Bolt
import androidx.compose.material.icons.rounded.Coffee
import androidx.compose.material.icons.rounded.Eco
import androidx.compose.material.icons.rounded.EmojiFoodBeverage
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.SmokingRooms
import androidx.compose.material.icons.rounded.WaterDrop
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.model.HabitDrinkBreakdown
import com.intellidream.daily.model.HabitType
import kotlin.math.roundToInt

data class AggregatedTickerItem(
    val id: String,
    val name: String,
    val amount: Double,
    val unit: String,
    val color: Color,
    val icon: ImageVector
)

@Composable
fun HabitCircleBreakdownTicker(
    items: List<HabitDrinkBreakdown>,
    habitType: HabitType = HabitType.WATER,
    modifier: Modifier = Modifier
) {
    val aggregatedItems = remember(items, habitType) {
        aggregateItems(items, habitType)
    }

    if (aggregatedItems.isEmpty()) return

    val scrollState = rememberScrollState()

    Box(
        modifier = modifier
            .widthIn(max = 175.dp)
            .height(24.dp)
            .shadow(4.dp, CircleShape)
            .clip(CircleShape)
            .background(Color.Black.copy(alpha = 0.40f))
            .border(0.8.dp, Color.White.copy(alpha = 0.18f), CircleShape)
            .padding(horizontal = 6.dp, vertical = 2.dp),
        contentAlignment = Alignment.Center
    ) {
        Row(
            modifier = Modifier.horizontalScroll(scrollState),
            horizontalArrangement = Arrangement.spacedBy(5.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            aggregatedItems.forEach { item ->
                val badgeText = formatBadgeText(item, habitType, aggregatedItems.size == 1)

                Row(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(item.color.copy(alpha = 0.22f))
                        .border(0.8.dp, item.color.copy(alpha = 0.40f), CircleShape)
                        .padding(horizontal = 6.dp, vertical = 2.dp),
                    horizontalArrangement = Arrangement.spacedBy(3.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = item.icon,
                        contentDescription = null,
                        tint = item.color,
                        modifier = Modifier.size(9.dp)
                    )
                    Text(
                        text = badgeText,
                        color = Color.White.copy(alpha = 0.92f),
                        fontSize = 9.5.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
            }
        }
    }
}

private fun formatBadgeText(item: AggregatedTickerItem, habitType: HabitType, isSingle: Boolean): String {
    val amountInt = item.amount.roundToInt()
    val formattedAmount = if (item.unit == "ml") "$amountInt ml" else "$amountInt"

    if (isSingle) {
        return "${item.name}: $formattedAmount"
    }

    return if (habitType == HabitType.WATER) {
        if (item.name == "Water") formattedAmount else "${item.name} $formattedAmount"
    } else {
        when (item.name) {
            "Cigarette" -> "$amountInt Cig"
            "Heated" -> "$amountInt Heat"
            "Rolled" -> "$amountInt Roll"
            "Cigarillo" -> "$amountInt Cigar"
            else -> "$amountInt ${item.name}"
        }
    }
}

private fun aggregateItems(
    items: List<HabitDrinkBreakdown>,
    habitType: HabitType
): List<AggregatedTickerItem> {
    val map = mutableMapOf<String, AggregatedTickerItem>()

    for (item in items) {
        val (category, color, icon) = if (habitType == HabitType.WATER) {
            normalizeDrink(item.drink, item.hexColor)
        } else {
            normalizeSmoke(item.drink, item.hexColor)
        }

        val existing = map[category]
        if (existing != null) {
            map[category] = existing.copy(amount = existing.amount + item.amount)
        } else {
            map[category] = AggregatedTickerItem(
                id = category,
                name = category,
                amount = item.amount,
                unit = item.unit,
                color = color,
                icon = icon
            )
        }
    }

    return map.values.sortedByDescending { it.amount }
}

private fun normalizeDrink(name: String, defaultColorHex: String): Triple<String, Color, ImageVector> {
    val lower = name.lowercase()
    return when {
        lower.contains("coffee") || lower.contains("espresso") || lower.contains("cappuccino") || lower.contains("latte") ->
            Triple("Coffee", Color(0xFFF59E0B), Icons.Rounded.Coffee)
        lower.contains("tea") || lower.contains("matcha") || lower.contains("infusion") ->
            Triple("Tea", Color(0xFF84CC16), Icons.Rounded.EmojiFoodBeverage)
        lower.contains("water") || lower.contains("glass") || lower.contains("bottle") ->
            Triple("Water", Color(0xFF00E5FF), Icons.Rounded.WaterDrop)
        else ->
            Triple(name, parseColorSafely(defaultColorHex, Color(0xFF00E5FF)), Icons.Rounded.WaterDrop)
    }
}

private fun normalizeSmoke(name: String, defaultColorHex: String): Triple<String, Color, ImageVector> {
    val lower = name.lowercase()
    return when {
        lower.contains("cigarette") || lower == "cig" || lower.contains("standard") ->
            Triple("Cigarette", Color(0xFFEF4444), Icons.Rounded.LocalFireDepartment)
        lower.contains("cigarillo") || (lower.contains("cigar") && !lower.contains("cigarette")) ->
            Triple("Cigarillo", Color(0xFFA855F7), Icons.Rounded.SmokingRooms)
        lower.contains("heat") || lower.contains("iqos") || lower.contains("glo") || lower.contains("vape") ->
            Triple("Heated", Color(0xFF3B82F6), Icons.Rounded.Bolt)
        lower.contains("roll") ->
            Triple("Rolled", Color(0xFFF97316), Icons.Rounded.Eco)
        else ->
            Triple("Cigarette", parseColorSafely(defaultColorHex, Color(0xFFEF4444)), Icons.Rounded.LocalFireDepartment)
    }
}

private fun parseColorSafely(hex: String, defaultColor: Color): Color {
    return try {
        val cleanHex = hex.removePrefix("#")
        val colorInt = cleanHex.toLong(16)
        if (cleanHex.length == 6) {
            Color(0xFF000000 or colorInt)
        } else if (cleanHex.length == 8) {
            Color(colorInt)
        } else {
            defaultColor
        }
    } catch (_: Exception) {
        defaultColor
    }
}
