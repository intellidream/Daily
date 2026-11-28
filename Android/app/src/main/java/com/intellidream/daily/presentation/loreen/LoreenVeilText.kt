package com.intellidream.daily.presentation.loreen

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.TextUnit
import com.intellidream.daily.R
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/** Static singleton font family — zero allocations inside LazyColumn/scrollables. */
val LoreenFontFamily = FontFamily(Font(R.font.loreen_regular))

private val SparkleCyan = Color(0xFF38E8FF)
private val SparkleWhite = Color.White
private val SparkleViolet = Color(0xFFB885FF)

/**
 * Renders text in either Loreen Script or the system font with a 120Hz GPU
 * "Movie Password Decrypt" sparkle (`✦`) & micro-dot (`•`) left-to-right sweep.
 * At rest (`morphProgress <= 0.001f`), zero particle or extra layer overhead is incurred.
 */
@Composable
fun LoreenVeilText(
    text: String,
    isVeiled: Boolean,
    color: Color,
    fontSize: TextUnit,
    modifier: Modifier = Modifier,
    fontWeight: FontWeight? = null,
    maxLines: Int = Int.MAX_VALUE,
    overflow: TextOverflow = TextOverflow.Clip,
    textDecoration: TextDecoration? = null,
    lineHeight: TextUnit = TextUnit.Unspecified
) {
    var displayVeiled by remember { mutableStateOf(isVeiled) }
    var previousVeiled by remember { mutableStateOf(isVeiled) }
    val morphProgress = remember { Animatable(0f) }

    LaunchedEffect(isVeiled) {
        if (isVeiled != previousVeiled) {
            previousVeiled = isVeiled
            morphProgress.snapTo(0f)
            morphProgress.animateTo(
                targetValue = 1f,
                animationSpec = tween(durationMillis = 460, easing = FastOutSlowInEasing)
            ) {
                if (value >= 0.48f && displayVeiled != isVeiled) {
                    displayVeiled = isVeiled
                }
            }
            displayVeiled = isVeiled
            morphProgress.snapTo(0f)
        }
    }

    val p = morphProgress.value
    val activeModifier = if (p > 0.001f) {
        modifier.drawWithContent {
            val bandCenter = p
            val bandHalf = 0.24f
            drawContent()
            drawSparkleDecryptWave(
                textSeed = text.hashCode(),
                bandCenter = bandCenter,
                bandHalf = bandHalf
            )
        }
    } else {
        modifier
    }

    val textColor = if (p > 0.001f) {
        val dip = sin(p * PI).toFloat() * 0.42f
        color.copy(alpha = (color.alpha * (1f - dip)).coerceIn(0f, 1f))
    } else {
        color
    }

    Text(
        text = text,
        color = textColor,
        fontSize = fontSize,
        fontWeight = if (displayVeiled) FontWeight.Normal else fontWeight,
        fontFamily = if (displayVeiled) LoreenFontFamily else FontFamily.Default,
        maxLines = maxLines,
        overflow = overflow,
        textDecoration = textDecoration,
        lineHeight = lineHeight,
        modifier = activeModifier
    )
}

private fun DrawScope.drawSparkleDecryptWave(
    textSeed: Int,
    bandCenter: Float,
    bandHalf: Float
) {
    val w = size.width
    val h = size.height
    if (w <= 1f || h <= 1f) return

    val colCount = max(4, min(18, (w / 14f).toInt()))
    for (col in 0 until colCount) {
        val normX = if (colCount > 1) col.toFloat() / (colCount - 1) else 0.5f
        val dist = abs(normX - bandCenter)
        if (dist > bandHalf) continue

        val intensity = sin((1f - dist / bandHalf) * PI).toFloat()
        if (intensity <= 0.06f) continue

        val colX = normX * w
        for (k in 0 until 3) {
            val h1 = hash01(textSeed + col * 31 + k * 17)
            val h2 = hash01(textSeed + col * 53 + k * 37 + 5)
            val h3 = hash01(textSeed + col * 79 + k * 71 + 11)

            val driftX = (h3 - 0.5f) * 10f * intensity
            val driftY = (h1 - 0.5f) * 10f * intensity
            val px = (colX + (h1 - 0.5f) * (w / colCount) + driftX).coerceIn(0f, w)
            val py = (h * (0.12f + 0.76f * h2) + driftY).coerceIn(0f, h)

            val twinkle = 0.55f + 0.45f * sin(((bandCenter * 4f + h3 * 2f) * PI).toFloat())
            val alpha = (intensity * 1.15f * twinkle).coerceIn(0f, 1f)
            val particleColor = when ((col + k) % 3) {
                0 -> SparkleCyan.copy(alpha = alpha)
                1 -> SparkleWhite.copy(alpha = alpha)
                else -> SparkleViolet.copy(alpha = alpha)
            }

            if (k == 0) {
                val r = (4.5f + 3.0f * h3) * twinkle
                drawFourPointStar(center = Offset(px, py), radius = r, color = particleColor)
            } else {
                val r = (1.8f + 1.8f * h3) * twinkle
                drawCircle(color = particleColor, radius = r, center = Offset(px, py))
            }
        }
    }
}

private fun DrawScope.drawFourPointStar(center: Offset, radius: Float, color: Color) {
    val inner = radius * 0.25f
    val path = Path().apply {
        moveTo(center.x, center.y - radius)
        lineTo(center.x + inner, center.y - inner)
        lineTo(center.x + radius, center.y)
        lineTo(center.x + inner, center.y + inner)
        lineTo(center.x, center.y + radius)
        lineTo(center.x - inner, center.y + inner)
        lineTo(center.x - radius, center.y)
        lineTo(center.x - inner, center.y - inner)
        close()
    }
    drawPath(path = path, color = color)
}

private fun hash01(seed: Int): Float {
    var x = seed.toLong() * 0x9E3779B97F4A7C15uL.toLong()
    x = (x xor (x ushr 30)) * (-0x40a7b892e31b1a47L)
    x = (x xor (x ushr 27)) * (-0x6b2fb644eccefe15L)
    x = x xor (x ushr 31)
    return ((x and 0xFFFFL).toFloat()) / 65535f
}
