package com.intellidream.daily.presentation.habits

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Fill
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.designsystem.ThemeColors

@Composable
fun SmokesLungsGaugeView(
    countToday: Int,
    baselineCount: Int,
    lastSmokeDate: Long?,
    timeSinceLastSmokeMillis: Long?,
    modifier: Modifier = Modifier
) {
    val safeBaseline = baselineCount.coerceAtLeast(1)
    val progressRatio = (countToday.toFloat() / safeBaseline.toFloat()).coerceIn(0f, 1.5f)
    val isOverLimit = countToday > safeBaseline
    val isWarning = countToday >= (safeBaseline * 0.8)

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
                red = 0.85f - t * (0.85f - 0.72f),
                green = (125f - t * (125f - 134f)) / 255f,
                blue = (142f - t * (142f - 11f)) / 255f
            )
        }
        else -> {
            val t = ((progressRatio - 0.75f) / 0.75f).coerceIn(0f, 1f)
            Color(
                red = 0.72f - t * (0.72f - 0.20f),
                green = 0.52f - t * (0.52f - 0.20f),
                blue = 0.04f + t * (0.20f - 0.04f)
            )
        }
    }

    val animatedLungColor by animateColorAsState(
        targetValue = targetLungColor,
        animationSpec = tween(600),
        label = "lungColor"
    )

    val timeSinceText = timeSinceLastSmokeMillis?.let { millis ->
        val mins = (millis / 60000).toInt()
        val hours = mins / 60
        val remMins = mins % 60
        when {
            hours > 0 -> "${hours}h ${remMins}m smoke-free"
            mins > 0 -> "${mins}m smoke-free"
            else -> "Just now"
        }
    } ?: "Smoke-Free Today"

    Box(
        modifier = modifier
            .size(240.dp)
            .clip(CircleShape)
            .background(Color(0xFF0A1220).copy(alpha = 0.8f))
            .border(
                width = 2.dp,
                brush = Brush.sweepGradient(
                    colors = listOf(
                        statusColor.copy(alpha = 0.7f),
                        statusColor.copy(alpha = 0.2f),
                        Color.White.copy(alpha = 0.1f),
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

            // 1. Concentric Allowance Track
            drawArc(
                color = Color.White.copy(alpha = 0.10f),
                startAngle = -90f,
                sweepAngle = 360f,
                useCenter = false,
                style = Stroke(width = 8.dp.toPx(), cap = StrokeCap.Round)
            )

            // 2. Allowance Progress Arc
            val sweep = (progressRatio.coerceAtMost(1f) * 360f)
            if (sweep > 0f) {
                drawArc(
                    brush = Brush.sweepGradient(
                        colors = listOf(
                            statusColor.copy(alpha = 0.6f),
                            statusColor,
                            statusColor
                        )
                    ),
                    startAngle = -90f,
                    sweepAngle = sweep,
                    useCenter = false,
                    style = Stroke(width = 8.dp.toPx(), cap = StrokeCap.Round)
                )
            }

            // 3. Anatomical Vector Lungs Silhouette (Center-scaled)
            val lungLeft = w * 0.22f
            val lungTop = h * 0.18f
            val lungW = w * 0.56f
            val lungH = h * 0.56f

            // Trachea
            val tracheaPath = Path().apply {
                moveTo(lungLeft + lungW * 0.48f, lungTop + lungH * 0.05f)
                lineTo(lungLeft + lungW * 0.52f, lungTop + lungH * 0.05f)
                lineTo(lungLeft + lungW * 0.52f, lungTop + lungH * 0.28f)
                lineTo(lungLeft + lungW * 0.48f, lungTop + lungH * 0.28f)
                close()
            }
            drawPath(tracheaPath, color = animatedLungColor.copy(alpha = 0.4f), style = Fill)

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
                        animatedLungColor.copy(alpha = 0.45f),
                        animatedLungColor.copy(alpha = 0.25f)
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
                        animatedLungColor.copy(alpha = 0.45f),
                        animatedLungColor.copy(alpha = 0.25f)
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
                color = animatedLungColor.copy(alpha = 0.8f),
                style = Stroke(width = 1.2.dp.toPx(), cap = StrokeCap.Round)
            )
        }

        // Telemetry Overlay
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.padding(16.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(34.dp)
                    .clip(CircleShape)
                    .background(Color.Black.copy(alpha = 0.45f))
                    .border(1.dp, statusColor.copy(alpha = 0.3f), CircleShape),
                contentAlignment = Alignment.Center
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
            }

            Spacer(modifier = Modifier.height(4.dp))

            Text(
                text = "$countToday / $baselineCount",
                fontSize = 28.sp,
                fontWeight = FontWeight.Bold,
                color = if (isOverLimit) Color(0xFFFF3B30) else Color.White
            )

            Text(
                text = "baseline max",
                fontSize = 11.sp,
                fontWeight = FontWeight.Medium,
                color = ThemeColors.textSecondary
            )

            Spacer(modifier = Modifier.height(8.dp))

            Box(
                modifier = Modifier
                    .clip(CircleShape)
                    .background(statusColor.copy(alpha = 0.18f))
                    .border(1.dp, statusColor.copy(alpha = 0.35f), CircleShape)
                    .padding(horizontal = 10.dp, vertical = 4.dp)
            ) {
                Text(
                    text = timeSinceText,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    color = statusColor
                )
            }
        }
    }
}
