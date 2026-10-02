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
import com.intellidream.daily.model.HabitDrinkBreakdown
import java.util.Locale
import kotlin.math.max

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
        breakdown: List<HabitDrinkBreakdown>
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
        val accentGreen = Color(0xFF00E676)
        val coffeeYellow = Color(0xFFF59E0B)
        val teaGreen = Color(0xFF84CC16)
        val textMuted = Color(0xFF8E9BAE)

        // Convert breakdown for Canvas rendering
        val breakdownPairs = breakdown.map { item ->
            val colorInt = runCatching { android.graphics.Color.parseColor(item.hexColor) }
                .getOrDefault(android.graphics.Color.parseColor("#00E5FF"))
            item.amount to colorInt
        }

        val arcBitmap = WidgetVisualGraphics.createMultiDrinkArcBitmap(
            sizePx = 200,
            todayMl = todayMl,
            goalMl = safeGoal,
            breakdown = breakdownPairs,
            strokeWidthPx = 18f
        )

        Box(
            modifier = GlanceModifier
                .fillMaxSize()
                .cornerRadius(24.dp)
                .background(Color(0xFF06101E))
                .padding(12.dp)
        ) {
            Row(
                modifier = GlanceModifier.fillMaxSize(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // LEFT: Circular Hero with Center Metric Overlay
                Box(
                    modifier = GlanceModifier
                        .size(92.dp)
                        .clickable(actionStartActivity(launchIntent)),
                    contentAlignment = Alignment.Center
                ) {
                    Image(
                        provider = ImageProvider(arcBitmap),
                        contentDescription = "Hydration Progress Ring",
                        modifier = GlanceModifier.size(92.dp)
                    )
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = String.format(Locale.US, "%,d", todayMl.toInt()),
                            style = TextStyle(
                                color = ColorProvider(Color.White),
                                fontSize = 16.sp,
                                fontWeight = FontWeight.Bold
                            ),
                            maxLines = 1
                        )
                        Text(
                            text = "of ${safeGoal.toInt()} ml",
                            style = TextStyle(
                                color = ColorProvider(textMuted),
                                fontSize = 9.sp,
                                fontWeight = FontWeight.Medium
                            ),
                            maxLines = 1
                        )
                    }
                }

                Spacer(modifier = GlanceModifier.width(10.dp))

                // RIGHT: Header (Percentage + Icon), Breakdown, and 2x2 Buttons Grid
                Column(
                    modifier = GlanceModifier.defaultWeight().fillMaxHeight(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // Header Row: Percentage on left, Drop icon on right
                    Row(
                        modifier = GlanceModifier.fillMaxWidth().clickable(actionStartActivity(launchIntent)),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "$progressPercent%",
                            style = TextStyle(
                                color = ColorProvider(accentCyan),
                                fontSize = 14.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                        Spacer(modifier = GlanceModifier.defaultWeight())
                        Text(
                            text = "💧",
                            style = TextStyle(
                                fontSize = 12.sp
                            )
                        )
                    }

                    Spacer(modifier = GlanceModifier.height(3.dp))

                    // Liquid Breakdown Pill Row
                    Row(
                        modifier = GlanceModifier.fillMaxWidth().clickable(actionStartActivity(launchIntent)),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        if (breakdown.isNotEmpty()) {
                            breakdown.take(2).forEachIndexed { idx, item ->
                                if (idx > 0) Spacer(modifier = GlanceModifier.width(6.dp))
                                val itemColor = runCatching {
                                    Color(android.graphics.Color.parseColor(item.hexColor))
                                }.getOrDefault(accentCyan)
                                Text(
                                    text = "${item.amount.toInt()} ml",
                                    style = TextStyle(
                                        color = ColorProvider(itemColor),
                                        fontSize = 10.sp,
                                        fontWeight = FontWeight.Bold
                                    )
                                )
                            }
                        } else {
                            Text(
                                text = "${todayMl.toInt()} ml logged",
                                style = TextStyle(
                                    color = ColorProvider(accentCyan),
                                    fontSize = 10.sp,
                                    fontWeight = FontWeight.Medium
                                )
                            )
                        }
                    }

                    Spacer(modifier = GlanceModifier.height(6.dp))

                    // 2x2 Interactive Action Buttons Grid (Matches iOS 1:1)
                    // Row 1: 300 (Water) & 150 (Water)
                    Row(
                        modifier = GlanceModifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        ActionButtonPill(
                            label = "300",
                            textColor = accentCyan,
                            bgColor = accentCyan.copy(alpha = 0.16f),
                            modifier = GlanceModifier.defaultWeight().height(26.dp)
                                .clickable(
                                    actionRunCallback<LogWaterActionCallback>(
                                        actionParametersOf(
                                            LogWaterActionCallback.AmountKey to 300.0,
                                            LogWaterActionCallback.DrinkKey to "Water"
                                        )
                                    )
                                )
                        )
                        Spacer(modifier = GlanceModifier.width(6.dp))
                        ActionButtonPill(
                            label = "150",
                            textColor = accentCyan,
                            bgColor = accentCyan.copy(alpha = 0.16f),
                            modifier = GlanceModifier.defaultWeight().height(26.dp)
                                .clickable(
                                    actionRunCallback<LogWaterActionCallback>(
                                        actionParametersOf(
                                            LogWaterActionCallback.AmountKey to 150.0,
                                            LogWaterActionCallback.DrinkKey to "Water"
                                        )
                                    )
                                )
                        )
                    }

                    Spacer(modifier = GlanceModifier.height(4.dp))

                    // Row 2: 100 (Coffee) & 200 (Tea)
                    Row(
                        modifier = GlanceModifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        ActionButtonPill(
                            label = "100",
                            textColor = coffeeYellow,
                            bgColor = coffeeYellow.copy(alpha = 0.16f),
                            modifier = GlanceModifier.defaultWeight().height(26.dp)
                                .clickable(
                                    actionRunCallback<LogWaterActionCallback>(
                                        actionParametersOf(
                                            LogWaterActionCallback.AmountKey to 100.0,
                                            LogWaterActionCallback.DrinkKey to "Coffee"
                                        )
                                    )
                                )
                        )
                        Spacer(modifier = GlanceModifier.width(6.dp))
                        ActionButtonPill(
                            label = "200",
                            textColor = teaGreen,
                            bgColor = teaGreen.copy(alpha = 0.16f),
                            modifier = GlanceModifier.defaultWeight().height(26.dp)
                                .clickable(
                                    actionRunCallback<LogWaterActionCallback>(
                                        actionParametersOf(
                                            LogWaterActionCallback.AmountKey to 200.0,
                                            LogWaterActionCallback.DrinkKey to "Tea"
                                        )
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

class DailyBubblesGlanceReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = DailyBubblesGlanceWidget()
}
