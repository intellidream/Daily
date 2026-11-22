package com.intellidream.daily.presentation.tagdos

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.ArrowDownward
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Checklist
import androidx.compose.material.icons.rounded.CloudDone
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.GridView
import androidx.compose.material.icons.rounded.Language
import androidx.compose.material.icons.rounded.Notifications
import androidx.compose.material.icons.rounded.NotificationsActive
import androidx.compose.material.icons.rounded.PushPin
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material.icons.rounded.SwapHoriz
import androidx.compose.material.icons.rounded.Sync
import androidx.compose.material.icons.rounded.TextFields
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshContainer
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import com.intellidream.daily.database.TagdosRepository
import com.intellidream.daily.designsystem.DailyLiquidLoadingIndicator
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.TagDoCluster
import com.intellidream.daily.model.TagDoPill
import com.intellidream.daily.model.TagDoPillAction
import com.intellidream.daily.model.TagDoPillType
import com.intellidream.daily.model.TagDoQuickNote
import com.intellidream.daily.model.TagDoStream
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Comprehensive interactive hub for TagDoS mental tag pipelines and quick notes.
 * 1:1 Kotlin port of iOS [TagdosNotesHubView.swift].
 */
@OptIn(ExperimentalLayoutApi::class, ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun TagdosNotesHubView(
    repository: TagdosRepository,
    onNavigateBack: () -> Unit,
    onOpenUrlInPrism: ((String) -> Unit)? = null,
    horizontalPadding: androidx.compose.ui.unit.Dp = 16.dp,
    applyStatusBarsPadding: Boolean = true
) {
    val context = LocalContext.current
    val streams by repository.streams.collectAsState()
    val quickNotes by repository.quickNotes.collectAsState()
    val isSyncing by repository.isSyncing.collectAsState()
    val pendingNav by repository.pendingNavigation.collectAsState()

    // -1 = "All" overview tab, 0..<streams.size = S1..SN, streams.size = "Notes"
    var selectedStreamIndex by remember { mutableIntStateOf(-1) }
    var isRawEditMode by remember { mutableStateOf(false) }
    var rawTextBuffer by remember { mutableStateOf("") }
    var highlightedClusterKey by remember { mutableStateOf<String?>(null) }

    // Dialogs & Sheets State
    var activePillAction by remember { mutableStateOf<TagDoPillAction?>(null) }
    var newPillClusterIndex by remember { mutableIntStateOf(0) }
    var showingAddTagSheet by remember { mutableStateOf(false) }
    var showingReminderPicker by remember { mutableStateOf(false) }
    var editingReminderClusterIndex by remember { mutableStateOf<Int?>(null) }
    var showingRenameSheet by remember { mutableStateOf(false) }
    var showingReorderSheet by remember { mutableStateOf(false) }
    var showingImportSheet by remember { mutableStateOf(false) }

    // Quick Note editor sheet (used on "All" overview tab)
    var activeOverviewNote by remember { mutableStateOf<TagDoQuickNote?>(null) }
    var isCreatingOverviewNote by remember { mutableStateOf(false) }

    val notificationPermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { _ -> }

    fun ensureNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val granted = ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
            if (!granted) {
                notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        }
    }

    val haptic = LocalHapticFeedback.current
    val coroutineScope = rememberCoroutineScope()
    val pullRefreshState = rememberPullToRefreshState()
    LaunchedEffect(Unit) {
        repository.syncWithSupabase(force = false)
    }
    if (pullRefreshState.isRefreshing) {
        LaunchedEffect(true) {
            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
            coroutineScope.launch {
                repository.syncWithSupabase(force = true)
                pullRefreshState.endRefresh()
            }
        }
    }

    val isAllTab = selectedStreamIndex == -1
    val isNotesTab = selectedStreamIndex >= streams.size
    val currentStream = if (selectedStreamIndex in streams.indices) streams[selectedStreamIndex] else null

    LaunchedEffect(selectedStreamIndex, currentStream?.rawText) {
        if (currentStream != null) {
            rawTextBuffer = currentStream.rawText
        } else {
            isRawEditMode = false
        }
    }

    // Consume deep-link / notification / widget / dashboard navigation targets
    LaunchedEffect(pendingNav, streams) {
        val target = pendingNav ?: return@LaunchedEffect
        if (streams.isEmpty()) return@LaunchedEffect

        val sid = target.streamId
        val sIdx = if (sid != null) streams.indexOfFirst { it.id == sid } else -1
        if (sIdx >= 0) {
            val stream = streams[sIdx]
            isRawEditMode = false
            selectedStreamIndex = sIdx
            rawTextBuffer = stream.rawText

            if (target.openPillEditor && target.pillId != null) {
                val pill = stream.allPills.firstOrNull { it.id == target.pillId }
                if (pill != null) {
                    activePillAction = TagDoPillAction(streamId = stream.id, pill = pill)
                }
            } else if (target.clusterIndex != null && target.clusterIndex in stream.clusters.indices) {
                val key = "${stream.id}_${target.clusterIndex}"
                highlightedClusterKey = key
                coroutineScope.launch {
                    delay(1800)
                    if (highlightedClusterKey == key) {
                        highlightedClusterKey = null
                    }
                }
            }
        }
        repository.consumePendingNavigation()
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(brush = ThemeColors.backgroundGradient)
            .nestedScroll(pullRefreshState.nestedScrollConnection)
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .then(if (applyStatusBarsPadding) Modifier.statusBarsPadding() else Modifier)
        ) {
            // MARK: - Top Navigation Bar
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = horizontalPadding, vertical = 12.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(
                    modifier = Modifier
                        .size(36.dp)
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.08f))
                        .border(1.dp, Color.White.copy(alpha = 0.12f), CircleShape)
                        .clickable(onClick = onNavigateBack),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowLeft,
                        contentDescription = "Back",
                        tint = Color.White,
                        modifier = Modifier.size(18.dp)
                    )
                }

                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.06f))
                        .border(1.dp, Color.White.copy(alpha = 0.10f), CircleShape)
                        .padding(horizontal = 12.dp, vertical = 6.dp)
                ) {
                    Text(
                        text = "Tagdos & Notes",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )

                    if (isSyncing) {
                        DailyLiquidLoadingIndicator(
                            modifier = Modifier.size(14.dp),
                            color = ThemeColors.accentCyan,
                            size = 14.dp
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

                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(
                        modifier = Modifier
                            .size(36.dp)
                            .clip(CircleShape)
                            .background(ThemeColors.accentCyan.copy(alpha = 0.16f))
                            .border(1.dp, ThemeColors.accentCyan.copy(alpha = 0.35f), CircleShape)
                            .clickable { showingImportSheet = true },
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.Download,
                            contentDescription = "Import Tasks",
                            tint = ThemeColors.accentCyan,
                            modifier = Modifier.size(18.dp)
                        )
                    }

                    if (currentStream != null) {
                        val modeColor = if (isRawEditMode) ThemeColors.accentGreen else ThemeColors.accentPurple
                        Box(
                            modifier = Modifier
                                .size(36.dp)
                                .clip(CircleShape)
                                .background(modeColor.copy(alpha = 0.18f))
                                .border(1.dp, modeColor.copy(alpha = 0.40f), CircleShape)
                                .clickable {
                                    if (isRawEditMode) {
                                        repository.updateStreamRawText(currentStream.id, rawTextBuffer)
                                    } else {
                                        rawTextBuffer = currentStream.rawText
                                    }
                                    isRawEditMode = !isRawEditMode
                                },
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(
                                imageVector = if (isRawEditMode) Icons.Rounded.GridView else Icons.Rounded.TextFields,
                                contentDescription = if (isRawEditMode) "Canvas Mode" else "Raw Text Mode",
                                tint = modeColor,
                                modifier = Modifier.size(18.dp)
                            )
                        }
                    }
                }
            }

            // MARK: - Stream Selector Tabs (All + S1..SN + Notes)
            val totalActiveTags = remember(streams) { streams.sumOf { it.activePills.size } }
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState())
                    .padding(horizontal = horizontalPadding, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // First Tab: "All"
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(5.dp),
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(
                            if (isAllTab) ThemeColors.accentCyan.copy(alpha = 0.32f)
                            else Color.White.copy(alpha = 0.06f)
                        )
                        .border(
                            1.dp,
                            if (isAllTab) ThemeColors.accentCyan else Color.White.copy(alpha = 0.12f),
                            CircleShape
                        )
                        .clickable {
                            selectedStreamIndex = -1
                            isRawEditMode = false
                        }
                        .padding(horizontal = 11.dp, vertical = 6.5.dp)
                ) {
                    Icon(
                        imageVector = Icons.Rounded.GridView,
                        contentDescription = null,
                        tint = if (isAllTab) Color.White else Color.White.copy(alpha = 0.68f),
                        modifier = Modifier.size(12.dp)
                    )
                    Text(
                        text = "All",
                        fontSize = 11.5.sp,
                        fontWeight = FontWeight.Bold,
                        color = if (isAllTab) Color.White else Color.White.copy(alpha = 0.68f)
                    )
                    if (totalActiveTags > 0) {
                        Box(
                            modifier = Modifier
                                .clip(CircleShape)
                                .background(Color.White.copy(alpha = 0.15f))
                                .padding(horizontal = 5.dp, vertical = 1.dp)
                        ) {
                            Text(
                                text = "$totalActiveTags",
                                fontSize = 9.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color.White
                            )
                        }
                    }
                }

                streams.forEachIndexed { index, stream ->
                    val isSelected = selectedStreamIndex == index
                    val driving = stream.drivingPill
                    val hasAnyReminder = stream.streamReminder != null || stream.clusters.any { it.reminderTime != null }

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
                            .combinedClickable(
                                onClick = {
                                    selectedStreamIndex = index
                                    rawTextBuffer = stream.rawText
                                },
                                onLongClick = {
                                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                    selectedStreamIndex = index
                                    rawTextBuffer = stream.rawText
                                    showingRenameSheet = true
                                }
                            )
                            .padding(horizontal = 10.dp, vertical = 6.dp)
                    ) {
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

                        val customTabTitle = stream.customTitle?.trim()?.takeIf { it.isNotEmpty() }
                        val tabLabel = customTabTitle ?: driving?.rawText
                        if (tabLabel != null) {
                            Text(
                                text = tabLabel,
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold,
                                color = if (isSelected) Color.White else Color.White.copy(alpha = 0.85f),
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.widthIn(max = 110.dp)
                            )
                        }

                        if (hasAnyReminder) {
                            Icon(
                                imageVector = Icons.Rounded.NotificationsActive,
                                contentDescription = null,
                                tint = ThemeColors.accentCyan,
                                modifier = Modifier.size(10.dp)
                            )
                        }
                    }
                }

                // Add New Stream Button
                Box(
                    modifier = Modifier
                        .size(28.dp)
                        .clip(CircleShape)
                        .background(ThemeColors.accentCyan.copy(alpha = 0.16f))
                        .border(1.dp, ThemeColors.accentCyan.copy(alpha = 0.35f), CircleShape)
                        .clickable {
                            val newId = repository.createStream()
                            val newIdx = repository.streams.value.indexOfFirst { it.id == newId }
                            selectedStreamIndex = if (newIdx >= 0) newIdx else 0
                            isRawEditMode = false
                        },
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Add,
                        contentDescription = "New Stream",
                        tint = ThemeColors.accentCyan,
                        modifier = Modifier.size(15.dp)
                    )
                }

                // Reorder Streams Button
                if (streams.size > 1) {
                    Box(
                        modifier = Modifier
                            .size(28.dp)
                            .clip(CircleShape)
                            .background(ThemeColors.accentPurple.copy(alpha = 0.18f))
                            .border(1.dp, ThemeColors.accentPurple.copy(alpha = 0.38f), CircleShape)
                            .clickable { showingReorderSheet = true },
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.SwapHoriz,
                            contentDescription = "Reorder Streams",
                            tint = ThemeColors.accentPurple,
                            modifier = Modifier.size(15.dp)
                        )
                    }
                }

                // Dedicated Notes Tab
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
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = horizontalPadding, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                if (isAllTab) {
                    AllStreamsAndNotesOverview(
                        streams = streams,
                        quickNotes = quickNotes,
                        onSelectStream = { idx ->
                            selectedStreamIndex = idx
                            rawTextBuffer = streams[idx].rawText
                        },
                        onPillClick = { streamId, pill ->
                            activePillAction = TagDoPillAction(streamId = streamId, pill = pill)
                        },
                        onQuickComplete = { streamId, pillId ->
                            haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            repository.togglePillCompletion(streamId, pillId)
                        },
                        onQuickRecycle = { streamId, pillId ->
                            haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            repository.recyclePillToBack(streamId, pillId)
                        },
                        onNewNote = {
                            isCreatingOverviewNote = true
                            activeOverviewNote = TagDoQuickNote()
                        },
                        onEditNote = { note ->
                            isCreatingOverviewNote = false
                            activeOverviewNote = note
                        },
                        onTogglePinNote = { id -> repository.togglePinQuickNote(id) },
                        onDeleteNote = { id -> repository.deleteQuickNote(id) },
                        onOpenUrlInPrism = onOpenUrlInPrism
                    )
                } else if (isNotesTab) {
                    TagdosQuickNotesView(
                        repository = repository,
                        onOpenUrlInPrism = onOpenUrlInPrism
                    )
                } else if (currentStream != null) {
                    if (isRawEditMode) {
                        RawEditorCard(
                            rawText = rawTextBuffer,
                            onTextChange = { rawTextBuffer = it },
                            onSave = {
                                repository.updateStreamRawText(currentStream.id, rawTextBuffer)
                                isRawEditMode = false
                            }
                        )
                    } else {
                        InteractiveCanvasCard(
                            stream = currentStream,
                            highlightedClusterKey = highlightedClusterKey,
                            onRenameClick = { showingRenameSheet = true },
                            onStreamReminderClick = {
                                editingReminderClusterIndex = null
                                showingReminderPicker = true
                            },
                            onClusterReminderClick = { clusterIdx ->
                                editingReminderClusterIndex = clusterIdx
                                showingReminderPicker = true
                            },
                            onAddPillClick = { clusterIndex ->
                                newPillClusterIndex = clusterIndex
                                showingAddTagSheet = true
                            },
                            onPillClick = { pill ->
                                activePillAction = TagDoPillAction(streamId = currentStream.id, pill = pill)
                            }
                        )
                    }

                    TagdosActiveMemoView(
                        streamId = currentStream.id,
                        streamNumber = currentStream.orderIndex + 1,
                        repository = repository
                    )
                }

                Spacer(modifier = Modifier.height(30.dp))
            }
        }

        if (pullRefreshState.isRefreshing || pullRefreshState.verticalOffset > 0.5f) {
            PullToRefreshContainer(
                state = pullRefreshState,
                modifier = Modifier.align(Alignment.TopCenter),
                containerColor = Color(0xFF0D182E),
                contentColor = ThemeColors.accentCyan
            )
        }
    }

    // MARK: - Bottom Sheets & Modals

    activePillAction?.let { action ->
        TagdosPillActionSheet(
            pill = action.pill,
            onUpdateText = { newText -> repository.updatePillText(action.streamId, action.pill.id, newText) },
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
        val currentIdx = streams.indexOfFirst { it.id == currentStream.id }.coerceAtLeast(0)
        TagdosRenameStreamSheet(
            currentTitle = currentStream.customTitle ?: currentStream.title,
            canDeleteStream = streams.size > 1,
            onDeleteStream = {
                repository.deleteStream(currentStream.id)
                selectedStreamIndex = selectedStreamIndex.coerceIn(0, (streams.size - 2).coerceAtLeast(0))
            },
            canMoveLeft = currentIdx > 0,
            canMoveRight = currentIdx < streams.size - 1,
            onMoveLeft = {
                if (currentIdx > 0) {
                    repository.moveStream(currentIdx, currentIdx - 1)
                    selectedStreamIndex = currentIdx - 1
                }
            },
            onMoveRight = {
                if (currentIdx < streams.size - 1) {
                    repository.moveStream(currentIdx, currentIdx + 1)
                    selectedStreamIndex = currentIdx + 1
                }
            },
            onSaveTitle = { newTitle ->
                repository.updateStreamTitle(currentStream.id, newTitle)
            },
            onDismiss = { showingRenameSheet = false }
        )
    }

    if (showingReorderSheet && streams.size > 1) {
        val activeStreamId = currentStream?.id
        TagdosReorderStreamsSheet(
            streams = streams,
            onMove = { fromIndex, toIndex ->
                repository.moveStream(fromIndex, toIndex)
                if (activeStreamId != null) {
                    if (selectedStreamIndex == fromIndex) {
                        selectedStreamIndex = toIndex
                    } else if (selectedStreamIndex in toIndex until fromIndex) {
                        selectedStreamIndex += 1
                    } else if (selectedStreamIndex in (fromIndex + 1)..toIndex) {
                        selectedStreamIndex -= 1
                    }
                }
            },
            onDismiss = { showingReorderSheet = false }
        )
    }

    if (showingReminderPicker && currentStream != null) {
        val cIdx = editingReminderClusterIndex
        val targetCluster = if (cIdx != null && cIdx in currentStream.clusters.indices) currentStream.clusters[cIdx] else null
        val sheetTitle = if (targetCluster != null) "Group Reminder" else "Stream Reminder"
        val sheetSubtitle = if (targetCluster != null) {
            val preview = targetCluster.pills.take(4).joinToString(" / ") { it.rawText }
            if (preview.isBlank()) "Daily notification for this group" else "Group: $preview"
        } else {
            currentStream.displayTitle
        }
        val existingTimestamp = if (targetCluster != null) targetCluster.reminderTime else currentStream.streamReminder

        TagdosReminderSheet(
            title = sheetTitle,
            subtitle = sheetSubtitle,
            currentReminder = existingTimestamp,
            onSetReminder = { timestamp ->
                if (timestamp != null) {
                    ensureNotificationPermissionIfNeeded()
                }
                if (cIdx != null) {
                    repository.setClusterReminder(currentStream.id, cIdx, timestamp)
                } else {
                    repository.setStreamReminder(currentStream.id, timestamp)
                }
            },
            onDismiss = { showingReminderPicker = false }
        )
    }

    if (showingImportSheet) {
        TagdosImportTasksSheet(
            repository = repository,
            initialStreamId = currentStream?.id,
            onImported = { importedId ->
                val idx = repository.streams.value.indexOfFirst { it.id == importedId }
                if (idx >= 0) {
                    selectedStreamIndex = idx
                    isRawEditMode = false
                }
            },
            onDismiss = { showingImportSheet = false }
        )
    }

    activeOverviewNote?.let { note ->
        MarkdownNoteEditorSheet(
            note = note,
            isNew = isCreatingOverviewNote,
            onSave = { updated ->
                if (isCreatingOverviewNote) {
                    repository.createQuickNote(updated.title, updated.content)
                } else {
                    repository.updateQuickNote(updated.id, updated.title, updated.content)
                }
                activeOverviewNote = null
            },
            onDelete = { id ->
                repository.deleteQuickNote(id)
                activeOverviewNote = null
            },
            onDismiss = { activeOverviewNote = null }
        )
    }
}

