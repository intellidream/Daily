package com.intellidream.daily.glance

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.action.Action
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
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

data class WidgetPill(
    val id: String,
    val text: String,
    val type: String
)

data class WidgetStream(
    val id: String,
    val title: String,
    val drivingPillId: String?,
    val drivingPillText: String,
    val drivingPillType: String,
    val activePillsCount: Int,
    val reminderTime: String?,
    val pills: List<WidgetPill>
)

class DailyTagdosGlanceReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = DailyTagdosGlanceWidget()
}

class DailyTagdosGlanceWidget : GlanceAppWidget() {

    override val sizeMode: SizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val app = runCatching { DailyApp.instance }.getOrNull()
        val repoStreams = app?.tagdosRepository?.streams?.value ?: emptyList()
        val hhmmFormat = SimpleDateFormat("HH:mm", Locale.getDefault())

        val streams = if (repoStreams.isNotEmpty()) {
            repoStreams.map { s ->
                val pills = s.activePills.map {
                    WidgetPill(
                        id = it.id,
                        text = it.rawText,
                        type = it.type.name.lowercase(Locale.ROOT)
                    )
                }
                val drivingPill = s.drivingPill ?: s.activePills.firstOrNull()
                val driving = drivingPill?.rawText ?: "TAG"
                val drivingType = drivingPill?.type?.name?.lowercase(Locale.ROOT) ?: "standard"
                val candidateTimes = buildList {
                    s.streamReminder?.let { add(hhmmFormat.format(Date(it))) }
                    s.clusters.forEach { c ->
                        c.reminderTime?.let { add(hhmmFormat.format(Date(it))) }
                    }
                }
                WidgetStream(
                    id = s.id,
                    title = s.displayTitle,
                    drivingPillId = drivingPill?.id,
                    drivingPillText = driving,
                    drivingPillType = drivingType,
                    activePillsCount = s.activePills.size,
                    reminderTime = candidateTimes.minOrNull(),
                    pills = pills
                )
            }
        } else {
            val s1 = WidgetStream(
                id = "",
                title = "Daily Ops",
                drivingPillId = null,
                drivingPillText = "MG",
                drivingPillType = "standard",
                activePillsCount = 8,
                reminderTime = "17:30",
                pills = listOf(
                    WidgetPill("", "MG", "standard"),
                    WidgetPill("", "GM", "standard"),
                    WidgetPill("", "TG", "standard"),
                    WidgetPill("", "FSH", "standard"),
                    WidgetPill("", "C\$T", "financial")
                )
            )
            val s2 = WidgetStream(
                id = "",
                title = "Work & Code",
                drivingPillId = null,
                drivingPillText = "WRK",
                drivingPillType = "standard",
                activePillsCount = 4,
                reminderTime = "11:00",
                pills = listOf(
                    WidgetPill("", "WRK", "standard"),
                    WidgetPill("", "PRJ", "standard"),
                    WidgetPill("", "REV", "standard"),
                    WidgetPill("", "MET", "standard")
                )
            )
            listOf(s1, s2)
        }

        val stream1 = streams.firstOrNull()
            ?: WidgetStream("", "Stream 1", null, "TAG", "standard", 0, null, emptyList())
        val stream2 = streams.getOrNull(1)
            ?: WidgetStream("", "Stream 2", null, "TAG", "standard", 0, null, emptyList())
        val totalActivePills = streams.sumOf { it.activePillsCount }
        val nextReminderFormatted = streams.mapNotNull { it.reminderTime }.minOrNull()

