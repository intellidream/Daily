package com.intellidream.daily.presentation.dashboard

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.FormatQuote
import androidx.compose.material.icons.rounded.SelfImprovement
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.MonkeyMascotView
import com.intellidream.daily.designsystem.MonkeySize
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.health.HealthDataRepository
import com.intellidream.daily.model.DashboardWidgetSize
import com.intellidream.daily.model.MonkeyMood
import com.intellidream.daily.model.StressAnalysisResult
import com.intellidream.daily.model.StressLevel

/**
 * Modular Stress & Mind Balance Card on the main Dashboard.
 * 1:1 Kotlin/Compose port of iOS [StressDashboardCard.swift].
 * Adaptively renders across Small (1x1), Wide (2x1), Tall (1x2), and Large (2x2) modular sizes.
 */
@Composable
fun StressDashboardCard(
    size: DashboardWidgetSize,
    repository: HealthDataRepository,
    onTap: () -> Unit,
    onLongClick: (() -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    val score by repository.currentStressScore.collectAsState()
    val level by repository.currentStressLevel.collectAsState()
    val analysis by repository.stressAnalysis.collectAsState()

    val cardHeight = when (size) {
        DashboardWidgetSize.Small -> 155.dp
        DashboardWidgetSize.Wide -> 160.dp
        DashboardWidgetSize.Tall -> 324.dp
        DashboardWidgetSize.Large -> 324.dp
    }

    GlassCard(
        modifier = modifier
            .fillMaxWidth()
            .height(cardHeight),
        cornerRadius = 20.dp,
        padding = if (size == DashboardWidgetSize.Small) 14.dp else 18.dp,
        onClick = onTap,
        onLongClick = onLongClick
    ) {
        when (size) {
            DashboardWidgetSize.Small -> SmallStressContent(score = score, level = level, analysis = analysis)
            DashboardWidgetSize.Wide -> WideStressContent(score = score, level = level, analysis = analysis)
            DashboardWidgetSize.Tall -> TallStressContent(score = score, level = level, analysis = analysis)
            DashboardWidgetSize.Large -> LargeStressContent(score = score, level = level, analysis = analysis)
        }
    }
}

// MARK: - Small (1x1) Compact Glance

@Composable
private fun SmallStressContent(
    score: Int,
    level: StressLevel,
    analysis: StressAnalysisResult?
) {
    val mood = analysis?.monkeyMood ?: MonkeyMood.CURIOUS
    val levelColor = Color(android.graphics.Color.parseColor(level.hexColor))

    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Icon(
                    imageVector = Icons.Rounded.SelfImprovement,
                    contentDescription = null,
                    tint = levelColor,
                    modifier = Modifier.size(14.dp)
                )
                Text(
                    text = "Stress",
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = levelColor
                )
            }

            MonkeyMascotView(
                mood = mood,
                size = MonkeySize.BADGE,
                animated = false,
                modifier = Modifier.size(24.dp)
            )
        }

        Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(
                text = "$score",
                fontSize = 28.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White
            )
            Text(
                text = level.displayName.uppercase(),
                fontSize = 10.sp,
                fontWeight = FontWeight.Bold,
                color = levelColor
            )
        }

        // Mini gauge
        val progress = (score / 100f).coerceIn(0.08f, 1f)
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(5.dp)
                .clip(CircleShape)
                .background(Color.White.copy(alpha = 0.12f))
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth(fraction = progress)
                    .fillMaxHeight()
                    .clip(CircleShape)
                    .background(
                        Brush.horizontalGradient(
                            colors = listOf(Color(0xFF00FFB2), levelColor)
                        )
                    )
            )
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = mood.displayName,
                fontSize = 10.sp,
                fontWeight = FontWeight.Medium,
                color = ThemeColors.fgMutedDark
            )
            val hrv = analysis?.currentHrvMs
            if (hrv != null) {
                Text(
                    text = "${hrv.toInt()}ms",
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color(0xFF00E5FF)
                )
            }
        }
    }
}

// MARK: - Wide (2x1) Standard Tile

@Composable
private fun WideStressContent(
    score: Int,
    level: StressLevel,
    analysis: StressAnalysisResult?
) {
    val mood = analysis?.monkeyMood ?: MonkeyMood.CURIOUS
    val levelColor = Color(android.graphics.Color.parseColor(level.hexColor))
    val para = analysis?.parasympatheticPercent ?: 65

    Row(
        modifier = Modifier.fillMaxSize(),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        MonkeyMascotView(
            mood = mood,
            size = MonkeySize.CARD,
            animated = true,
            modifier = Modifier.size(64.dp)
        )

        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(5.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "STRESS LEVEL",
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Black,
                    color = levelColor
                )

                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(levelColor.copy(alpha = 0.15f))
                        .padding(horizontal = 7.dp, vertical = 2.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .size(6.dp)
                            .clip(CircleShape)
                            .background(levelColor)
                    )
                    Text(
                        text = level.displayName,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        color = levelColor
                    )
                }
            }

            Row(
                verticalAlignment = Alignment.Bottom,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Text(
                    text = "$score",
                    fontSize = 26.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White
                )
                Text(
                    text = "/ 100",
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = ThemeColors.fgMutedDark,
                    modifier = Modifier.padding(bottom = 3.dp)
                )
                Spacer(modifier = Modifier.weight(1f))
                Text(
                    text = "$para% Recovery Tone",
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = Color(0xFF00FFB2),
                    modifier = Modifier.padding(bottom = 3.dp)
                )
            }

            Text(
                text = mood.adviceQuote,
                fontSize = 11.5.sp,
                fontWeight = FontWeight.Medium,
                color = Color.White.copy(alpha = 0.85f),
                maxLines = 1
            )
        }
    }
}

