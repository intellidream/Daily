package com.intellidream.daily.presentation.health

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Lightbulb
import androidx.compose.material.icons.rounded.LocalCafe
import androidx.compose.material.icons.rounded.SelfImprovement
import androidx.compose.material.icons.rounded.Thermostat
import androidx.compose.material.icons.rounded.WbSunny
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.SleepActionableTip
import com.intellidream.daily.model.SleepTipCategory

@Composable
fun SleepAdviceCard(
    tips: List<SleepActionableTip>,
    modifier: Modifier = Modifier
) {
    GlassCard(
        modifier = modifier.fillMaxWidth(),
        cornerRadius = 20.dp,
        padding = 18.dp
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            // Header
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Lightbulb,
                        contentDescription = null,
                        tint = Color(0xFFFFD600),
                        modifier = Modifier.size(14.dp)
                    )
                    Text(
                        text = "ACTIONABLE SLEEP HYGIENE",
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        color = ThemeColors.accentCyan
                    )
                }

                Text(
                    text = "AASM Clinical Science",
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Medium,
                    color = ThemeColors.fgMutedDark
                )
            }

            // Tips List
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                tips.forEach { tip ->
                    TipRow(tip = tip)
                }
            }
        }
    }
}

@Composable
private fun TipRow(tip: SleepActionableTip) {
    val categoryColor = Color(android.graphics.Color.parseColor(tip.category.hexColor))

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.Top
    ) {
        // Category Icon Badge
        Box(
            modifier = Modifier
                .size(32.dp)
                .clip(CircleShape)
                .background(categoryColor.copy(alpha = 0.12f)),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = getTipIcon(tip.category),
                contentDescription = null,
                tint = categoryColor,
                modifier = Modifier.size(15.dp)
            )
        }

        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(3.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Text(
                    text = tip.category.displayName.uppercase(),
                    fontSize = 9.sp,
                    fontWeight = FontWeight.Bold,
                    color = categoryColor
                )
                Text(
                    text = "•",
                    fontSize = 8.sp,
                    color = ThemeColors.fgMutedDark
                )
                Text(
                    text = tip.title,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White
                )
            }

            Text(
                text = tip.advice,
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
                color = Color.White.copy(alpha = 0.9f),
                lineHeight = 18.sp
            )

            Text(
                text = tip.scientificRationale,
                fontSize = 11.sp,
                fontWeight = FontWeight.Normal,
                color = ThemeColors.fgMutedDark,
                lineHeight = 16.sp
            )
        }
    }
}

private fun getTipIcon(category: SleepTipCategory): ImageVector = when (category) {
    SleepTipCategory.CIRCADIAN -> Icons.Rounded.WbSunny
    SleepTipCategory.ENVIRONMENT -> Icons.Rounded.Thermostat
    SleepTipCategory.NUTRITION -> Icons.Rounded.LocalCafe
    SleepTipCategory.WIND_DOWN -> Icons.Rounded.SelfImprovement
}
