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
import com.intellidream.daily.model.StressLevel

class DailyStressGlanceWidget : GlanceAppWidget() {

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val app = runCatching { DailyApp.instance }.getOrNull()

        val stressScore = app?.healthRepository?.currentStressScore?.value ?: 32
        val stressLevel = app?.healthRepository?.currentStressLevel?.value ?: StressLevel.CALM
        val monkeyMood = app?.healthRepository?.stressAnalysis?.value?.monkeyMood
        val monkeyEmoji = monkeyMood?.emoji ?: "🐵"
        val monkeyName = monkeyMood?.displayName ?: "Curious Monkey"

        provideContent {
            StressWidgetContent(
                context = context,
                stressScore = stressScore,
                stressLevel = stressLevel,
                monkeyEmoji = monkeyEmoji,
                monkeyName = monkeyName
            )
        }
    }

    @Composable
    private fun StressWidgetContent(
        context: Context,
        stressScore: Int,
        stressLevel: StressLevel,
        monkeyEmoji: String,
        monkeyName: String
    ) {
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        val levelColor = try {
            Color(android.graphics.Color.parseColor(stressLevel.hexColor))
        } catch (_: Exception) {
            Color(0xFFFFB703)
        }

        val protocol = when {
            stressScore > 75 -> "Box Breathing (4-4-4-4)"
            stressScore > 50 -> "Take a 3-min screen break"
            stressScore > 25 -> "Hydrate & steady rhythm"
            else -> "Peak recovery & flow state"
        }

        Box(
            modifier = GlanceModifier
                .fillMaxSize()
                .cornerRadius(22.dp)
                .background(Color(0xFF0D1520))
                .padding(14.dp)
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
                        text = "$monkeyEmoji STRESS STUDIO",
                        style = TextStyle(
                            color = ColorProvider(levelColor),
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                    Spacer(modifier = GlanceModifier.defaultWeight())
                    Box(
                        modifier = GlanceModifier
                            .cornerRadius(12.dp)
                            .background(levelColor.copy(alpha = 0.20f))
                            .padding(horizontal = 8.dp, vertical = 2.dp)
                    ) {
                        Text(
                            text = stressLevel.displayName,
                            style = TextStyle(
                                color = ColorProvider(levelColor),
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                    }
                }

                Spacer(modifier = GlanceModifier.height(8.dp))

                // Score Display
                Row(
                    verticalAlignment = Alignment.Bottom
                ) {
                    Text(
                        text = "$stressScore",
                        style = TextStyle(
                            color = ColorProvider(Color.White),
                            fontSize = 32.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                    Spacer(modifier = GlanceModifier.width(4.dp))
                    Text(
                        text = "/ 100",
                        style = TextStyle(
                            color = ColorProvider(Color(0xFF8E9BAE)),
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Normal
                        )
                    )
                }

                Spacer(modifier = GlanceModifier.height(6.dp))

                // Advice & protocol
                Text(
                    text = "$monkeyName: $protocol",
                    style = TextStyle(
                        color = ColorProvider(Color(0xFFE2E8F0)),
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Normal
                    ),
                    maxLines = 2
                )
            }
        }
    }
}

class DailyStressGlanceReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = DailyStressGlanceWidget()
}
