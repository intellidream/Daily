package com.intellidream.daily.presentation.dashboard

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.rounded.AcUnit
import androidx.compose.material.icons.rounded.Air
import androidx.compose.material.icons.rounded.Cloud
import androidx.compose.material.icons.rounded.FlashOn
import androidx.compose.material.icons.rounded.NightsStay
import androidx.compose.material.icons.rounded.Speed
import androidx.compose.material.icons.rounded.WaterDrop
import androidx.compose.material.icons.rounded.WbCloudy
import androidx.compose.material.icons.rounded.WbSunny
import androidx.compose.material.icons.rounded.WbTwilight
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.GlassIntensity
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.AppSettings
import com.intellidream.daily.model.DashboardWidgetSize
import com.intellidream.daily.model.ForecastItem
import com.intellidream.daily.model.ForecastResponse
import com.intellidream.daily.model.WeatherConditionHelper
import com.intellidream.daily.model.WeatherResponse
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.roundToInt

@Composable
fun WeatherDashboardCard(
    size: DashboardWidgetSize,
    weather: WeatherResponse?,
    forecast: ForecastResponse?,
    hourlyForecasts: List<ForecastItem>,
    locationName: String,
    isLoading: Boolean,
    settings: AppSettings,
    onTap: () -> Unit = {},
    onLongClick: (() -> Unit)? = null
) {
    val cardHeight = when (size) {
        DashboardWidgetSize.Small -> 155.dp
        DashboardWidgetSize.Wide -> 160.dp
        DashboardWidgetSize.Tall, DashboardWidgetSize.Large -> 324.dp
    }

    val glassIntensity = when (settings.glassIntensity) {
        com.intellidream.daily.model.GlassIntensity.Subtle -> GlassIntensity.Subtle
        com.intellidream.daily.model.GlassIntensity.Medium -> GlassIntensity.Medium
        com.intellidream.daily.model.GlassIntensity.Prominent -> GlassIntensity.Prominent
    }

    GlassCard(
        modifier = Modifier
            .fillMaxWidth()
            .height(cardHeight),
        cornerRadius = 20.dp,
        padding = if (size == DashboardWidgetSize.Small) 14.dp else 18.dp,
        intensity = glassIntensity,
        onClick = onTap,
        onLongClick = onLongClick
    ) {
        when (size) {
            DashboardWidgetSize.Small -> SmallWeatherContent(weather, locationName, isLoading, settings)
            DashboardWidgetSize.Wide -> WideWeatherContent(weather, locationName, isLoading, settings)
            DashboardWidgetSize.Tall -> TallWeatherContent(weather, hourlyForecasts, locationName, isLoading, settings)
            DashboardWidgetSize.Large -> LargeWeatherContent(weather, forecast, hourlyForecasts, locationName, isLoading, settings)
        }
    }
}

// MARK: - Small (1x1) Compact Glance
@Composable
private fun SmallWeatherContent(
    weather: WeatherResponse?,
    locationName: String,
    isLoading: Boolean,
    settings: AppSettings
) {
    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        // Header
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            val iconCode = weather?.weather?.firstOrNull()?.icon ?: "01d"
            Icon(
                imageVector = getWeatherIcon(iconCode),
                contentDescription = null,
                tint = Color(WeatherConditionHelper.conditionColorHex(iconCode)),
                modifier = Modifier.size(18.dp)
            )

            Text(
                text = locationName,
                color = ThemeColors.textMuted,
                fontSize = 11.sp,
                fontWeight = FontWeight.Medium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f, fill = false).padding(start = 6.dp)
            )
        }

        if (weather != null) {
            val temp = weather.main.temp.roundToInt()
            val tempMin = weather.main.tempMin.roundToInt()
            val tempMax = weather.main.tempMax.roundToInt()
            val desc = weather.weather.firstOrNull()?.description?.replaceFirstChar { it.uppercase() } ?: "Clear"

            Column {
                Row(verticalAlignment = Alignment.Top) {
                    Text(
                        text = "$temp",
                        color = Color.White,
                        fontSize = 36.sp,
                        fontWeight = FontWeight.Thin
                    )
                    Text(
                        text = "°",
                        color = Color.White,
                        fontSize = 20.sp,
                        fontWeight = FontWeight.Light
                    )
                }
                Text(
                    text = desc,
                    color = Color.White,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "H:$tempMax° L:$tempMin°",
                    color = ThemeColors.textMuted,
                    fontSize = 10.sp
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = Icons.Rounded.WaterDrop,
                        contentDescription = null,
                        tint = ThemeColors.accentCyan,
                        modifier = Modifier.size(9.dp)
                    )
                    Spacer(modifier = Modifier.width(2.dp))
                    Text(
                        text = "${weather.main.humidity}%",
                        color = Color.White.copy(alpha = 0.85f),
                        fontSize = 10.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                }
            }
        } else if (isLoading) {
            CircularProgressIndicator(
                color = ThemeColors.accentCyan,
                strokeWidth = 2.dp,
                modifier = Modifier.size(24.dp)
            )
            Text(
                text = "Loading...",
                color = ThemeColors.textMuted,
                fontSize = 11.sp
            )
        } else {
            Text(
                text = "--°",
                color = Color.White.copy(alpha = 0.4f),
                fontSize = 36.sp,
                fontWeight = FontWeight.Thin
            )
            Text(
                text = "Tap to load",
                color = ThemeColors.textMuted,
                fontSize = 11.sp
            )
        }
    }
}

