package com.intellidream.daily.wearos.presentation.logs

import android.view.HapticFeedbackConstants
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Delete
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.ButtonDefaults
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.dialog.Dialog
import com.intellidream.daily.wearos.domain.model.HabitLog
import com.intellidream.daily.wearos.util.SoundAndHapticFeedback
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

@Composable
fun HabitLogsScreen(
    habitType: String,
    dateTitle: String,
    logs: List<HabitLog>,
    onDeleteLog: (HabitLog) -> Unit,
    onClose: () -> Unit
) {
    val context = LocalContext.current
    val view = LocalView.current
    val listState = rememberScalingLazyListState()
    var logToDelete by remember { mutableStateOf<HabitLog?>(null) }

    val timeFormat = remember { SimpleDateFormat("HH:mm", Locale.getDefault()) }
    val parseFormat = remember {
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }
    }

    val isWater = habitType == "water"
    val screenTitle = if (isWater) "💧 Water Logs" else "🔥 Smoke Logs"
    val accentColor = if (isWater) Color.Cyan else Color(0xFFFF5555)

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
    ) {
        ScalingLazyColumn(
            state = listState,
            modifier = Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // Header
            item {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 8.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(
                        modifier = Modifier
                            .size(32.dp)
                            .clip(CircleShape)
                            .background(Color(0xFF222222))
                            .clickable {
                                SoundAndHapticFeedback.playClick(context, view)
                                onClose()
                            },
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = Icons.Filled.ArrowBack,
                            contentDescription = "Back",
                            tint = Color.White,
                            modifier = Modifier.size(16.dp)
                        )
                    }
                    Spacer(Modifier.width(8.dp))
                    Column {
                        Text(
                            text = screenTitle,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Bold,
                            color = accentColor
                        )
                        Text(
                            text = "${logs.size} entries • $dateTitle",
                            fontSize = 10.sp,
                            color = Color.Gray
                        )
                    }
                }
            }

            if (logs.isEmpty()) {
                item {
                    Spacer(Modifier.height(24.dp))
                    Text(
                        text = "No logs recorded for this day.",
                        fontSize = 11.sp,
                        color = Color.Gray,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(horizontal = 16.dp)
                    )
                }
            } else {
                items(logs) { log ->
                    val isCoffee = log.metadata?.contains("Coffee") == true
                    val isSmall = log.metadata?.contains("Small Water") == true
                    val isHeat = log.metadata?.contains("Heated") == true

                    val emoji = when {
                        isWater && isCoffee -> "☕"
                        isWater -> "💧"
                        isHeat -> "⚡"
                        else -> "🔥"
                    }

                    val label = when {
                        isWater && isCoffee -> "${log.value.toInt()} ml Coffee"
                        isWater && isSmall -> "${log.value.toInt()} ml Small"
                        isWater -> "${log.value.toInt()} ml Large"
                        isHeat -> "1 Heat"
                        else -> "1 Cig"
                    }

                    val timeStr = remember(log.logged_at) {
                        try {
                            val pureUTC = log.logged_at.replace("Z", "") + "Z"
                            val date = parseFormat.parse(pureUTC)
                            if (date != null) timeFormat.format(date) else ""
                        } catch (_: Exception) { "" }
                    }

                    Box(
                        modifier = Modifier
                            .fillMaxWidth(0.92f)
                            .padding(vertical = 3.dp)
                            .clip(RoundedCornerShape(10.dp))
                            .background(Color(0xFF1C1C1E))
                            .padding(horizontal = 10.dp, vertical = 8.dp)
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween,
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(emoji, fontSize = 15.sp)
                                Spacer(Modifier.width(6.dp))
                                Column {
                                    Text(
                                        text = label,
                                        fontSize = 12.sp,
                                        fontWeight = FontWeight.Medium,
                                        color = Color.White
                                    )
                                    if (timeStr.isNotEmpty()) {
                                        Text(
                                            text = timeStr,
                                            fontSize = 9.sp,
                                            color = Color.Gray
                                        )
                                    }
                                }
                            }

                            // Delete icon button
                            Box(
                                modifier = Modifier
                                    .size(28.dp)
                                    .clip(CircleShape)
                                    .background(Color(0x33FF3B30))
                                    .clickable {
                                        SoundAndHapticFeedback.playClick(context, view)
                                        logToDelete = log
                                    },
                                contentAlignment = Alignment.Center
                            ) {
                                Icon(
                                    imageVector = Icons.Filled.Delete,
                                    contentDescription = "Delete",
                                    tint = Color(0xFFFF3B30),
                                    modifier = Modifier.size(14.dp)
                                )
                            }
                        }
                    }
                }
            }
        }

        // Delete Confirmation Dialog
        logToDelete?.let { log ->
            Dialog(
                showDialog = true,
                onDismissRequest = { logToDelete = null }
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color.Black)
                        .padding(12.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    Text(
                        text = "Delete Log?",
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                    Spacer(Modifier.height(6.dp))
                    Text(
                        text = "This will permanently remove this entry.",
                        fontSize = 10.sp,
                        color = Color.Gray,
                        textAlign = TextAlign.Center
                    )
                    Spacer(Modifier.height(12.dp))
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceEvenly
                    ) {
                        Button(
                            onClick = {
                                SoundAndHapticFeedback.playClick(context, view)
                                logToDelete = null
                            },
                            colors = ButtonDefaults.buttonColors(backgroundColor = Color(0xFF333333)),
                            modifier = Modifier.weight(1f).height(32.dp).padding(end = 4.dp),
                            shape = RoundedCornerShape(8.dp)
                        ) {
                            Text("Cancel", fontSize = 11.sp, color = Color.White)
                        }
                        Button(
                            onClick = {
                                SoundAndHapticFeedback.playClick(context, view)
                                val target = log
                                logToDelete = null
                                onDeleteLog(target)
                            },
                            colors = ButtonDefaults.buttonColors(backgroundColor = Color(0xFFFF3B30)),
                            modifier = Modifier.weight(1f).height(32.dp).padding(start = 4.dp),
                            shape = RoundedCornerShape(8.dp)
                        ) {
                            Text("Delete", fontSize = 11.sp, color = Color.White, fontWeight = FontWeight.Bold)
                        }
                    }
                }
            }
        }
    }
}
