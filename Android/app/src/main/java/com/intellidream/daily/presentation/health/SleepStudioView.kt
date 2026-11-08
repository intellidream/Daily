package com.intellidream.daily.presentation.health

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Bed
import androidx.compose.material.icons.rounded.Bedtime
import androidx.compose.material.icons.rounded.Brightness4
import androidx.compose.material.icons.rounded.Hotel
import androidx.compose.material.icons.rounded.Nightlight
import androidx.compose.material.icons.rounded.RemoveRedEye
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.WbSunny
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.launch
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.DeviceSource
import com.intellidream.daily.model.NapSession
import com.intellidream.daily.model.SleepAIContext
import com.intellidream.daily.model.SleepActionableTip
import com.intellidream.daily.model.SleepRecoveryVerdict
import com.intellidream.daily.model.SleepSession
import com.intellidream.daily.model.SleepStageType

@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
fun SleepStudioView(
    session: SleepSession?,
    verdict: SleepRecoveryVerdict?,
    aiContext: SleepAIContext?,
    tips: List<SleepActionableTip>,
    daytimeNaps: List<NapSession>,
    onScrollToHypnogram: () -> Unit = {},
    modifier: Modifier = Modifier
) {
    val bringIntoViewRequester = remember { BringIntoViewRequester() }
    val scope = rememberCoroutineScope()
    val handleScrollToHypnogram: () -> Unit = {
        onScrollToHypnogram()
        scope.launch {
            bringIntoViewRequester.bringIntoView()
        }
    }

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        if (session != null) {
            // 1. Hero Sleep Score & Schedule Card
            HeroSleepScoreCard(
                session = session,
                onScoreRingTapped = handleScrollToHypnogram
            )

            // 2. Recovery Verdict & Readiness Card
            if (verdict != null) {
                SleepVerdictCard(verdict = verdict)
            }

            // 3. AI Sleep Intelligence Companion Card
            if (aiContext != null) {
                SleepAICoachCard(aiContext = aiContext, session = session)
            }

            // 4. Actionable Clinical Sleep Hygiene Tips
            if (tips.isNotEmpty()) {
                SleepAdviceCard(tips = tips)
            }

            // 5. Clinical Hypnogram Container Card
            Box(modifier = Modifier.fillMaxWidth().bringIntoViewRequester(bringIntoViewRequester)) {
                HypnogramContainerCard(session = session)
            }

            // 6. Sleep Architecture Breakdown Grid
            ArchitectureMetricsGrid(session = session)
        } else {
            EmptySleepCard()
        }

        // 7. Daytime Naps Section
        if (daytimeNaps.isNotEmpty()) {
            DaytimeNapsSection(naps = daytimeNaps)
        }
    }
}

// MARK: - Hero Sleep Score Card