// MARK: - Wide (2x1) Standard Card
@Composable
private fun WideWeatherContent(
    weather: WeatherResponse?,
    locationName: String,
    isLoading: Boolean,
    settings: AppSettings
) {
    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        // Header
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = Icons.Rounded.WbCloudy,
                    contentDescription = null,
                    tint = ThemeColors.accentCyan,
                    modifier = Modifier.size(16.dp)
                )
                Spacer(modifier = Modifier.width(6.dp))
                Text(
                    text = "Weather",
                    color = ThemeColors.accentCyan,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }

            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = locationName,
                    color = ThemeColors.textMuted,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium
                )
                Spacer(modifier = Modifier.width(2.dp))
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                    contentDescription = null,
                    tint = ThemeColors.textMuted,
                    modifier = Modifier.size(14.dp)
                )
            }
        }

        if (weather != null) {
            val iconCode = weather.weather.firstOrNull()?.icon ?: "01d"
            val temp = weather.main.temp.roundToInt()
            val tempMin = weather.main.tempMin.roundToInt()
            val tempMax = weather.main.tempMax.roundToInt()
            val desc = weather.weather.firstOrNull()?.description?.replaceFirstChar { it.uppercase() } ?: "Clear"
            val unitSymbol = settings.weatherUnitSystem.tempSymbol

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Row(verticalAlignment = Alignment.Top) {
                        Text(
                            text = "$temp",
                            color = Color.White,
                            fontSize = 48.sp,
                            fontWeight = FontWeight.Thin
                        )
                        Text(
                            text = "°",
                            color = Color.White,
                            fontSize = 28.sp,
                            fontWeight = FontWeight.Light
                        )
                    }

                    Spacer(modifier = Modifier.width(16.dp))

                    Column {
                        Text(
                            text = desc,
                            color = Color.White,
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Medium
                        )
                        Spacer(modifier = Modifier.height(2.dp))
                        Text(
                            text = "H: $tempMax$unitSymbol · L: $tempMin$unitSymbol",
                            color = ThemeColors.textMuted,
                            fontSize = 12.sp
                        )
                    }
                }

                Icon(
                    imageVector = getWeatherIcon(iconCode),
                    contentDescription = null,
                    tint = Color(WeatherConditionHelper.conditionColorHex(iconCode)),
                    modifier = Modifier.size(36.dp)
                )
            }
        } else if (isLoading) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.padding(vertical = 12.dp)
            ) {
                CircularProgressIndicator(
                    color = ThemeColors.accentCyan,
                    strokeWidth = 2.dp,
                    modifier = Modifier.size(20.dp)
                )
                Spacer(modifier = Modifier.width(12.dp))
                Text(
                    text = "Updating atmospheric telemetry...",
                    color = Color.White.copy(alpha = 0.7f),
                    fontSize = 13.sp
                )
            }
        } else {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "--°",
                    color = Color.White.copy(alpha = 0.4f),
                    fontSize = 46.sp,
                    fontWeight = FontWeight.Thin
                )
                Spacer(modifier = Modifier.width(16.dp))
                Column {
                    Text(
                        text = "Tap to load weather",
                        color = Color.White.copy(alpha = 0.8f),
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Medium
                    )
                    Text(
                        text = "Real-time telemetry",
                        color = ThemeColors.textMuted,
                        fontSize = 12.sp
                    )
                }
            }
        }
    }
}

