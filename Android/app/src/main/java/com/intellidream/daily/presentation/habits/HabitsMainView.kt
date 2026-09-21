package com.intellidream.daily.presentation.habits

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.CalendarMonth
import androidx.compose.material.icons.rounded.DeleteOutline
import androidx.compose.material.icons.rounded.Inbox
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.KeyboardArrowLeft
import androidx.compose.material.icons.rounded.KeyboardArrowUp
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.WaterDrop
import androidx.compose.ui.graphics.Brush
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.database.HabitsRepository
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.HabitConsistencyCell
import com.intellidream.daily.model.HabitLogRecord
import com.intellidream.daily.model.HabitTrendDay
import com.intellidream.daily.model.HabitType
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HabitsMainView(
    repository: HabitsRepository,
    onNavigateBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val activeHabit by repository.activeHabit.collectAsState()
    val waterGoal by repository.waterGoal.collectAsState()
    val smokesSettings by repository.smokesSettings.collectAsState()

    val waterTotalToday by repository.waterTotalToday.collectAsState()
    val smokesTotalToday by repository.smokesTotalToday.collectAsState()

    val waterLogs by repository.selectedDateWaterLogs.collectAsState()
    val smokesLogs by repository.selectedDateSmokesLogs.collectAsState()

    val waterBreakdown by repository.waterDrinkBreakdown.collectAsState()
    val smokesBreakdown by repository.smokesTypeBreakdown.collectAsState()

    val waterHistory by repository.waterSevenDayHistory.collectAsState()
    val smokesHistory by repository.smokesSevenDayHistory.collectAsState()

    val waterHeatmap by repository.waterConsistencyHeatmap.collectAsState()
    val smokesHeatmap by repository.smokesConsistencyHeatmap.collectAsState()

    val smokesFinancials by repository.smokesFinancials.collectAsState()

    var showGuidanceSheet by remember { mutableStateOf(false) }
    var showDatePickerDialog by remember { mutableStateOf(false) }
    var isTimelineExpanded by remember { mutableStateOf(true) }

    val currentLogs = if (activeHabit == HabitType.WATER) waterLogs else smokesLogs
    val isToday = repository.isSelectedDateToday()
    val dateTitle = repository.getFormattedDateTitle()

    LaunchedEffect(activeHabit) {
        repository.syncLogs()
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp)
            .verticalScroll(rememberScrollState()),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Spacer(modifier = Modifier.height(12.dp))

        // Top Header Day Navigator & Actions
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            IconButton(
                onClick = onNavigateBack,
                modifier = Modifier
                    .size(36.dp)
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.08f))
                    .border(1.dp, Color.White.copy(alpha = 0.15f), CircleShape)
            ) {
                Icon(
                    imageVector = Icons.AutoMirrored.Rounded.ArrowBack,
                    contentDescription = "Back",
                    tint = Color.White,
                    modifier = Modifier.size(18.dp)
                )
            }

            // Date Navigator Capsule
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.06f))
                    .border(1.dp, Color.White.copy(alpha = 0.12f), CircleShape)
                    .padding(horizontal = 8.dp, vertical = 4.dp)
            ) {
                IconButton(
                    onClick = { repository.goToPreviousDay() },
                    modifier = Modifier.size(26.dp)
                ) {
                    Icon(
                        imageVector = Icons.Rounded.KeyboardArrowLeft,
                        contentDescription = "Previous Day",
                        tint = Color.White,
                        modifier = Modifier.size(16.dp)
                    )
                }

                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(5.dp),
                    modifier = Modifier
                        .clickable { showDatePickerDialog = true }
                        .padding(horizontal = 6.dp, vertical = 2.dp)
                ) {
                    Icon(
                        imageVector = Icons.Rounded.CalendarMonth,
                        contentDescription = null,
                        tint = ThemeColors.accentCyan,
                        modifier = Modifier.size(14.dp)
                    )
                    Text(
                        text = dateTitle,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                }

                if (!isToday) {
                    Box(
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(ThemeColors.accentCyan.copy(alpha = 0.18f))
                            .clickable { repository.goToToday() }
                            .padding(horizontal = 7.dp, vertical = 3.dp)
                    ) {
                        Text(
                            text = "Today",
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                            color = ThemeColors.accentCyan
                        )
                    }

                    IconButton(
                        onClick = { repository.goToNextDay() },
                        modifier = Modifier.size(26.dp)
                    ) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                            contentDescription = "Next Day",
                            tint = Color.White,
                            modifier = Modifier.size(16.dp)
                        )
                    }
                }
            }

            IconButton(
                onClick = { showGuidanceSheet = true },
                modifier = Modifier
                    .size(36.dp)
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.08f))
                    .border(1.dp, Color.White.copy(alpha = 0.15f), CircleShape)
            ) {
                Icon(
                    imageVector = Icons.Rounded.AutoAwesome,
                    contentDescription = "Guidance",
                    tint = ThemeColors.accentCyan,
                    modifier = Modifier.size(18.dp)
                )
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Habit Switcher: Bubbles vs Smokes
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(CircleShape)
                .background(Color.White.copy(alpha = 0.06f))
                .border(1.dp, Color.White.copy(alpha = 0.10f), CircleShape)
                .padding(4.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            val isWater = activeHabit == HabitType.WATER
            Box(
                modifier = Modifier
                    .weight(1f)
                    .clip(CircleShape)
                    .then(
                        if (isWater) {
                            Modifier
                                .background(
                                    Brush.horizontalGradient(
                                        listOf(ThemeColors.accentBlue, ThemeColors.accentCyan)
                                    )
                                )
                                .border(1.dp, Color.White.copy(alpha = 0.35f), CircleShape)
                        } else Modifier
                    )
                    .clickable { repository.switchHabit(HabitType.WATER) }
                    .padding(vertical = 10.dp),
                contentAlignment = Alignment.Center
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Icon(
                        imageVector = Icons.Rounded.WaterDrop,
                        contentDescription = null,
                        tint = if (isWater) Color.White else Color.White.copy(alpha = 0.60f),
                        modifier = Modifier.size(16.dp)
                    )
                    Text(
                        text = "Bubbles",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold,
                        color = if (isWater) Color.White else Color.White.copy(alpha = 0.60f)
                    )
                }
            }

            val isSmokes = activeHabit == HabitType.SMOKES
            Box(
                modifier = Modifier
                    .weight(1f)
                    .clip(CircleShape)
                    .then(
                        if (isSmokes) {
                            Modifier
                                .background(
                                    Brush.horizontalGradient(
                                        listOf(Color(0xFF00FFB2).copy(alpha = 0.85f), ThemeColors.accentBlue)
                                    )
                                )
                                .border(1.dp, Color.White.copy(alpha = 0.35f), CircleShape)
                        } else Modifier
                    )
                    .clickable { repository.switchHabit(HabitType.SMOKES) }
                    .padding(vertical = 10.dp),
                contentAlignment = Alignment.Center
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Icon(
                        imageVector = Icons.Rounded.LocalFireDepartment,
                        contentDescription = null,
                        tint = if (isSmokes) Color.White else Color.White.copy(alpha = 0.60f),
                        modifier = Modifier.size(16.dp)
                    )
                    Text(
                        text = "Smokes",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold,
                        color = if (isSmokes) Color.White else Color.White.copy(alpha = 0.60f)
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Hero Visual Gauge
        if (activeHabit == HabitType.WATER) {
            WaterProgressWaveView(
                currentMl = waterTotalToday,
                goalMl = waterGoal,
                drinkBreakdown = waterBreakdown
            )
        } else {
            SmokesLungsGaugeView(
                countToday = smokesTotalToday,
                baselineCount = smokesSettings.baselineDailyCount,
                lastSmokeDate = smokesFinancials.lastSmokeDate,
                lastSmokeType = smokesFinancials.lastSmokeType,
                isToday = isToday,
                smokeBreakdown = smokesBreakdown
            )
        }

        Spacer(modifier = Modifier.height(20.dp))

        // Quick Logging Grid
        HabitQuickActionGrid(
            habitType = activeHabit,
            onLogWater = { preset, multiplier ->
                repository.logWater(preset, multiplier)
            },
            onLogCustomWater = { amount, _ ->
                repository.logWater(com.intellidream.daily.model.WaterPreset.GLASS, 1, amount)
            },
            onLogSmoke = { preset, multiplier ->
                repository.logSmoke(preset, multiplier)
            },
            onOpenCravingEmergency = {
                showGuidanceSheet = true
            }
        )

        Spacer(modifier = Modifier.height(16.dp))

        // Daily Logs Timeline (Collapsible)
        GlassCard(
            modifier = Modifier.fillMaxWidth(),
            cornerRadius = 16.dp,
            padding = 14.dp
        ) {
            Column(modifier = Modifier.fillMaxWidth()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { isTimelineExpanded = !isTimelineExpanded },
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "TIMELINE (${currentLogs.size})",
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        color = ThemeColors.textSecondary,
                        letterSpacing = 1.sp
                    )

                    Icon(
                        imageVector = if (isTimelineExpanded) Icons.Rounded.KeyboardArrowUp else Icons.Rounded.KeyboardArrowDown,
                        contentDescription = null,
                        tint = ThemeColors.textSecondary,
                        modifier = Modifier.size(18.dp)
                    )
                }

                AnimatedVisibility(
                    visible = isTimelineExpanded,
                    enter = fadeIn() + expandVertically(),
                    exit = fadeOut() + shrinkVertically()
                ) {
                    Column(
                        modifier = Modifier.padding(top = 10.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        if (currentLogs.isEmpty()) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(vertical = 16.dp),
                                horizontalArrangement = Arrangement.Center,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Column(
                                    horizontalAlignment = Alignment.CenterHorizontally,
                                    verticalArrangement = Arrangement.spacedBy(6.dp)
                                ) {
                                    Icon(
                                        imageVector = Icons.Rounded.Inbox,
                                        contentDescription = null,
                                        tint = ThemeColors.fgMutedDark,
                                        modifier = Modifier.size(24.dp)
                                    )
                                    Text(
                                        text = "No entries logged for this date",
                                        fontSize = 13.sp,
                                        color = ThemeColors.fgMutedDark
                                    )
                                }
                            }
                        } else {
                            val timeFormat = SimpleDateFormat("HH:mm", Locale.US)
                            currentLogs.forEach { log ->
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clip(RoundedCornerShape(10.dp))
                                        .background(Color.White.copy(alpha = 0.04f))
                                        .padding(horizontal = 10.dp, vertical = 8.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.SpaceBetween
                                ) {
                                    Row(
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                                    ) {
                                        Text(
                                            text = timeFormat.format(Date(log.loggedAt)),
                                            fontSize = 11.sp,
                                            fontWeight = FontWeight.SemiBold,
                                            color = ThemeColors.textSecondary
                                        )

                                        Box(
                                            modifier = Modifier
                                                .size(8.dp)
                                                .clip(CircleShape)
                                                .background(
                                                    Color(android.graphics.Color.parseColor(log.specificIconColorHex))
                                                )
                                        )

                                        Text(
                                            text = log.displayTitleWithMultiplier,
                                            fontSize = 13.sp,
                                            fontWeight = FontWeight.SemiBold,
                                            color = Color.White
                                        )
                                    }

                                    Row(
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                                    ) {
                                        Text(
                                            text = if (log.habitType == "water") "+${log.value.toInt()} ml" else "+${log.value.toInt()}",
                                            fontSize = 12.sp,
                                            fontWeight = FontWeight.Bold,
                                            color = Color(android.graphics.Color.parseColor(log.specificIconColorHex))
                                        )

                                        Box(
                                            modifier = Modifier
                                                .size(28.dp)
                                                .clip(CircleShape)
                                                .background(Color.White.copy(alpha = 0.06f))
                                                .clickable { repository.deleteLog(log.id) },
                                            contentAlignment = Alignment.Center
                                        ) {
                                            Icon(
                                                imageVector = Icons.Rounded.DeleteOutline,
                                                contentDescription = "Delete",
                                                tint = Color.White.copy(alpha = 0.5f),
                                                modifier = Modifier.size(14.dp)
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Smokes Financial Metrics Card
        if (activeHabit == HabitType.SMOKES) {
            GlassCard(
                modifier = Modifier.fillMaxWidth(),
                cornerRadius = 16.dp,
                padding = 14.dp
            ) {
                Column(modifier = Modifier.fillMaxWidth()) {
                    Text(
                        text = "FINANCIAL & CLINICAL GAINS",
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        color = ThemeColors.textSecondary,
                        letterSpacing = 1.sp
                    )

                    Spacer(modifier = Modifier.height(10.dp))

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Column {
                            Text(
                                text = "MONEY SAVED",
                                fontSize = 9.sp,
                                fontWeight = FontWeight.Bold,
                                color = ThemeColors.textSecondary
                            )
                            Text(
                                text = smokesFinancials.moneySavedFormatted,
                                fontSize = 18.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color(0xFF00FFB2)
                            )
                        }

                        Column {
                            Text(
                                text = "CIGS AVOIDED",
                                fontSize = 9.sp,
                                fontWeight = FontWeight.Bold,
                                color = ThemeColors.textSecondary
                            )
                            Text(
                                text = "${smokesFinancials.cigsAvoided}",
                                fontSize = 18.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color.White
                            )
                        }

                        Column {
                            Text(
                                text = "LIFE REGAINED",
                                fontSize = 9.sp,
                                fontWeight = FontWeight.Bold,
                                color = ThemeColors.textSecondary
                            )
                            Text(
                                text = smokesFinancials.lifeRegainedFormatted,
                                fontSize = 18.sp,
                                fontWeight = FontWeight.Bold,
                                color = ThemeColors.accentCyan
                            )
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))
        }

        // 7-Day Performance Bar Chart
        val trendDays = if (activeHabit == HabitType.WATER) waterHistory else smokesHistory
        val goalValue = if (activeHabit == HabitType.WATER) waterGoal else smokesSettings.baselineDailyCount.toDouble()

        GlassCard(
            modifier = Modifier.fillMaxWidth(),
            cornerRadius = 16.dp,
            padding = 14.dp
        ) {
            Column(modifier = Modifier.fillMaxWidth()) {
                Text(
                    text = "7-DAY PERFORMANCE",
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    color = ThemeColors.textSecondary,
                    letterSpacing = 1.sp
                )

                Spacer(modifier = Modifier.height(14.dp))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceEvenly,
                    verticalAlignment = Alignment.Bottom
                ) {
                    trendDays.forEach { day ->
                        val ratio = (day.value / goalValue.coerceAtLeast(1.0)).toFloat().coerceIn(0.05f, 1f)
                        val barColor = if (activeHabit == HabitType.WATER) {
                            if (day.isGoalMet) Color(0xFF00FFB2) else ThemeColors.accentCyan
                        } else {
                            if (day.value > goalValue) Color(0xFFFF3B30) else Color(0xFF00FFB2)
                        }

                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.Bottom,
                            modifier = Modifier.height(100.dp)
                        ) {
                            Text(
                                text = if (activeHabit == HabitType.WATER) "${(day.value / 1000).toInt()}k" else "${day.value.toInt()}",
                                fontSize = 9.sp,
                                fontWeight = FontWeight.Bold,
                                color = ThemeColors.textSecondary
                            )

                            Spacer(modifier = Modifier.height(4.dp))

                            Box(
                                modifier = Modifier
                                    .width(22.dp)
                                    .height((ratio * 65).dp.coerceAtLeast(4.dp))
                                    .clip(RoundedCornerShape(topStart = 4.dp, topEnd = 4.dp))
                                    .background(barColor)
                            )

                            Spacer(modifier = Modifier.height(6.dp))

                            Text(
                                text = day.dayLabel,
                                fontSize = 11.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = ThemeColors.textSecondary
                            )
                        }
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // 112-Day Consistency Heatmap (16 Weeks)
        val heatmapCells = if (activeHabit == HabitType.WATER) waterHeatmap else smokesHeatmap
        GlassCard(
            modifier = Modifier.fillMaxWidth(),
            cornerRadius = 16.dp,
            padding = 14.dp
        ) {
            Column(modifier = Modifier.fillMaxWidth()) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "112-DAY CONSISTENCY HEATMAP",
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        color = ThemeColors.textSecondary,
                        letterSpacing = 1.sp
                    )
                    Text(
                        text = "16 WEEKS",
                        fontSize = 9.sp,
                        fontWeight = FontWeight.Bold,
                        color = ThemeColors.textSecondary
                    )
                }

                Spacer(modifier = Modifier.height(12.dp))

                // Heatmap Grid: 16 columns of 7 days
                val weeks = heatmapCells.chunked(7)
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    weeks.forEach { week ->
                        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            week.forEach { cell ->
                                val cellColor = if (activeHabit == HabitType.WATER) {
                                    when (cell.intensityLevel) {
                                        4 -> Color(0xFF00FFB2)
                                        3 -> ThemeColors.accentCyan
                                        2 -> ThemeColors.accentCyan.copy(alpha = 0.6f)
                                        1 -> ThemeColors.accentCyan.copy(alpha = 0.3f)
                                        else -> Color.White.copy(alpha = 0.05f)
                                    }
                                } else {
                                    when (cell.intensityLevel) {
                                        4 -> Color(0xFF00FFB2)
                                        3 -> ThemeColors.accentCyan
                                        2 -> Color(0xFFFFB800)
                                        1 -> Color(0xFFFF9500)
                                        else -> Color(0xFFFF3B30)
                                    }
                                }

                                Box(
                                    modifier = Modifier
                                        .size(14.dp)
                                        .clip(RoundedCornerShape(3.dp))
                                        .background(cellColor)
                                )
                            }
                        }
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(100.dp)) // Space for bottom navigation capsule
    }

    // Guidance Sheet Modal
    if (showGuidanceSheet) {
        HabitGuidanceSheet(
            initialHabit = activeHabit,
            onDismiss = { showGuidanceSheet = false }
        )
    }

    // Material 3 Date Picker Dialog
    if (showDatePickerDialog) {
        val datePickerState = rememberDatePickerState()
        DatePickerDialog(
            onDismissRequest = { showDatePickerDialog = false },
            confirmButton = {
                TextButton(
                    onClick = {
                        datePickerState.selectedDateMillis?.let { millis ->
                            repository.selectDate(millis)
                        }
                        showDatePickerDialog = false
                    }
                ) {
                    Text("Select", color = ThemeColors.accentCyan, fontWeight = FontWeight.Bold)
                }
            },
            dismissButton = {
                TextButton(onClick = { showDatePickerDialog = false }) {
                    Text("Cancel", color = ThemeColors.textSecondary)
                }
            }
        ) {
            DatePicker(state = datePickerState)
        }
    }
}
