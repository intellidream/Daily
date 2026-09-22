package com.intellidream.daily.presentation.health

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowDropDown
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.FitnessCenter
import androidx.compose.material.icons.rounded.FormatQuote
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.Nightlight
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.SelfImprovement
import androidx.compose.material.icons.rounded.ShowChart
import androidx.compose.material.icons.rounded.Stop
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material.icons.rounded.Waves
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.MonkeyMascotView
import com.intellidream.daily.designsystem.MonkeySize
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.BreathingProtocol
import com.intellidream.daily.model.IntradayStressPoint
import com.intellidream.daily.model.MonkeyMood
import com.intellidream.daily.model.SleepSession
import com.intellidream.daily.model.StressAnalysisResult
import com.intellidream.daily.model.StressLevel
import kotlinx.coroutines.delay
import java.util.Locale
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Master Stress Studio screen integrating autonomic tone analysis,
 * the expressive stylized monkey mascot, intraday timeline, and interactive breathwork.
 * 1:1 Kotlin/Compose port of iOS [StressStudioView.swift].
 */
@Composable
fun StressStudioView(
    stressScore: Int,
    stressLevel: StressLevel,
    stressAnalysis: StressAnalysisResult?,
    intradayStress: List<IntradayStressPoint>,
    primarySleep: SleepSession?,
    modifier: Modifier = Modifier
) {
    val haptic = LocalHapticFeedback.current

    // Interactive Breathwork State
    var selectedProtocol by remember { mutableStateOf(BreathingProtocol.PHYSIOLOGICAL_SIGH) }
    var isBreathingActive by remember { mutableStateOf(false) }
    var breathPhaseText by remember { mutableStateOf("Ready to begin") }
    var breathTargetScale by remember { mutableFloatStateOf(1.0f) }
    var breathSecondsRemaining by remember { mutableIntStateOf(4) }
    var breathCycleCount by remember { mutableIntStateOf(0) }

    val animatedBubbleScale by animateFloatAsState(
        targetValue = breathTargetScale,
        animationSpec = tween(
            durationMillis = if (selectedProtocol == BreathingProtocol.PHYSIOLOGICAL_SIGH) 1500 else 3500,
            easing = FastOutSlowInEasing
        ),
        label = "breathBubbleScale"
    )

    // Breathing Session Coroutine
    LaunchedEffect(isBreathingActive, selectedProtocol) {
        if (!isBreathingActive) {
            breathPhaseText = "Ready to begin"
            breathTargetScale = 1.0f
            breathSecondsRemaining = 4
            breathCycleCount = 0
            return@LaunchedEffect
        }

        while (isBreathingActive) {
            when (selectedProtocol) {
                BreathingProtocol.PHYSIOLOGICAL_SIGH -> {
                    // Inhale 1
                    breathPhaseText = "Inhale deep"
                    breathTargetScale = 1.25f
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    for (s in 2 downTo 1) {
                        breathSecondsRemaining = s
                        delay(1000)
                    }

                    // Inhale 2 (Sniff at top)
                    breathPhaseText = "Sharp sniff"
                    breathTargetScale = 1.38f
                    haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    breathSecondsRemaining = 1
                    delay(1000)

                    // Slow Exhale
                    breathPhaseText = "Slow exhale sigh"
                    breathTargetScale = 0.92f
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    for (s in 5 downTo 1) {
                        breathSecondsRemaining = s
                        delay(1000)
                    }
                }

                BreathingProtocol.BOX_BREATHING -> {
                    // Inhale 4s
                    breathPhaseText = "Inhale"
                    breathTargetScale = 1.35f
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    for (s in 4 downTo 1) {
                        breathSecondsRemaining = s
                        delay(1000)
                    }
                    // Hold 4s
                    breathPhaseText = "Hold"
                    breathTargetScale = 1.35f
                    for (s in 4 downTo 1) {
                        breathSecondsRemaining = s
                        delay(1000)
                    }
                    // Exhale 4s
                    breathPhaseText = "Exhale"
                    breathTargetScale = 0.95f
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    for (s in 4 downTo 1) {
                        breathSecondsRemaining = s
                        delay(1000)
                    }
                    // Hold 4s
                    breathPhaseText = "Hold empty"
                    breathTargetScale = 0.95f
                    for (s in 4 downTo 1) {
                        breathSecondsRemaining = s
                        delay(1000)
                    }
                }

                BreathingProtocol.RESONANCE_FLOW -> {
                    // Inhale 5s
                    breathPhaseText = "Smooth inhale"
                    breathTargetScale = 1.32f
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    for (s in 5 downTo 1) {
                        breathSecondsRemaining = s
                        delay(1000)
                    }
                    // Exhale 5s
                    breathPhaseText = "Smooth exhale"
                    breathTargetScale = 0.95f
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    for (s in 5 downTo 1) {
                        breathSecondsRemaining = s
                        delay(1000)
                    }
                }

                BreathingProtocol.RELAX_478 -> {
                    // Inhale 4s
                    breathPhaseText = "Inhale"
                    breathTargetScale = 1.32f
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    for (s in 4 downTo 1) {
                        breathSecondsRemaining = s
                        delay(1000)
                    }
                    // Hold 7s
                    breathPhaseText = "Hold gently"
                    breathTargetScale = 1.32f
                    for (s in 7 downTo 1) {
                        breathSecondsRemaining = s
                        delay(1000)
                    }
                    // Exhale 8s
                    breathPhaseText = "Long exhale"
                    breathTargetScale = 0.92f
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    for (s in 8 downTo 1) {
                        breathSecondsRemaining = s
                        delay(1000)
                    }
                }
            }

            breathCycleCount++
            if (breathCycleCount >= selectedProtocol.cyclesRecommended) {
                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                isBreathingActive = false
                breathPhaseText = "Session Complete!"
                breathTargetScale = 1.0f
                delay(2000)
                breathPhaseText = "Ready to begin"
            }
        }
    }

    DisposableEffect(Unit) {
        onDispose {
            isBreathingActive = false
        }
    }

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // 1. Hero Mascot & Stress Dial Card
        HeroStressCard(
            score = stressScore,
            level = stressLevel,
            analysis = stressAnalysis
        )

        // 2. Autonomic Balance Card (Sympathetic vs Parasympathetic)
        AutonomicBalanceCard(analysis = stressAnalysis)

        // 3. Biometric Physiological Drivers Grid (2x2 with fixed 104dp height)
        PhysiologicalDriversGrid(
            analysis = stressAnalysis,
            primarySleep = primarySleep
        )

        // 4. Intraday Stress Curve (24-Hour Timeline)
        IntradayTimelineCard(
            intraday = intradayStress,
            dailyAverage = stressAnalysis?.dailyAverageScore ?: stressScore
        )

        // 5. Interactive Guided Breathwork Studio
        InteractiveBreathworkCard(
            selectedProtocol = selectedProtocol,
            onSelectProtocol = {
                selectedProtocol = it
                if (isBreathingActive) isBreathingActive = false
            },
            isBreathingActive = isBreathingActive,
            onToggleBreathing = {
                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                isBreathingActive = !isBreathingActive
            },
            phaseText = breathPhaseText,
            bubbleScale = animatedBubbleScale,
            secondsRemaining = breathSecondsRemaining,
            cycleCount = breathCycleCount
        )

        // 6. Science-Backed Guidance Card
        ScienceGuidanceCard(level = stressLevel, analysis = stressAnalysis)
    }
}

