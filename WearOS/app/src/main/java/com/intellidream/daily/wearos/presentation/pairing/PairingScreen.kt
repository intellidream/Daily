package com.intellidream.daily.wearos.presentation.pairing

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.ButtonDefaults
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import android.view.HapticFeedbackConstants
import com.intellidream.daily.wearos.data.WatchSessionManager

@Composable
fun PairingScreen(sessionManager: WatchSessionManager) {
    val isPairing by sessionManager.isPairing.collectAsState()
    val pairingCode by sessionManager.pairingCode.collectAsState()
    val errorMessage by sessionManager.errorMessage.collectAsState()
    val view = LocalView.current
    val scrollState = rememberScrollState()

    LaunchedEffect(Unit) {
        sessionManager.checkExistingSession()
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(scrollState)
            .padding(horizontal = 12.dp, vertical = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Text(
            text = "DayOne Orbit",
            fontSize = 15.sp,
            fontWeight = FontWeight.Bold,
            color = Color.Cyan
        )
        Spacer(modifier = Modifier.height(2.dp))
        Text(
            text = "Pairing PIN",
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold,
            color = Color.Gray
        )

        Spacer(modifier = Modifier.height(6.dp))

        if (errorMessage.isNotEmpty()) {
            Text(
                text = errorMessage,
                fontSize = 10.sp,
                color = MaterialTheme.colors.error,
                textAlign = TextAlign.Center
            )
            Spacer(modifier = Modifier.height(6.dp))
            Button(
                onClick = {
                    view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                    sessionManager.generatePairingCode()
                },
                modifier = Modifier.fillMaxWidth(0.7f).height(32.dp),
                colors = ButtonDefaults.buttonColors(backgroundColor = Color(0x3300FFFF))
            ) {
                Text("Retry", fontSize = 11.sp, color = Color.Cyan)
            }
        } else if (isPairing && pairingCode.isNotEmpty()) {
            Text(
                text = pairingCode,
                fontSize = 32.sp,
                fontWeight = FontWeight.Bold,
                fontFamily = FontFamily.Monospace,
                color = Color(0xFF4CAF50),
                letterSpacing = 3.sp
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = "Enter this PIN in DayOne to link.",
                fontSize = 10.sp,
                color = Color.LightGray,
                textAlign = TextAlign.Center
            )
            Spacer(modifier = Modifier.height(6.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(modifier = Modifier.size(12.dp), strokeWidth = 2.dp)
                Spacer(modifier = Modifier.size(4.dp))
                Text("Waiting for authorization...", fontSize = 9.sp, color = Color.Gray)
            }
            Spacer(modifier = Modifier.height(6.dp))
            Button(
                onClick = {
                    view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                    sessionManager.generatePairingCode()
                },
                modifier = Modifier.fillMaxWidth(0.6f).height(30.dp),
                shape = RoundedCornerShape(8.dp),
                colors = ButtonDefaults.buttonColors(backgroundColor = Color.White.copy(alpha = 0.1f))
            ) {
                Text("New PIN", fontSize = 11.sp, color = Color.Cyan)
            }
        } else {
            CircularProgressIndicator(modifier = Modifier.size(28.dp))
            Spacer(modifier = Modifier.height(4.dp))
            Text("Connecting to Orbit...", fontSize = 11.sp, color = Color.Gray)
        }
    }
}
