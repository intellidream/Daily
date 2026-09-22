package com.intellidream.daily.presentation.health

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.DirectionsWalk
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.Nightlight
import androidx.compose.material.icons.rounded.Scale
import androidx.compose.material.icons.rounded.SelfImprovement
import androidx.compose.material.icons.rounded.ShowChart
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.DailyMetricTrendPoint
import com.intellidream.daily.model.HealthMetricType
import java.util.Locale
import kotlin.math.max
import kotlin.math.roundToInt

@Composable
fun HealthTrendsView(
    historicalTrends: Map<HealthMetricType, List<DailyMetricTrendPoint>>,
    modifier: Modifier = Modifier
) {
    val displayedMetrics = listOf(
        HealthMetricType.STEPS,
        HealthMetricType.SLEEP_DURATION,
        HealthMetricType.HEART_RATE,
        HealthMetricType.STRESS,
        HealthMetricType.ACTIVE_ENERGY,
        HealthMetricType.HRV_SDNN,
        HealthMetricType.WEIGHT
    )

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        displayedMetrics.forEach { metric ->
            val points = historicalTrends[metric] ?: emptyList()
            TrendCard(metric = metric, points = points)
        }
    }
}

@Composable
private fun TrendCard(
    metric: HealthMetricType,
    points: List<DailyMetricTrendPoint>
) {
    GlassCard(
        modifier = Modifier.fillMaxWidth(),
        cornerRadius = 22.dp,
        padding = 18.dp
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // Header
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Icon(
                    imageVector = getTrendIcon(metric),
                    contentDescription = null,
                    tint = ThemeColors.accentCyan,
                    modifier = Modifier.size(18.dp)
                )

                Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                    Text(
                        text = "7-DAY EVOLUTION",
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        color = ThemeColors.accentCyan
                    )
                    Text(
                        text = metric.displayName,
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                }
            }

            // Daily Capsule Bars Chart
            if (points.isNotEmpty()) {
                DailyCapsuleBarChart(metric = metric, points = points)
            }

            HorizontalDivider(color = Color.White.copy(alpha = 0.08f))

            // Stats Grid (AVG, HIGH, LOW, TOTAL/LATEST)
            StatsGrid(metric = metric, points = points)
        }
    }
}

@Composable
private fun DailyCapsuleBarChart(
    metric: HealthMetricType,
    points: List<DailyMetricTrendPoint>
) {
    val maxVal = max(1.0, points.maxOfOrNull { it.value } ?: 1.0)
    val minVal = points.minOfOrNull { it.value } ?: 0.0
    val isFluctuating = metric == HealthMetricType.HEART_RATE ||
            metric == HealthMetricType.HRV_SDNN ||
            metric == HealthMetricType.WEIGHT

    val isStress = metric == HealthMetricType.STRESS
    val barGradient = if (isStress) {
        Brush.verticalGradient(colors = listOf(Color(0xFFFFA726), Color(0xFFFF7043)))
    } else {
        Brush.verticalGradient(colors = listOf(ThemeColors.accentCyan, ThemeColors.accentBlue))
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(155.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.Bottom
    ) {
        points.forEach { pt ->
            val normalizedFrac = if (isStress) {
                (pt.value / 100.0).toFloat().coerceIn(0.08f, 1f)
            } else if (isFluctuating) {
                if (maxVal > minVal) {
                    (((pt.value - minVal) / (maxVal - minVal)) * 0.75 + 0.15).toFloat()
                } else 0.5f
            } else {
                (pt.value / maxVal).toFloat().coerceIn(0.1f, 1f)
            }

            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.weight(1f)
            ) {
                // Bar container
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(120.dp),
                    contentAlignment = Alignment.BottomCenter
                ) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth(0.6f)
                            .fillMaxHeight(if (pt.value > 0) normalizedFrac else 0.04f)
                            .clip(CircleShape)
                            .background(barGradient)
                            .then(
                                Modifier.background(
                                    Color.White.copy(
                                        alpha = if (pt.value > 0) (if (pt.isCompleteDay) 0f else 0.4f) else 0.8f
                                    )
                                )
                            )
                    )
                }

                // Day Name
                Text(
                    text = pt.dayName,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = if (pt.isCompleteDay) Color.White.copy(alpha = 0.85f) else ThemeColors.fgMutedDark
                )
            }
        }
    }
}

@Composable
private fun StatsGrid(
    metric: HealthMetricType,
    points: List<DailyMetricTrendPoint>
) {
    val nonZeroValues = points.map { it.value }.filter { it > 0 }
    val avg = if (nonZeroValues.isNotEmpty()) nonZeroValues.average() else 0.0
    val high = nonZeroValues.maxOrNull() ?: 0.0
    val low = nonZeroValues.minOrNull() ?: 0.0
    val latest = points.lastOrNull()?.value ?: 0.0

    val isCumulative = metric == HealthMetricType.STEPS || metric == HealthMetricType.ACTIVE_ENERGY
    val totalOrLatest = if (isCumulative) nonZeroValues.sum() else latest

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        StatItem(label = "AVERAGE", value = formatStat(avg, metric))
        StatItem(label = "HIGH", value = formatStat(high, metric))
        StatItem(label = "LOW", value = formatStat(low, metric))
        StatItem(label = if (isCumulative) "TOTAL" else "LATEST", value = formatStat(totalOrLatest, metric))
    }
}

@Composable
private fun StatItem(label: String, value: String) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        Text(
            text = label,
            fontSize = 10.sp,
            fontWeight = FontWeight.Bold,
            color = ThemeColors.fgMutedDark
        )
        Text(
            text = value,
            fontSize = 14.sp,
            fontWeight = FontWeight.Bold,
            color = Color.White
        )
    }
}

private fun formatStat(valNum: Double, metric: HealthMetricType): String {
    if (valNum <= 0) return "--"
    return when (metric) {
        HealthMetricType.STEPS,
        HealthMetricType.ACTIVE_ENERGY,
        HealthMetricType.HEART_RATE,
        HealthMetricType.HRV_SDNN -> "${valNum.roundToInt()}"
        HealthMetricType.STRESS -> "${valNum.roundToInt()}/100"

        HealthMetricType.SLEEP_DURATION -> {
            val h = valNum.toInt() / 60
            val m = valNum.toInt() % 60
            "${h}h ${m}m"
        }

        HealthMetricType.WEIGHT -> String.format(Locale.getDefault(), "%.1f", valNum)
        else -> String.format(Locale.getDefault(), "%.1f", valNum)
    }
}

private fun getTrendIcon(metric: HealthMetricType): ImageVector = when (metric) {
    HealthMetricType.STEPS -> Icons.Rounded.DirectionsWalk
    HealthMetricType.SLEEP_DURATION -> Icons.Rounded.Nightlight
    HealthMetricType.HEART_RATE -> Icons.Rounded.Favorite
    HealthMetricType.ACTIVE_ENERGY -> Icons.Rounded.LocalFireDepartment
    HealthMetricType.HRV_SDNN -> Icons.Rounded.ShowChart
    HealthMetricType.STRESS -> Icons.Rounded.SelfImprovement
    HealthMetricType.WEIGHT -> Icons.Rounded.Scale
    else -> Icons.Rounded.ShowChart
}