@Composable
private fun HeroSleepScoreCard(
    session: SleepSession,
    onScoreRingTapped: () -> Unit
) {
    GlassCard(
        modifier = Modifier.fillMaxWidth(),
        cornerRadius = 22.dp,
        padding = 20.dp
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Text(
                            text = "LAST NIGHT'S SLEEP",
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold,
                            color = ThemeColors.accentCyan
                        )

                        // Source Device Origin Chip
                        val src = DeviceSource.from(session.sourceDevice)
                        val deviceIcon = getDeviceIcon(src.iconType)
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp),
                            modifier = Modifier
                                .clip(CircleShape)
                                .background(Color.White.copy(alpha = 0.1f))
                                .padding(horizontal = 8.dp, vertical = 3.dp)
                        ) {
                            Icon(
                                imageVector = deviceIcon,
                                contentDescription = null,
                                tint = Color.White.copy(alpha = 0.85f),
                                modifier = Modifier.size(11.dp)
                            )
                            Text(
                                text = session.sourceDevice,
                                fontSize = 10.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = Color.White.copy(alpha = 0.85f)
                            )
                        }
                    }

                    Text(
                        text = session.totalAsleepFormatted,
                        fontSize = 32.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )

                    Text(
                        text = "${session.timeInBedFormatted} in bed • ${session.efficiencyPercent}% efficiency",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Medium,
                        color = ThemeColors.fgMutedDark
                    )
                }

                // Radial Score Ring
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier
                        .size(76.dp)
                        .clickable { onScoreRingTapped() }
                ) {
                    Canvas(modifier = Modifier.size(76.dp)) {
                        val strokeWidth = 8.dp.toPx()
                        val diameter = size.minDimension - strokeWidth
                        val topLeft = Offset(strokeWidth / 2f, strokeWidth / 2f)
                        val arcSize = Size(diameter, diameter)

                        // Track
                        drawArc(
                            color = Color.White.copy(alpha = 0.08f),
                            startAngle = 0f,
                            sweepAngle = 360f,
                            useCenter = false,
                            topLeft = topLeft,
                            size = arcSize,
                            style = Stroke(width = strokeWidth)
                        )

                        // Angular Gradient Active Arc
                        val sweepGradient = Brush.sweepGradient(
                            colors = listOf(
                                ThemeColors.accentCyan,
                                Color(0xFF2979FF),
                                ThemeColors.accentPurple,
                                ThemeColors.accentCyan
                            ),
                            center = center
                        )
                        val sweepAngle = (session.sleepScore.coerceIn(0, 100) / 100f) * 360f
                        if (sweepAngle > 0f) {
                            drawArc(
                                brush = sweepGradient,
                                startAngle = -90f,
                                sweepAngle = sweepAngle,
                                useCenter = false,
                                topLeft = topLeft,
                                size = arcSize,
                                style = Stroke(width = strokeWidth, cap = StrokeCap.Round)
                            )
                        }
                    }
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(0.dp)
                    ) {
                        Text(
                            text = "${session.sleepScore}",
                            fontSize = 22.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White
                        )
                        Text(
                            text = session.sleepQualityRating,
                            fontSize = 9.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = ThemeColors.accentCyan
                        )
                    }
                }
            }

            HorizontalDivider(color = Color.White.copy(alpha = 0.08f))

            // Bedtime, Wake Time & Restorative Row
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Bedtime
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Nightlight,
                        contentDescription = null,
                        tint = ThemeColors.accentPurple,
                        modifier = Modifier.size(16.dp)
                    )
                    Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                        Text("Bedtime", fontSize = 11.sp, fontWeight = FontWeight.Medium, color = ThemeColors.fgMutedDark)
                        Text(session.bedtimeFormatted, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Color.White)
                    }
                }

                // Wake Time
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Icon(
                        imageVector = Icons.Rounded.WbSunny,
                        contentDescription = null,
                        tint = Color(0xFFFFD600),
                        modifier = Modifier.size(16.dp)
                    )
                    Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                        Text("Wake Time", fontSize = 11.sp, fontWeight = FontWeight.Medium, color = ThemeColors.fgMutedDark)
                        Text(session.wakeTimeFormatted, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Color.White)
                    }
                }

                // Restorative
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Icon(
                        imageVector = Icons.Rounded.AutoAwesome,
                        contentDescription = null,
                        tint = ThemeColors.accentCyan,
                        modifier = Modifier.size(16.dp)
                    )
                    Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                        Text("Restorative", fontSize = 11.sp, fontWeight = FontWeight.Medium, color = ThemeColors.fgMutedDark)
                        Text("${session.restorativePercent}%", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Color.White)
                    }
                }
            }
        }
    }
}

// MARK: - Hypnogram Container Card

