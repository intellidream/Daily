package com.intellidream.daily.presentation.dashboard

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.Bolt
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Coffee
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.Science
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material.icons.rounded.WaterDrop
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.database.HabitsRepository
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.DashboardWidgetSize
import com.intellidream.daily.model.SmokePreset
import com.intellidream.daily.model.WaterPreset

@Composable
fun HabitsDashboardCard(
    size: DashboardWidgetSize,
    repository: HabitsRepository,
    onOpenHub: () -> Unit,
    onLongClick: (() -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    val waterTotal by repository.waterTotalToday.collectAsState()
    val waterGoal by repository.waterGoal.collectAsState()
    val smokesTotal by repository.smokesTotalToday.collectAsState()
    val smokesSettings by repository.smokesSettings.collectAsState()

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
            DashboardWidgetSize.Small -> SmallHabitsContent(
                waterTotal = waterTotal,
                waterGoal = waterGoal,
                smokesTotal = smokesTotal,
                smokesBaseline = smokesSettings.baselineDailyCount,
                onLogWaterSmall = { repository.logWater(WaterPreset.SMALL_WATER) },
                onOpenHub = onOpenHub
            )

            DashboardWidgetSize.Wide -> WideHabitsContent(
                waterTotal = waterTotal,
                waterGoal = waterGoal,
                smokesTotal = smokesTotal,
                smokesBaseline = smokesSettings.baselineDailyCount,
                repository = repository,
                onOpenHub = onOpenHub
            )

            DashboardWidgetSize.Tall -> TallHabitsContent(
                waterTotal = waterTotal,
                waterGoal = waterGoal,
                smokesTotal = smokesTotal,
                smokesBaseline = smokesSettings.baselineDailyCount,
                repository = repository,
                onOpenHub = onOpenHub
            )

            DashboardWidgetSize.Large -> LargeHabitsContent(
                waterTotal = waterTotal,
                waterGoal = waterGoal,
                smokesTotal = smokesTotal,
                smokesBaseline = smokesSettings.baselineDailyCount,
                repository = repository,
                onOpenHub = onOpenHub
            )
        }
    }
}

