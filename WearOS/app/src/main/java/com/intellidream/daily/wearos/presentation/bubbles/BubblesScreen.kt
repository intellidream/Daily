package com.intellidream.daily.wearos.presentation.bubbles

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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.WaterDrop
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
fun BubblesScreen(
    sessionManager: WatchSessionManager,
    onOpenLogs: (habitType: String, dateTitle: String, logs: List<HabitLog>, onDelete: (HabitLog) -> Unit) -> Unit
) {
    var dayOffset by remember { mutableIntStateOf(0) }
    var dailyGoal by remember { mutableIntStateOf(sessionManager.cachedBubblesGoal ?: 2000) }
    var isLogging by remember { mutableStateOf(false) }
    var dayLogs by remember { mutableStateOf<List<HabitLog>>(sessionManager.cachedBubblesLogs ?: emptyList()) }
    var todayWater by remember { mutableIntStateOf(dayLogs.filter { it.metadata?.contains("Coffee") != true }.sumOf { it.value.toInt() }) }
    var todayCoffee by remember { mutableIntStateOf(dayLogs.filter { it.metadata?.contains("Coffee") == true }.sumOf { it.value.toInt() }) }
    var todayTotal by remember { mutableIntStateOf(todayWater + todayCoffee) }

    val scope = rememberCoroutineScope()
    val listState = rememberScalingLazyListState()
    val refreshTrigger by sessionManager.dataRefreshTrigger.collectAsState()
    val view = LocalView.current

    val localFormat = remember { SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()) }
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

    val fetchLogs = {
        scope.launch {
            try {
                // Fetch dynamic goal if viewing today
                if (dayOffset == 0) {
                    val goals = sessionManager.supabaseClient.postgrest["habits_goals"]
                        .select {
                            filter {
                                eq("habit_type", "water")
                                eq("is_deleted", false)
                            }
                        }.decodeList<com.intellidream.daily.wearos.domain.model.HabitGoal>()

                    if (goals.isNotEmpty()) {
                        dailyGoal = goals.first().target_value?.toInt() ?: 2000
                        sessionManager.cachedBubblesGoal = dailyGoal
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
                            eq("habit_type", "water")
                            eq("is_deleted", false)
                            gte("logged_at", startStr)
                            lt("logged_at", endStr)
                        }
                    }.decodeList<HabitLog>().sortedByDescending { it.logged_at }

                var tWater = 0
                var tCoffee = 0
                for (log in logs) {
                    val isCoffee = log.metadata?.contains("Coffee") == true
                    if (isCoffee) tCoffee += log.value.toInt() else tWater += log.value.toInt()
                }

                dayLogs = logs
                todayWater = tWater
                todayCoffee = tCoffee
                todayTotal = tWater + tCoffee

                if (dayOffset == 0) {
                    sessionManager.cachedBubblesLogs = logs
                    sessionManager.persistWaterTotal(todayTotal)
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
        val isCoffee = log.metadata?.contains("Coffee") == true
        if (isCoffee) {
            todayCoffee = maxOf(0, todayCoffee - log.value.toInt())
        } else {
            todayWater = maxOf(0, todayWater - log.value.toInt())
        }
        todayTotal = todayWater + todayCoffee
        val newLogs = dayLogs.filter { it.id != log.id }
        dayLogs = newLogs

        if (dayOffset == 0) {
            sessionManager.cachedBubblesLogs = newLogs
            sessionManager.persistWaterTotal(todayTotal)
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

    val logWater: (Int, String) -> Unit = { amount, type ->
        if (!isLogging) {
            isLogging = true
            view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)

            todayTotal += amount
            if (type.contains("Coffee")) todayCoffee += amount else todayWater += amount
            if (dayOffset == 0) {
                sessionManager.persistWaterTotal(todayTotal)
            }

            val metadata = buildJsonObject { put("drink", type) }.toString()

            // Calculate timestamp for the viewed date
            val targetCal = Calendar.getInstance()
            if (dayOffset != 0) {
                targetCal.add(Calendar.DAY_OF_YEAR, dayOffset)
            }
            val loggedAtStr = isoFormat.format(targetCal.time)

            val newLog = HabitLog(
                user_id = sessionManager.currentUserId.value,
                habit_type = "water",
                value = amount.toDouble(),
                unit = "ml",
                logged_at = loggedAtStr,
                metadata = metadata
            )

            val newHistory = listOf(newLog) + dayLogs
            dayLogs = newHistory
            if (dayOffset == 0) {
                sessionManager.cachedBubblesLogs = newHistory
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
                        imageVector = Icons.Filled.WaterDrop,
                        contentDescription = null,
                        tint = Color.Cyan,
                        modifier = Modifier.size(15.dp)
                    )
                    Spacer(Modifier.width(4.dp))
                    Text("Bubbles", fontWeight = FontWeight.Bold, fontSize = 16.sp, color = Color.White)
                }
            }

            // Temporal Navigation Header
            item {
                TemporalNavHeader(
                    title = formattedDateTitle,
                    canGoForward = dayOffset < 0,
                    accentColor = Color.Cyan,
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
                                onOpenLogs("water", formattedDateTitle, dayLogs, deleteLog)
                            }
                    ) {
                        val totalG = maxOf(dailyGoal, 1).toFloat()
                        val wProg = (todayWater.toFloat() / totalG).coerceIn(0f, 1f)
                        val cProg = (todayCoffee.toFloat() / totalG).coerceIn(0f, 1f)

                        val wProgAnim by animateFloatAsState(targetValue = wProg, animationSpec = tween(600))
                        val cProgAnim by animateFloatAsState(targetValue = cProg, animationSpec = tween(600))

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

                            val wSweep = (wProgAnim * 360f).coerceIn(0f, 360f)
                            val cSweep = (cProgAnim * 360f).coerceIn(0f, 360f)

                            // Water (Cyan)
                            if (wSweep > 0) {
                                drawArc(
                                    color = Color.Cyan,
                                    startAngle = -90f,
                                    sweepAngle = wSweep,
                                    useCenter = false,
                                    style = Stroke(width = strokeWidth, cap = StrokeCap.Round)
                                )
                            }

                            // Coffee (Orange)
                            if (cSweep > 0) {
                                drawArc(
                                    color = Color(0xFFFFA500),
                                    startAngle = -90f + wSweep,
                                    sweepAngle = cSweep,
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
                                color = Color.White
                            )
                            Text(
                                text = "/ $dailyGoal",
                                fontSize = 10.sp,
                                color = Color.Gray
                            )
                        }
                    }

                    // 3 Quick Add Action Buttons (💧 300, 💧 150, ☕ 100)
                    Column(
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        ActionPillButton(
                            text = "💧 300",
                            color = Color.Cyan,
                            onClick = { logWater(300, "Large Water") }
                        )
                        ActionPillButton(
                            text = "💧 150",
                            color = Color.Cyan,
                            onClick = { logWater(150, "Small Water") }
                        )
                        ActionPillButton(
                            text = "☕ 100",
                            color = Color(0xFFFFA500),
                            onClick = { logWater(100, "Coffee") }
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
                            onOpenLogs("water", formattedDateTitle, dayLogs, deleteLog)
                        }
                        .padding(vertical = 4.dp, horizontal = 8.dp),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("💧", fontSize = 11.sp)
                    Spacer(Modifier.width(2.dp))
                    Text(
                        text = "$todayWater ml",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Medium,
                        color = Color.White
                    )
                    Text("  •  ", fontSize = 11.sp, color = Color.Gray)
                    Text("☕", fontSize = 11.sp)
                    Spacer(Modifier.width(2.dp))
                    Text(
                        text = "$todayCoffee ml",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Medium,
                        color = Color.White
                    )
                    Spacer(Modifier.width(4.dp))
                    Text(
                        text = "›",
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.Cyan
                    )
                }
                Spacer(Modifier.height(10.dp))
            }
        }
    }
}

@Composable
fun ActionPillButton(
    text: String,
    color: Color,
    onClick: () -> Unit
) {
    Box(
        modifier = Modifier
            .size(width = 68.dp, height = 26.dp)
            .clip(RoundedCornerShape(13.dp))
            .background(Color(0xFF222222))
            .clickable { onClick() },
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = text,
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold,
            color = Color.White
        )
    }
}
