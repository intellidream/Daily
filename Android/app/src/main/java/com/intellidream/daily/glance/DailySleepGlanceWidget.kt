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
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.roundToInt

class DailySleepGlanceReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = DailySleepGlanceWidget()
}

class DailySleepGlanceWidget : GlanceAppWidget() {

    companion object {
        private val SMALL_BOX = DpSize(120.dp, 100.dp)
        private val MEDIUM_BOX = DpSize(240.dp, 100.dp)
        private val LARGE_BOX = DpSize(240.dp, 200.dp)
    }

    override val sizeMode: SizeMode = SizeMode.Responsive(
        setOf(SMALL_BOX, MEDIUM_BOX, LARGE_BOX)
    )

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val app = runCatching { DailyApp.instance }.getOrNull()
        val session = app?.healthRepository?.primarySleepSession?.value
        val hasData = session != null

        val sleepScore = session?.sleepScore ?: 88
        val totalMinutes = if (session != null && session.asleepSeconds > 0) (session.asleepSeconds / 60.0).roundToInt() else (7 * 60 + 42)
        val asleepHours = totalMinutes / 60
        val asleepMins = totalMinutes % 60
        val totalAsleepFormatted = "${asleepHours}h ${asleepMins}m"
        val timeInBedFormatted = "${asleepHours}h ${asleepMins + 34}m"
        val efficiencyPercent = session?.efficiencyPercent ?: 93
        val restorativePercent = session?.restorativePercent ?: 42
        val sleepQualityRating = when {
            sleepScore >= 85 -> "Optimal"
            sleepScore >= 75 -> "Great"
            sleepScore >= 60 -> "Fair"
            else -> "Deficit"
        }

        val timeFormatter = SimpleDateFormat("HH:mm", Locale.getDefault())
        val bedtimeFormatted = if (session != null && session.startTime > 0) timeFormatter.format(Date(session.startTime)) else "23:18"
        val wakeTimeFormatted = if (session != null && session.endTime > 0) timeFormatter.format(Date(session.endTime)) else "07:34"

        val deepSec = session?.deepSeconds?.takeIf { it > 0 } ?: 5400.0
        val remSec = session?.remSeconds?.takeIf { it > 0 } ?: 6120.0
        val lightSec = session?.lightSeconds?.takeIf { it > 0 } ?: 16200.0
        val awakeSec = session?.awakeSeconds?.takeIf { it > 0 } ?: 2080.0

        val deepFormatted = "${(deepSec / 3600).toInt()}h ${((deepSec % 3600) / 60).toInt()}m"
        val remFormatted = "${(remSec / 3600).toInt()}h ${((remSec % 3600) / 60).toInt()}m"
        val lightFormatted = "${(lightSec / 3600).toInt()}h ${((lightSec % 3600) / 60).toInt()}m"
        val awakeFormatted = "${(awakeSec / 60).toInt()}m"

        val restingHr = app?.healthRepository?.restingBpm?.value?.takeIf { it > 0.0 } ?: 58.0
        val hrvMs = 45.0
        val sourceDevice = session?.sourceDevice?.takeIf { it.isNotBlank() } ?: "Pixel Watch"

