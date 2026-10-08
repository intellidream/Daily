package com.intellidream.daily.presentation.foldable

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.rounded.VolumeUp
import androidx.compose.material.icons.rounded.AccountBalanceWallet
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Bedtime
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Checklist
import androidx.compose.material.icons.rounded.Cloud
import androidx.compose.material.icons.rounded.DirectionsWalk
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.Newspaper
import androidx.compose.material.icons.rounded.NightsStay
import androidx.compose.material.icons.rounded.WaterDrop
import androidx.compose.material.icons.rounded.WbSunny
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.briefing.SmartBriefingRepository
import com.intellidream.daily.database.FinanceDataRepository
import com.intellidream.daily.database.HabitsRepository
import com.intellidream.daily.database.NewsRepository
import com.intellidream.daily.database.SmartLedgerRepository
import com.intellidream.daily.database.TagdosRepository
import com.intellidream.daily.designsystem.GlassButton
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
import com.intellidream.daily.model.UserProfile
import com.intellidream.daily.model.WeatherResponse
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.roundToInt

/**
 * Signature Foldable Companion Pane displayed in the secondary / detail pane on expanded displays
 * (Samsung Galaxy Z Fold 8, Google Pixel 9 Pro Fold) when no hub or sheet is explicitly open.
 *
 * Provides a live diurnal intelligence header adapted to the time of day,
 * concentric recovery rings with animated stress mascot, Smart Briefing audio trigger,
 * and a rich Executive Multi-Hub Digest summarizing biometrics, habits, wealth, and news.
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
    val quickNotes by tagdosRepository.quickNotes.collectAsState()
    val latestNote = quickNotes.firstOrNull()

    // Briefing Telemetry
    val activeBriefing by smartBriefingRepository.activeBriefing.collectAsState()
    val slot = activeBriefing?.slot ?: BriefingTimeSlot.current()

    val displayBpm = latestBpm ?: averageBpm
    val hydrationProgress = if (waterGoal > 0) (waterTotal.toFloat() / waterGoal.toFloat()).coerceIn(0f, 1f) else 0f
    val stepsProgress = (totalSteps.toFloat() / 10000f).coerceIn(0f, 1f)
    val sleepScore = primarySleep?.sleepScore ?: 0
    val sleepProgress = (sleepScore.toFloat() / 100f).coerceIn(0f, 1f)

    // Diurnal Wish and Icon adapted to the time of day (1:1 with Smart Briefing bottom button)
    val diurnalWish = activeBriefing?.narrative?.closingWish ?: slot.defaultClosingWish
    val slotIcon: ImageVector = when (slot) {
        BriefingTimeSlot.MORNING -> Icons.Rounded.WbSunny
        BriefingTimeSlot.INTRADAY -> Icons.Rounded.WbSunny
        BriefingTimeSlot.EVENING -> Icons.Rounded.NightsStay
        BriefingTimeSlot.NIGHTLY -> Icons.Rounded.NightsStay
    }

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(top = 8.dp, bottom = 90.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        // 1. Diurnal Intelligence Header (Matching left HeaderGreetingView 56dp height & vertical alignment)
        item(key = "companion_header") {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp)
                    .padding(top = 4.dp, bottom = 4.dp),
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

                // Quick Live Heart Rate Pill
                GlassCard(
                    modifier = Modifier.clip(RoundedCornerShape(14.dp)),
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

        // 2. Concentric Recovery Rings & Mascot Hero Card
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
                        // Outer Ring: Activity / Steps
                        CircularProgressIndicator(
                            progress = { stepsProgress },
                            modifier = Modifier.size(170.dp),
                            color = ThemeColors.accentOrange,
                            trackColor = ThemeColors.accentOrange.copy(alpha = 0.15f),
                            strokeWidth = 10.dp,
                            strokeCap = StrokeCap.Round
                        )

                        // Middle Ring: Sleep Recovery
                        CircularProgressIndicator(
                            progress = { sleepProgress },
                            modifier = Modifier.size(136.dp),
                            color = ThemeColors.accentPurple,
                            trackColor = ThemeColors.accentPurple.copy(alpha = 0.15f),
                            strokeWidth = 10.dp,
                            strokeCap = StrokeCap.Round
                        )

                        // Inner Ring: Hydration
                        CircularProgressIndicator(
                            progress = { hydrationProgress },
                            modifier = Modifier.size(102.dp),
                            color = ThemeColors.accentCyan,
                            trackColor = ThemeColors.accentCyan.copy(alpha = 0.15f),
                            strokeWidth = 10.dp,
                            strokeCap = StrokeCap.Round
                        )

                        // Center: Live Stress Monkey Mascot
                        val monkeyMood = stressLevel?.let { MonkeyMood.fromLevel(it) } ?: MonkeyMood.ZEN
                        MonkeyMascotView(
                            mood = monkeyMood,
                            size = MonkeySize.CARD
                        )
                    }

                    Spacer(modifier = Modifier.height(16.dp))

                    // Metrics Legend Grid
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceEvenly
                    ) {
                        RingMetricItem(
                            label = "STEPS",
                            value = "$totalSteps",
                            color = ThemeColors.accentOrange,
                            onClick = { onOpenHub(NavigationTab.Health) }
                        )
                        RingMetricItem(
                            label = "SLEEP",
                            value = if (sleepScore > 0) "$sleepScore%" else "--",
                            color = ThemeColors.accentPurple,
                            onClick = { onOpenHub(NavigationTab.Health) }
                        )
                        RingMetricItem(
                            label = "WATER",
                            value = "${(hydrationProgress * 100).roundToInt()}%",
                            color = ThemeColors.accentCyan,
                            onClick = { onOpenHub(NavigationTab.Habits) }
                        )
                    }
                }
            }
        }

        // 3. Smart Briefing Quick Launcher Card
        item(key = "companion_briefing_card") {
            val auraBrush = Brush.horizontalGradient(
                listOf(
                    Color(0xFF0F1E36),
                    Color(0xFF14294D)
                )
            )

            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(20.dp))
                    .background(auraBrush)
                    .border(1.dp, ThemeColors.accentCyan.copy(alpha = 0.35f), RoundedCornerShape(20.dp))
                    .clickable {
                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                        onOpenBriefing()
                    }
                    .padding(18.dp)
            ) {
                Column {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                imageVector = Icons.Rounded.AutoAwesome,
                                contentDescription = null,
                                tint = ThemeColors.accentCyan,
                                modifier = Modifier.size(18.dp)
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(
                                text = "SMART BRIEFING · ${slot.name.uppercase()}",
                                color = ThemeColors.accentCyan,
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold,
                                letterSpacing = 0.8.sp
                            )
                        }

                        Icon(
                            imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                            contentDescription = null,
                            tint = Color.White.copy(alpha = 0.6f),
                            modifier = Modifier.size(20.dp)
                        )
                    }

                    Spacer(modifier = Modifier.height(10.dp))

                    val summaryText = activeBriefing?.narrative?.fullConcatenatedText?.takeIf { it.isNotBlank() }
                        ?: "Your personalized diurnal intelligence briefing is prepared. Tap to review insights, vitals, and goals."

                    Text(
                        text = summaryText,
                        color = Color.White.copy(alpha = 0.9f),
                        fontSize = 13.sp,
                        lineHeight = 18.sp,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )

                    Spacer(modifier = Modifier.height(14.dp))

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        GlassButton(
                            onClick = onOpenBriefing,
                            cornerRadius = 10.dp,
                            paddingHorizontal = 12.dp,
                            paddingVertical = 8.dp
                        ) {
                            Icon(
                                imageVector = Icons.AutoMirrored.Rounded.VolumeUp,
                                contentDescription = null,
                                tint = ThemeColors.accentCyan,
                                modifier = Modifier.size(16.dp)
                            )
                            Spacer(modifier = Modifier.width(6.dp))
                            Text(
                                text = "Listen / Open",
                                color = Color.White,
                                fontSize = 12.sp,
                                fontWeight = FontWeight.SemiBold
                            )
                        }

                        Text(
                            text = "3-4 min recap",
                            color = ThemeColors.textSecondary,
                            fontSize = 11.sp
                        )
                    }
                }
            }
        }

        // 4. Executive Multi-Hub Intelligence Digest (Full rich live summary replacing duplicate buttons)
        item(key = "executive_digest_header") {
            Text(
                text = "EXECUTIVE SUMMARY",
                color = ThemeColors.textSecondary,
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                letterSpacing = 1.sp,
                modifier = Modifier.padding(start = 4.dp, bottom = 2.dp)
            )
        }

        // Hub Digest 1: Health & Vitals
        item(key = "digest_health") {
            ExecutiveDigestCard(
                title = "Health & Vitals",
                subtitle = "Sleep, Recovery & Biometrics",
                icon = Icons.Rounded.Favorite,
                iconTint = ThemeColors.accentPink,
                onClick = { onOpenHub(NavigationTab.Health) }
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    DigestMetricPill(
                        label = "HEART",
                        value = if (displayBpm > 0.0) "${displayBpm.roundToInt()} BPM" else "-- BPM",
                        color = ThemeColors.accentPink
                    )
                    DigestMetricPill(
                        label = "RECOVERY",
                        value = if (sleepScore > 0) "$sleepScore%" else "--",
                        color = ThemeColors.accentPurple
                    )
                    DigestMetricPill(
                        label = "STEPS",
                        value = "$totalSteps",
                        color = ThemeColors.accentOrange
                    )
                    DigestMetricPill(
                        label = "ENERGY",
                        value = "${totalCalories.roundToInt()} kcal",
                        color = ThemeColors.accentCyan
                    )
                }
            }
        }

        // Hub Digest 2: Habits & Routines
        item(key = "digest_habits") {
            ExecutiveDigestCard(
                title = "Habits & Routines",
                subtitle = "Hydration & Smoke Cessation",
                icon = Icons.Rounded.WaterDrop,
                iconTint = ThemeColors.accentCyan,
                onClick = { onOpenHub(NavigationTab.Habits) }
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "Water: ${waterTotal.roundToInt()} / ${waterGoal.roundToInt()} ml",
                            color = Color.White.copy(alpha = 0.9f),
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                        Text(
                            text = "${(hydrationProgress * 100).roundToInt()}%",
                            color = ThemeColors.accentCyan,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }

                    LinearProgressIndicator(
                        progress = { hydrationProgress },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(6.dp)
                            .clip(RoundedCornerShape(3.dp)),
                        color = ThemeColors.accentCyan,
                        trackColor = ThemeColors.accentCyan.copy(alpha = 0.15f)
                    )

                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        modifier = Modifier.padding(top = 2.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.CheckCircle,
                            contentDescription = null,
                            tint = if (smokesTotal == 0) ThemeColors.accentGreen else ThemeColors.accentOrange,
                            modifier = Modifier.size(14.dp)
                        )
                        Text(
                            text = if (smokesTotal == 0) "Smoke-free today · Perfect clean streak" else "$smokesTotal smokes logged today",
                            color = if (smokesTotal == 0) ThemeColors.accentGreen else ThemeColors.textSecondary,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Medium
                        )
                    }
                }
            }
        }

        // Hub Digest 3: Smart Ledger & Money
        item(key = "digest_finances") {
            val netWorthEUR = parsedLedger.formattedNetWorthEUR
            ExecutiveDigestCard(
                title = "Smart Ledger",
                subtitle = "Wealth, Cashflow & Net Worth",
                icon = Icons.Rounded.AccountBalanceWallet,
                iconTint = ThemeColors.accentGreen,
                onClick = { onOpenHub(NavigationTab.Finances) }
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column {
                        Text(
                            text = "NET WORTH",
                            color = ThemeColors.textMuted,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                            letterSpacing = 0.8.sp
                        )
                        Text(
                            text = if (parsedLedger.netWorth > 0.0) netWorthEUR else "Track Assets",
                            color = Color.White,
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }

                    Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                        Column(horizontalAlignment = Alignment.End) {
                            Text(
                                text = "INFLOW",
                                color = ThemeColors.accentGreen,
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold
                            )
                            Text(
                                text = "+${parsedLedger.incomingTotal.roundToInt()} Lei",
                                color = Color.White.copy(alpha = 0.85f),
                                fontSize = 12.sp,
                                fontWeight = FontWeight.SemiBold
                            )
                        }
                        Column(horizontalAlignment = Alignment.End) {
                            Text(
                                text = "OUTFLOW",
                                color = ThemeColors.accentPink,
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold
                            )
                            Text(
                                text = "-${parsedLedger.outgoingTotal.roundToInt()} Lei",
                                color = Color.White.copy(alpha = 0.85f),
                                fontSize = 12.sp,
                                fontWeight = FontWeight.SemiBold
                            )
                        }
                    }
                }
            }
        }

        // Hub Digest 4: Tagdos & Notes
        item(key = "digest_tagdos") {
            ExecutiveDigestCard(
                title = "Tagdos & Notes",
                subtitle = "${quickNotes.size} Active Notes & Memos",
                icon = Icons.Rounded.Checklist,
                iconTint = ThemeColors.accentYellow,
                onClick = { onOpenHub(NavigationTab.Tagdos) }
            ) {
                val preview = latestNote?.displayTitle?.takeIf { it.isNotBlank() } ?: latestNote?.content?.trim()?.take(85)
                Text(
                    text = if (!preview.isNullOrBlank()) "\"$preview...\"" else "Capture ideas, quick memos, or tasks into your mental stream.",
                    color = Color.White.copy(alpha = 0.85f),
                    fontSize = 13.sp,
                    lineHeight = 18.sp,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }

        // Hub Digest 5: News & Briefings
        item(key = "digest_news") {
            ExecutiveDigestCard(
                title = "News & Briefings",
                subtitle = "Curated Intelligence",
                icon = Icons.Rounded.Newspaper,
                iconTint = ThemeColors.accentBlue,
                onClick = { onOpenHub(NavigationTab.News) }
            ) {
                if (latestArticle != null) {
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(
                            text = latestArticle.title,
                            color = Color.White.copy(alpha = 0.95f),
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Medium,
                            lineHeight = 18.sp,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis
                        )
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            Text(
                                text = latestArticle.publicationName ?: "Curated Feed",
                                color = ThemeColors.accentBlue,
                                fontSize = 11.sp,
                                fontWeight = FontWeight.SemiBold
                            )
                            Text(
                                text = "•",
                                color = ThemeColors.textMuted,
                                fontSize = 10.sp
                            )
                            Text(
                                text = latestArticle.relativeTimeFormatted,
                                color = ThemeColors.textSecondary,
                                fontSize = 11.sp
                            )
                        }
                    }
                } else {
                    Text(
                        text = "Curated morning & intraday intelligence feeds are ready for deep reading.",
                        color = Color.White.copy(alpha = 0.85f),
                        fontSize = 13.sp
                    )
                }
            }
        }
    }
}

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

/**
 * Signature Executive Digest Card rendering live summary content for a specific Hub.
 */
