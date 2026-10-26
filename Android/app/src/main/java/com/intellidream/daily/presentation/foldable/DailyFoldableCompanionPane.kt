package com.intellidream.daily.presentation.foldable

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Send
import androidx.compose.material.icons.automirrored.rounded.VolumeUp
import androidx.compose.material.icons.rounded.AccountBalanceWallet
import androidx.compose.material.icons.rounded.Air
import androidx.compose.material.icons.rounded.ArrowOutward
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Bedtime
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Checklist
import androidx.compose.material.icons.rounded.Cloud
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.Newspaper
import androidx.compose.material.icons.rounded.NightsStay
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.TrendingUp
import androidx.compose.material.icons.rounded.WaterDrop
import androidx.compose.material.icons.rounded.WbSunny
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.briefing.SmartBriefingRepository
import com.intellidream.daily.database.FinanceDataRepository
import com.intellidream.daily.database.HabitsRepository
import com.intellidream.daily.database.NewsRepository
import com.intellidream.daily.database.SmartLedgerRepository
import com.intellidream.daily.database.TagdosRepository
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.GlassIntensity
import com.intellidream.daily.designsystem.MonkeyMascotView
import com.intellidream.daily.designsystem.MonkeySize
import com.intellidream.daily.designsystem.NavigationTab
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.health.HealthDataRepository
import com.intellidream.daily.model.AppSettings
import com.intellidream.daily.model.BriefingTimeSlot
import com.intellidream.daily.model.MonkeyMood
import com.intellidream.daily.model.NewsArticle
import com.intellidream.daily.model.ParsedSmartLedger
import com.intellidream.daily.model.SleepSession
import com.intellidream.daily.model.SmartBriefingRecord
import com.intellidream.daily.model.StressLevel
import com.intellidream.daily.model.TagDoQuickNote
import com.intellidream.daily.model.TagDoStream
import com.intellidream.daily.model.UserProfile
import com.intellidream.daily.model.WeatherResponse
import java.util.Calendar
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt

// ---------------------------------------------------------------------------
// MARK: - Co-Pilot Prefabricated Topics & Inline Conversation Turn Models
// ---------------------------------------------------------------------------

private enum class CoPilotPrefabTopic(
    val id: String,
    val chipLabel: String,
    val fullQuestion: String,
    val icon: ImageVector,
    val accentColor: Color,
    val targetTab: NavigationTab,
    val portalButtonTitle: String
) {
    SLEEP_RECOVERY(
        id = "sleep_recovery",
        chipLabel = "Sleep & Readiness",
        fullQuestion = "Analyze my sleep architecture & recovery readiness today.",
        icon = Icons.Rounded.Bedtime,
        accentColor = Color(0xFFA855F7),
        targetTab = NavigationTab.Health,
        portalButtonTitle = "Open Sleep & Health Hub"
    ),
    CIRCADIAN_HYDRATION(
        id = "circadian_hydration",
        chipLabel = "Circadian Hydration",
        fullQuestion = "What is my optimal circadian hydration & habit protocol right now?",
        icon = Icons.Rounded.WaterDrop,
        accentColor = Color(0xFF00E5FF),
        targetTab = NavigationTab.Habits,
        portalButtonTitle = "Open Habits & Hydration Hub"
    ),
    URGENT_FOCUS(
        id = "urgent_focus",
        chipLabel = "Urgent Focus",
        fullQuestion = "Which Tagdos priorities and mental streams need my focus first?",
        icon = Icons.Rounded.Checklist,
        accentColor = Color(0xFFFFB300),
        targetTab = NavigationTab.Tagdos,
        portalButtonTitle = "Open Tagdos & Notes Hub"
    ),
    STRESS_RESET(
        id = "stress_reset",
        chipLabel = "Stress & Breathing",
        fullQuestion = "How is my autonomic stress balance & what reset protocol helps now?",
        icon = Icons.Rounded.Air,
        accentColor = Color(0xFF00E676),
        targetTab = NavigationTab.Health,
        portalButtonTitle = "Open Stress & Vitals Hub"
    ),
    WEALTH_PULSE(
        id = "wealth_pulse",
        chipLabel = "Cashflow Pulse",
        fullQuestion = "Summarize my Smart Ledger cashflow momentum and net worth.",
        icon = Icons.Rounded.TrendingUp,
        accentColor = Color(0xFF10B981),
        targetTab = NavigationTab.Finances,
        portalButtonTitle = "Open Smart Ledger Hub"
    )
}

private data class CoPilotInlineTurn(
    val question: String,
    val headline: String,
    val body: String,
    val highlights: List<String>,
    val targetTab: NavigationTab,
    val portalTitle: String,
    val accentColor: Color
)

private data class CircadianHydrationWindow(
    val timeRange: String,
    val title: String,
    val recommendedVolumeMl: Int,
    val rationale: String
)

private fun currentCircadianHydrationWindow(): CircadianHydrationWindow {
    val hour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
    return when {
        hour < 9 -> CircadianHydrationWindow(
            timeRange = "07:00 – 08:30",
            title = "Morning Kickstart",
            recommendedVolumeMl = 500,
            rationale = "Rehydrates cellular tissues after 7–8 hours of nocturnal respiratory water loss and stimulates peristalsis."
        )
        hour < 12 -> CircadianHydrationWindow(
            timeRange = "09:30 – 11:30",
            title = "Cognitive Focus Peak",
            recommendedVolumeMl = 500,
            rationale = "Maintains cerebral blood flow and alertness during peak morning cortisol and executive work."
        )
        hour < 15 -> CircadianHydrationWindow(
            timeRange = "12:30 – 14:30",
            title = "Digestive Preparation",
            recommendedVolumeMl = 400,
            rationale = "Supports enzymatic nutrient absorption around lunch and prevents post-prandial afternoon fatigue."
        )
        hour < 19 -> CircadianHydrationWindow(
            timeRange = "15:30 – 17:30",
            title = "Afternoon Energy Boost",
            recommendedVolumeMl = 500,
            rationale = "Stabilizes thermoregulation and counters the natural circadian dip in core body alertness."
        )
        else -> CircadianHydrationWindow(
            timeRange = "18:30 – 20:30",
            title = "Night Taper",
            recommendedVolumeMl = 300,
            rationale = "Completes daily hydration early enough to prevent nocturia and preserve uninterrupted Deep & REM sleep."
        )
    }
}

/**
 * Signature Foldable Companion Pane ("The Hybrid Co-Pilot") displayed in the secondary / detail pane
 * on expanded foldable displays (Samsung Galaxy Z Fold 8, Google Pixel 9 Pro Fold) when no hub is open.
 *
 * Aligns 100% 1:1 with iOS (iPhone Duo):
 * 1. Diurnal Intelligence Header + Live Heart Rate Pill
 * 2. Hero Widget: Concentric Recovery Rings (Steps, Sleep, Water) + Animated Monkey Mascot
 * 3. Monkey Co-Pilot · Studio: Interactive conversational card with 5 prefabricated prompt chips & custom query input
 * 4. Daily Spotlight & Hub Matrix: Unified 4-band qualitative insight & 1-tap Hub portal card
 */
