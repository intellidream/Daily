package com.intellidream.daily.presentation

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
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CloudSync
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Psychology
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
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
import com.intellidream.daily.model.AppTheme
import com.intellidream.daily.model.AuthProvider
import com.intellidream.daily.model.UserProfile
import com.intellidream.daily.model.WeatherUnitSystem

@Composable
fun SettingsScreen(
    settings: AppSettings,
    userProfile: UserProfile?,
    onUpdateSettings: ((AppSettings) -> AppSettings) -> Unit,
    onSignOutClick: () -> Unit,
    onBackClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(brush = ThemeColors.backgroundGradient)
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
        ) {
            // Top Bar
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                GlassButton(
                    onClick = onBackClick,
                    cornerRadius = 12.dp,
                    paddingHorizontal = 10.dp,
                    paddingVertical = 8.dp
                ) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                        contentDescription = "Back",
                        tint = Color.White,
                        modifier = Modifier.size(20.dp)
                    )
                }

                Spacer(modifier = Modifier.width(14.dp))

                Text(
                    text = "Settings",
                    color = Color.White,
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Bold
                )
            }

            // Scrollable Content
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                // 1. Account Section
                item {
                    AccountSettingsCard(
                        userProfile = userProfile,
                        onSignOutClick = onSignOutClick
                    )
                }

                // 2. Appearance Section
                item {
                    AppearanceSettingsCard(
                        settings = settings,
                        onUpdateSettings = onUpdateSettings
                    )
                }

                // 3. Health & Habits Section
                item {
                    HealthHabitsSettingsCard(
                        settings = settings,
                        onUpdateSettings = onUpdateSettings
                    )
                }

                // 4. Weather Section
                item {
                    WeatherSettingsCard(
                        settings = settings,
                        onUpdateSettings = onUpdateSettings
                    )
                }

                // 5. Cloud & Sync Section
                item {
                    CloudSyncSettingsCard(
                        settings = settings,
                        onUpdateSettings = onUpdateSettings
                    )
                }

                // 6. Smart Briefing Section
                item {
                    SmartBriefingSettingsCard(
                        settings = settings,
                        onUpdateSettings = onUpdateSettings
                    )
                }

                // 7. About Section
                item {
                    AboutSettingsCard()
                }

                item {
                    Spacer(modifier = Modifier.height(32.dp).navigationBarsPadding())
                }
            }
        }
    }
}

@Composable
private fun SectionHeader(icon: ImageVector, title: String) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.padding(bottom = 12.dp)
    ) {
        Icon(
            imageVector = icon,
            contentDescription = title,
            tint = ThemeColors.accentCyan,
            modifier = Modifier.size(18.dp)
        )
        Text(
            text = title,
            color = Color.White,
            fontSize = 16.sp,
            fontWeight = FontWeight.SemiBold
        )
    }
}

@Composable
private fun AccountSettingsCard(
    userProfile: UserProfile?,
    onSignOutClick: () -> Unit
) {
    GlassCard(modifier = Modifier.fillMaxWidth()) {
        Column {
            SectionHeader(icon = Icons.Filled.Person, title = "Account")

            val profile = userProfile ?: UserProfile.guest
            val isGuest = profile.provider == AuthProvider.Guest

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                // Avatar Circle
                Box(
                    modifier = Modifier
                        .size(50.dp)
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.15f))
                        .border(
                            width = 2.dp,
                            brush = ThemeColors.activeTabIndicatorBrush,
                            shape = CircleShape
                        ),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = profile.firstName.take(1).uppercase(),
                        color = Color.White,
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold
                    )
                }

                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = profile.fullName ?: "Hi, ${profile.firstName}!",
                        color = Color.White,
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        text = if (isGuest) "Guest Mode (Local Only)" else (profile.email ?: "Signed In"),
                        color = if (isGuest) ThemeColors.warning else ThemeColors.fgMutedDark,
                        fontSize = 12.sp
                    )
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                        modifier = Modifier.padding(top = 2.dp)
                    ) {
                        Box(
                            modifier = Modifier
                                .size(6.dp)
                                .clip(CircleShape)
                                .background(if (isGuest) ThemeColors.warning else ThemeColors.success)
                        )
                        Text(
                            text = profile.provider.displayName,
                            color = ThemeColors.fgMutedDark,
                            fontSize = 11.sp
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(14.dp))
            HorizontalDivider(color = Color.White.copy(alpha = 0.12f))
            Spacer(modifier = Modifier.height(14.dp))

            GlassButton(
                onClick = onSignOutClick,
                modifier = Modifier.fillMaxWidth(),
                cornerRadius = 10.dp,
                paddingVertical = 10.dp
            ) {
                Text(
                    text = if (isGuest) "Sign In with an Account" else "Sign Out",
                    color = if (isGuest) ThemeColors.accentBlue else ThemeColors.error,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.fillMaxWidth(),
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center
                )
            }
        }
    }
}

