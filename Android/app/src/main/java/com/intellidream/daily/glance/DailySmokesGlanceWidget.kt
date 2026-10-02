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
import java.util.Date

class DailySmokesGlanceWidget : GlanceAppWidget() {

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val app = runCatching { DailyApp.instance }.getOrNull()

        val todayTotal = app?.habitsRepository?.smokesTotalToday?.value ?: 0
        val baseline = app?.habitsRepository?.smokesSettings?.value?.baselineDailyCount ?: 20
        val breakdown = app?.habitsRepository?.smokesTypeBreakdown?.value ?: emptyList()
        val latestLog = app?.habitsRepository?.selectedDateSmokesLogs?.value?.maxByOrNull { it.loggedAt }
        val lastSmokeTime = latestLog?.loggedAt

        provideContent {
            SmokesWidgetContent(
                context = context,
                todayTotal = todayTotal,
                baseline = baseline,
                breakdown = breakdown,
                lastSmokeTime = lastSmokeTime
            )
        }
    }

    @Composable
    private fun SmokesWidgetContent(
        context: Context,
        todayTotal: Int,
        baseline: Int,
        breakdown: List<com.intellidream.daily.model.HabitDrinkBreakdown>,
        lastSmokeTime: Long?
    ) {
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_TARGET_TAB, MainActivity.TAB_HABITS)
            putExtra(MainActivity.EXTRA_HABIT_SUBTAB, "smokes")
        }

        val safeBaseline = if (baseline > 0) baseline else 20
        val ratio = todayTotal.toFloat() / safeBaseline.toFloat()
        val progress = ratio.coerceIn(0f, 1f)

        val healthColor = when {
            todayTotal == 0 -> Color(0xFF00E676)
            ratio <= 0.40f -> Color(0xFF10B981)
            ratio <= 0.75f -> Color(0xFFFFB800)
            ratio <= 1.0f -> Color(0xFFF97316)
            else -> Color(0xFFEF4444)
        }

        val elapsedText = if (lastSmokeTime != null && todayTotal > 0) {
            val diffSec = maxOf(0L, (System.currentTimeMillis() - lastSmokeTime) / 1000L)
            val hours = diffSec / 3600
            val minutes = (diffSec % 3600) / 60
            if (hours > 0) "${hours}h ${minutes}m ago" else "${minutes}m ago"
        } else if (todayTotal == 0) {
            "Clean today!"
        } else {
            "--"
        }

        Box(
            modifier = GlanceModifier
                .fillMaxSize()
                .cornerRadius(22.dp)
                .background(Color(0xFF0F131C))
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
                        text = "🫁 SMOKES & CRAVINGS",
                        style = TextStyle(
                            color = ColorProvider(healthColor),
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                    Spacer(modifier = GlanceModifier.defaultWeight())
                    Box(
                        modifier = GlanceModifier
                            .cornerRadius(12.dp)
                            .background(healthColor.copy(alpha = 0.20f))
                            .padding(horizontal = 8.dp, vertical = 2.dp)
                    ) {
                        Text(
                            text = elapsedText,
                            style = TextStyle(
                                color = ColorProvider(healthColor),
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                    }
                }

                Spacer(modifier = GlanceModifier.height(8.dp))

                // Metric Count Display
                Row(
                    verticalAlignment = Alignment.Bottom
                ) {
                    Text(
                        text = "$todayTotal",
                        style = TextStyle(
                            color = ColorProvider(Color.White),
                            fontSize = 28.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                    Spacer(modifier = GlanceModifier.width(4.dp))
                    Text(
                        text = "/ $safeBaseline max",
                        style = TextStyle(
                            color = ColorProvider(Color(0xFF8E9BAE)),
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Normal
                        )
                    )
                }

                Spacer(modifier = GlanceModifier.height(8.dp))

                // Progress Indicator
                LinearProgressIndicator(
                    progress = progress,
                    modifier = GlanceModifier
                        .fillMaxWidth()
                        .height(6.dp)
                        .cornerRadius(3.dp),
                    color = ColorProvider(healthColor),
                    backgroundColor = ColorProvider(Color.White.copy(alpha = 0.12f))
                )

                Spacer(modifier = GlanceModifier.height(8.dp))

                // Footer Breakdown
                val subtitle = if (breakdown.isNotEmpty()) {
                    breakdown.take(3).joinToString(" · ") { "${it.drink}: ${it.amount.toInt()}" }
                } else if (todayTotal == 0) {
                    "Lungs recovering · Zero cravings logged"
                } else {
                    "Cigarettes: $todayTotal"
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

class DailySmokesGlanceReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = DailySmokesGlanceWidget()
}
