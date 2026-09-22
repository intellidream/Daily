package com.intellidream.daily.designsystem

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Eco
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.model.MonkeyMood

/**
 * Size variants for the stylized procedural vector monkey mascot.
 * 1:1 parity with iOS MonkeySize.
 */
enum class MonkeySize(val dimension: Dp) {
    BADGE(24.dp), // For pills and widgets
    MINI(44.dp),  // For widget headers and list items
    CARD(80.dp),  // For dashboard cards
    HERO(130.dp); // For Stress Studio hero

    val scaleFactor: Float
        get() = dimension.value / 100f
}

/**
 * A charming, procedural vector monkey mascot with expressive moods and animated autonomic breath glow.
 * 1:1 Kotlin/Compose port of iOS [MonkeyMascotView.swift].
 */
@Composable
fun MonkeyMascotView(
    mood: MonkeyMood = MonkeyMood.CURIOUS,
    size: MonkeySize = MonkeySize.CARD,
    animated: Boolean = true,
    modifier: Modifier = Modifier
) {
    val auraColor = when (mood) {
        MonkeyMood.ZEN -> Color(0xFF00E5FF)        // Mint / neon cyan
        MonkeyMood.CURIOUS -> Color(0xFF00FFB2)    // Teal / spring green
        MonkeyMood.BUSY -> Color(0xFFFFA726)       // Warm amber
        MonkeyMood.OVERHEATED -> Color(0xFFFF5252) // Coral red
    }

    val animDuration = if (mood == MonkeyMood.OVERHEATED) 1400 else 3000
    val infiniteTransition = rememberInfiniteTransition(label = "monkeyMascotBreath")

    val breatheScale by if (animated) {
        infiniteTransition.animateFloat(
            initialValue = 1.0f,
            targetValue = 1.12f,
            animationSpec = infiniteRepeatable(
                animation = tween(durationMillis = animDuration, easing = FastOutSlowInEasing),
                repeatMode = RepeatMode.Reverse
            ),
            label = "breatheScale"
        )
    } else {
        androidx.compose.runtime.remember { androidx.compose.runtime.mutableFloatStateOf(1.0f) }
    }

    val earWiggle by if (animated) {
        val targetDeg = if (mood == MonkeyMood.BUSY) 4.0f else 1.5f
        infiniteTransition.animateFloat(
            initialValue = -targetDeg,
            targetValue = targetDeg,
            animationSpec = infiniteRepeatable(
                animation = tween(durationMillis = animDuration, easing = FastOutSlowInEasing),
                repeatMode = RepeatMode.Reverse
            ),
            label = "earWiggle"
        )
    } else {
        androidx.compose.runtime.remember { androidx.compose.runtime.mutableFloatStateOf(0.0f) }
    }

    val dim = size.dimension
    val scale = size.scaleFactor

    Box(
        modifier = modifier.size(dim),
        contentAlignment = Alignment.Center
    ) {
        // Background Autonomic Aura Halo
        Canvas(
            modifier = Modifier
                .size(dim)
                .scale(breatheScale)
        ) {
            drawCircle(
                brush = Brush.radialGradient(
                    colors = listOf(
                        auraColor.copy(alpha = 0.35f),
                        auraColor.copy(alpha = 0.08f),
                        Color.Transparent
                    ),
                    center = center,
                    radius = this.size.minDimension * 0.65f
                )
            )
        }

        // Monkey Facial Structure
        Box(
            modifier = Modifier.size(dim),
            contentAlignment = Alignment.Center
        ) {
            // Ears
            Row(
                modifier = Modifier
                    .offset(y = (-6 * scale).dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Left Ear
                EarView(scale = scale, isLeft = true, earWiggle = earWiggle)

                Box(modifier = Modifier.size((40 * scale).dp))

                // Right Ear
                EarView(scale = scale, isLeft = false, earWiggle = earWiggle)
            }

            // Main Head (Warm Caramel Coat)
            Box(
                modifier = Modifier
                    .size((72 * scale).dp, (68 * scale).dp)
                    .clip(CircleShape)
                    .background(
                        brush = Brush.verticalGradient(
                            listOf(Color(0xFF8D5B4C), Color(0xFF6D3B2C))
                        )
                    )
                    .border((1.5f * scale).dp, auraColor.copy(alpha = 0.4f), CircleShape)
            )

            // Face Mask (Peaches & Cream Inset)
            Row(
                modifier = Modifier.offset(y = (-4 * scale).dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(
                    modifier = Modifier
                        .size((36 * scale).dp)
                        .clip(CircleShape)
                        .background(Color(0xFFF7D6BF))
                )
                Box(
                    modifier = Modifier
                        .offset(x = (-8 * scale).dp)
                        .size((36 * scale).dp)
                        .clip(CircleShape)
                        .background(Color(0xFFF7D6BF))
                )
            }

            // Lower Muzzle
            Box(
                modifier = Modifier
                    .offset(y = (10 * scale).dp)
                    .size((50 * scale).dp, (32 * scale).dp)
                    .clip(CircleShape)
                    .background(Color(0xFFF7D6BF))
            )

            // Eyes & Expression
            EyesView(mood = mood, scale = scale)

            // Nose
            Box(
                modifier = Modifier
                    .offset(y = (9 * scale).dp)
                    .size((8 * scale).dp, (5 * scale).dp)
                    .clip(CircleShape)
                    .background(Color(0xFF4E271E))
            )

            // Mouth
            MouthView(mood = mood, scale = scale)

            // Mood Specific Accessories
            MoodAccessory(mood = mood, scale = scale)
        }
    }
}

@Composable
private fun EarView(scale: Float, isLeft: Boolean, earWiggle: Float) {
    Box(
        modifier = Modifier
            .rotate(if (isLeft) -earWiggle else earWiggle)
            .size((24 * scale).dp)
            .clip(CircleShape)
            .background(Color(0xFF7A4333)),
        contentAlignment = Alignment.Center
    ) {
        Box(
            modifier = Modifier
                .size((14 * scale).dp)
                .clip(CircleShape)
                .background(Color(0xFFF7B8A1))
        )
    }
}

@Composable
private fun EyesView(mood: MonkeyMood, scale: Float) {
    val spacing = (16 * scale).dp

    Box(
        modifier = Modifier.offset(y = (-2 * scale).dp),
        contentAlignment = Alignment.Center
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            when (mood) {
                MonkeyMood.ZEN -> {
                    // Serene curved closed eyes (smiling arcs)
                    Text(
                        text = "◜  ◝",
                        color = Color(0xFF3D1E15),
                        fontSize = (14 * scale).sp,
                        fontWeight = FontWeight.Bold
                    )
                }

                MonkeyMood.CURIOUS -> {
                    EyePupil(scale = scale)
                    Box(modifier = Modifier.size(spacing))
                    EyePupil(scale = scale)
                }

                MonkeyMood.BUSY -> {
                    EyePupil(scale = scale)
                    Box(modifier = Modifier.size(spacing))
                    Box(
                        modifier = Modifier
                            .size((6.5f * scale).dp, (5 * scale).dp)
                            .clip(CircleShape)
                            .background(Color(0xFF2D120B))
                    )
                }

                MonkeyMood.OVERHEATED -> {
                    Text(
                        text = "✕",
                        color = Color(0xFFFF5252),
                        fontSize = (10 * scale).sp,
                        fontWeight = FontWeight.Black
                    )
                    Box(modifier = Modifier.size((14 * scale).dp))
                    Text(
                        text = "✕",
                        color = Color(0xFFFF5252),
                        fontSize = (10 * scale).sp,
                        fontWeight = FontWeight.Black
                    )
                }
            }
        }
    }
}

@Composable
private fun EyePupil(scale: Float) {
    Box(
        modifier = Modifier
            .size((8 * scale).dp)
            .clip(CircleShape)
            .background(Color(0xFF241009))
    ) {
        Box(
            modifier = Modifier
                .offset(x = (1.5f * scale).dp, y = (1.5f * scale).dp)
                .size((2.5f * scale).dp)
                .clip(CircleShape)
                .background(Color.White)
        )
    }
}

@Composable
private fun MouthView(mood: MonkeyMood, scale: Float) {
    Box(
        modifier = Modifier.offset(y = (18 * scale).dp),
        contentAlignment = Alignment.Center
    ) {
        when (mood) {
            MonkeyMood.ZEN -> {
                Text(
                    text = "‿",
                    color = Color(0xFF4E271E),
                    fontSize = (14 * scale).sp,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.offset(y = (-4 * scale).dp)
                )
            }

            MonkeyMood.CURIOUS -> {
                Box(
                    modifier = Modifier
                        .size((8 * scale).dp, (4 * scale).dp)
                        .clip(CircleShape)
                        .background(Color(0xFFD85A5A))
                )
            }

            MonkeyMood.BUSY -> {
                Box(
                    modifier = Modifier
                        .size((10 * scale).dp, (2 * scale).dp)
                        .clip(CircleShape)
                        .background(Color(0xFF4E271E))
                )
            }

            MonkeyMood.OVERHEATED -> {
                Box(
                    modifier = Modifier
                        .size((10 * scale).dp, (6 * scale).dp)
                        .clip(CircleShape)
                        .background(Color(0xFFC62828))
                )
            }
        }
    }
}

@Composable
private fun MoodAccessory(mood: MonkeyMood, scale: Float) {
    when (mood) {
        MonkeyMood.ZEN -> {
            // Floating green lotus / leaf
            Icon(
                imageVector = Icons.Rounded.Eco,
                contentDescription = null,
                tint = Color(0xFF00E5FF),
                modifier = Modifier
                    .offset(x = (18 * scale).dp, y = (-26 * scale).dp)
                    .size((12 * scale).dp)
            )
        }

        MonkeyMood.CURIOUS -> {
            // Clean curious look
        }

        MonkeyMood.BUSY -> {
            // Thinking bubble
            Box(
                modifier = Modifier
                    .offset(x = (26 * scale).dp, y = (-22 * scale).dp)
                    .size((5 * scale).dp)
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.85f))
            )
        }

        MonkeyMood.OVERHEATED -> {
            // Cute cool ice-pack on forehead
            Box(
                modifier = Modifier
                    .offset(y = (-28 * scale).dp)
                    .size((28 * scale).dp, (12 * scale).dp)
                    .shadow((3 * scale).dp, CircleShape)
                    .clip(CircleShape)
                    .background(
                        brush = Brush.verticalGradient(
                            listOf(Color(0xFF64B5F6), Color(0xFF1E88E5))
                        )
                    ),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = "❄",
                    color = Color.White,
                    fontSize = (8 * scale).sp,
                    fontWeight = FontWeight.Bold
                )
            }
        }
    }
}
