package com.intellidream.daily.wearos.presentation.theme

import androidx.compose.ui.graphics.Color
import androidx.wear.compose.material.Colors

// DayOne Brand & Semantic Wear Colors
val WaterCyan = Color(0xFF38BDF8)
val WaterCyanTonal = Color(0xFF0C2738)
val CoffeeOrange = Color(0xFFFF9F0A)
val CoffeeOrangeTonal = Color(0xFF351F08)

val SmokeRed = Color(0xFFFF453A)
val SmokeRedTonal = Color(0xFF381212)
val SmokeGreen = Color(0xFF32D74B)
val HeatIndigo = Color(0xFF5E5CE6)
val HeatIndigoTonal = Color(0xFF1D1A38)

val SurfaceCard = Color(0xFF1C1C1E)
val SurfaceCardBorder = Color(0xFF2C2C2E)
val SurfaceCardActive = Color(0xFF3A3A3C)

val TextPrimary = Color(0xFFFFFFFF)
val TextSecondary = Color(0xFF8E8E93)
val TextTertiary = Color(0xFF636366)

object DailyWearColors {
    val WaterCyan = com.intellidream.daily.wearos.presentation.theme.WaterCyan
    val WaterCyanTonal = com.intellidream.daily.wearos.presentation.theme.WaterCyanTonal
    val CoffeeOrange = com.intellidream.daily.wearos.presentation.theme.CoffeeOrange
    val CoffeeOrangeTonal = com.intellidream.daily.wearos.presentation.theme.CoffeeOrangeTonal
    val SmokeRed = com.intellidream.daily.wearos.presentation.theme.SmokeRed
    val SmokeRedTonal = com.intellidream.daily.wearos.presentation.theme.SmokeRedTonal
    val SmokeGreen = com.intellidream.daily.wearos.presentation.theme.SmokeGreen
    val HeatIndigo = com.intellidream.daily.wearos.presentation.theme.HeatIndigo
    val HeatIndigoTonal = com.intellidream.daily.wearos.presentation.theme.HeatIndigoTonal
    val SurfaceCard = com.intellidream.daily.wearos.presentation.theme.SurfaceCard
    val SurfaceCardBorder = com.intellidream.daily.wearos.presentation.theme.SurfaceCardBorder
    val SurfaceCardActive = com.intellidream.daily.wearos.presentation.theme.SurfaceCardActive
    val TextPrimary = com.intellidream.daily.wearos.presentation.theme.TextPrimary
    val TextSecondary = com.intellidream.daily.wearos.presentation.theme.TextSecondary
    val TextTertiary = com.intellidream.daily.wearos.presentation.theme.TextTertiary
}

val dailyWearColorPalette: Colors = Colors(
    primary = WaterCyan,
    primaryVariant = WaterCyanTonal,
    secondary = CoffeeOrange,
    secondaryVariant = CoffeeOrangeTonal,
    error = SmokeRed,
    onPrimary = Color.Black,
    onSecondary = Color.Black,
    onError = Color.White,
    background = Color.Black,
    onBackground = TextPrimary,
    surface = SurfaceCard,
    onSurface = TextPrimary
)
