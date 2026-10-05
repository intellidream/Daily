package com.intellidream.daily.glance

import android.content.Context
import android.content.Intent
import android.net.Uri
import java.util.Locale
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
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
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
import com.intellidream.daily.model.HealthMetricType
import kotlin.math.min
import kotlin.math.roundToInt

class DailyStressGlanceReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = DailyStressGlanceWidget()
}

class DailyStressGlanceWidget : GlanceAppWidget() {

    override val sizeMode: SizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val app = runCatching { DailyApp.instance }.getOrNull()
        val hasData = app?.healthRepository?.stressAnalysis?.value != null || (app?.healthRepository?.currentStressScore?.value != null && app?.healthRepository?.currentStressScore?.value!! > 0)
        val rhr = app?.healthRepository?.restingBpm?.value?.takeIf { it > 0.0 }
            ?: (app?.healthRepository?.latestBpm?.value ?: 0.0)
        val hrvMs = app?.healthRepository?.currentVitals?.value?.get(HealthMetricType.HRV_SDNN)?.value?.takeIf { it > 0.0 } ?: 0.0

        val stressScore = if (hasData) (app?.healthRepository?.currentStressScore?.value ?: 0) else 0

        val currentLevel = if (hasData) app?.healthRepository?.currentStressLevel?.value else null
        val levelName = when {
            !hasData -> "No Data"
            currentLevel != null -> currentLevel.displayName
            stressScore > 65 -> "High"
            stressScore > 35 -> "Moderate"
            else -> "Calm"
        }

        val levelColorHex = currentLevel?.hexColor ?: when (levelName) {
            "High" -> "#EF4444"
            "Moderate" -> "#FFB800"
            "Calm" -> "#10B981"
            else -> "#6B7280"
        }
        val levelColor = Color(android.graphics.Color.parseColor(levelColorHex))

        val monkeyEmoji = when (levelName) {
            "High" -> "⚡️"
            "Moderate" -> "🐵"
            "Calm" -> "🧘"
            else -> "—"
        }

        val monkeyMoodTitle = when (levelName) {
            "High" -> "Storm Tamer"
            "Moderate" -> "Focus Chief"
            "Calm" -> "Zen Sage"
            else -> "Resting"
        }

        val adviceSnippet = when (levelName) {
            "High" -> "Deep autonomic breathing helps restore equilibrium."
            "Moderate" -> "Steady rhythm. Stay hydrated and take small breaks."
            "Calm" -> "Parasympathetic tone is optimal. Great restoration."
            else -> "No stress telemetry recorded today."
        }

        val parasympatheticPercent = if (hasData) (100 - stressScore).coerceIn(10, 90) else 50
        val sympatheticPercent = (100 - parasympatheticPercent)

