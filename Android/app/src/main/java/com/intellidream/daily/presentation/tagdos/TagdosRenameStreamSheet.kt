package com.intellidream.daily.presentation.tagdos

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.designsystem.ThemeColors

/**
 * Bottom sheet to rename a stream, reset it to auto-detected domain title, reorder it, or safely delete it.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TagdosRenameStreamSheet(
    currentTitle: String,
    canDeleteStream: Boolean = false,
    onDeleteStream: (() -> Unit)? = null,
    canMoveLeft: Boolean = false,
    canMoveRight: Boolean = false,
    onMoveLeft: (() -> Unit)? = null,
    onMoveRight: (() -> Unit)? = null,
    onSaveTitle: (String?) -> Unit,
    onDismiss: () -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var text by remember(currentTitle) { mutableStateOf(currentTitle) }
    var confirmDelete by remember { mutableStateOf(false) }

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
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Text(
                text = "Rename Stream",
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White
            )

            Text(
                text = "Set a custom title for this stream. If left blank or cleared, it will automatically detect the domain from active tags.",
                fontSize = 11.5.sp,
                fontWeight = FontWeight.Normal,
                color = Color.White.copy(alpha = 0.55f)
            )

            OutlinedTextField(
                value = text,
                onValueChange = { text = it },
                label = { Text("Stream Title") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedTextColor = Color.White,
                    unfocusedTextColor = Color.White,
                    focusedBorderColor = ThemeColors.accentCyan,
                    unfocusedBorderColor = Color.White.copy(alpha = 0.2f),
                    focusedLabelColor = ThemeColors.accentCyan,
                    unfocusedLabelColor = Color.White.copy(alpha = 0.6f)
                ),
                shape = RoundedCornerShape(12.dp)
            )

            if ((onMoveLeft != null && canMoveLeft) || (onMoveRight != null && canMoveRight)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    OutlinedButton(
                        onClick = { onMoveLeft?.invoke() },
                        enabled = canMoveLeft && onMoveLeft != null,
                        modifier = Modifier.weight(1f),
                        shape = RoundedCornerShape(12.dp)
                    ) {
                        Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = null, modifier = Modifier.size(16.dp), tint = if (canMoveLeft) ThemeColors.accentCyan else Color.White.copy(alpha = 0.3f))
                        Spacer(Modifier.width(6.dp))
                        Text("Move Left", color = if (canMoveLeft) ThemeColors.accentCyan else Color.White.copy(alpha = 0.3f), fontSize = 12.sp)
                    }
                    OutlinedButton(
                        onClick = { onMoveRight?.invoke() },
                        enabled = canMoveRight && onMoveRight != null,
                        modifier = Modifier.weight(1f),
                        shape = RoundedCornerShape(12.dp)
                    ) {
                        Text("Move Right", color = if (canMoveRight) ThemeColors.accentCyan else Color.White.copy(alpha = 0.3f), fontSize = 12.sp)
                        Spacer(Modifier.width(6.dp))
                        Icon(Icons.AutoMirrored.Rounded.ArrowForward, contentDescription = null, modifier = Modifier.size(16.dp), tint = if (canMoveRight) ThemeColors.accentCyan else Color.White.copy(alpha = 0.3f))
                    }
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                TextButton(
                    onClick = {
                        onSaveTitle(null)
                        onDismiss()
                    }
                ) {
                    Text("Reset to Auto", color = ThemeColors.accentOrange, fontSize = 12.sp)
                }

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TextButton(onClick = onDismiss) {
                        Text("Cancel", color = Color.White.copy(alpha = 0.6f))
                    }
                    Button(
                        onClick = {
                            val clean = text.trim()
                            onSaveTitle(clean.ifEmpty { null })
                            onDismiss()
                        },
                        colors = ButtonDefaults.buttonColors(containerColor = ThemeColors.accentCyan),
                        shape = RoundedCornerShape(12.dp)
                    ) {
                        Text("Save", color = Color.Black, fontWeight = FontWeight.Bold)
                    }
                }
            }

            if (canDeleteStream && onDeleteStream != null) {
                if (confirmDelete) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        OutlinedButton(
                            onClick = { confirmDelete = false },
                            modifier = Modifier.weight(1f),
                            shape = RoundedCornerShape(12.dp)
                        ) {
                            Text("Keep Stream", color = Color.White.copy(alpha = 0.75f), fontSize = 12.sp)
                        }
                        Button(
                            onClick = {
                                confirmDelete = false
                                onDeleteStream()
                                onDismiss()
                            },
                            modifier = Modifier.weight(1f),
                            colors = ButtonDefaults.buttonColors(containerColor = ThemeColors.accentPink),
                            shape = RoundedCornerShape(12.dp)
                        ) {
                            Icon(Icons.Rounded.Delete, contentDescription = null, modifier = Modifier.size(16.dp), tint = Color.White)
                            Spacer(Modifier.width(4.dp))
                            Text("Confirm Delete", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 12.sp)
                        }
                    }
                } else {
                    TextButton(
                        onClick = { confirmDelete = true },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(
                            text = "Delete Stream",
                            color = ThemeColors.accentPink,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }
            }
        }
    }
}