@Composable
private fun ExecutiveDigestCard(
    title: String,
    subtitle: String,
    icon: ImageVector,
    iconTint: Color,
    onClick: () -> Unit,
    content: @Composable () -> Unit
) {
    GlassCard(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .clickable(onClick = onClick),
        cornerRadius = 18.dp,
        padding = 16.dp,
        intensity = GlassIntensity.Medium
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            // Card Header
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        modifier = Modifier
                            .size(34.dp)
                            .clip(RoundedCornerShape(10.dp))
                            .background(iconTint.copy(alpha = 0.15f))
                            .border(1.dp, iconTint.copy(alpha = 0.35f), RoundedCornerShape(10.dp)),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = icon,
                            contentDescription = null,
                            tint = iconTint,
                            modifier = Modifier.size(18.dp)
                        )
                    }

                    Spacer(modifier = Modifier.width(10.dp))

                    Column {
                        Text(
                            text = title,
                            color = Color.White,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Bold
                        )
                        Text(
                            text = subtitle,
                            color = ThemeColors.textSecondary,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Normal
                        )
                    }
                }

                Icon(
                    imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                    contentDescription = null,
                    tint = Color.White.copy(alpha = 0.4f),
                    modifier = Modifier.size(18.dp)
                )
            }

            // Custom Content Body
            content()
        }
    }
}

@Composable
private fun DigestMetricPill(
    label: String,
    value: String,
    color: Color
) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            text = value,
            color = Color.White,
            fontSize = 13.sp,
            fontWeight = FontWeight.Bold
        )
        Text(
            text = label,
            color = color,
            fontSize = 10.sp,
            fontWeight = FontWeight.SemiBold,
            letterSpacing = 0.5.sp
        )
    }
}
