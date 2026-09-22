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
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.Bedtime
import androidx.compose.material.icons.rounded.DirectionsWalk
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.Nightlight
import androidx.compose.material.icons.rounded.SelfImprovement
import androidx.compose.material.icons.rounded.ShowChart
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.health.HealthDataRepository
import com.intellidream.daily.model.DashboardWidgetSize
import com.intellidream.daily.model.HealthMetricType
import kotlin.math.min
import kotlin.math.roundToInt

@Composable
fun HealthDashboardCard(
    size: DashboardWidgetSize,
    repository: HealthDataRepository,
    onOpenHub: () -> Unit,
    onLongClick: (() -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    val totalSteps by repository.totalStepsToday.collectAsState()
    val totalActiveCalories by repository.totalActiveCalories.collectAsState()
    val averageBpm by repository.averageBpm.collectAsState()
    val restingBpm by repository.restingBpm.collectAsState()
    val primarySleep by repository.primarySleepSession.collectAsState()
    val currentVitals by repository.currentVitals.collectAsState()
    val currentStressScore by repository.currentStressScore.collectAsState()
    val currentStressLevel by repository.currentStressLevel.collectAsState()
    val stressAnalysis by repository.stressAnalysis.collectAsState()

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
        padding = if (size == DashboardWidgetSize.Small) 12.dp else 16.dp,
        onClick = onOpenHub,
        onLongClick = onLongClick
    ) {
        when (size) {
            DashboardWidgetSize.Small -> SmallHealthContent(
                totalSteps = totalSteps,
                totalActiveCalories = totalActiveCalories,
                averageBpm = averageBpm,
                sleepAsleepFormatted = primarySleep?.totalAsleepFormatted
            )
            DashboardWidgetSize.Wide -> WideHealthContent(
                totalSteps = totalSteps,
                totalActiveCalories = totalActiveCalories,
                averageBpm = averageBpm,
                restingBpm = restingBpm,
                primarySleep = primarySleep,
                stressScore = currentStressScore,
                stressLevel = currentStressLevel,
                stressAnalysis = stressAnalysis
            )
            DashboardWidgetSize.Tall -> TallHealthContent(
                totalSteps = totalSteps,
                totalActiveCalories = totalActiveCalories,
                averageBpm = averageBpm,
                restingBpm = restingBpm,
                primarySleep = primarySleep
            )
            DashboardWidgetSize.Large -> LargeHealthContent(
                totalSteps = totalSteps,
                totalActiveCalories = totalActiveCalories,
                averageBpm = averageBpm,
                restingBpm = restingBpm,
                primarySleep = primarySleep,
                currentVitals = currentVitals
            )
        }
    }
}

// MARK: - Small (1x1) Compact Vitals Glance

