package com.intellidream.daily.presentation.tagdos

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.CloudDone
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.GridView
import androidx.compose.material.icons.rounded.Notifications
import androidx.compose.material.icons.rounded.NotificationsActive
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material.icons.rounded.TextFields
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.database.TagdosRepository
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.designsystem.calmBoundedSwipeGesture
import com.intellidream.daily.model.TagDoCluster
import com.intellidream.daily.model.TagDoPill
import com.intellidream.daily.model.TagDoPillAction
import com.intellidream.daily.model.TagDoPillType
import com.intellidream.daily.model.TagDoStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Comprehensive interactive hub for TagDoS mental tag pipelines and quick notes.
 * 1:1 Kotlin port of iOS [TagdosNotesHubView.swift].
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun TagdosNotesHubView(
    repository: TagdosRepository,
    onNavigateBack: () -> Unit
) {
    val streams by repository.streams.collectAsState()
    val quickNotes by repository.quickNotes.collectAsState()
    val isSyncing by repository.isSyncing.collectAsState()

    var selectedStreamIndex by remember { mutableIntStateOf(0) }
    var isRawEditMode by remember { mutableStateOf(false) }
    var rawTextBuffer by remember { mutableStateOf("") }

    // Dialogs & Sheets State
    var activePillAction by remember { mutableStateOf<TagDoPillAction?>(null) }
    var newPillClusterIndex by remember { mutableIntStateOf(0) }
    var showingAddTagSheet by remember { mutableStateOf(false) }
    var showingReminderPicker by remember { mutableStateOf(false) }
    var showingRenameSheet by remember { mutableStateOf(false) }

    val isNotesTab = selectedStreamIndex >= streams.size
    val currentStream = if (!isNotesTab && selectedStreamIndex < streams.size) streams[selectedStreamIndex] else null

    LaunchedEffect(selectedStreamIndex, currentStream?.rawText) {
        if (currentStream != null) {
            rawTextBuffer = currentStream.rawText
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(brush = ThemeColors.backgroundGradient)
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
        ) {
            // MARK: - Top Navigation Bar
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Back Button (circular Liquid Glass)
                Box(
                    modifier = Modifier
                        .size(36.dp)
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.08f))
                        .clickable(onClick = onNavigateBack),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Rounded.ArrowBack,
                        contentDescription = "Back",
                        tint = ThemeColors.accentCyan,
                        modifier = Modifier.size(18.dp)
                    )
                }

                // Center Title with Sync status
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Text(
                        text = "Tagdos & Notes",
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )

                    if (isSyncing) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(12.dp),
                            color = ThemeColors.accentCyan,
                            strokeWidth = 1.5.dp
                        )
                    } else {
                        Icon(
                            imageVector = Icons.Rounded.CloudDone,
                            contentDescription = "Synced",
                            tint = ThemeColors.accentGreen.copy(alpha = 0.85f),
                            modifier = Modifier.size(13.dp)
                        )
                    }
                }

                // Right Mode Toggle (Canvas vs Raw Text)
                if (!isNotesTab) {
                    Box(
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(
                                (if (isRawEditMode) ThemeColors.accentGreen else ThemeColors.accentPurple).copy(alpha = 0.18f)
                            )
                            .border(
                                1.dp,
                                (if (isRawEditMode) ThemeColors.accentGreen else ThemeColors.accentPurple).copy(alpha = 0.40f),
                                CircleShape
                            )
                            .clickable {
                                if (isRawEditMode) {
                                    if (currentStream != null) {
                                        repository.updateStreamRawText(currentStream.id, rawTextBuffer)
                                    }
                                } else {
                                    if (currentStream != null) {
                                        rawTextBuffer = currentStream.rawText
                                    }
                                }
                                isRawEditMode = !isRawEditMode
                            }
                            .padding(horizontal = 10.dp, vertical = 6.dp)
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            Icon(
                                imageVector = if (isRawEditMode) Icons.Rounded.GridView else Icons.Rounded.TextFields,
                                contentDescription = null,
                                tint = if (isRawEditMode) ThemeColors.accentGreen else ThemeColors.accentPurple,
                                modifier = Modifier.size(12.dp)
                            )
                            Text(
                                text = if (isRawEditMode) "Canvas" else "Raw Text",
                                fontSize = 11.5.sp,
                                fontWeight = FontWeight.Bold,
                                color = if (isRawEditMode) ThemeColors.accentGreen else ThemeColors.accentPurple
                            )
                        }
                    }
                } else {
                    Spacer(modifier = Modifier.size(36.dp))
                }
            }

            // MARK: - Stream Selector Tabs (1 to 5 + Notes)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                streams.forEachIndexed { index, stream ->
                    val isSelected = selectedStreamIndex == index
                    val driving = stream.drivingPill

                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(
                                if (isSelected) ThemeColors.accentPurple.copy(alpha = 0.35f)
                                else Color.White.copy(alpha = 0.06f)
                            )
                            .border(
                                1.dp,
                                if (isSelected) ThemeColors.accentPurple else Color.White.copy(alpha = 0.12f),
                                CircleShape
                            )
                            .clickable {
                                selectedStreamIndex = index
                                rawTextBuffer = stream.rawText
                            }
                            .padding(horizontal = 10.dp, vertical = 6.dp)
                    ) {
                        // S{N} Mini Badge
                        Box(
                            modifier = Modifier
                                .size(20.dp)
                                .clip(CircleShape)
                                .background(
                                    if (isSelected) ThemeColors.accentPurple
                                    else ThemeColors.accentPurple.copy(alpha = 0.18f)
                                )
                                .border(
                                    1.dp,
                                    ThemeColors.accentPurple.copy(alpha = if (isSelected) 0.8f else 0.4f),
                                    CircleShape
                                ),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                text = "S${index + 1}",
                                fontSize = 9.5.sp,
                                fontWeight = FontWeight.Black,
                                color = if (isSelected) Color.White else ThemeColors.accentPurple
                            )
                        }

                        if (driving != null) {
                            Text(
                                text = driving.rawText,
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold,
                                color = if (isSelected) Color.White else Color.White.copy(alpha = 0.85f),
                                maxLines = 1
                            )
                        }

                        if (stream.streamReminder != null) {
                            Icon(
                                imageVector = Icons.Rounded.NotificationsActive,
                                contentDescription = null,
                                tint = ThemeColors.accentCyan,
                                modifier = Modifier.size(10.dp)
                            )
                        }
                    }
                }

                // Dedicated 6th Tab: Notes
                val isNotesSelected = selectedStreamIndex >= streams.size
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(5.dp),
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(
                            if (isNotesSelected) ThemeColors.accentCyan.copy(alpha = 0.35f)
                            else Color.White.copy(alpha = 0.06f)
                        )
                        .border(
                            1.dp,
                            if (isNotesSelected) ThemeColors.accentCyan else Color.White.copy(alpha = 0.12f),
                            CircleShape
                        )
                        .clickable {
                            selectedStreamIndex = streams.size
                        }
                        .padding(horizontal = 12.dp, vertical = 6.5.dp)
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Description,
                        contentDescription = null,
                        tint = if (isNotesSelected) Color.White else Color.White.copy(alpha = 0.6f),
                        modifier = Modifier.size(12.dp)
                    )
                    Text(
                        text = "Notes",
                        fontSize = 11.5.sp,
                        fontWeight = FontWeight.Bold,
                        color = if (isNotesSelected) Color.White else Color.White.copy(alpha = 0.6f)
                    )

                    if (quickNotes.isNotEmpty()) {
                        Box(
                            modifier = Modifier
                                .clip(CircleShape)
                                .background(Color.White.copy(alpha = 0.15f))
                                .padding(horizontal = 5.dp, vertical = 1.dp)
                        ) {
                            Text(
                                text = "${quickNotes.size}",
                                fontSize = 9.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color.White
                            )
                        }
                    }
                }
            }

            // MARK: - Main Content Body
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .calmBoundedSwipeGesture(
                        currentIndex = selectedStreamIndex,
                        maxIndex = streams.size,
                        edgeGuardDp = 75.dp,
                        onIndexChange = { newIdx ->
                            if (!isRawEditMode && newIdx in 0..streams.size) {
                                selectedStreamIndex = newIdx
                                if (newIdx < streams.size) {
                                    rawTextBuffer = streams[newIdx].rawText
                                }
                            }
                        }
                    )
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                if (isNotesTab) {
                    TagdosQuickNotesView(repository = repository)
                } else {
                    if (currentStream != null) {
                        if (isRawEditMode) {
                            // Raw Text Editor Card
                            RawEditorCard(
                                rawText = rawTextBuffer,
                                onTextChange = { rawTextBuffer = it },
                                onSave = {
                                    repository.updateStreamRawText(currentStream.id, rawTextBuffer)
                                    isRawEditMode = false
                                }
                            )
                        } else {
                            // Interactive Canvas Card
                            InteractiveCanvasCard(
                                stream = currentStream,
                                onRenameClick = { showingRenameSheet = true },
                                onReminderClick = { showingReminderPicker = true },
                                onAddPillClick = { clusterIndex ->
                                    newPillClusterIndex = clusterIndex
                                    showingAddTagSheet = true
                                },
                                onPillClick = { pill ->
                                    activePillAction = TagDoPillAction(streamId = currentStream.id, pill = pill)
                                }
                            )
                        }

                        // Per-Stream Active Memos & Attachments
                        TagdosActiveMemoView(
                            streamId = currentStream.id,
                            streamNumber = currentStream.orderIndex + 1,
                            repository = repository
                        )
                    }
                }

                Spacer(modifier = Modifier.height(30.dp))
            }
        }
    }

    // MARK: - Bottom Sheets & Modals

    activePillAction?.let { action ->
        TagdosPillActionSheet(
            pill = action.pill,
            onRecycle = { repository.recyclePillToBack(action.streamId, action.pill.id) },
            onToggleCompletion = { repository.togglePillCompletion(action.streamId, action.pill.id) },
            onMoveToFront = { repository.movePillToFront(action.streamId, action.pill.id) },
            onDelete = { repository.removePill(action.streamId, action.pill.id) },
            onDismiss = { activePillAction = null }
        )
    }

    if (showingAddTagSheet && currentStream != null) {
        TagdosAddTagSheet(
            clusterIndex = newPillClusterIndex,
            onAddTag = { text ->
                repository.addPill(currentStream.id, newPillClusterIndex, text)
            },
            onDismiss = { showingAddTagSheet = false }
        )
    }

    if (showingRenameSheet && currentStream != null) {
        TagdosRenameStreamSheet(
            currentTitle = currentStream.customTitle ?: currentStream.title,
            onSaveTitle = { newTitle ->
                repository.updateStreamTitle(currentStream.id, newTitle)
            },
            onDismiss = { showingRenameSheet = false }
        )
    }

    if (showingReminderPicker && currentStream != null) {
        TagdosReminderSheet(
            currentReminder = currentStream.streamReminder,
            onSetReminder = { timestamp ->
                repository.setStreamReminder(currentStream.id, timestamp)
            },
            onDismiss = { showingReminderPicker = false }
        )
    }
}

