package com.intellidream.daily.wearos.presentation.smokes

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.Text
import com.intellidream.daily.wearos.data.WatchSessionManager
import com.intellidream.daily.wearos.domain.model.HabitLog
import com.intellidream.daily.wearos.presentation.components.TemporalNavHeader
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

data class SmokeDayBucket(
    val dateStr: String,
    val dayLabel: String,
    val isToday: Boolean,
    var cig: Double = 0.0,
    var heat: Double = 0.0
) {
    val total: Double get() = cig + heat
}

@Composable
fun Smokes7DaysScreen(sessionManager: WatchSessionManager) {
    var weekOffset by remember { mutableIntStateOf(0) }
    var dailyGoal by remember { mutableIntStateOf(sessionManager.cachedSmokesGoal ?: 20) }
    var buckets by remember { mutableStateOf<List<SmokeDayBucket>>(emptyList()) }
    var isLoading by remember { mutableStateOf(true) }

    val scope = rememberCoroutineScope()
    val listState = rememberScalingLazyListState()
    val refreshTrigger by sessionManager.dataRefreshTrigger.collectAsState()

    val localDateFmt = remember { SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()) }
    val dayLabelFmt = remember { SimpleDateFormat("EEE", Locale.getDefault()) }
    val weekTitleFmt = remember { SimpleDateFormat("d MMM", Locale.getDefault()) }
    val isoFmt = remember {
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }
    }
    val parseFmt = remember {
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }
    }

    // Monday-to-Sunday calculation
    fun getWeekWindow(offset: Int): Pair<Calendar, Calendar> {
        val cal = Calendar.getInstance()
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)

        val dayOfWeek = cal.get(Calendar.DAY_OF_WEEK)
        val daysFromMonday = if (dayOfWeek == Calendar.SUNDAY) 6 else dayOfWeek - Calendar.MONDAY
        cal.add(Calendar.DAY_OF_YEAR, -daysFromMonday + offset * 7)

        val monday = cal.clone() as Calendar
        val nextMonday = cal.clone() as Calendar
        nextMonday.add(Calendar.DAY_OF_YEAR, 7)
        return Pair(monday, nextMonday)
    }

    val weekTitle = remember(weekOffset) {
        if (weekOffset == 0) {
            "This Week"
        } else if (weekOffset == -1) {
            "Last Week"
        } else {
            val (mon, _) = getWeekWindow(weekOffset)
            val sun = mon.clone() as Calendar
            sun.add(Calendar.DAY_OF_YEAR, 6)
            "${weekTitleFmt.format(mon.time)} - ${weekTitleFmt.format(sun.time)}"
        }
    }

    val fetchWeekData: () -> Unit = {
        scope.launch {
            isLoading = true
            val (monCal, nextMonCal) = getWeekWindow(weekOffset)
            val startStr = isoFmt.format(monCal.time)
            val endStr = isoFmt.format(nextMonCal.time)
            val todayStr = localDateFmt.format(Date())

            val tempBuckets = mutableListOf<SmokeDayBucket>()
            for (i in 0 until 7) {
                val dCal = monCal.clone() as Calendar
                dCal.add(Calendar.DAY_OF_YEAR, i)
                val dStr = localDateFmt.format(dCal.time)
                val lbl = dayLabelFmt.format(dCal.time).take(1)
                tempBuckets.add(SmokeDayBucket(dStr, lbl, dStr == todayStr))
            }

            try {
                // Fetch dynamic goal if needed
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
            } catch (_: Exception) {}

            try {
                val logs = sessionManager.supabaseClient.postgrest["habits_logs"]
                    .select {
                        filter {
                            eq("habit_type", "smokes")
                            eq("is_deleted", false)
                            gte("logged_at", startStr)
                            lt("logged_at", endStr)
                        }
                    }.decodeList<HabitLog>()

                for (log in logs) {
                    try {
                        val pureUTC = log.logged_at.replace("Z", "") + "Z"
                        val date = parseFmt.parse(pureUTC)
                        if (date != null) {
                            val logDateStr = localDateFmt.format(date)
                            val bucket = tempBuckets.find { it.dateStr == logDateStr }
                            if (bucket != null) {
                                val isHeat = log.metadata?.contains("Heated") == true
                                if (isHeat) {
                                    bucket.heat += log.value
                                } else {
                                    bucket.cig += log.value
                                }
                            }
                        }
                    } catch (_: Exception) {}
                }

                buckets = tempBuckets
            } catch (_: Exception) {
                buckets = tempBuckets
            } finally {
                isLoading = false
            }
        }
    }

    LaunchedEffect(weekOffset, refreshTrigger) {
        fetchWeekData()
    }

    val weeklyAverage = remember(buckets, weekOffset) {
        if (buckets.isEmpty()) 0.0
        else {
            val sum = buckets.sumOf { it.total }
            if (weekOffset == 0) {
                val cal = Calendar.getInstance()
                val dow = cal.get(Calendar.DAY_OF_WEEK)
                val elapsed = if (dow == Calendar.SUNDAY) 7 else maxOf(1, dow - Calendar.MONDAY + 1)
                sum / elapsed
            } else {
                sum / 7.0
            }
        }
    }

    val formattedAvg = if (weeklyAverage >= 10.0) {
        weeklyAverage.toInt().toString()
    } else {
        String.format(Locale.US, "%.1f", weeklyAverage)
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
                    modifier = Modifier.padding(top = 2.dp, bottom = 4.dp)
                ) {
                    Icon(
                        imageVector = Icons.Filled.LocalFireDepartment,
                        contentDescription = null,
                        tint = Color(0xFFFF5555),
                        modifier = Modifier.size(15.dp)
                    )
                    Spacer(Modifier.width(4.dp))
                    Text("7 Days", fontWeight = FontWeight.Bold, fontSize = 16.sp, color = Color.White)
                }
            }

            // Temporal Navigation Header
            item {
                TemporalNavHeader(
                    title = weekTitle,
                    canGoForward = weekOffset < 0,
                    accentColor = Color(0xFFFF5555),
                    onPrevious = { weekOffset -= 1 },
                    onNext = { if (weekOffset < 0) weekOffset += 1 },
                    modifier = Modifier.padding(horizontal = 8.dp)
                )
            }

            // 7 Days Chart (Mon to Sun)
            item {
                Spacer(Modifier.height(6.dp))
                if (isLoading && buckets.isEmpty()) {
                    Box(modifier = Modifier.fillMaxWidth().height(80.dp), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(modifier = Modifier.size(24.dp), strokeWidth = 2.dp)
                    }
                } else {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(84.dp)
                            .padding(horizontal = 16.dp)
                    ) {
                        val maxVal = maxOf(dailyGoal.toDouble(), buckets.maxOfOrNull { it.total } ?: 1.0)

                        // Baseline Line (Dashed red)
                        val baselineY = 1f - (dailyGoal / maxVal).toFloat().coerceIn(0f, 1f)
                        androidx.compose.foundation.Canvas(modifier = Modifier.fillMaxSize()) {
                            drawLine(
                                color = Color(0xFFFF5252).copy(alpha = 0.5f),
                                start = Offset(0f, size.height * baselineY),
                                end = Offset(size.width, size.height * baselineY),
                                strokeWidth = 2f,
                                pathEffect = PathEffect.dashPathEffect(floatArrayOf(6f, 6f), 0f)
                            )
                        }

                        // Bars
                        Row(
                            modifier = Modifier.fillMaxSize(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.Bottom
                        ) {
                            buckets.forEach { item ->
                                val totalFrac = (item.total / maxVal).toFloat().coerceIn(0f, 1f)
                                val cigFrac = if (item.total > 0) (item.cig / item.total).toFloat() else 1f
                                val heatFrac = if (item.total > 0) (item.heat / item.total).toFloat() else 0f

                                Column(
                                    horizontalAlignment = Alignment.CenterHorizontally,
                                    verticalArrangement = Arrangement.Bottom,
                                    modifier = Modifier.weight(1f)
                                ) {
                                    Box(
                                        modifier = Modifier.weight(1f),
                                        contentAlignment = Alignment.BottomCenter
                                    ) {
                                        if (totalFrac > 0) {
                                            Column(
                                                modifier = Modifier
                                                    .width(13.dp)
                                                    .fillMaxHeight(totalFrac)
                                                    .clip(RoundedCornerShape(3.dp))
                                            ) {
                                                // Stacked Heat on top (Blue)
                                                if (heatFrac > 0) {
                                                    Box(
                                                        modifier = Modifier
                                                            .fillMaxWidth()
                                                            .weight(heatFrac)
                                                            .background(Color(0xFF1E90FF))
                                                    )
                                                }
                                                // Cig below (Red)
                                                if (cigFrac > 0) {
                                                    Box(
                                                        modifier = Modifier
                                                            .fillMaxWidth()
                                                            .weight(cigFrac)
                                                            .background(if (item.isToday) Color(0xFFFF3B30) else Color(0xFFD84315))
                                                    )
                                                }
                                            }
                                        } else {
                                            Box(
                                                modifier = Modifier
                                                    .width(13.dp)
                                                    .height(3.dp)
                                                    .clip(RoundedCornerShape(2.dp))
                                                    .background(Color(0xFF222222))
                                            )
                                        }
                                    }
                                    Spacer(Modifier.height(3.dp))
                                    Text(
                                        text = item.dayLabel,
                                        fontSize = 9.sp,
                                        fontWeight = if (item.isToday) FontWeight.Bold else FontWeight.Normal,
                                        color = if (item.isToday) Color(0xFFFF5555) else Color.Gray
                                    )
                                }
                            }
                        }
                    }
                }
            }

            // Summary Row: Avg & Base
            item {
                Spacer(Modifier.height(6.dp))
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 14.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("🔥", fontSize = 11.sp)
                        Spacer(Modifier.width(2.dp))
                        Text(
                            text = "Avg: $formattedAvg/d",
                            fontSize = 11.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = Color.White
                        )
                    }
                    Text(
                        text = "Base: $dailyGoal",
                        fontSize = 10.sp,
                        color = Color.Gray
                    )
                }
                Spacer(Modifier.height(10.dp))
            }
        }
    }
}