// MARK: - 1. Hero Mascot & Stress Dial Card

@Composable
private fun HeroStressCard(
    score: Int,
    level: StressLevel,
    analysis: StressAnalysisResult?
) {
    val mood = analysis?.monkeyMood ?: MonkeyMood.fromLevel(level)
    val levelColor = Color(android.graphics.Color.parseColor(level.hexColor))

    GlassCard(
        modifier = Modifier.fillMaxWidth(),
        cornerRadius = 24.dp,
        padding = 20.dp
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(18.dp)
            ) {
                // Stylized Vector Mascot
                Box(
                    modifier = Modifier.size(84.dp),
                    contentAlignment = Alignment.Center
                ) {
                    MonkeyMascotView(
                        mood = mood,
                        size = MonkeySize.CARD,
                        animated = true
                    )
                }

                // Score Dial & Status Pill
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(
                        verticalAlignment = Alignment.Bottom,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Text(
                            text = "$score",
                            color = Color.White,
                            fontSize = 42.sp,
                            fontWeight = FontWeight.Bold
                        )

                        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(
                                text = "/ 100",
                                color = ThemeColors.fgMutedDark,
                                fontSize = 13.sp,
                                fontWeight = FontWeight.SemiBold
                            )
                            Text(
                                text = "STRESS",
                                color = levelColor,
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Black
                            )
                        }
                    }

                    // Status Badge Pill
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(levelColor.copy(alpha = 0.15f))
                            .border(1.dp, levelColor.copy(alpha = 0.35f), CircleShape)
                            .padding(horizontal = 10.dp, vertical = 4.dp)
                    ) {
                        Box(
                            modifier = Modifier
                                .size(8.dp)
                                .clip(CircleShape)
                                .background(levelColor)
                        )

                        Text(
                            text = level.displayName.uppercase(),
                            color = levelColor,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold
                        )

                        Text(
                            text = "•",
                            color = Color.White.copy(alpha = 0.4f),
                            fontSize = 11.sp
                        )

                        Text(
                            text = mood.displayName,
                            color = Color.White.copy(alpha = 0.85f),
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Medium
                        )
                    }
                }
            }

            HorizontalDivider(
                color = Color.White.copy(alpha = 0.08f),
                thickness = 1.dp
            )

            // Monkey Contextual Advice Bubble
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.Top,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Icon(
                    imageVector = Icons.Rounded.FormatQuote,
                    contentDescription = null,
                    tint = levelColor,
                    modifier = Modifier.size(18.dp)
                )

                Text(
                    text = mood.adviceQuote,
                    color = Color.White.copy(alpha = 0.92f),
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium,
                    lineHeight = 18.sp
                )
            }
        }
    }
}

