package com.intellidream.daily.presentation.dashboard

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Checklist
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.Notifications
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.database.TagdosRepository
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.DashboardWidgetSize
import com.intellidream.daily.model.TagDoPill
import com.intellidream.daily.model.TagDoPillType
import com.intellidream.daily.model.TagDoQuickNote
import com.intellidream.daily.model.TagDoStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Liquid Glass Tagdos & Notes Card on the main Dashboard.
 * Adaptively renders across Small (1x1), Wide (2x1), Tall (1x2), and Large (2x2) modular sizes.
 * 1:1 Kotlin port of iOS [TagdosNotesDashboardCard.swift].
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun TagdosNotesDashboardCard(
    size: DashboardWidgetSize = DashboardWidgetSize.Wide,
    repository: TagdosRepository,
    onNavigateToHub: () -> Unit = {},
    onLongClick: () -> Unit = {}
) {
    val streams by repository.streams.collectAsState()
    val quickNotes by repository.quickNotes.collectAsState()

    GlassCard(
        cornerRadius = 20.dp,
        padding = if (size == DashboardWidgetSize.Small) 14.dp else 18.dp,
        modifier = Modifier
            .fillMaxSize()
            .clip(RoundedCornerShape(20.dp))
            .combinedClickable(
                onClick = onNavigateToHub,
                onLongClick = onLongClick
            )
    ) {
        when (size) {
            DashboardWidgetSize.Small -> SmallTagdosContent(
                streams = streams,
                onOpenHub = onNavigateToHub
            )
            DashboardWidgetSize.Wide -> WideTagdosContent(
                streams = streams,
                onOpenHub = onNavigateToHub
            )
            DashboardWidgetSize.Tall -> TallTagdosContent(
                streams = streams,
                quickNotes = quickNotes,
                onOpenHub = onNavigateToHub
            )
            DashboardWidgetSize.Large -> LargeTagdosContent(
                streams = streams,
                quickNotes = quickNotes,
                onOpenHub = onNavigateToHub
            )
        }
    }
}

// MARK: - Color Resolver
private fun resolvePillColor(type: TagDoPillType): Color {
    return when (type) {
        TagDoPillType.Standard -> Color(0xFF00E5FF)       // Neon Cyan
        TagDoPillType.Financial -> Color(0xFF00E676)      // Neon Emerald
        TagDoPillType.Urgent -> Color(0xFFFF2D55)         // Glowing Ruby Coral
        TagDoPillType.TemporalOrMetric -> Color(0xFFFFD600) // Neon Amber Yellow
        TagDoPillType.Completed -> Color.White.copy(alpha = 0.35f)
    }
}

private fun formatReminderTime(timestamp: Long?): String {
    if (timestamp == null) return ""
    val sdf = SimpleDateFormat("HH:mm", Locale.getDefault())
    return sdf.format(Date(timestamp))
}

// MARK: - Small (1x1)
@Composable
private fun SmallTagdosContent(
    streams: List<TagDoStream>,
    onOpenHub: () -> Unit
) {
    val stream1 = streams.firstOrNull()
    val driving = stream1?.drivingPill
    val nextPill = stream1?.activePills?.drop(1)?.firstOrNull()
    val totalActive = streams.sumOf { it.activePills.size }

    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        // Header
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Icon(
                    imageVector = Icons.Rounded.Checklist,
                    contentDescription = null,
                    tint = ThemeColors.accentPurple,
                    modifier = Modifier.size(13.dp)
                )
                Text(
                    text = "Tagdos",
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    color = ThemeColors.accentPurple
                )
            }

            if (stream1?.streamReminder != null) {
                Box(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(ThemeColors.accentCyan.copy(alpha = 0.18f))
                        .padding(horizontal = 6.dp, vertical = 2.dp)
                ) {
                    Text(
                        text = formatReminderTime(stream1.streamReminder),
                        fontSize = 9.sp,
                        fontWeight = FontWeight.Bold,
                        color = ThemeColors.accentCyan
                    )
                }
            } else {
                Box(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.08f))
                        .padding(horizontal = 6.dp, vertical = 2.dp)
                ) {
                    Text(
                        text = "$totalActive tags",
                        fontSize = 9.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White.copy(alpha = 0.6f)
                    )
                }
            }
        }

        // Center Hero: Driving Pill
        Column(
            verticalArrangement = Arrangement.spacedBy(3.dp),
            modifier = Modifier.padding(vertical = 4.dp)
        ) {
            Text(
                text = "CURRENT FOCUS",
                fontSize = 8.5.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White.copy(alpha = 0.45f)
            )

            if (driving != null) {
                val color = resolvePillColor(driving.type)
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(5.dp),
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(color.copy(alpha = 0.15f))
                        .border(1.dp, color.copy(alpha = 0.35f), CircleShape)
                        .padding(horizontal = 8.dp, vertical = 4.dp)
                ) {
                    Text(
                        text = driving.rawText,
                        fontSize = 17.sp,
                        fontWeight = FontWeight.Bold,
                        color = color,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Icon(
                        imageVector = Icons.AutoMirrored.Rounded.ArrowForward,
                        contentDescription = null,
                        tint = Color.White.copy(alpha = 0.45f),
                        modifier = Modifier.size(12.dp)
                    )
                }
            } else {
                Text(
                    text = "All Done! 🎉",
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Bold,
                    color = ThemeColors.accentGreen
                )
            }

            if (nextPill != null) {
                Text(
                    text = "Then: ${nextPill.rawText}",
                    fontSize = 9.5.sp,
                    fontWeight = FontWeight.Medium,
                    color = Color.White.copy(alpha = 0.6f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }

        // Footer
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "Open Hub",
                fontSize = 9.5.sp,
                fontWeight = FontWeight.SemiBold,
                color = ThemeColors.accentCyan
            )
            Icon(
                imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                contentDescription = null,
                tint = ThemeColors.accentCyan,
                modifier = Modifier.size(10.dp)
            )
        }
    }
}