        val launchIntent = Intent(context, MainActivity::class.java).apply {
            action = "com.intellidream.daily.ACTION_OPEN_TAGDOS"
            data = Uri.parse("daily://tagdos")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_TARGET_TAB, MainActivity.TAB_TAGDOS)
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
                        size.width >= 200.dp && size.height >= 215.dp -> LargeTagdosLayout(
                            streams = streams,
                            totalActivePills = totalActivePills,
                            nextReminderFormatted = nextReminderFormatted
                        )
                        size.width >= 200.dp -> MediumTagdosLayout(
                            stream1 = stream1,
                            stream2 = stream2
                        )
                        else -> SmallTagdosLayout(
                            stream1 = stream1,
                            totalActivePills = totalActivePills
                        )
                    }
                }
            }
        }
    }

    private fun buildOpenAction(context: Context, streamId: String, pillId: String? = null): Action {
        val uriStr = when {
            streamId.isNotBlank() && !pillId.isNullOrBlank() ->
                "daily://tagdos?streamId=${Uri.encode(streamId)}&pillId=${Uri.encode(pillId)}&edit=1"
            streamId.isNotBlank() ->
                "daily://tagdos?streamId=${Uri.encode(streamId)}"
            else ->
                "daily://tagdos"
        }
        val intent = Intent(context, MainActivity::class.java).apply {
            action = "com.intellidream.daily.ACTION_TAGDOS_${streamId}_${pillId.orEmpty()}"
            data = Uri.parse(uriStr)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_TARGET_TAB, MainActivity.TAB_TAGDOS)
        }
        return actionStartActivity(intent)
    }

    private fun buildQuickAction(streamId: String, pillId: String, actionType: String): Action {
        return actionRunCallback<TagdosPillActionCallback>(
            actionParametersOf(
                TagdosPillActionCallback.StreamIdKey to streamId,
                TagdosPillActionCallback.PillIdKey to pillId,
                TagdosPillActionCallback.ActionKey to actionType
            )
        )
    }

    @androidx.compose.runtime.Composable
    private fun QuickActionButtons(streamId: String, pillId: String, compact: Boolean = false) {
        val boxSize = if (compact) 18.dp else 22.dp
        val fontSize = if (compact) 9.sp else 10.sp
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = GlanceModifier
                    .size(boxSize)
                    .background(Color(0x3300E676))
                    .cornerRadius(9.dp)
                    .clickable(buildQuickAction(streamId, pillId, "done")),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = "✓",
                    style = TextStyle(
                        color = ColorProvider(Color(0xFF00E676)),
                        fontSize = fontSize,
                        fontWeight = FontWeight.Bold
                    )
                )
            }
            Spacer(modifier = GlanceModifier.width(3.dp))
            Box(
                modifier = GlanceModifier
                    .size(boxSize)
                    .background(Color(0x3300E5FF))
                    .cornerRadius(9.dp)
                    .clickable(buildQuickAction(streamId, pillId, "recycle")),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = "↻",
                    style = TextStyle(
                        color = ColorProvider(Color(0xFF00E5FF)),
                        fontSize = fontSize,
                        fontWeight = FontWeight.Bold
                    )
                )
            }
        }
    }

    // =========================================================================
    // MARK: - 1. SMALL LAYOUT (systemSmall: 2x2)
    // =========================================================================
    @androidx.compose.runtime.Composable
    private fun SmallTagdosLayout(
        stream1: WidgetStream,
        totalActivePills: Int
    ) {
        val context = LocalContext.current
        val driving = stream1.drivingPillText
        val nextTags = stream1.pills.drop(1).take(2).joinToString(" ➔ ") { it.text }
        val pillColor = resolvePillColor(stream1.drivingPillType)

        val watermarkBitmap = WidgetVisualGraphics.createVectorIconBitmap(
            icon = WidgetIconType.CHECKLIST,
            sizePx = 120,
            colorInt = android.graphics.Color.parseColor("#A855F7"),
            opacity = 0.06f
        )
        val checklistIcon = WidgetVisualGraphics.createVectorIconBitmap(
            icon = WidgetIconType.CHECKLIST,
            sizePx = 28,
            colorInt = android.graphics.Color.parseColor("#A855F7")
        )
        val starIcon = WidgetVisualGraphics.createVectorIconBitmap(
            icon = WidgetIconType.STAR_FILL,
            sizePx = 20,
            colorInt = android.graphics.Color.parseColor("#FFB800")
        )
        val chevronIcon = WidgetVisualGraphics.createVectorIconBitmap(
            icon = WidgetIconType.CHEVRON_RIGHT,
            sizePx = 20,
            colorInt = android.graphics.Color.parseColor("#00E5FF")
        )

        Box(modifier = GlanceModifier.fillMaxSize()) {
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

            Column(
                modifier = GlanceModifier.fillMaxSize().padding(start = 12.dp, end = 12.dp, top = 10.dp, bottom = 12.dp)
            ) {
                Row(
                    modifier = GlanceModifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Image(
                            provider = ImageProvider(checklistIcon),
                            contentDescription = null,
                            modifier = GlanceModifier.size(11.dp)
                        )
                        Spacer(modifier = GlanceModifier.width(4.dp))
                        Text(
                            text = "Tagdos",
                            style = TextStyle(
                                color = ColorProvider(Color(0xFFA855F7)),
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                    }

                    Spacer(modifier = GlanceModifier.defaultWeight())

                    if (stream1.reminderTime != null) {
                        Box(
                            modifier = GlanceModifier
                                .background(Color(0x2E00E5FF))
                                .cornerRadius(10.dp)
                                .padding(horizontal = 5.dp, vertical = 2.dp)
                        ) {
                            Text(
                                text = stream1.reminderTime,
                                style = TextStyle(
                                    color = ColorProvider(Color(0xFF00E5FF)),
                                    fontSize = 9.sp,
                                    fontWeight = FontWeight.Bold
                                )
                            )
                        }
                    } else {
                        Box(
                            modifier = GlanceModifier
                                .background(Color(0x1AFFFFFF))
                                .cornerRadius(10.dp)
                                .padding(horizontal = 5.dp, vertical = 2.dp)
                        ) {
                            Text(
                                text = "$totalActivePills",
                                style = TextStyle(
                                    color = ColorProvider(Color(0xB3FFFFFF)),
                                    fontSize = 9.sp,
                                    fontWeight = FontWeight.Bold
                                )
                            )
                        }
                    }
                }

                Spacer(modifier = GlanceModifier.defaultWeight())

                Column {
                    Text(
                        text = "FOCUS TAG",
                        style = TextStyle(
                            color = ColorProvider(Color(0x73FFFFFF)),
                            fontSize = 8.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                    Spacer(modifier = GlanceModifier.height(2.dp))
                    Row(
                        modifier = GlanceModifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Box(
                            modifier = GlanceModifier
                                .background(pillColor.copy(alpha = 0.15f))
                                .cornerRadius(10.dp)
                                .clickable(buildOpenAction(context, stream1.id, stream1.drivingPillId))
                                .padding(horizontal = 7.dp, vertical = 3.dp)
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(
                                    text = driving,
                                    style = TextStyle(
                                        color = ColorProvider(pillColor),
                                        fontSize = 16.sp,
                                        fontWeight = FontWeight.Bold
                                    )
                                )
                                Spacer(modifier = GlanceModifier.width(3.dp))
                                Image(
                                    provider = ImageProvider(starIcon),
                                    contentDescription = null,
                                    modifier = GlanceModifier.size(8.dp)
                                )
                            }
                        }

                        Spacer(modifier = GlanceModifier.defaultWeight())

                        if (stream1.id.isNotBlank() && !stream1.drivingPillId.isNullOrBlank()) {
                            QuickActionButtons(streamId = stream1.id, pillId = stream1.drivingPillId)
                        }
                    }

                    if (nextTags.isNotEmpty()) {
                        Spacer(modifier = GlanceModifier.height(3.dp))
                        Text(
                            text = "Next: $nextTags",
                            style = TextStyle(
                                color = ColorProvider(Color(0xA6FFFFFF)),
                                fontSize = 9.sp,
                                fontWeight = FontWeight.Medium
                            )
                        )
                    }
                }

                Spacer(modifier = GlanceModifier.defaultWeight())

                Row(
                    modifier = GlanceModifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "$totalActivePills Active",
                        style = TextStyle(
                            color = ColorProvider(Color(0x99FFFFFF)),
                            fontSize = 8.5.sp,
                            fontWeight = FontWeight.Medium
                        )
                    )
                    Spacer(modifier = GlanceModifier.defaultWeight())
                    Image(
                        provider = ImageProvider(chevronIcon),
                        contentDescription = null,
                        modifier = GlanceModifier.size(8.dp)
                    )
                }
            }
        }
    }

    // =========================================================================
    // MARK: - 2. MEDIUM LAYOUT (systemMedium: 4x2)
    // =========================================================================
    @androidx.compose.runtime.Composable
    private fun MediumTagdosLayout(
        stream1: WidgetStream,
        stream2: WidgetStream
    ) {
        val context = LocalContext.current
        val pillColor = resolvePillColor(stream1.drivingPillType)
        val checklistIcon = WidgetVisualGraphics.createVectorIconBitmap(
            icon = WidgetIconType.CHECKLIST,
            sizePx = 28,
            colorInt = android.graphics.Color.parseColor("#A855F7")
        )
        val bellIcon = WidgetVisualGraphics.createVectorIconBitmap(
            icon = WidgetIconType.BELL,
            sizePx = 20,
            colorInt = android.graphics.Color.parseColor("#00E5FF")
        )

        Row(
            modifier = GlanceModifier.fillMaxSize().padding(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(
                modifier = GlanceModifier.width(104.dp).fillMaxHeight()
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Image(
                        provider = ImageProvider(checklistIcon),
                        contentDescription = null,
                        modifier = GlanceModifier.size(11.dp)
                    )
                    Spacer(modifier = GlanceModifier.width(4.dp))
                    Text(
                        text = "Tagdos",
                        style = TextStyle(
                            color = ColorProvider(Color(0xFFA855F7)),
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                }

                Spacer(modifier = GlanceModifier.height(4.dp))

                Box(
                    modifier = GlanceModifier
                        .background(pillColor.copy(alpha = 0.14f))
                        .cornerRadius(10.dp)
                        .clickable(buildOpenAction(context, stream1.id, stream1.drivingPillId))
                        .padding(horizontal = 8.dp, vertical = 4.dp)
                ) {
                    Column {
                        Text(
                            text = stream1.drivingPillText,
                            style = TextStyle(
                                color = ColorProvider(pillColor),
                                fontSize = 16.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                        Text(
                            text = stream1.title,
                            style = TextStyle(
                                color = ColorProvider(Color(0x8CFFFFFF)),
                                fontSize = 8.5.sp,
                                fontWeight = FontWeight.Medium
                            )
                        )
                    }
                }

                Spacer(modifier = GlanceModifier.defaultWeight())

                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (stream1.id.isNotBlank() && !stream1.drivingPillId.isNullOrBlank()) {
                        QuickActionButtons(streamId = stream1.id, pillId = stream1.drivingPillId, compact = true)
                    }
                    if (stream1.reminderTime != null) {
                        Spacer(modifier = GlanceModifier.width(4.dp))
                        Box(
                            modifier = GlanceModifier
                                .background(Color(0x2900E5FF))
                                .cornerRadius(10.dp)
                                .padding(horizontal = 5.dp, vertical = 2.dp)
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Image(
                                    provider = ImageProvider(bellIcon),
                                    contentDescription = null,
                                    modifier = GlanceModifier.size(7.dp)
                                )
                                Spacer(modifier = GlanceModifier.width(2.dp))
                                Text(
                                    text = stream1.reminderTime,
                                    style = TextStyle(
                                        color = ColorProvider(Color(0xFF00E5FF)),
                                        fontSize = 8.sp,
                                        fontWeight = FontWeight.Bold
                                    )
                                )
                            }
                        }
                    }
                }
            }

            Spacer(modifier = GlanceModifier.width(8.dp))

            Box(modifier = GlanceModifier.width(1.dp).fillMaxHeight().background(Color(0x1FFFFFFF))) {}

            Spacer(modifier = GlanceModifier.width(10.dp))

            Column(
                modifier = GlanceModifier.defaultWeight().fillMaxHeight()
            ) {
                StreamRow(stream1)
                Spacer(modifier = GlanceModifier.height(6.dp))
                StreamRow(stream2)
            }
        }
    }

    // =========================================================================
    // MARK: - 3. LARGE LAYOUT (systemLarge: 4x4)
    // =========================================================================
    @androidx.compose.runtime.Composable
    private fun LargeTagdosLayout(
        streams: List<WidgetStream>,
        totalActivePills: Int,
        nextReminderFormatted: String?
    ) {
        val checklistIcon = WidgetVisualGraphics.createVectorIconBitmap(
            icon = WidgetIconType.CHECKLIST,
            sizePx = 36,
            colorInt = android.graphics.Color.parseColor("#A855F7")
        )
        val bellIcon = WidgetVisualGraphics.createVectorIconBitmap(
            icon = WidgetIconType.BELL,
            sizePx = 20,
            colorInt = android.graphics.Color.parseColor("#FFB800")
        )
        val arrowCircleIcon = WidgetVisualGraphics.createVectorIconBitmap(
            icon = WidgetIconType.ARROW_UP_RIGHT_CIRCLE,
            sizePx = 24,
            colorInt = android.graphics.Color.parseColor("#00E5FF")
        )

        Column(
            modifier = GlanceModifier.fillMaxSize().padding(14.dp)
        ) {
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Image(
                        provider = ImageProvider(checklistIcon),
                        contentDescription = null,
                        modifier = GlanceModifier.size(13.dp)
                    )
                    Spacer(modifier = GlanceModifier.width(6.dp))
                    Text(
                        text = "Tagdos & Notes",
                        style = TextStyle(
                            color = ColorProvider(Color(0xFFA855F7)),
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                }

                Spacer(modifier = GlanceModifier.defaultWeight())

                Box(
                    modifier = GlanceModifier
                        .background(Color(0x2900E5FF))
                        .cornerRadius(12.dp)
                        .padding(horizontal = 6.dp, vertical = 2.5.dp)
                ) {
                    Text(
                        text = "$totalActivePills Active Tags",
                        style = TextStyle(
                            color = ColorProvider(Color(0xFF00E5FF)),
                            fontSize = 9.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                }

                if (nextReminderFormatted != null) {
                    Spacer(modifier = GlanceModifier.width(6.dp))
                    Box(
                        modifier = GlanceModifier
                            .background(Color(0x29FFB800))
                            .cornerRadius(12.dp)
                            .padding(horizontal = 5.dp, vertical = 2.5.dp)
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Image(
                                provider = ImageProvider(bellIcon),
                                contentDescription = null,
                                modifier = GlanceModifier.size(7.dp)
                            )
                            Spacer(modifier = GlanceModifier.width(2.dp))
                            Text(
                                text = nextReminderFormatted,
                                style = TextStyle(
                                    color = ColorProvider(Color(0xFFFFB800)),
                                    fontSize = 9.sp,
                                    fontWeight = FontWeight.Bold
                                )
                            )
                        }
                    }
                }
            }

            Spacer(modifier = GlanceModifier.height(8.dp))
            Box(modifier = GlanceModifier.fillMaxWidth().height(1.dp).background(Color(0x1FFFFFFF))) {}
            Spacer(modifier = GlanceModifier.height(8.dp))

            Column(modifier = GlanceModifier.fillMaxWidth()) {
                for (stream in streams.take(5)) {
                    Box(modifier = GlanceModifier.fillMaxWidth().padding(bottom = 5.dp)) {
                        StreamRow(stream)
                    }
                }
            }

            Spacer(modifier = GlanceModifier.defaultWeight())

            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Tap any tag to edit · ✓ Done · ↻ Recycle",
                    style = TextStyle(
                        color = ColorProvider(Color(0x73FFFFFF)),
                        fontSize = 8.5.sp,
                        fontWeight = FontWeight.Medium
                    )
                )
                Spacer(modifier = GlanceModifier.defaultWeight())
                Image(
                    provider = ImageProvider(arrowCircleIcon),
                    contentDescription = null,
                    modifier = GlanceModifier.size(10.dp)
                )
            }
        }
    }

    @androidx.compose.runtime.Composable
    private fun StreamRow(stream: WidgetStream) {
        val context = LocalContext.current
        Column(modifier = GlanceModifier.fillMaxWidth()) {
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = stream.title,
                    modifier = GlanceModifier.defaultWeight().clickable(buildOpenAction(context, stream.id, null)),
                    maxLines = 1,
                    style = TextStyle(
                        color = ColorProvider(Color(0xB3FFFFFF)),
                        fontSize = 9.sp,
                        fontWeight = FontWeight.Bold
                    )
                )
                if (stream.reminderTime != null) {
                    Box(modifier = GlanceModifier.padding(start = 4.dp)) {
                        Text(
                            text = stream.reminderTime,
                            style = TextStyle(
                                color = ColorProvider(Color(0xFF00E5FF)),
                                fontSize = 8.sp,
                                fontWeight = FontWeight.Medium
                            )
                        )
                    }
                }
            }

            Spacer(modifier = GlanceModifier.height(2.5.dp))

            Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Row(
                    modifier = GlanceModifier.defaultWeight(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    val visible = stream.pills.take(4)
                    for (pill in visible) {
                        val color = resolvePillColor(pill.type)
                        Box(modifier = GlanceModifier.padding(end = 3.5.dp)) {
                            Box(
                                modifier = GlanceModifier
                                    .background(color.copy(alpha = 0.14f))
                                    .cornerRadius(8.dp)
                                    .clickable(buildOpenAction(context, stream.id, pill.id))
                                    .padding(horizontal = 4.5.dp, vertical = 2.dp)
                            ) {
                                Text(
                                    text = pill.text,
                                    style = TextStyle(
                                        color = ColorProvider(color),
                                        fontSize = 8.5.sp,
                                        fontWeight = FontWeight.Bold
                                    )
                                )
                            }
                        }
                    }
                    if (stream.activePillsCount > 4) {
                        Text(
                            text = "+${stream.activePillsCount - 4}",
                            style = TextStyle(
                                color = ColorProvider(Color(0x66FFFFFF)),
                                fontSize = 7.5.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                    }
                }
                if (stream.id.isNotBlank() && !stream.drivingPillId.isNullOrBlank()) {
                    Box(modifier = GlanceModifier.padding(start = 4.dp)) {
                        QuickActionButtons(streamId = stream.id, pillId = stream.drivingPillId, compact = true)
                    }
                }
            }
        }
    }

    private fun resolvePillColor(type: String?): Color {
        return when (type) {
            "financial" -> Color(0xFF00E676)
            "urgent" -> Color(0xFFFF2D55)
            "temporalmetrics", "temporalormetric" -> Color(0xFFFFB800)
            else -> Color(0xFF00E5FF)
        }
    }
}
