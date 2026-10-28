package com.intellidream.daily.wearos.presentation.smokes

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
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.ButtonDefaults
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.Text
import com.intellidream.daily.wearos.data.WatchSessionManager
import com.intellidream.daily.wearos.domain.model.SmokeDayBucket
import com.intellidream.daily.wearos.presentation.theme.DailyWearColors
import com.intellidream.daily.wearos.util.SoundAndHapticFeedback
import kotlinx.coroutines.launch
import java.util.Locale

@Composable
fun Smokes7DaysInlineCard(
    sessionManager: WatchSessionManager,
    isPageActive: Boolean = true,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val view = LocalView.current
    var weekOffset by remember { mutableIntStateOf(0) }
    val dailyGoal by sessionManager.smokesGoal.collectAsState()
    val refreshTrigger by sessionManager.dataRefreshTrigger.collectAsState()
    val scope = rememberCoroutineScope()

    val initialCached = sessionManager.getSmokesWeek(0)
    var buckets by remember { mutableStateOf<List<SmokeDayBucket>>(initialCached ?: emptyList()) }
    var isLoading by remember { mutableStateOf(initialCached == null) }

    fun loadWeek(offset: Int) {
        val cached = sessionManager.getSmokesWeek(offset)
        if (cached != null) {
            buckets = cached
            isLoading = false
        } else {
            isLoading = true
            if (isPageActive) {
                scope.launch {
                    sessionManager.fetchWeekData("smokes", offset)
                    val reloaded = sessionManager.getSmokesWeek(offset)
                    if (reloaded != null) {
                        buckets = reloaded
                    }
                    isLoading = false
                }
            }
        }
    }

    LaunchedEffect(weekOffset, refreshTrigger, isPageActive) {
        loadWeek(weekOffset)
    }

    val totalWeek = remember(buckets) { buckets.sumOf { it.total } }
    val daysWithData = remember(buckets) { buckets.count { it.total > 0 } }
    val avgDaily = remember(totalWeek, daysWithData) {
        if (daysWithData > 0) totalWeek.toDouble() / daysWithData else 0.0
    }
    val moneySpentToday = remember(refreshTrigger) { sessionManager.getMoneySpentTodayLei() }
    val moneySavedToday = remember(refreshTrigger) { sessionManager.getMoneySavedTodayLei() }

    val weekTitle = remember(weekOffset) {
        when (weekOffset) {
            0 -> "This Week"
            -1 -> "Last Week"
            else -> "$weekOffset wks"
        }
    }

    Column(
        modifier = modifier
            .fillMaxWidth(0.94f)
            .clip(RoundedCornerShape(18.dp))
            .background(Color(0xFF141820))
            .border(1.dp, Color.White.copy(alpha = 0.06f), RoundedCornerShape(18.dp))
            .padding(horizontal = 12.dp, vertical = 10.dp)
    ) {
        // Card Header
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column {
                Text(
                    text = "7-DAY TREND",
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    color = DailyWearColors.SmokeRed,
                    letterSpacing = 0.5.sp
                )
                Text(
                    text = weekTitle,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = Color.White
                )
            }

            Row(verticalAlignment = Alignment.CenterVertically) {
                Button(
                    onClick = {
                        SoundAndHapticFeedback.playClick(context, view)
                        weekOffset -= 1
                    },
                    modifier = Modifier.size(24.dp),
                    colors = ButtonDefaults.buttonColors(backgroundColor = Color(0xFF1E2430))
                ) {
                    Icon(
                        imageVector = Icons.Filled.ChevronLeft,
                        contentDescription = "Previous week",
                        tint = Color.White,
                        modifier = Modifier.size(14.dp)
                    )
                }

                Spacer(Modifier.width(4.dp))

                Button(
                    onClick = {
                        if (weekOffset < 0) {
                            SoundAndHapticFeedback.playClick(context, view)
                            weekOffset += 1
                        }
                    },
                    enabled = weekOffset < 0,
                    modifier = Modifier.size(24.dp),
                    colors = ButtonDefaults.buttonColors(
                        backgroundColor = if (weekOffset < 0) Color(0xFF1E2430) else Color.Transparent,
                        disabledBackgroundColor = Color.Transparent
                    )
                ) {
                    Icon(
                        imageVector = Icons.Filled.ChevronRight,
                        contentDescription = "Next week",
                        tint = if (weekOffset < 0) Color.White else Color.White.copy(alpha = 0.2f),
                        modifier = Modifier.size(14.dp)
                    )
                }
            }
        }

        Spacer(Modifier.height(8.dp))

        // Chart Area
        if (isLoading && buckets.isEmpty()) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(84.dp),
                contentAlignment = Alignment.Center
            ) {
                CircularProgressIndicator(
                    modifier = Modifier.size(20.dp),
                    strokeWidth = 2.dp,
                    indicatorColor = DailyWearColors.SmokeRed
                )
            }
        } else {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(84.dp)
            ) {
                val maxVal = maxOf(dailyGoal.toDouble(), buckets.maxOfOrNull { it.total.toDouble() } ?: 1.0)
                val goalY = 1f - (dailyGoal / maxVal).toFloat().coerceIn(0f, 1f)

                // Baseline Line (Dashed red)
                androidx.compose.foundation.Canvas(modifier = Modifier.fillMaxSize()) {
                    val lineY = size.height * 0.78f * goalY
                    drawLine(
                        color = DailyWearColors.SmokeRed.copy(alpha = 0.45f),
                        start = Offset(0f, lineY),
                        end = Offset(size.width, lineY),
                        strokeWidth = 1.2f,
                        pathEffect = PathEffect.dashPathEffect(floatArrayOf(4f, 4f), 0f)
                    )
                }

                // 7 Vertical Bars
                Row(
                    modifier = Modifier.fillMaxSize(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.Bottom
                ) {
                    buckets.forEach { item ->
                        val totalFrac = (item.total.toFloat() / maxVal.toFloat()).coerceIn(0f, 1f)
                        val cigFrac = if (item.total > 0) (item.cig.toFloat() / item.total.toFloat()) else 1f
                        val heatFrac = if (item.total > 0) (item.heat.toFloat() / item.total.toFloat()) else 0f

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
                                            .width(10.dp)
                                            .fillMaxHeight(totalFrac)
                                            .clip(RoundedCornerShape(3.dp))
                                    ) {
                                        if (heatFrac > 0) {
                                            Box(
                                                modifier = Modifier
                                                    .fillMaxWidth()
                                                    .weight(heatFrac)
                                                    .background(DailyWearColors.HeatIndigo)
                                            )
                                        }
                                        if (cigFrac > 0) {
                                            Box(
                                                modifier = Modifier
                                                    .fillMaxWidth()
                                                    .weight(cigFrac)
                                                    .background(
                                                        if (item.isToday) DailyWearColors.SmokeRed
                                                        else DailyWearColors.SmokeRed.copy(alpha = 0.65f)
                                                    )
                                            )
                                        }
                                    }
                                } else {
                                    Box(
                                        modifier = Modifier
                                            .width(10.dp)
                                            .height(3.dp)
                                            .clip(RoundedCornerShape(1.5.dp))
                                            .background(Color.White.copy(alpha = 0.08f))
                                    )
                                }
                            }

                            Spacer(Modifier.height(3.dp))

                            Text(
                                text = item.dayLabel.take(2),
                                fontSize = 9.sp,
                                fontWeight = if (item.isToday) FontWeight.Bold else FontWeight.Normal,
                                color = if (item.isToday) DailyWearColors.SmokeRed else Color.White.copy(alpha = 0.45f)
                            )
                        }
                    }
                }
            }
        }

        Spacer(Modifier.height(8.dp))

        // Financial & Pacing Summary Row
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(10.dp))
                .background(Color.White.copy(alpha = 0.04f))
                .padding(horizontal = 8.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column {
                Text(
                    text = "AVG DAILY",
                    fontSize = 8.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White.copy(alpha = 0.45f)
                )
                Text(
                    text = String.format(Locale.getDefault(), "%.1f /d", avgDaily),
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White
                )
            }

            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    text = "SPENT TODAY",
                    fontSize = 8.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White.copy(alpha = 0.45f)
                )
                Text(
                    text = String.format(Locale.getDefault(), "%.1f L", moneySpentToday),
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    color = DailyWearColors.SmokeRed
                )
            }

            Column(horizontalAlignment = Alignment.End) {
                Text(
                    text = "SAVED TODAY",
                    fontSize = 8.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White.copy(alpha = 0.45f)
                )
                Text(
                    text = String.format(Locale.getDefault(), "%.1f L", moneySavedToday),
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    color = DailyWearColors.SmokeGreen
                )
            }
        }
    }
}