// MARK: - Wide (2x1)
@Composable
private fun WideTagdosContent(
    streams: List<TagDoStream>,
    onOpenHub: () -> Unit
) {
    val stream1 = streams.firstOrNull()
    val stream2 = if (streams.size > 1) streams[1] else null
    val totalActive = streams.sumOf { it.activePills.size }

    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        // Header Row
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Icon(
                    imageVector = Icons.Rounded.Checklist,
                    contentDescription = null,
                    tint = ThemeColors.accentPurple,
                    modifier = Modifier.size(14.dp)
                )
                Text(
                    text = "Tagdos & Notes",
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    color = ThemeColors.accentPurple
                )
            }

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Box(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.10f))
                        .padding(horizontal = 7.dp, vertical = 2.5.dp)
                ) {
                    Text(
                        text = "$totalActive Active",
                        fontSize = 9.5.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White.copy(alpha = 0.8f)
                    )
                }

                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    Text(
                        text = "Open Hub",
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        color = ThemeColors.accentCyan
                    )
                    Icon(
                        imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                        contentDescription = null,
                        tint = ThemeColors.accentCyan,
                        modifier = Modifier.size(11.dp)
                    )
                }
            }
        }

        // Stream 1 Pill Pipeline
        if (stream1 != null) {
            StreamPipelineRow(stream = stream1, maxPills = 6)
        }

        // Stream 2 Pill Pipeline
        if (stream2 != null) {
            StreamPipelineRow(stream = stream2, maxPills = 6)
        }
    }
}

@Composable
private fun StreamPipelineRow(stream: TagDoStream, maxPills: Int) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(3.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = stream.displayTitle,
                fontSize = 10.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White.copy(alpha = 0.85f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )

            if (stream.streamReminder != null) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Notifications,
                        contentDescription = null,
                        tint = ThemeColors.accentCyan,
                        modifier = Modifier.size(9.dp)
                    )
                    Text(
                        text = formatReminderTime(stream.streamReminder),
                        fontSize = 8.5.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = ThemeColors.accentCyan
                    )
                }
            }
        }

        // Row of pills
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            val pills = stream.activePills.take(maxPills)
            pills.forEach { pill ->
                MiniPillBadge(pill = pill)
            }
            if (stream.activePills.size > maxPills) {
                Box(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.06f))
                        .padding(horizontal = 5.dp, vertical = 2.dp)
                ) {
                    Text(
                        text = "+${stream.activePills.size - maxPills}",
                        fontSize = 8.5.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White.copy(alpha = 0.45f)
                    )
                }
            }
        }
    }
}