// MARK: - "All" Overview Tab (Large-Widget-Style Full Hub Overview)
@OptIn(ExperimentalLayoutApi::class, ExperimentalFoundationApi::class)
@Composable
private fun AllStreamsAndNotesOverview(
    streams: List<TagDoStream>,
    quickNotes: List<TagDoQuickNote>,
    onSelectStream: (Int) -> Unit,
    onPillClick: (String, TagDoPill) -> Unit,
    onQuickComplete: (String, String) -> Unit,
    onQuickRecycle: (String, String) -> Unit,
    onNewNote: () -> Unit,
    onEditNote: (TagDoQuickNote) -> Unit,
    onTogglePinNote: (String) -> Unit,
    onDeleteNote: (String) -> Unit,
    onOpenUrlInPrism: ((String) -> Unit)?
) {
    val sdf = remember { SimpleDateFormat("HH:mm", Locale.getDefault()) }
    val totalActive = remember(streams) { streams.sumOf { it.activePills.size } }
    val sortedNotes = remember(quickNotes) {
        quickNotes.sortedWith(compareByDescending<TagDoQuickNote> { it.isPinned }.thenByDescending { it.updatedAt })
    }

    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        // 1. All Streams Card
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
                        text = "ALL STREAMS",
                        fontSize = 11.5.sp,
                        fontWeight = FontWeight.Bold,
                        color = ThemeColors.accentPurple
                    )
                }

                Box(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(ThemeColors.accentCyan.copy(alpha = 0.15f))
                        .padding(horizontal = 8.dp, vertical = 3.dp)
                ) {
                    Text(
                        text = "$totalActive Active Tags",
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        color = ThemeColors.accentCyan
                    )
                }
            }

            HorizontalDivider(color = Color.White.copy(alpha = 0.10f), thickness = 0.5.dp)

            streams.forEachIndexed { index, stream ->
                val earliestRem = remember(stream) {
                    buildList {
                        stream.streamReminder?.let { add(sdf.format(Date(it))) }
                        stream.clusters.forEach { c -> c.reminderTime?.let { add(sdf.format(Date(it))) } }
                    }.minOrNull()
                }
                val driving = stream.drivingPill

                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(14.dp))
                        .background(Color.White.copy(alpha = 0.04f))
                        .border(1.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(14.dp))
                        .padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(7.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                            modifier = Modifier
                                .weight(1f)
                                .clickable { onSelectStream(index) }
                        ) {
                            Box(
                                modifier = Modifier
                                    .size(20.dp)
                                    .clip(CircleShape)
                                    .background(ThemeColors.accentPurple.copy(alpha = 0.78f)),
                                contentAlignment = Alignment.Center
                            ) {
                                Text(
                                    text = "S${index + 1}",
                                    fontSize = 9.5.sp,
                                    fontWeight = FontWeight.Black,
                                    color = Color.White
                                )
                            }
                            Text(
                                text = stream.displayTitle,
                                fontSize = 13.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color.White,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.weight(1f, fill = false)
                            )
                            Icon(
                                imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                                contentDescription = null,
                                tint = Color.White.copy(alpha = 0.35f),
                                modifier = Modifier.size(13.dp)
                            )
                        }

                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(5.dp)
                        ) {
                            if (earliestRem != null) {
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(2.dp),
                                    modifier = Modifier
                                        .clip(CircleShape)
                                        .background(ThemeColors.accentCyan.copy(alpha = 0.14f))
                                        .padding(horizontal = 6.dp, vertical = 2.dp)
                                ) {
                                    Icon(
                                        imageVector = Icons.Rounded.NotificationsActive,
                                        contentDescription = null,
                                        tint = ThemeColors.accentCyan,
                                        modifier = Modifier.size(9.dp)
                                    )
                                    Text(
                                        text = earliestRem,
                                        fontSize = 9.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = ThemeColors.accentCyan
                                    )
                                }
                            }

                            if (driving != null) {
                                Box(
                                    modifier = Modifier
                                        .size(20.dp)
                                        .clip(CircleShape)
                                        .background(ThemeColors.accentGreen.copy(alpha = 0.16f))
                                        .border(0.8.dp, ThemeColors.accentGreen.copy(alpha = 0.4f), CircleShape)
                                        .clickable { onQuickComplete(stream.id, driving.id) },
                                    contentAlignment = Alignment.Center
                                ) {
                                    Icon(
                                        imageVector = Icons.Rounded.Check,
                                        contentDescription = "Mark Done",
                                        tint = ThemeColors.accentGreen,
                                        modifier = Modifier.size(11.dp)
                                    )
                                }
                                Box(
                                    modifier = Modifier
                                        .size(20.dp)
                                        .clip(CircleShape)
                                        .background(ThemeColors.accentCyan.copy(alpha = 0.16f))
                                        .border(0.8.dp, ThemeColors.accentCyan.copy(alpha = 0.4f), CircleShape)
                                        .clickable { onQuickRecycle(stream.id, driving.id) },
                                    contentAlignment = Alignment.Center
                                ) {
                                    Icon(
                                        imageVector = Icons.Rounded.Sync,
                                        contentDescription = "Recycle",
                                        tint = ThemeColors.accentCyan,
                                        modifier = Modifier.size(11.dp)
                                    )
                                }
                            }
                        }
                    }

                    val allPills = stream.allPills
                    if (allPills.isEmpty()) {
                        Text(
                            text = "No tags yet",
                            fontSize = 11.sp,
                            color = Color.White.copy(alpha = 0.4f)
                        )
                    } else {
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            allPills.forEach { pill ->
                                CanvasPill(
                                    pill = pill,
                                    isLeading = pill.id == driving?.id,
                                    onClick = { onPillClick(stream.id, pill) }
                                )
                            }
                        }
                    }

                    val memoTrimmed = stream.activeMemos.trim()
                    if (memoTrimmed.isNotEmpty()) {
                        Text(
                            text = memoTrimmed.replace("\n", " · "),
                            fontSize = 10.5.sp,
                            color = Color.White.copy(alpha = 0.6f),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }
            }
        }

        // 2. All Quick Notes Card
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
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Description,
                        contentDescription = null,
                        tint = ThemeColors.accentOrange,
                        modifier = Modifier.size(15.dp)
                    )
                    Text(
                        text = "QUICK NOTES",
                        fontSize = 11.5.sp,
                        fontWeight = FontWeight.Bold,
                        color = ThemeColors.accentOrange
                    )
                    if (sortedNotes.isNotEmpty()) {
                        Box(
                            modifier = Modifier
                                .clip(CircleShape)
                                .background(Color.White.copy(alpha = 0.10f))
                                .padding(horizontal = 6.dp, vertical = 1.5.dp)
                        ) {
                            Text(
                                text = "${sortedNotes.size}",
                                fontSize = 9.5.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color.White.copy(alpha = 0.7f)
                            )
                        }
                    }
                }

                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(ThemeColors.accentCyan)
                        .clickable(onClick = onNewNote)
                        .padding(horizontal = 10.dp, vertical = 5.dp)
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Add,
                        contentDescription = null,
                        tint = Color.Black,
                        modifier = Modifier.size(12.dp)
                    )
                    Text(
                        text = "New Note",
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.Black
                    )
                }
            }

            HorizontalDivider(color = Color.White.copy(alpha = 0.10f), thickness = 0.5.dp)

            if (sortedNotes.isEmpty()) {
                Text(
                    text = "No quick notes yet. Tap + New Note to jot down thoughts or markdown checklists.",
                    fontSize = 12.sp,
                    color = Color.White.copy(alpha = 0.5f)
                )
            } else {
                sortedNotes.forEach { note ->
                    var showNoteMenu by remember(note.id) { mutableStateOf(false) }
                    val detectedUrl = remember(note.content) {
                        Regex("""https?://[^\s)\]>]+""").find(note.content)?.value
                    }
                    Box {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(12.dp))
                                .background(Color.White.copy(alpha = 0.04f))
                                .border(1.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(12.dp))
                                .combinedClickable(
                                    onClick = { onEditNote(note) },
                                    onLongClick = { showNoteMenu = true }
                                )
                                .padding(11.dp),
                            verticalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(
                                    text = note.displayTitle,
                                    fontSize = 13.5.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = Color.White,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    modifier = Modifier.weight(1f)
                                )
                                if (note.isPinned) {
                                    Icon(
                                        imageVector = Icons.Rounded.PushPin,
                                        contentDescription = null,
                                        tint = ThemeColors.accentOrange,
                                        modifier = Modifier.size(12.dp)
                                    )
                                }
                            }
                            if (note.previewSnippet.isNotBlank()) {
                                Text(
                                    text = note.previewSnippet,
                                    fontSize = 11.5.sp,
                                    color = Color.White.copy(alpha = 0.65f),
                                    maxLines = 2,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }
                            if (detectedUrl != null && onOpenUrlInPrism != null) {
                                Row(
                                    modifier = Modifier
                                        .clip(CircleShape)
                                        .background(ThemeColors.accentCyan.copy(alpha = 0.14f))
                                        .clickable { onOpenUrlInPrism(detectedUrl) }
                                        .padding(horizontal = 8.dp, vertical = 3.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                                ) {
                                    Icon(
                                        imageVector = Icons.Rounded.Language,
                                        contentDescription = null,
                                        tint = ThemeColors.accentCyan,
                                        modifier = Modifier.size(11.dp)
                                    )
                                    Text(
                                        text = "Open in Prism",
                                        fontSize = 10.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = ThemeColors.accentCyan
                                    )
                                }
                            }
                        }

                        DropdownMenu(
                            expanded = showNoteMenu,
                            onDismissRequest = { showNoteMenu = false },
                            modifier = Modifier.background(Color(0xFF0D182E))
                        ) {
                            DropdownMenuItem(
                                text = { Text(if (note.isPinned) "Unpin Note" else "Pin to Top", color = Color.White) },
                                onClick = {
                                    showNoteMenu = false
                                    onTogglePinNote(note.id)
                                }
                            )
                            DropdownMenuItem(
                                text = { Text("Delete Note", color = ThemeColors.accentPink) },
                                onClick = {
                                    showNoteMenu = false
                                    onDeleteNote(note.id)
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Interactive Canvas Card
@OptIn(ExperimentalLayoutApi::class, ExperimentalFoundationApi::class)
@Composable
private fun InteractiveCanvasCard(
    stream: TagDoStream,
    highlightedClusterKey: String?,
    onRenameClick: () -> Unit,
    onStreamReminderClick: () -> Unit,
    onClusterReminderClick: (Int) -> Unit,
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
                    text = "${stream.activePills.size} active tags • ${stream.clusters.size} groups",
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Medium,
                    color = Color.White.copy(alpha = 0.55f)
                )
            }

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                modifier = Modifier
                    .clip(CircleShape)
                    .background(ThemeColors.accentCyan.copy(alpha = 0.15f))
                    .border(1.dp, ThemeColors.accentCyan.copy(alpha = 0.30f), CircleShape)
                    .clickable(onClick = onStreamReminderClick)
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

        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            if (stream.clusters.isEmpty()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(14.dp))
                        .background(Color.White.copy(alpha = 0.04f))
                        .border(1.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(14.dp))
                        .padding(12.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "No tags yet. Add a tag or import external tasks.",
                        fontSize = 12.sp,
                        color = Color.White.copy(alpha = 0.55f),
                        modifier = Modifier.weight(1f)
                    )
                    Box(
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(ThemeColors.accentCyan.copy(alpha = 0.15f))
                            .clickable { onAddPillClick(0) }
                            .padding(horizontal = 9.dp, vertical = 4.dp)
                    ) {
                        Text("+ Tag", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = ThemeColors.accentCyan)
                    }
                }
            } else {
                stream.clusters.forEachIndexed { clusterIndex, cluster ->
                    val clusterKey = "${stream.id}_$clusterIndex"
                    SwipeableClusterCard(
                        cluster = cluster,
                        isHighlighted = highlightedClusterKey == clusterKey,
                        reminderFormatted = cluster.reminderTime?.let { sdf.format(Date(it)) },
                        onAddPill = { onAddPillClick(clusterIndex) },
                        onSetReminder = { onClusterReminderClick(clusterIndex) },
                        onPillClick = onPillClick
                    )
                }
            }
        }
    }
}