// MARK: - Interactive Canvas Card
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun InteractiveCanvasCard(
    stream: TagDoStream,
    onRenameClick: () -> Unit,
    onReminderClick: () -> Unit,
    onAddPillClick: (Int) -> Unit,
    onPillClick: (TagDoPill) -> Unit
) {
    val sdf = remember { SimpleDateFormat("HH:mm", Locale.getDefault()) }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(20.dp))
            .background(Color(0xFF081426).copy(alpha = 0.75f))
            .border(1.dp, Color.White.copy(alpha = 0.14f), RoundedCornerShape(20.dp))
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        // Stream Header Row
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(
                modifier = Modifier
                    .weight(1f)
                    .clickable(onClick = onRenameClick),
                verticalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Text(
                        text = stream.displayTitle,
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Icon(
                        imageVector = Icons.Rounded.Edit,
                        contentDescription = "Rename",
                        tint = Color.White.copy(alpha = 0.35f),
                        modifier = Modifier.size(12.dp)
                    )
                }
                Text(
                    text = "${stream.activePills.size} active tags • ${stream.clusters.size} clusters",
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Medium,
                    color = Color.White.copy(alpha = 0.55f)
                )
            }

            // Reminder Pill
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                modifier = Modifier
                    .clip(CircleShape)
                    .background(ThemeColors.accentCyan.copy(alpha = 0.15f))
                    .border(1.dp, ThemeColors.accentCyan.copy(alpha = 0.30f), CircleShape)
                    .clickable(onClick = onReminderClick)
                    .padding(horizontal = 10.dp, vertical = 5.dp)
            ) {
                val reminder = stream.streamReminder
                Icon(
                    imageVector = if (reminder != null) Icons.Rounded.NotificationsActive else Icons.Rounded.Notifications,
                    contentDescription = null,
                    tint = ThemeColors.accentCyan,
                    modifier = Modifier.size(11.dp)
                )
                Text(
                    text = if (reminder != null) sdf.format(Date(reminder)) else "+ Reminder",
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    color = ThemeColors.accentCyan
                )
            }
        }

        HorizontalDivider(color = Color.White.copy(alpha = 0.12f), thickness = 0.5.dp)

        // Clusters Flow
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            stream.clusters.forEachIndexed { clusterIndex, cluster ->
                ClusterCardView(
                    clusterIndex = clusterIndex,
                    cluster = cluster,
                    onAddPill = { onAddPillClick(clusterIndex) },
                    onPillClick = onPillClick
                )

                if (clusterIndex < stream.clusters.size - 1) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.Center
                    ) {
                        Box(
                            modifier = Modifier
                                .clip(CircleShape)
                                .background(ThemeColors.accentPurple.copy(alpha = 0.15f))
                                .padding(horizontal = 8.dp, vertical = 2.dp)
                        ) {
                            Text(
                                text = "&",
                                fontSize = 13.sp,
                                fontWeight = FontWeight.Bold,
                                color = ThemeColors.accentPurple
                            )
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ClusterCardView(
    clusterIndex: Int,
    cluster: TagDoCluster,
    onAddPill: () -> Unit,
    onPillClick: (TagDoPill) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(Color.White.copy(alpha = 0.04f))
            .border(1.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(14.dp))
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "CLUSTER ${clusterIndex + 1}",
                fontSize = 9.5.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White.copy(alpha = 0.45f)
            )

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(3.dp),
                modifier = Modifier
                    .clip(CircleShape)
                    .background(ThemeColors.accentCyan.copy(alpha = 0.12f))
                    .clickable(onClick = onAddPill)
                    .padding(horizontal = 7.dp, vertical = 2.5.dp)
            ) {
                Text(
                    text = "+ Tag",
                    fontSize = 9.5.sp,
                    fontWeight = FontWeight.Bold,
                    color = ThemeColors.accentCyan
                )
            }
        }

        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            cluster.pills.forEachIndexed { pillIndex, pill ->
                CanvasPill(
                    pill = pill,
                    isLeading = pillIndex == 0,
                    onClick = { onPillClick(pill) }
                )
            }
        }
    }
}

