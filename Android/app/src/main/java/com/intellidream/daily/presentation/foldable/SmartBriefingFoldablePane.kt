package com.intellidream.daily.presentation.foldable

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.VolumeOff
import androidx.compose.material.icons.automirrored.rounded.VolumeUp
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.unit.dp
import com.intellidream.daily.briefing.SmartBriefingRepository
import com.intellidream.daily.database.HabitsRepository
import com.intellidream.daily.database.NewsRepository
import com.intellidream.daily.database.SmartLedgerRepository
import com.intellidream.daily.database.TagdosRepository
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.health.HealthDataRepository
import com.intellidream.daily.model.AppSettings
import com.intellidream.daily.model.BriefingTimeSlot
import com.intellidream.daily.model.UserProfile
import com.intellidream.daily.model.WeatherResponse
import com.intellidream.daily.presentation.briefing.SmartBriefingContent

/**
 * Embedded right-pane Smart Briefing presentation for foldables.
 * Hosts the rich diurnal typewriter narration and TTS speech audio without duplicate headers
 * or nested close buttons, featuring drag-down dismiss ergonomics.
 */
@Composable
fun SmartBriefingFoldablePane(
    repository: SmartBriefingRepository,
    userProfile: UserProfile?,
    settings: AppSettings,
    weather: WeatherResponse?,
    locationName: String,
    healthRepository: HealthDataRepository,
    habitsRepository: HabitsRepository,
    smartLedgerRepository: SmartLedgerRepository,
    tagdosRepository: TagdosRepository,
    newsRepository: NewsRepository,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier
) {
    val haptic = LocalHapticFeedback.current
    val activeBriefing by repository.activeBriefing.collectAsState()
    val isSpeaking by repository.isSpeaking.collectAsState()
    val slot = activeBriefing?.slot ?: BriefingTimeSlot.current()

    Column(
        modifier = modifier.fillMaxSize()
    ) {
        // Single unified header with circular 40dp close button, TTS action, and swipe-down dismiss
        FoldableDetailHeader(
            title = "Smart Briefing",
            icon = Icons.Rounded.AutoAwesome,
            iconTint = ThemeColors.accentCyan,
            subtitle = slot.displayName,
            onCloseClick = {
                repository.stopSpeech()
                onDismiss()
            },
            trailingContent = {
                activeBriefing?.let { rec ->
                    Box(
                        modifier = Modifier
                            .size(40.dp)
                            .shadow(4.dp, CircleShape)
                            .clip(CircleShape)
                            .background(
                                if (isSpeaking) ThemeColors.accentCyan.copy(alpha = 0.25f)
                                else Color(0xFF080F1E).copy(alpha = 0.72f)
                            )
                            .border(
                                1.dp,
                                if (isSpeaking) Brush.linearGradient(listOf(ThemeColors.accentCyan, ThemeColors.accentBlue))
                                else Brush.linearGradient(listOf(Color.White.copy(alpha = 0.40f), Color.White.copy(alpha = 0.10f))),
                                CircleShape
                            )
                            .clickable {
                                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                repository.toggleSpeechReadout(rec.narrative.fullConcatenatedText)
                            },
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = if (isSpeaking) Icons.AutoMirrored.Rounded.VolumeUp else Icons.AutoMirrored.Rounded.VolumeOff,
                            contentDescription = "Read Aloud",
                            tint = if (isSpeaking) ThemeColors.accentCyan else Color.White,
                            modifier = Modifier.size(18.dp)
                        )
                    }
                }
            }
        )

        // Typewriter narrative body (header is omitted to prevent duplicate navigation bars)
        SmartBriefingContent(
            repository = repository,
            userProfile = userProfile,
            settings = settings,
            weather = weather,
            locationName = locationName,
            healthRepository = healthRepository,
            habitsRepository = habitsRepository,
            smartLedgerRepository = smartLedgerRepository,
            tagdosRepository = tagdosRepository,
            newsRepository = newsRepository,
            onDismiss = onDismiss,
            showHeader = false,
            modifier = Modifier.fillMaxSize()
        )
    }
}
