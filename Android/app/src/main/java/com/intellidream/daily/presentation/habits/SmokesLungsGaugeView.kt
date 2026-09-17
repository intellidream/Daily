package com.intellidream.daily.presentation.habits

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Fill
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.HabitDrinkBreakdown
import com.intellidream.daily.model.HabitType
import kotlinx.coroutines.delay
import kotlin.math.ceil

data class CravingBadge(
    val text: String,
    val color: Color,
    val icon: ImageVector
)

@Composable
fun SmokesLungsGaugeView(
    countToday: Int,
    baselineCount: Int,
    lastSmokeDate: Long?,
    lastSmokeType: String? = null,
    isToday: Boolean = true,
    smokeBreakdown: List<HabitDrinkBreakdown> = emptyList(),
    modifier: Modifier = Modifier
) {
    val safeBaseline = baselineCount.coerceAtLeast(1)
    val progressRatio = (countToday.toFloat() / safeBaseline.toFloat()).coerceIn(0f, 1.5f)
    val isOverLimit = countToday > safeBaseline

    // Ticker to re-evaluate active smoking and craving-free minutes every 10s
    var currentTime by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(10000L)
            currentTime = System.currentTimeMillis()
        }
    }

    // Status colors
    val statusColor = when {
        countToday == 0 -> Color(0xFF00FFB2)
        progressRatio <= 0.6f -> ThemeColors.accentCyan
        progressRatio <= 1.0f -> Color(0xFFFFB800)
        else -> Color(0xFFFF3B30)
    }

    // Dynamic biological tissue color interpolation
    val targetLungColor = when {
        countToday == 0 -> Color(0xFFFF6B8B) // Radiant healthy lung pink
        progressRatio <= 0.35f -> {
            val t = progressRatio / 0.35f
            Color(
                red = 1f - t * (1f - 0.85f),
                green = (107f + t * (125f - 107f)) / 255f,
                blue = (139f + t * (142f - 139f)) / 255f
            )
        }
        progressRatio <= 0.75f -> {
            val t = (progressRatio - 0.35f) / 0.40f
            Color(
                red = 0.85f - t * (0.85f - 0.47f),
                green = (125f - t * (125f - 0.44f)) / 255f,
                blue = (142f - t * (142f - 0.42f)) / 255f
            )
        }
        else -> {
            val t = ((progressRatio - 0.75f) / 0.75f).coerceIn(0f, 1f)
            Color(
                red = 0.47f - t * (0.47f - 0.15f),
                green = 0.44f - t * (0.44f - 0.15f),
                blue = 0.42f - t * (0.42f - 0.16f)
            )
        }
    }

    val animatedLungColor by animateColorAsState(
        targetValue = targetLungColor,
        animationSpec = tween(600),
        label = "lungColor"
    )

    // Gentle breathing pulsation for healthy lungs
    val infiniteTransition = rememberInfiniteTransition(label = "pulse")
    val pulseScale by infiniteTransition.animateFloat(
        initialValue = 1.0f,
        targetValue = 1.04f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 3000),
            repeatMode = RepeatMode.Reverse
        ),
        label = "pulseScale"
    )

    // Compute Craving Badge Information
    val badge = remember(isToday, countToday, progressRatio, lastSmokeDate, lastSmokeType, currentTime) {
        if (!isToday) {
            when {
                countToday == 0 -> CravingBadge("Smoke-Free Day 🌟", Color(0xFF00FFB2), Icons.Rounded.CheckCircle)
                progressRatio <= 0.6f -> CravingBadge("Well Under Limit 🎯", Color(0xFF00E5FF), Icons.Rounded.CheckCircle)
                progressRatio <= 1.0f -> CravingBadge("Near Daily Limit ⚠️", Color(0xFFFFB800), Icons.Rounded.Warning)
                else -> CravingBadge("Over Daily Limit ✕", Color(0xFFFF3B30), Icons.Rounded.Warning)
            }
        } else if (lastSmokeDate == null) {
            CravingBadge("Smoke-Free Today!", Color(0xFF00FFB2), Icons.Rounded.CheckCircle)
        } else {
            val elapsed = currentTime - lastSmokeDate
            val duration = estimatedSmokingDurationMillis(lastSmokeType)
            if (elapsed < duration) {
                val remainingSec = (duration - elapsed) / 1000L
                val remainingMin = maxOf(1, ceil(remainingSec / 60.0).toInt())
                val text = if (remainingSec <= 45) "Finishing smoke..." else "Smoking now (~${remainingMin}m left)"
                CravingBadge(text, Color(0xFFF59E0B), Icons.Rounded.LocalFireDepartment)
            } else {
                val cleanInterval = elapsed - duration
                val cleanSec = cleanInterval / 1000L
                val text = when {
                    cleanSec < 60 -> "Just finished"
                    cleanSec < 3600 -> "${cleanSec / 60}m craving-free"
                    else -> "${cleanSec / 3600}h ${(cleanSec % 3600) / 60}m clean"
                }
                CravingBadge(text, Color(0xFF00FFB2), Icons.Rounded.LocalFireDepartment)
            }
        }
    }

    Box(
        modifier = modifier
            .size(240.dp)
            .clip(CircleShape)
            .background(Color(0xFF080F1E).copy(alpha = 0.85f))
            .border(
                width = 2.dp,
                brush = Brush.sweepGradient(
                    listOf(
                        statusColor.copy(alpha = 0.7f),
                        statusColor.copy(alpha = 0.2f),
                        Color.White.copy(alpha = 0.15f),
                        statusColor.copy(alpha = 0.7f)
                    )
                ),
                shape = CircleShape
            ),
        contentAlignment = Alignment.Center
    ) {
        // Outer Arc & Anatomical Lungs Silhouette Canvas
        Canvas(modifier = Modifier.fillMaxSize().padding(14.dp)) {
            val w = size.width
            val h = size.height

            // 1. Concentric Allowance Track Arc (0.15 to 0.85 = 252 degrees)
            drawArc(
                color = Color.White.copy(alpha = 0.10f),
                startAngle = 144f,
                sweepAngle = 252f,
                useCenter = false,
                style = Stroke(width = 6.dp.toPx(), cap = StrokeCap.Round)
            )

            // 2. Allowance Progress Arc
            val progressSweep = (progressRatio.coerceAtMost(1f) * 252f)
            if (progressSweep > 0f) {
                drawArc(
                    brush = Brush.sweepGradient(
                        listOf(
                            Color(0xFF00FFB2),
                            Color(0xFF00E5FF),
                            statusColor
                        )
                    ),
                    startAngle = 144f,
                    sweepAngle = progressSweep,
                    useCenter = false,
                    style = Stroke(width = 6.dp.toPx(), cap = StrokeCap.Round)
                )
            }

            // 3. Anatomical Vector Lungs Silhouette (Center-scaled)
            val lungLeft = w * 0.23f
            val lungTop = h * 0.19f
            val lungW = w * 0.54f
            val lungH = h * 0.54f

            // Trachea
            val tracheaPath = Path().apply {
                moveTo(lungLeft + lungW * 0.48f, lungTop + lungH * 0.05f)
                lineTo(lungLeft + lungW * 0.52f, lungTop + lungH * 0.05f)
                lineTo(lungLeft + lungW * 0.52f, lungTop + lungH * 0.28f)
                lineTo(lungLeft + lungW * 0.48f, lungTop + lungH * 0.28f)
                close()
            }
            drawPath(tracheaPath, color = animatedLungColor.copy(alpha = 0.35f), style = Fill)

            // Left Lung Lobe
            val leftLungPath = Path().apply {
                moveTo(lungLeft + lungW * 0.46f, lungTop + lungH * 0.29f)
                cubicTo(
                    lungLeft + lungW * 0.30f, lungTop + lungH * 0.26f,
                    lungLeft + lungW * 0.12f, lungTop + lungH * 0.38f,
                    lungLeft + lungW * 0.12f, lungTop + lungH * 0.52f
                )
                cubicTo(
                    lungLeft + lungW * 0.12f, lungTop + lungH * 0.72f,
                    lungLeft + lungW * 0.22f, lungTop + lungH * 0.88f,
                    lungLeft + lungW * 0.38f, lungTop + lungH * 0.90f
                )
                cubicTo(
                    lungLeft + lungW * 0.42f, lungTop + lungH * 0.80f,
                    lungLeft + lungW * 0.44f, lungTop + lungH * 0.52f,
                    lungLeft + lungW * 0.46f, lungTop + lungH * 0.38f
                )
                close()
            }
            drawPath(
                leftLungPath,
                brush = Brush.verticalGradient(
                    colors = listOf(
                        animatedLungColor.copy(alpha = 0.40f),
                        animatedLungColor.copy(alpha = 0.20f)
                    ),
                    startY = lungTop,
                    endY = lungTop + lungH
                ),
                style = Fill
            )
            drawPath(
                leftLungPath,
                color = animatedLungColor.copy(alpha = 0.6f),
                style = Stroke(width = 1.5.dp.toPx())
            )

            // Right Lung Lobe
            val rightLungPath = Path().apply {
                moveTo(lungLeft + lungW * 0.54f, lungTop + lungH * 0.29f)
                cubicTo(
                    lungLeft + lungW * 0.70f, lungTop + lungH * 0.26f,
                    lungLeft + lungW * 0.88f, lungTop + lungH * 0.38f,
                    lungLeft + lungW * 0.88f, lungTop + lungH * 0.52f
                )
                cubicTo(
                    lungLeft + lungW * 0.88f, lungTop + lungH * 0.72f,
                    lungLeft + lungW * 0.78f, lungTop + lungH * 0.88f,
                    lungLeft + lungW * 0.62f, lungTop + lungH * 0.90f
                )
                cubicTo(
                    lungLeft + lungW * 0.58f, lungTop + lungH * 0.80f,
                    lungLeft + lungW * 0.56f, lungTop + lungH * 0.52f,
                    lungLeft + lungW * 0.54f, lungTop + lungH * 0.38f
                )
                close()
            }
            drawPath(
                rightLungPath,
                brush = Brush.verticalGradient(
                    colors = listOf(
                        animatedLungColor.copy(alpha = 0.40f),
                        animatedLungColor.copy(alpha = 0.20f)
                    ),
                    startY = lungTop,
                    endY = lungTop + lungH
                ),
                style = Fill
            )
            drawPath(
                rightLungPath,
                color = animatedLungColor.copy(alpha = 0.6f),
                style = Stroke(width = 1.5.dp.toPx())
            )

            // Bronchial Tree Branches
            val bronchiPath = Path().apply {
                moveTo(lungLeft + lungW * 0.50f, lungTop + lungH * 0.10f)
                lineTo(lungLeft + lungW * 0.50f, lungTop + lungH * 0.28f)

                // Left branches
                quadraticBezierTo(
                    lungLeft + lungW * 0.42f, lungTop + lungH * 0.34f,
                    lungLeft + lungW * 0.33f, lungTop + lungH * 0.46f
                )
                quadraticBezierTo(
                    lungLeft + lungW * 0.30f, lungTop + lungH * 0.56f,
                    lungLeft + lungW * 0.27f, lungTop + lungH * 0.66f
                )

                // Right branches
                moveTo(lungLeft + lungW * 0.50f, lungTop + lungH * 0.28f)
                quadraticBezierTo(
                    lungLeft + lungW * 0.58f, lungTop + lungH * 0.34f,
                    lungLeft + lungW * 0.67f, lungTop + lungH * 0.46f
                )
                quadraticBezierTo(
                    lungLeft + lungW * 0.70f, lungTop + lungH * 0.56f,
                    lungLeft + lungW * 0.73f, lungTop + lungH * 0.66f
                )
            }
            drawPath(
                bronchiPath,
                color = animatedLungColor.copy(alpha = 0.7f),
                style = Stroke(width = 1.2.dp.toPx(), cap = StrokeCap.Round)
            )
        }

        // Telemetry Overlay
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
            modifier = Modifier
                .padding(14.dp)
                .scale(pulseScale)
        ) {
            Icon(
                imageVector = when {
                    isOverLimit -> Icons.Rounded.Warning
                    countToday == 0 -> Icons.Rounded.CheckCircle
                    else -> Icons.Rounded.LocalFireDepartment
                },
                contentDescription = null,
                tint = statusColor,
                modifier = Modifier.size(18.dp)
            )

            Spacer(modifier = Modifier.height(2.dp))

            Text(
                text = "$countToday",
                fontSize = 36.sp,
                fontWeight = FontWeight.Bold,
                color = if (isOverLimit) Color(0xFFFF3B30) else Color.White
            )

            Text(
                text = "of $safeBaseline baseline max",
                fontSize = 11.sp,
                fontWeight = FontWeight.Medium,
                color = Color.White.copy(alpha = 0.80f)
            )

            Spacer(modifier = Modifier.height(4.dp))

            // Craving Badge Capsule
            Row(
                modifier = Modifier
                    .clip(CircleShape)
                    .background(Color.Black.copy(alpha = 0.45f))
                    .border(1.dp, badge.color.copy(alpha = 0.40f), CircleShape)
                    .padding(horizontal = 8.dp, vertical = 3.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Icon(
                    imageVector = badge.icon,
                    contentDescription = null,
                    tint = badge.color,
                    modifier = Modifier.size(10.dp)
                )
                Text(
                    text = badge.text,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White
                )
            }

            // Internal Breakdown Ticker
            if (smokeBreakdown.isNotEmpty()) {
                Spacer(modifier = Modifier.height(4.dp))
                HabitCircleBreakdownTicker(
                    items = smokeBreakdown,
                    habitType = HabitType.SMOKES
                )
            }
        }
    }
}

private fun estimatedSmokingDurationMillis(type: String?): Long {
    val t = type?.lowercase() ?: return 6 * 60 * 1000L
    return when {
        t.contains("cigarillo") || (t.contains("cigar") && !t.contains("cigarette")) -> 12 * 60 * 1000L
        t.contains("heat") || t.contains("iqos") || t.contains("glo") || t.contains("vape") -> 5 * 60 * 1000L
        t.contains("roll") -> 5 * 60 * 1000L
        else -> 6 * 60 * 1000L
    }
}
