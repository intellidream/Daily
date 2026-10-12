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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.LocalFireDepartment
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
import com.intellidream.daily.wearos.presentation.components.QuickAddChip
import com.intellidream.daily.wearos.presentation.components.TemporalNavHeader
import com.intellidream.daily.wearos.presentation.theme.DailyWearColors
import com.intellidream.daily.wearos.util.SoundAndHapticFeedback
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
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
    var dailyGoal by remember { mutableIntStateOf(sessionManager.cachedSmokesGoal ?: 20) }
    var isLogging by remember { mutableStateOf(false) }

    val scope = rememberCoroutineScope()
    val columnState = rememberResponsiveColumnState(
        rotaryMode = ScalingLazyColumnState.RotaryMode.Snap
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

    // Fast local memory cache hit when dayOffset changes: 0ms UI update
    LaunchedEffect(dayOffset) {
        val cached = sessionManager.getSmokesLogs(targetDateStr)
        if (cached != null) {
            dayLogs = cached
            var tCig = 0
            var tHeat = 0
            for (log in cached) {
                val count = maxOf(1, log.value.toInt())
                val isHeat = log.metadata?.contains("Heated") == true
                if (isHeat) tHeat += count else tCig += count
            }
            todayCig = tCig
            todayHeat = tHeat
            todayTotal = tCig + tHeat
        }
    }

    val fetchLogs = {
        scope.launch {
            val goalDeferred = async {
                if (dayOffset == 0 && sessionManager.cachedSmokesGoal == null) {
                    try {
                        val goals = sessionManager.supabaseClient.postgrest["habits_goals"]
                            .select {
                                filter {
                                    eq("habit_type", "smoke")
                                    eq("is_deleted", false)
                                }
                            }.decodeList<com.intellidream.daily.wearos.domain.model.HabitGoal>()

                        if (goals.isNotEmpty()) {
                            val goal = goals.first().target_value?.toInt() ?: 20
                            sessionManager.cachedSmokesGoal = goal
                            dailyGoal = goal
                        }
                    } catch (_: Exception) {}
                }
            }

            val logsDeferred = async {
                try {
                    val cal = Calendar.getInstance()
                    cal.set(Calendar.HOUR_OF_DAY, 0)
                    cal.set(Calendar.MINUTE, 0)
                    cal.set(Calendar.SECOND, 0)
                    cal.set(Calendar.MILLISECOND, 0)
                    cal.add(Calendar.DAY_OF_YEAR, dayOffset)
                    val startOfDay = cal.time
                    val startStr = Instant.ofEpochMilli(startOfDay.time).toString()

                    val targetDayCal = cal.clone() as Calendar

                    cal.add(Calendar.DAY_OF_YEAR, 1)
                    val endOfDay = cal.time
                    val endStr = Instant.ofEpochMilli(endOfDay.time).toString()

                    val logs = sessionManager.supabaseClient.postgrest["habits_logs"]
                        .select {
                            filter {
                                eq("habit_type", "smoke")
                                eq("is_deleted", false)
                                and {
                                    gte("logged_at", startStr)
                                    lt("logged_at", endStr)
                                }
                            }
                        }.decodeList<HabitLog>().sortedByDescending { it.logged_at }

                    val targetStr = localFormat.format(targetDayCal.time)
                    val dayOnlyLogs = logs.filter { log ->
                        try {
                            val parsed = HabitDateParser.parseToLocalDate(log.logged_at)
                            parsed?.toString() == targetStr
                        } catch (_: Exception) {
                            true
                        }
                    }

                    var tCig = 0
                    var tHeat = 0
                    for (log in dayOnlyLogs) {
                        val count = maxOf(1, log.value.toInt())
                        val isHeat = log.metadata?.contains("Heated") == true
                        if (isHeat) tHeat += count else tCig += count
                    }

                    dayLogs = dayOnlyLogs
                    todayCig = tCig
                    todayHeat = tHeat
                    todayTotal = tCig + tHeat

                    sessionManager.setSmokesLogs(targetStr, dayOnlyLogs)
                    if (dayOffset == 0) {
                        sessionManager.persistSmokesTotal(todayTotal)
                    }
                    SoundAndHapticFeedback.playSuccess(context, view)
                } catch (e: Exception) {
                    if (e is kotlinx.coroutines.CancellationException) throw e
                    android.util.Log.w("SmokesScreen", "Failed to fetch logs: ${e.localizedMessage}")
                }
            }

            goalDeferred.await()
            logsDeferred.await()
        }
    }

    LaunchedEffect(dayOffset, refreshTrigger) {
        fetchLogs()
    }

    val deleteLog: (HabitLog) -> Unit = { log ->
        val count = maxOf(1, log.value.toInt())
        val isHeat = log.metadata?.contains("Heated") == true
        if (isHeat) {
            todayHeat = maxOf(0, todayHeat - count)
        } else {
            todayCig = maxOf(0, todayCig - count)
        }
        todayTotal = todayCig + todayHeat
        val newLogs = dayLogs.filter { it.id != log.id }
        dayLogs = newLogs

        sessionManager.setSmokesLogs(targetDateStr, newLogs)
        if (dayOffset == 0) {
            sessionManager.persistSmokesTotal(todayTotal)
            sessionManager.updateSmokesWeekToday(isHeated = isHeat, delta = -count.toDouble())
        }
        SoundAndHapticFeedback.playClick(context, view)

        scope.launch {
            try {
                sessionManager.supabaseClient.postgrest["habits_logs"]
                    .update({
                        set("is_deleted", true)
                    }) {
                        filter { eq("id", log.id) }
                    }
            } catch (_: Exception) {}
        }
    }

    val logSmoke: (String) -> Unit = { type ->
        if (!isLogging) {
            isLogging = true
            SoundAndHapticFeedback.playLogAdded(context, view)

            val isHeat = type.contains("Heated")
            if (isHeat) todayHeat += 1 else todayCig += 1
            todayTotal = todayCig + todayHeat

            val metadata = buildJsonObject { put("brand", type) }.toString()

            val targetCal = Calendar.getInstance()
            if (dayOffset != 0) {
                targetCal.add(Calendar.DAY_OF_YEAR, dayOffset)
            }
            val loggedAtStr = isoFormat.format(targetCal.time)
            val currentDateStr = localFormat.format(targetCal.time)

            val newLog = HabitLog(
                user_id = sessionManager.currentUserId.value,
                habit_type = "smoke",
                value = 1.0,
                unit = "count",
                logged_at = loggedAtStr,
                metadata = metadata
            )

            val newHistory = listOf(newLog) + dayLogs
            dayLogs = newHistory
            sessionManager.setSmokesLogs(currentDateStr, newHistory)
            if (dayOffset == 0) {
                sessionManager.persistSmokesTotal(todayTotal)
                sessionManager.updateSmokesWeekToday(isHeated = isHeat, delta = 1.0)
            }

            scope.launch {
                try {
                    sessionManager.supabaseClient.postgrest["habits_logs"].insert(newLog)
                } catch (_: Exception) {
                    OfflineSyncManager.shared.enqueue(newLog)
                } finally {
                    isLogging = false
                }
            }
        }
    }

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
                        tint = getSmokesColor(todayTotal, dailyGoal),
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

            // Hero 132dp Progress Ring
            item {
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier
                        .padding(vertical = 8.dp)
                        .size(132.dp)
                        .clickable {
                            SoundAndHapticFeedback.playClick(context, view)
                            if (dayLogs.isNotEmpty()) {
                                scope.launch { columnState.state.animateScrollToItem(5) }
                            }
                            onOpenLogs?.invoke("smokes", formattedDateTitle, dayLogs, deleteLog)
                        }
                ) {
                    val progress = (todayTotal.toFloat() / maxOf(dailyGoal, 1).toFloat()).coerceIn(0f, 1f)
                    val progAnim by animateFloatAsState(targetValue = progress, animationSpec = tween(600))
                    val ringColor = getSmokesColor(todayTotal, dailyGoal)

                    androidx.compose.foundation.Canvas(modifier = Modifier.fillMaxSize()) {
                        val strokeWidth = 11.dp.toPx()

                        // Background Track
                        drawArc(
                            color = Color.White.copy(alpha = 0.08f),
                            startAngle = -90f,
                            sweepAngle = 360f,
                            useCenter = false,
                            style = Stroke(width = strokeWidth, cap = StrokeCap.Round)
                        )

                        val sweep = (progAnim * 360f).coerceIn(0f, 360f)
                        if (sweep > 0) {
                            drawArc(
                                color = ringColor,
                                startAngle = -90f,
                                sweepAngle = sweep,
                                useCenter = false,
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
                            fontSize = 32.sp,
                            color = if (todayTotal > dailyGoal) DailyWearColors.SmokeRed else Color.White
                        )
                        Text(
                            text = "/ $dailyGoal max",
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Medium,
                            color = Color.White.copy(alpha = 0.55f)
                        )
                    }
                }
            }

            // Quick Add Action Chips (48dp full-width touch targets)
            item {
                QuickAddChip(
                    icon = "🔥",
                    title = "+1 Cigarette",
                    accentColor = DailyWearColors.SmokeRed,
                    onClick = { logSmoke("Cigarette") }
                )
            }
            item {
                Spacer(Modifier.height(4.dp))
                QuickAddChip(
                    icon = "⚡",
                    title = "+1 Heated",
                    accentColor = DailyWearColors.HeatIndigo,
                    onClick = { logSmoke("Heated Tobacco") }
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
                                scope.launch { columnState.state.animateScrollToItem(5) }
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
                            Text("🔥", fontSize = 12.sp)
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
                            Text("⚡", fontSize = 12.sp)
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

                items(dayLogs.size) { index ->
                    val log = dayLogs[index]
                    val count = maxOf(1, log.value.toInt())
                    val isHeat = log.metadata?.contains("Heated") == true
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
                            Text(if (isHeat) "⚡" else "🔥", fontSize = 13.sp)
                            Spacer(Modifier.width(6.dp))
                            Text(
                                text = "$count $displayType",
                                fontSize = 12.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = Color.White
                            )
                        }

                        val timeStr = try {
                            val inst = Instant.parse(log.logged_at)
                            val z = inst.atZone(java.time.ZoneId.systemDefault())
                            String.format(Locale.getDefault(), "%02d:%02d", z.hour, z.minute)
                        } catch (_: Exception) {
                            if (log.logged_at.length >= 16) log.logged_at.substring(11, 16) else ""
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
}
