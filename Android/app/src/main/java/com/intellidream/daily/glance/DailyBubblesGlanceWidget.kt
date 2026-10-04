package com.intellidream.daily.glance

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalSize
import androidx.glance.action.actionParametersOf
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.appWidgetBackground
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
import com.intellidream.daily.R
import java.util.Locale
import kotlin.math.max
import kotlin.math.min

class DailyBubblesGlanceReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = DailyBubblesGlanceWidget()
}

class DailyBubblesGlanceWidget : GlanceAppWidget() {

    override val sizeMode: SizeMode = SizeMode.Exact


    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val app = runCatching { DailyApp.instance }.getOrNull()
        val waterLogs = app?.habitsRepository?.selectedDateWaterLogs?.value ?: emptyList()
        val todayMl = app?.habitsRepository?.waterTotalToday?.value ?: waterLogs.sumOf { it.value }
        val goalMl = app?.habitsRepository?.waterGoal?.value ?: 2000.0
        val progressPercent = if (goalMl > 0) min(todayMl / goalMl, 1.0) else 0.0

        var waterMl = 0.0
        var coffeeMl = 0.0
        var teaMl = 0.0

        for (h in waterLogs) {
            val drink = h.drinkType.lowercase(Locale.ROOT)
            when {
                drink.contains("coffee") || drink.contains("espresso") -> coffeeMl += h.value
                drink.contains("tea") -> teaMl += h.value
                else -> waterMl += h.value
            }
        }

        val breakdown = mutableListOf<Pair<Double, Int>>()
        if (waterMl > 0) breakdown.add(waterMl to android.graphics.Color.parseColor("#00E5FF"))
        if (coffeeMl > 0) breakdown.add(coffeeMl to android.graphics.Color.parseColor("#F59E0B"))
        if (teaMl > 0) breakdown.add(teaMl to android.graphics.Color.parseColor("#84CC16"))

