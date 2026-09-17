package com.intellidream.daily.presentation.health

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.BatteryAlert
import androidx.compose.material.icons.rounded.Bolt
import androidx.compose.material.icons.rounded.FitnessCenter
import androidx.compose.material.icons.rounded.Psychology
import androidx.compose.material.icons.rounded.Shield
import androidx.compose.material.icons.rounded.ShowChart
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material3.HorizontalDivider
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
import com.intellidream.daily.model.SleepRecoveryStatus
import com.intellidream.daily.model.SleepRecoveryVerdict

@Composable
fun SleepVerdictCard(
    verdict: SleepRecoveryVerdict,
    modifier: Modifier = Modifier
) {
    val statusColor = Color(android.graphics.Color.parseColor(verdict.status.hexColor))

    GlassCard(
        modifier = modifier.fillMaxWidth(),
        cornerRadius = 20.dp,
        padding = 18.dp
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            // Header & Readiness Badge
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Status Chip
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(statusColor.copy(alpha = 0.12f))
                        .border(1.dp, statusColor.copy(alpha = 0.3f), CircleShape)
                        .padding(horizontal = 10.dp, vertical = 4.dp)
                ) {
                    Icon(
                        imageVector = getStatusIcon(verdict.status),
                        contentDescription = null,
                        tint = statusColor,
                        modifier = Modifier.size(13.dp)
                    )
                    Text(
                        text = verdict.status.displayName.uppercase(),
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        color = statusColor
                    )
                }

                // Energy / Readiness Score Pill
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(5.dp),
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.08f))
                        .padding(horizontal = 10.dp, vertical = 4.dp)
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Bolt,
                        contentDescription = null,
                        tint = ThemeColors.accentCyan,
                        modifier = Modifier.size(12.dp)
                    )
                    Text(
                        text = "${verdict.readinessScore}% Readiness",
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                }
            }

            // Headline
            Text(
                text = verdict.headline,
                fontSize = 16.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White,
                lineHeight = 22.sp
            )

            // Narrative Synthesis
            Text(
                text = verdict.narrative,
                fontSize = 13.sp,
                fontWeight = FontWeight.Normal,
                color = Color.White.copy(alpha = 0.85f),
                lineHeight = 20.sp
            )

            HorizontalDivider(color = Color.White.copy(alpha = 0.08f))

            // 3 Recovery Pillars
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                PillarItem(
                    modifier = Modifier.weight(1f),
                    title = "Physical Repair",
                    rating = verdict.physicalRepairRating,
                    icon = Icons.Rounded.FitnessCenter
                )
                PillarItem(
                    modifier = Modifier.weight(1f),
                    title = "Cognitive Rest",
                    rating = verdict.cognitiveRestoreRating,
                    icon = Icons.Rounded.Psychology
                )
                PillarItem(
                    modifier = Modifier.weight(1f),
                    title = "Continuity",
                    rating = verdict.sleepContinuityRating,
                    icon = Icons.Rounded.ShowChart
                )
            }
        }
    }
}

@Composable
private fun PillarItem(
    modifier: Modifier = Modifier,
    title: String,
    rating: String,
    icon: ImageVector
) {
    val color = when (rating.lowercase()) {
        "high", "continuous" -> ThemeColors.accentCyan
        "adequate" -> Color(0xFF00E676)
        else -> Color(0xFFFFB300)
    }

    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = color,
            modifier = Modifier.size(12.dp)
        )
        Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(
                text = title,
                fontSize = 9.sp,
                fontWeight = FontWeight.Medium,
                color = ThemeColors.fgMutedDark
            )
            Text(
                text = rating,
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                color = color
            )
        }
    }
}

private fun getStatusIcon(status: SleepRecoveryStatus): ImageVector = when (status) {
    SleepRecoveryStatus.OPTIMAL -> Icons.Rounded.Shield
    SleepRecoveryStatus.GREAT -> Icons.Rounded.AutoAwesome
    SleepRecoveryStatus.FAIR -> Icons.Rounded.BatteryAlert
    SleepRecoveryStatus.DEFICIT -> Icons.Rounded.Warning
}
