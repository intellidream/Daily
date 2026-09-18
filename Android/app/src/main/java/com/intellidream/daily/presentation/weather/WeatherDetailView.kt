package com.intellidream.daily.presentation.weather

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.Air
import androidx.compose.material.icons.rounded.ArrowDownward
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.Cloud
import androidx.compose.material.icons.rounded.Compress
import androidx.compose.material.icons.rounded.LocationOn
import androidx.compose.material.icons.rounded.MyLocation
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Visibility
import androidx.compose.material.icons.rounded.WaterDrop
import androidx.compose.material.icons.rounded.WbSunny
import androidx.compose.material.icons.rounded.Wifi
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.designsystem.GlassButton
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.AppSettings
import com.intellidream.daily.model.DailyForecastSummary
import com.intellidream.daily.model.ForecastItem
import com.intellidream.daily.model.LocationSource
import com.intellidream.daily.model.WeatherConditionHelper
import com.intellidream.daily.model.WeatherResponse
import com.intellidream.daily.network.WeatherRepository
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.roundToInt

@Composable
fun WeatherDetailView(
    weather: WeatherResponse?,
    hourlyForecasts: List<ForecastItem>,
    dailySummaries: List<DailyForecastSummary>,
    locationName: String,
    locationSource: LocationSource,
    isAutoLocation: Boolean,
    isLoading: Boolean,
    errorMessage: String?,
    settings: AppSettings,
    weatherRepository: WeatherRepository,
    onNavigateBack: () -> Unit,
    onRefreshWeather: () -> Unit,
    onSelectManualLocation: (Double, Double, String) -> Unit,
    onResetToAutoLocation: () -> Unit,
    modifier: Modifier = Modifier
) {
    var showingSearchSheet by remember { mutableStateOf(false) }
    val scrollState = rememberScrollState()

    val unitSymbol = settings.weatherUnitSystem.tempSymbol
    val speedUnit = if (settings.weatherUnitSystem == com.intellidream.daily.model.WeatherUnitSystem.Metric) "m/s" else "mph"
    val dateFormatter = remember { SimpleDateFormat("EEE, MMM d", Locale.getDefault()) }
    val timeFormatter = remember { SimpleDateFormat("HH:mm", Locale.getDefault()) }

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp, vertical = 8.dp)
    ) {
        // Top Location Bar
        TopLocationBar(
            cityName = locationName,
            formattedDate = dateFormatter.format(Date()),
            locationSource = locationSource,
            isAutoLocation = isAutoLocation,
            onBackClick = onNavigateBack,
            onSearchClick = { showingSearchSheet = true },
            onResetToAutoLocation = onResetToAutoLocation
        )

        Spacer(modifier = Modifier.height(16.dp))

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(scrollState)
                .padding(bottom = 110.dp), // Clear floating navigation capsule
            verticalArrangement = Arrangement.spacedBy(18.dp)
        ) {
            if (weather != null) {
                // Hero Weather Card
                HeroWeatherCard(
                    weather = weather,
                    unitSymbol = unitSymbol
                )

                // 24-Hour Forecast Carousel
                if (hourlyForecasts.isNotEmpty()) {
                    HourlyForecastCarousel(
                        items = hourlyForecasts,
                        unitSymbol = unitSymbol
                    )
                }

                // 5-Day Forecast Card
                if (dailySummaries.isNotEmpty()) {
                    DailyForecastCard(
                        summaries = dailySummaries,
                        unitSymbol = unitSymbol
                    )
                }

                // 2x3 Atmospheric Metrics Grid
                AtmosphericGrid(
                    weather = weather,
                    speedUnit = speedUnit,
                    timeFormatter = timeFormatter
                )
            } else if (isLoading) {
                // Loading Placeholder
                LoadingCard()
            } else if (!errorMessage.isNullOrEmpty()) {
                // Error Card
                ErrorCard(
                    message = errorMessage,
                    onRetry = onRefreshWeather
                )
            }
        }
    }

    if (showingSearchSheet) {
        CitySearchBottomSheet(
            weatherRepository = weatherRepository,
            isAutoLocation = isAutoLocation,
            onDismiss = { showingSearchSheet = false },
            onSelectLocation = onSelectManualLocation,
            onResetToAutoLocation = onResetToAutoLocation
        )
    }
}

