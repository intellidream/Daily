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
import androidx.glance.action.actionParametersOf
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.action.actionRunCallback
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
import com.intellidream.daily.model.HabitLogRecord
import kotlin.math.max

class DailySmokesGlanceWidget : GlanceAppWidget() {

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val app = runCatching { DailyApp.instance }.getOrNull()

        val todayTotal = app?.habitsRepository?.smokesTotalToday?.value ?: 0
        val baseline = app?.habitsRepository?.smokesSettings?.value?.baselineDailyCount ?: 15
        val logs = app?.habitsRepository?.selectedDateSmokesLogs?.value ?: emptyList()

        provideContent {
            SmokesWidgetContent(
                context = context,
                todayTotal = todayTotal,
                baseline = baseline,
                logs = logs
            )
        }
    }

    @Composable
    private fun SmokesWidgetContent(
        context: Context,
        todayTotal: Int,
        baseline: Int,
        logs: List<HabitLogRecord>
    ) {
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_TARGET_TAB, MainActivity.TAB_HABITS)
            putExtra(MainActivity.EXTRA_HABIT_SUBTAB, "smokes")
        }

        val safeBaseline = max(baseline, 1)
        val progressRatio = todayTotal.toFloat() / safeBaseline.toFloat()

        // Ring color based on harm reduction performance
        val ringColorInt = when {
            progressRatio <= 0.60f -> android.graphics.Color.parseColor("#00E676") // Green
            progressRatio <= 0.90f -> android.graphics.Color.parseColor("#00E5FF") // Cyan
            progressRatio <= 1.00f -> android.graphics.Color.parseColor("#FFB703") // Amber
            else -> android.graphics.Color.parseColor("#EF4444")                  // Red
        }
        val lungColorInt = when {
            progressRatio <= 0.70f -> android.graphics.Color.parseColor("#38BDF8")
            progressRatio <= 1.00f -> android.graphics.Color.parseColor("#FB923C")
            else -> android.graphics.Color.parseColor("#F87171")
        }

        val formattedTime = if (logs.isNotEmpty()) {
            val lastLog = logs.maxByOrNull { it.loggedAt }
            if (lastLog != null) {
                val diffMs = max(0L, System.currentTimeMillis() - lastLog.loggedAt)
                val diffMin = diffMs / 60000L
                if (diffMin < 60) "${diffMin}m ago" else "${diffMin / 60}h ago"
            } else "--"
        } else "Clear today"

        val accentPurple = Color(0xFFA855F7)
        val accentOrange = Color(0xFFF97316)
        val accentRed = Color(0xFFEF4444)
        val accentBlue = Color(0xFF3B82F6)
        val textMuted = Color(0xFF8E9BAE)

        val gaugeBitmap = WidgetVisualGraphics.createSmokesGaugeBitmap(
            sizePx = 200,
            todayTotal = todayTotal,
            baseline = safeBaseline,
            ringColorInt = ringColorInt,
            lungColorInt = lungColorInt,
            strokeWidthPx = 18f
        )

        Box(
            modifier = GlanceModifier
                .fillMaxSize()
                .cornerRadius(24.dp)
                .background(Color(0xFF140B10))
                .padding(12.dp)
        ) {
            Row(
                modifier = GlanceModifier.fillMaxSize(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // LEFT: Large Circle with Anatomical Lungs and Count
                Box(
                    modifier = GlanceModifier
                        .size(92.dp)
                        .clickable(actionStartActivity(launchIntent)),
                    contentAlignment = Alignment.Center
                ) {
                    Image(
                        provider = ImageProvider(gaugeBitmap),
                        contentDescription = "Smokes Health Gauge",
                        modifier = GlanceModifier.size(92.dp)
                    )
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = GlanceModifier.padding(top = 22.dp)
                    ) {
                        Text(
                            text = "$todayTotal",
                            style = TextStyle(
                                color = ColorProvider(Color.White),
                                fontSize = 16.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                    }
                }

                Spacer(modifier = GlanceModifier.width(10.dp))

                // RIGHT: Header (Base · Time · Flame) & 2x2 Buttons Grid
                Column(
                    modifier = GlanceModifier.defaultWeight().fillMaxHeight(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // Header Row: Baseline + Time + Flame Icon
                    Row(
                        modifier = GlanceModifier.fillMaxWidth().clickable(actionStartActivity(launchIntent)),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                text = "$baseline ",
                                style = TextStyle(
                                    color = ColorProvider(Color.White),
                                    fontSize = 12.sp,
                                    fontWeight = FontWeight.Bold
                                )
                            )
                            Text(
                                text = "base",
                                style = TextStyle(
                                    color = ColorProvider(textMuted),
                                    fontSize = 9.sp,
                                    fontWeight = FontWeight.Medium
                                )
                            )
                        }

                        Spacer(modifier = GlanceModifier.width(4.dp))
                        Text(
                            text = "·",
                            style = TextStyle(color = ColorProvider(textMuted), fontSize = 10.sp)
                        )
                        Spacer(modifier = GlanceModifier.width(4.dp))

                        Text(
                            text = formattedTime,
                            style = TextStyle(
                                color = ColorProvider(Color(0xFFE2E8F0)),
                                fontSize = 10.5.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )

                        Spacer(modifier = GlanceModifier.defaultWeight())

                        Text(
                            text = "🔥",
                            style = TextStyle(fontSize = 12.sp)
                        )
                    }

                    Spacer(modifier = GlanceModifier.height(8.dp))

                    // 2x2 Action Buttons Grid (Matches iOS 1:1)
                    // Top: Cgr (Purple) & Rol (Orange)
                    Row(
                        modifier = GlanceModifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        ActionButtonPill(
                            label = "Cgr",
                            textColor = accentPurple,
                            bgColor = accentPurple.copy(alpha = 0.16f),
                            modifier = GlanceModifier.defaultWeight().height(26.dp)
                                .clickable(
                                    actionRunCallback<LogSmokeActionCallback>(
                                        actionParametersOf(LogSmokeActionCallback.SmokeTypeKey to "Cgr")
                                    )
                                )
                        )
                        Spacer(modifier = GlanceModifier.width(6.dp))
                        ActionButtonPill(
                            label = "Rol",
                            textColor = accentOrange,
                            bgColor = accentOrange.copy(alpha = 0.16f),
                            modifier = GlanceModifier.defaultWeight().height(26.dp)
                                .clickable(
                                    actionRunCallback<LogSmokeActionCallback>(
                                        actionParametersOf(LogSmokeActionCallback.SmokeTypeKey to "Rol")
                                    )
                                )
                        )
                    }

                    Spacer(modifier = GlanceModifier.height(4.dp))

                    // Bottom: Cig (Red) & Heat (Blue)
                    Row(
                        modifier = GlanceModifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        ActionButtonPill(
                            label = "Cig",
                            textColor = accentRed,
                            bgColor = accentRed.copy(alpha = 0.16f),
                            modifier = GlanceModifier.defaultWeight().height(26.dp)
                                .clickable(
                                    actionRunCallback<LogSmokeActionCallback>(
                                        actionParametersOf(LogSmokeActionCallback.SmokeTypeKey to "Cig")
                                    )
                                )
                        )
                        Spacer(modifier = GlanceModifier.width(6.dp))
                        ActionButtonPill(
                            label = "Heat",
                            textColor = accentBlue,
                            bgColor = accentBlue.copy(alpha = 0.16f),
                            modifier = GlanceModifier.defaultWeight().height(26.dp)
                                .clickable(
                                    actionRunCallback<LogSmokeActionCallback>(
                                        actionParametersOf(LogSmokeActionCallback.SmokeTypeKey to "Heat")
                                    )
                                )
                        )
                    }
                }
            }
        }
    }

    @Composable
    private fun ActionButtonPill(
        label: String,
        textColor: Color,
        bgColor: Color,
        modifier: GlanceModifier
    ) {
        Box(
            modifier = modifier
                .cornerRadius(13.dp)
                .background(bgColor),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = label,
                style = TextStyle(
                    color = ColorProvider(textColor),
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold
                )
            )
        }
    }
}

class DailySmokesGlanceReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = DailySmokesGlanceWidget()
}
