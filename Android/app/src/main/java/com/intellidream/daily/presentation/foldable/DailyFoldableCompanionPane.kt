package com.intellidream.daily.presentation.foldable

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
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
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Cloud
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.Newspaper
import androidx.compose.material.icons.rounded.WaterDrop
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
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
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.health.HealthDataRepository
import com.intellidream.daily.model.AppSettings
import com.intellidream.daily.model.BriefingTimeSlot
import com.intellidream.daily.model.MonkeyMood
import com.intellidream.daily.designsystem.NavigationTab
import com.intellidream.daily.model.NewsArticle
import com.intellidream.daily.model.UserProfile
import com.intellidream.daily.model.WeatherResponse
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.roundToInt

/**
 * Signature Foldable Companion Pane displayed in the right pane on expanded displays
 * (Samsung Galaxy Z Fold 8, Google Pixel 9 Pro Fold) when no secondary Hub or sheet is active.
 *
 * Provides a live biometric vitals pulse, interactive Smart Briefing audio launcher,
 * and quick-glance companion hubs to maintain high utility across the unfolded screen canvas.
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

    // Briefing Telemetry
    val activeBriefing by smartBriefingRepository.activeBriefing.collectAsState()
    val slot = activeBriefing?.slot ?: BriefingTimeSlot.current()

    val displayBpm = latestBpm ?: averageBpm
    val hydrationProgress = if (waterGoal > 0) (waterTotal.toFloat() / waterGoal.toFloat()).coerceIn(0f, 1f) else 0f
    val stepsProgress = (totalSteps.toFloat() / 10000f).coerceIn(0f, 1f)
    val sleepScore = primarySleep?.sleepScore ?: 0
    val sleepProgress = (sleepScore.toFloat() / 100f).coerceIn(0f, 1f)

    val todayFormatted = remember {
        SimpleDateFormat("EEEE · MMMM d", Locale.getDefault()).format(Date())
    }

    LazyColumn(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp),
        contentPadding = PaddingValues(top = 16.dp, bottom = 90.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // 1. Companion Header Pill
        item(key = "companion_header") {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(
                            modifier = Modifier
                                .size(8.dp)
                                .clip(CircleShape)
                                .background(ThemeColors.accentGreen)
                        )
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(
                            text = "COMPANION PULSE",
                            color = ThemeColors.accentGreen,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold,
                            letterSpacing = 1.sp
                        )
                    }
                    Text(
                        text = todayFormatted,
                        color = Color.White,
                        fontSize = 20.sp,
                        fontWeight = FontWeight.Bold
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

        // 2. Concentric Rings & Mascot Hero Card
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

        // 3. Smart Briefing Quick Launcher
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

        // 4. Companion Hub Quick Navigation Cards
        item(key = "companion_hub_cards") {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    text = "QUICK HUBS",
                    color = ThemeColors.textSecondary,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 1.sp,
                    modifier = Modifier.padding(start = 4.dp, bottom = 2.dp)
                )

                // Health Studio Hub Shortcut
                CompanionHubRow(
                    title = "Health Studio & Biometrics",
                    subtitle = if (displayBpm > 0.0) "${displayBpm.roundToInt()} BPM · $totalSteps Steps" else "Track sleep, vitals and stress",
                    icon = Icons.Rounded.Favorite,
                    iconTint = ThemeColors.accentPink,
                    onClick = { onOpenHub(NavigationTab.Health) }
                )

                // Finances & Smart Ledger Shortcut
                val ledgerNetWorth = parsedLedger.netWorth
                val netWorthDisplay = if (ledgerNetWorth > 0.0) parsedLedger.formattedNetWorthEUR else "Track assets & ledger"
                CompanionHubRow(
                    title = "Smart Ledger & Finances",
                    subtitle = if (ledgerNetWorth > 0.0) "Net Worth: $netWorthDisplay" else "Track transactions & assets",
                    icon = Icons.Rounded.AccountBalanceWallet,
                    iconTint = ThemeColors.accentGreen,
                    onClick = { onOpenHub(NavigationTab.Finances) }
                )

                // Habits Shortcut with Quick Hydration
                CompanionHubRow(
                    title = "Habits & Routines",
                    subtitle = "$waterTotal / $waterGoal ml water · $smokesTotal smokes",
                    icon = Icons.Rounded.WaterDrop,
                    iconTint = ThemeColors.accentCyan,
                    onClick = { onOpenHub(NavigationTab.Habits) }
                )

                // News Feed Shortcut
                CompanionHubRow(
                    title = "Curated News & Briefing",
                    subtitle = latestArticle?.title ?: "Read full RSS and AI feeds",
                    icon = Icons.Rounded.Newspaper,
                    iconTint = ThemeColors.accentBlue,
                    onClick = { onOpenHub(NavigationTab.News) }
                )

                // Weather Detail Shortcut
                if (weather != null) {
                    CompanionHubRow(
                        title = "${weather.name} · ${weather.main.temp.roundToInt()}°",
                        subtitle = weather.weather.firstOrNull()?.description?.replaceFirstChar { it.uppercase() } ?: "Current conditions",
                        icon = Icons.Rounded.Cloud,
                        iconTint = ThemeColors.accentYellow,
                        onClick = { onOpenHub(NavigationTab.Weather) }
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

@Composable
private fun CompanionHubRow(
    title: String,
    subtitle: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    iconTint: Color,
    onClick: () -> Unit
) {
    GlassCard(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .clickable(onClick = onClick),
        cornerRadius = 16.dp,
        padding = 14.dp,
        intensity = GlassIntensity.Medium
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.weight(1f)
            ) {
                Box(
                    modifier = Modifier
                        .size(38.dp)
                        .clip(RoundedCornerShape(10.dp))
                        .background(iconTint.copy(alpha = 0.15f)),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = icon,
                        contentDescription = null,
                        tint = iconTint,
                        modifier = Modifier.size(20.dp)
                    )
                }

                Spacer(modifier = Modifier.width(12.dp))

                Column {
                    Text(
                        text = title,
                        color = Color.White,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        text = subtitle,
                        color = ThemeColors.textSecondary,
                        fontSize = 12.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }

            Icon(
                imageVector = Icons.Rounded.ChevronRight,
                contentDescription = null,
                tint = Color.White.copy(alpha = 0.4f),
                modifier = Modifier.size(20.dp)
            )
        }
    }
}
