package com.intellidream.daily.glance

import android.content.Context
import android.content.Intent
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

class DailySmokesGlanceReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = DailySmokesGlanceWidget()
}

class DailySmokesGlanceWidget : GlanceAppWidget() {

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
        val smokesLogs = app?.habitsRepository?.selectedDateSmokesLogs?.value ?: emptyList()
        val todayTotal = app?.habitsRepository?.smokesTotalToday?.value ?: smokesLogs.sumOf { it.value.toInt() }
        val baseline = app?.habitsRepository?.smokesSettings?.value?.baselineDailyCount ?: 20
        val costPerCig = app?.habitsRepository?.smokesSettings?.value?.costPerCig ?: 1.325

        var cigsCount = 0
        var heatedCount = 0
        var rolledCount = 0
        var cigarilloCount = 0
        var lastSmokeDate: Long? = null

        for (h in smokesLogs) {
            val type = h.smokeType.lowercase(Locale.ROOT)
            when {
                type.contains("cigarillo") || type.contains("cgr") -> cigarilloCount += h.value.toInt()
                type.contains("rolled") || type.contains("rol") -> rolledCount += h.value.toInt()
                type.contains("heated") || type.contains("heat") || type.contains("vape") -> heatedCount += h.value.toInt()
                else -> cigsCount += h.value.toInt()
            }
            if (lastSmokeDate == null || h.loggedAt > lastSmokeDate) {
                lastSmokeDate = h.loggedAt
            }
        }
        val spentTodayLei = todayTotal * costPerCig

