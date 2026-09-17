package com.intellidream.daily.presentation.dashboard

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AccountBalanceWallet
import androidx.compose.material.icons.rounded.ArrowDownward
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.Feed
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
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
import com.intellidream.daily.presentation.briefing.SmartBriefingBottomSheet

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
    healthRepository: com.intellidream.daily.health.HealthDataRepository,
    smartLedgerRepository: com.intellidream.daily.database.SmartLedgerRepository,
    financeDataRepository: com.intellidream.daily.database.FinanceDataRepository,
    onRefreshWeather: () -> Unit,
    onOpenSettings: () -> Unit,
    onOpenCustomize: () -> Unit,
    onUpdateSettings: ((AppSettings) -> AppSettings) -> Unit = {},
    onNavigateToHabits: () -> Unit = {},
    onNavigateToHealth: () -> Unit = {},
    onNavigateToFinances: () -> Unit = {},
    modifier: Modifier = Modifier
) {
    val visibleWidgets = settings.dashboardWidgets.filter { it.isVisible }
    val rows = DashboardRowBuilder.buildRows(visibleWidgets)

    var showBriefingSheet by remember { mutableStateOf(false) }

    val waterTotal by habitsRepository.waterTotalToday.collectAsState()
    val waterGoal by habitsRepository.waterGoal.collectAsState()
    val smokesTotal by habitsRepository.smokesTotalToday.collectAsState()
    val smokesSettings by habitsRepository.smokesSettings.collectAsState()

    fun updateWidgetSize(widgetId: String, newSize: DashboardWidgetSize) {
        onUpdateSettings { s ->
            s.copy(
                dashboardWidgets = s.dashboardWidgets.map {
                    if (it.id == widgetId) it.copy(size = newSize) else it
                }
            )
        }
    }

    fun moveWidget(widgetId: String, delta: Int) {
        onUpdateSettings { s ->
            val list = s.dashboardWidgets.toMutableList()
            val index = list.indexOfFirst { it.id == widgetId }
            val target = index + delta
            if (index >= 0 && target in list.indices) {
                val item = list.removeAt(index)
                list.add(target, item)
            }
            s.copy(dashboardWidgets = list)
        }
    }

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        verticalArrangement = Arrangement.spacedBy(14.dp),
        contentPadding = PaddingValues(top = 8.dp, bottom = 110.dp)
    ) {
        // 1. Signature Liquid Glass Header Greeting with Live Sync Avatar, Date Badge & Actions
        item(key = "header_greeting") {
            HeaderGreetingView(
                userProfile = userProfile,
                onAvatarTapped = onOpenSettings,
                onCustomizeTapped = onOpenCustomize,
                onBriefingTapped = { showBriefingSheet = true }
            )
        }

        // 2. Coalesced Rows with Long-Press Context Menu Support
        items(
            items = rows,
            key = { it.id }
        ) { row ->
            val renderWidget: @Composable (DashboardWidgetConfig, () -> Unit) -> Unit = { config, onLongClick ->
                DashboardWidgetRenderer(
                    config = config,
                    weather = weather,
                    forecast = forecast,
                    hourlyForecasts = hourlyForecasts,
                    locationName = locationName,
                    isWeatherLoading = isWeatherLoading,
                    settings = settings,
                    habitsRepository = habitsRepository,
                    healthRepository = healthRepository,
                    smartLedgerRepository = smartLedgerRepository,
                    financeDataRepository = financeDataRepository,
                    onRefreshWeather = onRefreshWeather,
                    onNavigateToHabits = onNavigateToHabits,
                    onNavigateToHealth = onNavigateToHealth,
                    onNavigateToFinances = onNavigateToFinances,
                    onLongClick = onLongClick
                )
            }

            when (row) {
                is DashboardRow.Full -> {
                    WidgetWithContextMenu(
                        config = row.config,
                        allWidgets = visibleWidgets,
                        onUpdateSize = { newSize -> updateWidgetSize(row.config.id, newSize) },
                        onMoveUp = { moveWidget(row.config.id, -1) },
                        onMoveDown = { moveWidget(row.config.id, 1) },
                        onOpenCustomize = onOpenCustomize
                    ) { onLongClick ->
                        renderWidget(row.config, onLongClick)
                    }
                }

                is DashboardRow.Pair -> {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(14.dp)
                    ) {
                        Box(modifier = Modifier.weight(1f)) {
                            WidgetWithContextMenu(
                                config = row.left,
                                allWidgets = visibleWidgets,
                                onUpdateSize = { newSize -> updateWidgetSize(row.left.id, newSize) },
                                onMoveUp = { moveWidget(row.left.id, -1) },
                                onMoveDown = { moveWidget(row.left.id, 1) },
                                onOpenCustomize = onOpenCustomize
                            ) { onLongClick ->
                                renderWidget(row.left, onLongClick)
                            }
                        }
                        Box(modifier = Modifier.weight(1f)) {
                            WidgetWithContextMenu(
                                config = row.right,
                                allWidgets = visibleWidgets,
                                onUpdateSize = { newSize -> updateWidgetSize(row.right.id, newSize) },
                                onMoveUp = { moveWidget(row.right.id, -1) },
                                onMoveDown = { moveWidget(row.right.id, 1) },
                                onOpenCustomize = onOpenCustomize
                            ) { onLongClick ->
                                renderWidget(row.right, onLongClick)
                            }
                        }
                    }
                }

                is DashboardRow.TallWithSmalls -> {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(14.dp)
                    ) {
                        Box(modifier = Modifier.weight(1f)) {
                            WidgetWithContextMenu(
                                config = row.tall,
                                allWidgets = visibleWidgets,
                                onUpdateSize = { newSize -> updateWidgetSize(row.tall.id, newSize) },
                                onMoveUp = { moveWidget(row.tall.id, -1) },
                                onMoveDown = { moveWidget(row.tall.id, 1) },
                                onOpenCustomize = onOpenCustomize
                            ) { onLongClick ->
                                renderWidget(row.tall, onLongClick)
                            }
                        }
                        Column(
                            modifier = Modifier.weight(1f),
                            verticalArrangement = Arrangement.spacedBy(14.dp)
                        ) {
                            row.smalls.forEach { smallConfig ->
                                WidgetWithContextMenu(
                                    config = smallConfig,
                                    allWidgets = visibleWidgets,
                                    onUpdateSize = { newSize -> updateWidgetSize(smallConfig.id, newSize) },
                                    onMoveUp = { moveWidget(smallConfig.id, -1) },
                                    onMoveDown = { moveWidget(smallConfig.id, 1) },
                                    onOpenCustomize = onOpenCustomize
                                ) { onLongClick ->
                                    renderWidget(smallConfig, onLongClick)
                                }
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
                            WidgetWithContextMenu(
                                config = row.config,
                                allWidgets = visibleWidgets,
                                onUpdateSize = { newSize -> updateWidgetSize(row.config.id, newSize) },
                                onMoveUp = { moveWidget(row.config.id, -1) },
                                onMoveDown = { moveWidget(row.config.id, 1) },
                                onOpenCustomize = onOpenCustomize
                            ) { onLongClick ->
                                renderWidget(row.config, onLongClick)
                            }
                        }
                        Spacer(modifier = Modifier.weight(1f))
                    }
                }
            }
        }
    }

    // Smart Briefing Modal Sheet
    if (showBriefingSheet) {
        SmartBriefingBottomSheet(
            userProfile = userProfile,
            weather = weather,
            waterTotalMl = waterTotal,
            waterGoalMl = waterGoal,
            smokesCount = smokesTotal,
            smokesBaseline = smokesSettings.baselineDailyCount,
            onDismiss = { showBriefingSheet = false }
        )
    }
}

