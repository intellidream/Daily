package com.intellidream.daily.presentation.health

import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.ui.platform.LocalContext
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.GlassIntensity
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.launch
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.Bedtime
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.Watch
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.health.HealthDataRepository
import com.intellidream.daily.model.DeviceSource
import com.intellidream.daily.model.HealthMetricType
import com.intellidream.daily.model.HealthSubTab
import com.intellidream.daily.model.SleepSession
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import kotlin.math.min
import kotlin.math.roundToInt

@Composable
fun HealthMainView(
    repository: HealthDataRepository,
    onNavigateBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val activeSubTab by repository.activeSubTab.collectAsState()
    val selectedDateMillis by repository.selectedDate.collectAsState()
    val selectedDeviceSource by repository.selectedDeviceSource.collectAsState()
    val availableSources by repository.availableSources.collectAsState()
    val isLoading by repository.isLoading.collectAsState()

    // Data states
    val totalSteps by repository.totalStepsToday.collectAsState()
    val totalActiveCalories by repository.totalActiveCalories.collectAsState()
    val averageBpm by repository.averageBpm.collectAsState()
    val minBpm by repository.minBpm.collectAsState()
    val maxBpm by repository.maxBpm.collectAsState()
    val restingBpm by repository.restingBpm.collectAsState()
    val hourlySteps by repository.hourlySteps.collectAsState()
    val intradayHeartRate by repository.intradayHeartRate.collectAsState()
    val heartRateZones by repository.heartRateZones.collectAsState()
    val primarySleep by repository.primarySleepSession.collectAsState()
    val daytimeNaps by repository.daytimeNaps.collectAsState()
    val sleepVerdict by repository.sleepRecoveryVerdict.collectAsState()
    val sleepTips by repository.sleepActionableTips.collectAsState()
    val sleepAIContext by repository.sleepAIContext.collectAsState()
    val currentVitals by repository.currentVitals.collectAsState()
    val historicalTrends by repository.historicalTrends.collectAsState()

    val context = LocalContext.current
    val coroutineScope = rememberCoroutineScope()
    var hasHealthPermissions by remember { mutableStateOf(true) }

    LaunchedEffect(Unit) {
        if (repository.healthConnectManager.isAvailable) {
            hasHealthPermissions = repository.healthConnectManager.hasAnyPermissions()
        }
    }

    val requestPermissionsLauncher = rememberLauncherForActivityResult(
        PermissionController.createRequestPermissionResultContract()
    ) { grantedPermissions ->
        if (grantedPermissions.isNotEmpty()) {
            hasHealthPermissions = true
            repository.loadDataForSelectedDate(forceRefresh = true)
        }
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(ThemeColors.backgroundGradient)
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            // Header Bar
            HeaderBar(
                selectedDateMillis = selectedDateMillis,
                selectedDeviceSource = selectedDeviceSource,
                availableSources = availableSources,
                onNavigateBack = onNavigateBack,
                onPrevDay = { repository.prevDay() },
                onNextDay = { repository.nextDay() },
                onJumpToday = { repository.jumpToToday() },
                onSelectSource = { repository.setDeviceFilter(it) },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp, vertical = 12.dp)
            )

            // Scrollable Content
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(horizontal = 20.dp, vertical = 4.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                // Sub-Tab Switcher
                item(key = "sub_tab_switcher") {
                    SubTabSwitcher(
                        activeTab = activeSubTab,
                        onTabSelected = { repository.setActiveSubTab(it) }
                    )
                }

                // Health Connect Permission Banner
                if (repository.healthConnectManager.isAvailable && !hasHealthPermissions) {
                    item(key = "health_connect_banner") {
                        GlassCard(
                            modifier = Modifier.fillMaxWidth(),
                            cornerRadius = 16.dp,
                            padding = 16.dp,
                            intensity = GlassIntensity.Medium
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                                    modifier = Modifier.weight(1f)
                                ) {
                                    Box(
                                        modifier = Modifier
                                            .size(36.dp)
                                            .clip(CircleShape)
                                            .background(ThemeColors.accentCyan.copy(alpha = 0.16f)),
                                        contentAlignment = Alignment.Center
                                    ) {
                                        Icon(
                                            imageVector = Icons.Rounded.Favorite,
                                            contentDescription = null,
                                            tint = ThemeColors.accentCyan,
                                            modifier = Modifier.size(18.dp)
                                        )
                                    }
                                    Column {
                                        Text(
                                            text = "Sync Health Connect",
                                            fontSize = 14.sp,
                                            fontWeight = FontWeight.Bold,
                                            color = Color.White
                                        )
                                        Text(
                                            text = "Grant access to steps, heart rate & sleep",
                                            fontSize = 11.sp,
                                            color = ThemeColors.textSecondary
                                        )
                                    }
                                }

                                Box(
                                    modifier = Modifier
                                        .clip(RoundedCornerShape(10.dp))
                                        .background(ThemeColors.accentCyan.copy(alpha = 0.20f))
                                        .border(1.dp, ThemeColors.accentCyan.copy(alpha = 0.40f), RoundedCornerShape(10.dp))
                                        .clickable {
                                            try {
                                                requestPermissionsLauncher.launch(repository.healthConnectManager.requiredPermissions)
                                            } catch (_: Exception) {
                                                try {
                                                    val intent = Intent(HealthConnectClient.ACTION_HEALTH_CONNECT_SETTINGS)
                                                    context.startActivity(intent)
                                                } catch (_: Exception) {}
                                            }
                                        }
                                        .padding(horizontal = 12.dp, vertical = 8.dp),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Text(
                                        text = "Grant Access",
                                        fontSize = 12.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = ThemeColors.accentCyan
                                    )
                                }
                            }
                        }
                    }
                }

                // Sub-Tab Content
                item(key = "sub_tab_content") {
                    AnimatedContent(
                        targetState = activeSubTab,
                        transitionSpec = {
                            fadeIn(animationSpec = tween(220)) togetherWith fadeOut(animationSpec = tween(180))
                        },
                        label = "SubTabAnimation"
                    ) { tab ->
                        when (tab) {
                            HealthSubTab.OVERVIEW -> OverviewSection(
                                totalSteps = totalSteps,
                                totalActiveCalories = totalActiveCalories,
                                averageBpm = averageBpm,
                                hourlySteps = hourlySteps,
                                primarySleep = primarySleep,
                                currentVitals = currentVitals,
                                onOpenSleepStudio = { repository.setActiveSubTab(HealthSubTab.SLEEP) }
                            )

                            HealthSubTab.SLEEP -> SleepStudioView(
                                session = primarySleep,
                                verdict = sleepVerdict,
                                aiContext = sleepAIContext,
                                tips = sleepTips,
                                daytimeNaps = daytimeNaps
                            )

                            HealthSubTab.VITALS -> VitalsSection(
                                averageBpm = averageBpm,
                                restingBpm = restingBpm,
                                minBpm = minBpm,
                                maxBpm = maxBpm,
                                intradayHeartRate = intradayHeartRate,
                                heartRateZones = heartRateZones,
                                currentVitals = currentVitals
                            )

                            HealthSubTab.TRENDS -> HealthTrendsView(
                                historicalTrends = historicalTrends
                            )
                        }
                    }
                }

                // Bottom padding for capsule navigation bar
                item(key = "bottom_spacer") {
                    Spacer(modifier = Modifier.height(110.dp))
                }
            }
        }
    }
}

