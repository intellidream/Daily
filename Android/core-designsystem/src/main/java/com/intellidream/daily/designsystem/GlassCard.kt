package com.intellidream.daily.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

enum class GlassIntensity(val blurOpacity: Float) {
    Subtle(0.12f),
    Medium(0.20f),
    Prominent(0.32f);

    val displayName: String
        get() = when (this) {
            Subtle -> "Subtle"
            Medium -> "Medium"
            Prominent -> "Prominent"
        }
}

fun Modifier.liquidGlass(
    cornerRadius: Dp = 16.dp,
    padding: Dp = 16.dp,
    isDark: Boolean = true,
    intensity: GlassIntensity = GlassIntensity.Medium,
    shape: Shape = RoundedCornerShape(cornerRadius)
): Modifier = this
    .shadow(
        elevation = if (isDark) 8.dp else 4.dp,
        shape = shape,
        ambientColor = if (isDark) Color.Black.copy(alpha = 0.35f) else Color.Black.copy(alpha = 0.08f),
        spotColor = if (isDark) Color.Black.copy(alpha = 0.35f) else Color.Black.copy(alpha = 0.08f)
    )
    .clip(shape)
    .background(
        color = if (isDark) Color(0xFF080F1E).copy(alpha = 0.72f) else Color.White.copy(alpha = 0.85f),
        shape = shape
    )
    .background(
        brush = Brush.linearGradient(
            colors = if (isDark) listOf(
                Color.White.copy(alpha = intensity.blurOpacity * 0.75f),
                Color.White.copy(alpha = intensity.blurOpacity * 0.35f)
            ) else listOf(
                Color.Black.copy(alpha = intensity.blurOpacity * 0.08f),
                Color.Black.copy(alpha = intensity.blurOpacity * 0.02f)
            )
        ),
        shape = shape
    )
    .border(
        width = 1.dp,
        brush = if (isDark) ThemeColors.glassDarkBorder else ThemeColors.glassLightBorder,
        shape = shape
    )
    .padding(padding)

@Composable
fun GlassCard(
    modifier: Modifier = Modifier,
    cornerRadius: Dp = 16.dp,
    padding: Dp = 16.dp,
    isDark: Boolean = true,
    intensity: GlassIntensity = GlassIntensity.Medium,
    shape: Shape = RoundedCornerShape(cornerRadius),
    onClick: (() -> Unit)? = null,
    content: @Composable BoxScope.() -> Unit
) {
    val clickModifier = if (onClick != null) {
        Modifier
            .clip(shape)
            .clickable(onClick = onClick)
    } else Modifier

    Box(
        modifier = modifier
            .then(clickModifier)
            .liquidGlass(
                cornerRadius = cornerRadius,
                padding = padding,
                isDark = isDark,
                intensity = intensity,
                shape = shape
            ),
        content = content
    )
}
