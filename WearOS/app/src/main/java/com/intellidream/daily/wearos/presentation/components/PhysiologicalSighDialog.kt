package com.intellidream.daily.wearos.presentation.components

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.ButtonDefaults
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.dialog.Dialog
import com.intellidream.daily.wearos.presentation.theme.DailyWearColors
import kotlinx.coroutines.delay

@Composable
fun PhysiologicalSighDialog(
    show: Boolean,
    onDismiss: () -> Unit
) {
    if (!show) return

    val context = LocalContext.current
    var currentCycle by remember { mutableIntStateOf(1) }
    var phaseName by remember { mutableStateOf("Inhale") }
    var phaseColor by remember { mutableStateOf(DailyWearColors.WaterCyan) }
    var phaseSecondsRemaining by remember { mutableDoubleStateOf(2.0) }
    var discScale by remember { mutableDoubleStateOf(0.6) }
    var isDone by remember { mutableStateOf(false) }

    val vibrator = remember {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vm = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            vm.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
    }

    fun playHaptic(durationMs: Long, amplitude: Int = 180) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createOneShot(durationMs, amplitude))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(durationMs)
        }
    }

    LaunchedEffect(show) {
        for (cycle in 1..5) {
            currentCycle = cycle

            // 1. Inhale 1 (Deep): 2.0s
            phaseName = "Inhale"
            phaseColor = DailyWearColors.WaterCyan
            discScale = 0.85
            playHaptic(80, 150)
            var rem = 2.0
            while (rem > 0) {
                phaseSecondsRemaining = rem
                delay(100)
                rem -= 0.1
            }

            // 2. Inhale 2 (Top-up): 1.5s
            phaseName = "Top Up"
            phaseColor = Color(0xFF38BDF8)
            discScale = 1.0
            playHaptic(50, 200)
            rem = 1.5
            while (rem > 0) {
                phaseSecondsRemaining = rem
                delay(100)
                rem -= 0.1
            }

            // 3. Exhale (Long mouth): 6.0s
            phaseName = "Exhale"
            phaseColor = Color(0xFF10B981)
            discScale = 0.4
            playHaptic(120, 100)
            rem = 6.0
            while (rem > 0) {
                phaseSecondsRemaining = rem
                delay(100)
                rem -= 0.1
            }
        }

        phaseName = "Done"
        phaseColor = Color(0xFF10B981)
        discScale = 0.6
        isDone = true
        playHaptic(200, 255)
    }

    Dialog(showDialog = show, onDismissRequest = onDismiss) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black),
            contentAlignment = Alignment.Center
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.SpaceBetween,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(8.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(0.9f),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = "Physiological Sigh",
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White.copy(alpha = 0.6f)
                    )
                    Text(
                        text = "$currentCycle/5",
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        color = DailyWearColors.WaterCyan
                    )
                }

                // Breathing Animated Disc
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier.size(90.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .size((90 * discScale).dp)
                            .clip(CircleShape)
                            .background(phaseColor.copy(alpha = 0.25f))
                    )

                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(
                            text = phaseName,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Bold,
                            color = phaseColor
                        )
                        if (!isDone) {
                            Text(
                                text = String.format("%.1fs", phaseSecondsRemaining),
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Medium,
                                color = Color.White.copy(alpha = 0.7f)
                            )
                        }
                    }
                }

                if (isDone) {
                    Button(
                        onClick = onDismiss,
                        colors = ButtonDefaults.buttonColors(backgroundColor = Color(0xFF10B981)),
                        modifier = Modifier
                            .fillMaxWidth(0.8f)
                            .height(30.dp)
                    ) {
                        Text("Close", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Color.Black)
                    }
                } else {
                    Button(
                        onClick = onDismiss,
                        colors = ButtonDefaults.secondaryButtonColors(),
                        modifier = Modifier
                            .fillMaxWidth(0.7f)
                            .height(28.dp)
                    ) {
                        Text("Cancel", fontSize = 10.sp)
                    }
                }
            }
        }
    }
}