// MARK: - 2. Autonomic Balance Card

@Composable
private fun AutonomicBalanceCard(analysis: StressAnalysisResult?) {
    val para = analysis?.parasympatheticPercent ?: 65
    val symp = analysis?.sympatheticPercent ?: 35

    GlassCard(
        modifier = Modifier.fillMaxWidth(),
        cornerRadius = 20.dp,
        padding = 18.dp
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Waves,
                        contentDescription = null,
                        tint = ThemeColors.accentCyan,
                        modifier = Modifier.size(16.dp)
                    )
                    Text(
                        text = "Autonomic Tone Balance",
                        color = ThemeColors.accentCyan,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold
                    )
                }

                Text(
                    text = if (para >= 55) "Recovery Dominant" else "Arousal Dominant",
                    color = if (para >= 55) Color(0xFF00FFB2) else Color(0xFFFFA726),
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }

            // Dual Stacked Progress Bar
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(10.dp),
                horizontalArrangement = Arrangement.spacedBy(3.dp)
            ) {
                // Parasympathetic
                Box(
                    modifier = Modifier
                        .weight(max(0.05f, para / 100f))
                        .height(10.dp)
                        .clip(RoundedCornerShape(4.dp))
                        .background(
                            brush = Brush.horizontalGradient(
                                listOf(Color(0xFF00E5FF), Color(0xFF00FFB2))
                            )
                        )
                )

                // Sympathetic
                Box(
                    modifier = Modifier
                        .weight(max(0.05f, symp / 100f))
                        .height(10.dp)
                        .clip(RoundedCornerShape(4.dp))
                        .background(
                            brush = Brush.horizontalGradient(
                                listOf(Color(0xFFFFA726), Color(0xFFFF5252))
                            )
                        )
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Column(horizontalAlignment = Alignment.Start) {
                    Text(
                        text = "$para% Parasympathetic",
                        color = Color(0xFF00FFB2),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        text = "Rest, repair & heart adaptability",
                        color = ThemeColors.fgMutedDark,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Medium
                    )
                }

                Column(horizontalAlignment = Alignment.End) {
                    Text(
                        text = "$symp% Sympathetic",
                        color = Color(0xFFFFA726),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        text = "Arousal, energy & cognitive load",
                        color = ThemeColors.fgMutedDark,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Medium
                    )
                }
            }
        }
    }
}

// MARK: - 3. Biometric Physiological Drivers Grid

