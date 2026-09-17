package com.intellidream.daily.presentation.tagdos

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Clear
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.PushPin
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.database.TagdosRepository
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.TagDoQuickNote
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

import androidx.compose.foundation.clickable

/**
 * Dedicated Quick Notes stream featuring search, pinning, and Markdown note editing.
 * 1:1 Kotlin port of iOS [TagdosQuickNotesView.swift].
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun TagdosQuickNotesView(
    repository: TagdosRepository
) {
    val quickNotes by repository.quickNotes.collectAsState()
    var searchText by remember { mutableStateOf("") }
    var activeEditingNote by remember { mutableStateOf<TagDoQuickNote?>(null) }
    var isCreatingNewNote by remember { mutableStateOf(false) }

    val filteredNotes = remember(quickNotes, searchText) {
        val query = searchText.trim().lowercase()
        if (query.isEmpty()) {
            quickNotes
        } else {
            quickNotes.filter {
                it.title.lowercase().contains(query) || it.content.lowercase().contains(query)
            }
        }
    }

    val pinnedNotes = remember(filteredNotes) { filteredNotes.filter { it.isPinned } }
    val unpinnedNotes = remember(filteredNotes) { filteredNotes.filter { !it.isPinned } }

    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        // MARK: - Search & New Note Action Bar
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            OutlinedTextField(
                value = searchText,
                onValueChange = { searchText = it },
                placeholder = { Text("Search notes...", color = Color.White.copy(alpha = 0.4f), fontSize = 13.sp) },
                leadingIcon = {
                    Icon(
                        imageVector = Icons.Rounded.Search,
                        contentDescription = null,
                        tint = Color.White.copy(alpha = 0.5f),
                        modifier = Modifier.size(16.dp)
                    )
                },
                trailingIcon = {
                    if (searchText.isNotEmpty()) {
                        IconButton(onClick = { searchText = "" }) {
                            Icon(
                                imageVector = Icons.Rounded.Clear,
                                contentDescription = "Clear",
                                tint = Color.White.copy(alpha = 0.5f),
                                modifier = Modifier.size(16.dp)
                            )
                        }
                    }
                },
                singleLine = true,
                modifier = Modifier.weight(1f),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedTextColor = Color.White,
                    unfocusedTextColor = Color.White,
                    focusedBorderColor = ThemeColors.accentCyan,
                    unfocusedBorderColor = Color.White.copy(alpha = 0.12f)
                ),
                shape = RoundedCornerShape(12.dp)
            )

            // New Note Button
            Box(
                modifier = Modifier
                    .clip(CircleShape)
                    .background(ThemeColors.accentCyan)
                    .clickable {
                        activeEditingNote = TagDoQuickNote()
                        isCreatingNewNote = true
                    }
                    .padding(horizontal = 14.dp, vertical = 10.dp),
                contentAlignment = Alignment.Center
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Add,
                        contentDescription = null,
                        tint = Color.Black,
                        modifier = Modifier.size(14.dp)
                    )
                    Text(
                        text = "New",
                        color = Color.Black,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
            }
        }

        // MARK: - Notes List
        if (filteredNotes.isEmpty()) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 40.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Icon(
                    imageVector = Icons.Rounded.Description,
                    contentDescription = null,
                    tint = Color.White.copy(alpha = 0.3f),
                    modifier = Modifier.size(36.dp)
                )
                Text(
                    text = if (searchText.isBlank()) "No Quick Notes yet" else "No matching notes found",
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                    color = Color.White.copy(alpha = 0.5f)
                )
                if (searchText.isBlank()) {
                    Text(
                        text = "Tap '+ New' to create your first note.",
                        fontSize = 12.sp,
                        color = Color.White.copy(alpha = 0.35f)
                    )
                }
            }
        } else {
            // Pinned Notes Section
            if (pinnedNotes.isNotEmpty()) {
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(5.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.PushPin,
                            contentDescription = null,
                            tint = ThemeColors.accentOrange,
                            modifier = Modifier.size(12.dp)
                        )
                        Text(
                            text = "Pinned",
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold,
                            color = ThemeColors.accentOrange
                        )
                    }

                    pinnedNotes.forEach { note ->
                        QuickNoteRowCard(
                            note = note,
                            onClick = {
                                activeEditingNote = note
                                isCreatingNewNote = false
                            },
                            onTogglePin = { repository.togglePinQuickNote(note.id) },
                            onDelete = { repository.deleteQuickNote(note.id) }
                        )
                    }
                }
            }

            // All Notes Section
            if (unpinnedNotes.isNotEmpty()) {
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    if (pinnedNotes.isNotEmpty()) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(5.dp)
                        ) {
                            Icon(
                                imageVector = Icons.Rounded.Description,
                                contentDescription = null,
                                tint = Color.White.copy(alpha = 0.45f),
                                modifier = Modifier.size(12.dp)
                            )
                            Text(
                                text = "All Notes",
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color.White.copy(alpha = 0.45f)
                            )
                        }
                    }

                    unpinnedNotes.forEach { note ->
                        QuickNoteRowCard(
                            note = note,
                            onClick = {
                                activeEditingNote = note
                                isCreatingNewNote = false
                            },
                            onTogglePin = { repository.togglePinQuickNote(note.id) },
                            onDelete = { repository.deleteQuickNote(note.id) }
                        )
                    }
                }
            }
        }
    }

    // Markdown Note Editor Bottom Sheet
    activeEditingNote?.let { note ->
        MarkdownNoteEditorSheet(
            note = note,
            isNew = isCreatingNewNote,
            onSave = { updated ->
                if (isCreatingNewNote) {
                    repository.createQuickNote(updated.title, updated.content)
                } else {
                    repository.updateQuickNote(updated.id, updated.title, updated.content)
                }
                activeEditingNote = null
            },
            onDelete = { id ->
                repository.deleteQuickNote(id)
                activeEditingNote = null
            },
            onDismiss = { activeEditingNote = null }
        )
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun QuickNoteRowCard(
    note: TagDoQuickNote,
    onClick: () -> Unit,
    onTogglePin: () -> Unit,
    onDelete: () -> Unit
) {
    var showMenu by remember { mutableStateOf(false) }
    val sdf = remember { SimpleDateFormat("d MMM, HH:mm", Locale.getDefault()) }
    val formattedDate = remember(note.updatedAt) { sdf.format(Date(note.updatedAt)) }

    Box {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(14.dp))
                .background(Color.White.copy(alpha = 0.04f))
                .combinedClickable(
                    onClick = onClick,
                    onLongClick = { showMenu = true }
                )
                .padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = note.displayTitle,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false)
                )

                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    if (note.isPinned) {
                        Icon(
                            imageVector = Icons.Rounded.PushPin,
                            contentDescription = null,
                            tint = ThemeColors.accentOrange,
                            modifier = Modifier.size(12.dp)
                        )
                    }
                    Text(
                        text = formattedDate,
                        fontSize = 10.5.sp,
                        fontWeight = FontWeight.Medium,
                        color = Color.White.copy(alpha = 0.45f)
                    )
                }
            }

            if (note.previewSnippet.isNotBlank()) {
                Text(
                    text = note.previewSnippet,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Normal,
                    color = Color.White.copy(alpha = 0.65f),
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    lineHeight = 16.sp
                )
            }
        }

        DropdownMenu(
            expanded = showMenu,
            onDismissRequest = { showMenu = false },
            modifier = Modifier.background(Color(0xFF0D182E))
        ) {
            DropdownMenuItem(
                text = { Text(if (note.isPinned) "Unpin Note" else "Pin to Top", color = Color.White) },
                onClick = {
                    showMenu = false
                    onTogglePin()
                }
            )
            DropdownMenuItem(
                text = { Text("Delete Note", color = ThemeColors.accentPink) },
                onClick = {
                    showMenu = false
                    onDelete()
                }
            )
        }
    }
}