/**
 * Clean cluster card without "CLUSTER N" label.
 * Drag right (reveals LEFT slot) -> "+ Tag".
 * Drag left (reveals RIGHT slot) -> "Alert" (per-cluster reminder).
 */
@OptIn(ExperimentalLayoutApi::class, ExperimentalFoundationApi::class)
@Composable
private fun SwipeableClusterCard(
    cluster: TagDoCluster,
    isHighlighted: Boolean,
    reminderFormatted: String?,
    onAddPill: () -> Unit,
    onSetReminder: () -> Unit,
    onPillClick: (TagDoPill) -> Unit
) {
    val density = LocalDensity.current
    val haptic = LocalHapticFeedback.current
    val revealWidthPx = with(density) { 80.dp.toPx() }
    val fullPullThresholdPx = with(density) { 122.dp.toPx() }

    var rawOffsetPx by remember(cluster.id) { mutableFloatStateOf(0f) }
    var restingOffsetPx by remember(cluster.id) { mutableFloatStateOf(0f) }
    val animatedOffsetPx by animateFloatAsState(
        targetValue = rawOffsetPx,
        animationSpec = spring(dampingRatio = 0.8f, stiffness = 500f),
        label = "ClusterSwipeOffset"
    )

    val bringIntoViewRequester = remember { BringIntoViewRequester() }
    LaunchedEffect(isHighlighted) {
        if (isHighlighted) {
            runCatching { bringIntoViewRequester.bringIntoView() }
        }
    }

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(IntrinsicSize.Min)
            .clip(RoundedCornerShape(14.dp))
            .bringIntoViewRequester(bringIntoViewRequester)
    ) {
        // Revealed Left ("+ Tag") & Right ("Alert") Action Slots
        Row(
            modifier = Modifier
                .fillMaxSize()
                .padding(vertical = 2.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            if (animatedOffsetPx > 4f) {
                Box(
                    modifier = Modifier
                        .width(74.dp)
                        .fillMaxHeight()
                        .clip(RoundedCornerShape(12.dp))
                        .background(ThemeColors.accentCyan)
                        .clickable {
                            rawOffsetPx = 0f
                            restingOffsetPx = 0f
                            haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            onAddPill()
                        },
                    contentAlignment = Alignment.Center
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(3.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.Add,
                            contentDescription = "Add Tag",
                            tint = Color.Black,
                            modifier = Modifier.size(13.dp)
                        )
                        Text(
                            text = "Tag",
                            fontSize = 11.5.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.Black
                        )
                    }
                }
            } else {
                Spacer(modifier = Modifier.width(1.dp))
            }

            if (animatedOffsetPx < -4f) {
                Box(
                    modifier = Modifier
                        .width(74.dp)
                        .fillMaxHeight()
                        .clip(RoundedCornerShape(12.dp))
                        .background(ThemeColors.accentPurple.copy(alpha = 0.88f))
                        .border(1.dp, ThemeColors.accentCyan.copy(alpha = 0.45f), RoundedCornerShape(12.dp))
                        .clickable {
                            rawOffsetPx = 0f
                            restingOffsetPx = 0f
                            haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            onSetReminder()
                        },
                    contentAlignment = Alignment.Center
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(3.dp)
                    ) {
                        Icon(
                            imageVector = if (reminderFormatted != null) Icons.Rounded.NotificationsActive else Icons.Rounded.Notifications,
                            contentDescription = "Set Reminder",
                            tint = Color.White,
                            modifier = Modifier.size(12.dp)
                        )
                        Text(
                            text = reminderFormatted ?: "Alert",
                            fontSize = 10.5.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White
                        )
                    }
                }
            } else {
                Spacer(modifier = Modifier.width(1.dp))
            }
        }

        // Foreground Cluster Surface
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .offset { IntOffset(animatedOffsetPx.roundToInt(), 0) }
                .clip(RoundedCornerShape(14.dp))
                .background(Color(0xFF0D1B30))
                .border(
                    width = if (isHighlighted) 1.8.dp else 1.dp,
                    color = if (isHighlighted) ThemeColors.accentCyan else Color.White.copy(alpha = 0.09f),
                    shape = RoundedCornerShape(14.dp)
                )
                .clickable(enabled = restingOffsetPx != 0f) {
                    rawOffsetPx = 0f
                    restingOffsetPx = 0f
                }
                .pointerInput(cluster.id) {
                    detectHorizontalDragGestures(
                        onHorizontalDrag = { change, dragAmount ->
                            change.consume()
                            val next = restingOffsetPx + (rawOffsetPx - restingOffsetPx) + dragAmount
                            rawOffsetPx = when {
                                next > revealWidthPx -> revealWidthPx + (next - revealWidthPx) * 0.35f
                                next < -revealWidthPx -> -revealWidthPx + (next + revealWidthPx) * 0.35f
                                else -> next
                            }
                        },
                        onDragEnd = {
                            when {
                                rawOffsetPx >= fullPullThresholdPx -> {
                                    rawOffsetPx = 0f
                                    restingOffsetPx = 0f
                                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                    onAddPill()
                                }
                                rawOffsetPx <= -fullPullThresholdPx -> {
                                    rawOffsetPx = 0f
                                    restingOffsetPx = 0f
                                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                    onSetReminder()
                                }
                                rawOffsetPx > revealWidthPx * 0.42f -> {
                                    rawOffsetPx = revealWidthPx
                                    restingOffsetPx = revealWidthPx
                                    haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                }
                                rawOffsetPx < -revealWidthPx * 0.42f -> {
                                    rawOffsetPx = -revealWidthPx
                                    restingOffsetPx = -revealWidthPx
                                    haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                }
                                else -> {
                                    rawOffsetPx = 0f
                                    restingOffsetPx = 0f
                                }
                            }
                        },
                        onDragCancel = {
                            rawOffsetPx = restingOffsetPx
                        }
                    )
                }
                .padding(horizontal = 13.dp, vertical = 11.dp)
        ) {
            // Subtle Left Edge Hint (Drag Right -> + Tag)
            Box(
                modifier = Modifier
                    .align(Alignment.CenterStart)
                    .offset(x = (-8).dp)
                    .width(2.5.dp)
                    .height(18.dp)
                    .clip(CircleShape)
                    .background(ThemeColors.accentCyan.copy(alpha = 0.48f))
            )

            // Subtle Right Edge Hint (Drag Left -> Reminder)
            Box(
                modifier = Modifier
                    .align(Alignment.CenterEnd)
                    .offset(x = 8.dp)
                    .width(2.5.dp)
                    .height(18.dp)
                    .clip(CircleShape)
                    .background(
                        (if (reminderFormatted != null) ThemeColors.accentCyan else ThemeColors.accentPurple)
                            .copy(alpha = 0.52f)
                    )
            )

            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                if (reminderFormatted != null) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.End
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(3.dp),
                            modifier = Modifier
                                .clip(CircleShape)
                                .background(ThemeColors.accentCyan.copy(alpha = 0.14f))
                                .clickable(onClick = onSetReminder)
                                .padding(horizontal = 6.dp, vertical = 2.dp)
                        ) {
                            Icon(
                                imageVector = Icons.Rounded.NotificationsActive,
                                contentDescription = null,
                                tint = ThemeColors.accentCyan,
                                modifier = Modifier.size(9.dp)
                            )
                            Text(
                                text = reminderFormatted,
                                fontSize = 9.sp,
                                fontWeight = FontWeight.Bold,
                                color = ThemeColors.accentCyan
                            )
                        }
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
                            onClick = {
                                if (abs(restingOffsetPx) > 1f) {
                                    rawOffsetPx = 0f
                                    restingOffsetPx = 0f
                                } else {
                                    onPillClick(pill)
                                }
                            }
                        )
                    }
                }
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
            text = "Format: Group1/Pill1/Pill2 & Group2/PillA/PillB\nUse $ or € for financial, ! for urgent, numbers for dates/specs.",
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TagdosReorderStreamsSheet(
    streams: List<TagDoStream>,
    onMove: (fromIndex: Int, toIndex: Int) -> Unit,
    onDismiss: () -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Color(0xFF081426),
        dragHandle = null
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Reorder Streams",
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White
                )
                TextButton(onClick = onDismiss) {
                    Text("Done", color = ThemeColors.accentCyan, fontWeight = FontWeight.Bold)
                }
            }

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                streams.forEachIndexed { index, stream ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(Color.White.copy(alpha = 0.05f))
                            .border(1.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(12.dp))
                            .padding(horizontal = 12.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        Box(
                            modifier = Modifier
                                .size(28.dp)
                                .clip(CircleShape)
                                .background(ThemeColors.accentPurple),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                text = "S${index + 1}",
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Black,
                                color = Color.White
                            )
                        }

                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = stream.displayTitle,
                                fontSize = 14.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = Color.White,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                            val drivingText = stream.drivingPill?.rawText
                            if (stream.customTitle != null && !drivingText.isNullOrBlank()) {
                                Text(
                                    text = drivingText,
                                    fontSize = 11.sp,
                                    color = Color.White.copy(alpha = 0.6f),
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }
                        }

                        IconButton(
                            onClick = { onMove(index, index - 1) },
                            enabled = index > 0,
                            modifier = Modifier.size(32.dp)
                        ) {
                            Icon(
                                imageVector = Icons.Rounded.ArrowUpward,
                                contentDescription = "Move Up",
                                tint = if (index > 0) Color.White else Color.White.copy(alpha = 0.25f),
                                modifier = Modifier.size(18.dp)
                            )
                        }
                        IconButton(
                            onClick = { onMove(index, index + 1) },
                            enabled = index < streams.size - 1,
                            modifier = Modifier.size(32.dp)
                        ) {
                            Icon(
                                imageVector = Icons.Rounded.ArrowDownward,
                                contentDescription = "Move Down",
                                tint = if (index < streams.size - 1) Color.White else Color.White.copy(alpha = 0.25f),
                                modifier = Modifier.size(18.dp)
                            )
                        }
                    }
                }
            }
        }
    }
}