// MARK: - Header Bar

@Composable
private fun HeaderBar(
    selectedDateMillis: Long,
    selectedDeviceSource: DeviceSource?,
    availableSources: List<DeviceSource>,
    onNavigateBack: () -> Unit,
    onPrevDay: () -> Unit,
    onNextDay: () -> Unit,
    onJumpToday: () -> Unit,
    onSelectSource: (DeviceSource?) -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        // Back Button
        Box(
            modifier = Modifier
                .size(36.dp)
                .clip(CircleShape)
                .background(Color.White.copy(alpha = 0.08f))
                .border(1.dp, Color.White.copy(alpha = 0.12f), CircleShape)
                .clickable { onNavigateBack() },
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowLeft,
                contentDescription = "Back",
                tint = Color.White,
                modifier = Modifier.size(18.dp)
            )
        }

        // Centered Date Navigator
        DayNavigatorBar(
            selectedDateMillis = selectedDateMillis,
            onPrevDay = onPrevDay,
            onNextDay = onNextDay,
            onJumpToday = onJumpToday
        )

        // Device Selector Menu
        DeviceSelectorMenu(
            selectedSource = selectedDeviceSource,
            availableSources = availableSources,
            onSelectSource = onSelectSource
        )
    }
}

@Composable
private fun DayNavigatorBar(
    selectedDateMillis: Long,
    onPrevDay: () -> Unit,
    onNextDay: () -> Unit,
    onJumpToday: () -> Unit
) {
    val isToday = isSameDay(selectedDateMillis, System.currentTimeMillis())

    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier
            .clip(CircleShape)
            .background(Color.White.copy(alpha = 0.06f))
            .border(1.dp, Color.White.copy(alpha = 0.1f), CircleShape)
            .padding(horizontal = 10.dp, vertical = 5.dp)
    ) {
        // Prev Day Button
        Box(
            modifier = Modifier
                .size(26.dp)
                .clip(CircleShape)
                .background(Color.White.copy(alpha = 0.08f))
                .clickable { onPrevDay() },
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowLeft,
                contentDescription = "Previous Day",
                tint = Color.White,
                modifier = Modifier.size(14.dp)
            )
        }

        // Date Title
        Text(
            text = formatDayTitle(selectedDateMillis),
            fontSize = 14.sp,
            fontWeight = FontWeight.Bold,
            color = Color.White
        )

        if (!isToday) {
            // Jump to Today
            Box(
                modifier = Modifier
                    .clip(CircleShape)
                    .background(ThemeColors.accentCyan.copy(alpha = 0.18f))
                    .clickable { onJumpToday() }
                    .padding(horizontal = 7.dp, vertical = 3.dp)
            ) {
                Text(
                    text = "Today",
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    color = ThemeColors.accentCyan
                )
            }

            // Next Day Button
            Box(
                modifier = Modifier
                    .size(26.dp)
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.08f))
                .clickable { onNextDay() },
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                    contentDescription = "Next Day",
                    tint = Color.White,
                    modifier = Modifier.size(14.dp)
                )
            }
        } else {
            Box(
                modifier = Modifier.size(26.dp),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                    contentDescription = null,
                    tint = Color.White.copy(alpha = 0.2f),
                    modifier = Modifier.size(14.dp)
                )
            }
        }
    }
}

