package com.intellidream.daily.presentation.dashboard

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Checklist
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.Notifications
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material.icons.rounded.Sync
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
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
                repository = repository,
                onOpenHub = onNavigateToHub
            )
            DashboardWidgetSize.Wide -> WideTagdosContent(
                streams = streams,
                repository = repository,
                onOpenHub = onNavigateToHub
            )
            DashboardWidgetSize.Tall -> TallTagdosContent(
                streams = streams,
                quickNotes = quickNotes,
                repository = repository,
                onOpenHub = onNavigateToHub
            )
            DashboardWidgetSize.Large -> LargeTagdosContent(
                streams = streams,
                quickNotes = quickNotes,
                repository = repository,
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

private fun effectiveStreamReminder(stream: TagDoStream): Long? {
    stream.streamReminder?.let { return it }
    return stream.clusters.mapNotNull { it.reminderTime }.minOrNull()
}

// MARK: - Small (1x1)
@Composable
private fun SmallTagdosContent(
    streams: List<TagDoStream>,
    repository: TagdosRepository,
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

            if (stream1 != null && driving != null) {
                val color = resolvePillColor(driving.type)
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                        modifier = Modifier
                            .weight(1f, fill = false)
                            .clip(CircleShape)
                            .background(color.copy(alpha = 0.15f))
                            .border(1.dp, color.copy(alpha = 0.35f), CircleShape)
                            .clickable {
                                repository.requestNavigation(
                                    streamId = stream1.id,
                                    pillId = driving.id,
                                    openPillEditor = true
                                )
                                onOpenHub()
                            }
                            .padding(horizontal = 8.dp, vertical = 4.dp)
                    ) {
                        Text(
                            text = driving.rawText,
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Bold,
                            color = color,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                        Icon(
                            imageVector = Icons.Rounded.Edit,
                            contentDescription = null,
                            tint = Color.White.copy(alpha = 0.45f),
                            modifier = Modifier.size(10.dp)
                        )
                    }

                    Spacer(modifier = Modifier.width(4.dp))

                    DashboardQuickActions(
                        onComplete = { repository.togglePillCompletion(stream1.id, driving.id) },
                        onRecycle = { repository.recyclePillToBack(stream1.id, driving.id) },
                        sizeDp = 22
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
    repository: TagdosRepository,
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
            StreamPipelineRow(stream = stream1, maxPills = 6, repository = repository, onOpenHub = onOpenHub)
        }

        // Stream 2 Pill Pipeline
        if (stream2 != null) {
            StreamPipelineRow(stream = stream2, maxPills = 6, repository = repository, onOpenHub = onOpenHub)
        }
    }
}

@Composable
private fun StreamPipelineRow(
    stream: TagDoStream,
    maxPills: Int,
    repository: TagdosRepository,
    onOpenHub: () -> Unit
) {
    val reminderTs = effectiveStreamReminder(stream)
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
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f)
            )

            if (reminderTs != null) {
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
                        text = formatReminderTime(reminderTs),
                        fontSize = 8.5.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = ThemeColors.accentCyan
                    )
                }
            }
        }

        StreamPillsRowWithQuickActions(
            stream = stream,
            compact = true,
            buttonSizeDp = 18,
            repository = repository,
            onOpenHub = onOpenHub
        )
    }
}

@Composable
private fun StreamPillsRowWithQuickActions(
    stream: TagDoStream,
    compact: Boolean,
    buttonSizeDp: Int,
    repository: TagdosRepository,
    onOpenHub: () -> Unit
) {
    val driving = stream.drivingPill
    Box(
        modifier = Modifier.fillMaxWidth(),
        contentAlignment = Alignment.CenterStart
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .graphicsLayer(compositingStrategy = CompositingStrategy.Offscreen)
                .drawWithContent {
                    drawContent()
                    if (driving != null) {
                        val fadeWidth = (buttonSizeDp * 2 + 10).dp.toPx()
                        val fadeStart = (size.width - fadeWidth).coerceAtLeast(0f)
                        drawRect(
                            brush = Brush.horizontalGradient(
                                colors = listOf(Color.Black, Color(0x0D000000)),
                                startX = fadeStart,
                                endX = size.width
                            ),
                            blendMode = BlendMode.DstIn
                        )
                    }
                }
                .horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(if (compact) 4.dp else 5.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            stream.activePills.forEach { pill ->
                if (compact) {
                    MiniPillBadge(
                        pill = pill,
                        onClick = {
                            repository.requestNavigation(streamId = stream.id, pillId = pill.id, openPillEditor = true)
                            onOpenHub()
                        }
                    )
                } else {
                    InteractivePillBadge(
                        pill = pill,
                        onClick = {
                            repository.requestNavigation(streamId = stream.id, pillId = pill.id, openPillEditor = true)
                            onOpenHub()
                        }
                    )
                }
            }
            if (driving != null) {
                Spacer(modifier = Modifier.width((buttonSizeDp * 2 + 16).dp))
            }
        }

        if (driving != null) {
            DashboardQuickActions(
                onComplete = { repository.togglePillCompletion(stream.id, driving.id) },
                onRecycle = { repository.recyclePillToBack(stream.id, driving.id) },
                sizeDp = buttonSizeDp,
                modifier = Modifier.align(Alignment.CenterEnd)
            )
        }
    }
}

