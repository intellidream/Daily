package com.intellidream.daily.glance

import android.content.Context
import android.content.Intent
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
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
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.intellidream.daily.DailyApp
import com.intellidream.daily.MainActivity
import java.util.Locale

class DailyCombinedGlanceWidget : GlanceAppWidget() {

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val app = runCatching { DailyApp.instance }.getOrNull()

        val steps = app?.healthRepository?.totalStepsToday?.value ?: 0
        val sleepSession = app?.healthRepository?.primarySleepSession?.value
        val sleepFormatted = sleepSession?.totalAsleepFormatted ?: "--"
        val sleepScore = sleepSession?.sleepScore
        val stressScore = app?.healthRepository?.currentStressScore?.value ?: 32
        val stressLevel = app?.healthRepository?.currentStressLevel?.value?.displayName ?: "Calm"
        val monkeyMood = app?.healthRepository?.stressAnalysis?.value?.monkeyMood
        val monkeyEmoji = monkeyMood?.emoji ?: "🐵"
        val waterMl = app?.habitsRepository?.waterTotalToday?.value ?: 0.0
        val waterLiters = "%.1fL".format(Locale.US, waterMl / 1000.0)

        provideContent {
            CombinedWidgetContent(
                context = context,
                steps = steps,
                sleepFormatted = sleepFormatted,
                sleepScore = sleepScore,
                stressScore = stressScore,
                stressLevel = stressLevel,
                monkeyEmoji = monkeyEmoji,
                waterLiters = waterLiters
            )
        }
    }

    @Composable
    private fun CombinedWidgetContent(
        context: Context,
        steps: Int,
        sleepFormatted: String,
        sleepScore: Int?,
        stressScore: Int,
        stressLevel: String,
        monkeyEmoji: String,
        waterLiters: String
    ) {
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        Box(
            modifier = GlanceModifier
                .fillMaxSize()
                .cornerRadius(22.dp)
                .background(Color(0xFF09101E))
                .padding(12.dp)
                .clickable(actionStartActivity(launchIntent))
        ) {
            Column(
                modifier = GlanceModifier.fillMaxSize(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Header Row
                Row(
                    modifier = GlanceModifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "DAYONE",
                        style = TextStyle(
                            color = ColorProvider(Color(0xFF00F5D4)),
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                    Spacer(modifier = GlanceModifier.defaultWeight())
                    Text(
                        text = "Overview",
                        style = TextStyle(
                            color = ColorProvider(Color(0xFF8E9BAE)),
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Normal
                        )
                    )
                }

                Spacer(modifier = GlanceModifier.height(8.dp))

                // Top Metrics Row (Steps + Sleep)
                Row(
                    modifier = GlanceModifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // Steps Block
                    Column(modifier = GlanceModifier.defaultWeight()) {
                        Text(
                            text = "STEPS",
                            style = TextStyle(
                                color = ColorProvider(Color(0xFF00F5D4)),
                                fontSize = 9.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                        Spacer(modifier = GlanceModifier.height(2.dp))
                        Text(
                            text = String.format(Locale.US, "%,d", steps),
                            style = TextStyle(
                                color = ColorProvider(Color.White),
                                fontSize = 14.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                    }

                    Spacer(modifier = GlanceModifier.width(8.dp))

                    // Sleep Block
                    Column(modifier = GlanceModifier.defaultWeight()) {
                        Text(
                            text = "SLEEP",
                            style = TextStyle(
                                color = ColorProvider(Color(0xFF8338EC)),
                                fontSize = 9.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                        Spacer(modifier = GlanceModifier.height(2.dp))
                        Text(
                            text = if (sleepScore != null) "$sleepFormatted · $sleepScore" else sleepFormatted,
                            style = TextStyle(
                                color = ColorProvider(Color.White),
                                fontSize = 14.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                    }
                }

                Spacer(modifier = GlanceModifier.height(8.dp))

                // Bottom Metrics Row (Hydration + Stress)
                Row(
                    modifier = GlanceModifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // Hydration Block
                    Column(modifier = GlanceModifier.defaultWeight()) {
                        Text(
                            text = "HYDRATION",
                            style = TextStyle(
                                color = ColorProvider(Color(0xFF00BBF9)),
                                fontSize = 9.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                        Spacer(modifier = GlanceModifier.height(2.dp))
                        Text(
                            text = waterLiters,
                            style = TextStyle(
                                color = ColorProvider(Color.White),
                                fontSize = 14.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                    }

                    Spacer(modifier = GlanceModifier.width(8.dp))

                    // Stress Block
                    Column(modifier = GlanceModifier.defaultWeight()) {
                        Text(
                            text = "STRESS",
                            style = TextStyle(
                                color = ColorProvider(Color(0xFFFFB703)),
                                fontSize = 9.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                        Spacer(modifier = GlanceModifier.height(2.dp))
                        Text(
                            text = "$stressScore $monkeyEmoji",
                            style = TextStyle(
                                color = ColorProvider(Color.White),
                                fontSize = 14.sp,
                                fontWeight = FontWeight.Bold
                            )
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