// MARK: - Tall (1x2) Vertical Forecast Tower
@Composable
private fun TallWeatherContent(
    weather: WeatherResponse?,
    hourlyForecasts: List<ForecastItem>,
    locationName: String,
    isLoading: Boolean,
    settings: AppSettings
) {
    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        // Header
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = Icons.Rounded.WbSunny,
                    contentDescription = null,
                    tint = ThemeColors.accentCyan,
                    modifier = Modifier.size(14.dp)
                )
                Spacer(modifier = Modifier.width(4.dp))
                Text(
                    text = "Weather",
                    color = ThemeColors.accentCyan,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }

            Text(
                text = locationName,
                color = ThemeColors.textMuted,
                fontSize = 11.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }

        if (weather != null) {
            val iconCode = weather.weather.firstOrNull()?.icon ?: "01d"
            val temp = weather.main.temp.roundToInt()
            val desc = weather.weather.firstOrNull()?.description?.replaceFirstChar { it.uppercase() } ?: "Clear"

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Row(verticalAlignment = Alignment.Top) {
                        Text(
                            text = "$temp",
                            color = Color.White,
                            fontSize = 34.sp,
                            fontWeight = FontWeight.Thin
                        )
                        Text(
                            text = "°",
                            color = Color.White,
                            fontSize = 20.sp,
                            fontWeight = FontWeight.Light
                        )
                    }
                    Text(
                        text = desc,
                        color = Color.White,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Medium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }

                Icon(
                    imageVector = getWeatherIcon(iconCode),
                    contentDescription = null,
                    tint = Color(WeatherConditionHelper.conditionColorHex(iconCode)),
                    modifier = Modifier.size(30.dp)
                )
            }

            HorizontalDivider(color = Color.White.copy(alpha = 0.10f))

            Text(
                text = "HOURLY FORECAST",
                color = ThemeColors.textMuted,
                fontSize = 9.sp,
                fontWeight = FontWeight.Bold,
                letterSpacing = 1.sp
            )

            // 4 vertical hourly entries
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                hourlyForecasts.take(4).forEach { item ->
                    val hourStr = formatHour(item.dt)
                    val itemIcon = item.weather.firstOrNull()?.icon ?: "01d"
                    val itemTemp = item.main.temp.roundToInt()

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = hourStr,
                            color = ThemeColors.textMuted,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Medium,
                            modifier = Modifier.width(42.dp)
                        )

                        Icon(
                            imageVector = getWeatherIcon(itemIcon),
                            contentDescription = null,
                            tint = Color(WeatherConditionHelper.conditionColorHex(itemIcon)),
                            modifier = Modifier.size(15.dp)
                        )

                        Text(
                            text = "$itemTemp°",
                            color = Color.White,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier.width(32.dp)
                        )
                    }
                }
            }

            HorizontalDivider(color = Color.White.copy(alpha = 0.10f))

            // Bottom tags: Humidity and Wind
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = Icons.Rounded.WaterDrop,
                        contentDescription = null,
                        tint = ThemeColors.accentCyan,
                        modifier = Modifier.size(11.dp)
                    )
                    Spacer(modifier = Modifier.width(3.dp))
                    Text(
                        text = "${weather.main.humidity}%",
                        color = Color.White,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                }

                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = Icons.Rounded.Air,
                        contentDescription = null,
                        tint = ThemeColors.accentBlue,
                        modifier = Modifier.size(11.dp)
                    )
                    Spacer(modifier = Modifier.width(3.dp))
                    Text(
                        text = "${(weather.wind?.speed ?: 0.0).roundToInt()} ${settings.weatherWindUnit}",
                        color = Color.White,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                }
            }
        } else {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(text = "Tap to load weather", color = ThemeColors.textMuted, fontSize = 12.sp)
            }
        }
    }
}