@Composable
private fun PhysiologicalDriversGrid(
    analysis: StressAnalysisResult?,
    primarySleep: SleepSession?
) {
    val baselineHrv = analysis?.baselineHrvMs ?: 45.0
    val currentHrv = analysis?.currentHrvMs ?: 48.0
    val hrvDelta = analysis?.hrvDeltaPercent ?: 6.0
    val restingBpm = analysis?.restingHeartRateBpm ?: 60.0
    val hrDelta = analysis?.heartRateElevationBpm ?: 3.0

    val sleepScore = primarySleep?.sleepScore ?: 82
    val sleepDurationFormatted = primarySleep?.totalAsleepFormatted ?: "7h 20m"

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // Driver 1: HRV
            DriverTile(
                title = "HRV (SDNN)",
                valueText = String.format(Locale.US, "%.0f ms", currentHrv),
                deltaText = String.format(Locale.US, "%+.0f%% vs base", hrvDelta),
                isPositive = hrvDelta >= 0,
                subtitle = "Baseline: ${baselineHrv.toInt()} ms",
                icon = Icons.Rounded.Waves,
                tintColor = Color(0xFF00E5FF),
                modifier = Modifier.weight(1f)
            )

            // Driver 2: Resting HR
            DriverTile(
                title = "Resting Heart Rate",
                valueText = "${restingBpm.toInt()} bpm",
                deltaText = "Baseline reference",
                isPositive = true,
                subtitle = "Cardiovascular floor",
                icon = Icons.Rounded.Favorite,
                tintColor = Color(0xFFFF5252),
                modifier = Modifier.weight(1f)
            )
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // Driver 3: Sedentary HR Elevation
            DriverTile(
                title = "Sedentary Elevation",
                valueText = String.format(Locale.US, "%+.0f bpm", hrDelta),
                deltaText = if (hrDelta <= 6) "Calm arousal" else "Elevated tension",
                isPositive = hrDelta <= 8,
                subtitle = "Resting baseline delta",
                icon = Icons.Rounded.LocalFireDepartment,
                tintColor = Color(0xFFFFA726),
                modifier = Modifier.weight(1f)
            )

            // Driver 4: Sleep Recovery
            DriverTile(
                title = "Sleep Readiness",
                valueText = "$sleepScore%",
                deltaText = if (sleepScore >= 75) "Optimal recovery" else "Sleep debt",
                isPositive = sleepScore >= 75,
                subtitle = "$sleepDurationFormatted total",
                icon = Icons.Rounded.Nightlight,
                tintColor = ThemeColors.accentPurple,
                modifier = Modifier.weight(1f)
            )
        }
    }
}

@Composable
private fun DriverTile(
    title: String,
    valueText: String,
    deltaText: String,
    isPositive: BoolOrBoolean,
    subtitle: String,
    icon: ImageVector,
    tintColor: Color,
    modifier: Modifier = Modifier
) {
    GlassCard(
        modifier = modifier.height(104.dp),
        cornerRadius = 16.dp,
        padding = 14.dp
    ) {
        Column(
            modifier = Modifier.fillMaxSize(),
            verticalArrangement = Arrangement.SpaceBetween,
            horizontalAlignment = Alignment.Start
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = tintColor,
                    modifier = Modifier.size(13.dp)
                )
                Text(
                    text = title,
                    color = ThemeColors.fgMutedDark,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1
                )
            }

            Text(
                text = valueText,
                color = Color.White,
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 1
            )

            Text(
                text = deltaText,
                color = if (isPositive) Color(0xFF00FFB2) else Color(0xFFFFA726),
                fontSize = 10.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 1
            )

            Text(
                text = subtitle,
                color = Color.White.copy(alpha = 0.5f),
                fontSize = 9.5.sp,
                fontWeight = FontWeight.Medium,
                maxLines = 1
            )
        }
    }
}

// MARK: - 4. Intraday Stress Timeline