        val ringColorInt = WidgetVisualGraphics.getSmokeRingColor(todayTotal, baseline)
        val lungColorInt = WidgetVisualGraphics.getLungHealthColor(todayTotal, baseline)
        val formattedTime = WidgetVisualGraphics.formatCompactTimeAgo(lastSmokeDate)

        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_TARGET_TAB, MainActivity.TAB_HABITS)
            putExtra(MainActivity.EXTRA_HABIT_SUBTAB, "smokes")
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
                        size.height >= 180.dp -> LargeSmokesLayout(
                            todayTotal = todayTotal,
                            baseline = baseline,
                            cigsCount = cigsCount,
                            heatedCount = heatedCount,
                            rolledCount = rolledCount,
                            cigarilloCount = cigarilloCount,
                            lastSmokeTime = formattedTime,
                            spentTodayLei = spentTodayLei,
                            ringColorInt = ringColorInt,
                            lungColorInt = lungColorInt
                        )
                        size.width >= 240.dp -> MediumSmokesLayout(
                            todayTotal = todayTotal,
                            baseline = baseline,
                            formattedTime = formattedTime,
                            ringColorInt = ringColorInt,
                            lungColorInt = lungColorInt
                        )
                        else -> SmallSmokesLayout(
                            todayTotal = todayTotal,
                            baseline = baseline,
                            formattedTime = formattedTime,
                            ringColorInt = ringColorInt
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
    private fun SmallSmokesLayout(
        todayTotal: Int,
        baseline: Int,
        formattedTime: String,
        ringColorInt: Int
    ) {
        val progress = if (baseline > 0) min(todayTotal.toFloat() / baseline.toFloat(), 1f) else 0f
        val ringBitmap = WidgetVisualGraphics.createCircularProgressRingBitmap(
            sizePx = 180,
            progress = progress,
            ringColorInt = ringColorInt,
            startColorInt = android.graphics.Color.parseColor("#00E676"),
            strokeWidthPx = 16f
        )
        val watermarkBitmap = WidgetVisualGraphics.createVectorIconBitmap(
            icon = WidgetIconType.FLAME,
            sizePx = 140,
            colorInt = ringColorInt,
            opacity = 0.14f
        )

        Box(modifier = GlanceModifier.fillMaxSize()) {
            // Trailing Watermark Flame
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
                // Top Section: Circle Hero on Left, Elapsed Time in Top-Right
                Row(
                    modifier = GlanceModifier.fillMaxWidth(),
                    verticalAlignment = Alignment.Top
                ) {
                    Box(
                        modifier = GlanceModifier.size(72.dp),
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
                                text = "$todayTotal",
                                style = TextStyle(
                                    color = ColorProvider(Color.White),
                                    fontSize = 17.sp,
                                    fontWeight = FontWeight.Bold
                                )
                            )
                            Text(
                                text = "/ $baseline",
                                style = TextStyle(
                                    color = ColorProvider(Color(0x99FFFFFF)),
                                    fontSize = 9.5.sp,
                                    fontWeight = FontWeight.Medium
                                )
                            )
                        }
                    }

                    Spacer(modifier = GlanceModifier.defaultWeight())

                    // Top-Right: Elapsed Time Pill
                    Box(
                        modifier = GlanceModifier
                            .background(Color(0x1FFFFFFF))
                            .cornerRadius(12.dp)
                            .padding(horizontal = 6.dp, vertical = 2.5.dp)
                    ) {
                        Text(
                            text = formattedTime,
                            style = TextStyle(
                                color = ColorProvider(Color(0xE6FFFFFF)),
                                fontSize = 9.5.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                    }
                }

                Spacer(modifier = GlanceModifier.defaultWeight())

                // Bottom 2 Quick Action Buttons: Cig & Heat
                Row(
                    modifier = GlanceModifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    SmokesActionButton(
                        label = "Cig",
                        color = Color(0xFFEF4444),
                        smokeType = "Cigarette",
                        height = 26.dp,
                        modifier = GlanceModifier.defaultWeight()
                    )
                    Spacer(modifier = GlanceModifier.width(4.dp))
                    SmokesActionButton(
                        label = "Heat",
                        color = Color(0xFF3B82F6),
                        smokeType = "Heated",
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
    private fun MediumSmokesLayout(
        todayTotal: Int,
        baseline: Int,
        formattedTime: String,
        ringColorInt: Int,
        lungColorInt: Int
    ) {
        val progress = if (baseline > 0) min(todayTotal.toFloat() / baseline.toFloat(), 1f) else 0f
        val ringBitmap = WidgetVisualGraphics.createCircularProgressRingBitmap(
            sizePx = 215,
            progress = progress,
            ringColorInt = ringColorInt,
            strokeWidthPx = 18f
        )
        val lungsBitmap = WidgetVisualGraphics.createVectorLungsBitmap(
            widthPx = 80,
            heightPx = 80,
            lungColorInt = lungColorInt
        )
        val flameIcon = WidgetVisualGraphics.createVectorIconBitmap(
            icon = WidgetIconType.FLAME,
            sizePx = 36,
            colorInt = ringColorInt
        )

        Row(
            modifier = GlanceModifier.fillMaxSize().padding(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Left Hero: 86x86 Circle with Anatomical Lungs and Count Below
            Box(
                modifier = GlanceModifier.size(86.dp),
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
                    Image(
                        provider = ImageProvider(lungsBitmap),
                        contentDescription = null,
                        modifier = GlanceModifier.size(32.dp)
                    )
                    Spacer(modifier = GlanceModifier.height(1.dp))
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

            Spacer(modifier = GlanceModifier.width(14.dp))

            // Right Column: Header (Base · Time · Flame) & 2x2 Buttons Grid
            Column(
                modifier = GlanceModifier.defaultWeight().fillMaxHeight()
            ) {
                // Header Row
                Row(
                    modifier = GlanceModifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            text = "$baseline",
                            style = TextStyle(
                                color = ColorProvider(Color.White),
                                fontSize = 13.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                        Spacer(modifier = GlanceModifier.width(2.dp))
                        Text(
                            text = "base",
                            style = TextStyle(
                                color = ColorProvider(Color(0x80FFFFFF)),
                                fontSize = 9.5.sp,
                                fontWeight = FontWeight.Medium
                            )
                        )
                    }

                    Text(
                        text = " · ",
                        style = TextStyle(
                            color = ColorProvider(Color(0x4DFFFFFF)),
                            fontSize = 10.sp
                        )
                    )

                    Text(
                        text = formattedTime,
                        style = TextStyle(
                            color = ColorProvider(Color(0xA6FFFFFF)),
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )

                    Spacer(modifier = GlanceModifier.defaultWeight())

                    Image(
                        provider = ImageProvider(flameIcon),
                        contentDescription = null,
                        modifier = GlanceModifier.size(13.dp)
                    )
                }

                Spacer(modifier = GlanceModifier.defaultWeight())

                // 2x2 Action Buttons Grid
                Column(modifier = GlanceModifier.fillMaxWidth()) {
                    Row(modifier = GlanceModifier.fillMaxWidth()) {
                        SmokesActionButton(
                            label = "Cgr",
                            color = Color(0xFFA855F7),
                            smokeType = "Cgr",
                            height = 24.dp,
                            modifier = GlanceModifier.defaultWeight()
                        )
                        Spacer(modifier = GlanceModifier.width(6.dp))
                        SmokesActionButton(
                            label = "Rol",
                            color = Color(0xFFF97316),
                            smokeType = "Rol",
                            height = 24.dp,
                            modifier = GlanceModifier.defaultWeight()
                        )
                    }
                    Spacer(modifier = GlanceModifier.height(4.dp))
                    Row(modifier = GlanceModifier.fillMaxWidth()) {
                        SmokesActionButton(
                            label = "Cig",
                            color = Color(0xFFEF4444),
                            smokeType = "Cigarette",
                            height = 24.dp,
                            modifier = GlanceModifier.defaultWeight()
                        )
                        Spacer(modifier = GlanceModifier.width(6.dp))
                        SmokesActionButton(
                            label = "Heat",
                            color = Color(0xFF3B82F6),
                            smokeType = "Heated",
                            height = 24.dp,
                            modifier = GlanceModifier.defaultWeight()
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
    private fun LargeSmokesLayout(
        todayTotal: Int,
        baseline: Int,
        cigsCount: Int,
        heatedCount: Int,
        rolledCount: Int,
        cigarilloCount: Int,
        lastSmokeTime: String,
        spentTodayLei: Double,
        ringColorInt: Int,
        lungColorInt: Int
    ) {
        val progress = if (baseline > 0) min(todayTotal.toFloat() / baseline.toFloat(), 1f) else 0f
        val ringBitmap = WidgetVisualGraphics.createCircularProgressRingBitmap(
            sizePx = 270,
            progress = progress,
            ringColorInt = ringColorInt,
            strokeWidthPx = 24f
        )
        val lungsBitmap = WidgetVisualGraphics.createVectorLungsBitmap(
            widthPx = 110,
            heightPx = 110,
            lungColorInt = lungColorInt
        )
        val flameIcon = WidgetVisualGraphics.createVectorIconBitmap(
            icon = WidgetIconType.FLAME,
            sizePx = 50,
            colorInt = ringColorInt
        )

        Column(
            modifier = GlanceModifier.fillMaxSize().padding(14.dp)
        ) {
            // Header: Large Flame Icon + Baseline Badge
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Image(
                    provider = ImageProvider(flameIcon),
                    contentDescription = null,
                    modifier = GlanceModifier.size(20.dp)
                )

                Spacer(modifier = GlanceModifier.defaultWeight())

                Box(
                    modifier = GlanceModifier
                        .background(Color(0x14FFFFFF))
                        .cornerRadius(12.dp)
                        .padding(horizontal = 8.dp, vertical = 4.dp)
                ) {
                    Text(
                        text = "Base: $baseline",
                        style = TextStyle(
                            color = ColorProvider(Color(0xA6FFFFFF)),
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                }
            }

            Spacer(modifier = GlanceModifier.height(10.dp))

            // Hero Lungs & Key Telemetry Row
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // 108x108 Gauge with 44x44 Lungs
                Box(
                    modifier = GlanceModifier.size(108.dp),
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
                        Image(
                            provider = ImageProvider(lungsBitmap),
                            contentDescription = null,
                            modifier = GlanceModifier.size(44.dp)
                        )
                        Spacer(modifier = GlanceModifier.height(2.dp))
                        Text(
                            text = "$todayTotal",
                            style = TextStyle(
                                color = ColorProvider(Color.White),
                                fontSize = 20.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                    }
                }

                Spacer(modifier = GlanceModifier.width(16.dp))

                // Telemetry Details
                Column(
                    modifier = GlanceModifier.defaultWeight()
                ) {
                    Row(modifier = GlanceModifier.fillMaxWidth()) {
                        TelemetryColumn("CIG", "$cigsCount", Color(0xFFEF4444), GlanceModifier.defaultWeight())
                        TelemetryColumn("HEAT", "$heatedCount", Color(0xFF3B82F6), GlanceModifier.defaultWeight())
                        TelemetryColumn("ROL", "$rolledCount", Color(0xFFF97316), GlanceModifier.defaultWeight())
                        TelemetryColumn("CGR", "$cigarilloCount", Color(0xFFA855F7), GlanceModifier.defaultWeight())
                    }

                    Spacer(modifier = GlanceModifier.height(8.dp))

                    Text(
                        text = "Last smoke: $lastSmokeTime",
                        style = TextStyle(
                            color = ColorProvider(Color(0xB3FFFFFF)),
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Medium
                        )
                    )

                    Spacer(modifier = GlanceModifier.height(2.dp))

                    Text(
                        text = String.format("Spent: %.2f Lei", spentTodayLei),
                        style = TextStyle(
                            color = ColorProvider(Color(0xE6FFFFFF)),
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold
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

            // 4-Button Action Grid Row
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                SmokesActionButton("Cgr", Color(0xFFA855F7), "Cgr", 34.dp, GlanceModifier.defaultWeight())
                Spacer(modifier = GlanceModifier.width(8.dp))
                SmokesActionButton("Rol", Color(0xFFF97316), "Rol", 34.dp, GlanceModifier.defaultWeight())
                Spacer(modifier = GlanceModifier.width(8.dp))
                SmokesActionButton("Cig", Color(0xFFEF4444), "Cigarette", 34.dp, GlanceModifier.defaultWeight())
                Spacer(modifier = GlanceModifier.width(8.dp))
                SmokesActionButton("Heat", Color(0xFF3B82F6), "Heated", 34.dp, GlanceModifier.defaultWeight())
            }
        }
    }

    // =========================================================================
    // MARK: - Action Button Component
    // =========================================================================
    @androidx.compose.runtime.Composable
    private fun SmokesActionButton(
        label: String,
        color: Color,
        smokeType: String,
        height: androidx.compose.ui.unit.Dp,
        modifier: GlanceModifier = GlanceModifier
    ) {
        val bgTint = color.copy(alpha = 0.15f)
        Box(
            modifier = modifier
                .height(height)
                .background(bgTint)
                .cornerRadius(height / 2)
                .clickable(
                    actionRunCallback<LogSmokeActionCallback>(
                        actionParametersOf(LogSmokeActionCallback.SmokeTypeKey to smokeType)
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

    @androidx.compose.runtime.Composable
    private fun TelemetryColumn(
        header: String,
        value: String,
        color: Color,
        modifier: GlanceModifier
    ) {
        Column(modifier = modifier) {
            Text(
                text = header,
                style = TextStyle(
                    color = ColorProvider(Color(0x73FFFFFF)),
                    fontSize = 8.5.sp,
                    fontWeight = FontWeight.Bold
                )
            )
            Text(
                text = value,
                style = TextStyle(
                    color = ColorProvider(color),
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Bold
                )
            )
        }
    }
}