        val launchIntent = Intent(context, MainActivity::class.java).apply {
            action = "com.intellidream.daily.ACTION_OPEN_HABITS_WATER"
            data = Uri.parse("daily://habits/bubbles")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_TARGET_TAB, MainActivity.TAB_HABITS)
            putExtra(MainActivity.EXTRA_HABIT_SUBTAB, "water")
        }

        provideContent {
            val size = LocalSize.current
            GlanceTheme {
                Box(
                    modifier = GlanceModifier
                        .fillMaxSize()
                        .appWidgetBackground()
                        .background(ImageProvider(R.drawable.widget_background))
                        .cornerRadius(22.dp)
                        .clickable(actionStartActivity(launchIntent))
                ) {
                    when {
                        size.width >= 200.dp && size.height >= 215.dp -> LargeBubblesLayout(
                            todayMl = todayMl,
                            goalMl = goalMl,
                            progressPercent = progressPercent,
                            waterMl = waterMl,
                            coffeeMl = coffeeMl,
                            teaMl = teaMl,
                            breakdown = breakdown
                        )
                        size.width >= 200.dp -> MediumBubblesLayout(
                            todayMl = todayMl,
                            goalMl = goalMl,
                            progressPercent = progressPercent,
                            waterMl = waterMl,
                            coffeeMl = coffeeMl,
                            teaMl = teaMl,
                            breakdown = breakdown
                        )
                        else -> SmallBubblesLayout(
                            size = size,
                            todayMl = todayMl,
                            goalMl = goalMl,
                            progressPercent = progressPercent,
                            breakdown = breakdown
                        )
                    }
                }
            }
        }
    }

    // =========================================================================
    // MARK: - 1. SMALL LAYOUT (systemSmall: 2x2)
    // =========================================================================
    @androidx.compose.runtime.Composable
    private fun SmallBubblesLayout(
        size: DpSize,
        todayMl: Double,
        goalMl: Double,
        progressPercent: Double,
        breakdown: List<Pair<Double, Int>>
    ) {
        val ringSize = 72.dp
        val ringBitmap = WidgetVisualGraphics.createMultiDrinkArcBitmap(
            sizePx = 180,
            todayMl = todayMl,
            goalMl = goalMl,
            breakdown = breakdown,
            strokeWidthPx = 16f
        )
        val watermarkBitmap = WidgetVisualGraphics.createVectorIconBitmap(
            icon = WidgetIconType.DROP,
            sizePx = 120,
            colorInt = android.graphics.Color.parseColor("#00E5FF"),
            opacity = 0.07f
        )

        Box(modifier = GlanceModifier.fillMaxSize()) {
            // Trailing Subtle Watermark Drop
            Box(
                modifier = GlanceModifier.fillMaxSize().padding(end = 2.dp),
                contentAlignment = Alignment.CenterEnd
            ) {
                Image(
                    provider = ImageProvider(watermarkBitmap),
                    contentDescription = null,
                    modifier = GlanceModifier.size(46.dp)
                )
            }

            // Foreground Content
            Column(
                modifier = GlanceModifier.fillMaxSize().padding(start = 12.dp, end = 12.dp, top = 10.dp, bottom = 12.dp)
            ) {
                // Top Section: Circle Hero on Left, Percentage in Top-Right
                Row(
                    modifier = GlanceModifier.fillMaxWidth(),
                    verticalAlignment = Alignment.Top
                ) {
                    Box(
                        modifier = GlanceModifier.size(ringSize),
                        contentAlignment = Alignment.Center
                    ) {
                        Image(
                            provider = ImageProvider(ringBitmap),
                            contentDescription = null,
                            modifier = GlanceModifier.fillMaxSize()
                        )
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            Text(
                                text = "${todayMl.toInt()}",
                                style = TextStyle(
                                    color = ColorProvider(Color.White),
                                    fontSize = 17.sp,
                                    fontWeight = FontWeight.Bold
                                )
                            )
                            Text(
                                text = "/ ${goalMl.toInt()} ml",
                                style = TextStyle(
                                    color = ColorProvider(Color(0x99FFFFFF)),
                                    fontSize = 9.5.sp,
                                    fontWeight = FontWeight.Medium
                                )
                            )
                        }
                    }

                    Spacer(modifier = GlanceModifier.defaultWeight())

                    // Top-Right: Percentage Pill
                    Box(
                        modifier = GlanceModifier
                            .background(Color(0x2E00E5FF))
                            .cornerRadius(10.dp)
                            .padding(horizontal = 5.5.dp, vertical = 2.5.dp)
                    ) {
                        Text(
                            text = "${(progressPercent * 100).toInt()}%",
                            style = TextStyle(
                                color = ColorProvider(Color(0xFF00E5FF)),
                                fontSize = 9.5.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                    }
                }

                Spacer(modifier = GlanceModifier.defaultWeight())

                // Bottom 3 Quick Action Buttons: 100 (Coffee), 150 (Water), 300 (Water)
                Row(
                    modifier = GlanceModifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    WaterActionButton(
                        label = "100",
                        amount = 100.0,
                        drinkType = "Coffee",
                        color = Color(0xFFF59E0B),
                        height = 26.dp,
                        modifier = GlanceModifier.defaultWeight()
                    )
                    Spacer(modifier = GlanceModifier.width(4.dp))
                    WaterActionButton(
                        label = "150",
                        amount = 150.0,
                        drinkType = "Water",
                        color = Color(0xFF00E5FF),
                        height = 26.dp,
                        modifier = GlanceModifier.defaultWeight()
                    )
                    Spacer(modifier = GlanceModifier.width(4.dp))
                    WaterActionButton(
                        label = "300",
                        amount = 300.0,
                        drinkType = "Water",
                        color = Color(0xFF00E5FF),
                        height = 26.dp,
                        modifier = GlanceModifier.defaultWeight()
                    )
                }
            }
        }
    }

    // =========================================================================
    // MARK: - 2. MEDIUM LAYOUT (systemMedium: 4x2)
    // =========================================================================
    @androidx.compose.runtime.Composable
    private fun MediumBubblesLayout(
        todayMl: Double,
        goalMl: Double,
        progressPercent: Double,
        waterMl: Double,
        coffeeMl: Double,
        teaMl: Double,
        breakdown: List<Pair<Double, Int>>
    ) {
        val ringBitmap = WidgetVisualGraphics.createMultiDrinkArcBitmap(
            sizePx = 230,
            todayMl = todayMl,
            goalMl = goalMl,
            breakdown = breakdown,
            strokeWidthPx = 18f
        )
        val dropIcon = WidgetVisualGraphics.createVectorIconBitmap(
            icon = WidgetIconType.DROP,
            sizePx = 36,
            colorInt = android.graphics.Color.parseColor("#00E5FF")
        )

        Row(
            modifier = GlanceModifier.fillMaxSize().padding(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Left Hero: 92x92 Circle
            Box(
                modifier = GlanceModifier.size(92.dp),
                contentAlignment = Alignment.Center
            ) {
                Image(
                    provider = ImageProvider(ringBitmap),
                    contentDescription = null,
                    modifier = GlanceModifier.fillMaxSize()
                )
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(
                        text = "${todayMl.toInt()}",
                        style = TextStyle(
                            color = ColorProvider(Color.White),
                            fontSize = 21.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                    Text(
                        text = "of ${goalMl.toInt()} ml",
                        style = TextStyle(
                            color = ColorProvider(Color(0x80FFFFFF)),
                            fontSize = 9.5.sp,
                            fontWeight = FontWeight.Medium
                        )
                    )
                }
            }

            Spacer(modifier = GlanceModifier.width(14.dp))

            // Right Column: Header, Breakdown, and 2x2 Buttons Grid
            Column(
                modifier = GlanceModifier.defaultWeight().fillMaxHeight()
            ) {
                // Top Row: Percentage on left, Drop icon on right
                Row(
                    modifier = GlanceModifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "${(progressPercent * 100).toInt()}%",
                        style = TextStyle(
                            color = ColorProvider(Color(0xFF00E5FF)),
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                    Spacer(modifier = GlanceModifier.defaultWeight())
                    Image(
                        provider = ImageProvider(dropIcon),
                        contentDescription = null,
                        modifier = GlanceModifier.size(13.dp)
                    )
                }

                Spacer(modifier = GlanceModifier.height(3.dp))

                // Breakdown Pills
                Row(
                    modifier = GlanceModifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "${waterMl.toInt()} ml",
                        style = TextStyle(
                            color = ColorProvider(Color(0xFF00E5FF)),
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                    if (coffeeMl > 0) {
                        Spacer(modifier = GlanceModifier.width(8.dp))
                        Text(
                            text = "${coffeeMl.toInt()} ml",
                            style = TextStyle(
                                color = ColorProvider(Color(0xFFF59E0B)),
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                    }
                    if (teaMl > 0) {
                        Spacer(modifier = GlanceModifier.width(8.dp))
                        Text(
                            text = "${teaMl.toInt()} ml",
                            style = TextStyle(
                                color = ColorProvider(Color(0xFF84CC16)),
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                    }
                }

                Spacer(modifier = GlanceModifier.defaultWeight())

                // 2x2 Action Buttons Grid: 300 & 150 (top), 100 & 200 (bottom)
                Column(modifier = GlanceModifier.fillMaxWidth()) {
                    Row(modifier = GlanceModifier.fillMaxWidth()) {
                        WaterActionButton("300", 300.0, "Water", Color(0xFF00E5FF), 24.dp, GlanceModifier.defaultWeight())
                        Spacer(modifier = GlanceModifier.width(6.dp))
                        WaterActionButton("150", 150.0, "Water", Color(0xFF00E5FF), 24.dp, GlanceModifier.defaultWeight())
                    }
                    Spacer(modifier = GlanceModifier.height(4.dp))
                    Row(modifier = GlanceModifier.fillMaxWidth()) {
                        WaterActionButton("100", 100.0, "Coffee", Color(0xFFF59E0B), 24.dp, GlanceModifier.defaultWeight())
                        Spacer(modifier = GlanceModifier.width(6.dp))
                        WaterActionButton("200", 200.0, "Tea", Color(0xFF84CC16), 24.dp, GlanceModifier.defaultWeight())
                    }
                }
            }
        }
    }

    // =========================================================================
    // MARK: - 3. LARGE LAYOUT (systemLarge: 4x4)
    // =========================================================================
    @androidx.compose.runtime.Composable
    private fun LargeBubblesLayout(
        todayMl: Double,
        goalMl: Double,
        progressPercent: Double,
        waterMl: Double,
        coffeeMl: Double,
        teaMl: Double,
        breakdown: List<Pair<Double, Int>>
    ) {
        val ringBitmap = WidgetVisualGraphics.createMultiDrinkArcBitmap(
            sizePx = 280,
            todayMl = todayMl,
            goalMl = goalMl,
            breakdown = breakdown,
            strokeWidthPx = 22f
        )
        val dropIcon = WidgetVisualGraphics.createVectorIconBitmap(
            icon = WidgetIconType.DROP,
            sizePx = 50,
            colorInt = android.graphics.Color.parseColor("#00E5FF")
        )

        Column(
            modifier = GlanceModifier.fillMaxSize().padding(14.dp)
        ) {
            // Header: Drop Icon + Percentage Goal Badge
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Image(
                    provider = ImageProvider(dropIcon),
                    contentDescription = null,
                    modifier = GlanceModifier.size(20.dp)
                )

                Spacer(modifier = GlanceModifier.defaultWeight())

                Box(
                    modifier = GlanceModifier
                        .background(Color(0x2400E676))
                        .cornerRadius(12.dp)
                        .padding(horizontal = 8.dp, vertical = 4.dp)
                ) {
                    Text(
                        text = "${(progressPercent * 100).toInt()}% Goal",
                        style = TextStyle(
                            color = ColorProvider(Color(0xFF00E676)),
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                }
            }

            Spacer(modifier = GlanceModifier.height(10.dp))

            // Hero Gauge & Detailed Breakdown Row
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // 118x118 Gauge
                Box(
                    modifier = GlanceModifier.size(118.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Image(
                        provider = ImageProvider(ringBitmap),
                        contentDescription = null,
                        modifier = GlanceModifier.fillMaxSize()
                    )
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text(
                            text = "${todayMl.toInt()}",
                            style = TextStyle(
                                color = ColorProvider(Color.White),
                                fontSize = 24.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                        Text(
                            text = "of ${goalMl.toInt()} ml",
                            style = TextStyle(
                                color = ColorProvider(Color(0x8CFFFFFF)),
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Medium
                            )
                        )
                    }
                }

                Spacer(modifier = GlanceModifier.width(16.dp))

                // Breakdown Column
                Column(
                    modifier = GlanceModifier.defaultWeight()
                ) {
                    Column {
                        Text(
                            text = "WATER",
                            style = TextStyle(color = ColorProvider(Color(0x73FFFFFF)), fontSize = 8.5.sp, fontWeight = FontWeight.Bold)
                        )
                        Text(
                            text = "${waterMl.toInt()} ml",
                            style = TextStyle(color = ColorProvider(Color(0xFF00E5FF)), fontSize = 14.sp, fontWeight = FontWeight.Bold)
                        )
                    }

                    if (coffeeMl > 0) {
                        Spacer(modifier = GlanceModifier.height(4.dp))
                        Column {
                            Text(
                                text = "COFFEE",
                                style = TextStyle(color = ColorProvider(Color(0x73FFFFFF)), fontSize = 8.5.sp, fontWeight = FontWeight.Bold)
                            )
                            Text(
                                text = "${coffeeMl.toInt()} ml",
                                style = TextStyle(color = ColorProvider(Color(0xFFF59E0B)), fontSize = 14.sp, fontWeight = FontWeight.Bold)
                            )
                        }
                    }

                    Spacer(modifier = GlanceModifier.height(4.dp))

                    val remaining = max(0.0, goalMl - todayMl)
                    val remainingText = if (remaining > 0) "${remaining.toInt()} ml remaining" else "Goal completed 🎉"
                    val remainingColor = if (remaining > 0) Color(0xA6FFFFFF) else Color(0xFF00E676)
                    Text(
                        text = remainingText,
                        style = TextStyle(
                            color = ColorProvider(remainingColor),
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Medium
                        )
                    )
                }
            }

            Spacer(modifier = GlanceModifier.defaultWeight())

            // Divider
            Box(
                modifier = GlanceModifier
                    .fillMaxWidth()
                    .height(1.dp)
                    .background(Color(0x1FFFFFFF))
            ) {}

            Spacer(modifier = GlanceModifier.height(10.dp))

            // Row of 4 Buttons: 300, 150, 100, 200
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                WaterActionButton("300", 300.0, "Water", Color(0xFF00E5FF), 34.dp, GlanceModifier.defaultWeight())
                Spacer(modifier = GlanceModifier.width(8.dp))
                WaterActionButton("150", 150.0, "Water", Color(0xFF00E5FF), 34.dp, GlanceModifier.defaultWeight())
                Spacer(modifier = GlanceModifier.width(8.dp))
                WaterActionButton("100", 100.0, "Coffee", Color(0xFFF59E0B), 34.dp, GlanceModifier.defaultWeight())
                Spacer(modifier = GlanceModifier.width(8.dp))
                WaterActionButton("200", 200.0, "Tea", Color(0xFF84CC16), 34.dp, GlanceModifier.defaultWeight())
            }
        }
    }

    // =========================================================================
    // MARK: - Action Button Component
    // =========================================================================
    @androidx.compose.runtime.Composable
    private fun WaterActionButton(
        label: String,
        amount: Double,
        drinkType: String,
        color: Color,
        height: androidx.compose.ui.unit.Dp,
        modifier: GlanceModifier = GlanceModifier
    ) {
        val bgTint = color.copy(alpha = 0.14f)
        Box(
            modifier = modifier
                .height(height)
                .background(bgTint)
                .cornerRadius(height / 2)
                .clickable(
                    actionRunCallback<LogWaterActionCallback>(
                        actionParametersOf(
                            LogWaterActionCallback.AmountKey to amount,
                            LogWaterActionCallback.DrinkKey to drinkType
                        )
                    )
                ),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = label,
                style = TextStyle(
                    color = ColorProvider(color),
                    fontSize = if (height >= 30.dp) 12.sp else 11.sp,
                    fontWeight = FontWeight.Bold
                )
            )
        }
    }
}