        val launchIntent = Intent(context, MainActivity::class.java).apply {
            action = "com.intellidream.daily.ACTION_OPEN_HEALTH_SLEEP"
            data = Uri.parse("daily://health/sleep")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_TARGET_TAB, MainActivity.TAB_HEALTH)
            putExtra(MainActivity.EXTRA_HEALTH_SUBTAB, "sleep")
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
                        size.height >= 180.dp -> LargeSleepLayout(
                            sleepScore = sleepScore,
                            totalAsleepFormatted = totalAsleepFormatted,
                            timeInBedFormatted = timeInBedFormatted,
                            efficiencyPercent = efficiencyPercent,
                            restorativePercent = restorativePercent,
                            sleepQualityRating = sleepQualityRating,
                            bedtimeFormatted = bedtimeFormatted,
                            wakeTimeFormatted = wakeTimeFormatted,
                            deepSec = deepSec,
                            remSec = remSec,
                            lightSec = lightSec,
                            awakeSec = awakeSec,
                            deepFormatted = deepFormatted,
                            remFormatted = remFormatted,
                            lightFormatted = lightFormatted,
                            awakeFormatted = awakeFormatted,
                            restingHr = restingHr,
                            hrvMs = hrvMs,
                            sourceDevice = sourceDevice
                        )
                        size.width >= 240.dp -> MediumSleepLayout(
                            sleepScore = sleepScore,
                            totalAsleepFormatted = totalAsleepFormatted,
                            timeInBedFormatted = timeInBedFormatted,
                            efficiencyPercent = efficiencyPercent,
                            restorativePercent = restorativePercent,
                            bedtimeFormatted = bedtimeFormatted,
                            wakeTimeFormatted = wakeTimeFormatted,
                            deepSec = deepSec,
                            remSec = remSec,
                            lightSec = lightSec,
                            awakeSec = awakeSec,
                            deepFormatted = deepFormatted,
                            remFormatted = remFormatted,
                            lightFormatted = lightFormatted,
                            awakeFormatted = awakeFormatted,
                            sourceDevice = sourceDevice
                        )
                        else -> SmallSleepLayout(
                            sleepScore = sleepScore,
                            totalAsleepFormatted = totalAsleepFormatted,
                            bedtimeFormatted = bedtimeFormatted,
                            wakeTimeFormatted = wakeTimeFormatted,
                            efficiencyPercent = efficiencyPercent
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
    private fun SmallSleepLayout(
        sleepScore: Int,
        totalAsleepFormatted: String,
        bedtimeFormatted: String,
        wakeTimeFormatted: String,
        efficiencyPercent: Int
    ) {
        val ringBitmap = WidgetVisualGraphics.createSleepScoreRingBitmap(
            sizePx = 220,
            score = sleepScore,
            strokeWidthPx = 18f
        )
        val watermarkBitmap = WidgetVisualGraphics.createVectorIconBitmap(
            icon = WidgetIconType.MOON_STARS,
            sizePx = 140,
            colorInt = android.graphics.Color.parseColor("#8B5CF6"),
            opacity = 0.14f
        )
        val moonIcon = WidgetVisualGraphics.createVectorIconBitmap(
            icon = WidgetIconType.MOON,
            sizePx = 24,
            colorInt = android.graphics.Color.parseColor("#8B5CF6")
        )
        val sparklesIcon = WidgetVisualGraphics.createVectorIconBitmap(
            icon = WidgetIconType.SPARKLES,
            sizePx = 24,
            colorInt = android.graphics.Color.parseColor("#00E5FF")
        )

        Box(modifier = GlanceModifier.fillMaxSize()) {
            // Trailing Watermark Moon & Stars
            Box(
                modifier = GlanceModifier.fillMaxSize().padding(end = 6.dp),
                contentAlignment = Alignment.CenterEnd
            ) {
                Image(
                    provider = ImageProvider(watermarkBitmap),
                    contentDescription = null,
                    modifier = GlanceModifier.size(59.dp)
                )
            }

            // Foreground Content
            Column(
                modifier = GlanceModifier.fillMaxSize().padding(11.dp)
            ) {
                // Top Section: Radial Score Ring on Left, Sleep Duration in Top-Right
                Row(
                    modifier = GlanceModifier.fillMaxWidth(),
                    verticalAlignment = Alignment.Top
                ) {
                    Box(
                        modifier = GlanceModifier.size(84.dp),
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
                                text = "$sleepScore",
                                style = TextStyle(
                                    color = ColorProvider(Color.White),
                                    fontSize = 22.sp,
                                    fontWeight = FontWeight.Bold
                                )
                            )
                            Text(
                                text = "/ 100",
                                style = TextStyle(
                                    color = ColorProvider(Color(0x99FFFFFF)),
                                    fontSize = 10.sp,
                                    fontWeight = FontWeight.Medium
                                )
                            )
                        }
                    }

                    Spacer(modifier = GlanceModifier.defaultWeight())

                    // Top-Right: Duration Pill
                    Box(
                        modifier = GlanceModifier
                            .background(Color(0x2E8B5CF6))
                            .cornerRadius(12.dp)
                            .padding(horizontal = 5.5.dp, vertical = 2.5.dp)
                    ) {
                        Text(
                            text = totalAsleepFormatted,
                            style = TextStyle(
                                color = ColorProvider(Color(0xFFA855F7)),
                                fontSize = 9.5.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                    }
                }

                Spacer(modifier = GlanceModifier.defaultWeight())

                // Bottom 2 Info Pills: Schedule & Efficiency
                Row(
                    modifier = GlanceModifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // Schedule Pill
                    Box(
                        modifier = GlanceModifier
                            .defaultWeight()
                            .height(24.dp)
                            .background(Color(0x248B5CF6))
                            .cornerRadius(12.dp)
                            .padding(horizontal = 4.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Image(
                                provider = ImageProvider(moonIcon),
                                contentDescription = null,
                                modifier = GlanceModifier.size(8.dp)
                            )
                            Spacer(modifier = GlanceModifier.width(2.dp))
                            Text(
                                text = "$bedtimeFormatted-$wakeTimeFormatted",
                                style = TextStyle(
                                    color = ColorProvider(Color(0xFFA855F7)),
                                    fontSize = 8.5.sp,
                                    fontWeight = FontWeight.Bold
                                )
                            )
                        }
                    }

                    Spacer(modifier = GlanceModifier.width(4.dp))

                    // Efficiency Pill
                    Box(
                        modifier = GlanceModifier
                            .defaultWeight()
                            .height(24.dp)
                            .background(Color(0x2400E5FF))
                            .cornerRadius(12.dp)
                            .padding(horizontal = 4.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Image(
                                provider = ImageProvider(sparklesIcon),
                                contentDescription = null,
                                modifier = GlanceModifier.size(8.dp)
                            )
                            Spacer(modifier = GlanceModifier.width(2.dp))
                            Text(
                                text = "$efficiencyPercent% Eff",
                                style = TextStyle(
                                    color = ColorProvider(Color(0xFF00E5FF)),
                                    fontSize = 9.sp,
                                    fontWeight = FontWeight.Bold
                                )
                            )
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // MARK: - 2. MEDIUM LAYOUT (systemMedium: 4x2)
    // =========================================================================
    @androidx.compose.runtime.Composable
    private fun MediumSleepLayout(
        sleepScore: Int,
        totalAsleepFormatted: String,
        timeInBedFormatted: String,
        efficiencyPercent: Int,
        restorativePercent: Int,
        bedtimeFormatted: String,
        wakeTimeFormatted: String,
        deepSec: Double,
        remSec: Double,
        lightSec: Double,
        awakeSec: Double,
        deepFormatted: String,
        remFormatted: String,
        lightFormatted: String,
        awakeFormatted: String,
        sourceDevice: String
    ) {
        val ringBitmap = WidgetVisualGraphics.createSleepScoreRingBitmap(
            sizePx = 225,
            score = sleepScore,
            strokeWidthPx = 18f
        )
        val hypnogramBitmap = WidgetVisualGraphics.createSleepHypnogramBarBitmap(
            widthPx = 400,
            heightPx = 16,
            deepSec = deepSec,
            remSec = remSec,
            lightSec = lightSec,
            awakeSec = awakeSec
        )
        val moonStarsIcon = WidgetVisualGraphics.createVectorIconBitmap(
            icon = WidgetIconType.MOON_STARS,
            sizePx = 28,
            colorInt = android.graphics.Color.parseColor("#A855F7")
        )
        val watchIcon = WidgetVisualGraphics.createVectorIconBitmap(
            icon = WidgetIconType.APPLE_WATCH,
            sizePx = 24,
            colorInt = android.graphics.Color.argb(130, 255, 255, 255)
        )

        Row(
            modifier = GlanceModifier.fillMaxSize().padding(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Left Hero: 88x88 Radial Sleep Score Ring
            Box(
                modifier = GlanceModifier.size(88.dp),
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
                        text = totalAsleepFormatted,
                        style = TextStyle(
                            color = ColorProvider(Color.White),
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                    Spacer(modifier = GlanceModifier.height(1.dp))
                    Box(
                        modifier = GlanceModifier
                            .background(Color(0x2E00E5FF))
                            .cornerRadius(8.dp)
                            .padding(horizontal = 5.dp, vertical = 1.5.dp)
                    ) {
                        Text(
                            text = "$sleepScore pts",
                            style = TextStyle(
                                color = ColorProvider(Color(0xFF00E5FF)),
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                    }
                }
            }

            Spacer(modifier = GlanceModifier.width(14.dp))

            // Right Column: Telemetry & Hypnogram Architecture
            Column(
                modifier = GlanceModifier.defaultWeight().fillMaxHeight()
            ) {
                // Header Row: Schedule & Restorative Badge
                Row(
                    modifier = GlanceModifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Image(
                            provider = ImageProvider(moonStarsIcon),
                            contentDescription = null,
                            modifier = GlanceModifier.size(9.dp)
                        )
                        Spacer(modifier = GlanceModifier.width(4.dp))
                        Text(
                            text = "$bedtimeFormatted ➔ $wakeTimeFormatted",
                            style = TextStyle(
                                color = ColorProvider(Color(0xE6FFFFFF)),
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                    }

                    Spacer(modifier = GlanceModifier.defaultWeight())

                    Box(
                        modifier = GlanceModifier
                            .background(Color(0x26A855F7))
                            .cornerRadius(10.dp)
                            .padding(horizontal = 5.dp, vertical = 2.dp)
                    ) {
                        Text(
                            text = "$efficiencyPercent% Eff · $restorativePercent% Rest",
                            style = TextStyle(
                                color = ColorProvider(Color(0xFFA855F7)),
                                fontSize = 8.5.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                    }
                }

                Spacer(modifier = GlanceModifier.height(4.dp))

                // Multi-Stage Proportional Bar
                Image(
                    provider = ImageProvider(hypnogramBitmap),
                    contentDescription = null,
                    modifier = GlanceModifier.fillMaxWidth().height(7.dp)
                )

                Spacer(modifier = GlanceModifier.height(4.dp))

                // 4 Mini Stage Metric Capsules
                Row(
                    modifier = GlanceModifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    MiniStagePill("Deep", deepFormatted, Color(0xFF6366F1), GlanceModifier.defaultWeight())
                    Spacer(modifier = GlanceModifier.width(3.dp))
                    MiniStagePill("REM", remFormatted, Color(0xFF8B5CF6), GlanceModifier.defaultWeight())
                    Spacer(modifier = GlanceModifier.width(3.dp))
                    MiniStagePill("Light", lightFormatted, Color(0xFF00E5FF), GlanceModifier.defaultWeight())
                    Spacer(modifier = GlanceModifier.width(3.dp))
                    MiniStagePill("Awake", awakeFormatted, Color(0xFFEF4444), GlanceModifier.defaultWeight())
                }

                Spacer(modifier = GlanceModifier.defaultWeight())

                // In-Bed and Source Row
                Row(
                    modifier = GlanceModifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "$timeInBedFormatted in bed",
                        style = TextStyle(
                            color = ColorProvider(Color(0x80FFFFFF)),
                            fontSize = 9.sp,
                            fontWeight = FontWeight.Medium
                        )
                    )

                    Spacer(modifier = GlanceModifier.defaultWeight())

                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Image(
                            provider = ImageProvider(watchIcon),
                            contentDescription = null,
                            modifier = GlanceModifier.size(8.dp)
                        )
                        Spacer(modifier = GlanceModifier.width(3.dp))
                        Text(
                            text = sourceDevice,
                            style = TextStyle(
                                color = ColorProvider(Color(0x80FFFFFF)),
                                fontSize = 8.5.sp,
                                fontWeight = FontWeight.Medium
                            )
                        )
                    }
                }
            }
        }
    }

    // =========================================================================
    // MARK: - 3. LARGE LAYOUT (systemLarge: 4x4)
    // =========================================================================
    @androidx.compose.runtime.Composable
    private fun LargeSleepLayout(
        sleepScore: Int,
        totalAsleepFormatted: String,
        timeInBedFormatted: String,
        efficiencyPercent: Int,
        restorativePercent: Int,
        sleepQualityRating: String,
        bedtimeFormatted: String,
        wakeTimeFormatted: String,
        deepSec: Double,
        remSec: Double,
        lightSec: Double,
        awakeSec: Double,
        deepFormatted: String,
        remFormatted: String,
        lightFormatted: String,
        awakeFormatted: String,
        restingHr: Double,
        hrvMs: Double,
        sourceDevice: String
    ) {
        val ringBitmap = WidgetVisualGraphics.createSleepScoreRingBitmap(
            sizePx = 240,
            score = sleepScore,
            strokeWidthPx = 20f
        )
        val hypnogramBitmap = WidgetVisualGraphics.createSleepHypnogramBarBitmap(
            widthPx = 600,
            heightPx = 22,
            deepSec = deepSec,
            remSec = remSec,
            lightSec = lightSec,
            awakeSec = awakeSec
        )
        val moonZzzIcon = WidgetVisualGraphics.createVectorIconBitmap(
            icon = WidgetIconType.MOON_ZZZ,
            sizePx = 36,
            colorInt = android.graphics.Color.parseColor("#A855F7")
        )
        val watchIcon = WidgetVisualGraphics.createVectorIconBitmap(
            icon = WidgetIconType.APPLE_WATCH,
            sizePx = 24,
            colorInt = android.graphics.Color.argb(180, 255, 255, 255)
        )
        val heartIcon = WidgetVisualGraphics.createVectorIconBitmap(
            icon = WidgetIconType.HEART,
            sizePx = 24,
            colorInt = android.graphics.Color.parseColor("#EF4444")
        )
        val ecgIcon = WidgetVisualGraphics.createVectorIconBitmap(
            icon = WidgetIconType.ECG,
            sizePx = 24,
            colorInt = android.graphics.Color.parseColor("#00E5FF")
        )
        val sparklesIcon = WidgetVisualGraphics.createVectorIconBitmap(
            icon = WidgetIconType.SPARKLES,
            sizePx = 24,
            colorInt = android.graphics.Color.parseColor("#A855F7")
        )

        Column(
            modifier = GlanceModifier.fillMaxSize().padding(14.dp)
        ) {
            // Header: Title & Device chip + Rating
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Image(
                        provider = ImageProvider(moonZzzIcon),
                        contentDescription = null,
                        modifier = GlanceModifier.size(13.dp)
                    )
                    Spacer(modifier = GlanceModifier.width(6.dp))
                    Text(
                        text = "SLEEP STUDIO",
                        style = TextStyle(
                            color = ColorProvider(Color(0xFFA855F7)),
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                }

                Spacer(modifier = GlanceModifier.defaultWeight())

                // Device Chip
                Box(
                    modifier = GlanceModifier
                        .background(Color(0x1AFFFFFF))
                        .cornerRadius(12.dp)
                        .padding(horizontal = 7.dp, vertical = 2.5.dp)
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Image(
                            provider = ImageProvider(watchIcon),
                            contentDescription = null,
                            modifier = GlanceModifier.size(9.dp)
                        )
                        Spacer(modifier = GlanceModifier.width(4.dp))
                        Text(
                            text = sourceDevice,
                            style = TextStyle(
                                color = ColorProvider(Color(0xBFFFFFFF)),
                                fontSize = 9.sp,
                                fontWeight = FontWeight.Medium
                            )
                        )
                    }
                }

                Spacer(modifier = GlanceModifier.width(6.dp))

                // Rating Capsule
                Box(
                    modifier = GlanceModifier
                        .background(Color(0x2E00E5FF))
                        .cornerRadius(12.dp)
                        .padding(horizontal = 6.dp, vertical = 2.5.dp)
                ) {
                    Text(
                        text = sleepQualityRating,
                        style = TextStyle(
                            color = ColorProvider(Color(0xFF00E5FF)),
                            fontSize = 9.5.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                }
            }

            Spacer(modifier = GlanceModifier.height(10.dp))

            // Hero Row: Score Radial Gauge + Primary Stats
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
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
                            text = "$sleepScore",
                            style = TextStyle(
                                color = ColorProvider(Color.White),
                                fontSize = 26.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                        Text(
                            text = "SCORE",
                            style = TextStyle(
                                color = ColorProvider(Color(0xFF00E5FF)),
                                fontSize = 8.5.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                    }
                }

                Spacer(modifier = GlanceModifier.width(16.dp))

                Column(modifier = GlanceModifier.defaultWeight()) {
                    Text(
                        text = totalAsleepFormatted,
                        style = TextStyle(
                            color = ColorProvider(Color.White),
                            fontSize = 26.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                    Text(
                        text = "$timeInBedFormatted in bed • $efficiencyPercent% efficiency",
                        style = TextStyle(
                            color = ColorProvider(Color(0x99FFFFFF)),
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Medium
                        )
                    )
                    Spacer(modifier = GlanceModifier.height(2.dp))
                    Text(
                        text = "Bed $bedtimeFormatted  ·  Wake $wakeTimeFormatted",
                        style = TextStyle(
                            color = ColorProvider(Color.White),
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                }
            }

            Spacer(modifier = GlanceModifier.height(10.dp))

            // Proportional Stage Architecture Header & Bar
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "STAGE ARCHITECTURE",
                    style = TextStyle(
                        color = ColorProvider(Color(0x73FFFFFF)),
                        fontSize = 9.sp,
                        fontWeight = FontWeight.Bold
                    )
                )
                Spacer(modifier = GlanceModifier.defaultWeight())
                Text(
                    text = "$restorativePercent% Restorative",
                    style = TextStyle(
                        color = ColorProvider(Color(0xFFA855F7)),
                        fontSize = 9.sp,
                        fontWeight = FontWeight.Bold
                    )
                )
            }

            Spacer(modifier = GlanceModifier.height(4.dp))

            Image(
                provider = ImageProvider(hypnogramBitmap),
                contentDescription = null,
                modifier = GlanceModifier.fillMaxWidth().height(10.dp)
            )

            Spacer(modifier = GlanceModifier.height(8.dp))

            // 4-Column Stage Breakdown Grid
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                LargeStageCard("Deep", deepFormatted, "20%", Color(0xFF6366F1), GlanceModifier.defaultWeight())
                Spacer(modifier = GlanceModifier.width(6.dp))
                LargeStageCard("REM", remFormatted, "22%", Color(0xFF8B5CF6), GlanceModifier.defaultWeight())
                Spacer(modifier = GlanceModifier.width(6.dp))
                LargeStageCard("Light", lightFormatted, "58%", Color(0xFF00E5FF), GlanceModifier.defaultWeight())
                Spacer(modifier = GlanceModifier.width(6.dp))
                LargeStageCard("Awake", awakeFormatted, "7%", Color(0xFFEF4444), GlanceModifier.defaultWeight())
            }

            Spacer(modifier = GlanceModifier.defaultWeight())

            // Bottom Nocturnal Vitals Row
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                VitalCard("RESTING HR", "${restingHr.toInt()}", "bpm", heartIcon, Color(0xFFEF4444), GlanceModifier.defaultWeight())
                Spacer(modifier = GlanceModifier.width(6.dp))
                VitalCard("HRV SDNN", "${hrvMs.toInt()}", "ms", ecgIcon, Color(0xFF00E5FF), GlanceModifier.defaultWeight())
                Spacer(modifier = GlanceModifier.width(6.dp))
                VitalCard("RESTORATIVE", "$restorativePercent", "%", sparklesIcon, Color(0xFFA855F7), GlanceModifier.defaultWeight())
            }
        }
    }

    // =========================================================================
    // MARK: - Components
    // =========================================================================
    @androidx.compose.runtime.Composable
    private fun MiniStagePill(
        label: String,
        duration: String,
        color: Color,
        modifier: GlanceModifier
    ) {
        Box(
            modifier = modifier
                .background(Color(0x14FFFFFF))
                .cornerRadius(6.dp)
                .padding(horizontal = 4.dp, vertical = 2.dp)
        ) {
            Column {
                Text(
                    text = label,
                    style = TextStyle(color = ColorProvider(color), fontSize = 7.5.sp, fontWeight = FontWeight.Bold)
                )
                Text(
                    text = duration,
                    style = TextStyle(color = ColorProvider(Color.White), fontSize = 8.5.sp, fontWeight = FontWeight.Bold)
                )
            }
        }
    }

    @androidx.compose.runtime.Composable
    private fun LargeStageCard(
        label: String,
        duration: String,
        percent: String,
        color: Color,
        modifier: GlanceModifier
    ) {
        Box(
            modifier = modifier
                .background(Color(0x14FFFFFF))
                .cornerRadius(8.dp)
                .padding(6.dp)
        ) {
            Column {
                Text(
                    text = label,
                    style = TextStyle(color = ColorProvider(color), fontSize = 9.sp, fontWeight = FontWeight.Bold)
                )
                Text(
                    text = duration,
                    style = TextStyle(color = ColorProvider(Color.White), fontSize = 11.sp, fontWeight = FontWeight.Bold)
                )
                Text(
                    text = percent,
                    style = TextStyle(color = ColorProvider(Color(0x80FFFFFF)), fontSize = 8.5.sp, fontWeight = FontWeight.Medium)
                )
            }
        }
    }

    @androidx.compose.runtime.Composable
    private fun VitalCard(
        title: String,
        value: String,
        unit: String,
        iconBitmap: android.graphics.Bitmap,
        color: Color,
        modifier: GlanceModifier
    ) {
        Box(
            modifier = modifier
                .background(Color(0x14FFFFFF))
                .cornerRadius(8.dp)
                .padding(horizontal = 6.dp, vertical = 4.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Image(
                    provider = ImageProvider(iconBitmap),
                    contentDescription = null,
                    modifier = GlanceModifier.size(10.dp)
                )
                Spacer(modifier = GlanceModifier.width(4.dp))
                Column {
                    Text(
                        text = title,
                        style = TextStyle(color = ColorProvider(Color(0x73FFFFFF)), fontSize = 7.5.sp, fontWeight = FontWeight.Bold)
                    )
                    Text(
                        text = "$value $unit",
                        style = TextStyle(color = ColorProvider(Color.White), fontSize = 10.sp, fontWeight = FontWeight.Bold)
                    )
                }
            }
        }
    }
}
