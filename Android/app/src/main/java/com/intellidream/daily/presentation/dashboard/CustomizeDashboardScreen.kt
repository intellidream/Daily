package com.intellidream.daily.presentation.dashboard

import androidx.compose.animation.animateColorAsState
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
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.rounded.AccountBalanceWallet
import androidx.compose.material.icons.rounded.ArrowDownward
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.Feed
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.RestartAlt
import androidx.compose.material.icons.rounded.TouchApp
import androidx.compose.material.icons.rounded.WbSunny
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.designsystem.GlassButton
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.GlassIntensity
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.AppSettings
import com.intellidream.daily.model.DashboardWidgetConfig
import com.intellidream.daily.model.DashboardWidgetSize
import com.intellidream.daily.model.DashboardWidgetType

@Composable
fun CustomizeDashboardScreen(
    settings: AppSettings,
    onUpdateSettings: ((AppSettings) -> AppSettings) -> Unit,
    onBackClick: () -> Unit
) {
    val widgets = settings.dashboardWidgets

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(brush = ThemeColors.backgroundGradient)
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .padding(horizontal = 20.dp, vertical = 12.dp)
        ) {
            // Header bar
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                GlassButton(
                    onClick = onBackClick,
                    cornerRadius = 12.dp,
                    paddingHorizontal = 10.dp,
                    paddingVertical = 10.dp
                ) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                        contentDescription = "Back",
                        tint = Color.White,
                        modifier = Modifier.size(20.dp)
                    )
                }

                Spacer(modifier = Modifier.width(16.dp))

                Text(
                    text = "Customize Dashboard",
                    color = Color.White,
                    fontSize = 22.sp,
                    fontWeight = FontWeight.Bold
                )
            }

            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                // Intro card
                item(key = "intro_card") {
                    GlassCard(cornerRadius = 16.dp, padding = 16.dp, intensity = GlassIntensity.Subtle) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                imageVector = Icons.Rounded.TouchApp,
                                contentDescription = null,
                                tint = ThemeColors.accentCyan,
                                modifier = Modifier.size(24.dp)
                            )
                            Spacer(modifier = Modifier.width(12.dp))
                            Column {
                                Text(
                                    text = "Personalize Your Grid",
                                    color = Color.White,
                                    fontSize = 14.sp,
                                    fontWeight = FontWeight.SemiBold
                                )
                                Text(
                                    text = "Reorder widgets, adjust aspect ratios, or toggle visibility. Changes persist automatically.",
                                    color = ThemeColors.textMuted,
                                    fontSize = 12.sp
                                )
                            }
                        }
                    }
                }

                // Widget configuration list
                itemsIndexed(
                    items = widgets,
                    key = { _, config -> config.id }
                ) { index, config ->
                    WidgetConfigItemCard(
                        index = index,
                        totalCount = widgets.size,
                        config = config,
                        onMoveUp = {
                            if (index > 0) {
                                onUpdateSettings { current ->
                                    val list = current.dashboardWidgets.toMutableList()
                                    val item = list.removeAt(index)
                                    list.add(index - 1, item)
                                    current.copy(dashboardWidgets = list)
                                }
                            }
                        },
                        onMoveDown = {
                            if (index < widgets.size - 1) {
                                onUpdateSettings { current ->
                                    val list = current.dashboardWidgets.toMutableList()
                                    val item = list.removeAt(index)
                                    list.add(index + 1, item)
                                    current.copy(dashboardWidgets = list)
                                }
                            }
                        },
                        onSelectSize = { newSize ->
                            onUpdateSettings { current ->
                                val list = current.dashboardWidgets.toMutableList()
                                val old = list[index]
                                list[index] = old.copy(size = newSize)
                                current.copy(dashboardWidgets = list)
                            }
                        },
                        onToggleVisibility = { isVisible ->
                            onUpdateSettings { current ->
                                val list = current.dashboardWidgets.toMutableList()
                                val old = list[index]
                                list[index] = old.copy(isVisible = isVisible)
                                current.copy(dashboardWidgets = list)
                            }
                        }
                    )
                }

                // Reset to Default button
                item(key = "reset_button") {
                    GlassCard(
                        modifier = Modifier.fillMaxWidth(),
                        cornerRadius = 16.dp,
                        padding = 16.dp,
                        intensity = GlassIntensity.Subtle,
                        onClick = {
                            onUpdateSettings { current ->
                                current.copy(dashboardWidgets = DashboardWidgetConfig.defaultLayout)
                            }
                        }
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.Center,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(
                                imageVector = Icons.Rounded.RestartAlt,
                                contentDescription = null,
                                tint = ThemeColors.accentPink,
                                modifier = Modifier.size(18.dp)
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(
                                text = "Reset to Default Layout",
                                color = ThemeColors.accentPink,
                                fontSize = 14.sp,
                                fontWeight = FontWeight.SemiBold
                            )
                        }
                    }
                }

                item(key = "bottom_space") {
                    Spacer(modifier = Modifier.height(40.dp))
                }
            }
        }
    }
}