@Composable
private fun IntradayTimelineCard(
    intraday: List<IntradayStressPoint>,
    dailyAverage: Int
) {
    val displayPoints = if (intraday.isNotEmpty()) intraday else generateMockIntraday()

    GlassCard(
        modifier = Modifier.fillMaxWidth(),
        cornerRadius = 20.dp,
        padding = 18.dp
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Icon(
                        imageVector = Icons.Rounded.ShowChart,
                        contentDescription = null,
                        tint = ThemeColors.accentBlue,
                        modifier = Modifier.size(16.dp)
                    )
                    Text(
                        text = "Intraday Stress Rhythm",
                        color = ThemeColors.accentBlue,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold
                    )
                }

                Text(
                    text = "Daily Avg: $dailyAverage",
                    color = ThemeColors.fgMutedDark,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }

            // Hourly Bar Chart
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState())
                    .padding(vertical = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.Bottom
            ) {
                displayPoints.forEach { pt ->
                    val barH = max(8.0f, (pt.score * 0.70f)).dp
                    val barColor = Color(android.graphics.Color.parseColor(pt.level.hexColor))

                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        Box(
                            modifier = Modifier
                                .size(14.dp, 70.dp)
                                .clip(CircleShape)
                                .background(Color.White.copy(alpha = 0.08f)),
                            contentAlignment = Alignment.BottomCenter
                        ) {
                            Box(
                                modifier = Modifier
                                    .size(14.dp, barH)
                                    .clip(CircleShape)
                                    .background(
                                        brush = Brush.verticalGradient(
                                            listOf(barColor, barColor.copy(alpha = 0.6f))
                                        )
                                    )
                            )
                        }

                        Text(
                            text = "${pt.hour}",
                            color = ThemeColors.fgMutedDark,
                            fontSize = 9.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }
            }
        }
    }
}

// MARK: - 5. Interactive Guided Breathwork Studio

@Composable
private fun InteractiveBreathworkCard(
    selectedProtocol: BreathingProtocol,
    onSelectProtocol: (BreathingProtocol) -> Unit,
    isBreathingActive: Boolean,
    onToggleBreathing: () -> Unit,
    phaseText: String,
    bubbleScale: Float,
    secondsRemaining: Int,
    cycleCount: Int
) {
    var expandedMenu by remember { mutableStateOf(false) }

    GlassCard(
        modifier = Modifier.fillMaxWidth(),
        cornerRadius = 22.dp,
        padding = 20.dp
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // Header with Dropdown
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Icon(
                        imageVector = Icons.Rounded.SelfImprovement,
                        contentDescription = null,
                        tint = ThemeColors.accentCyan,
                        modifier = Modifier.size(18.dp)
                    )
                    Text(
                        text = "Guided Autonomic Breathwork",
                        color = ThemeColors.accentCyan,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold
                    )
                }

                // Dropdown Menu Button
                Box {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(ThemeColors.accentCyan.copy(alpha = 0.15f))
                            .clickable { expandedMenu = true }
                            .padding(horizontal = 10.dp, vertical = 5.dp)
                    ) {
                        Text(
                            text = selectedProtocol.title,
                            color = ThemeColors.accentCyan,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold
                        )
                        Icon(
                            imageVector = Icons.Rounded.ArrowDropDown,
                            contentDescription = null,
                            tint = ThemeColors.accentCyan,
                            modifier = Modifier.size(16.dp)
                        )
                    }

                    DropdownMenu(
                        expanded = expandedMenu,
                        onDismissRequest = { expandedMenu = false },
                        modifier = Modifier.background(Color(0xFF0F1B30))
                    ) {
                        BreathingProtocol.entries.forEach { proto ->
                            DropdownMenuItem(
                                text = {
                                    Text(
                                        text = proto.title,
                                        color = if (selectedProtocol == proto) ThemeColors.accentCyan else Color.White,
                                        fontWeight = if (selectedProtocol == proto) FontWeight.Bold else FontWeight.Normal
                                    )
                                },
                                onClick = {
                                    onSelectProtocol(proto)
                                    expandedMenu = false
                                }
                            )
                        }
                    }
                }
            }

            Text(
                text = selectedProtocol.description,
                color = ThemeColors.fgMutedDark,
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
                textAlign = TextAlign.Center,
                lineHeight = 16.sp,
                modifier = Modifier.padding(horizontal = 8.dp)
            )

            // Animated Breath Bubble
            Box(
                modifier = Modifier.size(140.dp),
                contentAlignment = Alignment.Center
            ) {
                // Fixed outline circle
                Box(
                    modifier = Modifier
                        .size(140.dp)
                        .border(2.dp, ThemeColors.accentCyan.copy(alpha = 0.2f), CircleShape)
                )

                // Scaling glowing bubble
                Box(
                    modifier = Modifier
                        .size(130.dp)
                        .scale(bubbleScale)
                        .clip(CircleShape)
                        .background(
                            brush = Brush.radialGradient(
                                listOf(
                                    ThemeColors.accentCyan.copy(alpha = 0.40f),
                                    ThemeColors.accentBlue.copy(alpha = 0.15f),
                                    Color.Transparent
                                )
                            )
                        )
                )

                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Text(
                        text = phaseText,
                        color = Color.White,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold,
                        textAlign = TextAlign.Center
                    )

                    if (isBreathingActive) {
                        Text(
                            text = "${secondsRemaining}s",
                            color = ThemeColors.accentCyan,
                            fontSize = 24.sp,
                            fontWeight = FontWeight.Black
                        )
                    } else {
                        Icon(
                            imageVector = Icons.Rounded.PlayArrow,
                            contentDescription = "Start",
                            tint = ThemeColors.accentCyan,
                            modifier = Modifier.size(28.dp)
                        )
                    }
                }
            }

            // Controls
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(
                            if (isBreathingActive) Color(0xFFFF5252).copy(alpha = 0.2f)
                            else ThemeColors.accentCyan.copy(alpha = 0.2f)
                        )
                        .border(
                            1.dp,
                            if (isBreathingActive) Color(0xFFFF5252) else ThemeColors.accentCyan,
                            CircleShape
                        )
                        .clickable(onClick = onToggleBreathing)
                        .padding(horizontal = 20.dp, vertical = 10.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Icon(
                            imageVector = if (isBreathingActive) Icons.Rounded.Stop else Icons.Rounded.PlayArrow,
                            contentDescription = null,
                            tint = if (isBreathingActive) Color(0xFFFF5252) else ThemeColors.accentCyan,
                            modifier = Modifier.size(18.dp)
                        )
                        Text(
                            text = if (isBreathingActive) "Stop Session" else "Start Protocol",
                            color = if (isBreathingActive) Color(0xFFFF5252) else ThemeColors.accentCyan,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }
            }
        }
    }
}

