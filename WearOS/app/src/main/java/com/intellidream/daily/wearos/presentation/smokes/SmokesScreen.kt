package com.intellidream.daily.wearos.presentation.smokes

import android.view.HapticFeedbackConstants
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Tune
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.ButtonDefaults
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.dialog.Alert
import androidx.wear.compose.material.dialog.Dialog
import com.google.android.horologist.annotations.ExperimentalHorologistApi
import com.google.android.horologist.compose.layout.ScalingLazyColumn
import com.google.android.horologist.compose.layout.ScalingLazyColumnState
import com.google.android.horologist.compose.layout.ScreenScaffold
import com.google.android.horologist.compose.layout.rememberResponsiveColumnState
import com.intellidream.daily.wearos.data.OfflineSyncManager
import com.intellidream.daily.wearos.data.WatchSessionManager
import com.intellidream.daily.wearos.domain.model.HabitLog
import com.intellidream.daily.wearos.domain.util.HabitDateParser
import com.intellidream.daily.wearos.presentation.components.CravingPacingCard
import com.intellidream.daily.wearos.presentation.components.CustomSmokeDialog
import com.intellidream.daily.wearos.presentation.components.GoalEditDialog
import com.intellidream.daily.wearos.presentation.components.QuickAddChip
import com.intellidream.daily.wearos.presentation.components.TemporalNavHeader
import com.intellidream.daily.wearos.presentation.smokes.Smokes7DaysInlineCard
import com.intellidream.daily.wearos.presentation.theme.DailyWearColors
import com.intellidream.daily.wearos.util.SoundAndHapticFeedback
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.text.SimpleDateFormat
import java.time.Instant
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