// MARK: - Small (1x1) Compact Glance
@Composable
private fun SmallHabitsContent(
    waterTotal: Double,
    waterGoal: Double,
    smokesTotal: Int,
    smokesBaseline: Int,
    onLogWaterSmall: () -> Unit,
    onOpenHub: () -> Unit
) {
    val waterProgress = (waterTotal / waterGoal.coerceAtLeast(1.0)).toFloat().coerceIn(0f, 1f)
    val isWaterGoalMet = waterTotal >= waterGoal
    val smokesProgress = (smokesTotal.toFloat() / smokesBaseline.coerceAtLeast(1).toFloat()).coerceIn(0f, 1f)
    val isSmokesOver = smokesTotal > smokesBaseline

    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        // Header row
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
                    imageVector = Icons.Rounded.WaterDrop,
                    contentDescription = null,
                    tint = ThemeColors.accentCyan,
                    modifier = Modifier.size(13.dp)
                )
                Text(
                    text = "Habits",
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Bold,
                    color = ThemeColors.accentCyan
                )
            }

            Box(
                modifier = Modifier
                    .clip(CircleShape)
                    .background(ThemeColors.accentCyan.copy(alpha = 0.15f))
                    .clickable { onLogWaterSmall() }
                    .padding(horizontal = 6.dp, vertical = 2.dp)
            ) {
                Text(
                    text = "+150",
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    color = ThemeColors.accentCyan
                )
            }
        }

        // Water metric row
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Box(contentAlignment = Alignment.Center, modifier = Modifier.size(28.dp)) {
                CircularProgressIndicator(
                    progress = { 1f },
                    modifier = Modifier.fillMaxSize(),
                    color = Color.White.copy(alpha = 0.1f),
                    strokeWidth = 3.dp
                )
                CircularProgressIndicator(
                    progress = { waterProgress },
                    modifier = Modifier.fillMaxSize(),
                    color = if (isWaterGoalMet) Color(0xFF00FFB2) else ThemeColors.accentCyan,
                    strokeWidth = 3.dp,
                    strokeCap = StrokeCap.Round
                )
                Icon(
                    imageVector = if (isWaterGoalMet) Icons.Rounded.Check else Icons.Rounded.WaterDrop,
                    contentDescription = null,
                    tint = if (isWaterGoalMet) Color(0xFF00FFB2) else ThemeColors.accentCyan,
                    modifier = Modifier.size(11.dp)
                )
            }

            Column {
                Text(
                    text = "WATER",
                    fontSize = 8.sp,
                    fontWeight = FontWeight.Bold,
                    color = ThemeColors.textSecondary
                )
                Text(
                    text = "${waterTotal.toInt()} ml",
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White
                )
            }
        }

        // Smokes metric row
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Box(contentAlignment = Alignment.Center, modifier = Modifier.size(28.dp)) {
                CircularProgressIndicator(
                    progress = { 1f },
                    modifier = Modifier.fillMaxSize(),
                    color = Color.White.copy(alpha = 0.1f),
                    strokeWidth = 3.dp
                )
                CircularProgressIndicator(
                    progress = { smokesProgress },
                    modifier = Modifier.fillMaxSize(),
                    color = if (isSmokesOver) Color(0xFFFF3B30) else Color(0xFF00FFB2),
                    strokeWidth = 3.dp,
                    strokeCap = StrokeCap.Round
                )
                Icon(
                    imageVector = if (isSmokesOver) Icons.Rounded.Warning else Icons.Rounded.LocalFireDepartment,
                    contentDescription = null,
                    tint = if (isSmokesOver) Color(0xFFFF3B30) else Color(0xFF00FFB2),
                    modifier = Modifier.size(11.dp)
                )
            }

            Column {
                Text(
                    text = "SMOKES",
                    fontSize = 8.sp,
                    fontWeight = FontWeight.Bold,
                    color = ThemeColors.textSecondary
                )
                Text(
                    text = "$smokesTotal / $smokesBaseline",
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Bold,
                    color = if (isSmokesOver) Color(0xFFFF3B30) else Color.White
                )
            }
        }
    }
}

