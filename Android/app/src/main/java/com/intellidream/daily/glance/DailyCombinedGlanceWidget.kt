package com.intellidream.daily.glance

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.intellidream.daily.DailyApp
import com.intellidream.daily.MainActivity
import com.intellidream.daily.R
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

class DailyCombinedGlanceReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = DailyCombinedGlanceWidget()
}

class DailyCombinedGlanceWidget : GlanceAppWidget() {

    override val sizeMode: SizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val app = runCatching { DailyApp.instance }.getOrNull()
        val waterLogs = app?.habitsRepository?.selectedDateWaterLogs?.value ?: emptyList()
        val waterMl = app?.habitsRepository?.waterTotalToday?.value ?: waterLogs.sumOf { it.value }
        val goalMl = app?.habitsRepository?.waterGoal?.value ?: 2000.0
        val waterPercent = if (goalMl > 0) min(waterMl / goalMl, 1.0) else 0.0

        val smokesLogs = app?.habitsRepository?.selectedDateSmokesLogs?.value ?: emptyList()
        val smokesCount = app?.habitsRepository?.smokesTotalToday?.value ?: smokesLogs.sumOf { it.value.toInt() }
        val smokesBase = app?.habitsRepository?.smokesSettings?.value?.baselineDailyCount ?: 20
        val smokesRingColorInt = WidgetVisualGraphics.getSmokeRingColor(smokesCount, smokesBase)

        val sleepSession = app?.healthRepository?.primarySleepSession?.value
        val sleepScore = sleepSession?.sleepScore ?: 88
        val totalMinutes = if (sleepSession != null && sleepSession.asleepSeconds > 0) (sleepSession.asleepSeconds / 60.0).roundToInt() else (7 * 60 + 42)
        val totalAsleep = "${totalMinutes / 60}h ${totalMinutes % 60}m"
        val sleepEff = sleepSession?.efficiencyPercent ?: 93
        val deepSec = sleepSession?.deepSeconds?.takeIf { it > 0 } ?: 5400.0
        val remSec = sleepSession?.remSeconds?.takeIf { it > 0 } ?: 6120.0
        val deepFormatted = "${(deepSec / 3600).toInt()}h ${((deepSec % 3600) / 60).toInt()}m"
        val remFormatted = "${(remSec / 3600).toInt()}h ${((remSec % 3600) / 60).toInt()}m"

        val parsedMoney = app?.smartLedgerRepository?.parsedLedger?.value
        val netWorthLei = parsedMoney?.netWorth ?: 127156.47
        val netWorthEUR = parsedMoney?.netWorthEUR ?: (netWorthLei / 5.0)
        val formattedNetWorth = WidgetVisualGraphics.formatCompactNumber(netWorthLei) + " Lei"
        val formattedNetWorthEUR = "~" + WidgetVisualGraphics.formatCompactIntegerEUR(netWorthEUR)

        val stressScore = app?.healthRepository?.currentStressScore?.value ?: 28
        val stressLevelObj = app?.healthRepository?.currentStressLevel?.value
        val stressLevel = stressLevelObj?.displayName ?: "Calm"
        val stressEmoji = when (stressLevel) {
            "High" -> "⚡️"
            "Moderate" -> "🐵"
            else -> "🧘"
        }
        val stressColor = Color(android.graphics.Color.parseColor(stressLevelObj?.hexColor ?: "#10B981"))

        val firstActivePill = app?.tagdosRepository?.streams?.value
            ?.flatMap { it.activePills }
            ?.firstOrNull()
            ?.rawText
        val tagdosFocus = firstActivePill ?: "Fix brief auto-open"

