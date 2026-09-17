package com.intellidream.daily.presentation.tagdos

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.North
import androidx.compose.material.icons.rounded.Sync
import androidx.compose.material.icons.rounded.Undo
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.TagDoPill
import com.intellidream.daily.model.TagDoPillType

/**
 * Bottom sheet displaying interactive lifecycle operations for a TagDoS pill.
 * 1:1 Kotlin port of iOS [pillActionSheet in TagdosNotesHubView.swift].
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TagdosPillActionSheet(
    pill: TagDoPill,
    onRecycle: () -> Unit,
    onToggleCompletion: () -> Unit,
    onMoveToFront: () -> Unit,
    onDelete: () -> Unit,
    onDismiss: () -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val pillColor = when (pill.type) {
        TagDoPillType.Standard -> Color(0xFF00E5FF)
        TagDoPillType.Financial -> Color(0xFF00E676)
        TagDoPillType.Urgent -> Color(0xFFFF2D55)
        TagDoPillType.TemporalOrMetric -> Color(0xFFFFD600)
        TagDoPillType.Completed -> Color.White.copy(alpha = 0.35f)
    }

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
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            // Pill Title Header
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Tag: ${pill.rawText}",
                    fontSize = 19.sp,
                    fontWeight = FontWeight.Bold,
                    color = pillColor
                )
                Spacer(modifier = Modifier.weight(1f))
            }

            // Options List
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                // Option 1: Recycle to back (Recurring)
                PillActionRow(
                    icon = Icons.Rounded.Sync,
                    iconTint = ThemeColors.accentCyan,
                    title = "Recycle to Back (Mută la coadă • Recurent)",
                    backgroundColor = Color.White.copy(alpha = 0.06f),
                    textColor = Color.White,
                    onClick = {
                        onRecycle()
                        onDismiss()
                    }
                )

                // Option 2: Toggle Done (Stay in place)
                PillActionRow(
                    icon = if (pill.isCompleted) Icons.Rounded.Undo else Icons.Rounded.CheckCircle,
                    iconTint = ThemeColors.accentGreen,
                    title = if (pill.isCompleted) "Unmark / Debifează" else "Mark Done (Bifează pe loc)",
                    backgroundColor = Color.White.copy(alpha = 0.06f),
                    textColor = Color.White,
                    onClick = {
                        onToggleCompletion()
                        onDismiss()
                    }
                )

                // Option 3: Move to Front (Prioritize)
                PillActionRow(
                    icon = Icons.Rounded.North,
                    iconTint = ThemeColors.accentOrange,
                    title = "Prioritizează la început de șir",
                    backgroundColor = Color.White.copy(alpha = 0.06f),
                    textColor = Color.White,
                    onClick = {
                        onMoveToFront()
                        onDismiss()
                    }
                )

                // Option 4: Delete permanently (One-off)
                PillActionRow(
                    icon = Icons.Rounded.Delete,
                    iconTint = ThemeColors.accentPink,
                    title = "Șterge definitiv (One-Off Task)",
                    backgroundColor = ThemeColors.accentPink.copy(alpha = 0.10f),
                    textColor = ThemeColors.accentPink,
                    onClick = {
                        onDelete()
                        onDismiss()
                    }
                )
            }
        }
    }
}

@Composable
private fun PillActionRow(
    icon: ImageVector,
    iconTint: Color,
    title: String,
    backgroundColor: Color,
    textColor: Color,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(backgroundColor)
            .clickable(onClick = onClick)
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = iconTint,
            modifier = Modifier.size(18.dp)
        )
        Text(
            text = title,
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold,
            color = textColor
        )
    }
}
