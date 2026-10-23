package com.intellidream.daily.presentation.habits

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
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
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.WaterDrop
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Fill
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.HabitDrinkBreakdown
import com.intellidream.daily.model.HabitType
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.sin

data class LiquidStratum(
    val name: String,
    val amountMl: Double,
    val startProgress: Float,
    val endProgress: Float,
    val primaryColor: Color,
    val secondaryColor: Color
)

@Composable
fun WaterProgressWaveView(
    currentMl: Double,
    goalMl: Double,
    drinkBreakdown: List<HabitDrinkBreakdown> = emptyList(),
    modifier: Modifier = Modifier
) {
    val safeGoal = goalMl.coerceAtLeast(1.0)
    val progressRatio = (currentMl / safeGoal).toFloat().coerceIn(0f, 1f)
    val percentageDisplay = ((currentMl / safeGoal) * 100).toInt()
    val isGoalMet = currentMl >= safeGoal

    // Hydrodynamic Fluid Surge model: surges on hydration intake/appear, then settles calmly
    val phase1 = remember { Animatable(0f) }
    val phase2 = remember { Animatable(0.5f * PI.toFloat()) }
    var isSurging by remember { mutableStateOf(false) }

    LaunchedEffect(currentMl) {
        isSurging = true
        launch {
            phase1.animateTo(
                targetValue = phase1.value + (2f * PI.toFloat()),
                animationSpec = tween(durationMillis = 2500, easing = FastOutSlowInEasing)
            )
        }
        launch {
            phase2.animateTo(
                targetValue = phase2.value - (1.5f * PI.toFloat()),
                animationSpec = tween(durationMillis = 2500, easing = FastOutSlowInEasing)
            )
        }
        delay(2500L)
        isSurging = false
    }

    // Stratified liquids calculation
    val strata: List<LiquidStratum> = if (currentMl <= 0 || drinkBreakdown.isEmpty()) {
        listOf(
            LiquidStratum(
                name = "Water",
                amountMl = currentMl,
                startProgress = 0f,
                endProgress = progressRatio,
                primaryColor = ThemeColors.accentCyan,
                secondaryColor = Color(0xFF0077B6)
            )
        )
    } else {
        var waterAmt = 0.0
        var teaAmt = 0.0
        var coffeeAmt = 0.0

        for (item in drinkBreakdown) {
            val lower = item.drink.lowercase()
            when {
                lower.contains("coffee") || lower.contains("espresso") -> coffeeAmt += item.amount
                lower.contains("tea") -> teaAmt += item.amount
                else -> waterAmt += item.amount
            }
        }

        val total = (waterAmt + teaAmt + coffeeAmt).coerceAtLeast(1.0)
        val list = mutableListOf<LiquidStratum>()
        var cum = 0f

        if (waterAmt > 0) {
            val frac = ((waterAmt / total) * progressRatio).toFloat()
            list.add(
                LiquidStratum(
                    name = "Water",
                    amountMl = waterAmt,
                    startProgress = cum,
                    endProgress = cum + frac,
                    primaryColor = ThemeColors.accentCyan,
                    secondaryColor = Color(0xFF0077B6)
                )
            )
            cum += frac
        }
        if (teaAmt > 0) {
            val frac = ((teaAmt / total) * progressRatio).toFloat()
            list.add(
                LiquidStratum(
                    name = "Tea",
                    amountMl = teaAmt,
                    startProgress = cum,
                    endProgress = cum + frac,
                    primaryColor = Color(0xFF84CC16),
                    secondaryColor = Color(0xFF3F6212)
                )
            )
            cum += frac
        }
        if (coffeeAmt > 0) {
            val frac = ((coffeeAmt / total) * progressRatio).toFloat()
            list.add(
                LiquidStratum(
                    name = "Coffee",
                    amountMl = coffeeAmt,
                    startProgress = cum,
                    endProgress = cum + frac,
                    primaryColor = Color(0xFFF59E0B),
                    secondaryColor = Color(0xFF92400E)
                )
            )
        }
        if (list.isEmpty()) {
            listOf(
                LiquidStratum(
                    name = "Water",
                    amountMl = currentMl,
                    startProgress = 0f,
                    endProgress = progressRatio,
                    primaryColor = ThemeColors.accentCyan,
                    secondaryColor = Color(0xFF0077B6)
                )
            )
        } else {
            list
        }
    }

    Box(
        modifier = modifier
            .size(240.dp)
            .clip(CircleShape)
            .background(Color(0xFF0A1220).copy(alpha = 0.8f))
            .border(
                width = 2.dp,
                brush = Brush.sweepGradient(
                    colors = listOf(
                        ThemeColors.accentCyan.copy(alpha = 0.8f),
                        ThemeColors.accentBlue.copy(alpha = 0.3f),
                        Color.White.copy(alpha = 0.15f),
                        ThemeColors.accentCyan.copy(alpha = 0.8f)
                    )
                ),
                shape = CircleShape
            ),
        contentAlignment = Alignment.Center
    ) {
        // Fluid Wave Canvas
        Canvas(modifier = Modifier.fillMaxSize()) {
            val width = size.width
            val height = size.height
            val amplitude = if (isSurging) 10f else 3f
            val currentPhase1 = phase1.value
            val currentPhase2 = phase2.value

            for (stratum in strata) {
                // Secondary wave (background layer, slightly phase shifted)
                val pathBack = Path()
                val baseHeightBack = height * (1f - stratum.endProgress)
                pathBack.moveTo(0f, height * (1f - stratum.startProgress))
                pathBack.lineTo(0f, baseHeightBack)

                var x = 0f
                while (x <= width) {
                    val relativeX = x / width
                    val sine = sin(relativeX * 2 * PI + currentPhase2)
                    val y = baseHeightBack + sine.toFloat() * (amplitude * 0.7f)
                    pathBack.lineTo(x, y)
                    x += 4f
                }
                pathBack.lineTo(width, height * (1f - stratum.startProgress))
                pathBack.close()

                drawPath(
                    path = pathBack,
                    brush = Brush.verticalGradient(
                        colors = listOf(
                            stratum.primaryColor.copy(alpha = 0.35f),
                            stratum.secondaryColor.copy(alpha = 0.45f)
                        ),
                        startY = baseHeightBack,
                        endY = height
                    ),
                    style = Fill
                )

                // Primary wave (foreground layer)
                val pathFront = Path()
                val baseHeightFront = height * (1f - stratum.endProgress)
                pathFront.moveTo(0f, height * (1f - stratum.startProgress))
                pathFront.lineTo(0f, baseHeightFront)

                x = 0f
                while (x <= width) {
                    val relativeX = x / width
                    val sine = sin(relativeX * 2 * PI + currentPhase1)
                    val y = baseHeightFront + sine.toFloat() * amplitude
                    pathFront.lineTo(x, y)
                    x += 4f
                }
                pathFront.lineTo(width, height * (1f - stratum.startProgress))
                pathFront.close()

                drawPath(
                    path = pathFront,
                    brush = Brush.verticalGradient(
                        colors = listOf(
                            stratum.primaryColor.copy(alpha = 0.85f),
                            stratum.secondaryColor.copy(alpha = 0.95f)
                        ),
                        startY = baseHeightFront,
                        endY = height
                    ),
                    style = Fill
                )
            }
        }

        // Circular Glass Center Readout Overlay
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
            modifier = Modifier.padding(14.dp)
        ) {
            Icon(
                imageVector = if (isGoalMet) Icons.Rounded.Check else Icons.Rounded.WaterDrop,
                contentDescription = null,
                tint = if (isGoalMet) Color(0xFF00FFB2) else ThemeColors.accentCyan,
                modifier = Modifier.size(18.dp)
            )

            Spacer(modifier = Modifier.height(2.dp))

            Text(
                text = "${currentMl.toInt()}",
                fontSize = 34.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White
            )

            Text(
                text = "of ${goalMl.toInt()} ml ($percentageDisplay%)",
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
                color = Color.White.copy(alpha = 0.85f)
            )

            if (isGoalMet && goalMl > 0) {
                Spacer(modifier = Modifier.height(4.dp))
                Row(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(Color.Black.copy(alpha = 0.45f))
                        .border(1.dp, Color(0xFF00FFB2).copy(alpha = 0.40f), CircleShape)
                        .padding(horizontal = 8.dp, vertical = 3.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Check,
                        contentDescription = null,
                        tint = Color(0xFF00FFB2),
                        modifier = Modifier.size(10.dp)
                    )
                    Text(
                        text = "Goal Achieved",
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color(0xFF00FFB2)
                    )
                }
            } else {
                val remaining = (goalMl - currentMl).toInt().coerceAtLeast(0)
                Spacer(modifier = Modifier.height(2.dp))
                Text(
                    text = "$remaining ml left",
                    fontSize = 10.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = Color.White.copy(alpha = 0.70f)
                )
            }

            // Liquid Breakdown Ticker
            if (drinkBreakdown.isNotEmpty()) {
                Spacer(modifier = Modifier.height(4.dp))
                HabitCircleBreakdownTicker(
                    items = drinkBreakdown,
                    habitType = HabitType.WATER
                )
            }
        }
    }
}