// MARK: - 6. Science-Backed Guidance Card

@Composable
private fun ScienceGuidanceCard(
    level: StressLevel,
    analysis: StressAnalysisResult?
) {
    val levelColor = Color(android.graphics.Color.parseColor(level.hexColor))

    GlassCard(
        modifier = Modifier.fillMaxWidth(),
        cornerRadius = 20.dp,
        padding = 18.dp
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Icon(
                    imageVector = Icons.Rounded.Tune,
                    contentDescription = null,
                    tint = levelColor,
                    modifier = Modifier.size(16.dp)
                )
                Text(
                    text = "Clinical Context & Science",
                    color = levelColor,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Bold
                )
            }

            Text(
                text = level.clinicalDescription,
                color = Color.White.copy(alpha = 0.90f),
                fontSize = 12.5.sp,
                lineHeight = 18.sp
            )

            Text(
                text = "Stress index is computed in real-time from Heart Rate Variability (SDNN), sedentary cardiac elevation, and nocturnal recovery sleep debt.",
                color = ThemeColors.fgMutedDark,
                fontSize = 11.sp,
                lineHeight = 15.sp
            )
        }
    }
}

private fun generateMockIntraday(): List<IntradayStressPoint> {
    val list = mutableListOf<IntradayStressPoint>()
    val baseTime = System.currentTimeMillis()
    val pattern = listOf(22, 20, 18, 19, 24, 30, 36, 42, 48, 52, 46, 38, 32, 28)
    for (i in pattern.indices) {
        val score = pattern[i]
        list.add(
            IntradayStressPoint(
                timestamp = baseTime + (i * 3600_000L),
                hour = i + 7,
                score = score,
                level = StressLevel.from(score),
                hrvMs = 45.0 + (50 - score) * 0.4,
                heartRateBpm = 60.0 + (score * 0.2),
                isSedentary = true
            )
        )
    }
    return list
}

private typealias BoolOrBoolean = Boolean
