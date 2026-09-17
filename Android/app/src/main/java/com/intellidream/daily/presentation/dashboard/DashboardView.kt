package com.intellidream.daily.presentation.dashboard

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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AccountBalanceWallet
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Feed
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.designsystem.GlassButton
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.GlassIntensity
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.AppSettings
import com.intellidream.daily.model.DashboardRow
import com.intellidream.daily.model.DashboardRowBuilder
import com.intellidream.daily.model.DashboardWidgetConfig
import com.intellidream.daily.model.DashboardWidgetSize
import com.intellidream.daily.model.DashboardWidgetType
import com.intellidream.daily.model.ForecastItem
import com.intellidream.daily.model.ForecastResponse
import com.intellidream.daily.model.UserProfile
import com.intellidream.daily.model.WeatherResponse
import java.util.Calendar

@Composable
fun DashboardView(
    userProfile: UserProfile?,
    settings: AppSettings,
    weather: WeatherResponse?,
    forecast: ForecastResponse?,
    hourlyForecasts: List<ForecastItem>,
    locationName: String,
    isWeatherLoading: Boolean,
    habitsRepository: com.intellidream.daily.database.HabitsRepository,
    onRefreshWeather: () -> Unit,
    onOpenSettings: () -> Unit,
    onOpenCustomize: () -> Unit,
    onNavigateToHabits: () -> Unit = {},
    modifier: Modifier = Modifier
) {
    val visibleWidgets = settings.dashboardWidgets.filter { it.isVisible }
    val rows = DashboardRowBuilder.buildRows(visibleWidgets)

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        // 1. Header Greeting with Settings & Refresh button
        item(key = "header_greeting") {
            DashboardHeader(
                userProfile = userProfile,
                isLoading = isWeatherLoading,
                onRefresh = onRefreshWeather,
                onOpenCustomize = onOpenCustomize,
                onOpenSettings = onOpenSettings
            )
        }

        // 2. Coalesced Rows
        items(
            items = rows,
            key = { it.id }
        ) { row ->
            when (row) {
                is DashboardRow.Full -> {
                    DashboardWidgetRenderer(
                        config = row.config,
                        weather = weather,
                        forecast = forecast,
                        hourlyForecasts = hourlyForecasts,
                        locationName = locationName,
                        isWeatherLoading = isWeatherLoading,
                        settings = settings,
                        habitsRepository = habitsRepository,
                        onRefreshWeather = onRefreshWeather,
                        onNavigateToHabits = onNavigateToHabits
                    )
                }

                is DashboardRow.Pair -> {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(14.dp)
                    ) {
                        Box(modifier = Modifier.weight(1f)) {
                            DashboardWidgetRenderer(
                                config = row.left,
                                weather = weather,
                                forecast = forecast,
                                hourlyForecasts = hourlyForecasts,
                                locationName = locationName,
                                isWeatherLoading = isWeatherLoading,
                                settings = settings,
                                habitsRepository = habitsRepository,
                                onRefreshWeather = onRefreshWeather,
                                onNavigateToHabits = onNavigateToHabits
                            )
                        }
                        Box(modifier = Modifier.weight(1f)) {
                            DashboardWidgetRenderer(
                                config = row.right,
                                weather = weather,
                                forecast = forecast,
                                hourlyForecasts = hourlyForecasts,
                                locationName = locationName,
                                isWeatherLoading = isWeatherLoading,
                                settings = settings,
                                habitsRepository = habitsRepository,
                                onRefreshWeather = onRefreshWeather,
                                onNavigateToHabits = onNavigateToHabits
                            )
                        }
                    }
                }

                is DashboardRow.TallWithSmalls -> {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(14.dp)
                    ) {
                        Box(modifier = Modifier.weight(1f)) {
                            DashboardWidgetRenderer(
                                config = row.tall,
                                weather = weather,
                                forecast = forecast,
                                hourlyForecasts = hourlyForecasts,
                                locationName = locationName,
                                isWeatherLoading = isWeatherLoading,
                                settings = settings,
                                habitsRepository = habitsRepository,
                                onRefreshWeather = onRefreshWeather,
                                onNavigateToHabits = onNavigateToHabits
                            )
                        }
                        Column(
                            modifier = Modifier.weight(1f),
                            verticalArrangement = Arrangement.spacedBy(14.dp)
                        ) {
                            row.smalls.forEach { smallConfig ->
                                DashboardWidgetRenderer(
                                    config = smallConfig,
                                    weather = weather,
                                    forecast = forecast,
                                    hourlyForecasts = hourlyForecasts,
                                    locationName = locationName,
                                    isWeatherLoading = isWeatherLoading,
                                    settings = settings,
                                    habitsRepository = habitsRepository,
                                    onRefreshWeather = onRefreshWeather,
                                    onNavigateToHabits = onNavigateToHabits
                                )
                            }
                        }
                    }
                }

                is DashboardRow.SingleSmall -> {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(14.dp)
                    ) {
                        Box(modifier = Modifier.weight(1f)) {
                            DashboardWidgetRenderer(
                                config = row.config,
                                weather = weather,
                                forecast = forecast,
                                hourlyForecasts = hourlyForecasts,
                                locationName = locationName,
                                isWeatherLoading = isWeatherLoading,
                                settings = settings,
                                habitsRepository = habitsRepository,
                                onRefreshWeather = onRefreshWeather,
                                onNavigateToHabits = onNavigateToHabits
                            )
                        }
                        Spacer(modifier = Modifier.weight(1f))
                    }
                }
            }
        }

        // Bottom breathing room for floating capsule
        item(key = "bottom_spacer") {
            Spacer(modifier = Modifier.height(100.dp))
        }
    }
}