@Composable
private fun CanvasPill(
    pill: TagDoPill,
    isLeading: Boolean,
    onClick: () -> Unit
) {
    val color = when (pill.type) {
        TagDoPillType.Standard -> Color(0xFF00E5FF)
        TagDoPillType.Financial -> Color(0xFF00E676)
        TagDoPillType.Urgent -> Color(0xFFFF2D55)
        TagDoPillType.TemporalOrMetric -> Color(0xFFFFD600)
        TagDoPillType.Completed -> Color.White.copy(alpha = 0.35f)
    }

    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        modifier = Modifier
            .clip(CircleShape)
            .background(if (pill.isCompleted) Color.White.copy(alpha = 0.05f) else color.copy(alpha = 0.16f))
            .border(
                1.dp,
                if (pill.isCompleted) Color.White.copy(alpha = 0.12f) else color.copy(alpha = 0.40f),
                CircleShape
            )
            .clickable(onClick = onClick)
            .padding(horizontal = 9.dp, vertical = 5.dp)
    ) {
        if (pill.isCompleted) {
            Icon(
                imageVector = Icons.Rounded.CheckCircle,
                contentDescription = null,
                tint = ThemeColors.accentGreen,
                modifier = Modifier.size(11.dp)
            )
        }

        Text(
            text = pill.rawText,
            fontSize = 12.sp,
            fontWeight = FontWeight.Bold,
            color = if (pill.isCompleted) Color.White.copy(alpha = 0.4f) else color,
            textDecoration = if (pill.isCompleted) TextDecoration.LineThrough else TextDecoration.None
        )

        if (isLeading && !pill.isCompleted) {
            Icon(
                imageVector = Icons.Rounded.Star,
                contentDescription = null,
                tint = ThemeColors.accentOrange,
                modifier = Modifier.size(8.dp)
            )
        }
    }
}