@Composable
private fun DeviceSelectorMenu(
    selectedSource: DeviceSource?,
    availableSources: List<DeviceSource>,
    onSelectSource: (DeviceSource?) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    val isFiltered = selectedSource != null

    Box {
        Box(
            modifier = Modifier
                .size(36.dp)
                .clip(CircleShape)
                .background(if (isFiltered) ThemeColors.accentCyan.copy(alpha = 0.2f) else Color.White.copy(alpha = 0.08f))
                .border(
                    1.dp,
                    if (isFiltered) ThemeColors.accentCyan.copy(alpha = 0.6f) else Color.White.copy(alpha = 0.12f),
                    CircleShape
                )
                .clickable { expanded = true },
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = Icons.Rounded.Watch,
                contentDescription = "Device Selector",
                tint = if (isFiltered) ThemeColors.accentCyan else Color.White.copy(alpha = 0.85f),
                modifier = Modifier.size(16.dp)
            )
        }

        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
            modifier = Modifier.background(Color(0xFF0F1B30))
        ) {
            DropdownMenuItem(
                text = { Text("All Devices", color = Color.White) },
                trailingIcon = {
                    if (selectedSource == null) {
                        Icon(Icons.Rounded.Check, contentDescription = null, tint = ThemeColors.accentCyan)
                    }
                },
                onClick = {
                    expanded = false
                    onSelectSource(null)
                }
            )

            HorizontalDivider(color = Color.White.copy(alpha = 0.1f))

            availableSources.forEach { source ->
                DropdownMenuItem(
                    text = { Text(source.displayName, color = Color.White) },
                    trailingIcon = {
                        if (selectedSource == source) {
                            Icon(Icons.Rounded.Check, contentDescription = null, tint = ThemeColors.accentCyan)
                        }
                    },
                    onClick = {
                        expanded = false
                        onSelectSource(source)
                    }
                )
            }
        }
    }
}

// MARK: - Sub-Tab Switcher

@Composable
private fun SubTabSwitcher(
    activeTab: HealthSubTab,
    onTabSelected: (HealthSubTab) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(CircleShape)
            .background(Color.White.copy(alpha = 0.05f))
            .border(1.dp, Color.White.copy(alpha = 0.08f), CircleShape)
            .padding(4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        HealthSubTab.values().forEach { tab ->
            val isSelected = activeTab == tab
            Box(
                modifier = Modifier
                    .weight(1f)
                    .clip(CircleShape)
                    .background(if (isSelected) Color.White.copy(alpha = 0.12f) else Color.Transparent)
                    .clickable { onTabSelected(tab) }
                    .padding(vertical = 8.dp),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = tab.displayName,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = if (isSelected) Color.White else Color.White.copy(alpha = 0.6f)
                )
            }
        }
    }
}