// MARK: - Wide (2x1) Standard Dual Ring Card
@Composable
private fun WideHabitsContent(
    waterTotal: Double,
    waterGoal: Double,
    smokesTotal: Int,
    smokesBaseline: Int,
    repository: HabitsRepository,
    onOpenHub: () -> Unit
) {
    val waterProgress = (waterTotal / waterGoal.coerceAtLeast(1.0)).toFloat().coerceIn(0f, 1f)
    val isWaterGoalMet = waterTotal >= waterGoal
    val smokesProgress = (smokesTotal.toFloat() / smokesBaseline.coerceAtLeast(1).toFloat()).coerceIn(0f, 1f)
    val isSmokesOver = smokesTotal > smokesBaseline

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
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Icon(
                    imageVector = Icons.Rounded.WaterDrop,
                    contentDescription = null,
                    tint = ThemeColors.accentCyan,
                    modifier = Modifier.size(14.dp)
                )
                Text(
                    text = "Habits & Cravings",
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Bold,
                    color = ThemeColors.accentCyan
                )
            }

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(2.dp),
                modifier = Modifier.clickable { onOpenHub() }
            ) {
                Text(
                    text = "Open Hub",
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = ThemeColors.accentCyan
                )
                Icon(
                    imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                    contentDescription = null,
                    tint = ThemeColors.accentCyan,
                    modifier = Modifier.size(14.dp)
                )
            }
        }

        // Dual Progress Rings Row
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Water Ring
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                modifier = Modifier.weight(1f)
            ) {
                Box(contentAlignment = Alignment.Center, modifier = Modifier.size(38.dp)) {
                    CircularProgressIndicator(
                        progress = { 1f },
                        modifier = Modifier.fillMaxSize(),
                        color = Color.White.copy(alpha = 0.1f),
                        strokeWidth = 3.5.dp
                    )
                    CircularProgressIndicator(
                        progress = { waterProgress },
                        modifier = Modifier.fillMaxSize(),
                        color = if (isWaterGoalMet) Color(0xFF00FFB2) else ThemeColors.accentCyan,
                        strokeWidth = 3.5.dp,
                        strokeCap = StrokeCap.Round
                    )
                    Icon(
                        imageVector = if (isWaterGoalMet) Icons.Rounded.Check else Icons.Rounded.WaterDrop,
                        contentDescription = null,
                        tint = if (isWaterGoalMet) Color(0xFF00FFB2) else ThemeColors.accentCyan,
                        modifier = Modifier.size(14.dp)
                    )
                }

                Column {
                    Text(
                        text = "BUBBLES",
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        color = ThemeColors.textSecondary
                    )
                    Row(verticalAlignment = Alignment.Bottom) {
                        Text(
                            text = "${waterTotal.toInt()}",
                            fontSize = 17.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White
                        )
                        Text(
                            text = " / ${waterGoal.toInt()} ml",
                            fontSize = 11.sp,
                            color = ThemeColors.textSecondary
                        )
                    }
                }
            }

            Box(
                modifier = Modifier
                    .width(1.dp)
                    .height(32.dp)
                    .background(Color.White.copy(alpha = 0.15f))
            )

            // Smokes Ring
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                modifier = Modifier
                    .weight(1f)
                    .padding(start = 12.dp)
            ) {
                Box(contentAlignment = Alignment.Center, modifier = Modifier.size(38.dp)) {
                    CircularProgressIndicator(
                        progress = { 1f },
                        modifier = Modifier.fillMaxSize(),
                        color = Color.White.copy(alpha = 0.1f),
                        strokeWidth = 3.5.dp
                    )
                    CircularProgressIndicator(
                        progress = { smokesProgress },
                        modifier = Modifier.fillMaxSize(),
                        color = if (isSmokesOver) Color(0xFFFF3B30) else Color(0xFF00FFB2),
                        strokeWidth = 3.5.dp,
                        strokeCap = StrokeCap.Round
                    )
                    Icon(
                        imageVector = if (isSmokesOver) Icons.Rounded.Warning else Icons.Rounded.LocalFireDepartment,
                        contentDescription = null,
                        tint = if (isSmokesOver) Color(0xFFFF3B30) else Color(0xFF00FFB2),
                        modifier = Modifier.size(14.dp)
                    )
                }

                Column {
                    Text(
                        text = "SMOKES",
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        color = ThemeColors.textSecondary
                    )
                    Row(verticalAlignment = Alignment.Bottom) {
                        Text(
                            text = "$smokesTotal",
                            fontSize = 17.sp,
                            fontWeight = FontWeight.Bold,
                            color = if (isSmokesOver) Color(0xFFFF3B30) else Color.White
                        )
                        Text(
                            text = " / $smokesBaseline max",
                            fontSize = 11.sp,
                            color = ThemeColors.textSecondary
                        )
                    }
                }
            }
        }

        // Quick Action Chips Row
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                MiniActionChip(
                    title = "100",
                    icon = Icons.Rounded.Coffee,
                    color = Color(0xFFF59E0B),
                    onClick = { repository.logWater(WaterPreset.COFFEE) }
                )
                MiniActionChip(
                    title = "150",
                    icon = Icons.Rounded.WaterDrop,
                    color = ThemeColors.accentCyan,
                    onClick = { repository.logWater(WaterPreset.SMALL_WATER) }
                )
                MiniActionChip(
                    title = "300",
                    icon = Icons.Rounded.WaterDrop,
                    color = ThemeColors.accentCyan,
                    onClick = { repository.logWater(WaterPreset.LARGE_WATER) }
                )
            }

            Spacer(modifier = Modifier.weight(1f))

            Row(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                MiniActionChip(
                    title = "Cig",
                    icon = Icons.Rounded.LocalFireDepartment,
                    color = Color(0xFFEF4444),
                    onClick = { repository.logSmoke(SmokePreset.CIGARETTE) }
                )
                MiniActionChip(
                    title = "Heat",
                    icon = Icons.Rounded.Bolt,
                    color = Color(0xFF3B82F6),
                    onClick = { repository.logSmoke(SmokePreset.HEATED) }
                )
            }
        }
    }
}