// MARK: - Raw Editor Card
@Composable
private fun RawEditorCard(
    rawText: String,
    onTextChange: (String) -> Unit,
    onSave: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(20.dp))
            .background(Color(0xFF081426).copy(alpha = 0.75f))
            .border(1.dp, Color.White.copy(alpha = 0.14f), RoundedCornerShape(20.dp))
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "Raw Text Editor",
                fontSize = 14.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White
            )

            Button(
                onClick = onSave,
                colors = ButtonDefaults.buttonColors(containerColor = ThemeColors.accentGreen.copy(alpha = 0.40f)),
                shape = CircleShape
            ) {
                Text("Save & Parse", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 11.sp)
            }
        }

        Text(
            text = "Format: Cluster1/Pill1/Pill2 & Cluster2/PillA/PillB\nUse $ or € for financial, ! for urgent, numbers for dates/specs.",
            fontSize = 10.5.sp,
            fontWeight = FontWeight.Medium,
            color = Color.White.copy(alpha = 0.55f),
            lineHeight = 15.sp
        )

        OutlinedTextField(
            value = rawText,
            onValueChange = onTextChange,
            modifier = Modifier
                .fillMaxWidth()
                .height(180.dp),
            colors = OutlinedTextFieldDefaults.colors(
                focusedTextColor = Color.White,
                unfocusedTextColor = Color.White,
                focusedBorderColor = ThemeColors.accentCyan,
                unfocusedBorderColor = Color.White.copy(alpha = 0.12f)
            ),
            textStyle = androidx.compose.ui.text.TextStyle(
                fontFamily = FontFamily.Monospace,
                fontSize = 13.sp
            ),
            shape = RoundedCornerShape(12.dp)
        )
    }
}
