package com.intellidream.daily.wearos.presentation.components

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.ui.draw.scale
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

enum class WearBreathingProtocol(val title: String, val shortTitle: String, val totalCycles: Int, val accentColor: Color) {
    PHYSIOLOGICAL_SIGH("Physiological Sigh", "Sigh (48s)", 5, Color(0xFF00E5FF)),
    BOX_BREATHING("Box 4-4-4-4", "Box (64s)", 4, Color(0xFF38BDF8)),
    RESONANCE("Resonance 5.5s", "Resonance", 6, Color(0xFF10B981)),
    RELAX_478("4-7-8 Relax", "4-7-8 (76s)", 4, Color(0xFFA855F7))
}

private enum class StepPhase(val label: String, val color: Color) {
    INHALE_1("Inhale", Color(0xFF00E5FF)),
    INHALE_2("Top Up", Color(0xFF38BDF8)),
    HOLD("Hold", Color(0xFFFFD600)),
    EXHALE("Exhale", Color(0xFF10B981)),
    FINISHED("Done", Color(0xFF34D399))
}

@Composable
fun BreathingStudioDialog(
    show: Boolean,
    protocol: WearBreathingProtocol,
    onDismiss: () -> Unit
) {
    if (!show) return

    val context = LocalContext.current
    var currentCycle by remember { mutableIntStateOf(1) }
    var phase by remember { mutableStateOf(StepPhase.INHALE_1) }
    var phaseDurationSec by remember { mutableDoubleStateOf(2.0) }
    val targetScale by animateFloatAsState(
        targetValue = if (phase == StepPhase.INHALE_1 || phase == StepPhase.INHALE_2 || phase == StepPhase.HOLD) 1.0f else 0.45f,
        animationSpec = tween((phaseDurationSec * 1000).toInt()),
        label = "breathingScale"
    )
    var isRunning by remember { mutableStateOf(true) }

    fun triggerVibration(type: String) {
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                vm?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            } ?: return

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                when (type) {
                    "inhale" -> vibrator.vibrate(VibrationEffect.createOneShot(80, 100))
                    "hold" -> vibrator.vibrate(VibrationEffect.createOneShot(40, 150))
                    "exhale" -> vibrator.vibrate(VibrationEffect.createOneShot(120, 70))
                    "done" -> vibrator.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 100, 80, 150), -1))
                }
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(80)
            }
        } catch (ignored: Exception) {}
    }

    LaunchedEffect(show, protocol) {
        currentCycle = 1
        isRunning = true

        while (currentCycle <= protocol.totalCycles && isRunning) {
            when (protocol) {
                WearBreathingProtocol.PHYSIOLOGICAL_SIGH -> {
                    // 1. Inhale 1 (2.0s)
                    phase = StepPhase.INHALE_1
                    phaseDurationSec = 2.0
                    triggerVibration("inhale")
                    delay(2000)

                    // 2. Inhale 2 (1.5s)
                    phase = StepPhase.INHALE_2
                    phaseDurationSec = 1.5
                    triggerVibration("inhale")
                    delay(1500)

                    // 3. Exhale (6.0s)
                    phase = StepPhase.EXHALE
                    phaseDurationSec = 6.0
                    triggerVibration("exhale")
                    delay(6000)
                }

                WearBreathingProtocol.BOX_BREATHING -> {
                    // 1. Inhale (4.0s)
                    phase = StepPhase.INHALE_1
                    phaseDurationSec = 4.0
                    triggerVibration("inhale")
                    delay(4000)

                    // 2. Hold (4.0s)
                    phase = StepPhase.HOLD
                    phaseDurationSec = 4.0
                    triggerVibration("hold")
                    delay(4000)

                    // 3. Exhale (4.0s)
                    phase = StepPhase.EXHALE
                    phaseDurationSec = 4.0
                    triggerVibration("exhale")
                    delay(4000)

                    // 4. Hold (4.0s)
                    phase = StepPhase.HOLD
                    phaseDurationSec = 4.0
                    triggerVibration("hold")
                    delay(4000)
                }

                WearBreathingProtocol.RESONANCE -> {
                    // 1. Inhale (5.5s)
                    phase = StepPhase.INHALE_1
                    phaseDurationSec = 5.5
                    triggerVibration("inhale")
                    delay(5500)

                    // 2. Exhale (5.5s)
                    phase = StepPhase.EXHALE
                    phaseDurationSec = 5.5
                    triggerVibration("exhale")
                    delay(5500)
                }

                WearBreathingProtocol.RELAX_478 -> {
                    // 1. Inhale (4.0s)
                    phase = StepPhase.INHALE_1
                    phaseDurationSec = 4.0
                    triggerVibration("inhale")
                    delay(4000)

                    // 2. Hold (7.0s)
                    phase = StepPhase.HOLD
                    phaseDurationSec = 7.0
                    triggerVibration("hold")
                    delay(7000)

                    // 3. Exhale (8.0s)
                    phase = StepPhase.EXHALE
                    phaseDurationSec = 8.0
                    triggerVibration("exhale")
                    delay(8000)
                }
            }
            currentCycle += 1
        }

        if (isRunning) {
            phase = StepPhase.FINISHED
            triggerVibration("done")
        }
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
                    .padding(vertical = 10.dp, horizontal = 8.dp)
            ) {
                // Header
                Row(
                    modifier = Modifier.fillMaxWidth(0.9f),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = protocol.title,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        color = protocol.accentColor
                    )
                    Text(
                        text = "$currentCycle/${protocol.totalCycles}",
                        fontSize = 11.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = Color.White.copy(alpha = 0.8f)
                    )
                }

                // Center Pulsing Circle
                Box(
                    modifier = Modifier.size(86.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .clip(CircleShape)
                            .border(5.dp, phase.color.copy(alpha = 0.25f), CircleShape)
                    )

                    val animScale = when (phase) {
                        StepPhase.INHALE_1, StepPhase.INHALE_2 -> 0.95f
                        StepPhase.HOLD -> 0.95f
                        StepPhase.EXHALE -> 0.45f
                        StepPhase.FINISHED -> 0.8f
                    }
                    val scale by animateFloatAsState(
                        targetValue = animScale,
                        animationSpec = tween((phaseDurationSec * 1000).toInt())
                    )

                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .scale(scale)
                            .clip(CircleShape)
                            .background(phase.color.copy(alpha = 0.2f))
                    )

                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(
                            text = phase.label,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Bold,
                            color = phase.color
                        )
                    }
                }

                // Bottom Action
                if (phase == StepPhase.FINISHED) {
                    Button(
                        onClick = onDismiss,
                        colors = ButtonDefaults.buttonColors(backgroundColor = Color(0xFF34D399)),
                        modifier = Modifier.fillMaxWidth(0.75f).height(30.dp)
                    ) {
                        Text("Complete", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Color.Black)
                    }
                } else {
                    Button(
                        onClick = {
                            isRunning = false
                            onDismiss()
                        },
                        colors = ButtonDefaults.secondaryButtonColors(),
                        modifier = Modifier.fillMaxWidth(0.6f).height(28.dp)
                    ) {
                        Text("Cancel", fontSize = 10.sp)
                    }
                }
            }
        }
    }
}