        val launchIntent = Intent(context, MainActivity::class.java).apply {
            action = "com.intellidream.daily.ACTION_OPEN_DASHBOARD"
            data = Uri.parse("daily://dashboard")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_TARGET_TAB, MainActivity.TAB_DASHBOARD)
        }

        val habitsWaterIntent = Intent(context, MainActivity::class.java).apply {
            action = "com.intellidream.daily.ACTION_OPEN_HABITS_WATER"
            data = Uri.parse("daily://habits/bubbles")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_TARGET_TAB, MainActivity.TAB_HABITS)
            putExtra(MainActivity.EXTRA_HABIT_SUBTAB, "water")
        }

        val habitsSmokesIntent = Intent(context, MainActivity::class.java).apply {
            action = "com.intellidream.daily.ACTION_OPEN_HABITS_SMOKES"
            data = Uri.parse("daily://habits/smokes")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_TARGET_TAB, MainActivity.TAB_HABITS)
            putExtra(MainActivity.EXTRA_HABIT_SUBTAB, "smokes")
        }

        val healthSleepIntent = Intent(context, MainActivity::class.java).apply {
            action = "com.intellidream.daily.ACTION_OPEN_HEALTH_SLEEP"
            data = Uri.parse("daily://health/sleep")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_TARGET_TAB, MainActivity.TAB_HEALTH)
            putExtra(MainActivity.EXTRA_HEALTH_SUBTAB, "sleep")
        }

        val healthStressIntent = Intent(context, MainActivity::class.java).apply {
            action = "com.intellidream.daily.ACTION_OPEN_HEALTH_STRESS"
            data = Uri.parse("daily://health/stress")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_TARGET_TAB, MainActivity.TAB_HEALTH)
            putExtra(MainActivity.EXTRA_HEALTH_SUBTAB, "stress")
        }

        val financesMoneyIntent = Intent(context, MainActivity::class.java).apply {
            action = "com.intellidream.daily.ACTION_OPEN_FINANCES_MONEY"
            data = Uri.parse("daily://finances/money")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_TARGET_TAB, MainActivity.TAB_FINANCES)
        }

        val tagdosIntent = Intent(context, MainActivity::class.java).apply {
            action = "com.intellidream.daily.ACTION_OPEN_TAGDOS"
            data = Uri.parse("daily://tagdos")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_TARGET_TAB, MainActivity.TAB_TAGDOS)
        }

        provideContent {
            val size = LocalSize.current
            GlanceTheme {
                Box(
                    modifier = GlanceModifier
                        .fillMaxSize()
                        .appWidgetBackground()
                        .background(ImageProvider(R.drawable.widget_background))
                        .cornerRadius(22.dp)
                        .clickable(actionStartActivity(launchIntent))
                ) {
                    when {
                        size.width >= 200.dp && size.height >= 215.dp -> LargeCombinedLayout(
                            waterMl = waterMl,
                            goalMl = goalMl,
                            waterPercent = waterPercent,
                            smokesCount = smokesCount,
                            smokesBase = smokesBase,
                            smokesRingColorInt = smokesRingColorInt,
                            sleepScore = sleepScore,
                            totalAsleep = totalAsleep,
                            sleepEff = sleepEff,
                            deepFormatted = deepFormatted,
                            remFormatted = remFormatted,
                            formattedNetWorth = formattedNetWorth,
                            formattedNetWorthEUR = formattedNetWorthEUR,
                            stressScore = stressScore,
                            stressLevel = stressLevel,
                            stressEmoji = stressEmoji,
                            stressColor = stressColor,
                            tagdosFocus = tagdosFocus,
                            sleepIntent = healthSleepIntent,
                            waterIntent = habitsWaterIntent,
                            smokesIntent = habitsSmokesIntent,
                            stressIntent = healthStressIntent,
                            moneyIntent = financesMoneyIntent,
                            tagdosIntent = tagdosIntent
                        )
                        size.width >= 200.dp -> MediumCombinedLayout(
                            waterMl = waterMl,
                            goalMl = goalMl,
                            waterPercent = waterPercent,
                            smokesCount = smokesCount,
                            smokesBase = smokesBase,
                            smokesRingColorInt = smokesRingColorInt,
                            sleepScore = sleepScore,
                            totalAsleep = totalAsleep,
                            formattedNetWorth = formattedNetWorth,
                            formattedNetWorthEUR = formattedNetWorthEUR,
                            stressScore = stressScore,
                            stressLevel = stressLevel,
                            stressEmoji = stressEmoji,
                            stressColor = stressColor,
                            tagdosFocus = tagdosFocus,
                            sleepIntent = healthSleepIntent,
                            waterIntent = habitsWaterIntent,
                            smokesIntent = habitsSmokesIntent,
                            stressIntent = healthStressIntent,
                            moneyIntent = financesMoneyIntent,
                            tagdosIntent = tagdosIntent
                        )
                        else -> SmallCombinedLayout(
                            waterMl = waterMl,
                            waterPercent = waterPercent,
                            smokesCount = smokesCount,
                            smokesBase = smokesBase,
                            smokesRingColorInt = smokesRingColorInt,
                            sleepScore = sleepScore,
                            totalAsleep = totalAsleep,
                            formattedNetWorthEUR = formattedNetWorthEUR,
                            stressScore = stressScore,
                            stressLevel = stressLevel,
                            stressEmoji = stressEmoji,
                            stressColor = stressColor,
                            tagdosFocus = tagdosFocus,
                            sleepIntent = healthSleepIntent,
                            waterIntent = habitsWaterIntent,
                            smokesIntent = habitsSmokesIntent,
                            stressIntent = healthStressIntent,
                            moneyIntent = financesMoneyIntent,
                            tagdosIntent = tagdosIntent
                        )
                    }
                }
            }
        }
    }

    // =========================================================================
    // MARK: - 1. SMALL LAYOUT (systemSmall: 2x2)
    // =========================================================================
    @androidx.compose.runtime.Composable
    private fun SmallCombinedLayout(
        waterMl: Double,
        waterPercent: Double,
        smokesCount: Int,
        smokesBase: Int,
        smokesRingColorInt: Int,
        sleepScore: Int,
        totalAsleep: String,
        formattedNetWorthEUR: String,
        stressScore: Int,
        stressLevel: String,
        stressEmoji: String,
        stressColor: Color,
        tagdosFocus: String,
        sleepIntent: Intent,
        waterIntent: Intent,
        smokesIntent: Intent,
        stressIntent: Intent,
        moneyIntent: Intent,
        tagdosIntent: Intent
    ) {
        val sleepGauge = WidgetVisualGraphics.createMiniMetricGaugeBitmap(
            sizePx = 90,
            progress = sleepScore / 100f,
            colorInt = android.graphics.Color.parseColor("#00E5FF"),
            strokeWidthPx = 9f
        )
        val sparklesIcon = WidgetVisualGraphics.createVectorIconBitmap(WidgetIconType.SPARKLES, 20, android.graphics.Color.parseColor("#00E5FF"))
        val dropIcon = WidgetVisualGraphics.createVectorIconBitmap(WidgetIconType.DROP, 20, android.graphics.Color.parseColor("#00E5FF"))
        val flameIcon = WidgetVisualGraphics.createVectorIconBitmap(WidgetIconType.FLAME, 20, smokesRingColorInt)
        val cardIcon = WidgetVisualGraphics.createVectorIconBitmap(WidgetIconType.CREDIT_CARD, 20, android.graphics.Color.parseColor("#00E676"))

        Column(
            modifier = GlanceModifier.fillMaxSize().padding(start = 12.dp, end = 12.dp, top = 10.dp, bottom = 12.dp)
        ) {
            // Header Row: Daily + Status Pill
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Image(
                        provider = ImageProvider(sparklesIcon),
                        contentDescription = null,
                        modifier = GlanceModifier.size(11.dp)
                    )
                    Spacer(modifier = GlanceModifier.width(4.dp))
                    Text(
                        text = "Daily",
                        style = TextStyle(
                            color = ColorProvider(Color.White),
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                }

                Spacer(modifier = GlanceModifier.defaultWeight())

                // Stress/Status pill
                Box(
                    modifier = GlanceModifier
                        .background(stressColor.copy(alpha = 0.18f))
                        .cornerRadius(10.dp)
                        .padding(horizontal = 5.dp, vertical = 2.dp)
                        .clickable(actionStartActivity(stressIntent))
                ) {
                    Text(
                        text = "$stressEmoji $stressLevel",
                        style = TextStyle(
                            color = ColorProvider(stressColor),
                            fontSize = 8.5.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                }
            }

            Spacer(modifier = GlanceModifier.height(4.dp))

            // Sleep Hero Row: 36dp Ring + Sleep details
            Row(
                modifier = GlanceModifier
                    .fillMaxWidth()
                    .clickable(actionStartActivity(sleepIntent)),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(
                    modifier = GlanceModifier.size(36.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Image(
                        provider = ImageProvider(sleepGauge),
                        contentDescription = null,
                        modifier = GlanceModifier.fillMaxSize()
                    )
                    Text(
                        text = "$sleepScore",
                        style = TextStyle(
                            color = ColorProvider(Color.White),
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                }

                Spacer(modifier = GlanceModifier.width(8.dp))

                Column {
                    Text(
                        text = totalAsleep,
                        style = TextStyle(
                            color = ColorProvider(Color.White),
                            fontSize = 12.5.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                    Text(
                        text = "Sleep Quality",
                        style = TextStyle(
                            color = ColorProvider(Color(0xFF00E5FF)),
                            fontSize = 9.sp,
                            fontWeight = FontWeight.Medium
                        )
                    )
                }
            }

            Spacer(modifier = GlanceModifier.height(4.dp))

            // Tagdos Focus Chip
            Box(
                modifier = GlanceModifier
                    .fillMaxWidth()
                    .background(Color(0x14FFFFFF))
                    .cornerRadius(7.dp)
                    .padding(horizontal = 6.dp, vertical = 3.dp)
                    .clickable(actionStartActivity(tagdosIntent))
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        modifier = GlanceModifier
                            .background(Color(0x33A855F7))
                            .cornerRadius(4.dp)
                            .padding(horizontal = 4.dp, vertical = 1.dp)
                    ) {
                        Text(
                            text = "Focus",
                            style = TextStyle(
                                color = ColorProvider(Color(0xFFA855F7)),
                                fontSize = 8.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                    }
                    Spacer(modifier = GlanceModifier.width(4.dp))
                    Text(
                        text = tagdosFocus,
                        style = TextStyle(
                            color = ColorProvider(Color(0xE6FFFFFF)),
                            fontSize = 9.5.sp,
                            fontWeight = FontWeight.Medium
                        ),
                        maxLines = 1
                    )
                }
            }

            Spacer(modifier = GlanceModifier.defaultWeight())

            // Bottom 3 Quick Status Capsules (Water, Smokes, Money EUR)
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Water Capsule
                Box(
                    modifier = GlanceModifier
                        .defaultWeight()
                        .height(24.dp)
                        .background(Color(0x14FFFFFF))
                        .cornerRadius(12.dp)
                        .padding(horizontal = 4.dp)
                        .clickable(actionStartActivity(waterIntent)),
                    contentAlignment = Alignment.Center
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Image(provider = ImageProvider(dropIcon), contentDescription = null, modifier = GlanceModifier.size(8.dp))
                        Spacer(modifier = GlanceModifier.width(2.5.dp))
                        Text(
                            text = "${waterMl.toInt()} ml",
                            style = TextStyle(color = ColorProvider(Color.White), fontSize = 9.sp, fontWeight = FontWeight.Bold)
                        )
                    }
                }

                Spacer(modifier = GlanceModifier.width(4.dp))

                // Smokes Capsule
                Box(
                    modifier = GlanceModifier
                        .defaultWeight()
                        .height(24.dp)
                        .background(Color(0x14FFFFFF))
                        .cornerRadius(12.dp)
                        .padding(horizontal = 4.dp)
                        .clickable(actionStartActivity(smokesIntent)),
                    contentAlignment = Alignment.Center
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Image(provider = ImageProvider(flameIcon), contentDescription = null, modifier = GlanceModifier.size(8.dp))
                        Spacer(modifier = GlanceModifier.width(2.5.dp))
                        Text(
                            text = "$smokesCount",
                            style = TextStyle(color = ColorProvider(Color.White), fontSize = 9.sp, fontWeight = FontWeight.Bold)
                        )
                    }
                }

                Spacer(modifier = GlanceModifier.width(4.dp))

                // Money Capsule
                Box(
                    modifier = GlanceModifier
                        .defaultWeight()
                        .height(24.dp)
                        .background(Color(0x14FFFFFF))
                        .cornerRadius(12.dp)
                        .padding(horizontal = 4.dp)
                        .clickable(actionStartActivity(moneyIntent)),
                    contentAlignment = Alignment.Center
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Image(provider = ImageProvider(cardIcon), contentDescription = null, modifier = GlanceModifier.size(8.dp))
                        Spacer(modifier = GlanceModifier.width(2.5.dp))
                        Text(
                            text = formattedNetWorthEUR,
                            style = TextStyle(color = ColorProvider(Color.White), fontSize = 9.sp, fontWeight = FontWeight.Bold)
                        )
                    }
                }
            }
        }
    }

    // =========================================================================
    // MARK: - 2. MEDIUM LAYOUT (systemMedium: 4x2)
    // =========================================================================
    @androidx.compose.runtime.Composable
    private fun MediumCombinedLayout(
        waterMl: Double,
        goalMl: Double,
        waterPercent: Double,
        smokesCount: Int,
        smokesBase: Int,
        smokesRingColorInt: Int,
        sleepScore: Int,
        totalAsleep: String,
        formattedNetWorth: String,
        formattedNetWorthEUR: String,
        stressScore: Int,
        stressLevel: String,
        stressEmoji: String,
        stressColor: Color,
        tagdosFocus: String,
        sleepIntent: Intent,
        waterIntent: Intent,
        smokesIntent: Intent,
        stressIntent: Intent,
        moneyIntent: Intent,
        tagdosIntent: Intent
    ) {
        val sleepGauge = WidgetVisualGraphics.createMiniMetricGaugeBitmap(
            sizePx = 130,
            progress = sleepScore / 100f,
            colorInt = android.graphics.Color.parseColor("#00E5FF"),
            strokeWidthPx = 12f
        )
        val dropIcon = WidgetVisualGraphics.createVectorIconBitmap(WidgetIconType.DROP, 24, android.graphics.Color.parseColor("#3B82F6"))
        val flameIcon = WidgetVisualGraphics.createVectorIconBitmap(WidgetIconType.FLAME, 24, smokesRingColorInt)

        Row(
            modifier = GlanceModifier.fillMaxSize().padding(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Left Hero Column (width 104.dp): Sleep Arc + Net Worth + Stress
            Column(
                modifier = GlanceModifier.width(104.dp).fillMaxHeight(),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                // Sleep Arc
                Box(
                    modifier = GlanceModifier.size(52.dp).clickable(actionStartActivity(sleepIntent)),
                    contentAlignment = Alignment.Center
                ) {
                    Image(
                        provider = ImageProvider(sleepGauge),
                        contentDescription = null,
                        modifier = GlanceModifier.fillMaxSize()
                    )
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(
                            text = "$sleepScore",
                            style = TextStyle(color = ColorProvider(Color.White), fontSize = 15.sp, fontWeight = FontWeight.Bold)
                        )
                        Text(
                            text = totalAsleep,
                            style = TextStyle(color = ColorProvider(Color(0xFF00FFB2)), fontSize = 8.sp, fontWeight = FontWeight.Bold)
                        )
                    }
                }

                Spacer(modifier = GlanceModifier.height(3.dp))

                // Net Worth Pill
                Box(
                    modifier = GlanceModifier
                        .background(Color(0x14FFFFFF))
                        .cornerRadius(12.dp)
                        .padding(horizontal = 7.dp, vertical = 2.5.dp)
                        .clickable(actionStartActivity(moneyIntent))
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(
                            text = formattedNetWorth,
                            style = TextStyle(color = ColorProvider(Color(0xFF00E676)), fontSize = 10.5.sp, fontWeight = FontWeight.Bold)
                        )
                        Text(
                            text = formattedNetWorthEUR,
                            style = TextStyle(color = ColorProvider(Color(0x80FFFFFF)), fontSize = 8.sp, fontWeight = FontWeight.Medium)
                        )
                    }
                }

                Spacer(modifier = GlanceModifier.height(3.dp))

                // Stress Pill with Mascot
                Box(
                    modifier = GlanceModifier
                        .background(stressColor.copy(alpha = 0.15f))
                        .cornerRadius(12.dp)
                        .padding(horizontal = 6.dp, vertical = 2.dp)
                        .clickable(actionStartActivity(stressIntent))
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(text = stressEmoji, style = TextStyle(fontSize = 9.sp))
                        Spacer(modifier = GlanceModifier.width(3.dp))
                        Text(
                            text = "$stressScore",
                            style = TextStyle(color = ColorProvider(stressColor), fontSize = 10.sp, fontWeight = FontWeight.Bold)
                        )
                        Spacer(modifier = GlanceModifier.width(3.dp))
                        Text(
                            text = stressLevel,
                            style = TextStyle(color = ColorProvider(stressColor), fontSize = 8.sp, fontWeight = FontWeight.Bold)
                        )
                    }
                }
            }

            Spacer(modifier = GlanceModifier.width(12.dp))

            // Right Column: 3 Metric Cards (Water, Smokes, TagDoS)
            Column(
                modifier = GlanceModifier.defaultWeight().fillMaxHeight()
            ) {
                // 1. Water Card with Progress Bar
                Box(
                    modifier = GlanceModifier
                        .fillMaxWidth()
                        .background(Color(0x14FFFFFF))
                        .cornerRadius(11.dp)
                        .padding(horizontal = 10.dp, vertical = 6.dp)
                        .clickable(actionStartActivity(waterIntent))
                ) {
                    Column {
                        Row(
                            modifier = GlanceModifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Image(
                                provider = ImageProvider(dropIcon),
                                contentDescription = null,
                                modifier = GlanceModifier.size(10.dp)
                            )
                            Spacer(modifier = GlanceModifier.width(4.dp))
                            Text(
                                text = "Water",
                                style = TextStyle(color = ColorProvider(Color.White), fontSize = 11.sp, fontWeight = FontWeight.Bold)
                            )
                            Spacer(modifier = GlanceModifier.defaultWeight())
                            Text(
                                text = "${waterMl.toInt()} / ${goalMl.toInt()} ml",
                                style = TextStyle(color = ColorProvider(Color(0xD9FFFFFF)), fontSize = 10.sp, fontWeight = FontWeight.Bold)
                            )
                        }
                        Spacer(modifier = GlanceModifier.height(4.dp))
                        // Progress line
                        val waterBarBitmap = WidgetVisualGraphics.createLinearProgressBarBitmap(
                            widthPx = 250,
                            heightPx = 10,
                            progress = waterPercent.toFloat(),
                            activeColorInt = android.graphics.Color.parseColor("#00E5FF")
                        )
                        Image(
                            provider = ImageProvider(waterBarBitmap),
                            contentDescription = null,
                            modifier = GlanceModifier.fillMaxWidth().height(5.dp)
                        )
                    }
                }

                Spacer(modifier = GlanceModifier.height(5.dp))

                // 2. Smokes Counter Card
                Box(
                    modifier = GlanceModifier
                        .fillMaxWidth()
                        .background(Color(0x14FFFFFF))
                        .cornerRadius(11.dp)
                        .padding(horizontal = 10.dp, vertical = 6.dp)
                        .clickable(actionStartActivity(smokesIntent))
                ) {
                    Row(
                        modifier = GlanceModifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Image(
                            provider = ImageProvider(flameIcon),
                            contentDescription = null,
                            modifier = GlanceModifier.size(11.dp)
                        )
                        Spacer(modifier = GlanceModifier.width(5.dp))
                        Text(
                            text = "Smokes",
                            style = TextStyle(color = ColorProvider(Color.White), fontSize = 11.sp, fontWeight = FontWeight.Bold)
                        )
                        Spacer(modifier = GlanceModifier.defaultWeight())
                        Text(
                            text = "$smokesCount / $smokesBase cigs",
                            style = TextStyle(color = ColorProvider(Color(smokesRingColorInt)), fontSize = 11.sp, fontWeight = FontWeight.Bold)
                        )
                    }
                }

                Spacer(modifier = GlanceModifier.height(5.dp))

                // 3. TagDoS Active Pill
                Box(
                    modifier = GlanceModifier
                        .fillMaxWidth()
                        .background(Color(0x14FFFFFF))
                        .cornerRadius(11.dp)
                        .padding(horizontal = 10.dp, vertical = 6.dp)
                        .clickable(actionStartActivity(tagdosIntent))
                ) {
                    Row(
                        modifier = GlanceModifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "S1",
                            style = TextStyle(color = ColorProvider(Color(0xFFA855F7)), fontSize = 9.5.sp, fontWeight = FontWeight.Bold)
                        )
                        Spacer(modifier = GlanceModifier.width(6.dp))
                        Text(
                            text = tagdosFocus,
                            style = TextStyle(color = ColorProvider(Color(0xE6FFFFFF)), fontSize = 10.5.sp, fontWeight = FontWeight.Medium)
                        )
                    }
                }
            }
        }
    }

    // =========================================================================
    // MARK: - 3. LARGE LAYOUT (systemLarge: 4x4)
    // =========================================================================
    @androidx.compose.runtime.Composable
    private fun LargeCombinedLayout(
        waterMl: Double,
        goalMl: Double,
        waterPercent: Double,
        smokesCount: Int,
        smokesBase: Int,
        smokesRingColorInt: Int,
        sleepScore: Int,
        totalAsleep: String,
        sleepEff: Int,
        deepFormatted: String,
        remFormatted: String,
        formattedNetWorth: String,
        formattedNetWorthEUR: String,
        stressScore: Int,
        stressLevel: String,
        stressEmoji: String,
        stressColor: Color,
        tagdosFocus: String,
        sleepIntent: Intent,
        waterIntent: Intent,
        smokesIntent: Intent,
        stressIntent: Intent,
        moneyIntent: Intent,
        tagdosIntent: Intent
    ) {
        val sleepGauge = WidgetVisualGraphics.createMiniMetricGaugeBitmap(
            sizePx = 130,
            progress = sleepScore / 100f,
            colorInt = android.graphics.Color.parseColor("#00E5FF"),
            strokeWidthPx = 12f
        )
        val hypnogramBitmap = WidgetVisualGraphics.createSleepHypnogramBarBitmap(
            widthPx = 500,
            heightPx = 14,
            deepSec = 5400.0,
            remSec = 6120.0,
            lightSec = 16200.0,
            awakeSec = 2080.0
        )
        val cardIcon = WidgetVisualGraphics.createVectorIconBitmap(WidgetIconType.CREDIT_CARD, 24, android.graphics.Color.parseColor("#00E676"))
        val dropIcon = WidgetVisualGraphics.createVectorIconBitmap(WidgetIconType.DROP, 24, android.graphics.Color.parseColor("#3B82F6"))
        val flameIcon = WidgetVisualGraphics.createVectorIconBitmap(WidgetIconType.FLAME, 24, smokesRingColorInt)

        val dateStr = SimpleDateFormat("EEE, d MMM", Locale.getDefault()).format(Date())

        Column(
            modifier = GlanceModifier.fillMaxSize().padding(14.dp)
        ) {
            // Header Bar: Title + Date + Net Worth
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(
                        text = "Daily Executive",
                        style = TextStyle(color = ColorProvider(Color.White), fontSize = 14.sp, fontWeight = FontWeight.Bold)
                    )
                    Text(
                        text = dateStr,
                        style = TextStyle(color = ColorProvider(Color(0x80FFFFFF)), fontSize = 10.5.sp, fontWeight = FontWeight.Medium)
                    )
                }

                Spacer(modifier = GlanceModifier.defaultWeight())

                Row(
                    modifier = GlanceModifier.clickable(actionStartActivity(moneyIntent)),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Image(
                        provider = ImageProvider(cardIcon),
                        contentDescription = null,
                        modifier = GlanceModifier.size(11.dp)
                    )
                    Spacer(modifier = GlanceModifier.width(6.dp))
                    Column(horizontalAlignment = Alignment.End) {
                        Text(
                            text = formattedNetWorth,
                            style = TextStyle(color = ColorProvider(Color(0xFF00E676)), fontSize = 13.sp, fontWeight = FontWeight.Bold)
                        )
                        Text(
                            text = formattedNetWorthEUR,
                            style = TextStyle(color = ColorProvider(Color(0x80FFFFFF)), fontSize = 9.sp, fontWeight = FontWeight.Medium)
                        )
                    }
                }
            }

            Spacer(modifier = GlanceModifier.height(10.dp))

            // Sleep Studio Card
            Box(
                modifier = GlanceModifier
                    .fillMaxWidth()
                    .background(Color(0x14FFFFFF))
                    .cornerRadius(14.dp)
                    .padding(11.dp)
                    .clickable(actionStartActivity(sleepIntent))
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        modifier = GlanceModifier.size(52.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Image(
                            provider = ImageProvider(sleepGauge),
                            contentDescription = null,
                            modifier = GlanceModifier.fillMaxSize()
                        )
                        Text(
                            text = "$sleepScore",
                            style = TextStyle(color = ColorProvider(Color.White), fontSize = 15.sp, fontWeight = FontWeight.Bold)
                        )
                    }

                    Spacer(modifier = GlanceModifier.width(14.dp))

                    Column(modifier = GlanceModifier.defaultWeight()) {
                        Row(modifier = GlanceModifier.fillMaxWidth()) {
                            Text(
                                text = "Sleep Studio",
                                style = TextStyle(color = ColorProvider(Color.White), fontSize = 12.sp, fontWeight = FontWeight.Bold)
                            )
                            Spacer(modifier = GlanceModifier.defaultWeight())
                            Text(
                                text = totalAsleep,
                                style = TextStyle(color = ColorProvider(Color(0xFF00E5FF)), fontSize = 12.sp, fontWeight = FontWeight.Bold)
                            )
                        }

                        Spacer(modifier = GlanceModifier.height(3.dp))

                        Image(
                            provider = ImageProvider(hypnogramBitmap),
                            contentDescription = null,
                            modifier = GlanceModifier.fillMaxWidth().height(5.dp)
                        )

                        Spacer(modifier = GlanceModifier.height(3.dp))

                        Row(modifier = GlanceModifier.fillMaxWidth()) {
                            Text(text = "Deep $deepFormatted", style = TextStyle(color = ColorProvider(Color(0xFF6366F1)), fontSize = 9.sp))
                            Spacer(modifier = GlanceModifier.width(6.dp))
                            Text(text = "REM $remFormatted", style = TextStyle(color = ColorProvider(Color(0xFF8B5CF6)), fontSize = 9.sp))
                            Spacer(modifier = GlanceModifier.defaultWeight())
                            Text(text = "Eff $sleepEff%", style = TextStyle(color = ColorProvider(Color(0xFF00FFB2)), fontSize = 9.sp, fontWeight = FontWeight.Bold))
                        }
                    }
                }
            }

            Spacer(modifier = GlanceModifier.height(10.dp))

            // Habits Row: Water, Smokes, Stress
            Row(modifier = GlanceModifier.fillMaxWidth()) {
                // Water
                HabitTile("Water", "${waterMl.toInt()} ml", "${(waterPercent * 100).toInt()}%", dropIcon, Color(0xFF3B82F6), GlanceModifier.defaultWeight().clickable(actionStartActivity(waterIntent)))
                Spacer(modifier = GlanceModifier.width(8.dp))
                // Smokes
                HabitTile("Smokes", "$smokesCount", "Limit $smokesBase", flameIcon, Color(smokesRingColorInt), GlanceModifier.defaultWeight().clickable(actionStartActivity(smokesIntent)))
                Spacer(modifier = GlanceModifier.width(8.dp))
                // Stress
                Box(
                    modifier = GlanceModifier
                        .defaultWeight()
                        .background(Color(0x14FFFFFF))
                        .cornerRadius(12.dp)
                        .padding(9.dp)
                        .clickable(actionStartActivity(stressIntent))
                ) {
                    Column {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(text = stressEmoji, style = TextStyle(fontSize = 11.sp))
                            Spacer(modifier = GlanceModifier.width(4.dp))
                            Text(text = "Stress", style = TextStyle(color = ColorProvider(Color.White), fontSize = 10.5.sp, fontWeight = FontWeight.Bold))
                            Spacer(modifier = GlanceModifier.defaultWeight())
                            Text(text = "$stressScore", style = TextStyle(color = ColorProvider(stressColor), fontSize = 11.sp, fontWeight = FontWeight.Bold))
                        }
                        Spacer(modifier = GlanceModifier.height(4.dp))
                        Text(text = stressLevel, style = TextStyle(color = ColorProvider(stressColor), fontSize = 8.5.sp, fontWeight = FontWeight.Bold))
                    }
                }
            }

            Spacer(modifier = GlanceModifier.defaultWeight())

            // TagDoS Pipeline Card
            Box(
                modifier = GlanceModifier
                    .fillMaxWidth()
                    .background(Color(0x14FFFFFF))
                    .cornerRadius(13.dp)
                    .padding(11.dp)
                    .clickable(actionStartActivity(tagdosIntent))
            ) {
                Column {
                    Row(modifier = GlanceModifier.fillMaxWidth()) {
                        Text(
                            text = "TAGDOS PIPELINE",
                            style = TextStyle(color = ColorProvider(Color(0xFFA855F7)), fontSize = 10.sp, fontWeight = FontWeight.Bold)
                        )
                        Spacer(modifier = GlanceModifier.defaultWeight())
                        Text(
                            text = "2 streams active",
                            style = TextStyle(color = ColorProvider(Color(0x80FFFFFF)), fontSize = 9.5.sp, fontWeight = FontWeight.Medium)
                        )
                    }
                    Spacer(modifier = GlanceModifier.height(4.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(text = "S1", style = TextStyle(color = ColorProvider(Color(0xFFA855F7)), fontSize = 9.sp, fontWeight = FontWeight.Bold))
                        Spacer(modifier = GlanceModifier.width(6.dp))
                        Text(text = tagdosFocus, style = TextStyle(color = ColorProvider(Color.White), fontSize = 11.sp, fontWeight = FontWeight.Medium))
                    }
                }
            }
        }
    }

    // =========================================================================
    // MARK: - Components
    // =========================================================================
    @androidx.compose.runtime.Composable
    private fun MiniProgressRing(
        gaugeBitmap: android.graphics.Bitmap,
        valueText: String,
        labelText: String,
        iconBitmap: android.graphics.Bitmap,
        modifier: GlanceModifier
    ) {
        Column(
            modifier = modifier,
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Box(
                modifier = GlanceModifier.size(42.dp),
                contentAlignment = Alignment.Center
            ) {
                Image(
                    provider = ImageProvider(gaugeBitmap),
                    contentDescription = null,
                    modifier = GlanceModifier.fillMaxSize()
                )
                Text(
                    text = valueText,
                    style = TextStyle(color = ColorProvider(Color.White), fontSize = 12.sp, fontWeight = FontWeight.Bold)
                )
            }
            Spacer(modifier = GlanceModifier.height(2.5.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Image(
                    provider = ImageProvider(iconBitmap),
                    contentDescription = null,
                    modifier = GlanceModifier.size(8.5.dp)
                )
                Spacer(modifier = GlanceModifier.width(2.5.dp))
                Text(
                    text = labelText,
                    style = TextStyle(color = ColorProvider(Color(0xBFFFFFFF)), fontSize = 8.5.sp, fontWeight = FontWeight.Medium)
                )
            }
        }
    }

    @androidx.compose.runtime.Composable
    private fun HabitTile(
        title: String,
        value: String,
        sub: String,
        iconBitmap: android.graphics.Bitmap,
        tintColor: Color,
        modifier: GlanceModifier
    ) {
        Box(
            modifier = modifier
                .background(Color(0x14FFFFFF))
                .cornerRadius(12.dp)
                .padding(9.dp)
        ) {
            Column {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Image(
                        provider = ImageProvider(iconBitmap),
                        contentDescription = null,
                        modifier = GlanceModifier.size(10.dp)
                    )
                    Spacer(modifier = GlanceModifier.width(4.dp))
                    Text(
                        text = title,
                        style = TextStyle(color = ColorProvider(Color.White), fontSize = 10.5.sp, fontWeight = FontWeight.Bold)
                    )
                    Spacer(modifier = GlanceModifier.defaultWeight())
                    Text(
                        text = value,
                        style = TextStyle(color = ColorProvider(tintColor), fontSize = 11.sp, fontWeight = FontWeight.Bold)
                    )
                }
                Spacer(modifier = GlanceModifier.height(4.dp))
                Text(
                    text = sub,
                    style = TextStyle(color = ColorProvider(Color(0x80FFFFFF)), fontSize = 8.5.sp, fontWeight = FontWeight.Medium)
                )
            }
        }
    }
}
