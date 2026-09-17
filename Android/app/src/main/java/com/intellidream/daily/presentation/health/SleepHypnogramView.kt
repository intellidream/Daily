package com.intellidream.daily.presentation.health

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.SleepSession
import com.intellidream.daily.model.SleepStageRecord
import com.intellidream.daily.model.SleepStageType
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import kotlin.math.max
import kotlin.math.roundToInt

@Composable
fun SleepHypnogramView(
    session: SleepSession,
    modifier: Modifier = Modifier
) {
    var selectedStage by remember { mutableStateOf<SleepStageRecord?>(null) }
    val timeFormatter = remember { SimpleDateFormat("HH:mm", Locale.getDefault()) }

    val rowHeightDp = 28.dp
    val laneSpacingDp = 8.dp

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        // Selected stage inspection tooltip pill
        AnimatedVisibility(
            visible = selectedStage != null,
            enter = fadeIn(),
            exit = fadeOut()
        ) {
            selectedStage?.let { selected ->
                val stageColor = Color(android.graphics.Color.parseColor(selected.stageType.hexColor))
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.08f))
                        .padding(horizontal = 12.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .size(8.dp)
                            .clip(CircleShape)
                            .background(stageColor)
                    )
                    Text(
                        text = selected.stageType.rawValue,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                    Text(
                        text = "•",
                        fontSize = 12.sp,
                        color = ThemeColors.fgMutedDark
                    )
                    Text(
                        text = "${timeFormatter.format(Date(selected.startTime))} - ${timeFormatter.format(Date(selected.endTime))}",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Medium,
                        color = Color.White.copy(alpha = 0.85f)
                    )
                    Spacer(modifier = Modifier.weight(1f))
                    Text(
                        text = "${selected.durationMinutes.roundToInt()} min",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                        color = ThemeColors.accentCyan
                    )
                }
            }
        }

        // Hypnogram Canvas
        val totalSeconds = max(60.0, (session.endTime - session.startTime) / 1000.0)
        val orderedStages = listOf(
            SleepStageType.AWAKE,
            SleepStageType.REM,
            SleepStageType.LIGHT,
            SleepStageType.DEEP
        )

        Canvas(
            modifier = Modifier
                .fillMaxWidth()
                .height(150.dp)
                .pointerInput(session.stages) {
                    detectTapGestures { offset ->
                        val w = size.width
                        val h = size.height
                        val leftOffsetPx = 48.dp.toPx()
                        val chartWidth = w - leftOffsetPx - 4.dp.toPx()
                        val rowH = 28.dp.toPx()
                        val laneSp = 8.dp.toPx()

                        if (offset.x >= leftOffsetPx) {
                            val elapsedSec = ((offset.x - leftOffsetPx) / chartWidth) * totalSeconds
                            val targetTime = session.startTime + (elapsedSec * 1000).toLong()

                            val hit = session.stages.firstOrNull { stage ->
                                targetTime in stage.startTime..stage.endTime
                            }

                            selectedStage = if (selectedStage?.id == hit?.id) null else hit
                        }
                    }
                }
        ) {
            val w = size.width
            val h = size.height
            val leftOffsetPx = 48.dp.toPx()
            val chartWidth = w - leftOffsetPx - 4.dp.toPx()
            val rowH = 28.dp.toPx()
            val laneSp = 8.dp.toPx()

            // 1. Draw horizontal guidelines for the 4 lanes
            for (idx in orderedStages.indices) {
                val laneY = idx * (rowH + laneSp) + (rowH / 2f)
                drawLine(
                    color = Color.White.copy(alpha = 0.08f),
                    start = Offset(leftOffsetPx, laneY),
                    end = Offset(w, laneY),
                    strokeWidth = 1.dp.toPx()
                )
            }

            // 2. Draw vertical hourly grid lines
            val cal = Calendar.getInstance().apply { timeInMillis = session.startTime }
            cal.set(Calendar.MINUTE, 0)
            cal.set(Calendar.SECOND, 0)
            if (cal.timeInMillis < session.startTime) {
                cal.add(Calendar.HOUR_OF_DAY, 1)
            }
            while (cal.timeInMillis <= session.endTime) {
                val elapsedSec = (cal.timeInMillis - session.startTime) / 1000.0
                val tickX = leftOffsetPx + ((elapsedSec / totalSeconds).toFloat() * chartWidth)
                drawLine(
                    color = Color.White.copy(alpha = 0.06f),
                    start = Offset(tickX, 0f),
                    end = Offset(tickX, 4 * (rowH + laneSp)),
                    strokeWidth = 1.dp.toPx()
                )
                cal.add(Calendar.HOUR_OF_DAY, 1)
            }

            // 3. Draw Stage Blocks
            for (stage in session.stages) {
                val elapsed = max(0.0, (stage.startTime - session.startTime) / 1000.0)
                val stageDur = max(30.0, stage.durationSeconds)
                val left = leftOffsetPx + ((elapsed / totalSeconds).toFloat() * chartWidth)
                val blockWidth = max(3f, (stageDur / totalSeconds).toFloat() * chartWidth)

                val laneIndex = when (stage.stageType) {
                    SleepStageType.AWAKE -> 0
                    SleepStageType.REM -> 1
                    SleepStageType.LIGHT, SleepStageType.UNKNOWN -> 2
                    SleepStageType.DEEP -> 3
                }
                val topY = laneIndex * (rowH + laneSp) + 2.dp.toPx()
                val blockHeight = rowH - 4.dp.toPx()

                val isSelected = selectedStage?.id == stage.id
                val stageColor = Color(android.graphics.Color.parseColor(stage.stageType.hexColor))

                // Block fill
                drawRoundRect(
                    color = stageColor.copy(alpha = if (isSelected) 1.0f else 0.85f),
                    topLeft = Offset(left, topY),
                    size = Size(blockWidth, blockHeight),
                    cornerRadius = CornerRadius(4.dp.toPx(), 4.dp.toPx())
                )

                // Block border
                drawRoundRect(
                    color = if (isSelected) Color.White else Color.White.copy(alpha = 0.2f),
                    topLeft = Offset(left, topY),
                    size = Size(blockWidth, blockHeight),
                    cornerRadius = CornerRadius(4.dp.toPx(), 4.dp.toPx()),
                    style = Stroke(width = if (isSelected) 1.5.dp.toPx() else 0.5.dp.toPx())
                )
            }
        }

        // X-Axis Time Ticks
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = 48.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = session.bedtimeFormatted,
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                color = ThemeColors.fgMutedDark
            )

            Text(
                text = "← ${session.totalAsleepFormatted} asleep →",
                fontSize = 11.sp,
                fontWeight = FontWeight.Medium,
                color = Color.White.copy(alpha = 0.6f)
            )

            Text(
                text = session.wakeTimeFormatted,
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                color = ThemeColors.fgMutedDark
            )
        }
    }
}
