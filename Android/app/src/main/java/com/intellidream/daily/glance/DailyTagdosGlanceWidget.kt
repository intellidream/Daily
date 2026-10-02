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
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.intellidream.daily.DailyApp
import com.intellidream.daily.MainActivity
import com.intellidream.daily.model.TagDoStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class DailyTagdosGlanceWidget : GlanceAppWidget() {

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val app = runCatching { DailyApp.instance }.getOrNull()

        val streams = app?.tagdosRepository?.streams?.value ?: emptyList()
        val totalActive = streams.sumOf { it.activePills.size }

        provideContent {
            TagdosWidgetContent(
                context = context,
                streams = streams,
                totalActive = totalActive
            )
        }
    }

    @Composable
    private fun TagdosWidgetContent(
        context: Context,
        streams: List<TagDoStream>,
        totalActive: Int
    ) {
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_TARGET_TAB, MainActivity.TAB_TAGDOS)
        }

        val accentPurple = Color(0xFFA855F7)
        val accentCyan = Color(0xFF00E5FF)
        val accentAmber = Color(0xFFFFB703)
        val accentGreen = Color(0xFF00E676)
        val textMuted = Color(0xFF8E9BAE)
        val dividerColor = Color.White.copy(alpha = 0.12f)

        val stream1 = streams.firstOrNull()
        val stream2 = if (streams.size > 1) streams[1] else null

        val drivingPill = stream1?.drivingPill?.rawText ?: "All clear"
        val stream1Reminder = stream1?.streamReminder?.let {
            if (it > System.currentTimeMillis()) SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(it)) else null
        }

        Box(
            modifier = GlanceModifier
                .fillMaxSize()
                .cornerRadius(24.dp)
                .background(Color(0xFF0F0B1E))
                .padding(12.dp)
                .clickable(actionStartActivity(launchIntent))
        ) {
            Row(
                modifier = GlanceModifier.fillMaxSize(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // LEFT COLUMN: Header + Driving Hero Tag Pill + Reminder
                Column(
                    modifier = GlanceModifier.width(112.dp).fillMaxHeight(),
                    horizontalAlignment = Alignment.Start,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(text = "📋", style = TextStyle(fontSize = 12.sp))
                        Spacer(modifier = GlanceModifier.width(3.dp))
                        Text(
                            text = "TAGDOS",
                            style = TextStyle(
                                color = ColorProvider(accentPurple),
                                fontSize = 9.5.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                    }

                    Spacer(modifier = GlanceModifier.height(5.dp))

                    // Driving Pill Hero
                    Box(
                        modifier = GlanceModifier
                            .fillMaxWidth()
                            .cornerRadius(10.dp)
                            .background(accentPurple.copy(alpha = 0.16f))
                            .padding(horizontal = 7.dp, vertical = 4.dp)
                    ) {
                        Column {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(
                                    text = drivingPill,
                                    style = TextStyle(
                                        color = ColorProvider(Color.White),
                                        fontSize = 12.5.sp,
                                        fontWeight = FontWeight.Bold
                                    ),
                                    maxLines = 1
                                )
                                Spacer(modifier = GlanceModifier.width(2.dp))
                                Text(text = "⭐", style = TextStyle(fontSize = 8.sp))
                            }
                            Spacer(modifier = GlanceModifier.height(1.dp))
                            Text(
                                text = stream1?.displayTitle ?: "Daily Ops",
                                style = TextStyle(
                                    color = ColorProvider(textMuted),
                                    fontSize = 8.sp,
                                    fontWeight = FontWeight.Medium
                                ),
                                maxLines = 1
                            )
                        }
                    }

                    Spacer(modifier = GlanceModifier.height(4.dp))

                    // Reminder or Active Count Pill
                    if (stream1Reminder != null) {
                        Box(
                            modifier = GlanceModifier
                                .cornerRadius(8.dp)
                                .background(accentCyan.copy(alpha = 0.16f))
                                .padding(horizontal = 6.dp, vertical = 2.dp)
                        ) {
                            Text(
                                text = "🔔 $stream1Reminder",
                                style = TextStyle(
                                    color = ColorProvider(accentCyan),
                                    fontSize = 8.5.sp,
                                    fontWeight = FontWeight.Bold
                                )
                            )
                        }
                    } else {
                        Box(
                            modifier = GlanceModifier
                                .cornerRadius(8.dp)
                                .background(Color.White.copy(alpha = 0.08f))
                                .padding(horizontal = 6.dp, vertical = 2.dp)
                        ) {
                            Text(
                                text = "$totalActive Active",
                                style = TextStyle(
                                    color = ColorProvider(accentCyan),
                                    fontSize = 8.5.sp,
                                    fontWeight = FontWeight.Bold
                                )
                            )
                        }
                    }
                }

                Spacer(modifier = GlanceModifier.width(8.dp))

                // Vertical Divider
                Box(
                    modifier = GlanceModifier
                        .width(1.dp)
                        .fillMaxHeight()
                        .background(dividerColor)
                ) {}

                Spacer(modifier = GlanceModifier.width(8.dp))

                // RIGHT COLUMN: Stream 1 & Stream 2 Pipelines
                Column(
                    modifier = GlanceModifier.defaultWeight().fillMaxHeight(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // Stream 1 Pipeline
                    if (stream1 != null) {
                        val pillsChain = stream1.activePills.take(3).joinToString(" ➔ ") { it.rawText }
                        Column(modifier = GlanceModifier.fillMaxWidth()) {
                            Text(
                                text = stream1.displayTitle,
                                style = TextStyle(
                                    color = ColorProvider(Color.White),
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.Bold
                                ),
                                maxLines = 1
                            )
                            Spacer(modifier = GlanceModifier.height(2.dp))
                            Text(
                                text = if (pillsChain.isNotBlank()) pillsChain else "No active tags",
                                style = TextStyle(
                                    color = ColorProvider(accentCyan),
                                    fontSize = 9.5.sp,
                                    fontWeight = FontWeight.Medium
                                ),
                                maxLines = 1
                            )
                        }
                    }

                    Spacer(modifier = GlanceModifier.height(8.dp))

                    // Stream 2 Pipeline
                    if (stream2 != null) {
                        val pillsChain = stream2.activePills.take(3).joinToString(" ➔ ") { it.rawText }
                        Column(modifier = GlanceModifier.fillMaxWidth()) {
                            Text(
                                text = stream2.displayTitle,
                                style = TextStyle(
                                    color = ColorProvider(Color(0xFFCBD5E1)),
                                    fontSize = 10.sp,
                                    fontWeight = FontWeight.Bold
                                ),
                                maxLines = 1
                            )
                            Spacer(modifier = GlanceModifier.height(1.dp))
                            Text(
                                text = if (pillsChain.isNotBlank()) pillsChain else "No active tags",
                                style = TextStyle(
                                    color = ColorProvider(accentAmber),
                                    fontSize = 9.sp,
                                    fontWeight = FontWeight.Medium
                                ),
                                maxLines = 1
                            )
                        }
                    }
                }
            }
        }
    }
}

class DailyTagdosGlanceReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = DailyTagdosGlanceWidget()
}