@Composable
private fun HypnogramContainerCard(session: SleepSession) {
    val hasHypnogram = session.hasGranularHypnogram || session.stages.isNotEmpty()

    GlassCard(
        modifier = Modifier.fillMaxWidth(),
        cornerRadius = 20.dp,
        padding = 18.dp
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = if (hasHypnogram) "SLEEP HYPNOGRAM" else "STAGE PROPORTIONS",
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    color = ThemeColors.accentCyan
                )

                if (hasHypnogram) {
                    Text(
                        text = "Tap stage to inspect",
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Medium,
                        color = ThemeColors.fgMutedDark
                    )
                }
            }

            if (hasHypnogram) {
                SleepHypnogramView(session = session)
            } else {
                StageProportionBar(session = session)
            }

            // Legend Pills
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                LegendPill(
                    modifier = Modifier.weight(1f),
                    label = "Deep",
                    colorHex = SleepStageType.DEEP.hexColor,
                    valStr = session.deepFormatted,
                    pct = session.deepPercent
                )
                LegendPill(
                    modifier = Modifier.weight(1f),
                    label = "REM",
                    colorHex = SleepStageType.REM.hexColor,
                    valStr = session.remFormatted,
                    pct = session.remPercent
                )
                LegendPill(
                    modifier = Modifier.weight(1f),
                    label = "Light",
                    colorHex = SleepStageType.LIGHT.hexColor,
                    valStr = session.lightFormatted,
                    pct = session.lightPercent
                )
                LegendPill(
                    modifier = Modifier.weight(1f),
                    label = "Awake",
                    colorHex = SleepStageType.AWAKE.hexColor,
                    valStr = session.awakeFormatted,
                    pct = session.awakePercent
                )
            }
        }
    }
}

@Composable
private fun StageProportionBar(session: SleepSession) {
    val total = maxOf(1.0, session.deepSeconds + session.remSeconds + session.lightSeconds + session.awakeSeconds)

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(18.dp)
            .clip(RoundedCornerShape(4.dp)),
        horizontalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        if (session.deepSeconds > 0) {
            Box(
                modifier = Modifier
                    .weight((session.deepSeconds / total).toFloat())
                    .fillMaxWidth()
                    .height(18.dp)
                    .background(Color(android.graphics.Color.parseColor(SleepStageType.DEEP.hexColor)))
            )
        }
        if (session.remSeconds > 0) {
            Box(
                modifier = Modifier
                    .weight((session.remSeconds / total).toFloat())
                    .fillMaxWidth()
                    .height(18.dp)
                    .background(Color(android.graphics.Color.parseColor(SleepStageType.REM.hexColor)))
            )
        }
        if (session.lightSeconds > 0) {
            Box(
                modifier = Modifier
                    .weight((session.lightSeconds / total).toFloat())
                    .fillMaxWidth()
                    .height(18.dp)
                    .background(Color(android.graphics.Color.parseColor(SleepStageType.LIGHT.hexColor)))
            )
        }
        if (session.awakeSeconds > 0) {
            Box(
                modifier = Modifier
                    .weight((session.awakeSeconds / total).toFloat())
                    .fillMaxWidth()
                    .height(18.dp)
                    .background(Color(android.graphics.Color.parseColor(SleepStageType.AWAKE.hexColor)))
            )
        }
    }
}

@Composable
private fun LegendPill(
    modifier: Modifier = Modifier,
    label: String,
    colorHex: String,
    valStr: String,
    pct: Int
) {
    val color = Color(android.graphics.Color.parseColor(colorHex))
    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Box(
            modifier = Modifier
                .size(8.dp)
                .clip(CircleShape)
                .background(color)
        )
        Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(
                text = "$label $pct%",
                fontSize = 10.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White
            )
            Text(
                text = valStr,
                fontSize = 9.sp,
                fontWeight = FontWeight.Medium,
                color = ThemeColors.fgMutedDark
            )
        }
    }
}

// MARK: - Architecture Metrics Grid

