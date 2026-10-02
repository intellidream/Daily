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
import com.intellidream.daily.model.SleepRecoveryVerdict
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
        verdict: SleepRecoveryVerdict?
    ) {
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_TARGET_TAB, MainActivity.TAB_HEALTH)
            putExtra(MainActivity.EXTRA_HEALTH_SUBTAB, "sleep")
        }

        val hasData = session != null && session.sleepScore > 0
        val score = if (hasData) session?.sleepScore ?: 0 else 0
        val durationFormatted = session?.totalAsleepFormatted ?: "--"
        val efficiency = session?.efficiencyPercent ?: 85
        val bedtime = session?.bedtimeFormatted ?: "--:--"
        val waketime = session?.wakeTimeFormatted ?: "--:--"
        val timeInBed = session?.timeInBedFormatted ?: "--"
        val device = session?.sourceDevice ?: "Health Connect"

        val accentIndigo = Color(0xFF6366F1)
        val accentPurple = Color(0xFFA855F7)
        val accentCyan = Color(0xFF00E5FF)
        val accentAmber = Color(0xFFFFB800)
        val textMuted = Color(0xFF8E9BAE)

        val scoreBitmap = WidgetVisualGraphics.createSleepScoreRingBitmap(
            sizePx = 200,
            score = score,
            strokeWidthPx = 18f
        )

        val hypnogramBitmap = WidgetVisualGraphics.createSleepHypnogramBarBitmap(
            widthPx = 400,
            heightPx = 14,
            deepSec = session?.deepSeconds ?: 0.0,
            remSec = session?.remSeconds ?: 0.0,
            lightSec = session?.lightSeconds ?: 0.0,
            awakeSec = session?.awakeSeconds ?: 0.0
        )

        Box(
            modifier = GlanceModifier
                .fillMaxSize()
                .cornerRadius(24.dp)
                .background(Color(0xFF0A0C1D))
                .padding(12.dp)
                .clickable(actionStartActivity(launchIntent))
        ) {
            Row(
                modifier = GlanceModifier.fillMaxSize(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // LEFT: Sleep Score Radial Ring with Duration & Score Pill
                Box(
                    modifier = GlanceModifier.size(88.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Image(
                        provider = ImageProvider(scoreBitmap),
                        contentDescription = "Sleep Score Ring",
                        modifier = GlanceModifier.size(88.dp)
                    )
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = durationFormatted,
                            style = TextStyle(
                                color = ColorProvider(Color.White),
                                fontSize = 13.5.sp,
                                fontWeight = FontWeight.Bold
                            ),
                            maxLines = 1
                        )
                        Spacer(modifier = GlanceModifier.height(2.dp))
                        Box(
                            modifier = GlanceModifier
                                .cornerRadius(8.dp)
                                .background(accentCyan.copy(alpha = 0.18f))
                                .padding(horizontal = 5.dp, vertical = 1.dp)
                        ) {
                            Text(
                                text = if (hasData) "$score pts" else "No Data",
                                style = TextStyle(
                                    color = ColorProvider(accentCyan),
                                    fontSize = 9.sp,
                                    fontWeight = FontWeight.Bold
                                ),
                                maxLines = 1
                            )
                        }
                    }
                }

                Spacer(modifier = GlanceModifier.width(10.dp))

                // RIGHT: Schedule Header, Hypnogram Bar, 4 Mini Stage Pills, and Device
                Column(
                    modifier = GlanceModifier.defaultWeight().fillMaxHeight(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // Header Row: Schedule & Efficiency/Restorative
                    Row(
                        modifier = GlanceModifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "🌙 $bedtime ➔ $waketime",
                            style = TextStyle(
                                color = ColorProvider(Color.White),
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                        Spacer(modifier = GlanceModifier.defaultWeight())
                        Box(
                            modifier = GlanceModifier
                                .cornerRadius(8.dp)
                                .background(accentPurple.copy(alpha = 0.18f))
                                .padding(horizontal = 6.dp, vertical = 2.dp)
                        ) {
                            Text(
                                text = "$efficiency% Eff",
                                style = TextStyle(
                                    color = ColorProvider(accentPurple),
                                    fontSize = 9.sp,
                                    fontWeight = FontWeight.Bold
                                )
                            )
                        }
                    }

                    Spacer(modifier = GlanceModifier.height(4.dp))

                    // Multi-Stage Proportional Bar
                    Image(
                        provider = ImageProvider(hypnogramBitmap),
                        contentDescription = "Sleep Stage Architecture",
                        modifier = GlanceModifier.fillMaxWidth().height(7.dp)
                    )

                    Spacer(modifier = GlanceModifier.height(5.dp))

                    // 4 Mini Stage Metric Capsules
                    Row(
                        modifier = GlanceModifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        StageMiniPill(label = "Deep", duration = session?.deepFormatted ?: "--", color = accentIndigo, modifier = GlanceModifier.defaultWeight())
                        Spacer(modifier = GlanceModifier.width(3.dp))
                        StageMiniPill(label = "REM", duration = session?.remFormatted ?: "--", color = accentPurple, modifier = GlanceModifier.defaultWeight())
                        Spacer(modifier = GlanceModifier.width(3.dp))
                        StageMiniPill(label = "Light", duration = session?.lightFormatted ?: "--", color = accentCyan, modifier = GlanceModifier.defaultWeight())
                        Spacer(modifier = GlanceModifier.width(3.dp))
                        StageMiniPill(label = "Awake", duration = session?.awakeFormatted ?: "--", color = accentAmber, modifier = GlanceModifier.defaultWeight())
                    }

                    Spacer(modifier = GlanceModifier.height(4.dp))

                    // Footer Row: In-bed and source
                    Row(
                        modifier = GlanceModifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "$timeInBed in bed",
                            style = TextStyle(
                                color = ColorProvider(textMuted),
                                fontSize = 8.5.sp,
                                fontWeight = FontWeight.Normal
                            )
                        )
                        Spacer(modifier = GlanceModifier.defaultWeight())
                        Text(
                            text = device,
                            style = TextStyle(
                                color = ColorProvider(textMuted),
                                fontSize = 8.5.sp,
                                fontWeight = FontWeight.Medium
                            )
                        )
                    }
                }
            }
        }
    }

    @Composable
    private fun StageMiniPill(
        label: String,
        duration: String,
        color: Color,
        modifier: GlanceModifier
    ) {
        Column(
            modifier = modifier
                .cornerRadius(6.dp)
                .background(color.copy(alpha = 0.12f))
                .padding(vertical = 2.dp, horizontal = 2.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = label,
                style = TextStyle(
                    color = ColorProvider(color),
                    fontSize = 7.5.sp,
                    fontWeight = FontWeight.Bold
                ),
                maxLines = 1
            )
            Text(
                text = duration,
                style = TextStyle(
                    color = ColorProvider(Color.White),
                    fontSize = 8.sp,
                    fontWeight = FontWeight.Medium
                ),
                maxLines = 1
            )
        }
    }
}

class DailySleepGlanceReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = DailySleepGlanceWidget()
}
