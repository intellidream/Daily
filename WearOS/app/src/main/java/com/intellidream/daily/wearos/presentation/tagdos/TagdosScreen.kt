package com.intellidream.daily.wearos.presentation.tagdos

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.FormatListBulleted
import androidx.compose.material.icons.filled.NoteAdd
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.Sync
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.ButtonDefaults
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.dialog.Dialog
import com.google.android.horologist.annotations.ExperimentalHorologistApi
import com.google.android.horologist.compose.layout.ScalingLazyColumn
import com.google.android.horologist.compose.layout.ScalingLazyColumnState
import com.google.android.horologist.compose.layout.ScreenScaffold
import com.google.android.horologist.compose.layout.rememberResponsiveColumnState
import com.intellidream.daily.wearos.data.TagDoQuickNote
import com.intellidream.daily.wearos.data.WatchTagdosRepository
import com.intellidream.daily.wearos.data.badgeColor
import com.intellidream.daily.wearos.presentation.theme.DailyWearColors
import com.intellidream.daily.wearos.util.SoundAndHapticFeedback
import kotlinx.coroutines.launch

@OptIn(ExperimentalHorologistApi::class)
@Composable
fun TagdosScreen(
    isPageActive: Boolean = true
) {
    val context = LocalContext.current
    val view = LocalView.current
    val repository = remember { WatchTagdosRepository.getInstance(context) }
    val streams by repository.streams.collectAsState()
    val quickNotes by repository.quickNotes.collectAsState()
    val isSyncing by repository.isSyncing.collectAsState()

    var selectedStreamIdx by remember { mutableIntStateOf(0) }
    var showAddTaskDialog by remember { mutableStateOf(false) }
    var showAddNoteDialog by remember { mutableStateOf(false) }
    var selectedNote by remember { mutableStateOf<TagDoQuickNote?>(null) }

    val scope = rememberCoroutineScope()
    val columnState = rememberResponsiveColumnState(
        rotaryMode = ScalingLazyColumnState.RotaryMode.Scroll
    )

    LaunchedEffect(isPageActive) {
        if (isPageActive) {
            repository.syncWithSupabase()
        }
    }

    val currentStream = streams.getOrNull(selectedStreamIdx) ?: streams.firstOrNull()

    ScreenScaffold(scrollState = columnState) {
        ScalingLazyColumn(
            columnState = columnState,
            modifier = Modifier.fillMaxSize()
        ) {
            // Screen Header
            item {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center,
                    modifier = Modifier.padding(top = 4.dp, bottom = 2.dp)
                ) {
                    Icon(
                        imageVector = Icons.Filled.FormatListBulleted,
                        contentDescription = null,
                        tint = Color(0xFF00E5FF),
                        modifier = Modifier.size(16.dp)
                    )
                    Spacer(Modifier.width(4.dp))
                    Text(
                        text = "TagDoS",
                        fontWeight = FontWeight.Bold,
                        fontSize = 16.sp,
                        color = Color.White
                    )
                    if (isSyncing) {
                        Spacer(Modifier.width(6.dp))
                        CircularProgressIndicator(
                            modifier = Modifier.size(10.dp),
                            strokeWidth = 1.5.dp,
                            indicatorColor = Color(0xFF00E5FF)
                        )
                    }
                }
            }

            // 5-Stream Driving Radar (Horizontal Pills Row)
            item {
                val horizontalScroll = rememberScrollState()
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(horizontalScroll)
                        .padding(horizontal = 4.dp, vertical = 4.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    streams.forEachIndexed { index, stream ->
                        val isSelected = (index == selectedStreamIdx)
                        val drivingTag = stream.drivingPill?.rawText ?: "✓"
                        val count = stream.activePills.size

                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(12.dp))
                                .background(if (isSelected) stream.streamColor else Color(0xFF141820))
                                .border(
                                    1.dp,
                                    if (isSelected) stream.streamColor else Color.White.copy(alpha = 0.08f),
                                    RoundedCornerShape(12.dp)
                                )
                                .clickable {
                                    SoundAndHapticFeedback.playClick(context, view)
                                    selectedStreamIdx = index
                                }
                                .padding(horizontal = 8.dp, vertical = 5.dp)
                        ) {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(4.dp)
                            ) {
                                Text(
                                    text = stream.streamShortCode,
                                    fontSize = 10.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = if (isSelected) Color.Black else stream.streamColor
                                )
                                Text(
                                    text = drivingTag,
                                    fontSize = 10.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = if (isSelected) Color.Black else Color.White,
                                    maxLines = 1
                                )
                                if (count > 0) {
                                    Box(
                                        modifier = Modifier
                                            .clip(CircleShape)
                                            .background(if (isSelected) Color.Black.copy(alpha = 0.25f) else stream.streamColor.copy(alpha = 0.2f))
                                            .padding(horizontal = 4.dp, vertical = 1.dp)
                                    ) {
                                        Text(
                                            text = "$count",
                                            fontSize = 9.sp,
                                            fontWeight = FontWeight.Bold,
                                            color = if (isSelected) Color.Black else stream.streamColor
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Stream Queue Title & Count
            if (currentStream != null) {
                item {
                    Spacer(Modifier.height(4.dp))
                    Row(
                        modifier = Modifier
                            .fillMaxWidth(0.92f)
                            .padding(horizontal = 2.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = currentStream.title.uppercase(),
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                            color = currentStream.streamColor,
                            letterSpacing = 0.5.sp
                        )
                        Text(
                            text = "${currentStream.activePills.size} pending",
                            fontSize = 9.sp,
                            fontWeight = FontWeight.Medium,
                            color = Color.White.copy(alpha = 0.5f)
                        )
                    }
                }

                // Active Pills Checklist
                if (currentStream.activePills.isEmpty()) {
                    item {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth(0.92f)
                                .clip(RoundedCornerShape(14.dp))
                                .background(Color(0xFF141820))
                                .padding(vertical = 12.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Icon(
                                    imageVector = Icons.Filled.CheckCircle,
                                    contentDescription = null,
                                    tint = DailyWearColors.SmokeGreen,
                                    modifier = Modifier.size(20.dp)
                                )
                                Spacer(Modifier.height(4.dp))
                                Text(
                                    text = "Queue Completed!",
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = Color.White.copy(alpha = 0.8f)
                                )
                            }
                        }
                    }
                } else {
                    items(count = minOf(6, currentStream.activePills.size), key = { currentStream.activePills[it].id }) { pIdx ->
                        val pill = currentStream.activePills[pIdx]
                        val isLead = (pill.id == currentStream.drivingPill?.id)

                        Row(
                            modifier = Modifier
                                .fillMaxWidth(0.92f)
                                .padding(vertical = 2.dp)
                                .clip(RoundedCornerShape(10.dp))
                                .background(if (isLead) pill.type.badgeColor.copy(alpha = 0.12f) else Color(0xFF141820))
                                .border(
                                    1.dp,
                                    if (isLead) pill.type.badgeColor.copy(alpha = 0.35f) else Color.White.copy(alpha = 0.04f),
                                    RoundedCornerShape(10.dp)
                                )
                                .clickable {
                                    SoundAndHapticFeedback.playLogAdded(context, view)
                                    repository.completePill(currentStream.streamNumber, pill.id)
                                }
                                .padding(horizontal = 10.dp, vertical = 6.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Box(
                                    modifier = Modifier
                                        .size(16.dp)
                                        .clip(CircleShape)
                                        .border(1.5.dp, pill.type.badgeColor, CircleShape)
                                )
                                Spacer(Modifier.width(8.dp))
                                Text(
                                    text = pill.rawText,
                                    fontSize = 12.sp,
                                    fontWeight = if (isLead) FontWeight.Bold else FontWeight.Medium,
                                    color = Color.White,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }

                            if (isLead) {
                                Box(
                                    modifier = Modifier
                                        .clip(RoundedCornerShape(4.dp))
                                        .background(pill.type.badgeColor.copy(alpha = 0.25f))
                                        .padding(horizontal = 4.dp, vertical = 1.dp)
                                ) {
                                    Text(
                                        text = "LEAD",
                                        fontSize = 8.sp,
                                        fontWeight = FontWeight.Black,
                                        color = pill.type.badgeColor
                                    )
                                }
                            }
                        }
                    }

                    // Recycle Lead Action Chip
                    if (currentStream.activePills.size > 1) {
                        item {
                            Spacer(Modifier.height(2.dp))
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth(0.92f)
                                    .clip(RoundedCornerShape(8.dp))
                                    .clickable {
                                        SoundAndHapticFeedback.playClick(context, view)
                                        repository.recycleDrivingPill(currentStream.streamNumber)
                                    }
                                    .padding(vertical = 4.dp),
                                contentAlignment = Alignment.Center
                            ) {
                                Text(
                                    text = "↷ Recycle Lead to End",
                                    fontSize = 10.sp,
                                    fontWeight = FontWeight.Medium,
                                    color = Color.White.copy(alpha = 0.55f)
                                )
                            }
                        }
                    }
                }
            }

            // Quick Actions: + Task / + Note
            item {
                Spacer(Modifier.height(6.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(0.92f),
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .clip(RoundedCornerShape(10.dp))
                            .background(Color(0xFF141820))
                            .border(1.dp, Color(0xFF00E5FF).copy(alpha = 0.3f), RoundedCornerShape(10.dp))
                            .clickable {
                                SoundAndHapticFeedback.playClick(context, view)
                                showAddTaskDialog = true
                            }
                            .padding(vertical = 6.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                imageVector = Icons.Filled.Add,
                                contentDescription = null,
                                tint = Color(0xFF00E5FF),
                                modifier = Modifier.size(12.dp)
                            )
                            Spacer(Modifier.width(4.dp))
                            Text(
                                text = "+ Task",
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color(0xFF00E5FF)
                            )
                        }
                    }

                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .clip(RoundedCornerShape(10.dp))
                            .background(Color(0xFF141820))
                            .border(1.dp, Color(0xFFFFD600).copy(alpha = 0.3f), RoundedCornerShape(10.dp))
                            .clickable {
                                SoundAndHapticFeedback.playClick(context, view)
                                showAddNoteDialog = true
                            }
                            .padding(vertical = 6.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                imageVector = Icons.Filled.NoteAdd,
                                contentDescription = null,
                                tint = Color(0xFFFFD600),
                                modifier = Modifier.size(12.dp)
                            )
                            Spacer(Modifier.width(4.dp))
                            Text(
                                text = "+ Note",
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color(0xFFFFD600)
                            )
                        }
                    }
                }
            }

            // Pinned Notes Peek
            if (quickNotes.isNotEmpty()) {
                item {
                    Spacer(Modifier.height(8.dp))
                    Row(
                        modifier = Modifier
                            .fillMaxWidth(0.92f)
                            .padding(horizontal = 2.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(
                            imageVector = Icons.Filled.PushPin,
                            contentDescription = null,
                            tint = Color(0xFFFFD600),
                            modifier = Modifier.size(10.dp)
                        )
                        Spacer(Modifier.width(4.dp))
                        Text(
                            text = "PINNED NOTES",
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White.copy(alpha = 0.55f),
                            letterSpacing = 0.5.sp
                        )
                    }
                }

                items(count = minOf(3, quickNotes.size), key = { quickNotes[it].id }) { nIdx ->
                    val note = quickNotes[nIdx]
                    Box(
                        modifier = Modifier
                            .fillMaxWidth(0.92f)
                            .padding(vertical = 2.dp)
                            .clip(RoundedCornerShape(10.dp))
                            .background(Color(0xFF141820))
                            .border(1.dp, Color.White.copy(alpha = 0.05f), RoundedCornerShape(10.dp))
                            .clickable {
                                SoundAndHapticFeedback.playClick(context, view)
                                selectedNote = note
                            }
                            .padding(horizontal = 10.dp, vertical = 6.dp)
                    ) {
                        Column {
                            Text(
                                text = note.title,
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color.White,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                            Text(
                                text = note.content,
                                fontSize = 10.sp,
                                color = Color.White.copy(alpha = 0.6f),
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis
                            )
                        }
                    }
                }
            }

            item {
                Spacer(Modifier.height(16.dp))
            }
        }
    }

    // Add Task Dialog
    if (showAddTaskDialog) {
        var taskInput by remember { mutableStateOf("") }
        Dialog(showDialog = showAddTaskDialog, onDismissRequest = { showAddTaskDialog = false }) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black),
                contentAlignment = Alignment.Center
            ) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.padding(12.dp)
                ) {
                    Text(
                        text = "Add to ${currentStream?.streamShortCode ?: "Stream"}",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color(0xFF00E5FF)
                    )
                    Spacer(Modifier.height(8.dp))

                    BasicTextField(
                        value = taskInput,
                        onValueChange = { taskInput = it },
                        textStyle = TextStyle(color = Color.White, fontSize = 12.sp),
                        cursorBrush = SolidColor(Color(0xFF00E5FF)),
                        modifier = Modifier
                            .fillMaxWidth(0.9f)
                            .clip(RoundedCornerShape(8.dp))
                            .background(Color(0xFF1E222A))
                            .padding(8.dp)
                    )

                    Spacer(Modifier.height(10.dp))

                    Row(
                        modifier = Modifier.fillMaxWidth(0.9f),
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Button(
                            onClick = { showAddTaskDialog = false },
                            colors = ButtonDefaults.secondaryButtonColors(),
                            modifier = Modifier.weight(1f).height(30.dp)
                        ) {
                            Text("Cancel", fontSize = 10.sp)
                        }
                        Button(
                            onClick = {
                                if (taskInput.isNotBlank() && currentStream != null) {
                                    repository.addQuickTask(currentStream.streamNumber, taskInput)
                                    SoundAndHapticFeedback.playLogAdded(context, view)
                                }
                                showAddTaskDialog = false
                            },
                            colors = ButtonDefaults.buttonColors(backgroundColor = Color(0xFF00E5FF)),
                            modifier = Modifier.weight(1f).height(30.dp)
                        ) {
                            Text("Add", fontSize = 10.sp, fontWeight = FontWeight.Bold, color = Color.Black)
                        }
                    }
                }
            }
        }
    }

    // Add Note Dialog
    if (showAddNoteDialog) {
        var titleInput by remember { mutableStateOf("") }
        var contentInput by remember { mutableStateOf("") }
        Dialog(showDialog = showAddNoteDialog, onDismissRequest = { showAddNoteDialog = false }) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black),
                contentAlignment = Alignment.Center
            ) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.padding(10.dp)
                ) {
                    Text(
                        text = "New Quick Note",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color(0xFFFFD600)
                    )
                    Spacer(Modifier.height(6.dp))

                    BasicTextField(
                        value = titleInput,
                        onValueChange = { titleInput = it },
                        textStyle = TextStyle(color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold),
                        cursorBrush = SolidColor(Color(0xFFFFD600)),
                        decorationBox = { innerTextField ->
                            Box {
                                if (titleInput.isEmpty()) Text("Title", color = Color.Gray, fontSize = 11.sp)
                                innerTextField()
                            }
                        },
                        modifier = Modifier
                            .fillMaxWidth(0.9f)
                            .clip(RoundedCornerShape(6.dp))
                            .background(Color(0xFF1E222A))
                            .padding(6.dp)
                    )

                    Spacer(Modifier.height(4.dp))

                    BasicTextField(
                        value = contentInput,
                        onValueChange = { contentInput = it },
                        textStyle = TextStyle(color = Color.White, fontSize = 11.sp),
                        cursorBrush = SolidColor(Color(0xFFFFD600)),
                        decorationBox = { innerTextField ->
                            Box {
                                if (contentInput.isEmpty()) Text("Content", color = Color.Gray, fontSize = 11.sp)
                                innerTextField()
                            }
                        },
                        modifier = Modifier
                            .fillMaxWidth(0.9f)
                            .clip(RoundedCornerShape(6.dp))
                            .background(Color(0xFF1E222A))
                            .padding(6.dp)
                    )

                    Spacer(Modifier.height(8.dp))

                    Row(
                        modifier = Modifier.fillMaxWidth(0.9f),
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Button(
                            onClick = { showAddNoteDialog = false },
                            colors = ButtonDefaults.secondaryButtonColors(),
                            modifier = Modifier.weight(1f).height(30.dp)
                        ) {
                            Text("Cancel", fontSize = 10.sp)
                        }
                        Button(
                            onClick = {
                                repository.addQuickNote(titleInput, contentInput)
                                SoundAndHapticFeedback.playLogAdded(context, view)
                                showAddNoteDialog = false
                            },
                            colors = ButtonDefaults.buttonColors(backgroundColor = Color(0xFFFFD600)),
                            modifier = Modifier.weight(1f).height(30.dp)
                        ) {
                            Text("Save", fontSize = 10.sp, fontWeight = FontWeight.Bold, color = Color.Black)
                        }
                    }
                }
            }
        }
    }

    // View Note Detail Dialog
    if (selectedNote != null) {
        val note = selectedNote!!
        Dialog(showDialog = true, onDismissRequest = { selectedNote = null }) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black),
                contentAlignment = Alignment.Center
            ) {
                val scroll = rememberScrollState()
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .verticalScroll(scroll)
                        .padding(12.dp)
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            imageVector = Icons.Filled.PushPin,
                            contentDescription = null,
                            tint = Color(0xFFFFD600),
                            modifier = Modifier.size(12.dp)
                        )
                        Spacer(Modifier.width(4.dp))
                        Text(
                            text = note.title,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White
                        )
                    }

                    Spacer(Modifier.height(6.dp))

                    Text(
                        text = note.content,
                        fontSize = 11.sp,
                        color = Color.White.copy(alpha = 0.85f)
                    )

                    Spacer(Modifier.height(10.dp))

                    Button(
                        onClick = { selectedNote = null },
                        colors = ButtonDefaults.secondaryButtonColors(),
                        modifier = Modifier.fillMaxWidth().height(28.dp)
                    ) {
                        Text("Close", fontSize = 10.sp)
                    }
                }
            }
        }
    }
}
