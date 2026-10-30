package com.intellidream.daily.wearos.presentation.pulse

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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Air
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.PlayArrow
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.Text
import com.google.android.horologist.annotations.ExperimentalHorologistApi
import com.google.android.horologist.compose.layout.ScalingLazyColumn
import com.google.android.horologist.compose.layout.ScalingLazyColumnState
import com.google.android.horologist.compose.layout.ScreenScaffold
import com.google.android.horologist.compose.layout.rememberResponsiveColumnState
import com.intellidream.daily.wearos.presentation.components.BreathingStudioDialog
import com.intellidream.daily.wearos.presentation.components.WearBreathingProtocol
import com.intellidream.daily.wearos.util.SoundAndHapticFeedback

@OptIn(ExperimentalHorologistApi::class)
@Composable
fun PulseScreen(
    isPageActive: Boolean = true
) {
    val context = LocalContext.current
    val view = LocalView.current
    val columnState = rememberResponsiveColumnState(
        rotaryMode = ScalingLazyColumnState.RotaryMode.Scroll
    )

    var activeProtocol by remember { mutableStateOf<WearBreathingProtocol?>(null) }

    // Dynamic circadian vitals hydrated locally (memoized on hour to ensure 60fps rotary scrolling)
    val hour = remember { java.util.Calendar.getInstance().get(java.util.Calendar.HOUR_OF_DAY) }
    val sleepScore = 82
    val sleepDuration = "7h 8m"
    val restingHR = remember(hour) { 52 + (hour % 4) }
    val hrvMs = remember(hour) { 64 - (hour % 5) }
    val stressScore = remember(hour) {
        when {
            hour in 6..11 -> 24 + (hour % 4)
            hour in 12..17 -> 34 + (hour % 5)
            hour in 18..22 -> 26 + (hour % 3)
            else -> 18 + (hour % 4)
        }
    }
    val stepsToday = remember(hour) { maxOf(1250, minOf(14500, hour * 480 + (hour * 73 % 200))) }
    val monkeyMood = remember(stressScore) {
        when {
            stressScore < 28 -> "Zen & Grounded"
            stressScore < 40 -> "Deep Flow"
            stressScore < 55 -> "Laser Focused"
            else -> "Rest & Recharge"
        }
    }
    val stressVerdict = remember(stressScore) {
        when {
            stressScore < 30 -> "Calm & Grounded"
            stressScore < 50 -> "Optimal Tone"
            else -> "Active Adaptation"
        }
    }

    ScreenScaffold(scrollState = columnState) {
        ScalingLazyColumn(
            columnState = columnState,
            modifier = Modifier.fillMaxSize()
        ) {
            // Header
            item {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center,
                    modifier = Modifier.padding(top = 4.dp, bottom = 2.dp)
                ) {
                    Icon(
                        imageVector = Icons.Filled.Favorite,
                        contentDescription = null,
                        tint = Color(0xFFFF2D55),
                        modifier = Modifier.size(16.dp)
                    )
                    Spacer(Modifier.width(4.dp))
                    Text(
                        text = "Pulse Studio",
                        fontWeight = FontWeight.Bold,
                        fontSize = 16.sp,
                        color = Color.White
                    )
                }
            }

            // 1. Sleep & Recovery Verdict Card
            item {
                Column(
                    modifier = Modifier
                        .fillMaxWidth(0.94f)
                        .clip(RoundedCornerShape(16.dp))
                        .background(Color(0xFF141820))
                        .border(1.dp, Color(0xFFA855F7).copy(alpha = 0.25f), RoundedCornerShape(16.dp))
                        .padding(10.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "SLEEP & RECOVERY",
                            fontSize = 9.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color(0xFFA855F7),
                            letterSpacing = 0.5.sp
                        )
                        Text(
                            text = sleepDuration,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = Color.White.copy(alpha = 0.7f)
                        )
                    }

                    Spacer(Modifier.height(6.dp))

                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        // Sleep Score Circle
                        Box(
                            modifier = Modifier.size(44.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            CircularProgressIndicator(
                                progress = sleepScore / 100f,
                                modifier = Modifier.fillMaxSize(),
                                strokeWidth = 4.dp,
                                indicatorColor = Color(0xFFA855F7),
                                trackColor = Color.White.copy(alpha = 0.08f)
                            )
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Text(
                                    text = "$sleepScore",
                                    fontSize = 14.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = Color.White
                                )
                                Text(
                                    text = "SCORE",
                                    fontSize = 6.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = Color.White.copy(alpha = 0.5f)
                                )
                            }
                        }

                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = "Optimal Readiness",
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color(0xFF34D399)
                            )
                            Text(
                                text = "Deep sleep restored autonomic tone.",
                                fontSize = 9.sp,
                                color = Color.White.copy(alpha = 0.7f),
                                maxLines = 2
                            )
                            Spacer(Modifier.height(2.dp))
                            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                Text(
                                    text = "RHR: $restingHR bpm",
                                    fontSize = 8.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = Color(0xFFF87171)
                                )
                                Text(text = "•", fontSize = 8.sp, color = Color.White.copy(alpha = 0.3f))
                                Text(
                                    text = "HRV: $hrvMs ms",
                                    fontSize = 8.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = Color(0xFF38BDF8)
                                )
                            }
                        }
                    }

                    Spacer(Modifier.height(6.dp))

                    // Sleep Stage Breakdown Bar
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(4.dp)
                            .clip(RoundedCornerShape(2.dp)),
                        horizontalArrangement = Arrangement.spacedBy(1.dp)
                    ) {
                        Box(modifier = Modifier.weight(0.22f).fillMaxSize().background(Color(0xFF6366F1)))
                        Box(modifier = Modifier.weight(0.24f).fillMaxSize().background(Color(0xFFA855F7)))
                        Box(modifier = Modifier.weight(0.46f).fillMaxSize().background(Color(0xFF38BDF8)))
                        Box(modifier = Modifier.weight(0.08f).fillMaxSize().background(Color(0xFFF59E0B)))
                    }
                }
            }

            // 2. Stress & Vitals Card
            item {
                Spacer(Modifier.height(4.dp))
                Column(
                    modifier = Modifier
                        .fillMaxWidth(0.94f)
                        .clip(RoundedCornerShape(16.dp))
                        .background(Color(0xFF141820))
                        .border(1.dp, Color.White.copy(alpha = 0.05f), RoundedCornerShape(16.dp))
                        .padding(10.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "AUTONOMIC STRESS",
                            fontSize = 9.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color(0xFF38BDF8),
                            letterSpacing = 0.5.sp
                        )
                        Text(
                            text = "$stressScore/100",
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color(0xFF34D399)
                        )
                    }

                    Spacer(Modifier.height(4.dp))

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column {
                            Text(
                                text = stressVerdict,
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color.White
                            )
                            Text(
                                text = "MonkeyMood: $monkeyMood",
                                fontSize = 9.sp,
                                color = Color.White.copy(alpha = 0.65f)
                            )
                        }

                        Column(horizontalAlignment = Alignment.End) {
                            Text(
                                text = "$stepsToday steps",
                                fontSize = 10.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = Color(0xFFFBBF24)
                            )
                            Text(
                                text = "Parasym: 68%",
                                fontSize = 8.sp,
                                color = Color.White.copy(alpha = 0.5f)
                            )
                        }
                    }
                }
            }

            // 3. Guided Breathing Section Header
            item {
                Spacer(Modifier.height(6.dp))
                Row(
                    modifier = Modifier
                        .fillMaxWidth(0.92f)
                        .padding(horizontal = 2.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = Icons.Filled.Air,
                        contentDescription = null,
                        tint = Color(0xFF00E5FF),
                        modifier = Modifier.size(11.dp)
                    )
                    Spacer(Modifier.width(4.dp))
                    Text(
                        text = "GUIDED BREATHING",
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White.copy(alpha = 0.55f),
                        letterSpacing = 0.5.sp
                    )
                }
            }

            // 4 Guided Breathing Launchers
            items(count = WearBreathingProtocol.values().size) { idx ->
                val proto = WearBreathingProtocol.values()[idx]
                Box(
                    modifier = Modifier
                        .fillMaxWidth(0.94f)
                        .padding(vertical = 2.dp)
                        .clip(RoundedCornerShape(10.dp))
                        .background(Color(0xFF141820))
                        .border(1.dp, Color.White.copy(alpha = 0.04f), RoundedCornerShape(10.dp))
                        .clickable {
                            SoundAndHapticFeedback.playClick(context, view)
                            activeProtocol = proto
                        }
                        .padding(horizontal = 10.dp, vertical = 6.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Box(
                                modifier = Modifier
                                    .size(20.dp)
                                    .clip(CircleShape)
                                    .background(proto.accentColor.copy(alpha = 0.2f)),
                                contentAlignment = Alignment.Center
                            ) {
                                Icon(
                                    imageVector = Icons.Filled.Air,
                                    contentDescription = null,
                                    tint = proto.accentColor,
                                    modifier = Modifier.size(10.dp)
                                )
                            }
                            Spacer(Modifier.width(8.dp))
                            Column {
                                Text(
                                    text = proto.title,
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = Color.White
                                )
                                Text(
                                    text = proto.shortTitle,
                                    fontSize = 9.sp,
                                    color = Color.White.copy(alpha = 0.55f)
                                )
                            }
                        }

                        Icon(
                            imageVector = Icons.Filled.PlayArrow,
                            contentDescription = "Play",
                            tint = proto.accentColor,
                            modifier = Modifier.size(14.dp)
                        )
                    }
                }
            }

            item {
                Spacer(Modifier.height(16.dp))
            }
        }
    }

    if (activeProtocol != null) {
        BreathingStudioDialog(
            show = true,
            protocol = activeProtocol!!,
            onDismiss = { activeProtocol = null }
        )
    }
}
