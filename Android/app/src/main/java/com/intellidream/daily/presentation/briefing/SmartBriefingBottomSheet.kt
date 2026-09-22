package com.intellidream.daily.presentation.briefing

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
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
import androidx.compose.material.icons.automirrored.rounded.VolumeOff
import androidx.compose.material.icons.automirrored.rounded.VolumeUp
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Checklist
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Cloud
import androidx.compose.material.icons.rounded.CreditCard
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.Newspaper
import androidx.compose.material.icons.rounded.NightsStay
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.SelfImprovement
import androidx.compose.material.icons.rounded.WaterDrop
import androidx.compose.material.icons.rounded.WbSunny
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.briefing.SmartBriefingRepository
import com.intellidream.daily.database.HabitsRepository
import com.intellidream.daily.database.NewsRepository
import com.intellidream.daily.database.SmartLedgerRepository
import com.intellidream.daily.database.TagdosRepository
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.health.HealthDataRepository
import com.intellidream.daily.model.AppSettings
import com.intellidream.daily.model.BriefingCardItem
import com.intellidream.daily.model.BriefingTimeSlot
import com.intellidream.daily.model.SmartBriefingRecord
import com.intellidream.daily.model.UserProfile
import com.intellidream.daily.model.WeatherResponse
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Signature Liquid Glass modal overlay presenting the streamlined Smart Briefing across Morning,
 * Intra-day, Evening, and Nightly phases with progressive sequential streaming, dynamic luminous
 * border focus, contextual metric pills, TTS voice narration, and diurnal action buttons.
 * Forensic parity with iOS Daily [SmartBriefingOverlayView.swift].
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SmartBriefingBottomSheet(
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
    onDismiss: () -> Unit
) {
    val haptic = LocalHapticFeedback.current
    val coroutineScope = rememberCoroutineScope()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    val activeBriefing by repository.activeBriefing.collectAsState()
    val isLoading by repository.isLoading.collectAsState()
    val isSpeaking by repository.isSpeaking.collectAsState()

    var record by remember { mutableStateOf<SmartBriefingRecord?>(activeBriefing) }
    var revealedGlobalWordIndex by remember { mutableIntStateOf(0) }
    var activeCardIndex by remember { mutableIntStateOf(0) }
    var isFinished by remember { mutableStateOf(false) }

    var streamingJob by remember { mutableStateOf<Job?>(null) }

    val firstName = userProfile?.firstName ?: "Friend"
    val userId = userProfile?.id ?: "guest"
    val slot = record?.slot ?: BriefingTimeSlot.current()

    // Aurora gradient colors parsed from slot
    val auraColors = remember(slot) {
        slot.auraGradientHex.map {
            try {
                Color(android.graphics.Color.parseColor(it))
            } catch (_: Exception) {
                ThemeColors.accentCyan
            }
        }
    }

    // Clean up TTS when dismissed
    DisposableEffect(Unit) {
        onDispose {
            repository.stopSpeech()
        }
    }

    // Fetch or generate briefing on launch
    LaunchedEffect(Unit) {
        val rec = repository.getOrGenerateBriefing(
            forceRefresh = false,
            userName = firstName,
            userId = userId,
            settings = settings,
            weather = weather,
            locationName = locationName,
            healthRepository = healthRepository,
            habitsRepository = habitsRepository,
            smartLedgerRepository = smartLedgerRepository,
            tagdosRepository = tagdosRepository,
            newsRepository = newsRepository
        )
        record = rec
    }

    // Start typewriter / word-by-word streaming when record is ready
    LaunchedEffect(record) {
        val currentRec = record ?: return@LaunchedEffect
        val cardItems = repository.buildCardItems(currentRec)
        if (cardItems.isEmpty()) return@LaunchedEffect

        val wordsPerCard = cardItems.map { item ->
            item.text.split(Regex("\\s+")).filter { it.isNotBlank() }
        }
        val totalWords = wordsPerCard.sumOf { it.size }

        revealedGlobalWordIndex = 0
        activeCardIndex = 0
        isFinished = false

        streamingJob?.cancel()
        streamingJob = coroutineScope.launch {
            var globalIdx = 0
            for (cardIdx in wordsPerCard.indices) {
                activeCardIndex = cardIdx
                val words = wordsPerCard[cardIdx]
                for (word in words) {
                    globalIdx++
                    revealedGlobalWordIndex = globalIdx
                    delay(38L) // Fast, smooth typewriter cadence (matches iOS 0.035s)
                }
                delay(120L) // Subtle pause between cards
            }
            isFinished = true
            repository.markBriefingAsRead()
        }
    }

    fun completeInstantly(cardCount: Int, totalWords: Int) {
        streamingJob?.cancel()
        revealedGlobalWordIndex = totalWords + 10
        activeCardIndex = cardCount
        isFinished = true
        repository.markBriefingAsRead()
    }

    ModalBottomSheet(
        onDismissRequest = {
            repository.stopSpeech()
            onDismiss()
        },
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
                .fillMaxHeight(0.92f)
                .background(
                    Brush.verticalGradient(
                        listOf(
                            Color(0xFF091222),
                            Color(0xFF050A14),
                            Color.Black
                        )
                    )
                )
        ) {
            Column(
                modifier = Modifier.fillMaxSize()
            ) {
                // 1. Navigation Action Bar with Diurnal Greeting Status Pill
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp, vertical = 14.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // Diurnal Slot Status Pill (Matches iOS)
                    Row(
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(Color(0xFF080F1E).copy(alpha = 0.85f))
                            .border(
                                width = 1.dp,
                                brush = Brush.linearGradient(
                                    listOf(ThemeColors.accentCyan.copy(alpha = 0.45f), Color.White.copy(alpha = 0.18f))
                                ),
                                shape = CircleShape
                            )
                            .padding(horizontal = 14.dp, vertical = 7.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        val slotIcon: ImageVector = when (slot) {
                            BriefingTimeSlot.MORNING -> Icons.Rounded.WbSunny
                            BriefingTimeSlot.INTRADAY -> Icons.Rounded.WbSunny
                            BriefingTimeSlot.EVENING -> Icons.Rounded.NightsStay
                            BriefingTimeSlot.NIGHTLY -> Icons.Rounded.NightsStay
                        }
                        Icon(
                            imageVector = slotIcon,
                            contentDescription = null,
                            tint = ThemeColors.accentCyan,
                            modifier = Modifier.size(13.dp)
                        )
                        Text(
                            text = slot.diurnalGreeting(firstName),
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White.copy(alpha = 0.95f)
                        )
                    }

                    // Right Actions: TTS Speaker + Refresh + Close
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        // TTS Speaker Toggle
                        record?.let { rec ->
                            Box(
                                modifier = Modifier
                                    .size(34.dp)
                                    .clip(CircleShape)
                                    .background(if (isSpeaking) ThemeColors.accentCyan.copy(alpha = 0.25f) else Color.White.copy(alpha = 0.08f))
                                    .border(1.dp, if (isSpeaking) ThemeColors.accentCyan else Color.White.copy(alpha = 0.15f), CircleShape)
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
                                    modifier = Modifier.size(16.dp)
                                )
                            }
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
                                    repository.stopSpeech()
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
                }

                // 2. Body Content
                if (isLoading || record == null) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .weight(1f),
                        contentAlignment = Alignment.Center
                    ) {
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(14.dp)
                        ) {
                            CircularProgressIndicator(
                                color = ThemeColors.accentCyan,
                                modifier = Modifier.size(36.dp),
                                strokeWidth = 3.dp
                            )
                            Text(
                                text = "Synthesizing cross-hub briefing...",
                                color = ThemeColors.textSecondary,
                                fontSize = 13.sp,
                                fontWeight = FontWeight.Medium
                            )
                        }
                    }
                } else {
                    val currentRec = record!!
                    val items = remember(currentRec) { repository.buildCardItems(currentRec) }
                    val wordsPerCard = remember(items) {
                        items.map { item ->
                            item.text.split(Regex("\\s+")).filter { it.isNotBlank() }
                        }
                    }
                    val totalWords = remember(wordsPerCard) { wordsPerCard.sumOf { it.size } }

                    // Calculate start indices for each card
                    val cardStartIndices = remember(wordsPerCard) {
                        val offsets = mutableListOf<Int>()
                        var running = 0
                        for (w in wordsPerCard) {
                            offsets.add(running)
                            running += w.size
                        }
                        offsets
                    }

                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .verticalScroll(rememberScrollState())
                            .clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null
                            ) {
                                if (!isFinished) {
                                    completeInstantly(items.size, totalWords)
                                }
                            }
                            .padding(horizontal = 20.dp, vertical = 6.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        // Sequential Card Reveal
                        items.forEachIndexed { index, item ->
                            if (isFinished || index <= activeCardIndex) {
                                AnimatedVisibility(
                                    visible = true,
                                    enter = fadeIn(tween(220)) + slideInVertically(
                                        initialOffsetY = { 20 },
                                        animationSpec = tween(220, easing = FastOutSlowInEasing)
                                    )
                                ) {
                                    val words = wordsPerCard.getOrElse(index) { emptyList() }
                                    val startIdx = cardStartIndices.getOrElse(index) { 0 }
                                    BriefingCard(
                                        item = item,
                                        index = index,
                                        words = words,
                                        startIndex = startIdx,
                                        revealedGlobalWordIndex = revealedGlobalWordIndex,
                                        activeCardIndex = activeCardIndex,
                                        isFinished = isFinished
                                    )
                                }
                            }
                        }

                        // Tap to Reveal Instantly hint
                        if (!isFinished) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(top = 4.dp),
                                horizontalArrangement = Arrangement.Center,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(
                                    imageVector = Icons.Rounded.AutoAwesome,
                                    contentDescription = null,
                                    tint = ThemeColors.accentCyan,
                                    modifier = Modifier.size(11.dp)
                                )
                                Spacer(modifier = Modifier.width(5.dp))
                                Text(
                                    text = "Tap anywhere to reveal instantly",
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.Medium,
                                    color = ThemeColors.textMuted
                                )
                            }
                        }

                        // Contextual Diurnal Bottom Action Button (blooms in at the end)
                        if (isFinished || activeCardIndex >= items.size - 1) {
                            val wish = currentRec.narrative.closingWish ?: slot.defaultClosingWish
                            val buttonIcon: ImageVector = when (slot) {
                                BriefingTimeSlot.MORNING -> Icons.Rounded.WbSunny
                                BriefingTimeSlot.INTRADAY -> Icons.Rounded.WbSunny
                                BriefingTimeSlot.EVENING -> Icons.Rounded.NightsStay
                                BriefingTimeSlot.NIGHTLY -> Icons.Rounded.NightsStay
                            }

                            Spacer(modifier = Modifier.height(6.dp))

                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .shadow(10.dp, RoundedCornerShape(18.dp))
                                    .clip(RoundedCornerShape(18.dp))
                                    .background(
                                        Brush.horizontalGradient(auraColors)
                                    )
                                    .clickable {
                                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                        repository.stopSpeech()
                                        repository.markBriefingAsRead()
                                        onDismiss()
                                    }
                                    .padding(vertical = 15.dp),
                                contentAlignment = Alignment.Center
                            ) {
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                                ) {
                                    Icon(
                                        imageVector = buttonIcon,
                                        contentDescription = null,
                                        tint = Color.White,
                                        modifier = Modifier.size(18.dp)
                                    )
                                    Text(
                                        text = wish,
                                        fontSize = 15.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = Color.White
                                    )
                                }
                            }
                        }

                        Spacer(modifier = Modifier.height(36.dp))
                    }
                }
            }
        }
    }
}