@Composable
private fun SmallHealthContent(
    totalSteps: Int,
    totalActiveCalories: Double,
    averageBpm: Double,
    sleepAsleepFormatted: String?
) {
    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        // Header
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
                    imageVector = Icons.Rounded.Favorite,
                    contentDescription = null,
                    tint = ThemeColors.accentPink,
                    modifier = Modifier.size(13.dp)
                )
                Text(
                    text = "Health",
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = ThemeColors.accentPink
                )
            }

            if (averageBpm > 0) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    Icon(
                        imageVector = Icons.Rounded.ShowChart,
                        contentDescription = null,
                        tint = ThemeColors.accentPink,
                        modifier = Modifier.size(10.dp)
                    )
                    Text(
                        text = "${averageBpm.roundToInt()}",
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        color = ThemeColors.accentPink
                    )
                }
            }
        }

        // Steps Glance
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(3.dp)
            ) {
                Icon(
                    imageVector = Icons.Rounded.DirectionsWalk,
                    contentDescription = null,
                    tint = ThemeColors.accentPink,
                    modifier = Modifier.size(9.dp)
                )
                Text(
                    text = "STEPS",
                    fontSize = 9.sp,
                    fontWeight = FontWeight.Bold,
                    color = ThemeColors.fgMutedDark
                )
            }

            Text(
                text = "$totalSteps",
                fontSize = 26.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White
            )
        }

        // Progress bar towards 10,000 steps
        val progress = min(totalSteps.toFloat() / 10_000f, 1f)
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(5.dp)
                .clip(RoundedCornerShape(3.dp))
                .background(Color.White.copy(alpha = 0.12f))
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth(fraction = progress)
                    .fillMaxHeight()
                    .clip(RoundedCornerShape(3.dp))
                    .background(
                        Brush.horizontalGradient(
                            colors = listOf(ThemeColors.accentPink, ThemeColors.accentCyan)
                        )
                    )
            )
        }

        // Sleep & Active Calories Footer
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(3.dp)
            ) {
                Icon(
                    imageVector = Icons.Rounded.Nightlight,
                    contentDescription = null,
                    tint = ThemeColors.accentCyan,
                    modifier = Modifier.size(10.dp)
                )
                Text(
                    text = sleepAsleepFormatted ?: "--",
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = ThemeColors.accentCyan
                )
            }

            if (totalActiveCalories > 0) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    Icon(
                        imageVector = Icons.Rounded.LocalFireDepartment,
                        contentDescription = null,
                        tint = ThemeColors.accentOrange,
                        modifier = Modifier.size(9.dp)
                    )
                    Text(
                        text = "${totalActiveCalories.roundToInt()} kcal",
                        fontSize = 10.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = ThemeColors.fgMutedDark
                    )
                }
            }
        }
    }
}

// MARK: - Wide (2x1) Standard 4-Column Split

