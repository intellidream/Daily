package com.intellidream.daily.wearos.presentation.about

import android.view.HapticFeedbackConstants
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.rotary.onRotaryScrollEvent
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.ButtonDefaults
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.dialog.Dialog
import com.intellidream.daily.wearos.R
import com.intellidream.daily.wearos.data.WatchSessionManager
import android.content.Context
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

@Composable
fun AboutScreen(sessionManager: WatchSessionManager) {
    val context = LocalContext.current
    val view = LocalView.current
    val listState = rememberScalingLazyListState()
    val scope = rememberCoroutineScope()
    val focusRequester = remember { FocusRequester() }
    var showUnpairDialog by remember { mutableStateOf(false) }
    var syncText by remember { mutableStateOf("synced") }
    var syncColor by remember { mutableStateOf(Color(0xFFFFCC00)) }

    LaunchedEffect(Unit) {
        try {
            focusRequester.requestFocus()
        } catch (_: Exception) {}
        try {
            val prefs = context.getSharedPreferences(WatchSessionManager.PREFS_NAME, Context.MODE_PRIVATE)
            val lastSyncStr = prefs.getString(WatchSessionManager.KEY_LAST_HEALTH_SYNC, null)
            val lastSyncTime = lastSyncStr?.toLongOrNull() ?: 0L
            if (lastSyncTime > 0) {
                val cal = Calendar.getInstance()
                val syncCal = Calendar.getInstance().apply { timeInMillis = lastSyncTime }
                val isToday = cal.get(Calendar.YEAR) == syncCal.get(Calendar.YEAR) &&
                        cal.get(Calendar.DAY_OF_YEAR) == syncCal.get(Calendar.DAY_OF_YEAR)
                val timeFmt = SimpleDateFormat("HH:mm", Locale.getDefault())
                val timeStr = timeFmt.format(Date(lastSyncTime))
                if (isToday) {
                    syncText = "synced at $timeStr"
                    syncColor = Color(0xFFFFCC00)
                } else {
                    val dateFmt = SimpleDateFormat("d MMM", Locale.getDefault())
                    val dateStr = dateFmt.format(Date(lastSyncTime))
                    syncText = "synced at $timeStr, $dateStr"
                    syncColor = Color(0xFFFFCC00)
                }
            } else {
                syncText = "not synced"
                syncColor = Color(0xFFFF3B30)
            }
        } catch (_: Exception) {}
    }

    Box(modifier = Modifier.fillMaxSize().background(Color.Black)) {
        ScalingLazyColumn(
            state = listState,
            autoCentering = null,
            contentPadding = PaddingValues(top = 22.dp, bottom = 28.dp, start = 8.dp, end = 8.dp),
            modifier = Modifier
                .fillMaxSize()
                .focusRequester(focusRequester)
                .focusable()
                .onRotaryScrollEvent {
                    scope.launch {
                        listState.scrollBy(it.verticalScrollPixels)
                    }
                    true
                },
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            item {
                Spacer(Modifier.height(8.dp))
                // Orbit Logo
                Image(
                    painter = painterResource(id = R.drawable.orbit_logo),
                    contentDescription = "DayOne Orbit Logo",
                    modifier = Modifier
                        .size(44.dp)
                        .clip(RoundedCornerShape(10.dp))
                )
            }

            item {
                Spacer(Modifier.height(4.dp))
                Text(
                    text = "DayOne Orbit",
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White
                )
                Text(
                    text = "v1.0",
                    fontSize = 11.sp,
                    color = Color.Gray
                )
            }

            item {
                Spacer(Modifier.height(8.dp))
                Box(
                    modifier = Modifier
                        .fillMaxWidth(0.85f)
                        .height(1.dp)
                        .background(Color.White.copy(alpha = 0.15f))
                )
                Spacer(Modifier.height(6.dp))
            }

            item {
                Column(
                    modifier = Modifier
                        .fillMaxWidth(0.85f)
                        .padding(horizontal = 4.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text("Status:", fontSize = 11.sp, color = Color.Gray)
                        Text("Connected", fontSize = 11.sp, fontWeight = FontWeight.Medium, color = Color(0xFF4CAF50))
                    }

                    Spacer(Modifier.height(4.dp))

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("Health:", fontSize = 11.sp, color = Color.Gray)
                        Text(syncText, fontSize = 10.sp, fontWeight = FontWeight.Medium, color = syncColor)
                    }
                }
            }

            item {
                Spacer(Modifier.height(8.dp))
                Box(
                    modifier = Modifier
                        .fillMaxWidth(0.85f)
                        .height(1.dp)
                        .background(Color.White.copy(alpha = 0.15f))
                )
                Spacer(Modifier.height(10.dp))
            }

            item {
                Button(
                    onClick = {
                        view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                        showUnpairDialog = true
                    },
                    modifier = Modifier
                        .fillMaxWidth(0.85f)
                        .height(36.dp),
                    shape = RoundedCornerShape(8.dp),
                    colors = ButtonDefaults.buttonColors(backgroundColor = Color(0x33FF3B30))
                ) {
                    Text(
                        text = "Unpair Watch",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = Color(0xFFFF3B30)
                    )
                }
                Spacer(Modifier.height(16.dp))
            }
        }

        // Unpair Confirmation Dialog
        if (showUnpairDialog) {
            Dialog(
                showDialog = true,
                onDismissRequest = { showUnpairDialog = false }
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
                        text = "Unpair Watch?",
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                    Spacer(Modifier.height(6.dp))
                    Text(
                        text = "This will disconnect this watch from your account.",
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
                            onClick = { showUnpairDialog = false },
                            colors = ButtonDefaults.buttonColors(backgroundColor = Color(0xFF333333)),
                            modifier = Modifier.weight(1f).height(32.dp).padding(end = 4.dp),
                            shape = RoundedCornerShape(8.dp)
                        ) {
                            Text("Cancel", fontSize = 11.sp, color = Color.White)
                        }
                        Button(
                            onClick = {
                                view.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
                                showUnpairDialog = false
                                sessionManager.logout()
                            },
                            colors = ButtonDefaults.buttonColors(backgroundColor = Color(0xFFFF3B30)),
                            modifier = Modifier.weight(1f).height(32.dp).padding(start = 4.dp),
                            shape = RoundedCornerShape(8.dp)
                        ) {
                            Text("Unpair", fontSize = 11.sp, color = Color.White, fontWeight = FontWeight.Bold)
                        }
                    }
                }
            }
        }
    }
}
