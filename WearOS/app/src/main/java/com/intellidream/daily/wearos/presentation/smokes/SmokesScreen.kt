package com.intellidream.daily.wearos.presentation.smokes

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
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.FlashOn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.wear.compose.foundation.lazy.items
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.ListHeader
import androidx.wear.compose.material.Text
import com.google.android.horologist.compose.layout.ScalingLazyColumn
import com.google.android.horologist.compose.layout.rememberResponsiveColumnState
import com.intellidream.daily.wearos.data.OfflineSyncManager
import com.intellidream.daily.wearos.data.WatchSessionManager
import com.intellidream.daily.wearos.domain.model.HabitLog
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.flow.first
import androidx.compose.runtime.collectAsState
import kotlinx.coroutines.launch
import kotlinx.serialization.json.put
import kotlinx.serialization.json.buildJsonObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import com.google.android.horologist.annotations.ExperimentalHorologistApi

@OptIn(ExperimentalHorologistApi::class)
@Composable
fun SmokesScreen(sessionManager: WatchSessionManager) {
    var dailyGoal by remember { mutableIntStateOf(sessionManager.cachedSmokesGoal ?: 20) }
    var isLogging by remember { mutableStateOf(false) }
    var historyLogs by remember { mutableStateOf<List<HabitLog>>(sessionManager.cachedSmokesLogs ?: emptyList()) }
    var todayTotal by remember { mutableIntStateOf(historyLogs.size) }

    val scope = rememberCoroutineScope()
    val columnState = rememberResponsiveColumnState()
    val refreshTrigger by sessionManager.dataRefreshTrigger.collectAsState()

    val timeFormat = remember { SimpleDateFormat("HH:mm", Locale.getDefault()) }
    val parseFormat = remember {
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }
    }

    val fetchLogs = {
        scope.launch {
            try {
                // Fetch dynamic goal
                val userId = sessionManager.currentUserId.value
                if (userId != null) {
                    val prefs = sessionManager.supabaseClient.postgrest["user_preferences"]
                        .select {
                            filter {
                                eq("id", userId)
                            }
                        }.decodeList<com.intellidream.daily.wearos.domain.model.UserPreference>()

                    if (prefs.isNotEmpty()) {
                        dailyGoal = prefs.first().smokes_baseline ?: 20
                        sessionManager.cachedSmokesGoal = dailyGoal
                    }
                }
            } catch (ignored: Exception) {
                // Ignore goal fetch errors (e.g. offline) and proceed with default dailyGoal
            }
                
            try {
                // Fetch today's logs
                val calendar = java.util.Calendar.getInstance()
                calendar.set(java.util.Calendar.HOUR_OF_DAY, 0)
                calendar.set(java.util.Calendar.MINUTE, 0)
                calendar.set(java.util.Calendar.SECOND, 0)
                
                val format = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
                format.timeZone = TimeZone.getTimeZone("UTC")
                val startOfDay = format.format(calendar.time)

                val logs = sessionManager.supabaseClient.postgrest["habits_logs"]
                    .select {
                        filter {
                            eq("habit_type", "smokes")
                            eq("is_deleted", false)
                            gte("logged_at", startOfDay)
                        }
                    }.decodeList<HabitLog>().sortedByDescending { it.logged_at }

                historyLogs = logs
                sessionManager.cachedSmokesLogs = logs
                todayTotal = logs.size
                sessionManager.persistSmokesTotal(todayTotal)

            } catch (e: Exception) {
                // Token expired — attempt silent session refresh. The refreshed
                // session will trigger dataRefreshTrigger via onAppResumed, which
                // LaunchedEffect listens to and will re-invoke fetchLogs.
                try {
                    sessionManager.supabaseClient.auth.refreshCurrentSession()
                } catch (_: Exception) { }
            }
        }
    }

    LaunchedEffect(refreshTrigger) {
        fetchLogs()
    }

    val getSmokesColor: (Int, Int) -> Color = { total, goal ->
        when {
            total >= goal -> Color(0xFFE53935) // Muted Red
            total >= goal * 0.8 -> Color(0xFFFB8C00) // Muted Orange
            else -> Color(0xFFFFD54F) // Muted Yellow
        }
    }

    val logSmoke: (String) -> Unit = { type ->
        if (!isLogging) {
            isLogging = true
            todayTotal += 1
            sessionManager.persistSmokesTotal(todayTotal)
            
            val metadata = buildJsonObject { put("type", type) }.toString()
            val format = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
            format.timeZone = TimeZone.getTimeZone("UTC")
            val nowStr = format.format(Date())

            val newLog = HabitLog(
                user_id = sessionManager.currentUserId.value,
                habit_type = "smokes",
                value = 1.0,
                unit = "cig",
                logged_at = nowStr,
                metadata = metadata
            )

            val newHistory = listOf(newLog) + historyLogs
            historyLogs = newHistory
            sessionManager.cachedSmokesLogs = newHistory

            scope.launch {
                try {
                    sessionManager.supabaseClient.postgrest["habits_logs"].insert(newLog)
                } catch (ignored: Exception) {
                    OfflineSyncManager.shared.enqueue(newLog)
                } finally {
                    isLogging = false
                }
            }
        }
    }

    ScalingLazyColumn(
        columnState = columnState,
        modifier = Modifier.fillMaxSize()
    ) {
        item {
            // Header
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(bottom = 8.dp)) {
                Icon(imageVector = Icons.Filled.LocalFireDepartment, contentDescription = null, tint = getSmokesColor(todayTotal, dailyGoal), modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(4.dp))
                Text("Smokes", fontWeight = FontWeight.Bold, color = Color.White)
            }
        }

        item {
            // Main Ring
            Box(contentAlignment = Alignment.Center, modifier = Modifier.size(120.dp)) {
                val remaining = maxOf(0, dailyGoal - todayTotal)
                val progress = remaining.toFloat() / maxOf(dailyGoal, 1).toFloat()
                val ringColor = getSmokesColor(todayTotal, dailyGoal)
                
                CircularProgressIndicator(
                    progress = 1f,
                    modifier = Modifier.fillMaxSize(),
                    strokeWidth = 10.dp,
                    indicatorColor = Color.DarkGray.copy(alpha=0.3f),
                    trackColor = Color.Transparent
                )

                CircularProgressIndicator(
                    progress = animateFloatAsState(targetValue = progress, animationSpec = tween(800)).value,
                    modifier = Modifier.fillMaxSize(),
                    strokeWidth = 10.dp,
                    indicatorColor = ringColor,
                    trackColor = Color.Transparent
                )

                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("$todayTotal", fontWeight = FontWeight.Bold, fontSize = 24.sp, color = if(todayTotal>dailyGoal) Color.Red else Color.White)
                    Text("/ $dailyGoal", fontSize = 12.sp, color = Color.Gray)
                }
            }
        }
        
        item {
            Spacer(Modifier.height(8.dp))
        }

        item {
            // Buttons
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp),
                horizontalArrangement = Arrangement.SpaceEvenly
            ) {
                SmokesMiniButton(Icons.Filled.LocalFireDepartment, "Cig", Color(0xFFE53935)) { logSmoke("Cigarette") }
                SmokesMiniButton(Icons.Filled.FlashOn, "Heat", Color(0xFF1E90FF)) { logSmoke("Heated Tobacco") }
            }
        }

        if (historyLogs.isNotEmpty()) {
            item {
                ListHeader { Text("TODAY'S LOGS", color = Color.Gray, fontSize = 10.sp) }
            }
            
            items(historyLogs.size) { index ->
                val log = historyLogs[index]
                val type = if (log.metadata?.contains("Heated") == true) "Heated Tobacco" else "Cigarette"
                val isHeated = type == "Heated Tobacco"
                
                // Parse the UTC date properly into the Local Device Timezone
                val timeStr = remember(log.logged_at) {
                    try {
                        val pureUTC = log.logged_at.replace("Z", "") + "Z" // ensure Z bounds
                        val date = parseFormat.parse(pureUTC)
                        if (date != null) timeFormat.format(date) else ""
                    } catch (ignored: Exception) { "" }
                }

                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 2.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .background(Color.White.copy(alpha = 0.1f))
                        .padding(12.dp)
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            imageVector = if (isHeated) Icons.Filled.FlashOn else Icons.Filled.LocalFireDepartment,
                            contentDescription = type,
                            tint = if (isHeated) Color(0xFF1E90FF) else Color(0xFFE53935),
                            modifier = Modifier.size(16.dp)
                        )
                        Spacer(Modifier.width(8.dp))
                        Text(
                            if (isHeated) "1 Heat" else "1 Cig",
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Medium,
                            color = Color.White
                        )
                        Spacer(Modifier.weight(1f))
                        Text(timeStr, color = Color.Gray, fontSize = 10.sp)
                    }
                }
            }
        }
    }
}

@Composable
fun SmokesMiniButton(icon: ImageVector, label: String, color: Color, onClick: () -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            modifier = Modifier
                .width(60.dp)
                .height(44.dp)
                .clip(RoundedCornerShape(22.dp))
                .background(color.copy(alpha = 0.2f))
                .clickable { onClick() },
            contentAlignment = Alignment.Center
        ) {
            Icon(imageVector = icon, contentDescription = null, tint = color, modifier = Modifier.size(24.dp))
        }
        Spacer(Modifier.height(4.dp))
        Text(label, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = color)
    }
}