@Composable
private fun WideHealthContent(
    totalSteps: Int,
    totalActiveCalories: Double,
    averageBpm: Double,
    restingBpm: Double,
    primarySleep: com.intellidream.daily.model.SleepSession?,
    stressScore: Int,
    stressLevel: com.intellidream.daily.model.StressLevel,
    stressAnalysis: com.intellidream.daily.model.StressAnalysisResult?
) {
    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        // Header
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(5.dp)
            ) {
                Icon(
                    imageVector = Icons.Rounded.Favorite,
                    contentDescription = null,
                    tint = ThemeColors.accentPink,
                    modifier = Modifier.size(14.dp)
                )
                Text(
                    text = "Health & Vitals",
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = ThemeColors.accentPink
                )
            }

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(3.dp)
            ) {
                Text(
                    text = "Open Hub",
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = ThemeColors.accentPink
                )
                Icon(
                    imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                    contentDescription = null,
                    tint = ThemeColors.accentPink,
                    modifier = Modifier.size(12.dp)
                )
            }
        }

        // 4-Column Split: Steps | Heart | Sleep | Stress
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Steps Column
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(3.dp)
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(3.dp)
                ) {
                    Icon(
                        imageVector = Icons.Rounded.DirectionsWalk,
                        contentDescription = null,
                        tint = ThemeColors.accentPink,
                        modifier = Modifier.size(9.dp)
                    )
                    Text(
                        text = "STEPS",
                        fontSize = 9.5.sp,
                        fontWeight = FontWeight.Bold,
                        color = ThemeColors.fgMutedDark
                    )
                }
                Text(
                    text = "$totalSteps",
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White
                )
                if (totalActiveCalories > 0) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(2.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.LocalFireDepartment,
                            contentDescription = null,
                            tint = ThemeColors.accentOrange,
                            modifier = Modifier.size(8.dp)
                        )
                        Text(
                            text = "${totalActiveCalories.roundToInt()} kcal",
                            fontSize = 9.sp,
                            fontWeight = FontWeight.Medium,
                            color = ThemeColors.fgMutedDark
                        )
                    }
                }
            }

            VerticalDivider(
                color = Color.White.copy(alpha = 0.15f),
                modifier = Modifier
                    .height(34.dp)
                    .padding(horizontal = 4.dp)
            )

            // Heart Rate Column
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(3.dp)
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(3.dp)
                ) {
                    Icon(
                        imageVector = Icons.Rounded.ShowChart,
                        contentDescription = null,
                        tint = ThemeColors.accentPink,
                        modifier = Modifier.size(9.dp)
                    )
                    Text(
                        text = "HEART",
                        fontSize = 9.5.sp,
                        fontWeight = FontWeight.Bold,
                        color = ThemeColors.fgMutedDark
                    )
                }
                Text(
                    text = if (averageBpm > 0) "${averageBpm.roundToInt()} bpm" else "--",
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                    color = ThemeColors.accentPink
                )
                if (restingBpm > 0) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(2.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.Favorite,
                            contentDescription = null,
                            tint = ThemeColors.accentPink.copy(alpha = 0.85f),
                            modifier = Modifier.size(8.dp)
                        )
                        Text(
                            text = "Rest ${restingBpm.roundToInt()}",
                            fontSize = 9.sp,
                            fontWeight = FontWeight.Medium,
                            color = ThemeColors.fgMutedDark
                        )
                    }
                }
            }

            VerticalDivider(
                color = Color.White.copy(alpha = 0.15f),
                modifier = Modifier
                    .height(34.dp)
                    .padding(horizontal = 4.dp)
            )

            // Sleep Column
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(3.dp)
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(3.dp)
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Nightlight,
                        contentDescription = null,
                        tint = ThemeColors.accentCyan,
                        modifier = Modifier.size(9.dp)
                    )
                    Text(
                        text = "SLEEP",
                        fontSize = 9.5.sp,
                        fontWeight = FontWeight.Bold,
                        color = ThemeColors.fgMutedDark
                    )
                }
                Text(
                    text = primarySleep?.totalAsleepFormatted ?: "--",
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                    color = ThemeColors.accentCyan
                )
                if (primarySleep != null) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(2.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.AutoAwesome,
                            contentDescription = null,
                            tint = ThemeColors.accentCyan.copy(alpha = 0.85f),
                            modifier = Modifier.size(8.dp)
                        )
                        Text(
                            text = "${primarySleep.efficiencyPercent}% eff",
                            fontSize = 9.sp,
                            fontWeight = FontWeight.Medium,
                            color = ThemeColors.fgMutedDark
                        )
                    }
                }
            }

            VerticalDivider(
                color = Color.White.copy(alpha = 0.15f),
                modifier = Modifier
                    .height(34.dp)
                    .padding(horizontal = 4.dp)
            )

            // Stress Column
            val mood = stressAnalysis?.monkeyMood ?: com.intellidream.daily.model.MonkeyMood.CURIOUS
            val levelColor = Color(android.graphics.Color.parseColor(stressLevel.hexColor))

            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(3.dp)
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(3.dp)
                ) {
                    Text(
                        text = mood.emoji,
                        fontSize = 9.sp
                    )
                    Text(
                        text = "STRESS",
                        fontSize = 9.5.sp,
                        fontWeight = FontWeight.Bold,
                        color = ThemeColors.fgMutedDark
                    )
                }
                Text(
                    text = "$stressScore",
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                    color = levelColor
                )
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(3.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .size(5.dp)
                            .clip(CircleShape)
                            .background(levelColor)
                    )
                    Text(
                        text = stressLevel.displayName,
                        fontSize = 9.sp,
                        fontWeight = FontWeight.Medium,
                        color = ThemeColors.fgMutedDark,
                        maxLines = 1
                    )
                }
            }
        }
    }
}

// MARK: - Tall (1x2) Vertical Health Tower