@Composable
private fun WidgetWithContextMenu(
    config: DashboardWidgetConfig,
    allWidgets: List<DashboardWidgetConfig>,
    onUpdateSize: (DashboardWidgetSize) -> Unit,
    onMoveUp: () -> Unit,
    onMoveDown: () -> Unit,
    onOpenCustomize: () -> Unit,
    content: @Composable (onLongClick: () -> Unit) -> Unit
) {
    var isExpanded by remember { mutableStateOf(false) }
    val haptic = LocalHapticFeedback.current
    val index = allWidgets.indexOfFirst { it.id == config.id }

    Box {
        content {
            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
            isExpanded = true
        }

        DropdownMenu(
            expanded = isExpanded,
            onDismissRequest = { isExpanded = false },
            modifier = Modifier
                .background(Color(0xFF0D182E))
                .border(1.dp, Color.White.copy(alpha = 0.20f), RoundedCornerShape(14.dp))
        ) {
            Text(
                text = "WIDGET SIZE",
                fontSize = 10.sp,
                fontWeight = FontWeight.Bold,
                color = ThemeColors.accentCyan,
                modifier = Modifier.padding(horizontal = 14.dp, vertical = 6.dp)
            )

            DashboardWidgetSize.entries.forEach { size ->
                DropdownMenuItem(
                    text = {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                text = size.displayName,
                                color = Color.White,
                                fontSize = 14.sp
                            )
                            if (config.size == size) {
                                Icon(
                                    imageVector = Icons.Rounded.Check,
                                    contentDescription = null,
                                    tint = ThemeColors.accentCyan,
                                    modifier = Modifier.size(16.dp)
                                )
                            }
                        }
                    },
                    onClick = {
                        isExpanded = false
                        onUpdateSize(size)
                    }
                )
            }

            HorizontalDivider(
                color = Color.White.copy(alpha = 0.12f),
                modifier = Modifier.padding(vertical = 4.dp)
            )

            Text(
                text = "ORDER",
                fontSize = 10.sp,
                fontWeight = FontWeight.Bold,
                color = ThemeColors.textSecondary,
                modifier = Modifier.padding(horizontal = 14.dp, vertical = 6.dp)
            )

            if (index > 0) {
                DropdownMenuItem(
                    leadingIcon = {
                        Icon(
                            imageVector = Icons.Rounded.ArrowUpward,
                            contentDescription = null,
                            tint = Color.White,
                            modifier = Modifier.size(16.dp)
                        )
                    },
                    text = { Text("Move Up", color = Color.White, fontSize = 14.sp) },
                    onClick = {
                        isExpanded = false
                        onMoveUp()
                    }
                )
            }

            if (index < allWidgets.size - 1) {
                DropdownMenuItem(
                    leadingIcon = {
                        Icon(
                            imageVector = Icons.Rounded.ArrowDownward,
                            contentDescription = null,
                            tint = Color.White,
                            modifier = Modifier.size(16.dp)
                        )
                    },
                    text = { Text("Move Down", color = Color.White, fontSize = 14.sp) },
                    onClick = {
                        isExpanded = false
                        onMoveDown()
                    }
                )
            }

            HorizontalDivider(
                color = Color.White.copy(alpha = 0.12f),
                modifier = Modifier.padding(vertical = 4.dp)
            )

            DropdownMenuItem(
                leadingIcon = {
                    Icon(
                        imageVector = Icons.Rounded.Tune,
                        contentDescription = null,
                        tint = ThemeColors.accentCyan,
                        modifier = Modifier.size(16.dp)
                    )
                },
                text = { Text("Customize Dashboard...", color = Color.White, fontSize = 14.sp) },
                onClick = {
                    isExpanded = false
                    onOpenCustomize()
                }
            )
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
    healthRepository: com.intellidream.daily.health.HealthDataRepository,
    smartLedgerRepository: com.intellidream.daily.database.SmartLedgerRepository,
    financeDataRepository: com.intellidream.daily.database.FinanceDataRepository,
    onRefreshWeather: () -> Unit,
    onNavigateToHabits: () -> Unit,
    onNavigateToHealth: () -> Unit,
    onNavigateToFinances: () -> Unit,
    onLongClick: () -> Unit
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
                onTap = onRefreshWeather,
                onLongClick = onLongClick
            )
        }
        DashboardWidgetType.Habits.id -> {
            HabitsDashboardCard(
                size = config.size,
                repository = habitsRepository,
                onOpenHub = onNavigateToHabits,
                onLongClick = onLongClick
            )
        }
        DashboardWidgetType.News.id -> {
            PlaceholderHubCard(
                title = "News & Briefings",
                subtitle = "Morning intelligence ready",
                icon = Icons.Rounded.Feed,
                iconTint = ThemeColors.accentCyan,
                size = config.size,
                settings = settings,
                onLongClick = onLongClick
            )
        }
        DashboardWidgetType.Health.id -> {
            HealthDashboardCard(
                size = config.size,
                repository = healthRepository,
                onOpenHub = onNavigateToHealth,
                onLongClick = onLongClick
            )
        }
        DashboardWidgetType.Finances.id -> {
            FinancesDashboardCard(
                size = config.size,
                smartLedgerRepository = smartLedgerRepository,
                financeDataRepository = financeDataRepository,
                onOpenHub = onNavigateToFinances,
                onLongClick = onLongClick
            )
        }
        DashboardWidgetType.TagdosNotes.id -> {
            PlaceholderHubCard(
                title = "Tagdos & Tasks",
                subtitle = "Active tasks · Today",
                icon = Icons.Rounded.CheckCircle,
                iconTint = ThemeColors.accentBlue,
                size = config.size,
                settings = settings,
                onLongClick = onLongClick
            )
        }
        else -> {
            PlaceholderHubCard(
                title = config.id.replaceFirstChar { it.uppercase() },
                subtitle = "Widget",
                icon = Icons.Rounded.Settings,
                iconTint = ThemeColors.accentCyan,
                size = config.size,
                settings = settings,
                onLongClick = onLongClick
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
    settings: AppSettings,
    onLongClick: () -> Unit
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
        intensity = glassIntensity,
        onLongClick = onLongClick
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
