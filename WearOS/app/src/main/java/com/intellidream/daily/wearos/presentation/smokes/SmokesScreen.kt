package com.intellidream.daily.wearos.presentation.smokes

import android.view.HapticFeedbackConstants
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
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
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.Text
import com.intellidream.daily.wearos.data.OfflineSyncManager
import com.intellidream.daily.wearos.data.WatchSessionManager
import com.intellidream.daily.wearos.domain.model.HabitLog
import com.intellidream.daily.wearos.presentation.bubbles.ActionPillButton
import com.intellidream.daily.wearos.presentation.components.TemporalNavHeader
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.launch
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

@Composable
fun SmokesScreen(
    sessionManager: WatchSessionManager,
    onOpenLogs: (habitType: String, dateTitle: String, logs: List<HabitLog>, onDelete: (HabitLog) -> Unit) -> Unit
) {
    var dayOffset by remember { mutableIntStateOf(0) }
    var dailyGoal by remember { mutableIntStateOf(sessionManager.cachedSmokesGoal ?: 20) }
    var isLogging by remember { mutableStateOf(false) }
    var dayLogs by remember { mutableStateOf<List<HabitLog>>(sessionManager.cachedSmokesLogs ?: emptyList()) }
    var todayCig by remember { mutableIntStateOf(dayLogs.count { it.metadata?.contains("Heated") != true }) }
    var todayHeat by remember { mutableIntStateOf(dayLogs.count { it.metadata?.contains("Heated") == true }) }
    var todayTotal by remember { mutableIntStateOf(todayCig + todayHeat) }

    val scope = rememberCoroutineScope()
    val listState = rememberScalingLazyListState()
    val refreshTrigger by sessionManager.dataRefreshTrigger.collectAsState()
    val view = LocalView.current

    val dayTitleFormat = remember { SimpleDateFormat("EEE, d MMM", Locale.getDefault()) }
    val isoFormat = remember {
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }
    }

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
            total >= goal -> Color(0xFFFF3B30) // Red
            total >= goal * 0.75 -> Color(0xFFFF9500) // Orange
            else -> Color(0xFF4CD964) // Green
        }
    }

    val fetchLogs = {
        scope.launch {
            try {
                // Fetch dynamic baseline if viewing today
                if (dayOffset == 0) {
                    val userId = sessionManager.currentUserId.value
                    if (userId != null) {
                        val prefs = sessionManager.supabaseClient.postgrest["user_preferences"]
                            .select {
                                filter { eq("id", userId) }
                            }.decodeList<com.intellidream.daily.wearos.domain.model.UserPreference>()

                        if (prefs.isNotEmpty()) {
                            dailyGoal = prefs.first().smokes_baseline ?: 20
                            sessionManager.cachedSmokesGoal = dailyGoal
                        }
                    }
                }
            } catch (_: Exception) {}

            try {
                val cal = Calendar.getInstance()
                cal.set(Calendar.HOUR_OF_DAY, 0)
                cal.set(Calendar.MINUTE, 0)
                cal.set(Calendar.SECOND, 0)
                cal.set(Calendar.MILLISECOND, 0)
                cal.add(Calendar.DAY_OF_YEAR, dayOffset)
                val startOfDay = cal.time
                val startStr = isoFormat.format(startOfDay)

                cal.add(Calendar.DAY_OF_YEAR, 1)
                val endOfDay = cal.time
                val endStr = isoFormat.format(endOfDay)

                val logs = sessionManager.supabaseClient.postgrest["habits_logs"]
                    .select {
                        filter {
                            eq("habit_type", "smokes")
                            eq("is_deleted", false)
                            gte("logged_at", startStr)
                            lt("logged_at", endStr)
                        }
                    }.decodeList<HabitLog>().sortedByDescending { it.logged_at }

                var tCig = 0
                var tHeat = 0
                for (log in logs) {
                    val isHeat = log.metadata?.contains("Heated") == true
                    if (isHeat) tHeat += 1 else tCig += 1
                }

                dayLogs = logs
                todayCig = tCig
                todayHeat = tHeat
                todayTotal = tCig + tHeat

                if (dayOffset == 0) {
                    sessionManager.cachedSmokesLogs = logs
                    sessionManager.persistSmokesTotal(todayTotal)
                }
            } catch (e: Exception) {
                try { sessionManager.supabaseClient.auth.refreshCurrentSession() } catch (_: Exception) {}
            }
        }
    }

    LaunchedEffect(dayOffset, refreshTrigger) {
        fetchLogs()
    }

    val deleteLog: (HabitLog) -> Unit = { log ->
        val isHeat = log.metadata?.contains("Heated") == true
        if (isHeat) {
            todayHeat = maxOf(0, todayHeat - 1)
        } else {
            todayCig = maxOf(0, todayCig - 1)
        }
        todayTotal = todayCig + todayHeat
        val newLogs = dayLogs.filter { it.id != log.id }
        dayLogs = newLogs

        if (dayOffset == 0) {
            sessionManager.cachedSmokesLogs = newLogs
            sessionManager.persistSmokesTotal(todayTotal)
        }

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
            view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)

            val isHeat = type.contains("Heated")
            if (isHeat) todayHeat += 1 else todayCig += 1
            todayTotal += 1

            if (dayOffset == 0) {
                sessionManager.persistSmokesTotal(todayTotal)
            }

            val metadata = buildJsonObject { put("type", type) }.toString()

            // Calculate timestamp for the viewed date
            val targetCal = Calendar.getInstance()
            if (dayOffset != 0) {
                targetCal.add(Calendar.DAY_OF_YEAR, dayOffset)
            }
            val loggedAtStr = isoFormat.format(targetCal.time)

            val newLog = HabitLog(
                user_id = sessionManager.currentUserId.value,
                habit_type = "smokes",
                value = 1.0,
                unit = "cig",
                logged_at = loggedAtStr,
                metadata = metadata
            )

            val newHistory = listOf(newLog) + dayLogs
            dayLogs = newHistory
            if (dayOffset == 0) {
                sessionManager.cachedSmokesLogs = newHistory
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

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
    ) {
        ScalingLazyColumn(
            state = listState,
            modifier = Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // Header
            item {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.padding(top = 2.dp, bottom = 2.dp)
                ) {
                    Icon(
                        imageVector = Icons.Filled.LocalFireDepartment,
                        contentDescription = null,
                        tint = getSmokesColor(todayTotal, dailyGoal),
                        modifier = Modifier.size(15.dp)
                    )
                    Spacer(Modifier.width(4.dp))
                    Text("Smokes", fontWeight = FontWeight.Bold, fontSize = 16.sp, color = Color.White)
                }
            }

            // Temporal Navigation Header
            item {
                TemporalNavHeader(
                    title = formattedDateTitle,
                    canGoForward = dayOffset < 0,
                    accentColor = Color(0xFFFF5555),
                    onPrevious = { dayOffset -= 1 },
                    onNext = { if (dayOffset < 0) dayOffset += 1 },
                    modifier = Modifier.padding(horizontal = 8.dp)
                )
            }

            // Main Progress Arc & Action Buttons Row
            item {
                Spacer(Modifier.height(4.dp))
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 10.dp),
                    horizontalArrangement = Arrangement.SpaceEvenly,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // Circular Progress Ring
                    Box(
                        contentAlignment = Alignment.Center,
                        modifier = Modifier
                            .size(86.dp)
                            .clickable {
                                view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                                onOpenLogs("smokes", formattedDateTitle, dayLogs, deleteLog)
                            }
                    ) {
                        val progress = (todayTotal.toFloat() / maxOf(dailyGoal, 1).toFloat()).coerceIn(0f, 1f)
                        val progAnim by animateFloatAsState(targetValue = progress, animationSpec = tween(600))
                        val ringColor = getSmokesColor(todayTotal, dailyGoal)

                        androidx.compose.foundation.Canvas(modifier = Modifier.fillMaxSize()) {
                            val strokeWidth = 9.dp.toPx()

                            // Background Track
                            drawArc(
                                color = Color.DarkGray.copy(alpha = 0.35f),
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

                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(
                                text = "$todayTotal",
                                fontWeight = FontWeight.Bold,
                                fontSize = 18.sp,
                                color = if (todayTotal > dailyGoal) Color(0xFFFF3B30) else Color.White
                            )
                            Text(
                                text = "/ $dailyGoal",
                                fontSize = 10.sp,
                                color = Color.Gray
                            )
                        }
                    }

                    // 2 Quick Add Action Buttons (🔥 Cig, ⚡ Heat)
                    Column(
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        ActionPillButton(
                            text = "🔥 Cig",
                            color = Color(0xFFFF3B30),
                            onClick = { logSmoke("Cigarette") }
                        )
                        ActionPillButton(
                            text = "⚡ Heat",
                            color = Color(0xFF1E90FF),
                            onClick = { logSmoke("Heated Tobacco") }
                        )
                    }
                }
            }

            // Centered Breakdown Row with chevron (Tapping opens Logs)
            item {
                Spacer(Modifier.height(8.dp))
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(8.dp))
                        .clickable {
                            view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                            onOpenLogs("smokes", formattedDateTitle, dayLogs, deleteLog)
                        }
                        .padding(vertical = 4.dp, horizontal = 8.dp),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("🔥", fontSize = 11.sp)
                    Spacer(Modifier.width(2.dp))
                    Text(
                        text = "$todayCig cig",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Medium,
                        color = Color.White
                    )
                    Text("  •  ", fontSize = 11.sp, color = Color.Gray)
                    Text("⚡", fontSize = 11.sp)
                    Spacer(Modifier.width(2.dp))
                    Text(
                        text = "$todayHeat heat",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Medium,
                        color = Color.White
                    )
                    Spacer(Modifier.width(4.dp))
                    Text(
                        text = "›",
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color(0xFFFF5555)
                    )
                }
                Spacer(Modifier.height(10.dp))
            }
        }
    }
}
