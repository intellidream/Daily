package com.intellidream.daily.wearos.presentation.bubbles

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
import androidx.compose.material.icons.filled.LocalCafe
import androidx.compose.material.icons.filled.LocalDrink
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
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
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
fun BubblesScreen(sessionManager: WatchSessionManager) {
    var dailyGoal by remember { mutableIntStateOf(sessionManager.cachedBubblesGoal ?: 2000) }
    var isLogging by remember { mutableStateOf(false) }
    var historyLogs by remember { mutableStateOf<List<HabitLog>>(sessionManager.cachedBubblesLogs ?: emptyList()) }
    var todayWater by remember { mutableIntStateOf(historyLogs.filter { it.metadata?.contains("Coffee") != true }.sumOf { it.value.toInt() }) }
    var todayCoffee by remember { mutableIntStateOf(historyLogs.filter { it.metadata?.contains("Coffee") == true }.sumOf { it.value.toInt() }) }
    var todayTotal by remember { mutableIntStateOf(todayWater + todayCoffee) }

    val scope = rememberCoroutineScope()
    val columnState = rememberResponsiveColumnState()
    val refreshTrigger by sessionManager.dataRefreshTrigger.collectAsState()

    val timeFormat = remember { SimpleDateFormat("HH:mm", Locale.getDefault()) }
    val parseFormat = remember { SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US) }

    val fetchLogs = {
        scope.launch {
            try {
                // Fetch dynamic goal
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
                            eq("habit_type", "water")
                            eq("is_deleted", false)
                            gte("logged_at", startOfDay)
                        }
                    }.decodeList<HabitLog>().sortedByDescending { it.logged_at }

                historyLogs = logs
                sessionManager.cachedBubblesLogs = logs
                
                var tWater = 0
                var tCoffee = 0
                for (log in logs) {
                    val isCoffee = log.metadata?.contains("Coffee") == true
                    if (isCoffee) tCoffee += log.value.toInt() else tWater += log.value.toInt()
                }
                todayWater = tWater
                todayCoffee = tCoffee
                todayTotal = tWater + tCoffee
                sessionManager.persistWaterTotal(todayTotal)
                
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

    val logWater: (Int, String) -> Unit = { amount, type ->
        if (!isLogging) {
            isLogging = true
            todayTotal += amount
            sessionManager.persistWaterTotal(todayTotal)
            if (type.contains("Coffee")) todayCoffee += amount else todayWater += amount
            
            val metadata = buildJsonObject { put("drink", type) }.toString()
            val format = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
            format.timeZone = TimeZone.getTimeZone("UTC")
            val nowStr = format.format(Date())

            val newLog = HabitLog(
                user_id = sessionManager.currentUserId.value,
                habit_type = "water",
                value = amount.toDouble(),
                unit = "ml",
                logged_at = nowStr,
                metadata = metadata
            )
            
            val newHistory = listOf(newLog) + historyLogs
            historyLogs = newHistory
            sessionManager.cachedBubblesLogs = newHistory

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
                Icon(imageVector = Icons.Filled.WaterDrop, contentDescription = null, tint = Color.Cyan, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(4.dp))
                Text("Bubbles", fontWeight = FontWeight.Bold, color = Color.White)
            }
        }
        
        item {
            // Main Ring
            Box(contentAlignment = Alignment.Center, modifier = Modifier.size(120.dp)) {
                val totalG = maxOf(dailyGoal, 1).toFloat()
                val wProg = (todayWater.toFloat() / totalG).coerceIn(0f, 1f)
                val cProg = (todayCoffee.toFloat() / totalG).coerceIn(0f, 1f)
                
                val wProgAnim by animateFloatAsState(targetValue = wProg, animationSpec = tween(800))
                val cProgAnim by animateFloatAsState(targetValue = cProg, animationSpec = tween(800))

                androidx.compose.foundation.Canvas(modifier = Modifier.fillMaxSize()) {
                    val strokeWidth = 10.dp.toPx()
                    
                    // Background Ring
                    drawArc(
                        color = Color.DarkGray.copy(alpha=0.3f),
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
                    
                    // Coffee (Orange) draws immediately after Water
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
                    Text("$todayTotal", fontWeight = FontWeight.Bold, fontSize = 24.sp)
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
                QuickAddMiniButton(Icons.Filled.WaterDrop, 300, Color.Cyan) { logWater(300, "Water") }
                QuickAddMiniButton(Icons.Filled.LocalDrink, 150, Color.Cyan) { logWater(150, "Small Water") }
                QuickAddMiniButton(Icons.Filled.LocalCafe, 100, Color(0xFFFFA500)) { logWater(100, "Coffee") }
            }
        }

        if (historyLogs.isNotEmpty()) {
            item {
                ListHeader { Text("TODAY'S LOGS", color = Color.Gray, fontSize = 10.sp) }
            }
            
            items(historyLogs.size) { index ->
                val log = historyLogs[index]
                val isCoffee = log.metadata?.contains("Coffee") == true
                val isSmallWater = log.metadata?.contains("Small Water") == true
                val type = if (isCoffee) "Coffee" else if (isSmallWater) "Small Water" else "Water"
                
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
                        val rowIcon = when {
                            isCoffee -> Icons.Filled.LocalCafe
                            isSmallWater -> Icons.Filled.LocalDrink
                            else -> Icons.Filled.WaterDrop
                        }
                        Icon(
                            imageVector = rowIcon,
                            contentDescription = type,
                            tint = if (isCoffee) Color(0xFFFFA500) else Color.Cyan,
                            modifier = Modifier.size(16.dp)
                        )
                        Spacer(Modifier.width(8.dp))
                        Text(
                            "${log.value.toInt()} ${log.unit} $type",
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
fun QuickAddMiniButton(icon: ImageVector, amount: Int, color: Color, onClick: () -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            modifier = Modifier
                .size(44.dp)
                .clip(CircleShape)
                .background(color.copy(alpha = 0.2f))
                .clickable { onClick() },
            contentAlignment = Alignment.Center
        ) {
            Icon(imageVector = icon, contentDescription = null, tint = color, modifier = Modifier.size(24.dp))
        }
        Spacer(Modifier.height(4.dp))
        Text("$amount", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = color)
    }
}