@Composable
private fun AppearanceSettingsCard(
    settings: AppSettings,
    onUpdateSettings: ((AppSettings) -> AppSettings) -> Unit
) {
    GlassCard(modifier = Modifier.fillMaxWidth()) {
        Column {
            SectionHeader(icon = Icons.Filled.Palette, title = "Appearance")

            // Theme Picker
            Text(
                text = "Application Theme",
                color = Color.White,
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium
            )
            Spacer(modifier = Modifier.height(8.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                AppTheme.entries.forEach { theme ->
                    val isSelected = settings.theme == theme
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .clip(RoundedCornerShape(10.dp))
                            .background(if (isSelected) ThemeColors.accentBlue.copy(alpha = 0.4f) else Color.White.copy(alpha = 0.08f))
                            .border(
                                width = 1.dp,
                                color = if (isSelected) ThemeColors.accentCyan else Color.White.copy(alpha = 0.15f),
                                shape = RoundedCornerShape(10.dp)
                            )
                            .clickable { onUpdateSettings { it.copy(theme = theme) } }
                            .padding(vertical = 10.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = theme.displayName,
                            color = if (isSelected) Color.White else ThemeColors.textSecondary,
                            fontSize = 13.sp,
                            fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(14.dp))
            HorizontalDivider(color = Color.White.copy(alpha = 0.12f))
            Spacer(modifier = Modifier.height(14.dp))

            // Glass Intensity Picker
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Liquid Glass Intensity",
                    color = Color.White,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium
                )
                Text(
                    text = settings.glassIntensity.displayName,
                    color = ThemeColors.accentCyan,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }
            Spacer(modifier = Modifier.height(8.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                com.intellidream.daily.model.GlassIntensity.entries.forEach { intensity ->
                    val isSelected = settings.glassIntensity == intensity
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .clip(RoundedCornerShape(10.dp))
                            .background(if (isSelected) ThemeColors.accentBlue.copy(alpha = 0.4f) else Color.White.copy(alpha = 0.08f))
                            .border(
                                width = 1.dp,
                                color = if (isSelected) ThemeColors.accentCyan else Color.White.copy(alpha = 0.15f),
                                shape = RoundedCornerShape(10.dp)
                            )
                            .clickable { onUpdateSettings { it.copy(glassIntensity = intensity) } }
                            .padding(vertical = 10.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = intensity.displayName,
                            color = if (isSelected) Color.White else ThemeColors.textSecondary,
                            fontSize = 13.sp,
                            fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(14.dp))
            HorizontalDivider(color = Color.White.copy(alpha = 0.12f))
            Spacer(modifier = Modifier.height(14.dp))

            // Haptics Toggle
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(
                        text = "Haptic Feedback",
                        color = Color.White,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Medium
                    )
                    Text(
                        text = "Subtle tactile responses for buttons and switches",
                        color = ThemeColors.textMuted,
                        fontSize = 11.sp
                    )
                }
                Switch(
                    checked = settings.hapticsEnabled,
                    onCheckedChange = { onUpdateSettings { s -> s.copy(hapticsEnabled = it) } },
                    colors = SwitchDefaults.colors(
                        checkedThumbColor = Color.White,
                        checkedTrackColor = ThemeColors.accentBlue
                    )
                )
            }
        }
    }
}

@Composable
private fun HealthHabitsSettingsCard(
    settings: AppSettings,
    onUpdateSettings: ((AppSettings) -> AppSettings) -> Unit
) {
    GlassCard(modifier = Modifier.fillMaxWidth()) {
        Column {
            SectionHeader(icon = Icons.Filled.Favorite, title = "Health & Habits Goals")

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(text = "Sleep Target", color = Color.White, fontSize = 14.sp)
                    Text(text = "Nocturnal target duration", color = ThemeColors.textMuted, fontSize = 11.sp)
                }
                Text(
                    text = "${settings.healthSleepTargetHours} hrs",
                    color = ThemeColors.accentCyan,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }

            Spacer(modifier = Modifier.height(12.dp))
            HorizontalDivider(color = Color.White.copy(alpha = 0.12f))
            Spacer(modifier = Modifier.height(12.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(text = "Hydration Target", color = Color.White, fontSize = 14.sp)
                    Text(text = "Daily fluid intake goal", color = ThemeColors.textMuted, fontSize = 11.sp)
                }
                Text(
                    text = "${settings.habitsWaterTargetLiters} L",
                    color = ThemeColors.accentCyan,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }
    }
}

@Composable
private fun WeatherSettingsCard(
    settings: AppSettings,
    onUpdateSettings: ((AppSettings) -> AppSettings) -> Unit
) {
    GlassCard(modifier = Modifier.fillMaxWidth()) {
        Column {
            SectionHeader(icon = Icons.Filled.WbSunny, title = "Weather & Atmosphere")

            Text(text = "Unit System", color = Color.White, fontSize = 14.sp)
            Spacer(modifier = Modifier.height(8.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                WeatherUnitSystem.entries.forEach { unit ->
                    val isSelected = settings.weatherUnitSystem == unit
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .clip(RoundedCornerShape(10.dp))
                            .background(if (isSelected) ThemeColors.accentBlue.copy(alpha = 0.4f) else Color.White.copy(alpha = 0.08f))
                            .border(
                                width = 1.dp,
                                color = if (isSelected) ThemeColors.accentCyan else Color.White.copy(alpha = 0.15f),
                                shape = RoundedCornerShape(10.dp)
                            )
                            .clickable { onUpdateSettings { it.copy(weatherUnitSystem = unit) } }
                            .padding(vertical = 10.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = unit.displayName,
                            color = if (isSelected) Color.White else ThemeColors.textSecondary,
                            fontSize = 13.sp,
                            fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(14.dp))
            HorizontalDivider(color = Color.White.copy(alpha = 0.12f))
            Spacer(modifier = Modifier.height(14.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(text = "Always Auto-Location", color = Color.White, fontSize = 14.sp)
                    Text(text = "Use GPS + IP fallback for weather updates", color = ThemeColors.textMuted, fontSize = 11.sp)
                }
                Switch(
                    checked = settings.weatherAlwaysAutoLocation,
                    onCheckedChange = { onUpdateSettings { s -> s.copy(weatherAlwaysAutoLocation = it) } },
                    colors = SwitchDefaults.colors(
                        checkedThumbColor = Color.White,
                        checkedTrackColor = ThemeColors.accentBlue
                    )
                )
            }
        }
    }
}

@Composable
private fun CloudSyncSettingsCard(
    settings: AppSettings,
    onUpdateSettings: ((AppSettings) -> AppSettings) -> Unit
) {
    GlassCard(modifier = Modifier.fillMaxWidth()) {
        Column {
            SectionHeader(icon = Icons.Filled.CloudSync, title = "Cloud & Sync")

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(text = "Supabase Cloud Sync", color = Color.White, fontSize = 14.sp)
                    Text(text = "Realtime multi-device database synchronization", color = ThemeColors.textMuted, fontSize = 11.sp)
                }
                Switch(
                    checked = settings.cloudSyncEnabled,
                    onCheckedChange = { onUpdateSettings { s -> s.copy(cloudSyncEnabled = it) } },
                    colors = SwitchDefaults.colors(
                        checkedThumbColor = Color.White,
                        checkedTrackColor = ThemeColors.accentBlue
                    )
                )
            }
        }
    }
}

@Composable
private fun SmartBriefingSettingsCard(
    settings: AppSettings,
    onUpdateSettings: ((AppSettings) -> AppSettings) -> Unit
) {
    GlassCard(modifier = Modifier.fillMaxWidth()) {
        Column {
            SectionHeader(icon = Icons.Filled.Psychology, title = "Smart Briefing & Gemini")

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(text = "Morning Briefing", color = Color.White, fontSize = 14.sp)
                    Text(text = "AI executive synthesis generated every morning", color = ThemeColors.textMuted, fontSize = 11.sp)
                }
                Switch(
                    checked = settings.smartBriefingAutoMorning,
                    onCheckedChange = { onUpdateSettings { s -> s.copy(smartBriefingAutoMorning = it) } },
                    colors = SwitchDefaults.colors(
                        checkedThumbColor = Color.White,
                        checkedTrackColor = ThemeColors.accentBlue
                    )
                )
            }
        }
    }
}

@Composable
private fun AboutSettingsCard() {
    GlassCard(modifier = Modifier.fillMaxWidth()) {
        Column {
            SectionHeader(icon = Icons.Filled.Info, title = "About DayOne Android")
            Text(
                text = "DayOne Native Android • Version 1.0.0",
                color = Color.White,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = "Pure Kotlin with Jetpack Compose, Room local-first SQLite cache, Supabase PostgreSQL sync, and tactile Liquid Glass design system matching iOS & DailyCore.",
                color = ThemeColors.textSecondary,
                fontSize = 12.sp,
                lineHeight = 17.sp
            )
        }
    }
}
