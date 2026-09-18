package com.intellidream.daily.presentation.weather

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CalendarToday
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.DailyForecastSummary
import com.intellidream.daily.model.WeatherConditionHelper
import kotlin.math.roundToInt

@Composable
fun DailyForecastCard(
    summaries: List<DailyForecastSummary>,
    unitSymbol: String = "°",
    modifier: Modifier = Modifier
) {
    if (summaries.isEmpty()) return

    val overallMin = summaries.minOfOrNull { it.tempMin } ?: 0.0
    val rawMax = summaries.maxOfOrNull { it.tempMax } ?: 30.0
    val overallMax = if (rawMax == overallMin) rawMax + 1.0 else rawMax

    GlassCard(
        modifier = modifier.fillMaxWidth(),
        cornerRadius = 22.dp,
        padding = 18.dp
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            // Header
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Icon(
                    imageVector = Icons.Rounded.CalendarToday,
                    contentDescription = null,
                    tint = ThemeColors.accentCyan,
                    modifier = Modifier.size(13.dp)
                )
                Text(
                    text = "5-DAY FORECAST",
                    color = Color.White.copy(alpha = 0.6f),
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 0.8.sp
                )
            }

            HorizontalDivider(
                color = Color.White.copy(alpha = 0.1f),
                thickness = 1.dp
            )

            // Forecast Rows
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                summaries.forEach { summary ->
                    val isToday = summary.dayName.equals("Today", ignoreCase = true)
                    val iconCode = summary.iconCode
                    val icon = getWeatherIcon(iconCode)
                    val iconColor = Color(WeatherConditionHelper.conditionColorHex(iconCode))
                    val popPercent = (summary.popMax * 100).roundToInt()

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        // Day Name & Date (65dp fixed width)
                        Column(
                            modifier = Modifier.width(65.dp),
                            verticalArrangement = Arrangement.spacedBy(1.dp)
                        ) {
                            Text(
                                text = summary.dayName,
                                color = if (isToday) ThemeColors.accentCyan else Color.White,
                                fontSize = 15.sp,
                                fontWeight = if (isToday) FontWeight.Bold else FontWeight.Medium
                            )
                            Text(
                                text = summary.dateFormatted,
                                color = Color.White.copy(alpha = 0.5f),
                                fontSize = 11.sp
                            )
                        }

                        // Icon & Pop Badge (60dp width)
                        Row(
                            modifier = Modifier.width(60.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            Icon(
                                imageVector = icon,
                                contentDescription = null,
                                tint = iconColor,
                                modifier = Modifier.size(20.dp)
                            )
                            if (popPercent >= 15) {
                                Text(
                                    text = "$popPercent%",
                                    color = ThemeColors.accentBlue,
                                    fontSize = 10.sp,
                                    fontWeight = FontWeight.Bold
                                )
                            }
                        }

                        // Min Temp (34dp width)
                        Text(
                            text = "${summary.tempMin.roundToInt()}$unitSymbol",
                            color = Color.White.copy(alpha = 0.6f),
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Medium,
                            modifier = Modifier.width(34.dp)
                        )

                        Spacer(modifier = Modifier.width(8.dp))

                        // Temperature Range Gradient Bar (Flexible weight)
                        BoxWithConstraints(
                            modifier = Modifier
                                .weight(1f)
                                .height(6.dp),
                            contentAlignment = Alignment.CenterStart
                        ) {
                            val totalWidth = maxWidth
                            val totalRange = overallMax - overallMin
                            val leftRatio = ((summary.tempMin - overallMin) / totalRange).coerceIn(0.0, 1.0)
                            val rightRatio = ((summary.tempMax - overallMin) / totalRange).coerceIn(0.0, 1.0)

                            val startOffset = totalWidth * leftRatio.toFloat()
                            val fillWidth = (totalWidth * (rightRatio - leftRatio).toFloat()).coerceAtLeast(8.dp)

                            // Background Track
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .height(5.dp)
                                    .clip(CircleShape)
                                    .background(Color.White.copy(alpha = 0.08f))
                            )

                            // Active Temperature Range Gradient Fill
                            Box(
                                modifier = Modifier
                                    .offset(x = startOffset)
                                    .width(fillWidth)
                                    .height(5.dp)
                                    .clip(CircleShape)
                                    .background(
                                        brush = Brush.horizontalGradient(
                                            listOf(
                                                ThemeColors.accentBlue,
                                                ThemeColors.accentCyan,
                                                Color(0xFFFFD166)
                                            )
                                        )
                                    )
                            )
                        }

                        Spacer(modifier = Modifier.width(8.dp))

                        // Max Temp (34dp width)
                        Text(
                            text = "${summary.tempMax.roundToInt()}$unitSymbol",
                            color = Color.White,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier.width(34.dp)
                        )
                    }
                }
            }
        }
    }
}
