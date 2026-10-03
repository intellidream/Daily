package com.intellidream.daily.designsystem

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Luxury Liquid Glass loading indicator.
 * Features dual glowing orbital arcs with fluid continuous momentum and an ambient breathing halo.
 */
@Composable
fun DailyLiquidLoadingIndicator(
    modifier: Modifier = Modifier,
    color: Color = ThemeColors.accentCyan,
    size: Dp = 44.dp,
    label: String? = null
) {
    val infiniteTransition = rememberInfiniteTransition(label = "LiquidLoadingTransition")

    // Rotation angle
    val rotation by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 1400, easing = LinearEasing),
            repeatMode = RepeatMode.Restart
        ),
        label = "LiquidRotation"
    )

    // Breathing pulse for ambient halo
    val pulseAlpha by infiniteTransition.animateFloat(
        initialValue = 0.25f,
        targetValue = 0.65f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 900, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "LiquidPulse"
    )

    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Box(
            modifier = Modifier.size(size),
            contentAlignment = Alignment.Center
        ) {
            // Ambient neon halo
            Box(
                modifier = Modifier
                    .size(size * 0.85f)
                    .blur(10.dp)
                    .background(color.copy(alpha = pulseAlpha * 0.45f), shape = RoundedCornerShape(percent = 50))
            )

            Canvas(modifier = Modifier.size(size)) {
                val strokeWidth = (size * 0.08f).toPx().coerceAtLeast(3f)
                val halfStroke = strokeWidth / 2f
                val canvasSize = this.size.minDimension - strokeWidth
                val topLeft = Offset(halfStroke, halfStroke)

                // Track ring
                drawArc(
                    color = color.copy(alpha = 0.12f),
                    startAngle = 0f,
                    sweepAngle = 360f,
                    useCenter = false,
                    topLeft = topLeft,
                    size = androidx.compose.ui.geometry.Size(canvasSize, canvasSize),
                    style = Stroke(width = strokeWidth, cap = StrokeCap.Round)
                )

                // Primary glowing orbital arc
                drawArc(
                    brush = Brush.sweepGradient(
                        0.0f to color.copy(alpha = 0.1f),
                        0.5f to color,
                        1.0f to Color.White
                    ),
                    startAngle = rotation,
                    sweepAngle = 135f,
                    useCenter = false,
                    topLeft = topLeft,
                    size = androidx.compose.ui.geometry.Size(canvasSize, canvasSize),
                    style = Stroke(width = strokeWidth, cap = StrokeCap.Round)
                )

                // Counter-balance micro spark
                drawArc(
                    color = Color.White.copy(alpha = pulseAlpha),
                    startAngle = (rotation + 190f) % 360f,
                    sweepAngle = 35f,
                    useCenter = false,
                    topLeft = topLeft,
                    size = androidx.compose.ui.geometry.Size(canvasSize, canvasSize),
                    style = Stroke(width = strokeWidth * 0.9f, cap = StrokeCap.Round)
                )
            }
        }

        if (!label.isNullOrEmpty()) {
            Spacer(modifier = Modifier.height(10.dp))
            Text(
                text = label,
                color = ThemeColors.textSecondary,
                fontSize = 13.sp,
                fontWeight = FontWeight.Medium
            )
        }
    }
}

/**
 * Luxury Liquid Glass skeleton shimmer placeholder box.
 */
@Composable
fun LiquidShimmerBox(
    modifier: Modifier = Modifier,
    cornerRadius: Dp = 12.dp
) {
    val transition = rememberInfiniteTransition(label = "ShimmerTransition")
    val translateAnim by transition.animateFloat(
        initialValue = -500f,
        targetValue = 1200f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 1300, easing = LinearEasing),
            repeatMode = RepeatMode.Restart
        ),
        label = "ShimmerTranslate"
    )

    val shimmerBrush = Brush.linearGradient(
        colors = listOf(
            Color.White.copy(alpha = 0.04f),
            Color.White.copy(alpha = 0.12f),
            ThemeColors.accentCyan.copy(alpha = 0.15f),
            Color.White.copy(alpha = 0.04f)
        ),
        start = Offset(translateAnim - 300f, translateAnim - 300f),
        end = Offset(translateAnim + 300f, translateAnim + 300f)
    )

    Box(
        modifier = modifier
            .clip(RoundedCornerShape(cornerRadius))
            .background(shimmerBrush)
    )
}
