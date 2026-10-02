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
import androidx.glance.appwidget.LinearProgressIndicator
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
import com.intellidream.daily.model.SleepSession

class DailySleepGlanceWidget : GlanceAppWidget() {

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val app = runCatching { DailyApp.instance }.getOrNull()

        val sleepSession = app?.healthRepository?.primarySleepSession?.value
        val verdict = app?.healthRepository?.sleepRecoveryVerdict?.value

        provideContent {
            SleepWidgetContent(
                context = context,
                session = sleepSession,
                verdict = verdict
            )
        }
    }

    @Composable
    private fun SleepWidgetContent(
        context: Context,
        session: SleepSession?,
        verdict: com.intellidream.daily.model.SleepRecoveryVerdict?
    ) {
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_TARGET_TAB, MainActivity.TAB_HEALTH)
            putExtra(MainActivity.EXTRA_HEALTH_SUBTAB, "sleep")
        }

        val hasData = session != null && session.sleepScore > 0
        val score = session?.takeIf { it.sleepScore > 0 }?.sleepScore
        val durationFormatted = session?.totalAsleepFormatted ?: "--"
        val efficiency = session?.takeIf { it.sleepScore > 0 }?.efficiencyPercent

        val accentIndigo = Color(0xFF8B5CF6)
        val accentCyan = Color(0xFF00E5FF)
        val verdictColor = verdict?.let {
            runCatching { Color(android.graphics.Color.parseColor(it.status.hexColor)) }.getOrNull()
        } ?: if (hasData) accentIndigo else Color(0xFF8E9BAE)
        val verdictTitle = verdict?.status?.displayName?.uppercase(java.util.Locale.US) ?: if (hasData) "RECOVERY" else "NO DATA"

        Box(
            modifier = GlanceModifier
                .fillMaxSize()
                .cornerRadius(22.dp)
                .background(Color(0xFF0C0E1E))
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
                        text = "🌙 SLEEP STUDIO",
                        style = TextStyle(
                            color = ColorProvider(accentIndigo),
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                    Spacer(modifier = GlanceModifier.defaultWeight())
                    Box(
                        modifier = GlanceModifier
                            .cornerRadius(12.dp)
                            .background(verdictColor.copy(alpha = 0.20f))
                            .padding(horizontal = 8.dp, vertical = 2.dp)
                    ) {
                        Text(
                            text = verdictTitle,
                            style = TextStyle(
                                color = ColorProvider(verdictColor),
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                    }
                }

                Spacer(modifier = GlanceModifier.height(8.dp))

                // Score / Duration Display
                Row(
                    verticalAlignment = Alignment.Bottom
                ) {
                    Text(
                        text = if (score != null) "$score" else "--",
                        style = TextStyle(
                            color = ColorProvider(Color.White),
                            fontSize = 28.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                    if (score != null) {
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
                    Spacer(modifier = GlanceModifier.defaultWeight())
                    Text(
                        text = if (efficiency != null) "$durationFormatted · $efficiency% eff" else durationFormatted,
                        style = TextStyle(
                            color = ColorProvider(accentCyan),
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                }

                Spacer(modifier = GlanceModifier.height(8.dp))

                // Progress Indicator
                val progress = if (score != null) (score.toFloat() / 100f).coerceIn(0f, 1f) else 0f
                LinearProgressIndicator(
                    progress = progress,
                    modifier = GlanceModifier
                        .fillMaxWidth()
                        .height(6.dp)
                        .cornerRadius(3.dp),
                    color = ColorProvider(accentIndigo),
                    backgroundColor = ColorProvider(Color.White.copy(alpha = 0.12f))
                )

                Spacer(modifier = GlanceModifier.height(8.dp))

                // Footer breakdown / advice
                val subtitle = if (session != null && hasData) {
                    val deepFormatted = session.deepFormatted
                    val remFormatted = session.remFormatted
                    "Deep: $deepFormatted · REM: $remFormatted"
                } else {
                    "Wear smartwatch overnight to record sleep"
                }

                Text(
                    text = subtitle,
                    style = TextStyle(
                        color = ColorProvider(Color(0xFF8E9BAE)),
                        fontSize = 10.5.sp,
                        fontWeight = FontWeight.Normal
                    ),
                    maxLines = 1
                )
            }
        }
    }
}

class DailySleepGlanceReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = DailySleepGlanceWidget()
}