@Composable
private fun TopLocationBar(
    cityName: String,
    formattedDate: String,
    locationSource: LocationSource,
    isAutoLocation: Boolean,
    onBackClick: () -> Unit,
    onSearchClick: () -> Unit,
    onResetToAutoLocation: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Back Button
        Box(
            modifier = Modifier
                .size(38.dp)
                .clip(CircleShape)
                .background(Color.White.copy(alpha = 0.08f))
                .border(1.dp, Color.White.copy(alpha = 0.12f), CircleShape)
                .clickable(onClick = onBackClick),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = Icons.AutoMirrored.Rounded.ArrowBack,
                contentDescription = "Back",
                tint = Color.White,
                modifier = Modifier.size(18.dp)
            )
        }

        Spacer(modifier = Modifier.width(12.dp))

        // Centered Location & Date
        Column(
            modifier = Modifier.weight(1f),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Text(
                    text = cityName,
                    color = Color.White,
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1
                )

                // Location Source Chip
                val (badgeIcon, badgeText) = when (locationSource) {
                    LocationSource.GPS -> Pair(Icons.Rounded.LocationOn, "GPS")
                    LocationSource.IP -> Pair(Icons.Rounded.Wifi, "NET")
                    LocationSource.Manual -> Pair(Icons.Rounded.LocationOn, "CUSTOM")
                    LocationSource.Unknown -> Pair(Icons.Rounded.LocationOn, "AUTO")
                }

                Row(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(ThemeColors.accentCyan.copy(alpha = 0.18f))
                        .padding(horizontal = 6.dp, vertical = 2.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(3.dp)
                ) {
                    Icon(
                        imageVector = badgeIcon,
                        contentDescription = null,
                        tint = ThemeColors.accentCyan,
                        modifier = Modifier.size(9.dp)
                    )
                    Text(
                        text = badgeText,
                        color = ThemeColors.accentCyan,
                        fontSize = 9.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
            }

            Text(
                text = formattedDate,
                color = Color.White.copy(alpha = 0.6f),
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium
            )
        }

        Spacer(modifier = Modifier.width(12.dp))

        // Right Quick Actions
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            if (!isAutoLocation) {
                Box(
                    modifier = Modifier
                        .size(38.dp)
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.08f))
                        .border(1.dp, Color.White.copy(alpha = 0.12f), CircleShape)
                        .clickable(onClick = onResetToAutoLocation),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = Icons.Rounded.MyLocation,
                        contentDescription = "Reset Location",
                        tint = ThemeColors.accentCyan,
                        modifier = Modifier.size(18.dp)
                    )
                }
            }

            Box(
                modifier = Modifier
                    .size(38.dp)
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.08f))
                    .border(1.dp, Color.White.copy(alpha = 0.12f), CircleShape)
                    .clickable(onClick = onSearchClick),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Rounded.Search,
                    contentDescription = "Search Location",
                    tint = Color.White,
                    modifier = Modifier.size(18.dp)
                )
            }
        }
    }
}

@Composable
private fun HeroWeatherCard(
    weather: WeatherResponse,
    unitSymbol: String
) {
    val condition = weather.weather.firstOrNull()
    val iconCode = condition?.icon ?: "01d"
    val icon = getWeatherIcon(iconCode)
    val desc = condition?.description?.replaceFirstChar { it.uppercase() } ?: "Clear"
    val temp = weather.main.temp.roundToInt()
    val feelsLike = weather.main.feelsLike?.roundToInt() ?: temp
    val tempMin = weather.main.tempMin.roundToInt()
    val tempMax = weather.main.tempMax.roundToInt()
    val ambientColor = Color(WeatherConditionHelper.conditionColorHex(iconCode))

    GlassCard(
        modifier = Modifier.fillMaxWidth(),
        cornerRadius = 24.dp,
        padding = 22.dp
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // Top Condition Pill & High/Low Range
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = desc,
                    color = Color.White,
                    fontSize = 18.sp,
                    fontWeight = FontWeight.SemiBold
                )

                Row(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.08f))
                        .padding(horizontal = 10.dp, vertical = 5.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(3.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.ArrowDownward,
                            contentDescription = null,
                            tint = ThemeColors.accentBlue,
                            modifier = Modifier.size(11.dp)
                        )
                        Text(
                            text = "$tempMin°",
                            color = Color.White.copy(alpha = 0.85f),
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                    }

                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(3.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.ArrowUpward,
                            contentDescription = null,
                            tint = Color(0xFFFFD166),
                            modifier = Modifier.size(11.dp)
                        )
                        Text(
                            text = "$tempMax°",
                            color = Color.White.copy(alpha = 0.85f),
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }
            }

            // Middle: Temperature & Ambient Icon
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        text = "$temp°",
                        color = Color.White,
                        fontSize = 68.sp,
                        fontWeight = FontWeight.Bold,
                        lineHeight = 72.sp
                    )

                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Text(
                            text = "FEELS LIKE",
                            color = Color.White.copy(alpha = 0.5f),
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                            letterSpacing = 0.6.sp
                        )
                        Text(
                            text = "$feelsLike$unitSymbol",
                            color = Color.White.copy(alpha = 0.9f),
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }

                // Ambient Icon
                Box(
                    modifier = Modifier.size(80.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Box(
                        modifier = Modifier
                            .size(70.dp)
                            .clip(CircleShape)
                            .background(ambientColor.copy(alpha = 0.25f))
                            .blur(18.dp)
                    )

                    Icon(
                        imageVector = icon,
                        contentDescription = null,
                        tint = ambientColor,
                        modifier = Modifier.size(60.dp)
                    )
                }
            }
        }
    }
}

