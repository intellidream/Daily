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
import com.intellidream.daily.model.StressAnalysisResult
import com.intellidream.daily.model.StressLevel

class DailyStressGlanceWidget : GlanceAppWidget() {

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val app = runCatching { DailyApp.instance }.getOrNull()

        val analysis = app?.healthRepository?.stressAnalysis?.value
        val level = app?.healthRepository?.currentStressLevel?.value

        provideContent {
            StressWidgetContent(
                context = context,
                analysis = analysis,
                fallbackLevel = level
            )
        }
    }

    @Composable
    private fun StressWidgetContent(
        context: Context,
        analysis: StressAnalysisResult?,
        fallbackLevel: StressLevel?
    ) {
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_TARGET_TAB, MainActivity.TAB_HEALTH)
            putExtra(MainActivity.EXTRA_HEALTH_SUBTAB, "stress")
        }

        val hasData = analysis != null
        val score = analysis?.currentScore ?: 0
        val level = analysis?.currentLevel ?: fallbackLevel ?: StressLevel.CALM
        val monkeyMood = analysis?.monkeyMood
        val monkeyEmoji = monkeyMood?.emoji ?: "🐵"
        val monkeyName = monkeyMood?.displayName ?: "Stress Studio"
        val adviceQuote = analysis?.adviceQuote ?: "Sync biometrics to measure stress and HRV balance"
        val parasympathetic = analysis?.parasympatheticPercent ?: 60
        val sympathetic = analysis?.sympatheticPercent ?: 40
        val hrv = analysis?.currentHrvMs
        val bpm = analysis?.restingHeartRateBpm

        val levelColorInt = runCatching {
            android.graphics.Color.parseColor(level.hexColor)
        }.getOrDefault(android.graphics.Color.parseColor("#00E5FF"))
        val levelColor = Color(levelColorInt)

        val accentCyan = Color(0xFF00E5FF)
        val accentOrange = Color(0xFFF97316)
        val accentRed = Color(0xFFEF4444)
        val textMuted = Color(0xFF8E9BAE)

        val gaugeBitmap = WidgetVisualGraphics.createStressGaugeBitmap(
            sizePx = 180,
            score = score,
            levelColorInt = levelColorInt,
            strokeWidthPx = 15f
        )

        val balanceBitmap = WidgetVisualGraphics.createAutonomicBalanceBarBitmap(
            widthPx = 300,
            heightPx = 10,
            parasympatheticPct = parasympathetic,
            sympatheticPct = sympathetic
        )

        Box(
            modifier = GlanceModifier
                .fillMaxSize()
                .cornerRadius(24.dp)
                .background(Color(0xFF0B141E))
                .padding(12.dp)
                .clickable(actionStartActivity(launchIntent))
        ) {
            Row(
                modifier = GlanceModifier.fillMaxSize(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // LEFT COLUMN: Mascot Pill + Gauge + Autonomic Balance Bar
                Column(
                    modifier = GlanceModifier.width(106.dp).fillMaxHeight(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // Mascot & Level Chip
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(text = monkeyEmoji, style = TextStyle(fontSize = 12.sp))
                        Spacer(modifier = GlanceModifier.width(3.dp))
                        Box(
                            modifier = GlanceModifier
                                .cornerRadius(8.dp)
                                .background(levelColor.copy(alpha = 0.18f))
                                .padding(horizontal = 5.dp, vertical = 1.5.dp)
                        ) {
                            Text(
                                text = level.displayName,
                                style = TextStyle(
                                    color = ColorProvider(levelColor),
                                    fontSize = 8.5.sp,
                                    fontWeight = FontWeight.Bold
                                )
                            )
                        }
                    }

                    Spacer(modifier = GlanceModifier.height(3.dp))

                    // Gauge
                    Box(
                        modifier = GlanceModifier.size(62.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Image(
                            provider = ImageProvider(gaugeBitmap),
                            contentDescription = "Stress Score Gauge",
                            modifier = GlanceModifier.size(62.dp)
                        )
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(
                                text = if (hasData) "$score" else "--",
                                style = TextStyle(
                                    color = ColorProvider(Color.White),
                                    fontSize = 14.sp,
                                    fontWeight = FontWeight.Bold
                                )
                            )
                            Text(
                                text = "STRESS",
                                style = TextStyle(
                                    color = ColorProvider(textMuted),
                                    fontSize = 7.sp,
                                    fontWeight = FontWeight.Bold
                                )
                            )
                        }
                    }

                    Spacer(modifier = GlanceModifier.height(3.dp))

                    // Balance labels
                    Row(
                        modifier = GlanceModifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "Rest $parasympathetic%",
                            style = TextStyle(color = ColorProvider(accentCyan), fontSize = 7.sp, fontWeight = FontWeight.Bold)
                        )
                        Spacer(modifier = GlanceModifier.defaultWeight())
                        Text(
                            text = "Act $sympathetic%",
                            style = TextStyle(color = ColorProvider(accentOrange), fontSize = 7.sp, fontWeight = FontWeight.Bold)
                        )
                    }

                    Spacer(modifier = GlanceModifier.height(2.dp))

                    Image(
                        provider = ImageProvider(balanceBitmap),
                        contentDescription = "Autonomic Balance Bar",
                        modifier = GlanceModifier.fillMaxWidth().height(5.dp)
                    )
                }

                Spacer(modifier = GlanceModifier.width(10.dp))

                // RIGHT COLUMN: Biometrics, Advice Card, Prompt
                Column(
                    modifier = GlanceModifier.defaultWeight().fillMaxHeight(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // Biometric Pills (HRV & BPM)
                    Row(
                        modifier = GlanceModifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        if (hrv != null) {
                            Box(
                                modifier = GlanceModifier
                                    .cornerRadius(8.dp)
                                    .background(Color.White.copy(alpha = 0.08f))
                                    .padding(horizontal = 6.dp, vertical = 2.dp)
                            ) {
                                Text(
                                    text = "⚡ ${hrv.toInt()} ms",
                                    style = TextStyle(
                                        color = ColorProvider(Color.White),
                                        fontSize = 8.5.sp,
                                        fontWeight = FontWeight.Bold
                                    )
                                )
                            }
                        }
                        if (bpm != null) {
                            Spacer(modifier = GlanceModifier.width(5.dp))
                            Box(
                                modifier = GlanceModifier
                                    .cornerRadius(8.dp)
                                    .background(Color.White.copy(alpha = 0.08f))
                                    .padding(horizontal = 6.dp, vertical = 2.dp)
                            ) {
                                Text(
                                    text = "❤️ ${bpm.toInt()} bpm",
                                    style = TextStyle(
                                        color = ColorProvider(Color.White),
                                        fontSize = 8.5.sp,
                                        fontWeight = FontWeight.Bold
                                    )
                                )
                            }
                        }
                    }

                    Spacer(modifier = GlanceModifier.height(5.dp))

                    // Wisdom / Advice Card
                    Box(
                        modifier = GlanceModifier
                            .fillMaxWidth()
                            .cornerRadius(10.dp)
                            .background(Color(0xFF061020).copy(alpha = 0.85f))
                            .padding(7.dp)
                    ) {
                        Column {
                            Text(
                                text = monkeyName,
                                style = TextStyle(
                                    color = ColorProvider(levelColor),
                                    fontSize = 8.5.sp,
                                    fontWeight = FontWeight.Bold
                                )
                            )
                            Spacer(modifier = GlanceModifier.height(1.dp))
                            Text(
                                text = adviceQuote,
                                style = TextStyle(
                                    color = ColorProvider(Color(0xFFE2E8F0)),
                                    fontSize = 9.sp,
                                    fontWeight = FontWeight.Normal
                                ),
                                maxLines = 2
                            )
                        }
                    }

                    Spacer(modifier = GlanceModifier.height(4.dp))

                    // Footer Link
                    Row(
                        modifier = GlanceModifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "Open Stress Studio",
                            style = TextStyle(
                                color = ColorProvider(accentCyan),
                                fontSize = 8.5.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                        Spacer(modifier = GlanceModifier.width(2.dp))
                        Text(
                            text = "➔",
                            style = TextStyle(
                                color = ColorProvider(accentCyan),
                                fontSize = 8.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                    }
                }
            }
        }
    }
}

class DailyStressGlanceReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = DailyStressGlanceWidget()
}
