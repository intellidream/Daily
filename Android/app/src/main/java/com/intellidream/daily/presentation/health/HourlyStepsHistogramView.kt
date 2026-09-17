package com.intellidream.daily.presentation.health

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Bolt
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.HourlyStepBucket
import kotlin.math.max

@Composable
fun HourlyStepsHistogramView(
    totalSteps: Int,
    hourlySteps: List<HourlyStepBucket>,
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
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        text = "STEP CADENCE",
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        color = ThemeColors.accentCyan
                    )

                    Row(
                        verticalAlignment = Alignment.Bottom,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Text(
                            text = "$totalSteps",
                            fontSize = 30.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White
                        )
                        Text(
                            text = "STEPS",
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = ThemeColors.fgMutedDark,
                            modifier = Modifier.padding(bottom = 3.dp)
                        )
                    }
                }

                // Active Hours Callout
                val activeHours = hourlySteps.count { it.steps >= 250 }
                Column(
                    horizontalAlignment = Alignment.End,
                    verticalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    Text(
                        text = "Active Hours",
                        fontSize = 11.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = ThemeColors.fgMutedDark
                    )
                    Text(
                        text = "$activeHours of 12 hrs",
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold,
                        color = ThemeColors.accentCyan
                    )
                }
            }

            // 24-Hour Cadence Bar Chart (Canvas)
            val maxSteps = max(500, hourlySteps.maxOfOrNull { it.steps } ?: 500)
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Canvas(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(110.dp)
                ) {
                    val canvasWidth = size.width
                    val canvasHeight = size.height
                    val barCount = 24
                    val spacing = 3.dp.toPx()
                    val totalSpacing = spacing * (barCount - 1)
                    val barWidth = max(2f, (canvasWidth - totalSpacing) / barCount)

                    // Draw baseline grid lines
                    val midY = canvasHeight * 0.5f
                    drawLine(
                        color = Color.White.copy(alpha = 0.06f),
                        start = Offset(0f, midY),
                        end = Offset(canvasWidth, midY),
                        strokeWidth = 1.dp.toPx()
                    )

                    for (h in 0 until barCount) {
                        val bucket = hourlySteps.firstOrNull { it.hour == h }
                        val steps = bucket?.steps ?: 0
                        val barHeight = if (steps > 0) {
                            max(4.dp.toPx(), (steps.toFloat() / maxSteps.toFloat()) * canvasHeight)
                        } else {
                            2.dp.toPx()
                        }

                        val x = h * (barWidth + spacing)
                        val y = canvasHeight - barHeight

                        val color = when {
                            steps >= 1000 -> ThemeColors.accentCyan
                            steps >= 250 -> ThemeColors.accentBlue
                            steps > 0 -> Color.White.copy(alpha = 0.35f)
                            else -> Color.White.copy(alpha = 0.12f)
                        }

                        drawRoundRect(
                            color = color,
                            topLeft = Offset(x, y),
                            size = Size(barWidth, barHeight),
                            cornerRadius = CornerRadius(3.dp.toPx(), 3.dp.toPx())
                        )
                    }
                }

                // X-Axis Hour Labels
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    listOf("00:00", "06:00", "12:00", "18:00", "23:00").forEach { label ->
                        Text(
                            text = label,
                            fontSize = 9.sp,
                            fontWeight = FontWeight.Medium,
                            color = ThemeColors.fgMutedDark
                        )
                    }
                }
            }

            // Peak Hour Callout
            val peak = hourlySteps.maxByOrNull { it.steps }
            if (peak != null && peak.steps > 0) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.06f))
                        .padding(horizontal = 10.dp, vertical = 6.dp)
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Bolt,
                        contentDescription = null,
                        tint = Color(0xFFFFD600),
                        modifier = Modifier.size(13.dp)
                    )
                    Text(
                        text = "Peak activity at ${peak.hourFormatted}:",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Medium,
                        color = ThemeColors.fgMutedDark
                    )
                    Text(
                        text = "${peak.steps} steps",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                }
            }
        }
    }
}