@Composable
private fun AtmosphericGrid(
    weather: WeatherResponse,
    speedUnit: String,
    timeFormatter: SimpleDateFormat
) {
    val windSpeed = weather.wind?.speed ?: 0.0
    val windDir = weather.wind?.cardinalDirection ?: "N/A"
    val humidity = weather.main.humidity
    val pressure = weather.main.pressure
    val visibilityKm = (weather.visibility ?: 10000) / 1000.0
    val clouds = weather.clouds?.all ?: 0

    val sunriseDate = weather.sys?.sunrise?.let { Date(it * 1000L) }
    val sunsetDate = weather.sys?.sunset?.let { Date(it * 1000L) }
    val sunriseStr = sunriseDate?.let { timeFormatter.format(it) } ?: "--:--"
    val sunsetStr = sunsetDate?.let { timeFormatter.format(it) } ?: "--:--"

    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        // Row 1: Wind & Humidity
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Box(modifier = Modifier.weight(1f)) {
                AtmosphericMetricTile(
                    icon = Icons.Rounded.Air,
                    title = "Wind",
                    value = String.format(Locale.US, "%.1f", windSpeed),
                    unit = speedUnit,
                    subtitle = "Direction: $windDir",
                    accentColor = ThemeColors.accentCyan
                )
            }
            Box(modifier = Modifier.weight(1f)) {
                AtmosphericMetricTile(
                    icon = Icons.Rounded.WaterDrop,
                    title = "Humidity",
                    value = "$humidity",
                    unit = "%",
                    subtitle = if (humidity > 65) "High moisture" else if (humidity < 35) "Dry air" else "Comfortable",
                    accentColor = ThemeColors.accentBlue
                )
            }
        }

        // Row 2: Pressure & Visibility
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Box(modifier = Modifier.weight(1f)) {
                AtmosphericMetricTile(
                    icon = Icons.Rounded.Compress,
                    title = "Pressure",
                    value = "$pressure",
                    unit = "hPa",
                    subtitle = if (pressure >= 1013) "High pressure" else "Low pressure",
                    accentColor = Color(0xFF7FF0D5)
                )
            }
            Box(modifier = Modifier.weight(1f)) {
                AtmosphericMetricTile(
                    icon = Icons.Rounded.Visibility,
                    title = "Visibility",
                    value = String.format(Locale.US, "%.0f", visibilityKm),
                    unit = "km",
                    subtitle = if (visibilityKm >= 10.0) "Clear view" else "Reduced visibility",
                    accentColor = Color(0xFFA0B2C6)
                )
            }
        }

        // Row 3: Clouds & Sun Schedule
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Box(modifier = Modifier.weight(1f)) {
                AtmosphericMetricTile(
                    icon = Icons.Rounded.Cloud,
                    title = "Clouds",
                    value = "$clouds",
                    unit = "%",
                    subtitle = if (clouds > 70) "Overcast skies" else if (clouds > 30) "Partly cloudy" else "Clear skies",
                    accentColor = Color(0xFF90A4AE)
                )
            }
            Box(modifier = Modifier.weight(1f)) {
                AtmosphericMetricTile(
                    icon = Icons.Rounded.WbSunny,
                    title = "Sun Schedule",
                    value = sunriseStr,
                    unit = "↑",
                    subtitle = "Sunset: $sunsetStr ↓",
                    accentColor = Color(0xFFFFD166)
                )
            }
        }
    }
}

@Composable
private fun LoadingCard() {
    GlassCard(
        modifier = Modifier.fillMaxWidth(),
        cornerRadius = 24.dp,
        padding = 32.dp
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            CircularProgressIndicator(
                color = ThemeColors.accentCyan,
                strokeWidth = 3.dp,
                modifier = Modifier.size(36.dp)
            )
            Text(
                text = "Fetching live atmospheric telemetry...",
                color = Color.White.copy(alpha = 0.7f),
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium
            )
        }
    }
}

@Composable
private fun ErrorCard(
    message: String,
    onRetry: () -> Unit
) {
    GlassCard(
        modifier = Modifier.fillMaxWidth(),
        cornerRadius = 24.dp,
        padding = 24.dp
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                text = "Unable to Load Weather",
                color = Color.White,
                fontSize = 16.sp,
                fontWeight = FontWeight.Bold
            )
            Text(
                text = message,
                color = Color.White.copy(alpha = 0.7f),
                fontSize = 13.sp
            )
            GlassButton(
                onClick = onRetry,
                cornerRadius = 12.dp,
                paddingHorizontal = 16.dp,
                paddingVertical = 8.dp
            ) {
                Text(
                    text = "Try Again",
                    color = ThemeColors.accentCyan,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }
    }
}
