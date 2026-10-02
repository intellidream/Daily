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
import java.util.Locale

class DailyBubblesGlanceWidget : GlanceAppWidget() {

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val app = runCatching { DailyApp.instance }.getOrNull()

        val todayMl = app?.habitsRepository?.waterTotalToday?.value ?: 0.0
        val goalMl = app?.habitsRepository?.waterGoal?.value ?: 2000.0
        val breakdown = app?.habitsRepository?.waterDrinkBreakdown?.value ?: emptyList()

        provideContent {
            BubblesWidgetContent(
                context = context,
                todayMl = todayMl,
                goalMl = goalMl,
                breakdown = breakdown
            )
        }
    }

    @Composable
    private fun BubblesWidgetContent(
        context: Context,
        todayMl: Double,
        goalMl: Double,
        breakdown: List<com.intellidream.daily.model.HabitDrinkBreakdown>
    ) {
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_TARGET_TAB, MainActivity.TAB_HABITS)
            putExtra(MainActivity.EXTRA_HABIT_SUBTAB, "water")
        }

        val safeGoal = if (goalMl > 0.0) goalMl else 2000.0
        val progress = (todayMl / safeGoal).toFloat().coerceIn(0f, 1f)
        val progressPercent = (progress * 100).toInt()

        val accentCyan = Color(0xFF00E5FF)
        val accentMint = Color(0xFF00FFB2)

        Box(
            modifier = GlanceModifier
                .fillMaxSize()
                .cornerRadius(22.dp)
                .background(Color(0xFF071224))
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
                        text = "💧 BUBBLES HYDRATION",
                        style = TextStyle(
                            color = ColorProvider(accentCyan),
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                    Spacer(modifier = GlanceModifier.defaultWeight())
                    Box(
                        modifier = GlanceModifier
                            .cornerRadius(12.dp)
                            .background(accentCyan.copy(alpha = 0.20f))
                            .padding(horizontal = 8.dp, vertical = 2.dp)
                    ) {
                        Text(
                            text = "$progressPercent%",
                            style = TextStyle(
                                color = ColorProvider(accentCyan),
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                    }
                }

                Spacer(modifier = GlanceModifier.height(8.dp))

                // Score / Amount Display
                Row(
                    verticalAlignment = Alignment.Bottom
                ) {
                    Text(
                        text = String.format(Locale.US, "%,d", todayMl.toInt()),
                        style = TextStyle(
                            color = ColorProvider(Color.White),
                            fontSize = 28.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                    Spacer(modifier = GlanceModifier.width(4.dp))
                    Text(
                        text = "/ ${String.format(Locale.US, "%,d", safeGoal.toInt())} ml",
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
                    color = ColorProvider(accentCyan),
                    backgroundColor = ColorProvider(Color.White.copy(alpha = 0.12f))
                )

                Spacer(modifier = GlanceModifier.height(8.dp))

                // Footer Breakdown or Encouragement
                val subtitle = if (breakdown.isNotEmpty()) {
                    breakdown.take(3).joinToString(" · ") { "${it.drink}: ${it.amount.toInt()}ml" }
                } else if (todayMl > 0) {
                    "Water: ${todayMl.toInt()} ml"
                } else {
                    "Tap to log your first drink of the day"
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

class DailyBubblesGlanceReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = DailyBubblesGlanceWidget()
}
