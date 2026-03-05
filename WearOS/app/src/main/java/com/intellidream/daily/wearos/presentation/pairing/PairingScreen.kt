package com.intellidream.daily.wearos.presentation.pairing

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import com.intellidream.daily.wearos.data.WatchSessionManager

@Composable
fun PairingScreen(sessionManager: WatchSessionManager) {
    val isPairing by sessionManager.isPairing.collectAsState()
    val pairingCode by sessionManager.pairingCode.collectAsState()
    val errorMessage by sessionManager.errorMessage.collectAsState()

    LaunchedEffect(Unit) {
        sessionManager.checkExistingSession()
    }

    Column(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        if (errorMessage.isNotEmpty()) {
            Text("Error", color = MaterialTheme.colors.error, fontWeight = FontWeight.Bold)
            Text(errorMessage, fontSize = 10.sp, textAlign = TextAlign.Center)
            Spacer(modifier = Modifier.size(8.dp))
            Button(onClick = { sessionManager.generatePairingCode() }) {
                Text("Retry")
            }
        } else if (isPairing) {
            Text("Pairing Code", color = MaterialTheme.colors.secondary, fontWeight = FontWeight.Bold)
            Spacer(modifier = Modifier.size(8.dp))
            Text(
                text = pairingCode,
                fontSize = 34.sp,
                fontWeight = FontWeight.Bold,
                fontFamily = FontFamily.Monospace,
                color = MaterialTheme.colors.onBackground
            )
            Spacer(modifier = Modifier.size(8.dp))
            Text(
                text = "Open Daily on phone:\nSettings -> Pair Watch",
                fontSize = 11.sp,
                textAlign = TextAlign.Center
            )
        } else {
            CircularProgressIndicator()
        }
    }
}
