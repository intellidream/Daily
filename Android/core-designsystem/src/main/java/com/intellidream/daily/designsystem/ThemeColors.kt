package com.intellidream.daily.designsystem

import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color

object ThemeColors {
    // Background gradient stops (mirroring iOS ThemeColors & WinUI 3)
    val bgStop0 = Color(0xFF030609)
    val bgStop1 = Color(0xFF050F1A)
    val bgStop2 = Color(0xFF0D1A35)
    val bgStop3 = Color(0xFF132B4A)

    // Light theme background
    val lightBgColor = Color(0xFFD4C9B0)

    // Accent Glow & Highlights
    val accentCyan = Color(0xFF00E5FF)
    val accentBlue = Color(0xFF4A9EFF)
    val accentPink = Color(0xFFFF2D55)
    val accentPurple = Color(0xFFAF52DE)
    val accentGreen = Color(0xFF00E676)
    val accentOrange = Color(0xFFFF9500)
    val glowPurple = Color(0xFF8A2BE2)

    // Status colors
    val error = Color(0xFFFF6B6B)
    val warning = Color(0xFFFFD166)
    val success = Color(0xFF00E676)

    // Foreground / Text
    val fgPrimaryDark = Color.White
    val fgMutedDark = Color.White.copy(alpha = 0.70f)
    val textSecondary = Color.White.copy(alpha = 0.70f)
    val textMuted = Color.White.copy(alpha = 0.45f)
    val fgPrimaryLight = Color(0xFF1A1A1A)
    val fgMutedLight = Color(0xFF1A1A1A).copy(alpha = 0.65f)

    // Glass borders
    val glassDarkBorder = Brush.linearGradient(
        colors = listOf(
            Color.White.copy(alpha = 0.35f),
            Color.White.copy(alpha = 0.10f),
            Color.Transparent,
            Color.White.copy(alpha = 0.18f)
        )
    )

    val glassLightBorder = Brush.linearGradient(
        colors = listOf(
            Color.Black.copy(alpha = 0.18f),
            Color.Black.copy(alpha = 0.06f),
            Color.Transparent,
            Color.Black.copy(alpha = 0.12f)
        )
    )

    val backgroundGradient = Brush.verticalGradient(
        colors = listOf(bgStop0, bgStop1, bgStop2, bgStop3)
    )

    val activeTabIndicatorBrush = Brush.linearGradient(
        colors = listOf(
            accentBlue.copy(alpha = 0.65f),
            accentCyan.copy(alpha = 0.40f)
        )
    )
}