// MARK: - Overview Section

@Composable
private fun OverviewSection(
    totalSteps: Int,
    totalActiveCalories: Double,
    averageBpm: Double,
    hourlySteps: List<com.intellidream.daily.model.HourlyStepBucket>,
    primarySleep: SleepSession?,
    currentVitals: Map<HealthMetricType, com.intellidream.daily.model.VitalMetricRecord>,
    onOpenSleepStudio: () -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        // Activity Hero Dual Rings Card
        ActivityHeroCard(
            totalSteps = totalSteps,
            totalActiveCalories = totalActiveCalories,
            averageBpm = averageBpm
        )

        // Hourly Step Cadence
        HourlyStepsHistogramView(
            totalSteps = totalSteps,
            hourlySteps = hourlySteps
        )

        // Sleep Preview Card (Tap opens Sleep Studio)
        if (primarySleep != null) {
            SleepOverviewPreviewCard(
                session = primarySleep,
                onClick = onOpenSleepStudio
            )
        }

        // Primary Vitals Grid
        VitalsGrid(currentVitals = currentVitals)
    }
}

@Composable
private fun ActivityHeroCard(
    totalSteps: Int,
    totalActiveCalories: Double,
    averageBpm: Double
) {
    GlassCard(
        modifier = Modifier.fillMaxWidth(),
        cornerRadius = 22.dp,
        padding = 20.dp
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(20.dp)
        ) {
            // Dual Concentric Activity Rings
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier.size(90.dp)
            ) {
                // Outer Steps Ring
                CircularProgressIndicator(
                    progress = { 1f },
                    modifier = Modifier.size(90.dp),
                    color = Color.White.copy(alpha = 0.08f),
                    strokeWidth = 10.dp
                )
                CircularProgressIndicator(
                    progress = { min(1f, totalSteps.toFloat() / 10_000f) },
                    modifier = Modifier.size(90.dp),
                    color = ThemeColors.accentCyan,
                    strokeWidth = 10.dp,
                    strokeCap = StrokeCap.Round
                )

                // Inner Calories Ring
                CircularProgressIndicator(
                    progress = { 1f },
                    modifier = Modifier.size(66.dp),
                    color = Color.White.copy(alpha = 0.05f),
                    strokeWidth = 8.dp
                )
                CircularProgressIndicator(
                    progress = { min(1f, totalActiveCalories.toFloat() / 550f) },
                    modifier = Modifier.size(66.dp),
                    color = Color(0xFFFF7043),
                    strokeWidth = 8.dp,
                    strokeCap = StrokeCap.Round
                )

                // Center Pulsing Heart
                Icon(
                    imageVector = Icons.Rounded.Favorite,
                    contentDescription = null,
                    tint = ThemeColors.accentPink,
                    modifier = Modifier.size(16.dp)
                )
            }

            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Row(
                    verticalAlignment = Alignment.Bottom,
                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Text(
                        text = "$totalSteps",
                        fontSize = 26.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                    Text(
                        text = "/ 10,000 steps",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = ThemeColors.fgMutedDark,
                        modifier = Modifier.padding(bottom = 3.dp)
                    )
                }

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                        Text(
                            text = "Active Calories",
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Medium,
                            color = ThemeColors.fgMutedDark
                        )
                        Text(
                            text = "${totalActiveCalories.roundToInt()} kcal",
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color(0xFFFF7043)
                        )
                    }

                    Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                        Text(
                            text = "Current BPM",
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Medium,
                            color = ThemeColors.fgMutedDark
                        )
                        Text(
                            text = if (averageBpm > 0) "${averageBpm.roundToInt()} bpm" else "--",
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Bold,
                            color = ThemeColors.accentPink
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun SleepOverviewPreviewCard(
    session: SleepSession,
    onClick: () -> Unit
) {
    GlassCard(
        modifier = Modifier.fillMaxWidth(),
        cornerRadius = 18.dp,
        padding = 16.dp,
        onClick = onClick
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Box(
                    modifier = Modifier
                        .size(42.dp)
                        .clip(CircleShape)
                        .background(ThemeColors.accentPurple.copy(alpha = 0.18f)),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Bedtime,
                        contentDescription = null,
                        tint = ThemeColors.accentPurple,
                        modifier = Modifier.size(18.dp)
                    )
                }

                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        text = "LAST NIGHT'S SLEEP",
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        color = ThemeColors.accentPurple
                    )
                    Text(
                        text = session.totalAsleepFormatted,
                        fontSize = 20.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                    Text(
                        text = "${session.sleepScore} Score • ${session.sleepQualityRating}",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Medium,
                        color = ThemeColors.fgMutedDark
                    )
                }
            }

            Icon(
                imageVector = Icons.Rounded.ChevronRight,
                contentDescription = null,
                tint = ThemeColors.fgMutedDark,
                modifier = Modifier.size(18.dp)
            )
        }
    }
}

