package com.intellidream.daily.wearos.presentation.bubbles

import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.Text
import com.google.android.horologist.annotations.ExperimentalHorologistApi
import com.google.android.horologist.compose.layout.ScalingLazyColumn
import com.google.android.horologist.compose.layout.ScalingLazyColumnState
import com.google.android.horologist.compose.layout.ScreenScaffold
import com.google.android.horologist.compose.layout.rememberResponsiveColumnState
import com.intellidream.daily.wearos.data.WatchSessionManager
import com.intellidream.daily.wearos.domain.model.HabitLog
import com.intellidream.daily.wearos.domain.model.WaterDayBucket
import com.intellidream.daily.wearos.domain.util.HabitDateParser
import com.intellidream.daily.wearos.presentation.components.TemporalNavHeader
import com.intellidream.daily.wearos.presentation.theme.DailyWearColors
import com.intellidream.daily.wearos.util.SoundAndHapticFeedback
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.time.Instant
import java.util.Calendar
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalHorologistApi::class)
@Composable
fun Bubbles7DaysScreen(
    sessionManager: WatchSessionManager,
    isPageActive: Boolean = true
) {
    val context = LocalContext.current
    val view = LocalView.current
    var weekOffset by remember { mutableIntStateOf(0) }
    val dailyGoal by sessionManager.bubblesGoal.collectAsState()
    val initialCached = sessionManager.getBubblesWeek(0)
    var buckets by remember { mutableStateOf<List<WaterDayBucket>>(initialCached ?: emptyList()) }
    var isLoading by remember { mutableStateOf(initialCached == null) }

    val scope = rememberCoroutineScope()
    // RotaryMode.Scroll provides silky-smooth 60/120Hz scrolling with crown haptic ticks
    val columnState = rememberResponsiveColumnState(
        rotaryMode = ScalingLazyColumnState.RotaryMode.Scroll
    )
    val refreshTrigger by sessionManager.dataRefreshTrigger.collectAsState()

    val localDateFmt = remember { SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()) }
    val dayLabelFmt = remember { SimpleDateFormat("EEE", Locale.getDefault()) }
    val weekTitleFmt = remember { SimpleDateFormat("d MMM", Locale.getDefault()) }

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

    LaunchedEffect(weekOffset) {
        val cached = sessionManager.getBubblesWeek(weekOffset)
        if (cached != null) {
            buckets = cached
            isLoading = false
        }
    }

    val fetchWeekData: () -> Unit = {
        if (isPageActive) {
            scope.launch(Dispatchers.IO) {
                if (sessionManager.getBubblesWeek(weekOffset) == null) {
                    withContext(Dispatchers.Main) { isLoading = true }
                }
                val (monCal, nextMonCal) = getWeekWindow(weekOffset)
            val startStr = Instant.ofEpochMilli(monCal.timeInMillis).toString()
            val endStr = Instant.ofEpochMilli(nextMonCal.timeInMillis).toString()
            val todayStr = localDateFmt.format(Date())

            val tempBuckets = mutableListOf<WaterDayBucket>()
            for (i in 0 until 7) {
                val dCal = monCal.clone() as Calendar
                dCal.add(Calendar.DAY_OF_YEAR, i)
                val dStr = localDateFmt.format(dCal.time)
                val lbl = dayLabelFmt.format(dCal.time).take(1)
                tempBuckets.add(WaterDayBucket(dStr, lbl, dStr == todayStr))
            }

            try {
                val logs = sessionManager.supabaseClient.postgrest["habits_logs"]
                    .select {
                        filter {
                            eq("habit_type", "water")
                            eq("is_deleted", false)
                            and {
                                gte("logged_at", startStr)
                                lt("logged_at", endStr)
                            }
                        }
                    }.decodeList<HabitLog>()

                for (log in logs) {
                    try {
                        val localDate = HabitDateParser.parseToLocalDate(log.logged_at)
                        if (localDate != null) {
                            val logDateStr = localDate.toString()
                            val bucket = tempBuckets.find { it.dateStr == logDateStr }
                            if (bucket != null) {
                                val isCoffee = log.metadata?.contains("Coffee", ignoreCase = true) == true
                                if (isCoffee) {
                                    bucket.coffee += log.value
                                } else {
                                    bucket.water += log.value
                                }
                            }
                        }
                    } catch (e: Exception) {
                        android.util.Log.w("Bubbles7Days", "Failed to process log: ${e.message}")
                    }
                }

                sessionManager.setBubblesWeek(weekOffset, tempBuckets)
                withContext(Dispatchers.Main) {
                    buckets = tempBuckets
                    isLoading = false
                }
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                android.util.Log.e("Bubbles7Days", "Failed to fetch week logs: ${e.message}", e)
                withContext(Dispatchers.Main) {
                    if (buckets.isEmpty()) {
                        buckets = tempBuckets
                    }
                    isLoading = false
                }
            }
        }
    }
}

    LaunchedEffect(isPageActive, weekOffset, refreshTrigger) {
        if (isPageActive) {
            fetchWeekData()
        }
    }

    val weeklyAverage = remember(buckets, weekOffset) {
        if (buckets.isEmpty()) 0
        else {
            val sum = buckets.sumOf { it.total }
            if (weekOffset == 0) {
                val cal = Calendar.getInstance()
                val dow = cal.get(Calendar.DAY_OF_WEEK)
                val elapsed = if (dow == Calendar.SUNDAY) 7 else maxOf(1, dow - Calendar.MONDAY + 1)
                (sum / elapsed).toInt()
            } else {
                (sum / 7).toInt()
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
                        imageVector = Icons.Filled.WaterDrop,
                        contentDescription = null,
                        tint = DailyWearColors.WaterCyan,
                        modifier = Modifier.size(16.dp)
                    )
                    Spacer(Modifier.width(4.dp))
                    Text(
                        text = "Bubbles 7 Days",
                        fontWeight = FontWeight.Bold,
                        fontSize = 16.sp,
                        color = Color.White
                    )
                }
            }

            // Temporal Navigation Header Pill
            item {
                TemporalNavHeader(
                    title = weekTitle,
                    canGoForward = weekOffset < 0,
                    accentColor = DailyWearColors.WaterCyan,
                    onPrevious = {
                        SoundAndHapticFeedback.playClick(context, view)
                        weekOffset -= 1
                    },
                    onNext = {
                        if (weekOffset < 0) {
                            SoundAndHapticFeedback.playClick(context, view)
                            weekOffset += 1
                        }
                    },
                    modifier = Modifier.padding(vertical = 4.dp)
                )
            }

            // 7 Days Bar Chart
            item {
                Spacer(Modifier.height(8.dp))
                if (isLoading && buckets.isEmpty()) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth(0.92f)
                            .height(96.dp)
                            .clip(RoundedCornerShape(16.dp))
                            .background(Color(0xFF141820)),
                        contentAlignment = Alignment.Center
                    ) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(24.dp),
                            strokeWidth = 2.dp,
                            indicatorColor = DailyWearColors.WaterCyan
                        )
                    }
                } else {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth(0.92f)
                            .height(104.dp)
                            .clip(RoundedCornerShape(16.dp))
                            .background(Color(0xFF141820))
                            .border(1.dp, Color.White.copy(alpha = 0.05f), RoundedCornerShape(16.dp))
                            .padding(horizontal = 10.dp, vertical = 8.dp)
                    ) {
                        val maxVal = maxOf(dailyGoal.toDouble(), buckets.maxOfOrNull { it.total } ?: 1.0)

                        // Goal Line (Dashed cyan)
                        val goalY = 1f - (dailyGoal / maxVal).toFloat().coerceIn(0f, 1f)
                        androidx.compose.foundation.Canvas(modifier = Modifier.fillMaxSize()) {
                            val lineY = size.height * 0.80f * goalY
                            drawLine(
                                color = DailyWearColors.WaterCyan.copy(alpha = 0.4f),
                                start = Offset(0f, lineY),
                                end = Offset(size.width, lineY),
                                strokeWidth = 1.5f,
                                pathEffect = PathEffect.dashPathEffect(floatArrayOf(5f, 5f), 0f)
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
                                val waterFrac = if (item.total > 0) (item.water / item.total).toFloat() else 1f
                                val coffeeFrac = if (item.total > 0) (item.coffee / item.total).toFloat() else 0f

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
                                                    .width(14.dp)
                                                    .fillMaxHeight(totalFrac)
                                                    .clip(RoundedCornerShape(4.dp))
                                            ) {
                                                // Stacked Coffee on top (Orange)
                                                if (coffeeFrac > 0) {
                                                    Box(
                                                        modifier = Modifier
                                                            .fillMaxWidth()
                                                            .weight(coffeeFrac)
                                                            .background(DailyWearColors.CoffeeOrange)
                                                    )
                                                }
                                                // Water below (Cyan)
                                                if (waterFrac > 0) {
                                                    Box(
                                                        modifier = Modifier
                                                            .fillMaxWidth()
                                                            .weight(waterFrac)
                                                            .background(if (item.isToday) DailyWearColors.WaterCyan else DailyWearColors.WaterCyan.copy(alpha = 0.65f))
                                                    )
                                                }
                                            }
                                        } else {
                                            // Empty track dot/bar
                                            Box(
                                                modifier = Modifier
                                                    .width(14.dp)
                                                    .height(4.dp)
                                                    .clip(RoundedCornerShape(2.dp))
                                                    .background(Color.White.copy(alpha = 0.08f))
                                            )
                                        }
                                    }
                                    Spacer(Modifier.height(4.dp))
                                    Text(
                                        text = item.dayLabel,
                                        fontSize = 10.sp,
                                        fontWeight = if (item.isToday) FontWeight.Bold else FontWeight.Medium,
                                        color = if (item.isToday) DailyWearColors.WaterCyan else Color.White.copy(alpha = 0.5f)
                                    )
                                }
                            }
                        }
                    }
                }
            }

            // Summary Card: Daily Average & Goal
            item {
                Spacer(Modifier.height(8.dp))
                Box(
                    modifier = Modifier
                        .fillMaxWidth(0.92f)
                        .clip(RoundedCornerShape(16.dp))
                        .background(Color(0xFF141820))
                        .border(1.dp, Color.White.copy(alpha = 0.05f), RoundedCornerShape(16.dp))
                        .padding(horizontal = 14.dp, vertical = 10.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column {
                            Text(
                                text = "DAILY AVERAGE",
                                fontSize = 9.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color.White.copy(alpha = 0.45f)
                            )
                            Spacer(Modifier.height(2.dp))
                            Text(
                                text = "$weeklyAverage ml",
                                fontSize = 14.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color.White
                            )
                        }

                        Column(horizontalAlignment = Alignment.End) {
                            Text(
                                text = "TARGET",
                                fontSize = 9.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color.White.copy(alpha = 0.45f)
                            )
                            Spacer(Modifier.height(2.dp))
                            Text(
                                text = "$dailyGoal ml",
                                fontSize = 14.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = DailyWearColors.WaterCyan
                            )
                        }
                    }
                }
                Spacer(Modifier.height(16.dp))
            }
        }
    }
}
