package com.intellidream.daily.designsystem

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBalanceWallet
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Newspaper
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.WaterDrop
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

enum class NavigationTab(val displayName: String, val icon: ImageVector) {
    Dashboard("Dashboard", Icons.Filled.GridView),
    Finances("Money", Icons.Filled.AccountBalanceWallet),
    Tagdos("TagDoS", Icons.Filled.Checklist),
    Health("Health", Icons.Filled.Favorite),
    Habits("Habits", Icons.Filled.WaterDrop),
    Weather("Weather", Icons.Filled.Cloud),
    News("News", Icons.Filled.Newspaper),
    Settings("Settings", Icons.Filled.Settings);

    companion object {
        val primaryTabs = listOf(Dashboard, Finances, Tagdos, Health, Habits)
    }
}

@Composable
fun FloatingGlassCapsule(
    selectedTab: NavigationTab,
    onTabSelected: (NavigationTab) -> Unit,
    modifier: Modifier = Modifier,
    isDark: Boolean = true
) {
    val haptic = LocalHapticFeedback.current

    Box(
        modifier = modifier
            .wrapContentWidth()
            .height(58.dp)
            .shadow(
                elevation = 16.dp,
                shape = CircleShape,
                ambientColor = Color.Black.copy(alpha = 0.5f),
                spotColor = Color.Black.copy(alpha = 0.5f)
            )
            .clip(CircleShape)
            .background(
                color = if (isDark) Color(0xFF060D1A).copy(alpha = 0.85f) else Color.White.copy(alpha = 0.90f)
            )
            .border(
                width = 1.dp,
                brush = if (isDark) ThemeColors.glassDarkBorder else ThemeColors.glassLightBorder,
                shape = CircleShape
            )
            .padding(horizontal = 6.dp, vertical = 6.dp),
        contentAlignment = Alignment.Center
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            NavigationTab.primaryTabs.forEach { tab ->
                val isSelected = selectedTab == tab
                val interactionSource = remember { MutableInteractionSource() }

                Box(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(
                            brush = if (isSelected) ThemeColors.activeTabIndicatorBrush else Brush.linearGradient(listOf(Color.Transparent, Color.Transparent)),
                            shape = CircleShape
                        )
                        .then(
                            if (isSelected) {
                                Modifier.border(
                                    width = 1.dp,
                                    color = Color.White.copy(alpha = 0.40f),
                                    shape = CircleShape
                                )
                            } else Modifier
                        )
                        .clickable(
                            interactionSource = interactionSource,
                            indication = null
                        ) {
                            if (!isSelected) {
                                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                onTabSelected(tab)
                            }
                        }
                        .padding(horizontal = if (isSelected) 14.dp else 10.dp, vertical = 8.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Icon(
                            imageVector = tab.icon,
                            contentDescription = tab.displayName,
                            tint = if (isSelected) Color.White else Color.White.copy(alpha = 0.60f),
                            modifier = Modifier.height(18.dp).width(18.dp)
                        )
                        AnimatedVisibility(
                            visible = isSelected,
                            enter = fadeIn(animationSpec = spring(dampingRatio = 0.75f)),
                            exit = fadeOut(animationSpec = spring(dampingRatio = 0.75f))
                        ) {
                            Text(
                                text = tab.displayName,
                                color = Color.White,
                                fontSize = 13.sp,
                                fontWeight = FontWeight.SemiBold,
                                maxLines = 1
                            )
                        }
                    }
                }
            }
        }
    }
}
