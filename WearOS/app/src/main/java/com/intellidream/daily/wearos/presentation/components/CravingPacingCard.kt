package com.intellidream.daily.wearos.presentation.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.Spa
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.Text
import com.intellidream.daily.wearos.data.WatchSessionManager
import com.intellidream.daily.wearos.presentation.theme.DailyWearColors

@Composable
fun CravingPacingCard(sessionManager: WatchSessionManager) {
    var showSighDialog by remember { mutableStateOf(false) }

    val refreshTrigger by sessionManager.dataRefreshTrigger.collectAsState()
    var tick by remember { mutableStateOf(0L) }
    LaunchedEffect(Unit) {
        while (true) {
            kotlinx.coroutines.delay(30000L)
            tick++
        }
    }

    val formattedTime = remember(refreshTrigger, tick) {
        sessionManager.getFormattedTimeSinceLastSmoke()
    }
    val isWarning = remember(refreshTrigger, tick) {
        sessionManager.isCravingWarning()
    }
    val badgeColor = remember(formattedTime, isWarning) {
        when {
            isWarning -> DailyWearColors.CoffeeOrange
            formattedTime.contains("Smoke-Free") -> Color(0xFF10B981)
            formattedTime.contains("h") && !formattedTime.startsWith("0h") -> Color(0xFF10B981)
            else -> Color(0xFFEAB308)
        }
    }

    Box(
        modifier = Modifier
            .fillMaxWidth(0.94f)
            .clip(RoundedCornerShape(14.dp))
            .background(Color.White.copy(alpha = 0.08f))
            .padding(horizontal = 10.dp, vertical = 5.dp),
        contentAlignment = Alignment.Center
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Left: Timer icon and craving-free text (wrapping to 2 lines when needed)
            Row(
                modifier = Modifier
                    .weight(1f)
                    .padding(end = 6.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = Icons.Filled.Timer,
                    contentDescription = null,
                    tint = badgeColor,
                    modifier = Modifier.size(12.dp)
                )
                Spacer(Modifier.width(4.dp))
                Text(
                    text = formattedTime,
                    fontSize = 11.sp,
                    lineHeight = 13.sp,
                    maxLines = 2,
                    fontWeight = FontWeight.SemiBold,
                    color = badgeColor
                )
            }

            // Right: Breathe action chip (strictly single-line, never squished)
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(8.dp))
                    .background(Color(0xFF10B981).copy(alpha = 0.2f))
                    .clickable { showSighDialog = true }
                    .padding(horizontal = 7.dp, vertical = 4.dp),
                contentAlignment = Alignment.Center
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center
                ) {
                    Icon(
                        imageVector = Icons.Filled.Spa,
                        contentDescription = "Breathe",
                        tint = Color(0xFF10B981),
                        modifier = Modifier.size(10.dp)
                    )
                    Spacer(Modifier.width(3.dp))
                    Text(
                        text = "Breathe",
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color(0xFF10B981),
                        maxLines = 1,
                        softWrap = false
                    )
                }
            }
        }
    }

    if (showSighDialog) {
        PhysiologicalSighDialog(show = showSighDialog, onDismiss = { showSighDialog = false })
    }
}