@Composable
fun DailyFoldableCompanionPane(
    userProfile: UserProfile?,
    settings: AppSettings,
    weather: WeatherResponse?,
    healthRepository: HealthDataRepository,
    habitsRepository: HabitsRepository,
    smartLedgerRepository: SmartLedgerRepository,
    financeDataRepository: FinanceDataRepository,
    tagdosRepository: TagdosRepository,
    newsRepository: NewsRepository,
    smartBriefingRepository: SmartBriefingRepository,
    onOpenHub: (NavigationTab) -> Unit,
    onOpenBriefing: () -> Unit,
    onOpenNewsArticle: (NewsArticle) -> Unit,
    modifier: Modifier = Modifier
) {
    val haptic = LocalHapticFeedback.current
    val focusManager = LocalFocusManager.current

    // Health Telemetry
    val totalSteps by healthRepository.totalStepsToday.collectAsState()
    val totalCalories by healthRepository.totalActiveCalories.collectAsState()
    val latestBpm by healthRepository.latestBpm.collectAsState()
    val averageBpm by healthRepository.averageBpm.collectAsState()
    val primarySleep by healthRepository.primarySleepSession.collectAsState()
    val stressScore by healthRepository.currentStressScore.collectAsState()
    val stressLevel by healthRepository.currentStressLevel.collectAsState()

    // Habits Telemetry
    val waterTotal by habitsRepository.waterTotalToday.collectAsState()
    val waterGoal by habitsRepository.waterGoal.collectAsState()
    val smokesTotal by habitsRepository.smokesTotalToday.collectAsState()

    // Finances Telemetry
    val parsedLedger by smartLedgerRepository.parsedLedger.collectAsState()

    // News Telemetry
    val articles by newsRepository.articles.collectAsState()
    val latestArticle = articles.firstOrNull()

    // Tagdos Telemetry
    val streams by tagdosRepository.streams.collectAsState()
    val quickNotes by tagdosRepository.quickNotes.collectAsState()
    val latestNote = quickNotes.firstOrNull()

    // Briefing Telemetry
    val activeBriefing by smartBriefingRepository.activeBriefing.collectAsState()
    val slot = activeBriefing?.slot ?: BriefingTimeSlot.current()

    // Co-Pilot Interactive State
    var selectedPrefab by remember { mutableStateOf<CoPilotPrefabTopic?>(null) }
    var activeTurn by remember { mutableStateOf<CoPilotInlineTurn?>(null) }
    var customQueryText by remember { mutableStateOf("") }

    val displayBpm = latestBpm ?: averageBpm
    val hydrationProgress = if (waterGoal > 0) (waterTotal.toFloat() / waterGoal.toFloat()).coerceIn(0f, 1f) else 0f
    val stepsProgress = (totalSteps.toFloat() / 10000f).coerceIn(0f, 1f)
    val sleepScore = primarySleep?.sleepScore ?: 0
    val sleepProgress = (sleepScore.toFloat() / 100f).coerceIn(0f, 1f)

    // Extract top driving/active Tagdos pills across streams
    val topUrgentPills: List<String> = remember(streams) {
        val driving = streams.mapNotNull { it.drivingPill?.rawText }.filter { it.isNotBlank() }
        if (driving.isNotEmpty()) {
            driving.take(3)
        } else {
            streams.flatMap { stream -> stream.clusters.flatMap { it.activePills } }
                .map { it.rawText }
                .filter { it.isNotBlank() }
                .take(3)
        }
    }

    val hydroWindow = remember { currentCircadianHydrationWindow() }

    // Diurnal Wish and Icon adapted to the time of day (1:1 with iOS & Smart Briefing bottom button)
    val diurnalWish = activeBriefing?.narrative?.closingWish ?: slot.defaultClosingWish
    val slotIcon: ImageVector = when (slot) {
        BriefingTimeSlot.MORNING -> Icons.Rounded.WbSunny
        BriefingTimeSlot.INTRADAY -> Icons.Rounded.WbSunny
        BriefingTimeSlot.EVENING -> Icons.Rounded.NightsStay
        BriefingTimeSlot.NIGHTLY -> Icons.Rounded.NightsStay
    }

    fun selectPrefabTopic(topic: CoPilotPrefabTopic) {
        haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
        if (selectedPrefab == topic) {
            selectedPrefab = null
            activeTurn = null
        } else {
            selectedPrefab = topic
            activeTurn = buildInlineTurn(
                topic = topic,
                primarySleep = primarySleep,
                hydroWindow = hydroWindow,
                waterMl = waterTotal.roundToInt(),
                waterGoalMl = waterGoal.roundToInt(),
                hydrationProgress = hydrationProgress,
                smokesTotal = smokesTotal,
                topUrgentPills = topUrgentPills,
                streamsCount = streams.size,
                quickNotes = quickNotes,
                stressScore = stressScore,
                stressLevel = stressLevel,
                displayBpm = displayBpm,
                parsedLedger = parsedLedger
            )
        }
    }

    fun submitCustomQuery() {
        val trimmed = customQueryText.trim()
        if (trimmed.isEmpty()) return
        haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
        customQueryText = ""
        focusManager.clearFocus()

        val q = trimmed.lowercase()
        val matchedTopic: CoPilotPrefabTopic? = when {
            q.contains("sleep") || q.contains("somn") || q.contains("rem") || q.contains("deep") || q.contains("obosit") ->
                CoPilotPrefabTopic.SLEEP_RECOVERY
            q.contains("water") || q.contains("apa") || q.contains("apă") || q.contains("hidr") || q.contains("fum") || q.contains("tig") || q.contains("crav") ->
                CoPilotPrefabTopic.CIRCADIAN_HYDRATION
            q.contains("tag") || q.contains("task") || q.contains("urgent") || q.contains("not") || q.contains("memo") || q.contains("focus") ->
                CoPilotPrefabTopic.URGENT_FOCUS
            q.contains("bani") || q.contains("finan") || q.contains("lei") || q.contains("eur") || q.contains("ledger") || q.contains("cash") || q.contains("worth") ->
                CoPilotPrefabTopic.WEALTH_PULSE
            q.contains("stres") || q.contains("calm") || q.contains("resp") || q.contains("breath") || q.contains("puls") || q.contains("bpm") ->
                CoPilotPrefabTopic.STRESS_RESET
            else -> null
        }

        if (matchedTopic != null) {
            selectedPrefab = matchedTopic
            val baseTurn = buildInlineTurn(
                topic = matchedTopic,
                primarySleep = primarySleep,
                hydroWindow = hydroWindow,
                waterMl = waterTotal.roundToInt(),
                waterGoalMl = waterGoal.roundToInt(),
                hydrationProgress = hydrationProgress,
                smokesTotal = smokesTotal,
                topUrgentPills = topUrgentPills,
                streamsCount = streams.size,
                quickNotes = quickNotes,
                stressScore = stressScore,
                stressLevel = stressLevel,
                displayBpm = displayBpm,
                parsedLedger = parsedLedger
            )
            activeTurn = baseTurn.copy(question = trimmed)
        } else {
            selectedPrefab = null
            val pulse = synthesizeCrossDomainPulse(
                slot = slot,
                stressLevel = stressLevel,
                primarySleep = primarySleep,
                activeBriefing = activeBriefing,
                hydroWindow = hydroWindow,
                waterMl = waterTotal.roundToInt(),
                waterGoalMl = waterGoal.roundToInt(),
                totalSteps = totalSteps,
                topUrgentPills = topUrgentPills
            )
            activeTurn = CoPilotInlineTurn(
                question = trimmed,
                headline = pulse.first,
                body = pulse.second,
                highlights = listOf(
                    "Hydration Window: ${hydroWindow.title} (+${hydroWindow.recommendedVolumeMl} ml target)",
                    "Net Worth: ${parsedLedger.formattedNetWorthEUR} • Steps Today: $totalSteps"
                ),
                targetTab = NavigationTab.Health,
                portalTitle = "Open Health & Vitals Hub",
                accentColor = ThemeColors.accentCyan
            )
        }
    }

    // Automatically trigger Smart Briefing generation / refresh whenever primary sleep data or slot updates
    LaunchedEffect(primarySleep?.id, primarySleep?.sleepScore, primarySleep?.asleepSeconds, slot) {
        val currentBrief = activeBriefing
        val needsRefresh = currentBrief == null ||
                currentBrief.slot != slot ||
                currentBrief.metrics.sleepScore != primarySleep?.sleepScore ||
                currentBrief.metrics.sleepDurationFormatted != primarySleep?.totalAsleepFormatted

        if (needsRefresh) {
            smartBriefingRepository.getOrGenerateBriefing(
                forceRefresh = true,
                userName = userProfile?.firstName ?: "Friend",
                userId = userProfile?.id ?: "local_user",
                settings = settings,
                weather = weather,
                locationName = weather?.name ?: "",
                healthRepository = healthRepository,
                habitsRepository = habitsRepository,
                smartLedgerRepository = smartLedgerRepository,
                tagdosRepository = tagdosRepository,
                newsRepository = newsRepository
            )
        }
    }

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(top = 8.dp, bottom = 96.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        // -------------------------------------------------------------------
        // 1. Diurnal Intelligence Header (100% 1:1 with iOS)
        // -------------------------------------------------------------------
        item(key = "companion_header") {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp)
                    .padding(vertical = 4.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.Center
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Icon(
                            imageVector = slotIcon,
                            contentDescription = null,
                            tint = ThemeColors.accentCyan,
                            modifier = Modifier.size(13.dp)
                        )
                        Text(
                            text = slot.displayName.uppercase(),
                            color = ThemeColors.accentCyan,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold,
                            letterSpacing = 1.sp
                        )
                    }
                    Spacer(modifier = Modifier.height(2.dp))
                    Text(
                        text = diurnalWish,
                        color = Color.White,
                        fontSize = 20.sp,
                        fontWeight = FontWeight.Bold,
                        letterSpacing = (-0.3).sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }

                // Tappable Live Heart Rate Pill -> Opens Health Hub
                GlassCard(
                    modifier = Modifier
                        .clip(RoundedCornerShape(14.dp))
                        .clickable {
                            haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            onOpenHub(NavigationTab.Health)
                        },
                    cornerRadius = 14.dp,
                    padding = 10.dp,
                    intensity = GlassIntensity.Subtle
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            imageVector = Icons.Rounded.Favorite,
                            contentDescription = "Heart rate",
                            tint = ThemeColors.accentPink,
                            modifier = Modifier.size(16.dp)
                        )
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(
                            text = if (displayBpm > 0.0) "${displayBpm.roundToInt()} BPM" else "-- BPM",
                            color = Color.White,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }
            }
        }

        // -------------------------------------------------------------------
        // 2. Concentric Recovery Rings & Mascot Hero Card (100% 1:1 with iOS)
        // -------------------------------------------------------------------
        item(key = "companion_rings_hero") {
            GlassCard(
                modifier = Modifier.fillMaxWidth(),
                cornerRadius = 24.dp,
                padding = 20.dp,
                intensity = GlassIntensity.Prominent
            ) {
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Box(
                        modifier = Modifier.size(170.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        // Outer Ring: Activity / Steps (Orange)
                        CircularProgressIndicator(
                            progress = { max(stepsProgress, 0.02f) },
                            modifier = Modifier.size(170.dp),
                            color = ThemeColors.accentOrange,
                            trackColor = ThemeColors.accentOrange.copy(alpha = 0.15f),
                            strokeWidth = 10.dp,
                            strokeCap = StrokeCap.Round
                        )

                        // Middle Ring: Sleep Recovery (Purple)
                        CircularProgressIndicator(
                            progress = { max(sleepProgress, 0.02f) },
                            modifier = Modifier.size(136.dp),
                            color = ThemeColors.accentPurple,
                            trackColor = ThemeColors.accentPurple.copy(alpha = 0.15f),
                            strokeWidth = 10.dp,
                            strokeCap = StrokeCap.Round
                        )

                        // Inner Ring: Hydration (Cyan)
                        CircularProgressIndicator(
                            progress = { max(hydrationProgress, 0.02f) },
                            modifier = Modifier.size(102.dp),
                            color = ThemeColors.accentCyan,
                            trackColor = ThemeColors.accentCyan.copy(alpha = 0.15f),
                            strokeWidth = 10.dp,
                            strokeCap = StrokeCap.Round
                        )

                        // Center: Live Stress Monkey Mascot + Stress Status
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.Center
                        ) {
                            val monkeyMood = stressLevel?.let { MonkeyMood.fromLevel(it) } ?: MonkeyMood.ZEN
                            MonkeyMascotView(
                                mood = monkeyMood,
                                size = MonkeySize.MINI
                            )
                            Spacer(modifier = Modifier.height(2.dp))
                            Text(
                                text = stressLevel?.displayName ?: "Balanced",
                                color = Color.White.copy(alpha = 0.90f),
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold,
                                style = TextStyle(
                                    shadow = androidx.compose.ui.graphics.Shadow(
                                        color = Color.Black.copy(alpha = 0.85f),
                                        offset = androidx.compose.ui.geometry.Offset(0f, 2f),
                                        blurRadius = 4f
                                    )
                                )
                            )
                        }
                    }

                    Spacer(modifier = Modifier.height(16.dp))

                    // Interactive Metrics Legend Grid
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceEvenly
                    ) {
                        RingMetricItem(
                            label = "STEPS",
                            value = "$totalSteps",
                            color = ThemeColors.accentOrange,
                            onClick = {
                                haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                onOpenHub(NavigationTab.Health)
                            }
                        )
                        RingMetricItem(
                            label = "SLEEP",
                            value = if (sleepScore > 0) "$sleepScore%" else "--",
                            color = ThemeColors.accentPurple,
                            onClick = {
                                haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                onOpenHub(NavigationTab.Health)
                            }
                        )
                        RingMetricItem(
                            label = "WATER",
                            value = "${(hydrationProgress * 100).roundToInt()}%",
                            color = ThemeColors.accentCyan,
                            onClick = {
                                haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                onOpenHub(NavigationTab.Habits)
                            }
                        )
                    }
                }
            }
        }

        // -------------------------------------------------------------------
        // 3. Monkey Co-Pilot · Studio (Interactive Prefabricated + Custom Chat)
        // -------------------------------------------------------------------
        item(key = "monkey_copilot_studio") {
            val studioGradient = Brush.linearGradient(
                listOf(
                    Color(0xFF0E1D35).copy(alpha = 0.94f),
                    Color(0xFF13284C).copy(alpha = 0.88f)
                )
            )

            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(22.dp))
                    .background(studioGradient)
                    .border(
                        width = 1.dp,
                        color = (selectedPrefab?.accentColor ?: ThemeColors.accentCyan).copy(alpha = 0.38f),
                        shape = RoundedCornerShape(22.dp)
                    )
                    .padding(16.dp)
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    // Studio Header Bar
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(7.dp)
                        ) {
                            Icon(
                                imageVector = Icons.Rounded.AutoAwesome,
                                contentDescription = null,
                                tint = ThemeColors.accentCyan,
                                modifier = Modifier.size(16.dp)
                            )
                            Text(
                                text = "MONKEY CO-PILOT · STUDIO",
                                color = ThemeColors.accentCyan,
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold,
                                letterSpacing = 0.8.sp
                            )
                        }

                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            if (activeTurn != null) {
                                Row(
                                    modifier = Modifier
                                        .clip(CircleShape)
                                        .background(Color.White.copy(alpha = 0.08f))
                                        .clickable {
                                            haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                            selectedPrefab = null
                                            activeTurn = null
                                        }
                                        .padding(horizontal = 8.dp, vertical = 4.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                                ) {
                                    Icon(
                                        imageVector = Icons.Rounded.Refresh,
                                        contentDescription = "Reset overview",
                                        tint = Color.White.copy(alpha = 0.75f),
                                        modifier = Modifier.size(11.dp)
                                    )
                                    Text(
                                        text = "Overview",
                                        color = Color.White.copy(alpha = 0.75f),
                                        fontSize = 10.sp,
                                        fontWeight = FontWeight.SemiBold
                                    )
                                }
                            }

                            Row(
                                modifier = Modifier
                                    .clip(CircleShape)
                                    .background(ThemeColors.accentCyan.copy(alpha = 0.14f))
                                    .border(0.8.dp, ThemeColors.accentCyan.copy(alpha = 0.35f), CircleShape)
                                    .clickable {
                                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                        onOpenBriefing()
                                    }
                                    .padding(horizontal = 10.dp, vertical = 5.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(5.dp)
                            ) {
                                Icon(
                                    imageVector = Icons.AutoMirrored.Rounded.VolumeUp,
                                    contentDescription = "Full Briefing",
                                    tint = ThemeColors.accentCyan,
                                    modifier = Modifier.size(13.dp)
                                )
                                Text(
                                    text = "Full Briefing",
                                    color = Color.White,
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.SemiBold
                                )
                            }
                        }
                    }

                    // Dynamic Response Area (Overview vs Active Turn)
                    AnimatedContent(
                        targetState = activeTurn,
                        transitionSpec = { fadeIn() togetherWith fadeOut() },
                        label = "copilot_turn_transition"
                    ) { turn ->
                        if (turn != null) {
                            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                // User Prompt Bubble (Right-aligned)
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.End
                                ) {
                                    Text(
                                        text = turn.question,
                                        color = Color.White.copy(alpha = 0.92f),
                                        fontSize = 12.sp,
                                        fontWeight = FontWeight.Medium,
                                        modifier = Modifier
                                            .clip(RoundedCornerShape(14.dp))
                                            .background(turn.accentColor.copy(alpha = 0.18f))
                                            .border(0.8.dp, turn.accentColor.copy(alpha = 0.4f), RoundedCornerShape(14.dp))
                                            .padding(horizontal = 12.dp, vertical = 7.dp)
                                    )
                                }

                                // Co-Pilot Answer Bubble (Left-aligned)
                                Column(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clip(RoundedCornerShape(16.dp))
                                        .background(Color.White.copy(alpha = 0.05f))
                                        .border(0.8.dp, Color.White.copy(alpha = 0.1f), RoundedCornerShape(16.dp))
                                        .padding(12.dp),
                                    verticalArrangement = Arrangement.spacedBy(8.dp)
                                ) {
                                    Text(
                                        text = turn.headline,
                                        color = turn.accentColor,
                                        fontSize = 13.sp,
                                        fontWeight = FontWeight.Bold
                                    )

                                    Text(
                                        text = turn.body,
                                        color = Color.White.copy(alpha = 0.9f),
                                        fontSize = 12.sp,
                                        lineHeight = 17.sp
                                    )

                                    if (turn.highlights.isNotEmpty()) {
                                        Column(
                                            verticalArrangement = Arrangement.spacedBy(4.dp),
                                            modifier = Modifier.padding(top = 2.dp)
                                        ) {
                                            turn.highlights.forEach { bullet ->
                                                Row(
                                                    verticalAlignment = Alignment.Top,
                                                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                                                ) {
                                                    Box(
                                                        modifier = Modifier
                                                            .padding(top = 6.dp)
                                                            .size(5.dp)
                                                            .clip(CircleShape)
                                                            .background(turn.accentColor)
                                                    )
                                                    Text(
                                                        text = bullet,
                                                        color = Color.White.copy(alpha = 0.82f),
                                                        fontSize = 11.5.sp,
                                                        lineHeight = 16.sp
                                                    )
                                                }
                                            }
                                        }
                                    }

                                    // Direct Hub Portal Button inside Answer
                                    Row(
                                        modifier = Modifier
                                            .padding(top = 4.dp)
                                            .clip(CircleShape)
                                            .background(turn.accentColor.copy(alpha = 0.15f))
                                            .border(0.8.dp, turn.accentColor.copy(alpha = 0.4f), CircleShape)
                                            .clickable {
                                                haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                                onOpenHub(turn.targetTab)
                                            }
                                            .padding(horizontal = 12.dp, vertical = 6.dp),
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                                    ) {
                                        Text(
                                            text = turn.portalTitle,
                                            color = turn.accentColor,
                                            fontSize = 11.5.sp,
                                            fontWeight = FontWeight.Bold
                                        )
                                        Icon(
                                            imageVector = Icons.Rounded.ArrowOutward,
                                            contentDescription = null,
                                            tint = turn.accentColor,
                                            modifier = Modifier.size(13.dp)
                                        )
                                    }
                                }
                            }
                        } else {
                            val defaultPulse = synthesizeCrossDomainPulse(
                                slot = slot,
                                stressLevel = stressLevel,
                                primarySleep = primarySleep,
                                activeBriefing = activeBriefing,
                                hydroWindow = hydroWindow,
                                waterMl = waterTotal.roundToInt(),
                                waterGoalMl = waterGoal.roundToInt(),
                                totalSteps = totalSteps,
                                topUrgentPills = topUrgentPills
                            )
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clip(RoundedCornerShape(14.dp))
                                    .background(Color.White.copy(alpha = 0.04f))
                                    .padding(12.dp),
                                verticalArrangement = Arrangement.spacedBy(6.dp)
                            ) {
                                Text(
                                    text = defaultPulse.first,
                                    color = Color.White,
                                    fontSize = 13.5.sp,
                                    fontWeight = FontWeight.Bold
                                )
                                Text(
                                    text = defaultPulse.second,
                                    color = Color.White.copy(alpha = 0.86f),
                                    fontSize = 12.5.sp,
                                    lineHeight = 18.sp,
                                    maxLines = 4,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }
                        }
                    }

                    // Prefabricated Smart Prompt Chips
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(
                            text = "INSTANT CO-PILOT PROMPTS",
                            color = Color.White.copy(alpha = 0.45f),
                            fontSize = 9.5.sp,
                            fontWeight = FontWeight.Bold,
                            letterSpacing = 0.7.sp
                        )

                        LazyRow(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            contentPadding = PaddingValues(vertical = 2.dp)
                        ) {
                            items(CoPilotPrefabTopic.entries, key = { it.id }) { topic ->
                                val isSelected = selectedPrefab == topic
                                Row(
                                    modifier = Modifier
                                        .clip(CircleShape)
                                        .background(
                                            if (isSelected) topic.accentColor.copy(alpha = 0.24f)
                                            else Color.White.copy(alpha = 0.06f)
                                        )
                                        .border(
                                            width = 1.dp,
                                            color = if (isSelected) topic.accentColor else Color.White.copy(alpha = 0.12f),
                                            shape = CircleShape
                                        )
                                        .clickable { selectPrefabTopic(topic) }
                                        .padding(horizontal = 11.dp, vertical = 7.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                                ) {
                                    Icon(
                                        imageVector = topic.icon,
                                        contentDescription = null,
                                        tint = if (isSelected) Color.White else topic.accentColor,
                                        modifier = Modifier.size(13.dp)
                                    )
                                    Text(
                                        text = topic.chipLabel,
                                        color = if (isSelected) Color.White else Color.White.copy(alpha = 0.88f),
                                        fontSize = 11.5.sp,
                                        fontWeight = FontWeight.SemiBold
                                    )
                                }
                            }
                        }
                    }

                    // Interactive Custom Prompt Input Bar
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(14.dp))
                            .background(Color.Black.copy(alpha = 0.25f))
                            .border(0.8.dp, Color.White.copy(alpha = 0.12f), RoundedCornerShape(14.dp))
                            .padding(horizontal = 12.dp, vertical = 9.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.AutoAwesome,
                            contentDescription = null,
                            tint = ThemeColors.accentCyan.copy(alpha = 0.8f),
                            modifier = Modifier.size(14.dp)
                        )

                        Box(modifier = Modifier.weight(1f)) {
                            if (customQueryText.isEmpty()) {
                                Text(
                                    text = "Ask Monkey Co-Pilot about sleep, hydration, focus, or money...",
                                    color = Color.White.copy(alpha = 0.42f),
                                    fontSize = 12.sp,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }
                            BasicTextField(
                                value = customQueryText,
                                onValueChange = { customQueryText = it },
                                singleLine = true,
                                textStyle = TextStyle(
                                    color = Color.White,
                                    fontSize = 12.sp,
                                    fontWeight = FontWeight.Normal
                                ),
                                cursorBrush = SolidColor(ThemeColors.accentCyan),
                                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
                                keyboardActions = KeyboardActions(onSend = { submitCustomQuery() }),
                                modifier = Modifier.fillMaxWidth()
                            )
                        }

                        Icon(
                            imageVector = Icons.AutoMirrored.Rounded.Send,
                            contentDescription = "Ask Co-Pilot",
                            tint = if (customQueryText.isBlank()) Color.White.copy(alpha = 0.25f) else ThemeColors.accentCyan,
                            modifier = Modifier
                                .size(18.dp)
                                .clickable(enabled = customQueryText.isNotBlank()) {
                                    submitCustomQuery()
                                }
                        )
                    }
                }
            }
        }

        // -------------------------------------------------------------------
        // 4. Unified "Daily Spotlight & Hub Portals" Matrix (Replaces old tiles)
        // -------------------------------------------------------------------
        item(key = "spotlight_matrix_header") {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 4.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "DAILY SPOTLIGHT & HUB PORTALS",
                    color = ThemeColors.textSecondary,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 1.sp
                )
                Text(
                    text = "Tap any row to open Hub",
                    color = Color.White.copy(alpha = 0.42f),
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Medium
                )
            }
        }

        item(key = "spotlight_composite_matrix") {
            GlassCard(
                modifier = Modifier.fillMaxWidth(),
                cornerRadius = 22.dp,
                padding = 0.dp,
                intensity = GlassIntensity.Medium
            ) {
                Column(modifier = Modifier.fillMaxWidth()) {
                    // Band 1: Focus & Mental Stream (Tagdos Hub Portal)
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                onOpenHub(NavigationTab.Tagdos)
                            }
                            .padding(14.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalAlignment = Alignment.Top
                    ) {
                        SpotlightIconBadge(
                            icon = Icons.Rounded.Checklist,
                            color = Color(0xFFFFB300)
                        )

                        Column(
                            modifier = Modifier.weight(1f),
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(
                                    text = "Focus & Mental Stream",
                                    color = Color.White,
                                    fontSize = 14.sp,
                                    fontWeight = FontWeight.Bold
                                )
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(3.dp)
                                ) {
                                    Text(
                                        text = "Tagdos",
                                        color = Color(0xFFFFB300),
                                        fontSize = 11.sp,
                                        fontWeight = FontWeight.Bold
                                    )
                                    Icon(
                                        imageVector = Icons.Rounded.ArrowOutward,
                                        contentDescription = null,
                                        tint = Color(0xFFFFB300),
                                        modifier = Modifier.size(12.dp)
                                    )
                                }
                            }

                            if (topUrgentPills.isNotEmpty()) {
                                Row(
                                    modifier = Modifier.horizontalScroll(rememberScrollState()),
                                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                                ) {
                                    topUrgentPills.forEach { pillText ->
                                        Row(
                                            modifier = Modifier
                                                .clip(CircleShape)
                                                .background(Color(0xFFFFB300).copy(alpha = 0.14f))
                                                .border(0.7.dp, Color(0xFFFFB300).copy(alpha = 0.35f), CircleShape)
                                                .padding(horizontal = 8.dp, vertical = 4.dp),
                                            verticalAlignment = Alignment.CenterVertically,
                                            horizontalArrangement = Arrangement.spacedBy(4.dp)
                                        ) {
                                            Box(
                                                modifier = Modifier
                                                    .size(5.dp)
                                                    .clip(CircleShape)
                                                    .background(Color(0xFFFFB300))
                                            )
                                            Text(
                                                text = pillText,
                                                color = Color.White.copy(alpha = 0.92f),
                                                fontSize = 11.sp,
                                                fontWeight = FontWeight.SemiBold,
                                                maxLines = 1
                                            )
                                        }
                                    }
                                }
                            } else {
                                val notePreview = latestNote?.displayTitle?.takeIf { it.isNotBlank() }
                                    ?: latestNote?.content?.trim()?.take(80)
                                    ?: "No urgent blockers — tap to capture a quick memo or task."
                                Text(
                                    text = "\"$notePreview\"",
                                    color = Color.White.copy(alpha = 0.78f),
                                    fontSize = 12.sp,
                                    fontStyle = FontStyle.Italic,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }
                        }
                    }

                    HorizontalDivider(
                        modifier = Modifier.padding(horizontal = 16.dp),
                        thickness = 1.dp,
                        color = Color.White.copy(alpha = 0.07f)
                    )

                    // Band 2: Circadian Bio-Protocol (Habits & Health Hub Portals)
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(14.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalAlignment = Alignment.Top
                    ) {
                        SpotlightIconBadge(
                            icon = Icons.Rounded.WaterDrop,
                            color = ThemeColors.accentCyan
                        )

                        Column(
                            modifier = Modifier.weight(1f),
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Column {
                                    Text(
                                        text = hydroWindow.title,
                                        color = Color.White,
                                        fontSize = 14.sp,
                                        fontWeight = FontWeight.Bold
                                    )
                                    Text(
                                        text = "${hydroWindow.timeRange} • Target +${hydroWindow.recommendedVolumeMl} ml",
                                        color = ThemeColors.accentCyan,
                                        fontSize = 10.5.sp,
                                        fontWeight = FontWeight.SemiBold
                                    )
                                }

                                // Dual Direct Hub Portals: Habits & Health
                                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                    Row(
                                        modifier = Modifier
                                            .clip(CircleShape)
                                            .background(ThemeColors.accentCyan.copy(alpha = 0.14f))
                                            .clickable {
                                                haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                                onOpenHub(NavigationTab.Habits)
                                            }
                                            .padding(horizontal = 8.dp, vertical = 4.dp),
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(3.dp)
                                    ) {
                                        Text(
                                            text = "Habits",
                                            color = ThemeColors.accentCyan,
                                            fontSize = 10.5.sp,
                                            fontWeight = FontWeight.Bold
                                        )
                                        Icon(
                                            imageVector = Icons.Rounded.ArrowOutward,
                                            contentDescription = null,
                                            tint = ThemeColors.accentCyan,
                                            modifier = Modifier.size(11.dp)
                                        )
                                    }

                                    Row(
                                        modifier = Modifier
                                            .clip(CircleShape)
                                            .background(ThemeColors.accentPink.copy(alpha = 0.14f))
                                            .clickable {
                                                haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                                onOpenHub(NavigationTab.Health)
                                            }
                                            .padding(horizontal = 8.dp, vertical = 4.dp),
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(3.dp)
                                    ) {
                                        Text(
                                            text = "Vitals",
                                            color = ThemeColors.accentPink,
                                            fontSize = 10.5.sp,
                                            fontWeight = FontWeight.Bold
                                        )
                                        Icon(
                                            imageVector = Icons.Rounded.ArrowOutward,
                                            contentDescription = null,
                                            tint = ThemeColors.accentPink,
                                            modifier = Modifier.size(11.dp)
                                        )
                                    }
                                }
                            }

                            Text(
                                text = hydroWindow.rationale,
                                color = Color.White.copy(alpha = 0.78f),
                                fontSize = 11.5.sp,
                                lineHeight = 16.sp,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis
                            )
                        }
                    }

                    HorizontalDivider(
                        modifier = Modifier.padding(horizontal = 16.dp),
                        thickness = 1.dp,
                        color = Color.White.copy(alpha = 0.07f)
                    )

                    // Band 3: Cashflow Momentum Bar (Finances Hub Portal)
                    val inflow = max(parsedLedger.incomingTotal, 0.0)
                    val outflow = max(parsedLedger.outgoingTotal, 0.0)
                    val totalFlow = max(inflow + outflow, 1.0)
                    val inflowRatio = (inflow / totalFlow).toFloat().coerceIn(0.08f, 0.92f)
                    val netDelta = inflow - outflow

                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                onOpenHub(NavigationTab.Finances)
                            }
                            .padding(14.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalAlignment = Alignment.Top
                    ) {
                        SpotlightIconBadge(
                            icon = Icons.Rounded.AccountBalanceWallet,
                            color = Color(0xFF10B981)
                        )

                        Column(
                            modifier = Modifier.weight(1f),
                            verticalArrangement = Arrangement.spacedBy(7.dp)
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(
                                    text = "Cashflow Momentum • ${parsedLedger.formattedNetWorthEUR}",
                                    color = Color.White,
                                    fontSize = 13.5.sp,
                                    fontWeight = FontWeight.Bold
                                )
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(3.dp)
                                ) {
                                    Text(
                                        text = "Ledger",
                                        color = Color(0xFF10B981),
                                        fontSize = 11.sp,
                                        fontWeight = FontWeight.Bold
                                    )
                                    Icon(
                                        imageVector = Icons.Rounded.ArrowOutward,
                                        contentDescription = null,
                                        tint = Color(0xFF10B981),
                                        modifier = Modifier.size(12.dp)
                                    )
                                }
                            }

                            // Proportional Inflow vs Outflow Visual Bar
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .height(7.dp)
                                    .clip(CircleShape)
                                    .background(Color.White.copy(alpha = 0.06f)),
                                horizontalArrangement = Arrangement.spacedBy(3.dp)
                            ) {
                                Box(
                                    modifier = Modifier
                                        .weight(inflowRatio)
                                        .fillMaxHeight()
                                        .clip(CircleShape)
                                        .background(Color(0xFF10B981))
                                )
                                Box(
                                    modifier = Modifier
                                        .weight(1f - inflowRatio)
                                        .fillMaxHeight()
                                        .clip(CircleShape)
                                        .background(Color(0xFFFF2D55))
                                )
                            }

                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(
                                    text = "In +${inflow.roundToInt()}k • Out -${outflow.roundToInt()}k Lei",
                                    color = Color.White.copy(alpha = 0.65f),
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.Medium
                                )
                                Text(
                                    text = if (netDelta >= 0) "Net +${netDelta.roundToInt()}k Surplus" else "Net -${abs(netDelta).roundToInt()}k Deficit",
                                    color = if (netDelta >= 0) Color(0xFF10B981) else Color(0xFFFF2D55),
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.Bold
                                )
                            }
                        }
                    }

                    HorizontalDivider(
                        modifier = Modifier.padding(horizontal = 16.dp),
                        thickness = 1.dp,
                        color = Color.White.copy(alpha = 0.07f)
                    )

                    // Band 4: Editorial Radar & Sky (News + Weather Hub Portals)
                    val tempC = weather?.main?.temp?.roundToInt()
                    val weatherMain = weather?.weather?.firstOrNull()?.main?.lowercase() ?: ""
                    val isRainy = weatherMain.contains("rain") || weatherMain.contains("drizzle") || weatherMain.contains("storm") || weatherMain.contains("snow")
                    val skyAdvice = when {
                        tempC != null && isRainy -> "$tempC°C & precipitation — umbrella advised"
                        tempC != null -> "$tempC°C — ideal outdoor window for walk & sunlight"
                        else -> "Check live radar & hourly UV forecast"
                    }

                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(14.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalAlignment = Alignment.Top
                    ) {
                        SpotlightIconBadge(
                            icon = Icons.Rounded.Newspaper,
                            color = Color(0xFF38BDF8)
                        )

                        Column(
                            modifier = Modifier.weight(1f),
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable {
                                        haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                        onOpenHub(NavigationTab.News)
                                    },
                                verticalArrangement = Arrangement.spacedBy(2.dp)
                            ) {
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                                ) {
                                    Text(
                                        text = latestArticle?.publicationName ?: "Editorial Radar",
                                        color = Color(0xFF38BDF8),
                                        fontSize = 10.sp,
                                        fontWeight = FontWeight.Bold
                                    )
                                    Text(
                                        text = "•",
                                        color = Color.White.copy(alpha = 0.4f),
                                        fontSize = 10.sp
                                    )
                                    Text(
                                        text = "Read in News Hub ↗",
                                        color = Color.White.copy(alpha = 0.55f),
                                        fontSize = 10.sp,
                                        fontWeight = FontWeight.SemiBold
                                    )
                                }

                                Text(
                                    text = latestArticle?.title ?: "Curated intelligence feeds ready for deep reading.",
                                    color = Color.White.copy(alpha = 0.95f),
                                    fontSize = 12.5.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    lineHeight = 17.sp,
                                    maxLines = 2,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }

                            Row(
                                modifier = Modifier
                                    .clip(CircleShape)
                                    .background(Color(0xFFFBBF24).copy(alpha = 0.12f))
                                    .clickable {
                                        haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                        onOpenHub(NavigationTab.Weather)
                                    }
                                    .padding(horizontal = 8.dp, vertical = 4.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(5.dp)
                            ) {
                                Icon(
                                    imageVector = Icons.Rounded.Cloud,
                                    contentDescription = null,
                                    tint = Color(0xFFFBBF24),
                                    modifier = Modifier.size(12.dp)
                                )
                                Text(
                                    text = "$skyAdvice • Weather ↗",
                                    color = Color(0xFFFBBF24),
                                    fontSize = 10.5.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Subcomponents & Deterministic Co-Pilot Intelligence Builders
// ---------------------------------------------------------------------------

@Composable
private fun RingMetricItem(
    label: String,
    value: String,
    color: Color,
    onClick: () -> Unit
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .clip(RoundedCornerShape(8.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 8.dp, vertical = 4.dp)
    ) {
        Text(
            text = value,
            color = Color.White,
            fontSize = 16.sp,
            fontWeight = FontWeight.Bold
        )
        Text(
            text = label,
            color = color,
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold,
            letterSpacing = 0.5.sp
        )
    }
}

@Composable
private fun SpotlightIconBadge(
    icon: ImageVector,
    color: Color
) {
    Box(
        modifier = Modifier
            .size(36.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(color.copy(alpha = 0.15f))
            .border(1.dp, color.copy(alpha = 0.35f), RoundedCornerShape(12.dp)),
        contentAlignment = Alignment.Center
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = color,
            modifier = Modifier.size(18.dp)
        )
    }
}

private fun synthesizeCrossDomainPulse(
    slot: BriefingTimeSlot,
    stressLevel: StressLevel?,
    primarySleep: SleepSession?,
    activeBriefing: SmartBriefingRecord?,
    hydroWindow: CircadianHydrationWindow,
    waterMl: Int,
    waterGoalMl: Int,
    totalSteps: Int,
    topUrgentPills: List<String>
): Pair<String, String> {
    val stressName = stressLevel?.displayName ?: "Balanced"
    val headline = "${slot.displayName} • $stressName Autonomic Tone"

    // Check if activeBriefing has up-to-date sleep telemetry matching primarySleep
    val liveSleepScore = primarySleep?.sleepScore
    val briefSleepScore = activeBriefing?.metrics?.sleepScore
    val isSleepConsistent = (liveSleepScore == briefSleepScore)

    if (isSleepConsistent && activeBriefing != null) {
        val parts = listOf(
            activeBriefing.narrative.healthText,
            activeBriefing.narrative.stressText,
            activeBriefing.narrative.tagdosText
        ).filter { it.isNotBlank() }

        if (parts.isNotEmpty()) {
            return headline to parts.joinToString(" ")
        }
    }

    // Dynamic live synthesis incorporating real-time sleep, hydration, and tasks
    val sleepPart = if (primarySleep != null) {
        val sleepTime = primarySleep.totalAsleepFormatted
        val score = primarySleep.sleepScore
        if (score >= 80) {
            "Great recovery with $sleepTime asleep (Score $score%). Ready for a focused, high-energy day."
        } else {
            "Logged $sleepTime asleep (Score $score%). Maintain steady energy and stay hydrated."
        }
    } else ""

    val focusPart = if (topUrgentPills.isEmpty()) {
        "Tagdos streams have no urgent blockers."
    } else {
        "Priority focus: ${topUrgentPills.take(3).joinToString(", ")}."
    }

    val hydroPart = "You're in the ${hydroWindow.title} window ($waterMl/$waterGoalMl ml logged, $totalSteps steps)."
    val body = listOf(sleepPart, hydroPart, focusPart)
        .filter { it.isNotBlank() }
        .joinToString(" ")

    return headline to body
}

private fun buildInlineTurn(
    topic: CoPilotPrefabTopic,
    primarySleep: SleepSession?,
    hydroWindow: CircadianHydrationWindow,
    waterMl: Int,
    waterGoalMl: Int,
    hydrationProgress: Float,
    smokesTotal: Int,
    topUrgentPills: List<String>,
    streamsCount: Int,
    quickNotes: List<TagDoQuickNote>,
    stressScore: Int?,
    stressLevel: StressLevel?,
    displayBpm: Double,
    parsedLedger: ParsedSmartLedger
): CoPilotInlineTurn {
    return when (topic) {
        CoPilotPrefabTopic.SLEEP_RECOVERY -> {
            if (primarySleep != null && primarySleep.sleepScore > 0) {
                val totalMins = (primarySleep.asleepSeconds / 60.0).roundToInt()
                val hours = totalMins / 60
                val mins = totalMins % 60
                val deepMins = (primarySleep.deepSeconds / 60.0).roundToInt()
                val remMins = (primarySleep.remSeconds / 60.0).roundToInt()
                CoPilotInlineTurn(
                    question = topic.fullQuestion,
                    headline = "Sleep Score ${primarySleep.sleepScore}% • ${hours}h ${mins}m Architecture",
                    body = "Your nocturnal session recorded ${deepMins}m of physical-repair Deep NREM and ${remMins}m of cognitive REM consolidation.",
                    highlights = listOf(
                        "Deep NREM (${deepMins}m): Supports muscular & immune cellular restoration.",
                        "REM Stage (${remMins}m): Anchors emotional regulation and memory synthesis."
                    ),
                    targetTab = topic.targetTab,
                    portalTitle = topic.portalButtonTitle,
                    accentColor = topic.accentColor
                )
            } else {
                CoPilotInlineTurn(
                    question = topic.fullQuestion,
                    headline = "Sleep Architecture & Circadian Readiness",
                    body = "No nocturnal session synced yet for today. To maximize slow-wave Deep Sleep and REM consolidation tonight, anchor your circadian clock with morning daylight and cool your bedroom to 18–20°C.",
                    highlights = listOf(
                        "Circadian Anchor: 15–20 min outdoor daylight boosts evening melatonin onset.",
                        "Thermoregulation: A 1°C core temperature drop triggers deep NREM stages."
                    ),
                    targetTab = topic.targetTab,
                    portalTitle = topic.portalButtonTitle,
                    accentColor = topic.accentColor
                )
            }
        }

        CoPilotPrefabTopic.CIRCADIAN_HYDRATION -> {
            val pct = (hydrationProgress * 100).roundToInt()
            CoPilotInlineTurn(
                question = topic.fullQuestion,
                headline = "${hydroWindow.title} (${hydroWindow.timeRange})",
                body = "${hydroWindow.rationale} You have logged $waterMl / $waterGoalMl ml today ($pct%).",
                highlights = listOf(
                    "Recommended Intake Now: +${hydroWindow.recommendedVolumeMl} ml pure or electrolyte water.",
                    if (smokesTotal == 0) {
                        "Smoke-Free Streak: 0 cigarettes logged today — bronchial and vascular recovery active."
                    } else {
                        "4D Craving Protocol (Delay & Drink Water): Wait 7 minutes and sip ice water slowly to blunt dopamine spikes."
                    }
                ),
                targetTab = topic.targetTab,
                portalTitle = topic.portalButtonTitle,
                accentColor = topic.accentColor
            )
        }

        CoPilotPrefabTopic.URGENT_FOCUS -> {
            val latestNote = quickNotes.firstOrNull()
            val notePreview = latestNote?.displayTitle?.takeIf { it.isNotBlank() }
                ?: latestNote?.content?.take(70)
                ?: "No active quick memos"

            val bodyText = if (topUrgentPills.isEmpty()) {
                "All $streamsCount Tagdos streams are clear of urgent blockers. You have ${quickNotes.size} quick notes stored."
            } else {
                "Across your $streamsCount active streams, these driving tasks require your immediate execution:"
            }

            val bullets = mutableListOf<String>()
            topUrgentPills.take(3).forEach { bullets.add("Priority Pill: $it") }
            bullets.add("Latest Memo: \"$notePreview\"")

            CoPilotInlineTurn(
                question = topic.fullQuestion,
                headline = "Tagdos Execution & Mental Stream",
                body = bodyText,
                highlights = bullets,
                targetTab = topic.targetTab,
                portalTitle = topic.portalButtonTitle,
                accentColor = topic.accentColor
            )
        }

        CoPilotPrefabTopic.STRESS_RESET -> {
            val levelName = stressLevel?.displayName ?: "Balanced"
            val scoreVal = stressScore ?: 25
            val bpmText = if (displayBpm > 0.0) "${displayBpm.roundToInt()} BPM" else "baseline"
            CoPilotInlineTurn(
                question = topic.fullQuestion,
                headline = "Autonomic Balance: $levelName ($scoreVal/100)",
                body = "Your sympathetic/parasympathetic balance is currently ${levelName.lowercase()} with heart rate at $bpmText. Use a 60-second vagal reset to elevate HRV and mental clarity:",
                highlights = listOf(
                    "Physiological Sigh: Double inhale through the nose, long slow exhale through the mouth (3x).",
                    "Box Breathing: Inhale 4s → Hold 4s → Exhale 4s → Hold 4s for parasympathetic calm."
                ),
                targetTab = topic.targetTab,
                portalTitle = topic.portalButtonTitle,
                accentColor = topic.accentColor
            )
        }

        CoPilotPrefabTopic.WEALTH_PULSE -> {
            val netFlow = parsedLedger.incomingTotal - parsedLedger.outgoingTotal
            CoPilotInlineTurn(
                question = topic.fullQuestion,
                headline = "Net Worth ${parsedLedger.formattedNetWorthEUR} • Flow Analysis",
                body = "Your Smart Ledger tracks ${parsedLedger.incomingTotal.roundToInt()}k Lei incoming against ${parsedLedger.outgoingTotal.roundToInt()}k Lei outgoing, with liquid deposits at ${parsedLedger.depositTotal.roundToInt()}k Lei.",
                highlights = listOf(
                    if (netFlow >= 0) {
                        "Monthly Balance: Positive net flow of +${netFlow.roundToInt()}k Lei."
                    } else {
                        "Monthly Balance: Outflow exceeds inflow by ${abs(netFlow).roundToInt()}k Lei — review discretionary items."
                    },
                    "EUR Portfolio Value: ${parsedLedger.formattedNetWorthEUR} across liquid & deposit assets."
                ),
                targetTab = topic.targetTab,
                portalTitle = topic.portalButtonTitle,
                accentColor = topic.accentColor
            )
        }
    }
}