@Composable
private fun TallHealthContent(
    totalSteps: Int,
    totalActiveCalories: Double,
    averageBpm: Double,
    restingBpm: Double,
    primarySleep: com.intellidream.daily.model.SleepSession?
) {
    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        // Header
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
                    imageVector = Icons.Rounded.Favorite,
                    contentDescription = null,
                    tint = ThemeColors.accentPink,
                    modifier = Modifier.size(13.dp)
                )
                Text(
                    text = "Health",
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = ThemeColors.accentPink
                )
            }

            Icon(
                imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                contentDescription = null,
                tint = ThemeColors.accentPink,
                modifier = Modifier.size(12.dp)
            )
        }

        // Steps Section with Circular Ring
        val stepProgress = min(totalSteps.toFloat() / 10_000f, 1f)
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier.size(38.dp)
            ) {
                CircularProgressIndicator(
                    progress = { 1f },
                    modifier = Modifier.fillMaxSize(),
                    color = Color.White.copy(alpha = 0.12f),
                    strokeWidth = 3.5.dp
                )
                CircularProgressIndicator(
                    progress = { stepProgress },
                    modifier = Modifier.fillMaxSize(),
                    color = ThemeColors.accentPink,
                    strokeWidth = 3.5.dp,
                    strokeCap = StrokeCap.Round
                )
                Icon(
                    imageVector = Icons.Rounded.DirectionsWalk,
                    contentDescription = null,
                    tint = ThemeColors.accentPink,
                    modifier = Modifier.size(11.dp)
                )
            }

            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    text = "STEPS",
                    fontSize = 9.sp,
                    fontWeight = FontWeight.Bold,
                    color = ThemeColors.fgMutedDark
                )
                Text(
                    text = "$totalSteps",
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White
                )
                if (totalActiveCalories > 0) {
                    Text(
                        text = "${totalActiveCalories.roundToInt()} kcal",
                        fontSize = 9.sp,
                        fontWeight = FontWeight.Medium,
                        color = ThemeColors.fgMutedDark
                    )
                }
            }
        }

        HorizontalDivider(color = Color.White.copy(alpha = 0.12f))

        // Heart Rate Section
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "HEART RATE",
                    fontSize = 9.sp,
                    fontWeight = FontWeight.Bold,
                    color = ThemeColors.fgMutedDark
                )
                if (restingBpm > 0) {
                    Text(
                        text = "Rest ${restingBpm.roundToInt()}",
                        fontSize = 8.5.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = ThemeColors.fgMutedDark
                    )
                }
            }
            Text(
                text = if (averageBpm > 0) "${averageBpm.roundToInt()} bpm" else "--",
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = ThemeColors.accentPink
            )
        }

        HorizontalDivider(color = Color.White.copy(alpha = 0.12f))

        // Sleep Section
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "SLEEP",
                    fontSize = 9.sp,
                    fontWeight = FontWeight.Bold,
                    color = ThemeColors.fgMutedDark
                )
                if (primarySleep != null) {
                    Text(
                        text = "${primarySleep.efficiencyPercent}% eff",
                        fontSize = 8.5.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = ThemeColors.fgMutedDark
                    )
                }
            }
            Text(
                text = primarySleep?.totalAsleepFormatted ?: "--",
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = ThemeColors.accentCyan
            )
            if (primarySleep != null) {
                Text(
                    text = "${primarySleep.bedtimeFormatted} - ${primarySleep.wakeTimeFormatted}",
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Medium,
                    color = ThemeColors.fgMutedDark
                )
            }
        }
    }
}

// MARK: - Large (2x2) Extended Biometrics Hub

