package com.intellidream.daily.wearos.presentation.about

import android.content.Context
import android.view.HapticFeedbackConstants
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.ButtonDefaults
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.dialog.Alert
import androidx.wear.compose.material.dialog.Dialog
import com.google.android.horologist.annotations.ExperimentalHorologistApi
import com.google.android.horologist.compose.layout.ScalingLazyColumn
import com.google.android.horologist.compose.layout.ScalingLazyColumnState
import com.google.android.horologist.compose.layout.ScreenScaffold
import com.google.android.horologist.compose.layout.rememberResponsiveColumnState
import com.intellidream.daily.wearos.R
import com.intellidream.daily.wearos.data.WatchSessionManager
import com.intellidream.daily.wearos.presentation.theme.DailyWearColors
import com.intellidream.daily.wearos.util.SoundAndHapticFeedback
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalHorologistApi::class)
@Composable
fun AboutScreen(
    sessionManager: WatchSessionManager,
    isPageActive: Boolean = true
) {
    val context = LocalContext.current
    val view = LocalView.current
    val columnState = rememberResponsiveColumnState(
        rotaryMode = ScalingLazyColumnState.RotaryMode.Snap
    )
    var showUnpairDialog by remember { mutableStateOf(false) }
    var syncText by remember { mutableStateOf("Not Synced") }
    var syncColor by remember { mutableStateOf(DailyWearColors.SmokeRed) }

    LaunchedEffect(isPageActive) {
        try {
            val prefs = context.getSharedPreferences(WatchSessionManager.PREFS_NAME, Context.MODE_PRIVATE)
            val lastSyncStr = prefs.getString(WatchSessionManager.KEY_LAST_HEALTH_SYNC, null)
            val lastSyncStatus = prefs.getString(WatchSessionManager.KEY_LAST_HEALTH_SYNC_STATUS, null)
            val lastSyncTime = lastSyncStr?.toLongOrNull() ?: 0L
            if (lastSyncStatus == "no_new_data") {
                syncText = "No New Data"
                syncColor = DailyWearColors.CoffeeOrange
            } else if (lastSyncTime > 0) {
                val fmt = SimpleDateFormat("d MMM, HH:mm:ss", Locale.getDefault())
                val dtStr = fmt.format(Date(lastSyncTime))
                syncText = "Synced at $dtStr"
                syncColor = DailyWearColors.WaterCyan
            } else {
                syncText = "Not Synced"
                syncColor = DailyWearColors.SmokeRed
            }
        } catch (_: Exception) {}
    }

    ScreenScaffold(
        scrollState = columnState
    ) {
        ScalingLazyColumn(
            columnState = columnState,
            modifier = Modifier.fillMaxSize()
        ) {
            // App Logo & Identity
            item {
                Spacer(Modifier.height(4.dp))
                Image(
                    painter = painterResource(id = R.drawable.orbit_logo),
                    contentDescription = "Daily Orbit Logo",
                    modifier = Modifier
                        .size(48.dp)
                        .clip(RoundedCornerShape(12.dp))
                )
            }

            item {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.fillMaxWidth().padding(top = 4.dp, bottom = 4.dp)
                ) {
                    Text(
                        text = "Daily Orbit",
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White,
                        textAlign = TextAlign.Center
                    )
                    Spacer(Modifier.height(2.dp))
                    Text(
                        text = "Pixel Watch Edition • v1.0",
                        fontSize = 11.sp,
                        color = Color.White.copy(alpha = 0.5f),
                        textAlign = TextAlign.Center
                    )
                }
            }

            // Connection & Health Telemetry Card
            item {
                Spacer(Modifier.height(6.dp))
                Box(
                    modifier = Modifier
                        .fillMaxWidth(0.92f)
                        .clip(RoundedCornerShape(16.dp))
                        .background(Color(0xFF141820))
                        .border(1.dp, Color.White.copy(alpha = 0.05f), RoundedCornerShape(16.dp))
                        .padding(horizontal = 14.dp, vertical = 10.dp)
                ) {
                    Column(modifier = Modifier.fillMaxWidth()) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                text = "Status",
                                fontSize = 11.sp,
                                color = Color.White.copy(alpha = 0.5f)
                            )
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Box(
                                    modifier = Modifier
                                        .size(7.dp)
                                        .clip(CircleShape)
                                        .background(DailyWearColors.SmokeGreen)
                                )
                                Spacer(Modifier.width(5.dp))
                                Text(
                                    text = "Connected",
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = DailyWearColors.SmokeGreen
                                )
                            }
                        }

                        Spacer(Modifier.height(8.dp))
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(1.dp)
                                .background(Color.White.copy(alpha = 0.06f))
                        )
                        Spacer(Modifier.height(8.dp))

                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                text = "Health",
                                fontSize = 11.sp,
                                color = Color.White.copy(alpha = 0.5f)
                            )
                            Text(
                                text = syncText,
                                fontSize = 10.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = syncColor
                            )
                        }
                    }
                }
            }

            // Unpair Watch Full-Width Action Chip
            item {
                Spacer(Modifier.height(8.dp))
                Box(
                    modifier = Modifier
                        .fillMaxWidth(0.92f)
                        .height(44.dp)
                        .clip(RoundedCornerShape(22.dp))
                        .background(DailyWearColors.SmokeRedTonal)
                        .border(1.dp, DailyWearColors.SmokeRed.copy(alpha = 0.35f), RoundedCornerShape(22.dp))
                        .clickable {
                            SoundAndHapticFeedback.playClick(context, view)
                            showUnpairDialog = true
                        },
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = "Unpair Watch",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                        color = DailyWearColors.SmokeRed
                    )
                }
                Spacer(Modifier.height(16.dp))
            }
        }
    }

    // Unpair Confirmation Dialog
    if (showUnpairDialog) {
        Dialog(
            showDialog = true,
            onDismissRequest = { showUnpairDialog = false }
        ) {
            Alert(
                title = {
                    Text(
                        text = "Unpair Watch?",
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold,
                        textAlign = TextAlign.Center
                    )
                },
                content = {
                    item {
                        Text(
                            text = "This will disconnect this watch from your Daily account.",
                            fontSize = 11.sp,
                            color = Color.White.copy(alpha = 0.6f),
                            textAlign = TextAlign.Center
                        )
                    }
                    item {
                        Spacer(Modifier.height(10.dp))
                        Button(
                            onClick = {
                                view.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
                                showUnpairDialog = false
                                sessionManager.logout()
                            },
                            colors = ButtonDefaults.buttonColors(backgroundColor = DailyWearColors.SmokeRed),
                            modifier = Modifier.fillMaxWidth().height(36.dp)
                        ) {
                            Text("Unpair", fontSize = 12.sp, color = Color.White, fontWeight = FontWeight.Bold)
                        }
                    }
                    item {
                        Spacer(Modifier.height(4.dp))
                        Button(
                            onClick = {
                                SoundAndHapticFeedback.playClick(context, view)
                                showUnpairDialog = false
                            },
                            colors = ButtonDefaults.buttonColors(backgroundColor = Color(0xFF262A32)),
                            modifier = Modifier.fillMaxWidth().height(36.dp)
                        ) {
                            Text("Cancel", fontSize = 12.sp, color = Color.LightGray)
                        }
                    }
                }
            )
        }
    }
}