@Composable
private fun BriefingCard(
    item: BriefingCardItem,
    index: Int,
    words: List<String>,
    startIndex: Int,
    revealedGlobalWordIndex: Int,
    activeCardIndex: Int,
    isFinished: Boolean
) {
    val count = words.size
    val isCompleted = isFinished || (index < activeCardIndex) || (revealedGlobalWordIndex >= startIndex + count)
    val isCurrentlyTyping = !isFinished && (index == activeCardIndex) && (revealedGlobalWordIndex >= startIndex && revealedGlobalWordIndex < startIndex + count)

    val visibleText = when {
        isCompleted -> item.text
        isCurrentlyTyping -> {
            val localCount = (revealedGlobalWordIndex - startIndex).coerceIn(0, count)
            words.take(localCount).joinToString(" ")
        }
        else -> ""
    }

    val iconVector: ImageVector = when (item.id) {
        "weather" -> Icons.Rounded.Cloud
        "health" -> Icons.Rounded.Favorite
        "stress" -> Icons.Rounded.SelfImprovement
        "habits" -> Icons.Rounded.WaterDrop
        "finances" -> Icons.Rounded.CreditCard
        "tagdos" -> Icons.Rounded.Checklist
        "news" -> Icons.Rounded.Newspaper
        else -> Icons.Rounded.AutoAwesome
    }

    val accentColor = try {
        Color(android.graphics.Color.parseColor(item.accentColorHex))
    } catch (_: Exception) {
        ThemeColors.accentCyan
    }

    val infiniteTransition = rememberInfiniteTransition(label = "cardBorderGlow")
    val borderAlpha by infiniteTransition.animateFloat(
        initialValue = 0.55f,
        targetValue = 0.95f,
        animationSpec = infiniteRepeatable(
            animation = tween(1200),
            repeatMode = RepeatMode.Reverse
        ),
        label = "borderGlow"
    )

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .shadow(
                elevation = if (isCurrentlyTyping) 12.dp else 4.dp,
                shape = RoundedCornerShape(18.dp),
                ambientColor = Color.Black.copy(alpha = 0.40f),
                spotColor = if (isCurrentlyTyping) ThemeColors.accentCyan.copy(alpha = 0.35f) else Color.Transparent
            )
            .clip(RoundedCornerShape(18.dp))
            .background(Color(0xFF080F1E).copy(alpha = if (isCurrentlyTyping) 0.88f else 0.72f))
            .border(
                width = if (isCurrentlyTyping) 1.6.dp else 0.8.dp,
                brush = if (isCurrentlyTyping) {
                    Brush.linearGradient(
                        listOf(
                            ThemeColors.accentCyan.copy(alpha = borderAlpha),
                            ThemeColors.accentBlue.copy(alpha = borderAlpha * 0.85f),
                            ThemeColors.accentCyan.copy(alpha = borderAlpha)
                        )
                    )
                } else {
                    Brush.linearGradient(
                        listOf(Color.White.copy(alpha = 0.16f), Color.White.copy(alpha = 0.06f))
                    )
                },
                shape = RoundedCornerShape(18.dp)
            )
            .padding(15.dp)
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            // Header: Category Icon + Title + Suggestive Contextual Metric Badge
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(9.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .size(26.dp)
                            .clip(CircleShape)
                            .background(accentColor.copy(alpha = 0.16f)),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = iconVector,
                            contentDescription = null,
                            tint = accentColor,
                            modifier = Modifier.size(13.dp)
                        )
                    }

                    Text(
                        text = item.title,
                        color = Color.White,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold
                    )
                }

                item.badgeText?.let { badge ->
                    val badgeColor = try {
                        Color(android.graphics.Color.parseColor(item.badgeColorHex ?: item.accentColorHex))
                    } catch (_: Exception) {
                        ThemeColors.accentCyan
                    }

                    Row(
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(badgeColor.copy(alpha = 0.12f))
                            .border(0.8.dp, badgeColor.copy(alpha = 0.28f), CircleShape)
                            .padding(horizontal = 8.dp, vertical = 3.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        Box(
                            modifier = Modifier
                                .size(4.dp)
                                .clip(CircleShape)
                                .background(badgeColor)
                        )
                        Text(
                            text = badge,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = badgeColor
                        )
                    }
                }
            }

            HorizontalDivider(color = Color.White.copy(alpha = 0.08f))

            // Body: Progressive Typewriter Word Text
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = visibleText,
                    color = Color.White.copy(alpha = 0.92f),
                    fontSize = 14.sp,
                    lineHeight = 20.sp,
                    fontWeight = FontWeight.Normal
                )
                if (isCurrentlyTyping) {
                    Text(
                        text = " ✨",
                        color = ThemeColors.accentCyan,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
            }
        }
    }
}
