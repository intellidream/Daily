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

        val accentCyan = Color(0xFF00E5FF)
        val accentBlue = Color(0xFF3B82F6)

        val firstStream = streams.firstOrNull()
        val secondStream = if (streams.size > 1) streams[1] else null
        val nextReminder = streams.mapNotNull { it.streamReminder }
            .filter { it > System.currentTimeMillis() }
            .minOrNull()
            ?.let { java.text.SimpleDateFormat("HH:mm", java.util.Locale.getDefault()).format(java.util.Date(it)) }

        Box(
            modifier = GlanceModifier
                .fillMaxSize()
                .cornerRadius(22.dp)
                .background(Color(0xFF07111E))
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
                        text = "📋 TAGDOS TASKS",
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
                            text = "$totalActive Active",
                            style = TextStyle(
                                color = ColorProvider(accentCyan),
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                    }
                }

                Spacer(modifier = GlanceModifier.height(8.dp))

                // Primary Stream Row
                if (firstStream != null) {
                    val pillsText = firstStream.activePills.take(5).joinToString("  ") { "[${it.rawText}]" }
                    Column(modifier = GlanceModifier.fillMaxWidth()) {
                        Text(
                            text = firstStream.displayTitle,
                            style = TextStyle(
                                color = ColorProvider(Color.White),
                                fontSize = 13.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                        Spacer(modifier = GlanceModifier.height(2.dp))
                        Text(
                            text = if (pillsText.isNotBlank()) pillsText else "All tasks completed",
                            style = TextStyle(
                                color = ColorProvider(Color(0xFF00E5FF)),
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold
                            ),
                            maxLines = 1
                        )
                    }
                }

                Spacer(modifier = GlanceModifier.height(6.dp))

                // Secondary Stream Row
                if (secondStream != null) {
                    val pillsText = secondStream.activePills.take(4).joinToString("  ") { "[${it.rawText}]" }
                    Column(modifier = GlanceModifier.fillMaxWidth()) {
                        Text(
                            text = secondStream.displayTitle,
                            style = TextStyle(
                                color = ColorProvider(Color(0xFF8E9BAE)),
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Medium
                            )
                        )
                        Spacer(modifier = GlanceModifier.height(1.dp))
                        Text(
                            text = if (pillsText.isNotBlank()) pillsText else "All tasks completed",
                            style = TextStyle(
                                color = ColorProvider(Color(0xFF38BDF8)),
                                fontSize = 10.5.sp,
                                fontWeight = FontWeight.Normal
                            ),
                            maxLines = 1
                        )
                    }
                }

                Spacer(modifier = GlanceModifier.height(6.dp))

                // Footer Reminder
                val footerText = if (!nextReminder.isNullOrBlank()) {
                    "⏰ Next reminder at $nextReminder"
                } else {
                    "Tap to manage mental tags & quick notes"
                }

                Text(
                    text = footerText,
                    style = TextStyle(
                        color = ColorProvider(Color(0xFF8E9BAE)),
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Normal
                    ),
                    maxLines = 1
                )
            }
        }
    }
}

class DailyTagdosGlanceReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = DailyTagdosGlanceWidget()
}
