package com.intellidream.daily.presentation.tagdos

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AttachFile
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.KeyboardArrowUp
import androidx.compose.material3.Icon
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.database.TagdosRepository
import com.intellidream.daily.designsystem.ThemeColors

/**
 * Interactive per-stream memo and attachment viewer with Markdown formatting,
 * collapsible header, and inline editing.
 * 1:1 Kotlin port of iOS [TagdosActiveMemoView.swift].
 */
@Composable
fun TagdosActiveMemoView(
    streamId: String,
    streamNumber: Int,
    repository: TagdosRepository
) {
    val streams by repository.streams.collectAsState()
    val currentStream = streams.firstOrNull { it.id == streamId }

    var isCollapsed by remember { mutableStateOf(true) }
    var isEditingText by remember { mutableStateOf(false) }
    var memoDraft by remember(currentStream?.activeMemos) {
        mutableStateOf(currentStream?.activeMemos ?: "")
    }

    val hasMemos = currentStream?.activeMemos?.trim()?.isNotEmpty() == true
    val attCount = currentStream?.attachments?.size ?: 0

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(Color.White.copy(alpha = 0.04f))
            .padding(if (isCollapsed) 12.dp else 14.dp),
        verticalArrangement = Arrangement.spacedBy(if (isCollapsed) 0.dp else 14.dp)
    ) {
        // MARK: - Collapsible Header
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(8.dp))
                    .clickable { isCollapsed = !isCollapsed }
            ) {
                Icon(
                    imageVector = Icons.Rounded.Description,
                    contentDescription = null,
                    tint = ThemeColors.accentCyan,
                    modifier = Modifier.size(16.dp)
                )
                Text(
                    text = "Active Memos",
                    fontSize = 13.5.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White
                )

                if (hasMemos || attCount > 0) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(Color.White.copy(alpha = 0.08f))
                            .padding(horizontal = 6.dp, vertical = 2.dp)
                    ) {
                        if (hasMemos) {
                            Text(
                                text = "Memo",
                                fontSize = 9.5.sp,
                                fontWeight = FontWeight.Bold,
                                color = ThemeColors.accentCyan
                            )
                        }
                        if (attCount > 0) {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(2.dp)
                            ) {
                                Icon(
                                    imageVector = Icons.Rounded.AttachFile,
                                    contentDescription = null,
                                    tint = ThemeColors.accentOrange,
                                    modifier = Modifier.size(9.dp)
                                )
                                Text(
                                    text = "$attCount",
                                    fontSize = 9.5.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = ThemeColors.accentOrange
                                )
                            }
                        }
                    }
                }
            }

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                if (!isCollapsed) {
                    Box(
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(
                                (if (isEditingText) ThemeColors.accentGreen else ThemeColors.accentCyan).copy(alpha = 0.18f)
                            )
                            .clickable {
                                if (isEditingText) {
                                    repository.updateStreamMemos(streamId, memoDraft)
                                    isEditingText = false
                                } else {
                                    memoDraft = currentStream?.activeMemos ?: ""
                                    isEditingText = true
                                }
                            }
                            .padding(horizontal = 9.dp, vertical = 4.dp)
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(3.dp)
                        ) {
                            Icon(
                                imageVector = if (isEditingText) Icons.Rounded.Check else Icons.Rounded.Edit,
                                contentDescription = null,
                                tint = if (isEditingText) ThemeColors.accentGreen else ThemeColors.accentCyan,
                                modifier = Modifier.size(11.dp)
                            )
                            Text(
                                text = if (isEditingText) "Done" else "Edit",
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold,
                                color = if (isEditingText) ThemeColors.accentGreen else ThemeColors.accentCyan
                            )
                        }
                    }
                }

                Box(
                    modifier = Modifier
                        .size(24.dp)
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.06f))
                        .clickable { isCollapsed = !isCollapsed },
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = if (isCollapsed) Icons.Rounded.KeyboardArrowDown else Icons.Rounded.KeyboardArrowUp,
                        contentDescription = null,
                        tint = Color.White.copy(alpha = 0.45f),
                        modifier = Modifier.size(16.dp)
                    )
                }
            }
        }

        // Expanded Body
        AnimatedVisibility(
            visible = !isCollapsed,
            enter = expandVertically() + fadeIn(),
            exit = shrinkVertically() + fadeOut()
        ) {
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                if (isEditingText) {
                    OutlinedTextField(
                        value = memoDraft,
                        onValueChange = { memoDraft = it },
                        placeholder = {
                            Text(
                                "Add reference notes, credentials, deep links, or details for Stream $streamNumber...",
                                color = Color.White.copy(alpha = 0.35f),
                                fontSize = 13.sp
                            )
                        },
                        modifier = Modifier.fillMaxWidth(),
                        minLines = 4,
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedTextColor = Color.White,
                            unfocusedTextColor = Color.White,
                            focusedBorderColor = ThemeColors.accentCyan,
                            unfocusedBorderColor = Color.White.copy(alpha = 0.15f)
                        ),
                        shape = RoundedCornerShape(12.dp)
                    )
                } else {
                    if (hasMemos) {
                        Text(
                            text = currentStream?.activeMemos.orEmpty(),
                            fontSize = 13.5.sp,
                            fontWeight = FontWeight.Normal,
                            color = Color.White.copy(alpha = 0.85f),
                            lineHeight = 19.sp,
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(10.dp))
                                .background(Color.White.copy(alpha = 0.03f))
                                .padding(10.dp)
                        )
                    } else {
                        Text(
                            text = "Tap 'Edit' to add reference links, credentials, or notes for Stream $streamNumber.",
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Normal,
                            color = Color.White.copy(alpha = 0.40f)
                        )
                    }
                }

                // Attachments List if any
                if (attCount > 0) {
                    Column(
                        modifier = Modifier.fillMaxWidth(),
                        verticalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Text(
                            text = "ATTACHMENTS ($attCount)",
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White.copy(alpha = 0.45f)
                        )

                        currentStream?.attachments?.forEach { att ->
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clip(RoundedCornerShape(8.dp))
                                    .background(Color.White.copy(alpha = 0.05f))
                                    .padding(horizontal = 10.dp, vertical = 6.dp),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                                ) {
                                    Icon(
                                        imageVector = Icons.Rounded.AttachFile,
                                        contentDescription = null,
                                        tint = ThemeColors.accentCyan,
                                        modifier = Modifier.size(13.dp)
                                    )
                                    Text(
                                        text = att.fileName,
                                        fontSize = 12.sp,
                                        fontWeight = FontWeight.Medium,
                                        color = Color.White
                                    )
                                }
                                Text(
                                    text = att.formattedSize,
                                    fontSize = 10.5.sp,
                                    color = Color.White.copy(alpha = 0.5f)
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