// MARK: - Tall (1x2) Vertical Habits Tower
@Composable
private fun TallHabitsContent(
    waterTotal: Double,
    waterGoal: Double,
    smokesTotal: Int,
    smokesBaseline: Int,
    repository: HabitsRepository,
    onOpenHub: () -> Unit
) {
    val waterProgress = (waterTotal / waterGoal.coerceAtLeast(1.0)).toFloat().coerceIn(0f, 1f)
    val isWaterGoalMet = waterTotal >= waterGoal
    val smokesProgress = (smokesTotal.toFloat() / smokesBaseline.coerceAtLeast(1).toFloat()).coerceIn(0f, 1f)
    val isSmokesOver = smokesTotal > smokesBaseline

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
                    imageVector = Icons.Rounded.WaterDrop,
                    contentDescription = null,
                    tint = ThemeColors.accentCyan,
                    modifier = Modifier.size(13.dp)
                )
                Text(
                    text = "Habits",
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Bold,
                    color = ThemeColors.accentCyan
                )
            }
            Icon(
                imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                contentDescription = null,
                tint = ThemeColors.accentCyan,
                modifier = Modifier.size(14.dp)
            )
        }

        // Bubbles Section
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Box(contentAlignment = Alignment.Center, modifier = Modifier.size(36.dp)) {
                    CircularProgressIndicator(
                        progress = { 1f },
                        modifier = Modifier.fillMaxSize(),
                        color = Color.White.copy(alpha = 0.1f),
                        strokeWidth = 3.5.dp
                    )
                    CircularProgressIndicator(
                        progress = { waterProgress },
                        modifier = Modifier.fillMaxSize(),
                        color = if (isWaterGoalMet) Color(0xFF00FFB2) else ThemeColors.accentCyan,
                        strokeWidth = 3.5.dp,
                        strokeCap = StrokeCap.Round
                    )
                    Icon(
                        imageVector = if (isWaterGoalMet) Icons.Rounded.Check else Icons.Rounded.WaterDrop,
                        contentDescription = null,
                        tint = if (isWaterGoalMet) Color(0xFF00FFB2) else ThemeColors.accentCyan,
                        modifier = Modifier.size(13.dp)
                    )
                }

                Column {
                    Text(
                        text = "BUBBLES",
                        fontSize = 9.sp,
                        fontWeight = FontWeight.Bold,
                        color = ThemeColors.textSecondary
                    )
                    Text(
                        text = "${waterTotal.toInt()} ml",
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                }
            }

            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                MiniActionChip(
                    title = "+300",
                    icon = Icons.Rounded.WaterDrop,
                    color = ThemeColors.accentCyan,
                    onClick = { repository.logWater(WaterPreset.LARGE_WATER) }
                )
                MiniActionChip(
                    title = "+150",
                    icon = Icons.Rounded.WaterDrop,
                    color = ThemeColors.accentCyan,
                    onClick = { repository.logWater(WaterPreset.SMALL_WATER) }
                )
            }
        }

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(1.dp)
                .background(Color.White.copy(alpha = 0.12f))
        )

        // Smokes Section
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Box(contentAlignment = Alignment.Center, modifier = Modifier.size(36.dp)) {
                    CircularProgressIndicator(
                        progress = { 1f },
                        modifier = Modifier.fillMaxSize(),
                        color = Color.White.copy(alpha = 0.1f),
                        strokeWidth = 3.5.dp
                    )
                    CircularProgressIndicator(
                        progress = { smokesProgress },
                        modifier = Modifier.fillMaxSize(),
                        color = if (isSmokesOver) Color(0xFFFF3B30) else Color(0xFF00FFB2),
                        strokeWidth = 3.5.dp,
                        strokeCap = StrokeCap.Round
                    )
                    Icon(
                        imageVector = if (isSmokesOver) Icons.Rounded.Warning else Icons.Rounded.LocalFireDepartment,
                        contentDescription = null,
                        tint = if (isSmokesOver) Color(0xFFFF3B30) else Color(0xFF00FFB2),
                        modifier = Modifier.size(13.dp)
                    )
                }

                Column {
                    Text(
                        text = "SMOKES",
                        fontSize = 9.sp,
                        fontWeight = FontWeight.Bold,
                        color = ThemeColors.textSecondary
                    )
                    Text(
                        text = "$smokesTotal / $smokesBaseline",
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold,
                        color = if (isSmokesOver) Color(0xFFFF3B30) else Color.White
                    )
                }
            }

            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                MiniActionChip(
                    title = "+Cig",
                    icon = Icons.Rounded.LocalFireDepartment,
                    color = Color(0xFFEF4444),
                    onClick = { repository.logSmoke(SmokePreset.CIGARETTE) }
                )
                MiniActionChip(
                    title = "+Heat",
                    icon = Icons.Rounded.Bolt,
                    color = Color(0xFF3B82F6),
                    onClick = { repository.logSmoke(SmokePreset.HEATED) }
                )
            }
        }
    }
}