// MARK: - Tall (1x2)
@Composable
private fun TallTagdosContent(
    streams: List<TagDoStream>,
    quickNotes: List<TagDoQuickNote>,
    onOpenHub: () -> Unit
) {
    val totalActive = streams.sumOf { it.activePills.size }

    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        // Header
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(5.dp)
            ) {
                Icon(
                    imageVector = Icons.Rounded.Checklist,
                    contentDescription = null,
                    tint = ThemeColors.accentPurple,
                    modifier = Modifier.size(13.dp)
                )
                Text(
                    text = "Tagdos",
                    fontSize = 11.5.sp,
                    fontWeight = FontWeight.Bold,
                    color = ThemeColors.accentPurple
                )
            }
            Text(
                text = "$totalActive active",
                fontSize = 9.5.sp,
                fontWeight = FontWeight.Bold,
                color = ThemeColors.accentCyan
            )
        }

        HorizontalDivider(color = Color.White.copy(alpha = 0.10f), thickness = 0.5.dp)

        // Stack of up to 3 streams
        Column(
            verticalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.fillMaxWidth()
        ) {
            streams.take(3).forEach { stream ->
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(3.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = stream.displayTitle,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                        if (stream.streamReminder != null) {
                            Text(
                                text = formatReminderTime(stream.streamReminder),
                                fontSize = 8.5.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = ThemeColors.accentCyan
                            )
                        }
                    }

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(3.dp)
                    ) {
                        stream.activePills.take(4).forEach { pill ->
                            MiniPillBadge(pill = pill)
                        }
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(2.dp))

        // Quick Note preview snippet
        val firstNote = quickNotes.firstOrNull()
        if (firstNote != null) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(8.dp))
                    .background(Color.White.copy(alpha = 0.05f))
                    .padding(horizontal = 7.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(5.dp)
            ) {
                Icon(
                    imageVector = Icons.Rounded.Description,
                    contentDescription = null,
                    tint = ThemeColors.accentOrange,
                    modifier = Modifier.size(11.dp)
                )
                Text(
                    text = firstNote.displayTitle,
                    fontSize = 9.5.sp,
                    fontWeight = FontWeight.Medium,
                    color = Color.White.copy(alpha = 0.7f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}

// MARK: - Large (2x2)
@Composable
private fun LargeTagdosContent(
    streams: List<TagDoStream>,
    quickNotes: List<TagDoQuickNote>,
    onOpenHub: () -> Unit
) {
    val totalActive = streams.sumOf { it.activePills.size }

    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        // Header
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Icon(
                    imageVector = Icons.Rounded.Checklist,
                    contentDescription = null,
                    tint = ThemeColors.accentPurple,
                    modifier = Modifier.size(15.dp)
                )
                Text(
                    text = "Tagdos & Notes",
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    color = ThemeColors.accentPurple
                )
            }

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Box(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(ThemeColors.accentCyan.copy(alpha = 0.15f))
                        .padding(horizontal = 8.dp, vertical = 3.dp)
                ) {
                    Text(
                        text = "$totalActive Tags Active",
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        color = ThemeColors.accentCyan
                    )
                }

                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    Text(
                        text = "Open Hub",
                        fontSize = 10.5.sp,
                        fontWeight = FontWeight.Bold,
                        color = ThemeColors.accentCyan
                    )
                    Icon(
                        imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                        contentDescription = null,
                        tint = ThemeColors.accentCyan,
                        modifier = Modifier.size(12.dp)
                    )
                }
            }
        }

        HorizontalDivider(color = Color.White.copy(alpha = 0.10f), thickness = 0.5.dp)

        // Render up to 4 streams with horizontal scrolling pills
        Column(
            verticalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.fillMaxWidth()
        ) {
            streams.take(4).forEach { stream ->
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(3.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = stream.displayTitle,
                            fontSize = 10.5.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )

                        if (stream.streamReminder != null) {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(3.dp)
                            ) {
                                Icon(
                                    imageVector = Icons.Rounded.Notifications,
                                    contentDescription = null,
                                    tint = ThemeColors.accentCyan,
                                    modifier = Modifier.size(9.dp)
                                )
                                Text(
                                    text = formatReminderTime(stream.streamReminder),
                                    fontSize = 8.5.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = ThemeColors.accentCyan
                                )
                            }
                        }
                    }

                    // Horizontal scrolling pill row
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(5.dp)
                    ) {
                        stream.activePills.take(8).forEach { pill ->
                            InteractivePillBadge(pill = pill)
                        }
                    }
                }
            }
        }

        // Bottom Notes Strip
        if (quickNotes.isNotEmpty()) {
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Description,
                        contentDescription = null,
                        tint = ThemeColors.accentOrange,
                        modifier = Modifier.size(10.dp)
                    )
                    Text(
                        text = "Quick Notes",
                        fontSize = 9.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White.copy(alpha = 0.5f)
                    )
                }

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    quickNotes.take(2).forEach { note ->
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .clip(RoundedCornerShape(6.dp))
                                .background(Color.White.copy(alpha = 0.06f))
                                .padding(horizontal = 8.dp, vertical = 4.dp)
                        ) {
                            Text(
                                text = note.displayTitle,
                                fontSize = 9.5.sp,
                                fontWeight = FontWeight.Medium,
                                color = Color.White.copy(alpha = 0.8f),
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Mini Pill Badges
@Composable
private fun MiniPillBadge(pill: TagDoPill) {
    val color = resolvePillColor(pill.type)
    Box(
        modifier = Modifier
            .clip(CircleShape)
            .background(color.copy(alpha = 0.15f))
            .border(0.5.dp, color.copy(alpha = 0.35f), CircleShape)
            .padding(horizontal = 6.dp, vertical = 2.dp)
    ) {
        Text(
            text = pill.rawText,
            fontSize = 9.sp,
            fontWeight = FontWeight.Bold,
            color = color,
            textDecoration = if (pill.isCompleted) TextDecoration.LineThrough else TextDecoration.None
        )
    }
}

@Composable
private fun InteractivePillBadge(pill: TagDoPill) {
    val color = resolvePillColor(pill.type)
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        modifier = Modifier
            .clip(CircleShape)
            .background(color.copy(alpha = 0.16f))
            .border(1.dp, color.copy(alpha = 0.40f), CircleShape)
            .padding(horizontal = 8.dp, vertical = 3.dp)
    ) {
        if (pill.isCompleted) {
            Icon(
                imageVector = Icons.Rounded.CheckCircle,
                contentDescription = null,
                tint = ThemeColors.accentGreen,
                modifier = Modifier.size(10.dp)
            )
        }
        Text(
            text = pill.rawText,
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold,
            color = color,
            textDecoration = if (pill.isCompleted) TextDecoration.LineThrough else TextDecoration.None
        )
    }
}