// MARK: - Tall (1x2)
@Composable
private fun TallTagdosContent(
    streams: List<TagDoStream>,
    quickNotes: List<TagDoQuickNote>,
    repository: TagdosRepository,
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
                val remTs = effectiveStreamReminder(stream)
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
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f)
                        )
                        if (remTs != null) {
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
                                    text = formatReminderTime(remTs),
                                    fontSize = 8.5.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = ThemeColors.accentCyan
                                )
                            }
                        }
                    }

                    StreamPillsRowWithQuickActions(
                        stream = stream,
                        compact = true,
                        buttonSizeDp = 17,
                        repository = repository,
                        onOpenHub = onOpenHub
                    )
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
    repository: TagdosRepository,
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
                val remTs = effectiveStreamReminder(stream)
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
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f)
                        )

                        if (remTs != null) {
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
                                    text = formatReminderTime(remTs),
                                    fontSize = 8.5.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = ThemeColors.accentCyan
                                )
                            }
                        }
                    }

                    // Horizontal scrolling pill row underneath ✓ / ↻
                    StreamPillsRowWithQuickActions(
                        stream = stream,
                        compact = false,
                        buttonSizeDp = 18,
                        repository = repository,
                        onOpenHub = onOpenHub
                    )
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

// MARK: - Mini Pill Badges & Quick Actions
@Composable
private fun DashboardQuickActions(
    onComplete: () -> Unit,
    onRecycle: () -> Unit,
    sizeDp: Int = 20,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(0.dp)
    ) {
        JewelActionCircle(
            icon = Icons.Rounded.Check,
            contentDescription = "Mark Done",
            accentColor = ThemeColors.accentGreen,
            coreFillColor = Color(0xFF0D3026),
            sizeDp = sizeDp,
            onClick = onComplete
        )
        JewelActionCircle(
            icon = Icons.Rounded.Sync,
            contentDescription = "Recycle Tag",
            accentColor = ThemeColors.accentCyan,
            coreFillColor = Color(0xFF0D2B3D),
            sizeDp = sizeDp,
            onClick = onRecycle
        )
    }
}

@Composable
private fun JewelActionCircle(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    contentDescription: String,
    accentColor: Color,
    coreFillColor: Color,
    sizeDp: Int,
    onClick: () -> Unit
) {
    Box(
        modifier = Modifier
            .size((sizeDp + 5).dp)
            .background(
                Brush.radialGradient(
                    colors = listOf(accentColor.copy(alpha = 0.28f), Color.Transparent)
                )
            ),
        contentAlignment = Alignment.Center
    ) {
        Box(
            modifier = Modifier
                .size(sizeDp.dp)
                .clip(CircleShape)
                .background(coreFillColor)
                .border(0.9.dp, accentColor.copy(alpha = 0.58f), CircleShape)
                .clickable(onClick = onClick),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = icon,
                contentDescription = contentDescription,
                tint = accentColor,
                modifier = Modifier.size((sizeDp * 0.55f).dp)
            )
        }
    }
}

@Composable
private fun MiniPillBadge(pill: TagDoPill, onClick: () -> Unit) {
    val color = resolvePillColor(pill.type)
    Box(
        modifier = Modifier
            .clip(CircleShape)
            .background(color.copy(alpha = 0.15f))
            .border(0.5.dp, color.copy(alpha = 0.35f), CircleShape)
            .clickable(onClick = onClick)
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
private fun InteractivePillBadge(pill: TagDoPill, onClick: () -> Unit) {
    val color = resolvePillColor(pill.type)
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        modifier = Modifier
            .clip(CircleShape)
            .background(color.copy(alpha = 0.16f))
            .border(1.dp, color.copy(alpha = 0.40f), CircleShape)
            .clickable(onClick = onClick)
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