// MARK: - Large (2x2) Extended Habits Station
@Composable
private fun LargeHabitsContent(
    waterTotal: Double,
    waterGoal: Double,
    smokesTotal: Int,
    smokesBaseline: Int,
    repository: HabitsRepository,
    onOpenHub: () -> Unit
) {
    val waterProgress = (waterTotal / waterGoal.coerceAtLeast(1.0)).toFloat().coerceIn(0f, 1f)
    val isWaterGoalMet = waterTotal >= waterGoal
    val smokesProgress = (smokesTotal.toFloat() / smokesBaseline.coerceAtLeast(1).toFloat()).coerceIn(0f, 1f)
    val isSmokesOver = smokesTotal > smokesBaseline

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
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Icon(
                    imageVector = Icons.Rounded.WaterDrop,
                    contentDescription = null,
                    tint = ThemeColors.accentCyan,
                    modifier = Modifier.size(14.dp)
                )
                Text(
                    text = "Habits & Performance Hub",
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Bold,
                    color = ThemeColors.accentCyan
                )
            }

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(2.dp),
                modifier = Modifier.clickable { onOpenHub() }
            ) {
                Text(
                    text = "Open Hub",
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = ThemeColors.accentCyan
                )
                Icon(
                    imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                    contentDescription = null,
                    tint = ThemeColors.accentCyan,
                    modifier = Modifier.size(14.dp)
                )
            }
        }

        // Dual Progress Rings
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            // Water
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.weight(1f)
            ) {
                Box(contentAlignment = Alignment.Center, modifier = Modifier.size(44.dp)) {
                    CircularProgressIndicator(
                        progress = { 1f },
                        modifier = Modifier.fillMaxSize(),
                        color = Color.White.copy(alpha = 0.1f),
                        strokeWidth = 4.dp
                    )
                    CircularProgressIndicator(
                        progress = { waterProgress },
                        modifier = Modifier.fillMaxSize(),
                        color = if (isWaterGoalMet) Color(0xFF00FFB2) else ThemeColors.accentCyan,
                        strokeWidth = 4.dp,
                        strokeCap = StrokeCap.Round
                    )
                    Icon(
                        imageVector = if (isWaterGoalMet) Icons.Rounded.Check else Icons.Rounded.WaterDrop,
                        contentDescription = null,
                        tint = if (isWaterGoalMet) Color(0xFF00FFB2) else ThemeColors.accentCyan,
                        modifier = Modifier.size(16.dp)
                    )
                }

                Column {
                    Text(
                        text = "HYDRATION",
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        color = ThemeColors.textSecondary
                    )
                    Text(
                        text = "${waterTotal.toInt()} ml",
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                    Text(
                        text = "Goal: ${waterGoal.toInt()} ml",
                        fontSize = 10.sp,
                        color = ThemeColors.textSecondary
                    )
                }
            }

            // Smokes
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier
                    .weight(1f)
                    .padding(start = 12.dp)
            ) {
                Box(contentAlignment = Alignment.Center, modifier = Modifier.size(44.dp)) {
                    CircularProgressIndicator(
                        progress = { 1f },
                        modifier = Modifier.fillMaxSize(),
                        color = Color.White.copy(alpha = 0.1f),
                        strokeWidth = 4.dp
                    )
                    CircularProgressIndicator(
                        progress = { smokesProgress },
                        modifier = Modifier.fillMaxSize(),
                        color = if (isSmokesOver) Color(0xFFFF3B30) else Color(0xFF00FFB2),
                        strokeWidth = 4.dp,
                        strokeCap = StrokeCap.Round
                    )
                    Icon(
                        imageVector = if (isSmokesOver) Icons.Rounded.Warning else Icons.Rounded.LocalFireDepartment,
                        contentDescription = null,
                        tint = if (isSmokesOver) Color(0xFFFF3B30) else Color(0xFF00FFB2),
                        modifier = Modifier.size(16.dp)
                    )
                }

                Column {
                    Text(
                        text = "SMOKES",
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        color = ThemeColors.textSecondary
                    )
                    Text(
                        text = "$smokesTotal / $smokesBaseline",
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold,
                        color = if (isSmokesOver) Color(0xFFFF3B30) else Color.White
                    )
                    Text(
                        text = "Baseline: $smokesBaseline",
                        fontSize = 10.sp,
                        color = ThemeColors.textSecondary
                    )
                }
            }
        }

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(1.dp)
                .background(Color.White.copy(alpha = 0.12f))
        )

        // Comprehensive Quick Intake (2 rows of 3 chips)
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                text = "QUICK INTAKE",
                fontSize = 10.sp,
                fontWeight = FontWeight.Bold,
                color = ThemeColors.textSecondary,
                letterSpacing = 1.sp
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                MiniActionChip(
                    title = "+500 Bottle",
                    icon = Icons.Rounded.Science,
                    color = Color(0xFF06B6D4),
                    onClick = { repository.logWater(WaterPreset.BOTTLE) }
                )
                MiniActionChip(
                    title = "+300 Water",
                    icon = Icons.Rounded.WaterDrop,
                    color = ThemeColors.accentCyan,
                    onClick = { repository.logWater(WaterPreset.LARGE_WATER) }
                )
                MiniActionChip(
                    title = "+150 Water",
                    icon = Icons.Rounded.WaterDrop,
                    color = ThemeColors.accentCyan,
                    onClick = { repository.logWater(WaterPreset.SMALL_WATER) }
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                MiniActionChip(
                    title = "+100 Coffee",
                    icon = Icons.Rounded.Coffee,
                    color = Color(0xFFF59E0B),
                    onClick = { repository.logWater(WaterPreset.COFFEE) }
                )
                MiniActionChip(
                    title = "+1 Cigarette",
                    icon = Icons.Rounded.LocalFireDepartment,
                    color = Color(0xFFEF4444),
                    onClick = { repository.logSmoke(SmokePreset.CIGARETTE) }
                )
                MiniActionChip(
                    title = "+1 Heated",
                    icon = Icons.Rounded.Bolt,
                    color = Color(0xFF3B82F6),
                    onClick = { repository.logSmoke(SmokePreset.HEATED) }
                )
            }
        }
    }
}

@Composable
private fun MiniActionChip(
    title: String,
    icon: ImageVector,
    color: Color,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .clip(CircleShape)
            .background(color.copy(alpha = 0.12f))
            .border(1.dp, color.copy(alpha = 0.35f), CircleShape)
            .clickable(onClick = onClick)
            .padding(horizontal = 8.dp, vertical = 6.dp)
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = color,
                modifier = Modifier.size(11.dp)
            )
            Text(
                text = title,
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                color = color
            )
        }
    }
}