// MARK: - Large (2x2) Extended Weather Station
@Composable
private fun LargeWeatherContent(
    weather: WeatherResponse?,
    forecast: ForecastResponse?,
    hourlyForecasts: List<ForecastItem>,
    locationName: String,
    isLoading: Boolean,
    settings: AppSettings
) {
    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        // Header
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = Icons.Rounded.WbSunny,
                    contentDescription = null,
                    tint = ThemeColors.accentCyan,
                    modifier = Modifier.size(16.dp)
                )
                Spacer(modifier = Modifier.width(6.dp))
                Text(
                    text = "Weather Station",
                    color = ThemeColors.accentCyan,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }

            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = locationName,
                    color = ThemeColors.textMuted,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium
                )
                Spacer(modifier = Modifier.width(2.dp))
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                    contentDescription = null,
                    tint = ThemeColors.textMuted,
                    modifier = Modifier.size(14.dp)
                )
            }
        }

        if (weather != null) {
            val iconCode = weather.weather.firstOrNull()?.icon ?: "01d"
            val temp = weather.main.temp.roundToInt()
            val tempMin = weather.main.tempMin.roundToInt()
            val tempMax = weather.main.tempMax.roundToInt()
            val desc = weather.weather.firstOrNull()?.description?.replaceFirstChar { it.uppercase() } ?: "Clear"
            val unitSymbol = settings.weatherUnitSystem.tempSymbol

            // Main hero row
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Row(verticalAlignment = Alignment.Top) {
                        Text(
                            text = "$temp",
                            color = Color.White,
                            fontSize = 44.sp,
                            fontWeight = FontWeight.Thin
                        )
                        Text(
                            text = "°",
                            color = Color.White,
                            fontSize = 24.sp,
                            fontWeight = FontWeight.Light
                        )
                    }

                    Spacer(modifier = Modifier.width(16.dp))

                    Column {
                        Text(
                            text = desc,
                            color = Color.White,
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Medium
                        )
                        Text(
                            text = "H: $tempMax$unitSymbol · L: $tempMin$unitSymbol",
                            color = ThemeColors.textMuted,
                            fontSize = 12.sp
                        )
                    }
                }

                Icon(
                    imageVector = getWeatherIcon(iconCode),
                    contentDescription = null,
                    tint = Color(WeatherConditionHelper.conditionColorHex(iconCode)),
                    modifier = Modifier.size(40.dp)
                )
            }

            HorizontalDivider(color = Color.White.copy(alpha = 0.10f))

            // Horizontal hourly strip
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                hourlyForecasts.take(6).forEach { item ->
                    val hourStr = formatHour(item.dt)
                    val itemIcon = item.weather.firstOrNull()?.icon ?: "01d"
                    val itemTemp = item.main.temp.roundToInt()

                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        Text(
                            text = hourStr,
                            color = ThemeColors.textMuted,
                            fontSize = 11.sp
                        )
                        Icon(
                            imageVector = getWeatherIcon(itemIcon),
                            contentDescription = null,
                            tint = Color(WeatherConditionHelper.conditionColorHex(itemIcon)),
                            modifier = Modifier.size(16.dp)
                        )
                        Text(
                            text = "$itemTemp°",
                            color = Color.White,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Medium
                        )
                    }
                }
            }

            HorizontalDivider(color = Color.White.copy(alpha = 0.10f))

            // 4-tile atmospheric grid
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                TelemetryMiniTile(
                    title = "Humidity",
                    value = "${weather.main.humidity}%",
                    icon = Icons.Rounded.WaterDrop,
                    iconTint = ThemeColors.accentCyan,
                    modifier = Modifier.weight(1f)
                )
                TelemetryMiniTile(
                    title = "Wind",
                    value = "${(weather.wind?.speed ?: 0.0).roundToInt()} ${settings.weatherWindUnit}",
                    icon = Icons.Rounded.Air,
                    iconTint = ThemeColors.accentBlue,
                    modifier = Modifier.weight(1f)
                )
                TelemetryMiniTile(
                    title = "Pressure",
                    value = "${weather.main.pressure} hPa",
                    icon = Icons.Rounded.Speed,
                    iconTint = ThemeColors.accentCyan,
                    modifier = Modifier.weight(1f)
                )
                val sunriseTime = weather.sys?.sunrise?.let { formatTime(it) } ?: "06:30"
                TelemetryMiniTile(
                    title = "Sunrise",
                    value = sunriseTime,
                    icon = Icons.Rounded.WbTwilight,
                    iconTint = Color(0xFFFFD166),
                    modifier = Modifier.weight(1f)
                )
            }
        } else {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(text = "Tap to load weather", color = ThemeColors.textMuted, fontSize = 12.sp)
            }
        }
    }
}

@Composable
private fun TelemetryMiniTile(
    title: String,
    value: String,
    icon: ImageVector,
    iconTint: Color,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .background(
                color = Color.White.copy(alpha = 0.05f),
                shape = RoundedCornerShape(10.dp)
            )
            .padding(horizontal = 8.dp, vertical = 6.dp)
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = iconTint,
                    modifier = Modifier.size(10.dp)
                )
                Spacer(modifier = Modifier.width(3.dp))
                Text(
                    text = title,
                    color = ThemeColors.textMuted,
                    fontSize = 9.sp,
                    maxLines = 1
                )
            }
            Text(
                text = value,
                color = Color.White,
                fontSize = 11.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1
            )
        }
    }
}

private fun getWeatherIcon(iconCode: String): ImageVector {
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

private fun formatHour(dt: Long): String {
    val date = Date(dt * 1000L)
    val formatter = SimpleDateFormat("HH:mm", Locale.getDefault())
    return formatter.format(date)
}

private fun formatTime(dt: Long): String {
    val date = Date(dt * 1000L)
    val formatter = SimpleDateFormat("HH:mm", Locale.getDefault())
    return formatter.format(date)
}