@Composable
private fun ArchitectureMetricsGrid(session: SleepSession) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            MetricTile(
                modifier = Modifier.weight(1f),
                title = "Deep Sleep",
                value = session.deepFormatted,
                subtitle = "${session.deepPercent}% of sleep",
                icon = Icons.Rounded.Nightlight,
                tint = Color(android.graphics.Color.parseColor(SleepStageType.DEEP.hexColor))
            )
            MetricTile(
                modifier = Modifier.weight(1f),
                title = "REM Sleep",
                value = session.remFormatted,
                subtitle = "${session.remPercent}% of sleep",
                icon = Icons.Rounded.AutoAwesome,
                tint = Color(android.graphics.Color.parseColor(SleepStageType.REM.hexColor))
            )
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            MetricTile(
                modifier = Modifier.weight(1f),
                title = "Light / Core",
                value = session.lightFormatted,
                subtitle = "${session.lightPercent}% of sleep",
                icon = Icons.Rounded.Bed,
                tint = Color(android.graphics.Color.parseColor(SleepStageType.LIGHT.hexColor))
            )
            MetricTile(
                modifier = Modifier.weight(1f),
                title = "Awakenings",
                value = "${session.awakeCount} times",
                subtitle = "${session.awakeFormatted} awake",
                icon = Icons.Rounded.RemoveRedEye,
                tint = Color(android.graphics.Color.parseColor(SleepStageType.AWAKE.hexColor))
            )
        }
    }
}

@Composable
private fun MetricTile(
    modifier: Modifier = Modifier,
    title: String,
    value: String,
    subtitle: String,
    icon: ImageVector,
    tint: Color
) {
    GlassCard(
        modifier = modifier,
        cornerRadius = 16.dp,
        padding = 14.dp
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = tint,
                    modifier = Modifier.size(15.dp)
                )
                Text(
                    text = title,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = ThemeColors.fgMutedDark
                )
            }

            Text(
                text = value,
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White
            )

            Text(
                text = subtitle,
                fontSize = 11.sp,
                fontWeight = FontWeight.Medium,
                color = tint.copy(alpha = 0.85f)
            )
        }
    }
}

// MARK: - Daytime Naps Section

@Composable
private fun DaytimeNapsSection(naps: List<NapSession>) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            modifier = Modifier.padding(start = 4.dp)
        ) {
            Icon(
                imageVector = Icons.Rounded.WbSunny,
                contentDescription = null,
                tint = Color(0xFFFFD600),
                modifier = Modifier.size(13.dp)
            )
            Text(
                text = "DAYTIME NAPS (${naps.size})",
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                color = ThemeColors.accentCyan
            )
        }

        naps.forEach { nap ->
            GlassCard(
                modifier = Modifier.fillMaxWidth(),
                cornerRadius = 16.dp,
                padding = 14.dp
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        Box(
                            modifier = Modifier
                                .size(36.dp)
                                .clip(CircleShape)
                                .background(ThemeColors.accentCyan.copy(alpha = 0.12f)),
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(
                                imageVector = Icons.Rounded.Bedtime,
                                contentDescription = null,
                                tint = ThemeColors.accentCyan,
                                modifier = Modifier.size(18.dp)
                            )
                        }

                        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(
                                text = "Nap Session",
                                fontSize = 14.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color.White
                            )
                            Text(
                                text = nap.timeRangeFormatted,
                                fontSize = 12.sp,
                                fontWeight = FontWeight.Medium,
                                color = ThemeColors.fgMutedDark
                            )
                        }
                    }

                    Column(
                        horizontalAlignment = Alignment.End,
                        verticalArrangement = Arrangement.spacedBy(2.dp)
                    ) {
                        Text(
                            text = nap.formattedDuration,
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Bold,
                            color = ThemeColors.accentCyan
                        )
                        Text(
                            text = nap.sourceDevice,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Medium,
                            color = ThemeColors.fgMutedDark
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Empty State

@Composable
private fun EmptySleepCard() {
    GlassCard(
        modifier = Modifier.fillMaxWidth(),
        cornerRadius = 20.dp,
        padding = 32.dp
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Icon(
                imageVector = Icons.Rounded.Hotel,
                contentDescription = null,
                tint = ThemeColors.accentCyan.copy(alpha = 0.7f),
                modifier = Modifier.size(40.dp)
            )
            Text(
                text = "No Sleep Data Recorded",
                fontSize = 16.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White
            )
            Text(
                text = "Wear your smartwatch or fitness tracker overnight to view your sleep architecture and hypnogram.",
                fontSize = 12.sp,
                color = ThemeColors.fgMutedDark,
                textAlign = TextAlign.Center
            )
        }
    }
}
