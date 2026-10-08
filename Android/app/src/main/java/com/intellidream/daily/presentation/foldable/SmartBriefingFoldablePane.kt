package com.intellidream.daily.presentation.foldable

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.intellidream.daily.briefing.SmartBriefingRepository
import com.intellidream.daily.database.HabitsRepository
import com.intellidream.daily.database.NewsRepository
import com.intellidream.daily.database.SmartLedgerRepository
import com.intellidream.daily.database.TagdosRepository
import com.intellidream.daily.health.HealthDataRepository
import com.intellidream.daily.model.AppSettings
import com.intellidream.daily.model.UserProfile
import com.intellidream.daily.model.WeatherResponse
import com.intellidream.daily.presentation.briefing.SmartBriefingContent

/**
 * Embedded right-pane Smart Briefing presentation for foldables.
 * Hosts the rich diurnal typewriter narration and TTS speech audio without a ModalBottomSheet.
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
    Box(
        modifier = modifier
            .fillMaxSize()
            .clip(RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp))
    ) {
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
            modifier = Modifier.fillMaxSize()
        )
    }
}