@OptIn(ExperimentalHorologistApi::class)
@Composable
fun SmokesScreen(
    sessionManager: WatchSessionManager,
    isPageActive: Boolean = true,
    onOpenLogs: ((habitType: String, dateTitle: String, logs: List<HabitLog>, onDelete: (HabitLog) -> Unit) -> Unit)? = null
) {
    val context = LocalContext.current
    val view = LocalView.current
    var dayOffset by remember { mutableIntStateOf(0) }
    val dailyGoal by sessionManager.smokesGoal.collectAsState()

    val scope = rememberCoroutineScope()
    // RotaryMode.Scroll provides silky-smooth 60/120Hz scrolling with crown haptic ticks
    val columnState = rememberResponsiveColumnState(
        rotaryMode = ScalingLazyColumnState.RotaryMode.Scroll
    )
    val refreshTrigger by sessionManager.dataRefreshTrigger.collectAsState()

    val localFormat = remember { SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()) }
    val dayTitleFormat = remember { SimpleDateFormat("EEE, d MMM", Locale.getDefault()) }
    val isoFormat = remember {
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }
    }

    val targetDateStr = remember(dayOffset) {
        val cal = Calendar.getInstance()
        if (dayOffset != 0) cal.add(Calendar.DAY_OF_YEAR, dayOffset)
        localFormat.format(cal.time)
    }

    val initialLogs = remember(targetDateStr) {
        sessionManager.getSmokesLogs(targetDateStr)
            ?: (if (dayOffset == 0) sessionManager.cachedSmokesLogs else null)
            ?: emptyList()
    }

    var dayLogs by remember { mutableStateOf<List<HabitLog>>(initialLogs) }
    var todayCig by remember { mutableIntStateOf(dayLogs.filter { it.metadata?.contains("Heated") != true }.sumOf { maxOf(1, it.value.toInt()) }) }
    var todayHeat by remember { mutableIntStateOf(dayLogs.filter { it.metadata?.contains("Heated") == true }.sumOf { maxOf(1, it.value.toInt()) }) }
    var todayTotal by remember { mutableIntStateOf(todayCig + todayHeat) }
    var logToDelete by remember { mutableStateOf<HabitLog?>(null) }
    var showDeleteDialog by remember { mutableStateOf(false) }
    var showCustomDialog by remember { mutableStateOf(false) }
    var showGoalDialog by remember { mutableStateOf(false) }

    val formattedDateTitle = remember(dayOffset) {
        when (dayOffset) {
            0 -> "Today"
            -1 -> "Yesterday"
            else -> {
                val cal = Calendar.getInstance()
                cal.add(Calendar.DAY_OF_YEAR, dayOffset)
                dayTitleFormat.format(cal.time)
            }
        }
    }

    val getSmokesColor: (Int, Int) -> Color = { total, goal ->
        when {
            total >= goal -> DailyWearColors.SmokeRed
            total >= goal * 0.75 -> DailyWearColors.CoffeeOrange
            else -> DailyWearColors.SmokeGreen
        }
    }

    fun loadCachedDate(targetDate: String) {
        val cached = sessionManager.getSmokesLogs(targetDate)
        if (cached != null) {
            dayLogs = cached
            var tCig = 0
            var tHeat = 0
            for (log in cached) {
                val count = maxOf(1, log.value.toInt())
                val isHeat = log.isHeatedSmoke
                if (isHeat) tHeat += count else tCig += count
            }
            todayCig = tCig
            todayHeat = tHeat
            todayTotal = tCig + tHeat
        } else {
            dayLogs = emptyList()
            todayCig = 0
            todayHeat = 0
            todayTotal = 0
            if (isPageActive) {
                scope.launch {
                    sessionManager.fetchDayLogs("smokes", targetDate)
                }
            }
        }
    }

    LaunchedEffect(dayOffset, refreshTrigger, isPageActive) {
        loadCachedDate(targetDateStr)
    }

    val deleteLog: (HabitLog) -> Unit = { log ->
        SoundAndHapticFeedback.playClick(context, view)
        sessionManager.deleteHabitLog(log, dayOffset)
        loadCachedDate(targetDateStr)
    }

    val logSmoke: (String) -> Unit = { type ->
        SoundAndHapticFeedback.playLogAdded(context, view)
        sessionManager.logSmoke(type, dayOffset)
        loadCachedDate(targetDateStr)
    }

    val progress = (todayTotal.toFloat() / maxOf(dailyGoal, 1).toFloat()).coerceIn(0f, 1f)
    val progAnim by animateFloatAsState(targetValue = progress, animationSpec = tween(600), label = "smokesProg")
    val ringColor = getSmokesColor(todayTotal, dailyGoal)

    ScreenScaffold(
        scrollState = columnState
    ) {
        ScalingLazyColumn(
            columnState = columnState,
            modifier = Modifier.fillMaxSize()
        ) {
            // Screen Title
            item {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.padding(top = 4.dp, bottom = 2.dp)
                ) {
                    Icon(
                        imageVector = Icons.Filled.LocalFireDepartment,
                        contentDescription = null,
                        tint = ringColor,
                        modifier = Modifier.size(16.dp)
                    )
                    Spacer(Modifier.width(4.dp))
                    Text(
                        text = "Smokes",
                        fontWeight = FontWeight.Bold,
                        fontSize = 16.sp,
                        color = Color.White
                    )
                }
            }

            // Temporal Navigation Header Pill
            item {
                TemporalNavHeader(
                    title = formattedDateTitle,
                    canGoForward = dayOffset < 0,
                    accentColor = DailyWearColors.SmokeRed,
                    onPrevious = {
                        SoundAndHapticFeedback.playClick(context, view)
                        dayOffset -= 1
                    },
                    onNext = {
                        if (dayOffset < 0) {
                            SoundAndHapticFeedback.playClick(context, view)
                            dayOffset += 1
                        }
                    },
                    modifier = Modifier.padding(vertical = 4.dp)
                )
            }

            // Hero 122dp Progress Ring - Mathematically inset to eliminate clipping
            item {
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier
                        .padding(vertical = 4.dp)
                        .size(122.dp)
                        .clickable {
                            SoundAndHapticFeedback.playClick(context, view)
                            if (dayLogs.isNotEmpty()) {
                                scope.launch { columnState.state.animateScrollToItem(6) }
                            }
                            onOpenLogs?.invoke("smokes", formattedDateTitle, dayLogs, deleteLog)
                        }
                ) {

                    androidx.compose.foundation.Canvas(modifier = Modifier.fillMaxSize()) {
                        val strokeWidth = 10.dp.toPx()
                        val halfStroke = strokeWidth / 2f
                        val arcSize = Size(size.width - strokeWidth, size.height - strokeWidth)
                        val arcTopLeft = Offset(halfStroke, halfStroke)

                        // Background Track
                        drawArc(
                            color = Color.White.copy(alpha = 0.08f),
                            startAngle = -90f,
                            sweepAngle = 360f,
                            useCenter = false,
                            topLeft = arcTopLeft,
                            size = arcSize,
                            style = Stroke(width = strokeWidth, cap = StrokeCap.Round)
                        )

                        val sweep = (progAnim * 360f).coerceIn(0f, 360f)
                        if (sweep > 0) {
                            drawArc(
                                color = ringColor,
                                startAngle = -90f,
                                sweepAngle = sweep,
                                useCenter = false,
                                topLeft = arcTopLeft,
                                size = arcSize,
                                style = Stroke(width = strokeWidth, cap = StrokeCap.Round)
                            )
                        }
                    }

                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center
                    ) {
                        Text(
                            text = "$todayTotal",
                            fontWeight = FontWeight.Bold,
                            fontSize = 30.sp,
                            color = if (todayTotal > dailyGoal) DailyWearColors.SmokeRed else Color.White
                        )
                        Text(
                            text = "/ $dailyGoal max",
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Medium,
                            color = Color.White.copy(alpha = 0.55f),
                            modifier = Modifier
                                .clip(RoundedCornerShape(8.dp))
                                .clickable {
                                    SoundAndHapticFeedback.playClick(context, view)
                                    showGoalDialog = true
                                }
                                .padding(horizontal = 4.dp, vertical = 2.dp)
                        )
                    }
                }
            }

            // Live Craving Pacing Timer & Sigh Shortcut (Today only)
            if (dayOffset == 0) {
                item {
                    CravingPacingCard(sessionManager = sessionManager)
                    Spacer(Modifier.height(4.dp))
                }
            }

            // Quick Add Action Chips with matching vector icons
            item {
                QuickAddChip(
                    icon = Icons.Filled.LocalFireDepartment, // Exactly matches top header icon!
                    title = "+1 Cigarette",
                    accentColor = DailyWearColors.SmokeRed,
                    onClick = { logSmoke("Cigarette") }
                )
            }
            item {
                Spacer(Modifier.height(4.dp))
                QuickAddChip(
                    icon = Icons.Filled.Bolt, // Matching vector bolt icon
                    title = "+1 Heated",
                    accentColor = DailyWearColors.HeatIndigo,
                    onClick = { logSmoke("Heated Tobacco") }
                )
            }
            item {
                Spacer(Modifier.height(4.dp))
                QuickAddChip(
                    icon = Icons.Filled.Tune,
                    title = "+ Custom / Retroactive",
                    accentColor = Color(0xFFFFB74D),
                    onClick = {
                        SoundAndHapticFeedback.playClick(context, view)
                        showCustomDialog = true
                    }
                )
            }

            // Breakdown Card
            item {
                Spacer(Modifier.height(6.dp))
                Box(
                    modifier = Modifier
                        .fillMaxWidth(0.92f)
                        .clip(RoundedCornerShape(16.dp))
                        .background(Color(0xFF141820))
                        .border(1.dp, Color.White.copy(alpha = 0.05f), RoundedCornerShape(16.dp))
                        .clickable {
                            SoundAndHapticFeedback.playClick(context, view)
                            if (dayLogs.isNotEmpty()) {
                                scope.launch { columnState.state.animateScrollToItem(6) }
                            }
                            onOpenLogs?.invoke("smokes", formattedDateTitle, dayLogs, deleteLog)
                        }
                        .padding(horizontal = 14.dp, vertical = 10.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                imageVector = Icons.Filled.LocalFireDepartment,
                                contentDescription = null,
                                tint = DailyWearColors.SmokeRed,
                                modifier = Modifier.size(13.dp)
                            )
                            Spacer(Modifier.width(4.dp))
                            Text(
                                text = "$todayCig Cig",
                                fontSize = 12.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = Color.White
                            )
                            Text(
                                text = "  •  ",
                                fontSize = 12.sp,
                                color = Color.White.copy(alpha = 0.3f)
                            )
                            Icon(
                                imageVector = Icons.Filled.Bolt,
                                contentDescription = null,
                                tint = DailyWearColors.HeatIndigo,
                                modifier = Modifier.size(13.dp)
                            )
                            Spacer(Modifier.width(4.dp))
                            Text(
                                text = "$todayHeat Heat",
                                fontSize = 12.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = Color.White
                            )
                        }

                        Text(
                            text = "›",
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Bold,
                            color = DailyWearColors.SmokeRed
                        )
                    }
                }
            }

            // 7-Day Trend Section
            item {
                Spacer(Modifier.height(8.dp))
                Smokes7DaysInlineCard(
                    sessionManager = sessionManager,
                    isPageActive = isPageActive
                )
            }

            // In-Flow Logs Section
            if (dayLogs.isNotEmpty()) {
                item {
                    Spacer(Modifier.height(10.dp))
                    Text(
                        text = if (dayOffset == 0) "TODAY'S LOGS" else "LOGS",
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White.copy(alpha = 0.5f),
                        modifier = Modifier
                            .fillMaxWidth(0.88f)
                            .padding(bottom = 4.dp)
                    )
                }

                items(count = dayLogs.size, key = { dayLogs[it].id }) { index ->
                    val log = dayLogs[index]
                    val count = maxOf(1, log.value.toInt())
                    val isHeat = log.isHeatedSmoke
                    val displayType = if (isHeat) "Heated" else "Cigarette"

                    Row(
                        modifier = Modifier
                            .fillMaxWidth(0.92f)
                            .padding(vertical = 3.dp)
                            .clip(RoundedCornerShape(14.dp))
                            .background(Color(0xFF141820))
                            .border(1.dp, Color.White.copy(alpha = 0.05f), RoundedCornerShape(14.dp))
                            .clickable {
                                SoundAndHapticFeedback.playClick(context, view)
                                logToDelete = log
                                showDeleteDialog = true
                            }
                            .padding(horizontal = 12.dp, vertical = 9.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                imageVector = if (isHeat) Icons.Filled.Bolt else Icons.Filled.LocalFireDepartment,
                                contentDescription = null,
                                tint = if (isHeat) DailyWearColors.HeatIndigo else DailyWearColors.SmokeRed,
                                modifier = Modifier.size(14.dp)
                            )
                            Spacer(Modifier.width(6.dp))
                            Text(
                                text = "$count $displayType",
                                fontSize = 12.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = Color.White
                            )
                        }

                        val timeStr = remember(log.logged_at) {
                            try {
                                val inst = Instant.parse(log.logged_at)
                                val z = inst.atZone(java.time.ZoneId.systemDefault())
                                String.format(Locale.getDefault(), "%02d:%02d", z.hour, z.minute)
                            } catch (_: Exception) {
                                if (log.logged_at.length >= 16) log.logged_at.substring(11, 16) else ""
                            }
                        }

                        Text(
                            text = timeStr,
                            fontSize = 10.sp,
                            color = Color.White.copy(alpha = 0.45f)
                        )
                    }
                }

                item {
                    Spacer(Modifier.height(16.dp))
                }
            }
        }
    }

    // Delete Confirmation Dialog
    if (showDeleteDialog && logToDelete != null) {
        Dialog(
            showDialog = showDeleteDialog,
            onDismissRequest = {
                showDeleteDialog = false
                logToDelete = null
            }
        ) {
            Alert(
                title = {
                    Text(
                        text = "Delete Log?",
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold,
                        textAlign = TextAlign.Center
                    )
                },
                content = {
                    item {
                        val count = maxOf(1, logToDelete?.value?.toInt() ?: 1)
                        val isHeat = logToDelete?.metadata?.contains("Heated") == true
                        val typeName = if (isHeat) "Heated Tobacco" else "Cigarette"
                        Text(
                            text = "$count $typeName",
                            fontSize = 12.sp,
                            color = Color.Gray,
                            textAlign = TextAlign.Center
                        )
                    }
                    item {
                        Spacer(Modifier.height(8.dp))
                        Button(
                            onClick = {
                                val target = logToDelete
                                if (target != null) {
                                    deleteLog(target)
                                }
                                showDeleteDialog = false
                                logToDelete = null
                            },
                            colors = ButtonDefaults.buttonColors(backgroundColor = Color(0xFFE53935)),
                            modifier = Modifier.fillMaxWidth().height(36.dp)
                        ) {
                            Text("Delete", fontSize = 12.sp, color = Color.White, fontWeight = FontWeight.Bold)
                        }
                    }
                    item {
                        Spacer(Modifier.height(4.dp))
                        Button(
                            onClick = {
                                SoundAndHapticFeedback.playClick(context, view)
                                showDeleteDialog = false
                                logToDelete = null
                            },
                            colors = ButtonDefaults.buttonColors(backgroundColor = Color(0xFF262A32)),
                            modifier = Modifier.fillMaxWidth().height(36.dp)
                        ) {
                            Text("Cancel", fontSize = 12.sp, color = Color.LightGray)
                        }
                    }
                }
            )
        }
    }

    if (showCustomDialog) {
        CustomSmokeDialog(
            show = showCustomDialog,
            onDismiss = { showCustomDialog = false },
            onLog = { type, offsetMinutes ->
                SoundAndHapticFeedback.playLogAdded(context, view)
                sessionManager.logSmoke(type, dayOffset, offsetMinutes)
                loadCachedDate(targetDateStr)
                showCustomDialog = false
            }
        )
    }

    if (showGoalDialog) {
        GoalEditDialog(
            show = showGoalDialog,
            isWater = false,
            currentValue = dailyGoal,
            onDismiss = { showGoalDialog = false },
            onSave = { newGoal ->
                sessionManager.updateSmokesGoal(newGoal)
                showGoalDialog = false
            }
        )
    }
}