@Composable
private fun LargeHealthContent(
    totalSteps: Int,
    totalActiveCalories: Double,
    averageBpm: Double,
    restingBpm: Double,
    primarySleep: com.intellidream.daily.model.SleepSession?,
    currentVitals: Map<HealthMetricType, com.intellidream.daily.model.VitalMetricRecord>
) {
    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        // Header
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(5.dp)
            ) {
                Icon(
                    imageVector = Icons.Rounded.Favorite,
                    contentDescription = null,
                    tint = ThemeColors.accentPink,
                    modifier = Modifier.size(14.dp)
                )
                Text(
                    text = "Health & Biometrics",
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = ThemeColors.accentPink
                )
            }

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(3.dp)
            ) {
                Text(
                    text = "Vitals Hub",
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = ThemeColors.accentPink
                )
                Icon(
                    imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                    contentDescription = null,
                    tint = ThemeColors.accentPink,
                    modifier = Modifier.size(12.dp)
                )
            }
        }

        // Primary 3-Metric Row
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Steps
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("STEPS", fontSize = 10.sp, fontWeight = FontWeight.Bold, color = ThemeColors.fgMutedDark)
                Text("$totalSteps", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = Color.White)
                if (totalActiveCalories > 0) {
                    Text("${totalActiveCalories.roundToInt()} kcal", fontSize = 9.5.sp, fontWeight = FontWeight.Medium, color = ThemeColors.fgMutedDark)
                }
            }

            // Avg BPM
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("AVG BPM", fontSize = 10.sp, fontWeight = FontWeight.Bold, color = ThemeColors.fgMutedDark)
                Text(if (averageBpm > 0) "${averageBpm.roundToInt()} bpm" else "--", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = ThemeColors.accentPink)
                if (restingBpm > 0) {
                    Text("Rest ${restingBpm.roundToInt()}", fontSize = 9.5.sp, fontWeight = FontWeight.Medium, color = ThemeColors.fgMutedDark)
                }
            }

            // Sleep
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("SLEEP", fontSize = 10.sp, fontWeight = FontWeight.Bold, color = ThemeColors.fgMutedDark)
                Text(primarySleep?.totalAsleepFormatted ?: "--", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = ThemeColors.accentCyan)
                if (primarySleep != null) {
                    Text("${primarySleep.efficiencyPercent}% eff", fontSize = 9.5.sp, fontWeight = FontWeight.Medium, color = ThemeColors.fgMutedDark)
                }
            }
        }

        HorizontalDivider(color = Color.White.copy(alpha = 0.12f))

        // Secondary Biometrics 2x2 Grid
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                val hrvVal = currentVitals[HealthMetricType.HRV_SDNN]?.value
                CompactVitalsTile(
                    modifier = Modifier.weight(1f),
                    title = "HRV (SDNN)",
                    value = if (hrvVal != null) "${hrvVal.roundToInt()} ms" else "--",
                    color = ThemeColors.accentPurple,
                    icon = Icons.Rounded.ShowChart
                )

                val spo2Val = currentVitals[HealthMetricType.OXYGEN_SATURATION]?.value
                CompactVitalsTile(
                    modifier = Modifier.weight(1f),
                    title = "BLOOD OXYGEN",
                    value = if (spo2Val != null) "${spo2Val.roundToInt()}%" else "--",
                    color = ThemeColors.accentBlue,
                    icon = Icons.Rounded.SelfImprovement
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                val rhrVal = currentVitals[HealthMetricType.RESTING_HEART_RATE]?.value
                CompactVitalsTile(
                    modifier = Modifier.weight(1f),
                    title = "RESTING HR",
                    value = if (rhrVal != null) "${rhrVal.roundToInt()} bpm" else "--",
                    color = ThemeColors.accentPink,
                    icon = Icons.Rounded.Favorite
                )

                val sleepScore = primarySleep?.sleepScore
                CompactVitalsTile(
                    modifier = Modifier.weight(1f),
                    title = "SLEEP SCORE",
                    value = if (sleepScore != null) "$sleepScore" else "--",
                    color = ThemeColors.accentCyan,
                    icon = Icons.Rounded.Bedtime
                )
            }
        }
    }
}

@Composable
private fun CompactVitalsTile(
    modifier: Modifier = Modifier,
    title: String,
    value: String,
    color: Color,
    icon: ImageVector
) {
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .background(Color.White.copy(alpha = 0.05f))
            .padding(horizontal = 10.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = color,
            modifier = Modifier.size(14.dp)
        )
        Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(
                text = title,
                fontSize = 8.sp,
                fontWeight = FontWeight.Bold,
                color = ThemeColors.fgMutedDark
            )
            Text(
                text = value,
                fontSize = 13.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White
            )
        }
    }
}