@Composable
private fun DashboardHeader(
    userProfile: UserProfile?,
    isLoading: Boolean,
    onRefresh: () -> Unit,
    onOpenCustomize: () -> Unit,
    onOpenSettings: () -> Unit
) {
    val greeting = rememberGreeting()
    val firstName = userProfile?.firstName ?: "Friend"

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column {
            Text(
                text = "$greeting, $firstName",
                color = ThemeColors.textSecondary,
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium
            )
            Text(
                text = "Your Life, Synchronized",
                color = Color.White,
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold
            )
        }

        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            GlassButton(
                onClick = onRefresh,
                cornerRadius = 12.dp,
                paddingHorizontal = 10.dp,
                paddingVertical = 10.dp
            ) {
                if (isLoading) {
                    CircularProgressIndicator(
                        color = ThemeColors.accentCyan,
                        strokeWidth = 2.dp,
                        modifier = Modifier.size(20.dp)
                    )
                } else {
                    Icon(
                        imageVector = Icons.Rounded.Refresh,
                        contentDescription = "Refresh",
                        tint = Color.White,
                        modifier = Modifier.size(20.dp)
                    )
                }
            }

            GlassButton(
                onClick = onOpenCustomize,
                cornerRadius = 12.dp,
                paddingHorizontal = 10.dp,
                paddingVertical = 10.dp
            ) {
                Icon(
                    imageVector = Icons.Rounded.Tune,
                    contentDescription = "Customize Grid",
                    tint = ThemeColors.accentCyan,
                    modifier = Modifier.size(20.dp)
                )
            }

            GlassButton(
                onClick = onOpenSettings,
                cornerRadius = 12.dp,
                paddingHorizontal = 10.dp,
                paddingVertical = 10.dp
            ) {
                Icon(
                    imageVector = Icons.Rounded.Settings,
                    contentDescription = "Settings",
                    tint = Color.White,
                    modifier = Modifier.size(20.dp)
                )
            }
        }
    }
}

@Composable
private fun DashboardWidgetRenderer(
    config: DashboardWidgetConfig,
    weather: WeatherResponse?,
    forecast: ForecastResponse?,
    hourlyForecasts: List<ForecastItem>,
    locationName: String,
    isWeatherLoading: Boolean,
    settings: AppSettings,
    habitsRepository: com.intellidream.daily.database.HabitsRepository,
    onRefreshWeather: () -> Unit,
    onNavigateToHabits: () -> Unit
) {
    when (config.id) {
        DashboardWidgetType.Weather.id -> {
            WeatherDashboardCard(
                size = config.size,
                weather = weather,
                forecast = forecast,
                hourlyForecasts = hourlyForecasts,
                locationName = locationName,
                isLoading = isWeatherLoading,
                settings = settings,
                onTap = onRefreshWeather
            )
        }
        DashboardWidgetType.Habits.id -> {
            HabitsDashboardCard(
                size = config.size,
                repository = habitsRepository,
                onOpenHub = onNavigateToHabits
            )
        }
        DashboardWidgetType.News.id -> {
            PlaceholderHubCard(
                title = "News & Briefings",
                subtitle = "Morning intelligence ready",
                icon = Icons.Rounded.Feed,
                iconTint = ThemeColors.accentCyan,
                size = config.size,
                settings = settings
            )
        }
        DashboardWidgetType.Health.id -> {
            PlaceholderHubCard(
                title = "Health & Vitals",
                subtitle = "Sleep ${settings.healthSleepTargetHours}h target · In sync",
                icon = Icons.Rounded.Favorite,
                iconTint = Color(0xFFFF5252),
                size = config.size,
                settings = settings
            )
        }
        DashboardWidgetType.Finances.id -> {
            PlaceholderHubCard(
                title = "Finances & Markets",
                subtitle = "Live balances & trends",
                icon = Icons.Rounded.AccountBalanceWallet,
                iconTint = Color(0xFF00E676),
                size = config.size,
                settings = settings
            )
        }
        DashboardWidgetType.TagdosNotes.id -> {
            PlaceholderHubCard(
                title = "Tagdos & Tasks",
                subtitle = "Active tasks · Today",
                icon = Icons.Rounded.CheckCircle,
                iconTint = ThemeColors.accentBlue,
                size = config.size,
                settings = settings
            )
        }
        else -> {
            PlaceholderHubCard(
                title = config.id.replaceFirstChar { it.uppercase() },
                subtitle = "Widget",
                icon = Icons.Rounded.Settings,
                iconTint = ThemeColors.accentCyan,
                size = config.size,
                settings = settings
            )
        }
    }
}

@Composable
private fun PlaceholderHubCard(
    title: String,
    subtitle: String,
    icon: ImageVector,
    iconTint: Color,
    size: DashboardWidgetSize,
    settings: AppSettings
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
        padding = 18.dp,
        intensity = glassIntensity
    ) {
        Column(
            modifier = Modifier.fillMaxSize(),
            verticalArrangement = Arrangement.SpaceBetween
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = icon,
                        contentDescription = null,
                        tint = iconTint,
                        modifier = Modifier.size(18.dp)
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = title,
                        color = Color.White,
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                }
            }

            Column {
                Text(
                    text = subtitle,
                    color = ThemeColors.textSecondary,
                    fontSize = 13.sp
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "Tactile Liquid Glass · 100% Native",
                    color = ThemeColors.textMuted,
                    fontSize = 11.sp
                )
            }
        }
    }
}

@Composable
private fun rememberGreeting(): String {
    val hour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
    return when (hour) {
        in 5..11 -> "Good morning"
        in 12..16 -> "Good afternoon"
        in 17..22 -> "Good evening"
        else -> "Good night"
    }
}
