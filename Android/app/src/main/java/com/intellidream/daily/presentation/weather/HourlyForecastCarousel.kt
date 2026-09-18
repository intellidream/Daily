package com.intellidream.daily.presentation.weather

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AccessTime
import androidx.compose.material.icons.rounded.AcUnit
import androidx.compose.material.icons.rounded.Cloud
import androidx.compose.material.icons.rounded.FlashOn
import androidx.compose.material.icons.rounded.NightsStay
import androidx.compose.material.icons.rounded.WaterDrop
import androidx.compose.material.icons.rounded.WbCloudy
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
import com.intellidream.daily.model.ForecastItem
import com.intellidream.daily.model.WeatherConditionHelper
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.roundToInt

@Composable
fun HourlyForecastCarousel(
    items: List<ForecastItem>,
    unitSymbol: String = "°",
    modifier: Modifier = Modifier
) {
    val scrollState = rememberScrollState()
    val hourFormatter = SimpleDateFormat("h a", Locale.getDefault())

    GlassCard(
        modifier = modifier.fillMaxWidth(),
        cornerRadius = 22.dp,
        padding = 16.dp
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
                    imageVector = Icons.Rounded.AccessTime,
                    contentDescription = null,
                    tint = ThemeColors.accentCyan,
                    modifier = Modifier.size(14.dp)
                )
                Text(
                    text = "24-HOUR FORECAST",
                    color = Color.White.copy(alpha = 0.6f),
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 0.8.sp
                )
            }

            // Horizontal Carousel
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(scrollState),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                items.forEachIndexed { index, item ->
                    val isNow = index == 0
                    val iconCode = item.weather.firstOrNull()?.icon ?: "01d"
                    val icon = getWeatherIcon(iconCode)
                    val iconColor = Color(WeatherConditionHelper.conditionColorHex(iconCode))
                    val timeLabel = if (isNow) "Now" else hourFormatter.format(Date(item.dt * 1000L)).lowercase()
                    val tempValue = item.main.temp.roundToInt()
                    val popValue = ((item.pop ?: 0.0) * 100).roundToInt()

                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                        modifier = Modifier
                            .clip(RoundedCornerShape(16.dp))
                            .background(
                                if (isNow) ThemeColors.accentCyan.copy(alpha = 0.15f)
                                else Color.White.copy(alpha = 0.04f)
                            )
                            .then(
                                if (isNow) Modifier.border(
                                    1.dp,
                                    ThemeColors.accentCyan.copy(alpha = 0.4f),
                                    RoundedCornerShape(16.dp)
                                ) else Modifier
                            )
                            .padding(vertical = 10.dp, horizontal = 14.dp)
                    ) {
                        Text(
                            text = timeLabel,
                            color = if (isNow) ThemeColors.accentCyan else Color.White.copy(alpha = 0.8f),
                            fontSize = 13.sp,
                            fontWeight = if (isNow) FontWeight.Bold else FontWeight.Medium
                        )

                        Icon(
                            imageVector = icon,
                            contentDescription = null,
                            tint = iconColor,
                            modifier = Modifier.size(24.dp)
                        )

                        if (popValue > 0) {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(2.dp)
                            ) {
                                Icon(
                                    imageVector = Icons.Rounded.WaterDrop,
                                    contentDescription = null,
                                    tint = ThemeColors.accentBlue,
                                    modifier = Modifier.size(9.dp)
                                )
                                Text(
                                    text = "$popValue%",
                                    color = ThemeColors.accentBlue,
                                    fontSize = 10.sp,
                                    fontWeight = FontWeight.Bold
                                )
                            }
                        } else {
                            Spacer(modifier = Modifier.height(13.dp))
                        }

                        Text(
                            text = "$tempValue$unitSymbol",
                            color = Color.White,
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }
            }
        }
    }
}

internal fun getWeatherIcon(iconCode: String): ImageVector {
    return when (iconCode) {
        "01d" -> Icons.Rounded.WbSunny
        "01n" -> Icons.Rounded.NightsStay
        "02d", "02n" -> Icons.Rounded.WbCloudy
        "03d", "03n", "04d", "04n" -> Icons.Rounded.Cloud
        "09d", "09n", "10d", "10n" -> Icons.Rounded.WaterDrop
        "11d", "11n" -> Icons.Rounded.FlashOn
        "13d", "13n" -> Icons.Rounded.AcUnit
        else -> Icons.Rounded.Cloud
    }
}
