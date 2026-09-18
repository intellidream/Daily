package com.intellidream.daily.presentation.dashboard

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.designsystem.DailyAsyncImage
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.UserProfile
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
fun HeaderGreetingView(
    userProfile: UserProfile?,
    onAvatarTapped: () -> Unit,
    onCustomizeTapped: () -> Unit,
    onBriefingTapped: () -> Unit,
    modifier: Modifier = Modifier
) {
    val haptic = LocalHapticFeedback.current
    val firstName = userProfile?.firstName ?: "Friend"
    val formattedDate = remember {
        SimpleDateFormat("EEE, MMM d", Locale.US).format(Date()).uppercase()
    }

    // Gentle pulse animation for the smart briefing sparkle badge
    val infiniteTransition = rememberInfiniteTransition(label = "BriefingSparkleTransition")
    val pulseScale by infiniteTransition.animateFloat(
        initialValue = 1f,
        targetValue = 1.15f,
        animationSpec = infiniteRepeatable(
            animation = tween(1200),
            repeatMode = RepeatMode.Reverse
        ),
        label = "BriefingPulseScale"
    )

    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(top = 4.dp, bottom = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Left: Interactive Glass Avatar with Gradient Border & Live Sync Dot
        Box(
            modifier = Modifier
                .size(48.dp)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null
                ) {
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    onAvatarTapped()
                },
            contentAlignment = Alignment.Center
        ) {
            Box(
                modifier = Modifier
                    .size(48.dp)
                    .shadow(10.dp, CircleShape, ambientColor = ThemeColors.accentCyan, spotColor = ThemeColors.accentCyan)
                    .clip(CircleShape)
                    .border(
                        width = 2.dp,
                        brush = Brush.linearGradient(
                            listOf(ThemeColors.accentCyan, ThemeColors.accentBlue, Color(0xFF8A2BE2))
                        ),
                        shape = CircleShape
                    )
                    .background(
                        Brush.linearGradient(
                            listOf(ThemeColors.accentBlue.copy(alpha = 0.5f), ThemeColors.accentCyan.copy(alpha = 0.3f))
                        )
                    ),
                contentAlignment = Alignment.Center
            ) {
                val avatarUrl = userProfile?.avatarUrl
                val initial = (userProfile?.firstName?.take(1) ?: "G").uppercase()
                if (!avatarUrl.isNullOrBlank()) {
                    DailyAsyncImage(
                        url = avatarUrl,
                        contentDescription = "Profile Avatar",
                        modifier = Modifier
                            .size(44.dp)
                            .clip(CircleShape),
                        placeholder = {
                            Text(
                                text = initial,
                                color = Color.White,
                                fontSize = 19.sp,
                                fontWeight = FontWeight.Bold
                            )
                        }
                    )
                } else {
                    Text(
                        text = initial,
                        color = Color.White,
                        fontSize = 19.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
            }

            // Live Online Sync Status Dot (11dp emerald with 2dp dark border and green shadow)
            Box(
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .offset(x = 1.dp, y = 1.dp)
                    .size(12.dp)
                    .shadow(4.dp, CircleShape, ambientColor = Color(0xFF00FFB2), spotColor = Color(0xFF00FFB2))
                    .clip(CircleShape)
                    .background(Color(0xFF00FFB2))
                    .border(2.dp, Color(0xFF030609), CircleShape)
            )
        }

        Spacer(modifier = Modifier.width(12.dp))

        // Middle: Contextual Date Pill & Greeting (Click triggers Smart Briefing)
        Column(
            modifier = Modifier
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null
                ) {
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    onBriefingTapped()
                },
            verticalArrangement = Arrangement.spacedBy(3.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                // Micro Date Pill Badge
                Row(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(ThemeColors.accentCyan.copy(alpha = 0.12f))
                        .border(0.8.dp, ThemeColors.accentCyan.copy(alpha = 0.25f), CircleShape)
                        .padding(horizontal = 7.dp, vertical = 3.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .size(4.5.dp)
                            .clip(CircleShape)
                            .background(ThemeColors.accentCyan)
                    )
                    Text(
                        text = formattedDate,
                        color = ThemeColors.accentCyan,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        maxLines = 1
                    )
                }

                // Ambient Briefing Sparkle
                Icon(
                    imageVector = Icons.Rounded.AutoAwesome,
                    contentDescription = "Smart Briefing",
                    tint = ThemeColors.accentCyan,
                    modifier = Modifier
                        .size(12.dp)
                        .scale(pulseScale)
                )
            }

            Text(
                text = "Hi, $firstName!",
                color = Color.White,
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold
            )
        }

        Spacer(
            modifier = Modifier
                .weight(1f)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null
                ) {
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    onBriefingTapped()
                }
        )

        // Right: Two 40x40 Circle Glass Action Buttons (Customize Grid & Settings)
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Customize Button
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .shadow(4.dp, CircleShape)
                    .clip(CircleShape)
                    .background(Color(0xFF080F1E).copy(alpha = 0.72f))
                    .border(
                        1.dp,
                        Brush.linearGradient(
                            listOf(Color.White.copy(alpha = 0.40f), Color.White.copy(alpha = 0.10f))
                        ),
                        CircleShape
                    )
                    .clickable {
                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                        onCustomizeTapped()
                    },
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Rounded.Tune,
                    contentDescription = "Customize Dashboard",
                    tint = Color.White.copy(alpha = 0.85f),
                    modifier = Modifier.size(16.dp)
                )
            }

            // Settings Button
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .shadow(4.dp, CircleShape)
                    .clip(CircleShape)
                    .background(Color(0xFF080F1E).copy(alpha = 0.72f))
                    .border(
                        1.dp,
                        Brush.linearGradient(
                            listOf(Color.White.copy(alpha = 0.40f), Color.White.copy(alpha = 0.10f))
                        ),
                        CircleShape
                    )
                    .clickable {
                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                        onAvatarTapped()
                    },
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Rounded.Settings,
                    contentDescription = "Settings",
                    tint = Color.White.copy(alpha = 0.85f),
                    modifier = Modifier.size(16.dp)
                )
            }
        }
    }
}
