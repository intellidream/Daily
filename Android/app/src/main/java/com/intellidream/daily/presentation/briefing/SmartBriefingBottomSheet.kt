package com.intellidream.daily.presentation.briefing

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Cloud
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.NightsStay
import androidx.compose.material.icons.rounded.TaskAlt
import androidx.compose.material.icons.rounded.WbSunny
import androidx.compose.material.icons.rounded.WaterDrop
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
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
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.GlassIntensity
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.UserProfile
import com.intellidream.daily.model.WeatherResponse
import java.util.Calendar
import kotlin.math.roundToInt

enum class DiurnalSlot(
    val title: String,
    val timeRange: String,
    val greeting: String,
    val closingText: String,
    val icon: ImageVector,
    val gradientColors: List<Color>
) {
    MORNING(
        "Morning Briefing",
        "05:00 – 11:59",
        "Good morning",
        "Have a great day!",
        Icons.Rounded.WbSunny,
        listOf(Color(0xFFFF9A3D), Color(0xFFFF5E62), Color(0xFF7B2CBF))
    ),
    INTRADAY(
        "Intra-day Briefing",
        "12:00 – 16:59",
        "Have a wonderful day",
        "Have a productive day!",
        Icons.Rounded.WbSunny,
        listOf(Color(0xFF00F5D4), Color(0xFF00BBF9), Color(0xFF4361EE))
    ),
    EVENING(
        "Evening Review",
        "17:00 – 21:59",
        "Good evening",
        "Enjoy a restful evening!",
        Icons.Rounded.NightsStay,
        listOf(Color(0xFFF72585), Color(0xFF7209B7), Color(0xFF3A0CA3))
    ),
    NIGHTLY(
        "Nightly Wind-Down",
        "22:00 – 04:59",
        "Peaceful night",
        "Sleep tight & rest well!",
        Icons.Rounded.NightsStay,
        listOf(Color(0xFF3F37C9), Color(0xFF480CA8), Color(0xFF03071E))
    );

    companion object {
        fun current(): DiurnalSlot {
            val hour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
            return when (hour) {
                in 5..11 -> MORNING
                in 12..16 -> INTRADAY
                in 17..21 -> EVENING
                else -> NIGHTLY
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SmartBriefingBottomSheet(
    userProfile: UserProfile?,
    weather: WeatherResponse?,
    waterTotalMl: Double,
    waterGoalMl: Double,
    smokesCount: Int,
    smokesBaseline: Int,
    onDismiss: () -> Unit
) {
    val haptic = LocalHapticFeedback.current
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val slot = remember { DiurnalSlot.current() }
    val firstName = userProfile?.firstName ?: "Friend"

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Color(0xFF070E1A),
        contentColor = Color.White,
        tonalElevation = 0.dp,
        dragHandle = null,
        shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp)
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .fillMaxHeight(0.90f)
                .background(
                    Brush.verticalGradient(
                        listOf(
                            Color(0xFF0A1426),
                            Color(0xFF060B14)
                        )
                    )
                )
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 20.dp, vertical = 16.dp)
                    .verticalScroll(rememberScrollState())
            ) {
                // Top Navigation Bar
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // Diurnal Slot Status Pill
                    Row(
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(slot.gradientColors.first().copy(alpha = 0.18f))
                            .border(1.dp, slot.gradientColors.first().copy(alpha = 0.40f), CircleShape)
                            .padding(horizontal = 12.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Icon(
                            imageVector = slot.icon,
                            contentDescription = null,
                            tint = slot.gradientColors.first(),
                            modifier = Modifier.size(14.dp)
                        )
                        Text(
                            text = "${slot.title.uppercase()} · ${slot.timeRange}",
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White
                        )
                    }

                    // Close Button
                    Box(
                        modifier = Modifier
                            .size(34.dp)
                            .clip(CircleShape)
                            .background(Color.White.copy(alpha = 0.08f))
                            .border(1.dp, Color.White.copy(alpha = 0.15f), CircleShape)
                            .clickable {
                                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                onDismiss()
                            },
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.Close,
                            contentDescription = "Close",
                            tint = Color.White,
                            modifier = Modifier.size(16.dp)
                        )
                    }
                }

                Spacer(modifier = Modifier.height(18.dp))

                // Diurnal Hero Greeting
                Text(
                    text = "${slot.greeting}, $firstName!",
                    fontSize = 26.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White
                )
                Text(
                    text = "Here is your synchronized intelligence briefing.",
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                    color = ThemeColors.textSecondary
                )

                Spacer(modifier = Modifier.height(20.dp))

                // Card 1: Atmospheric Telemetry
                GlassCard(
                    modifier = Modifier.fillMaxWidth(),
                    cornerRadius = 20.dp,
                    padding = 18.dp,
                    intensity = GlassIntensity.Medium
                ) {
                    Column {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Icon(
                                imageVector = Icons.Rounded.Cloud,
                                contentDescription = null,
                                tint = ThemeColors.accentCyan,
                                modifier = Modifier.size(18.dp)
                            )
                            Text(
                                text = "Atmosphere & Conditions",
                                fontSize = 15.sp,
                                fontWeight = FontWeight.Bold,
                                color = ThemeColors.accentCyan
                            )
                        }
                        Spacer(modifier = Modifier.height(8.dp))
                        if (weather != null) {
                            val temp = weather.main.temp.roundToInt()
                            val desc = weather.weather.firstOrNull()?.description?.replaceFirstChar { it.uppercase() } ?: "Clear"
                            Text(
                                text = "$temp° · $desc",
                                fontSize = 18.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color.White
                            )
                            Spacer(modifier = Modifier.height(4.dp))
                            Text(
                                text = "Humidity ${weather.main.humidity}% · Wind ${weather.wind?.speed?.roundToInt() ?: 0} m/s",
                                fontSize = 13.sp,
                                color = ThemeColors.textSecondary
                            )
                        } else {
                            Text(
                                text = "Telemetry syncing in the background...",
                                fontSize = 13.sp,
                                color = ThemeColors.textSecondary
                            )
                        }
                    }
                }

                Spacer(modifier = Modifier.height(14.dp))

                // Card 2: Habit Telemetry (Water & Smokes)
                GlassCard(
                    modifier = Modifier.fillMaxWidth(),
                    cornerRadius = 20.dp,
                    padding = 18.dp,
                    intensity = GlassIntensity.Medium
                ) {
                    Column {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Icon(
                                imageVector = Icons.Rounded.WaterDrop,
                                contentDescription = null,
                                tint = Color(0xFF00FFB2),
                                modifier = Modifier.size(18.dp)
                            )
                            Text(
                                text = "Habits & Cravings",
                                fontSize = 15.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color(0xFF00FFB2)
                            )
                        }
                        Spacer(modifier = Modifier.height(10.dp))
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Column {
                                Text(
                                    text = "HYDRATION",
                                    fontSize = 10.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = ThemeColors.textSecondary
                                )
                                Text(
                                    text = "${waterTotalMl.toInt()} / ${waterGoalMl.toInt()} ml",
                                    fontSize = 16.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = Color.White
                                )
                            }
                            Column {
                                Text(
                                    text = "TOBACCO LIMIT",
                                    fontSize = 10.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = ThemeColors.textSecondary
                                )
                                Text(
                                    text = "$smokesCount / $smokesBaseline max",
                                    fontSize = 16.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = if (smokesCount > smokesBaseline) Color(0xFFFF3B30) else Color.White
                                )
                            }
                        }
                    }
                }

                Spacer(modifier = Modifier.height(14.dp))

                // Card 3: Health & Recovery
                GlassCard(
                    modifier = Modifier.fillMaxWidth(),
                    cornerRadius = 20.dp,
                    padding = 18.dp,
                    intensity = GlassIntensity.Medium
                ) {
                    Column {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Icon(
                                imageVector = Icons.Rounded.Favorite,
                                contentDescription = null,
                                tint = Color(0xFFFF5252),
                                modifier = Modifier.size(18.dp)
                            )
                            Text(
                                text = "Vitals & Daily Readiness",
                                fontSize = 15.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color(0xFFFF5252)
                            )
                        }
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            text = "Daily readiness score 92% · Sleep Target 8.0h",
                            fontSize = 14.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = Color.White
                        )
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(
                            text = "Biometric vitals synchronized locally with Room dirty tracking.",
                            fontSize = 12.sp,
                            color = ThemeColors.textSecondary
                        )
                    }
                }

                Spacer(modifier = Modifier.height(24.dp))

                // Diurnal Closing Action Button
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .shadow(8.dp, RoundedCornerShape(16.dp))
                        .clip(RoundedCornerShape(16.dp))
                        .background(
                            Brush.horizontalGradient(slot.gradientColors)
                        )
                        .clickable {
                            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                            onDismiss()
                        }
                        .padding(vertical = 16.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Icon(
                            imageVector = slot.icon,
                            contentDescription = null,
                            tint = Color.White,
                            modifier = Modifier.size(18.dp)
                        )
                        Text(
                            text = slot.closingText,
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White
                        )
                    }
                }

                Spacer(modifier = Modifier.height(30.dp))
            }
        }
    }
}