@Composable
private fun WidgetConfigItemCard(
    index: Int,
    totalCount: Int,
    config: DashboardWidgetConfig,
    onMoveUp: () -> Unit,
    onMoveDown: () -> Unit,
    onSelectSize: (DashboardWidgetSize) -> Unit,
    onToggleVisibility: (Boolean) -> Unit
) {
    val widgetType = when (config.id) {
        DashboardWidgetType.Weather.id -> DashboardWidgetType.Weather
        DashboardWidgetType.News.id -> DashboardWidgetType.News
        DashboardWidgetType.Health.id -> DashboardWidgetType.Health
        DashboardWidgetType.Habits.id -> DashboardWidgetType.Habits
        DashboardWidgetType.Finances.id -> DashboardWidgetType.Finances
        DashboardWidgetType.TagdosNotes.id -> DashboardWidgetType.TagdosNotes
        else -> null
    }

    val title = widgetType?.title ?: config.id.replaceFirstChar { it.uppercase() }
    val icon = getWidgetIcon(config.id)

    GlassCard(cornerRadius = 18.dp, padding = 16.dp, intensity = GlassIntensity.Medium) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            // Top row: Icon, Title, Up/Down, Visibility
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = icon,
                        contentDescription = null,
                        tint = ThemeColors.accentCyan,
                        modifier = Modifier.size(20.dp)
                    )
                    Spacer(modifier = Modifier.width(10.dp))
                    Text(
                        text = title,
                        color = Color.White,
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                }

                Row(verticalAlignment = Alignment.CenterVertically) {
                    // Up button
                    Box(
                        modifier = Modifier
                            .size(28.dp)
                            .clip(CircleShape)
                            .background(Color.White.copy(alpha = if (index > 0) 0.12f else 0.04f))
                            .clickable(enabled = index > 0, onClick = onMoveUp),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.ArrowUpward,
                            contentDescription = "Move Up",
                            tint = if (index > 0) Color.White else Color.White.copy(alpha = 0.25f),
                            modifier = Modifier.size(14.dp)
                        )
                    }

                    Spacer(modifier = Modifier.width(6.dp))

                    // Down button
                    Box(
                        modifier = Modifier
                            .size(28.dp)
                            .clip(CircleShape)
                            .background(Color.White.copy(alpha = if (index < totalCount - 1) 0.12f else 0.04f))
                            .clickable(enabled = index < totalCount - 1, onClick = onMoveDown),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.ArrowDownward,
                            contentDescription = "Move Down",
                            tint = if (index < totalCount - 1) Color.White else Color.White.copy(alpha = 0.25f),
                            modifier = Modifier.size(14.dp)
                        )
                    }

                    Spacer(modifier = Modifier.width(10.dp))

                    Switch(
                        checked = config.isVisible,
                        onCheckedChange = onToggleVisibility,
                        colors = SwitchDefaults.colors(
                            checkedThumbColor = Color.White,
                            checkedTrackColor = ThemeColors.accentCyan,
                            uncheckedThumbColor = Color.White.copy(alpha = 0.7f),
                            uncheckedTrackColor = Color.White.copy(alpha = 0.15f)
                        )
                    )
                }
            }

            HorizontalDivider(color = Color.White.copy(alpha = 0.08f))

            // Size selector
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    text = "ASPECT RATIO",
                    color = ThemeColors.textMuted,
                    fontSize = 9.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 1.sp
                )

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    listOf(
                        DashboardWidgetSize.Small to "1×1 Small",
                        DashboardWidgetSize.Wide to "2×1 Wide",
                        DashboardWidgetSize.Tall to "1×2 Tall",
                        DashboardWidgetSize.Large to "2×2 Large"
                    ).forEach { (size, label) ->
                        val isSelected = config.size == size
                        val bg by animateColorAsState(
                            targetValue = if (isSelected) ThemeColors.accentCyan.copy(alpha = 0.22f) else Color.White.copy(alpha = 0.05f),
                            label = "size_bg"
                        )
                        val border by animateColorAsState(
                            targetValue = if (isSelected) ThemeColors.accentCyan else Color.Transparent,
                            label = "size_border"
                        )
                        val textColor by animateColorAsState(
                            targetValue = if (isSelected) ThemeColors.accentCyan else Color.White.copy(alpha = 0.75f),
                            label = "size_text"
                        )

                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .clip(RoundedCornerShape(8.dp))
                                .background(bg)
                                .border(1.dp, border, RoundedCornerShape(8.dp))
                                .clickable { onSelectSize(size) }
                                .padding(vertical = 7.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                text = label,
                                color = textColor,
                                fontSize = 11.sp,
                                fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal
                            )
                        }
                    }
                }
            }
        }
    }
}

private fun getWidgetIcon(id: String): ImageVector {
    return when (id) {
        DashboardWidgetType.Weather.id -> Icons.Rounded.WbSunny
        DashboardWidgetType.News.id -> Icons.Rounded.Feed
        DashboardWidgetType.Health.id -> Icons.Rounded.Favorite
        DashboardWidgetType.Habits.id -> Icons.Rounded.LocalFireDepartment
        DashboardWidgetType.Finances.id -> Icons.Rounded.AccountBalanceWallet
        DashboardWidgetType.TagdosNotes.id -> Icons.Rounded.CheckCircle
        else -> Icons.Rounded.WbSunny
    }
}