// MARK: - Tall (1x2) Vertical Tile

@Composable
private fun TallStressContent(
    score: Int,
    level: StressLevel,
    analysis: StressAnalysisResult?
) {
    val mood = analysis?.monkeyMood ?: MonkeyMood.CURIOUS
    val levelColor = Color(android.graphics.Color.parseColor(level.hexColor))

    Column(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Icon(
                    imageVector = Icons.Rounded.SelfImprovement,
                    contentDescription = null,
                    tint = levelColor,
                    modifier = Modifier.size(14.dp)
                )
                Text(
                    text = "Stress",
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    color = levelColor
                )
            }
            Text(
                text = level.displayName,
                fontSize = 10.sp,
                fontWeight = FontWeight.Bold,
                color = levelColor
            )
        }

        MonkeyMascotView(
            mood = mood,
            size = MonkeySize.CARD,
            animated = true,
            modifier = Modifier.size(64.dp)
        )

        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            Text(
                text = "$score",
                fontSize = 32.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White
            )
            Text(
                text = mood.displayName,
                fontSize = 11.sp,
                fontWeight = FontWeight.SemiBold,
                color = ThemeColors.fgMutedDark
            )
        }

        HorizontalDivider(color = Color.White.copy(alpha = 0.08f))

        Text(
            text = mood.adviceQuote,
            fontSize = 11.sp,
            fontWeight = FontWeight.Medium,
            color = Color.White.copy(alpha = 0.85f),
            textAlign = TextAlign.Center,
            maxLines = 3
        )
    }
}

// MARK: - Large (2x2) Full Feature Card

@Composable
private fun LargeStressContent(
    score: Int,
    level: StressLevel,
    analysis: StressAnalysisResult?
) {
    val mood = analysis?.monkeyMood ?: MonkeyMood.CURIOUS
    val levelColor = Color(android.graphics.Color.parseColor(level.hexColor))
    val para = analysis?.parasympatheticPercent ?: 65
    val symp = analysis?.sympatheticPercent ?: 35
    val hrv = analysis?.currentHrvMs ?: 48.0

    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            MonkeyMascotView(
                mood = mood,
                size = MonkeySize.CARD,
                animated = true,
                modifier = Modifier.size(72.dp)
            )

            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "STRESS & AUTONOMIC TONE",
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Black,
                        color = levelColor
                    )
                    Text(
                        text = level.displayName.uppercase(),
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        color = levelColor,
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(levelColor.copy(alpha = 0.15f))
                            .padding(horizontal = 8.dp, vertical = 3.dp)
                    )
                }

                Row(
                    verticalAlignment = Alignment.Bottom,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Text(
                        text = "$score",
                        fontSize = 34.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                    Text(
                        text = "/ 100",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = ThemeColors.fgMutedDark,
                        modifier = Modifier.padding(bottom = 4.dp)
                    )
                    Spacer(modifier = Modifier.weight(1f))
                    Text(
                        text = "${hrv.toInt()} ms HRV",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color(0xFF00E5FF),
                        modifier = Modifier.padding(bottom = 4.dp)
                    )
                }
            }
        }

        // Autonomic Split Bar
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(6.dp)
                .clip(CircleShape),
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Box(
                modifier = Modifier
                    .weight(para.toFloat().coerceAtLeast(1f))
                    .fillMaxHeight()
                    .background(Color(0xFF00FFB2))
            )
            Box(
                modifier = Modifier
                    .weight(symp.toFloat().coerceAtLeast(1f))
                    .fillMaxHeight()
                    .background(Color(0xFFFFA726))
            )
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = "$para% Rest & Digest",
                fontSize = 10.sp,
                fontWeight = FontWeight.Bold,
                color = Color(0xFF00FFB2)
            )
            Text(
                text = "$symp% Arousal",
                fontSize = 10.sp,
                fontWeight = FontWeight.Bold,
                color = Color(0xFFFFA726)
            )
        }

        HorizontalDivider(color = Color.White.copy(alpha = 0.08f))

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.Top
        ) {
            Icon(
                imageVector = Icons.Rounded.FormatQuote,
                contentDescription = null,
                tint = levelColor,
                modifier = Modifier.size(16.dp)
            )
            Text(
                text = mood.adviceQuote,
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
                color = Color.White.copy(alpha = 0.9f),
                lineHeight = 16.sp
            )
        }
    }
}
