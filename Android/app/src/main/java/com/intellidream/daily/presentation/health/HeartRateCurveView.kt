package com.intellidream.daily.presentation.health

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material3.Icon
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.HeartRateZone
import com.intellidream.daily.model.IntradayHeartRatePoint
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

@Composable
fun HeartRateCurveView(
    averageBpm: Double,
    restingBpm: Double,
    minBpm: Double,
    maxBpm: Double,
    intradayHeartRate: List<IntradayHeartRatePoint>,
    heartRateZones: Map<HeartRateZone, Int>,
    modifier: Modifier = Modifier
) {
    var selectedPoint by remember { mutableStateOf<IntradayHeartRatePoint?>(null) }
    val timeFormatter = remember { SimpleDateFormat("HH:mm", Locale.getDefault()) }

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // 1. Hero Heart Rate Card
        GlassCard(
            modifier = Modifier.fillMaxWidth(),
            cornerRadius = 20.dp,
            padding = 18.dp
        ) {
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                // Header
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(
                            text = "HEART RATE TODAY",
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold,
                            color = ThemeColors.accentCyan
                        )

                        Row(
                            verticalAlignment = Alignment.Bottom,
                            horizontalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            Text(
                                text = "${averageBpm.roundToInt()}",
                                fontSize = 34.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color.White
                            )
                            Text(
                                text = "BPM AVG",
                                fontSize = 13.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = ThemeColors.fgMutedDark,
                                modifier = Modifier.padding(bottom = 4.dp)
                            )
                        }
                    }

                    // Resting HR Pill
                    Column(
                        horizontalAlignment = Alignment.End,
                        verticalArrangement = Arrangement.spacedBy(2.dp)
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            Icon(
                                imageVector = Icons.Rounded.Favorite,
                                contentDescription = null,
                                tint = ThemeColors.accentPink,
                                modifier = Modifier.size(12.dp)
                            )
                            Text(
                                text = "Resting HR",
                                fontSize = 11.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = ThemeColors.fgMutedDark
                            )
                        }
                        Text(
                            text = "${restingBpm.roundToInt()} bpm",
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White
                        )
                    }
                }

                // Selected Point Callout
                if (selectedPoint != null) {
                    val pt = selectedPoint!!
                    val zoneColor = Color(android.graphics.Color.parseColor(pt.zone.hexColor))
                    Row(
                        modifier = Modifier
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
                                .background(zoneColor)
                        )
                        Text(
                            text = "${pt.bpm.roundToInt()} BPM",
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White
                        )
                        Text(
                            text = "at ${timeFormatter.format(Date(pt.timestamp))}",
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Medium,
                            color = ThemeColors.fgMutedDark
                        )
                        Spacer(modifier = Modifier.weight(1f))
                        Text(
                            text = pt.zone.displayName,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold,
                            color = zoneColor
                        )
                    }
                }

                // Intraday Heart Rate Curve Canvas
                if (intradayHeartRate.isNotEmpty()) {
                    val yMin = max(35.0, minBpm - 5.0)
                    val yMax = min(220.0, maxBpm + 10.0)

                    Canvas(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(140.dp)
                            .pointerInput(intradayHeartRate) {
                                detectTapGestures { offset ->
                                    val canvasWidth = size.width
                                    val tMin = intradayHeartRate.first().timestamp
                                    val tMax = intradayHeartRate.last().timestamp
                                    if (tMax > tMin) {
                                        val frac = (offset.x / canvasWidth).coerceIn(0f, 1f)
                                        val targetTime = tMin + (frac * (tMax - tMin)).toLong()
                                        selectedPoint = intradayHeartRate.minByOrNull {
                                            kotlin.math.abs(it.timestamp - targetTime)
                                        }
                                    }
                                }
                            }
                    ) {
                        val w = size.width
                        val h = size.height
                        val tMin = intradayHeartRate.first().timestamp
                        val tMax = max(tMin + 3600000L, intradayHeartRate.last().timestamp)
                        val ySpan = max(10.0, yMax - yMin)

                        // Grid lines
                        for (gridSteps in listOf(0.25f, 0.5f, 0.75f)) {
                            val lineY = h * gridSteps
                            drawLine(
                                color = Color.White.copy(alpha = 0.08f),
                                start = Offset(0f, lineY),
                                end = Offset(w, lineY),
                                strokeWidth = 1.dp.toPx()
                            )
                        }

                        // Build smooth path
                        val points = intradayHeartRate.map { pt ->
                            val x = ((pt.timestamp - tMin).toFloat() / (tMax - tMin).toFloat()) * w
                            val y = h - (((pt.bpm - yMin) / ySpan).toFloat() * h)
                            Offset(x.coerceIn(0f, w), y.coerceIn(0f, h))
                        }

                        if (points.isNotEmpty()) {
                            val linePath = Path()
                            val fillPath = Path()

                            linePath.moveTo(points.first().x, points.first().y)
                            fillPath.moveTo(points.first().x, h)
                            fillPath.lineTo(points.first().x, points.first().y)

                            for (i in 0 until points.size - 1) {
                                val p0 = points[i]
                                val p1 = points[i + 1]
                                val cx = (p0.x + p1.x) / 2f
                                linePath.cubicTo(cx, p0.y, cx, p1.y, p1.x, p1.y)
                                fillPath.cubicTo(cx, p0.y, cx, p1.y, p1.x, p1.y)
                            }

                            fillPath.lineTo(points.last().x, h)
                            fillPath.close()

                            // Draw area fill
                            drawPath(
                                path = fillPath,
                                brush = Brush.verticalGradient(
                                    colors = listOf(
                                        ThemeColors.accentCyan.copy(alpha = 0.35f),
                                        ThemeColors.accentCyan.copy(alpha = 0.0f)
                                    )
                                )
                            )

                            // Draw curve stroke
                            drawPath(
                                path = linePath,
                                color = ThemeColors.accentCyan,
                                style = Stroke(
                                    width = 2.dp.toPx(),
                                    cap = StrokeCap.Round,
                                    join = StrokeJoin.Round
                                )
                            )

                            // Draw selected point indicator
                            selectedPoint?.let { sp ->
                                val selX = ((sp.timestamp - tMin).toFloat() / (tMax - tMin).toFloat()) * w
                                val selY = h - (((sp.bpm - yMin) / ySpan).toFloat() * h)
                                drawCircle(
                                    color = Color.White,
                                    radius = 5.dp.toPx(),
                                    center = Offset(selX, selY)
                                )
                                drawCircle(
                                    color = Color(android.graphics.Color.parseColor(sp.zone.hexColor)),
                                    radius = 3.dp.toPx(),
                                    center = Offset(selX, selY)
                                )
                            }
                        }
                    }
                } else {
                    Text(
                        text = "No intraday heart rate telemetry available for this day.",
                        fontSize = 12.sp,
                        color = ThemeColors.fgMutedDark,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 24.dp),
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center
                    )
                }

                // Range Callouts
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = "Min: ${minBpm.roundToInt()} bpm",
                        fontSize = 11.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = Color(android.graphics.Color.parseColor(HeartRateZone.RESTING.hexColor))
                    )
                    Text(
                        text = "Max: ${maxBpm.roundToInt()} bpm",
                        fontSize = 11.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = Color(android.graphics.Color.parseColor(HeartRateZone.PEAK.hexColor))
                    )
                }
            }
        }

        // 2. Heart Rate Intensity Zones Card
        GlassCard(
            modifier = Modifier.fillMaxWidth(),
            cornerRadius = 18.dp,
            padding = 16.dp
        ) {
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Text(
                    text = "HEART RATE ZONES",
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    color = ThemeColors.accentCyan
                )

                // Multi-Segment Zone Bar
                val totalZoneCount = max(1, heartRateZones.values.sum())
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(12.dp)
                        .clip(RoundedCornerShape(3.dp))
                        .background(Color.White.copy(alpha = 0.08f))
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(2.dp)
                    ) {
                        listOf(HeartRateZone.RESTING, HeartRateZone.FAT_BURN, HeartRateZone.CARDIO, HeartRateZone.PEAK).forEach { z ->
                            val count = heartRateZones[z] ?: 0
                            if (count > 0) {
                                val frac = count.toFloat() / totalZoneCount.toFloat()
                                Box(
                                    modifier = Modifier
                                        .weight(frac)
                                        .height(12.dp)
                                        .clip(RoundedCornerShape(3.dp))
                                        .background(Color(android.graphics.Color.parseColor(z.hexColor)))
                                )
                            }
                        }
                    }
                }

                // Zone Rows
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    listOf(HeartRateZone.PEAK, HeartRateZone.CARDIO, HeartRateZone.FAT_BURN, HeartRateZone.RESTING).forEach { zone ->
                        val count = heartRateZones[zone] ?: 0
                        val pct = ((count.toDouble() / totalZoneCount.toDouble()) * 100).roundToInt()
                        val zoneColor = Color(android.graphics.Color.parseColor(zone.hexColor))

                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                Box(
                                    modifier = Modifier
                                        .size(8.dp)
                                        .clip(CircleShape)
                                        .background(zoneColor)
                                )
                                Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                                    Text(
                                        text = zone.displayName,
                                        fontSize = 12.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = Color.White
                                    )
                                    Text(
                                        text = zone.bpmRangeText,
                                        fontSize = 10.sp,
                                        fontWeight = FontWeight.Medium,
                                        color = ThemeColors.fgMutedDark
                                    )
                                }
                            }

                            Text(
                                text = "$pct%",
                                fontSize = 13.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color.White
                            )
                        }
                    }
                }
            }
        }
    }
}
