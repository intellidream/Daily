package com.intellidream.daily.wearos.presentation.pulse

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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Air
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.Text
import com.google.android.horologist.annotations.ExperimentalHorologistApi
import com.google.android.horologist.compose.layout.ScalingLazyColumn
import com.google.android.horologist.compose.layout.ScalingLazyColumnState
import com.google.android.horologist.compose.layout.ScreenScaffold
import com.google.android.horologist.compose.layout.rememberResponsiveColumnState
import com.intellidream.daily.wearos.data.WatchPulseRepository
import com.intellidream.daily.wearos.data.WatchSessionManager
import com.intellidream.daily.wearos.presentation.components.BreathingStudioDialog
import com.intellidream.daily.wearos.presentation.components.WearBreathingProtocol
import com.intellidream.daily.wearos.util.SoundAndHapticFeedback
import kotlinx.coroutines.launch

@OptIn(ExperimentalHorologistApi::class)
@Composable
fun PulseScreen(
    isPageActive: Boolean = true
) {
    val context = LocalContext.current
    val view = LocalView.current
    val repository = remember { WatchPulseRepository.getInstance(context) }
    val sessionManager = remember { WatchSessionManager.getInstance(context) }
    val refreshTrigger by sessionManager.dataRefreshTrigger.collectAsState()
    val snap by repository.snapshot.collectAsState()
    val isSyncing by repository.isSyncing.collectAsState()
    val scope = rememberCoroutineScope()

    val columnState = rememberResponsiveColumnState(
        rotaryMode = ScalingLazyColumnState.RotaryMode.Scroll
    )

    var activeProtocol by remember { mutableStateOf<WearBreathingProtocol?>(null) }

    LaunchedEffect(isPageActive, refreshTrigger) {
        if (isPageActive) {
            repository.syncWithSupabase(force = false)
        }
    }

    // Memoize colors, progress, and protocol enum list to ensure 0-allocation rotary scrolling
    val sleepProgress = remember(snap.hasSleepData, snap.sleepScore) {
        if (snap.hasSleepData) (snap.sleepScore / 100f).coerceIn(0f, 1f) else 0f
    }
    val sleepScoreLabel = remember(snap.hasSleepData, snap.sleepScore) {
        if (snap.hasSleepData) "${snap.sleepScore}" else "--"
    }
    val readinessColor = remember(snap.hasSleepData, snap.sleepScore) {
        when {
            !snap.hasSleepData -> Color.White.copy(alpha = 0.6f)
            snap.sleepScore >= 75 -> Color(0xFF34D399)
            snap.sleepScore >= 60 -> Color(0xFFFBBF24)
            else -> Color(0xFFF87171)
        }
    }
    val stressAccentColor = remember(snap.hasStressData, snap.stressScore) {
        when {
            !snap.hasStressData -> Color(0xFF38BDF8)
            snap.stressScore <= 25 -> Color(0xFF00E5FF)
            snap.stressScore <= 50 -> Color(0xFF34D399)
            snap.stressScore <= 75 -> Color(0xFFFBBF24)
            else -> Color(0xFFF87171)
        }
    }
    val recommendedProto = remember(snap.recommendedBreathing) {
        val lower = snap.recommendedBreathing.lowercase()
        when {
            lower.contains("4-7-8") -> WearBreathingProtocol.RELAX_478
            lower.contains("box") -> WearBreathingProtocol.BOX_BREATHING
            lower.contains("resonance") || lower.contains("coherent") -> WearBreathingProtocol.RESONANCE
            else -> WearBreathingProtocol.PHYSIOLOGICAL_SIGH
        }
    }
    val protocols = remember { WearBreathingProtocol.entries }

    ScreenScaffold(scrollState = columnState) {
        ScalingLazyColumn(
            columnState = columnState,
            modifier = Modifier.fillMaxSize()
        ) {
            // Header (TagDoS-style title + compact refresh indicator next to title)
            item {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center,
                    modifier = Modifier
                        .clip(RoundedCornerShape(8.dp))
                        .clickable {
                            SoundAndHapticFeedback.playClick(context, view)
                            scope.launch {
                                repository.syncWithSupabase(force = true)
                            }
                        }
                        .padding(horizontal = 6.dp, vertical = 3.dp)
                ) {
                    Icon(
                        imageVector = Icons.Filled.Favorite,
                        contentDescription = null,
                        tint = Color(0xFFFF2D55),
                        modifier = Modifier.size(16.dp)
                    )
                    Spacer(Modifier.width(4.dp))
                    Text(
                        text = "Pulse Studio",
                        fontWeight = FontWeight.Bold,
                        fontSize = 16.sp,
                        color = Color.White,
                        maxLines = 1,
                        softWrap = false
                    )
                    if (isSyncing) {
                        Spacer(Modifier.width(6.dp))
                        CircularProgressIndicator(
                            modifier = Modifier.size(10.dp),
                            strokeWidth = 1.5.dp,
                            indicatorColor = Color(0xFFFF2D55)
                        )
                    }
                }
            }

            // 1. Sleep & Recovery Verdict Card
            item {
                Column(
                    modifier = Modifier
                        .fillMaxWidth(0.94f)
                        .clip(RoundedCornerShape(16.dp))
                        .background(Color(0xFF141820))
                        .border(1.dp, Color(0xFFA855F7).copy(alpha = 0.25f), RoundedCornerShape(16.dp))
                        .padding(10.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "SLEEP & RECOVERY",
                            fontSize = 9.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color(0xFFA855F7),
                            letterSpacing = 0.5.sp,
                            maxLines = 1,
                            softWrap = false
                        )
                        Text(
                            text = snap.sleepDurationFormatted,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = Color.White.copy(alpha = 0.75f),
                            maxLines = 1,
                            softWrap = false
                        )
                    }

                    Spacer(Modifier.height(6.dp))

                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        // Sleep Score Circle
                        Box(
                            modifier = Modifier.size(44.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            CircularProgressIndicator(
                                progress = sleepProgress,
                                modifier = Modifier.fillMaxSize(),
                                strokeWidth = 4.dp,
                                indicatorColor = Color(0xFFA855F7),
                                trackColor = Color.White.copy(alpha = 0.08f)
                            )
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Text(
                                    text = sleepScoreLabel,
                                    fontSize = 14.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = Color.White,
                                    maxLines = 1
                                )
                                Text(
                                    text = "SCORE",
                                    fontSize = 6.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = Color.White.copy(alpha = 0.5f),
                                    maxLines = 1
                                )
                            }
                        }

                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = snap.readinessHeadline,
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold,
                                color = readinessColor,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                            Text(
                                text = snap.sleepNarrative,
                                fontSize = 9.sp,
                                lineHeight = 11.5.sp,
                                color = Color.White.copy(alpha = 0.72f),
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis
                            )
                            Spacer(Modifier.height(2.dp))
                            Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                                Text(
                                    text = snap.restingHrText,
                                    fontSize = 8.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = Color(0xFFF87171),
                                    maxLines = 1,
                                    softWrap = false
                                )
                                Text(text = "•", fontSize = 8.sp, color = Color.White.copy(alpha = 0.3f))
                                Text(
                                    text = snap.hrvText,
                                    fontSize = 8.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = Color(0xFF38BDF8),
                                    maxLines = 1,
                                    softWrap = false
                                )
                            }
                        }
                    }

                    Spacer(Modifier.height(6.dp))

                    // Proportional Sleep Stage Breakdown Bar (Deep, REM, Core/Light, Awake)
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(4.dp)
                            .clip(RoundedCornerShape(2.dp)),
                        horizontalArrangement = Arrangement.spacedBy(1.dp)
                    ) {
                        Box(modifier = Modifier.weight(snap.deepWeight).fillMaxSize().background(Color(0xFF6366F1)))
                        Box(modifier = Modifier.weight(snap.remWeight).fillMaxSize().background(Color(0xFFA855F7)))
                        Box(modifier = Modifier.weight(snap.lightWeight).fillMaxSize().background(Color(0xFF38BDF8)))
                        Box(modifier = Modifier.weight(snap.awakeWeight).fillMaxSize().background(Color(0xFFF59E0B)))
                    }
                }
            }

            // 2. Autonomic Stress & Vitals Card (Engine v2.0)
            item {
                Spacer(Modifier.height(4.dp))
                Column(
                    modifier = Modifier
                        .fillMaxWidth(0.94f)
                        .clip(RoundedCornerShape(16.dp))
                        .background(Color(0xFF141820))
                        .border(1.dp, Color.White.copy(alpha = 0.06f), RoundedCornerShape(16.dp))
                        .padding(10.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "AUTONOMIC STRESS",
                            fontSize = 9.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color(0xFF38BDF8),
                            letterSpacing = 0.5.sp,
                            maxLines = 1,
                            softWrap = false
                        )
                        Text(
                            text = snap.stressBadgeText,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold,
                            color = stressAccentColor,
                            maxLines = 1,
                            softWrap = false
                        )
                    }

                    Spacer(Modifier.height(4.dp))

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = snap.stressHeadline,
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color.White,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                            Text(
                                text = snap.monkeyMoodText,
                                fontSize = 9.sp,
                                color = Color.White.copy(alpha = 0.68f),
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                        }

                        Spacer(Modifier.width(6.dp))

                        Column(horizontalAlignment = Alignment.End) {
                            Text(
                                text = snap.stepsText,
                                fontSize = 10.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = Color(0xFFFBBF24),
                                maxLines = 1,
                                softWrap = false
                            )
                            Text(
                                text = snap.parasympatheticText,
                                fontSize = 8.sp,
                                color = Color.White.copy(alpha = 0.55f),
                                maxLines = 1,
                                softWrap = false
                            )
                        }
                    }

                    Spacer(Modifier.height(6.dp))
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(1.dp)
                            .background(Color.White.copy(alpha = 0.06f))
                    )
                    Spacer(Modifier.height(5.dp))

                    // Status quote (maxLines = 2) + single-line "Breathe" action chip
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Text(
                            text = snap.adviceQuote,
                            fontSize = 8.5.sp,
                            lineHeight = 11.sp,
                            color = Color.White.copy(alpha = 0.65f),
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f)
                        )

                        Box(
                            modifier = Modifier
                                .clip(CircleShape)
                                .background(Color(0xFF00E5FF).copy(alpha = 0.16f))
                                .clickable {
                                    SoundAndHapticFeedback.playClick(context, view)
                                    activeProtocol = recommendedProto
                                }
                                .padding(horizontal = 8.dp, vertical = 4.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(
                                    imageVector = Icons.Filled.Air,
                                    contentDescription = "Breathe",
                                    tint = Color(0xFF00E5FF),
                                    modifier = Modifier.size(9.dp)
                                )
                                Spacer(Modifier.width(3.dp))
                                Text(
                                    text = "Breathe",
                                    fontSize = 9.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = Color(0xFF00E5FF),
                                    maxLines = 1,
                                    softWrap = false
                                )
                            }
                        }
                    }
                }
            }

            // 3. Guided Breathing Section Header
            item {
                Spacer(Modifier.height(6.dp))
                Row(
                    modifier = Modifier
                        .fillMaxWidth(0.92f)
                        .padding(horizontal = 2.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = Icons.Filled.Air,
                        contentDescription = null,
                        tint = Color(0xFF00E5FF),
                        modifier = Modifier.size(11.dp)
                    )
                    Spacer(Modifier.width(4.dp))
                    Text(
                        text = "GUIDED BREATHING",
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White.copy(alpha = 0.55f),
                        letterSpacing = 0.5.sp
                    )
                }
            }

            // 4 Guided Breathing Launchers
            items(count = protocols.size, key = { protocols[it].name }) { idx ->
                val proto = protocols[idx]
                Box(
                    modifier = Modifier
                        .fillMaxWidth(0.94f)
                        .padding(vertical = 2.dp)
                        .clip(RoundedCornerShape(10.dp))
                        .background(Color(0xFF141820))
                        .border(1.dp, Color.White.copy(alpha = 0.04f), RoundedCornerShape(10.dp))
                        .clickable {
                            SoundAndHapticFeedback.playClick(context, view)
                            activeProtocol = proto
                        }
                        .padding(horizontal = 10.dp, vertical = 6.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Box(
                                modifier = Modifier
                                    .size(20.dp)
                                    .clip(CircleShape)
                                    .background(proto.accentColor.copy(alpha = 0.2f)),
                                contentAlignment = Alignment.Center
                            ) {
                                Icon(
                                    imageVector = Icons.Filled.Air,
                                    contentDescription = null,
                                    tint = proto.accentColor,
                                    modifier = Modifier.size(10.dp)
                                )
                            }
                            Spacer(Modifier.width(8.dp))
                            Column {
                                Text(
                                    text = proto.title,
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = Color.White,
                                    maxLines = 1
                                )
                                Text(
                                    text = proto.shortTitle,
                                    fontSize = 9.sp,
                                    color = Color.White.copy(alpha = 0.55f),
                                    maxLines = 1
                                )
                            }
                        }

                        Icon(
                            imageVector = Icons.Filled.PlayArrow,
                            contentDescription = "Play",
                            tint = proto.accentColor,
                            modifier = Modifier.size(14.dp)
                        )
                    }
                }
            }

            item {
                Spacer(Modifier.height(16.dp))
            }
        }
    }

    if (activeProtocol != null) {
        BreathingStudioDialog(
            show = true,
            protocol = activeProtocol!!,
            onDismiss = { activeProtocol = null }
        )
    }
}