        val launchIntent = Intent(context, MainActivity::class.java).apply {
            action = "com.intellidream.daily.ACTION_OPEN_HEALTH_STRESS"
            data = Uri.parse("daily://health/stress")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_TARGET_TAB, MainActivity.TAB_HEALTH)
            putExtra(MainActivity.EXTRA_HEALTH_SUBTAB, "stress")
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
                        size.width >= 200.dp && size.height >= 215.dp -> LargeStressLayout(
                            stressScore = stressScore,
                            levelName = levelName,
                            levelColor = levelColor,
                            levelColorHex = levelColorHex,
                            monkeyEmoji = monkeyEmoji,
                            monkeyMoodTitle = monkeyMoodTitle,
                            adviceSnippet = adviceSnippet,
                            parasympatheticPercent = parasympatheticPercent,
                            sympatheticPercent = sympatheticPercent,
                            hrvMs = hrvMs,
                            rhr = rhr
                        )
                        size.width >= 200.dp -> MediumStressLayout(
                            stressScore = stressScore,
                            levelName = levelName,
                            levelColor = levelColor,
                            levelColorHex = levelColorHex,
                            monkeyEmoji = monkeyEmoji,
                            monkeyMoodTitle = monkeyMoodTitle,
                            adviceSnippet = adviceSnippet,
                            parasympatheticPercent = parasympatheticPercent,
                            sympatheticPercent = sympatheticPercent,
                            hrvMs = hrvMs,
                            rhr = rhr
                        )
                        else -> SmallStressLayout(
                            size = size,
                            stressScore = stressScore,
                            levelName = levelName,
                            levelColor = levelColor,
                            levelColorHex = levelColorHex,
                            monkeyEmoji = monkeyEmoji,
                            monkeyMoodTitle = monkeyMoodTitle,
                            parasympatheticPercent = parasympatheticPercent,
                            sympatheticPercent = sympatheticPercent,
                            hrvMs = hrvMs
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
    private fun SmallStressLayout(
        size: DpSize,
        stressScore: Int,
        levelName: String,
        levelColor: Color,
        levelColorHex: String,
        monkeyEmoji: String,
        monkeyMoodTitle: String,
        parasympatheticPercent: Int,
        sympatheticPercent: Int,
        hrvMs: Double
    ) {
        val gaugeSize = 50.dp
        val gaugeBitmap = WidgetVisualGraphics.createStressGaugeBitmap(
            sizePx = 130,
            score = stressScore,
            levelColorInt = android.graphics.Color.parseColor(levelColorHex),
            strokeWidthPx = 12f
        )
        val balanceBitmap = WidgetVisualGraphics.createAutonomicBalanceBarBitmap(
            widthPx = 280,
            heightPx = 10,
            parasympatheticPct = parasympatheticPercent,
            sympatheticPct = sympatheticPercent
        )
        val ecgIcon = WidgetVisualGraphics.createVectorIconBitmap(
            icon = WidgetIconType.ECG,
            sizePx = 20,
            colorInt = android.graphics.Color.parseColor("#00E5FF")
        )

        Column(
            modifier = GlanceModifier.fillMaxSize().padding(start = 12.dp, end = 12.dp, top = 10.dp, bottom = 10.dp)
        ) {
            // Header: Monkey + STRESS + Status Pill
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = monkeyEmoji,
                        style = TextStyle(fontSize = 11.sp)
                    )
                    Spacer(modifier = GlanceModifier.width(3.5.dp))
                    Text(
                        text = "STRESS",
                        style = TextStyle(
                            color = ColorProvider(levelColor),
                            fontSize = 8.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                }

                Spacer(modifier = GlanceModifier.defaultWeight())

                Box(
                    modifier = GlanceModifier
                        .background(levelColor.copy(alpha = 0.18f))
                        .cornerRadius(10.dp)
                        .padding(horizontal = 4.5.dp, vertical = 1.5.dp)
                ) {
                    Text(
                        text = levelName,
                        style = TextStyle(
                            color = ColorProvider(levelColor),
                            fontSize = 8.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                }
            }

            Spacer(modifier = GlanceModifier.height(3.dp))

            // Center Circular Score Gauge
            Box(
                modifier = GlanceModifier.fillMaxWidth(),
                contentAlignment = Alignment.Center
            ) {
                Box(
                    modifier = GlanceModifier.size(gaugeSize),
                    contentAlignment = Alignment.Center
                ) {
                    Image(
                        provider = ImageProvider(gaugeBitmap),
                        contentDescription = null,
                        modifier = GlanceModifier.fillMaxSize()
                    )
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text(
                            text = "$stressScore",
                            style = TextStyle(
                                color = ColorProvider(Color.White),
                                fontSize = 16.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                        Text(
                            text = "/100",
                            style = TextStyle(
                                color = ColorProvider(Color(0x80FFFFFF)),
                                fontSize = 8.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                    }
                }
            }

            Spacer(modifier = GlanceModifier.height(3.dp))

            // Autonomic Balance Mini-Bar
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "$parasympatheticPercent% Rest",
                    style = TextStyle(
                        color = ColorProvider(Color(0xFF00E5FF)),
                        fontSize = 7.5.sp,
                        fontWeight = FontWeight.Medium
                    )
                )
                Spacer(modifier = GlanceModifier.defaultWeight())
                Text(
                    text = "$sympatheticPercent% Active",
                    style = TextStyle(
                        color = ColorProvider(Color(0xFFF97316)),
                        fontSize = 7.5.sp,
                        fontWeight = FontWeight.Medium
                    )
                )
            }

            Spacer(modifier = GlanceModifier.height(2.dp))

            Image(
                provider = ImageProvider(balanceBitmap),
                contentDescription = null,
                modifier = GlanceModifier.fillMaxWidth().height(3.dp)
            )

            Spacer(modifier = GlanceModifier.defaultWeight())

            // Bottom Metric: Clean HRV snippet
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Image(
                    provider = ImageProvider(ecgIcon),
                    contentDescription = null,
                    modifier = GlanceModifier.size(8.dp)
                )
                Spacer(modifier = GlanceModifier.width(3.dp))
                Text(
                    text = "${hrvMs.toInt()} ms HRV",
                    style = TextStyle(
                        color = ColorProvider(Color(0xE6FFFFFF)),
                        fontSize = 8.sp,
                        fontWeight = FontWeight.Bold
                    )
                )
            }
        }
    }

    // =========================================================================
    // MARK: - 2. MEDIUM LAYOUT (systemMedium: 4x2)
    // =========================================================================
    @androidx.compose.runtime.Composable
    private fun MediumStressLayout(
        stressScore: Int,
        levelName: String,
        levelColor: Color,
        levelColorHex: String,
        monkeyEmoji: String,
        monkeyMoodTitle: String,
        adviceSnippet: String,
        parasympatheticPercent: Int,
        sympatheticPercent: Int,
        hrvMs: Double,
        rhr: Double
    ) {
        val gaugeBitmap = WidgetVisualGraphics.createStressGaugeBitmap(
            sizePx = 190,
            score = stressScore,
            levelColorInt = android.graphics.Color.parseColor(levelColorHex),
            strokeWidthPx = 16f
        )
        val balanceBitmap = WidgetVisualGraphics.createAutonomicBalanceBarBitmap(
            widthPx = 280,
            heightPx = 10,
            parasympatheticPct = parasympatheticPercent,
            sympatheticPct = sympatheticPercent
        )
        val ecgIcon = WidgetVisualGraphics.createVectorIconBitmap(
            icon = WidgetIconType.ECG,
            sizePx = 20,
            colorInt = android.graphics.Color.parseColor("#00E5FF")
        )
        val heartIcon = WidgetVisualGraphics.createVectorIconBitmap(
            icon = WidgetIconType.HEART,
            sizePx = 20,
            colorInt = android.graphics.Color.parseColor("#EF4444")
        )
        val arrowIcon = WidgetVisualGraphics.createVectorIconBitmap(
            icon = WidgetIconType.ARROW_RIGHT,
            sizePx = 20,
            colorInt = android.graphics.Color.parseColor("#00E5FF")
        )

        Row(
            modifier = GlanceModifier.fillMaxSize().padding(11.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Left Column (width 118.dp): Mascot + Gauge + Autonomic Balance
            Column(
                modifier = GlanceModifier.width(118.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                // Header
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(text = monkeyEmoji, style = TextStyle(fontSize = 13.sp))
                    Spacer(modifier = GlanceModifier.width(4.dp))
                    Box(
                        modifier = GlanceModifier
                            .background(levelColor.copy(alpha = 0.18f))
                            .cornerRadius(10.dp)
                            .padding(horizontal = 6.dp, vertical = 2.dp)
                    ) {
                        Text(
                            text = levelName,
                            style = TextStyle(
                                color = ColorProvider(levelColor),
                                fontSize = 9.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                    }
                }

                Spacer(modifier = GlanceModifier.height(4.dp))

                // Circular Gauge
                Box(
                    modifier = GlanceModifier.size(74.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Image(
                        provider = ImageProvider(gaugeBitmap),
                        contentDescription = null,
                        modifier = GlanceModifier.fillMaxSize()
                    )
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text(
                            text = "$stressScore",
                            style = TextStyle(
                                color = ColorProvider(Color.White),
                                fontSize = 22.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                        Text(
                            text = "STRESS",
                            style = TextStyle(
                                color = ColorProvider(Color(0x80FFFFFF)),
                                fontSize = 8.5.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                    }
                }

                Spacer(modifier = GlanceModifier.height(4.dp))

                // Autonomic Balance
                Row(
                    modifier = GlanceModifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "Rest $parasympatheticPercent%",
                        style = TextStyle(color = ColorProvider(Color(0xFF00E5FF)), fontSize = 7.5.sp, fontWeight = FontWeight.Medium)
                    )
                    Spacer(modifier = GlanceModifier.defaultWeight())
                    Text(
                        text = "Active $sympatheticPercent%",
                        style = TextStyle(color = ColorProvider(Color(0xFFF97316)), fontSize = 7.5.sp, fontWeight = FontWeight.Medium)
                    )
                }
                Spacer(modifier = GlanceModifier.height(1.dp))
                Image(
                    provider = ImageProvider(balanceBitmap),
                    contentDescription = null,
                    modifier = GlanceModifier.fillMaxWidth().height(3.5.dp)
                )
            }

            Spacer(modifier = GlanceModifier.width(12.dp))

            // Right Column: Biometrics + Wisdom Card + Studio CTA
            Column(
                modifier = GlanceModifier.defaultWeight().fillMaxHeight()
            ) {
                // Biometrics mini pills
                Row(
                    modifier = GlanceModifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(
                        modifier = GlanceModifier
                            .background(Color(0x14FFFFFF))
                            .cornerRadius(10.dp)
                            .padding(horizontal = 6.dp, vertical = 3.dp)
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Image(
                                provider = ImageProvider(ecgIcon),
                                contentDescription = null,
                                modifier = GlanceModifier.size(8.dp)
                            )
                            Spacer(modifier = GlanceModifier.width(3.dp))
                            Text(
                                text = "${hrvMs.toInt()} ms",
                                style = TextStyle(color = ColorProvider(Color.White), fontSize = 9.sp, fontWeight = FontWeight.Bold)
                            )
                        }
                    }

                    Spacer(modifier = GlanceModifier.width(5.dp))

                    Box(
                        modifier = GlanceModifier
                            .background(Color(0x14FFFFFF))
                            .cornerRadius(10.dp)
                            .padding(horizontal = 6.dp, vertical = 3.dp)
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Image(
                                provider = ImageProvider(heartIcon),
                                contentDescription = null,
                                modifier = GlanceModifier.size(8.dp)
                            )
                            Spacer(modifier = GlanceModifier.width(3.dp))
                            Text(
                                text = "${rhr.toInt()} bpm",
                                style = TextStyle(color = ColorProvider(Color.White), fontSize = 9.sp, fontWeight = FontWeight.Bold)
                            )
                        }
                    }
                }

                Spacer(modifier = GlanceModifier.height(6.dp))

                // Monkey Wisdom Card
                Box(
                    modifier = GlanceModifier
                        .fillMaxWidth()
                        .background(Color(0xBF061020))
                        .cornerRadius(10.dp)
                        .padding(8.dp)
                ) {
                    Column {
                        Text(
                            text = monkeyMoodTitle,
                            style = TextStyle(
                                color = ColorProvider(levelColor),
                                fontSize = 9.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                        Spacer(modifier = GlanceModifier.height(2.dp))
                        Text(
                            text = adviceSnippet,
                            style = TextStyle(
                                color = ColorProvider(Color(0xE0FFFFFF)),
                                fontSize = 9.5.sp,
                                fontWeight = FontWeight.Medium
                            )
                        )
                    }
                }

                Spacer(modifier = GlanceModifier.defaultWeight())

                // Footer Prompt
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = "Open Stress Studio",
                        style = TextStyle(
                            color = ColorProvider(Color(0xFF00E5FF)),
                            fontSize = 9.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                    Spacer(modifier = GlanceModifier.width(4.dp))
                    Image(
                        provider = ImageProvider(arrowIcon),
                        contentDescription = null,
                        modifier = GlanceModifier.size(7.5.dp)
                    )
                }
            }
        }
    }

    // =========================================================================
    // MARK: - 3. LARGE LAYOUT (systemLarge: 4x4)
    // =========================================================================
    @androidx.compose.runtime.Composable
    private fun LargeStressLayout(
        stressScore: Int,
        levelName: String,
        levelColor: Color,
        levelColorHex: String,
        monkeyEmoji: String,
        monkeyMoodTitle: String,
        adviceSnippet: String,
        parasympatheticPercent: Int,
        sympatheticPercent: Int,
        hrvMs: Double,
        rhr: Double
    ) {
        val gaugeBitmap = WidgetVisualGraphics.createStressGaugeBitmap(
            sizePx = 230,
            score = stressScore,
            levelColorInt = android.graphics.Color.parseColor(levelColorHex),
            strokeWidthPx = 18f
        )
        val balanceBitmap = WidgetVisualGraphics.createAutonomicBalanceBarBitmap(
            widthPx = 320,
            heightPx = 12,
            parasympatheticPct = parasympatheticPercent,
            sympatheticPct = sympatheticPercent
        )
        val ecgIcon = WidgetVisualGraphics.createVectorIconBitmap(
            icon = WidgetIconType.ECG,
            sizePx = 24,
            colorInt = android.graphics.Color.parseColor("#00E5FF")
        )
        val heartIcon = WidgetVisualGraphics.createVectorIconBitmap(
            icon = WidgetIconType.HEART,
            sizePx = 24,
            colorInt = android.graphics.Color.parseColor("#EF4444")
        )
        val arrowIcon = WidgetVisualGraphics.createVectorIconBitmap(
            icon = WidgetIconType.ARROW_RIGHT,
            sizePx = 20,
            colorInt = android.graphics.Color.parseColor("#00E5FF")
        )

        Column(
            modifier = GlanceModifier.fillMaxSize().padding(14.dp)
        ) {
            // Header: Monkey + Title + Level badge
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(text = monkeyEmoji, style = TextStyle(fontSize = 18.sp))
                    Spacer(modifier = GlanceModifier.width(6.dp))
                    Text(
                        text = "AUTONOMIC STRESS STUDIO",
                        style = TextStyle(
                            color = ColorProvider(Color(0xFF00E5FF)),
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                }

                Spacer(modifier = GlanceModifier.defaultWeight())

                Box(
                    modifier = GlanceModifier
                        .background(levelColor.copy(alpha = 0.18f))
                        .cornerRadius(12.dp)
                        .padding(horizontal = 8.dp, vertical = 3.dp)
                ) {
                    Text(
                        text = levelName.uppercase(Locale.ROOT),
                        style = TextStyle(
                            color = ColorProvider(levelColor),
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                }
            }

            Spacer(modifier = GlanceModifier.height(10.dp))

            // Upper Section: 86dp Gauge + Telemetry column
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Circular Gauge
                Box(
                    modifier = GlanceModifier.size(86.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Image(
                        provider = ImageProvider(gaugeBitmap),
                        contentDescription = null,
                        modifier = GlanceModifier.fillMaxSize()
                    )
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(
                            text = "$stressScore",
                            style = TextStyle(
                                color = ColorProvider(Color.White),
                                fontSize = 24.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                        Text(
                            text = "/ 100",
                            style = TextStyle(
                                color = ColorProvider(Color(0x80FFFFFF)),
                                fontSize = 9.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                    }
                }

                Spacer(modifier = GlanceModifier.width(14.dp))

                // Telemetry cards: HRV & Resting HR
                Column(modifier = GlanceModifier.defaultWeight()) {
                    Box(
                        modifier = GlanceModifier
                            .fillMaxWidth()
                            .background(Color(0x14FFFFFF))
                            .cornerRadius(10.dp)
                            .padding(horizontal = 10.dp, vertical = 6.dp)
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Image(provider = ImageProvider(ecgIcon), contentDescription = null, modifier = GlanceModifier.size(12.dp))
                            Spacer(modifier = GlanceModifier.width(6.dp))
                            Text(
                                text = "HRV: ${hrvMs.toInt()} ms",
                                style = TextStyle(color = ColorProvider(Color.White), fontSize = 11.sp, fontWeight = FontWeight.Bold)
                            )
                        }
                    }

                    Spacer(modifier = GlanceModifier.height(6.dp))

                    Box(
                        modifier = GlanceModifier
                            .fillMaxWidth()
                            .background(Color(0x14FFFFFF))
                            .cornerRadius(10.dp)
                            .padding(horizontal = 10.dp, vertical = 6.dp)
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Image(provider = ImageProvider(heartIcon), contentDescription = null, modifier = GlanceModifier.size(12.dp))
                            Spacer(modifier = GlanceModifier.width(6.dp))
                            Text(
                                text = "Resting: ${rhr.toInt()} bpm",
                                style = TextStyle(color = ColorProvider(Color.White), fontSize = 11.sp, fontWeight = FontWeight.Bold)
                            )
                        }
                    }
                }
            }

            Spacer(modifier = GlanceModifier.height(10.dp))

            // Autonomic Balance Section
            Box(
                modifier = GlanceModifier
                    .fillMaxWidth()
                    .background(Color(0x14FFFFFF))
                    .cornerRadius(10.dp)
                    .padding(10.dp)
            ) {
                Column {
                    Row(
                        modifier = GlanceModifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "Parasympathetic $parasympatheticPercent%",
                            style = TextStyle(color = ColorProvider(Color(0xFF00E5FF)), fontSize = 9.sp, fontWeight = FontWeight.Bold)
                        )
                        Spacer(modifier = GlanceModifier.defaultWeight())
                        Text(
                            text = "Sympathetic $sympatheticPercent%",
                            style = TextStyle(color = ColorProvider(Color(0xFFF97316)), fontSize = 9.sp, fontWeight = FontWeight.Bold)
                        )
                    }
                    Spacer(modifier = GlanceModifier.height(4.dp))
                    Image(
                        provider = ImageProvider(balanceBitmap),
                        contentDescription = null,
                        modifier = GlanceModifier.fillMaxWidth().height(5.dp)
                    )
                }
            }

            Spacer(modifier = GlanceModifier.height(8.dp))

            // Monkey Clinical Coach Card
            Box(
                modifier = GlanceModifier
                    .fillMaxWidth()
                    .defaultWeight()
                    .background(Color(0xCC061020))
                    .cornerRadius(10.dp)
                    .padding(10.dp)
            ) {
                Column {
                    Text(
                        text = monkeyMoodTitle,
                        style = TextStyle(color = ColorProvider(levelColor), fontSize = 11.sp, fontWeight = FontWeight.Bold)
                    )
                    Spacer(modifier = GlanceModifier.height(3.dp))
                    Text(
                        text = adviceSnippet,
                        style = TextStyle(color = ColorProvider(Color(0xE0FFFFFF)), fontSize = 10.sp, fontWeight = FontWeight.Medium)
                    )
                }
            }

            Spacer(modifier = GlanceModifier.height(8.dp))

            // Bottom CTA
            Box(
                modifier = GlanceModifier
                    .fillMaxWidth()
                    .height(32.dp)
                    .background(Color(0x2400E5FF))
                    .cornerRadius(16.dp),
                contentAlignment = Alignment.Center
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = "Take a Breath · Open Stress Studio",
                        style = TextStyle(color = ColorProvider(Color(0xFF00E5FF)), fontSize = 11.sp, fontWeight = FontWeight.Bold)
                    )
                    Spacer(modifier = GlanceModifier.width(6.dp))
                    Image(provider = ImageProvider(arrowIcon), contentDescription = null, modifier = GlanceModifier.size(10.dp))
                }
            }
        }
    }
}