@Composable
private fun VitalsGrid(
    currentVitals: Map<HealthMetricType, com.intellidream.daily.model.VitalMetricRecord>
) {
    val displayedTiles = listOf(
        Pair(HealthMetricType.RESTING_HEART_RATE, ThemeColors.accentPink),
        Pair(HealthMetricType.HRV_SDNN, ThemeColors.accentCyan),
        Pair(HealthMetricType.OXYGEN_SATURATION, ThemeColors.accentBlue),
        Pair(HealthMetricType.RESPIRATORY_RATE, ThemeColors.accentCyan),
        Pair(HealthMetricType.BLOOD_PRESSURE_SYSTOLIC, Color(0xFFFF6666)),
        Pair(HealthMetricType.STRESS, Color(0xFFFFB300)),
        Pair(HealthMetricType.HYDRATION, ThemeColors.accentCyan),
        Pair(HealthMetricType.WEIGHT, ThemeColors.accentPurple)
    )

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        for (i in displayedTiles.indices step 2) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                val (metric1, tint1) = displayedTiles[i]
                VitalMetricTile(
                    modifier = Modifier.weight(1f),
                    metricType = metric1,
                    record = currentVitals[metric1],
                    tint = tint1
                )

                if (i + 1 < displayedTiles.size) {
                    val (metric2, tint2) = displayedTiles[i + 1]
                    VitalMetricTile(
                        modifier = Modifier.weight(1f),
                        metricType = metric2,
                        record = currentVitals[metric2],
                        tint = tint2
                    )
                } else {
                    Spacer(modifier = Modifier.weight(1f))
                }
            }
        }
    }
}

// MARK: - Vitals Section

@Composable
private fun VitalsSection(
    averageBpm: Double,
    restingBpm: Double,
    minBpm: Double,
    maxBpm: Double,
    intradayHeartRate: List<com.intellidream.daily.model.IntradayHeartRatePoint>,
    heartRateZones: Map<com.intellidream.daily.model.HeartRateZone, Int>,
    currentVitals: Map<HealthMetricType, com.intellidream.daily.model.VitalMetricRecord>
) {
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        HeartRateCurveView(
            averageBpm = averageBpm,
            restingBpm = restingBpm,
            minBpm = minBpm,
            maxBpm = maxBpm,
            intradayHeartRate = intradayHeartRate,
            heartRateZones = heartRateZones
        )

        Text(
            text = "ALL SENSOR VITALS",
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold,
            color = ThemeColors.accentCyan,
            modifier = Modifier.padding(start = 4.dp, top = 4.dp)
        )

        VitalsGrid(currentVitals = currentVitals)
    }
}

// Helpers
private fun formatDayTitle(dateMillis: Long): String {
    val cal = Calendar.getInstance()
    val todayStart = getMidnight(System.currentTimeMillis())
    val dateStart = getMidnight(dateMillis)

    return when (dateStart) {
        todayStart -> "Today, ${SimpleDateFormat("MMM d", Locale.getDefault()).format(Date(dateMillis))}"
        todayStart - 86400000L -> "Yesterday, ${SimpleDateFormat("MMM d", Locale.getDefault()).format(Date(dateMillis))}"
        else -> SimpleDateFormat("EEEE, MMM d", Locale.getDefault()).format(Date(dateMillis))
    }
}

private fun getMidnight(time: Long): Long {
    val cal = Calendar.getInstance().apply {
        timeInMillis = time
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }
    return cal.timeInMillis
}

private fun isSameDay(time1: Long, time2: Long): Boolean = getMidnight(time1) == getMidnight(time2)
