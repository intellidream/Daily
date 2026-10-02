package com.intellidream.daily.glance

import android.content.Context
import android.content.Intent
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.action.actionStartActivity
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
import com.intellidream.daily.model.ParsedSmartLedger
import com.intellidream.daily.model.SleepSession
import com.intellidream.daily.model.StressAnalysisResult
import java.util.Locale
import kotlin.math.max

class DailyCombinedGlanceWidget : GlanceAppWidget() {

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val app = runCatching { DailyApp.instance }.getOrNull()

        val sleepSession = app?.healthRepository?.primarySleepSession?.value
        val stressAnalysis = app?.healthRepository?.stressAnalysis?.value
        val waterTotal = app?.habitsRepository?.waterTotalToday?.value ?: 0.0
        val waterGoal = app?.habitsRepository?.waterGoal?.value ?: 2000.0
        val smokesTotal = app?.habitsRepository?.smokesTotalToday?.value ?: 0
        val smokesBase = app?.habitsRepository?.smokesSettings?.value?.baselineDailyCount ?: 15
        val streams = app?.tagdosRepository?.streams?.value ?: emptyList()
        val parsedLedger = app?.smartLedgerRepository?.parsedLedger?.value

        provideContent {
            CombinedWidgetContent(
                context = context,
                sleep = sleepSession,
                stress = stressAnalysis,
                waterTotal = waterTotal,
                waterGoal = waterGoal,
                smokesTotal = smokesTotal,
                smokesBase = smokesBase,
                drivingTask = streams.firstOrNull()?.drivingPill?.rawText ?: "All clear",
                ledger = parsedLedger
            )
        }
    }

    @Composable
    private fun CombinedWidgetContent(
        context: Context,
        sleep: SleepSession?,
        stress: StressAnalysisResult?,
        waterTotal: Double,
        waterGoal: Double,
        smokesTotal: Int,
        smokesBase: Int,
        drivingTask: String,
        ledger: ParsedSmartLedger?
    ) {
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_TARGET_TAB, MainActivity.TAB_DASHBOARD)
        }

        val sleepScore = sleep?.takeIf { it.sleepScore > 0 }?.sleepScore ?: 0
        val sleepFormatted = sleep?.totalAsleepFormatted ?: "--"
        val hasSleep = sleepScore > 0

        val stressScore = stress?.currentScore
        val stressLevel = stress?.currentLevel?.displayName ?: "Calm"
        val monkeyEmoji = stress?.monkeyMood?.emoji ?: "🐵"

        val netWorth = ledger?.netWorth ?: 0.0
        val netWorthEUR = ledger?.formattedNetWorthEUR ?: "~0 €"

        val accentCyan = Color(0xFF00E5FF)
        val accentMint = Color(0xFF00FFB2)
        val accentIndigo = Color(0xFF6366F1)
        val accentGreen = Color(0xFF00E676)
        val accentPurple = Color(0xFFA855F7)
        val textMuted = Color(0xFF8E9BAE)
        val cardBg = Color.White.copy(alpha = 0.06f)

        val sleepProgress = if (hasSleep) (sleepScore / 100f).coerceIn(0.05f, 1f) else 0.05f
        val sleepArcBitmap = WidgetVisualGraphics.createMiniMetricGaugeBitmap(
            sizePx = 140,
            progress = sleepProgress,
            colorInt = android.graphics.Color.parseColor("#00E5FF"),
            strokeWidthPx = 12f
        )

        Box(
            modifier = GlanceModifier
                .fillMaxSize()
                .cornerRadius(24.dp)
                .background(Color(0xFF07101E))
                .padding(12.dp)
                .clickable(actionStartActivity(launchIntent))
        ) {
            Row(
                modifier = GlanceModifier.fillMaxSize(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // LEFT HERO COLUMN: Sleep Arc + Net Worth Pill + Stress Pill (Matches iOS 1:1)
                Column(
                    modifier = GlanceModifier.width(106.dp).fillMaxHeight(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // Sleep Arc Hero
                    Box(
                        modifier = GlanceModifier.size(54.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Image(
                            provider = ImageProvider(sleepArcBitmap),
                            contentDescription = "Sleep Progress",
                            modifier = GlanceModifier.size(54.dp)
                        )
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(
                                text = if (hasSleep) "$sleepScore" else "--",
                                style = TextStyle(
                                    color = ColorProvider(Color.White),
                                    fontSize = 13.sp,
                                    fontWeight = FontWeight.Bold
                                )
                            )
                            Text(
                                text = sleepFormatted,
                                style = TextStyle(
                                    color = ColorProvider(accentMint),
                                    fontSize = 7.5.sp,
                                    fontWeight = FontWeight.Bold
                                )
                            )
                        }
                    }

                    Spacer(modifier = GlanceModifier.height(3.dp))

                    // Net Worth Badge
                    Box(
                        modifier = GlanceModifier
                            .cornerRadius(8.dp)
                            .background(cardBg)
                            .padding(horizontal = 6.dp, vertical = 2.dp)
                    ) {
                        Text(
                            text = netWorthEUR,
                            style = TextStyle(
                                color = ColorProvider(accentGreen),
                                fontSize = 9.sp,
                                fontWeight = FontWeight.Bold
                            ),
                            maxLines = 1
                        )
                    }

                    Spacer(modifier = GlanceModifier.height(3.dp))

                    // Stress Pill with Monkey Mascot
                    Box(
                        modifier = GlanceModifier
                            .cornerRadius(8.dp)
                            .background(cardBg)
                            .padding(horizontal = 5.dp, vertical = 2.dp)
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(text = monkeyEmoji, style = TextStyle(fontSize = 8.5.sp))
                            Spacer(modifier = GlanceModifier.width(2.dp))
                            Text(
                                text = if (stressScore != null) "$stressScore $stressLevel" else "Calm",
                                style = TextStyle(
                                    color = ColorProvider(Color(0xFFFFB703)),
                                    fontSize = 7.5.sp,
                                    fontWeight = FontWeight.Bold
                                )
                            )
                        }
                    }
                }

                Spacer(modifier = GlanceModifier.width(8.dp))

                // RIGHT COLUMN: 3 Metric Cards (Water, Smokes, TagDoS)
                Column(
                    modifier = GlanceModifier.defaultWeight().fillMaxHeight(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // Card 1: Water
                    Row(
                        modifier = GlanceModifier
                            .fillMaxWidth()
                            .cornerRadius(8.dp)
                            .background(cardBg)
                            .padding(horizontal = 8.dp, vertical = 5.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(text = "💧", style = TextStyle(fontSize = 10.sp))
                        Spacer(modifier = GlanceModifier.width(4.dp))
                        Text(
                            text = "Water",
                            style = TextStyle(
                                color = ColorProvider(Color.White),
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                        Spacer(modifier = GlanceModifier.defaultWeight())
                        Text(
                            text = "${waterTotal.toInt()} / ${waterGoal.toInt()} ml",
                            style = TextStyle(
                                color = ColorProvider(accentCyan),
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                    }

                    Spacer(modifier = GlanceModifier.height(4.dp))

                    // Card 2: Smokes
                    Row(
                        modifier = GlanceModifier
                            .fillMaxWidth()
                            .cornerRadius(8.dp)
                            .background(cardBg)
                            .padding(horizontal = 8.dp, vertical = 5.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(text = "🔥", style = TextStyle(fontSize = 10.sp))
                        Spacer(modifier = GlanceModifier.width(4.dp))
                        Text(
                            text = "Smokes",
                            style = TextStyle(
                                color = ColorProvider(Color.White),
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                        Spacer(modifier = GlanceModifier.defaultWeight())
                        Text(
                            text = "$smokesTotal / $smokesBase",
                            style = TextStyle(
                                color = ColorProvider(if (smokesTotal <= smokesBase) accentGreen else Color(0xFFEF4444)),
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                    }

                    Spacer(modifier = GlanceModifier.height(4.dp))

                    // Card 3: TagDoS Focus
                    Row(
                        modifier = GlanceModifier
                            .fillMaxWidth()
                            .cornerRadius(8.dp)
                            .background(cardBg)
                            .padding(horizontal = 8.dp, vertical = 5.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Box(
                            modifier = GlanceModifier
                                .cornerRadius(4.dp)
                                .background(accentPurple.copy(alpha = 0.25f))
                                .padding(horizontal = 3.dp, vertical = 1.dp)
                        ) {
                            Text(
                                text = "S1",
                                style = TextStyle(
                                    color = ColorProvider(accentPurple),
                                    fontSize = 7.5.sp,
                                    fontWeight = FontWeight.Bold
                                )
                            )
                        }
                        Spacer(modifier = GlanceModifier.width(4.dp))
                        Text(
                            text = drivingTask,
                            style = TextStyle(
                                color = ColorProvider(Color(0xFFE2E8F0)),
                                fontSize = 9.5.sp,
                                fontWeight = FontWeight.Medium
                            ),
                            maxLines = 1
                        )
                    }
                }
            }
        }
    }
}

class DailyCombinedGlanceReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = DailyCombinedGlanceWidget()
}
