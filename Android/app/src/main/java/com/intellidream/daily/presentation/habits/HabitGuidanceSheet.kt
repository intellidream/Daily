package com.intellidream.daily.presentation.habits

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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Air
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.DirectionsWalk
import androidx.compose.material.icons.rounded.EmojiEvents
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Timer
import androidx.compose.material.icons.rounded.VerifiedUser
import androidx.compose.material.icons.rounded.WaterDrop
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetState
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.HabitType
import com.intellidream.daily.model.HabitsGuidance
import kotlinx.coroutines.delay
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HabitGuidanceSheet(
    initialHabit: HabitType,
    onDismiss: () -> Unit,
    sheetState: SheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
) {
    var activeTab by remember { mutableStateOf(initialHabit) }

    // Live 5-minute Craving Timer State
    var timerSecondsRemaining by remember { mutableIntStateOf(300) } // 5 minutes
    var isTimerRunning by remember { mutableStateOf(false) }

    LaunchedEffect(isTimerRunning) {
        while (isTimerRunning && timerSecondsRemaining > 0) {
            delay(1000L)
            timerSecondsRemaining--
        }
        if (timerSecondsRemaining <= 0) {
            isTimerRunning = false
        }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Color(0xFF070F1B),
        dragHandle = null
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 20.dp, vertical = 16.dp)
        ) {
            // Header Bar
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Clinical Guidance & Tools",
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White
                )

                IconButton(
                    onClick = onDismiss,
                    modifier = Modifier
                        .size(32.dp)
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.08f))
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Close,
                        contentDescription = "Close",
                        tint = Color.White,
                        modifier = Modifier.size(16.dp)
                    )
                }
            }

            Spacer(modifier = Modifier.height(14.dp))

            // Segmented Habit Tab Switcher
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.06f))
                    .padding(4.dp)
            ) {
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .clip(CircleShape)
                        .background(
                            if (activeTab == HabitType.WATER) ThemeColors.accentCyan
                            else Color.Transparent
                        )
                        .clickable { activeTab = HabitType.WATER }
                        .padding(vertical = 8.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = "💧 Bubbles Hydration",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold,
                        color = if (activeTab == HabitType.WATER) Color.Black else ThemeColors.textSecondary
                    )
                }

                Box(
                    modifier = Modifier
                        .weight(1f)
                        .clip(CircleShape)
                        .background(
                            if (activeTab == HabitType.SMOKES) Color(0xFFFF3B30)
                            else Color.Transparent
                        )
                        .clickable { activeTab = HabitType.SMOKES }
                        .padding(vertical = 8.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = "🔥 Smokes & Cravings",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold,
                        color = if (activeTab == HabitType.SMOKES) Color.White else ThemeColors.textSecondary
                    )
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Scrollable Content Body
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                if (activeTab == HabitType.WATER) {
                    // Diurnal Circadian Hydration Section
                    Text(
                        text = "CIRCADIAN DIURNAL SCHEDULE",
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        color = ThemeColors.textSecondary,
                        letterSpacing = 1.sp
                    )

                    HabitsGuidance.circadianSlots.forEach { slot ->
                        GlassCard(
                            modifier = Modifier.fillMaxWidth(),
                            cornerRadius = 14.dp,
                            padding = 12.dp
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.Top
                            ) {
                                Column(modifier = Modifier.weight(1f)) {
                                    Row(
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                                    ) {
                                        Text(
                                            text = slot.timeRange,
                                            fontSize = 11.sp,
                                            fontWeight = FontWeight.Bold,
                                            color = ThemeColors.accentCyan
                                        )
                                        Text(
                                            text = "•",
                                            fontSize = 11.sp,
                                            color = ThemeColors.textSecondary
                                        )
                                        Text(
                                            text = slot.title,
                                            fontSize = 13.sp,
                                            fontWeight = FontWeight.Bold,
                                            color = Color.White
                                        )
                                    }

                                    Spacer(modifier = Modifier.height(4.dp))

                                    Text(
                                        text = slot.rationale,
                                        fontSize = 12.sp,
                                        color = ThemeColors.textSecondary,
                                        lineHeight = 16.sp
                                    )
                                }

                                Box(
                                    modifier = Modifier
                                        .clip(CircleShape)
                                        .background(ThemeColors.accentCyan.copy(alpha = 0.15f))
                                        .padding(horizontal = 8.dp, vertical = 4.dp)
                                ) {
                                    Text(
                                        text = "${slot.recommendedVolumeMl}ml",
                                        fontSize = 11.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = ThemeColors.accentCyan
                                    )
                                }
                            }
                        }
                    }

                    // Drink Hydration Index (DHI) Section
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = "DRINK HYDRATION INDEX (DHI)",
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        color = ThemeColors.textSecondary,
                        letterSpacing = 1.sp
                    )

                    HabitsGuidance.drinkHydrationIndex.forEach { dhi ->
                        val color = Color(android.graphics.Color.parseColor(dhi.hexColor))
                        GlassCard(
                            modifier = Modifier.fillMaxWidth(),
                            cornerRadius = 14.dp,
                            padding = 12.dp
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        text = dhi.name,
                                        fontSize = 14.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = Color.White
                                    )
                                    Text(
                                        text = dhi.description,
                                        fontSize = 12.sp,
                                        color = ThemeColors.textSecondary
                                    )
                                    Spacer(modifier = Modifier.height(2.dp))
                                    Text(
                                        text = "💡 ${dhi.proTip}",
                                        fontSize = 11.sp,
                                        color = color,
                                        lineHeight = 15.sp
                                    )
                                }

                                Box(
                                    modifier = Modifier
                                        .clip(CircleShape)
                                        .background(color.copy(alpha = 0.15f))
                                        .border(1.dp, color.copy(alpha = 0.4f), CircleShape)
                                        .padding(horizontal = 8.dp, vertical = 4.dp)
                                ) {
                                    Text(
                                        text = "${dhi.indexScore}×",
                                        fontSize = 12.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = color
                                    )
                                }
                            }
                        }
                    }
                } else {
                    // Smokes: 4D Craving Protocol with live interactive countdown
                    Text(
                        text = "4D EMERGENCY CRAVING TIMER",
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        color = ThemeColors.textSecondary,
                        letterSpacing = 1.sp
                    )

                    GlassCard(
                        modifier = Modifier.fillMaxWidth(),
                        cornerRadius = 18.dp,
                        padding = 16.dp
                    ) {
                        Column(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            val mins = timerSecondsRemaining / 60
                            val secs = timerSecondsRemaining % 60
                            val timeFormatted = String.format(Locale.US, "%02d:%02d", mins, secs)

                            Box(
                                modifier = Modifier
                                    .size(100.dp)
                                    .clip(CircleShape)
                                    .background(Color(0xFFFF3B30).copy(alpha = 0.12f))
                                    .border(
                                        2.dp,
                                        Brush.sweepGradient(
                                            listOf(
                                                Color(0xFFFF3B30),
                                                Color(0xFFFF9500),
                                                Color(0xFFFF3B30)
                                            )
                                        ),
                                        CircleShape
                                    ),
                                contentAlignment = Alignment.Center
                            ) {
                                Text(
                                    text = timeFormatted,
                                    fontSize = 24.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = Color.White
                                )
                            }

                            Spacer(modifier = Modifier.height(12.dp))

                            // Action buttons: Start/Pause and Reset
                            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                Box(
                                    modifier = Modifier
                                        .clip(CircleShape)
                                        .background(Color(0xFFFF3B30))
                                        .clickable { isTimerRunning = !isTimerRunning }
                                        .padding(horizontal = 20.dp, vertical = 8.dp)
                                ) {
                                    Row(
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                                    ) {
                                        Icon(
                                            imageVector = if (isTimerRunning) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
                                            contentDescription = null,
                                            tint = Color.White,
                                            modifier = Modifier.size(16.dp)
                                        )
                                        Text(
                                            text = if (isTimerRunning) "PAUSE" else "START TIMER",
                                            fontSize = 12.sp,
                                            fontWeight = FontWeight.Bold,
                                            color = Color.White
                                        )
                                    }
                                }

                                Box(
                                    modifier = Modifier
                                        .clip(CircleShape)
                                        .background(Color.White.copy(alpha = 0.1f))
                                        .clickable {
                                            isTimerRunning = false
                                            timerSecondsRemaining = 300
                                        }
                                        .padding(horizontal = 14.dp, vertical = 8.dp)
                                ) {
                                    Icon(
                                        imageVector = Icons.Rounded.Refresh,
                                        contentDescription = "Reset",
                                        tint = Color.White,
                                        modifier = Modifier.size(16.dp)
                                    )
                                }
                            }
                        }
                    }

                    // 4D Protocol Steps
                    HabitsGuidance.fourDsCravingProtocol.forEach { step ->
                        GlassCard(
                            modifier = Modifier.fillMaxWidth(),
                            cornerRadius = 14.dp,
                            padding = 12.dp
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.Top
                            ) {
                                Box(
                                    modifier = Modifier
                                        .size(32.dp)
                                        .clip(CircleShape)
                                        .background(Color(0xFFFF3B30).copy(alpha = 0.2f)),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Text(
                                        text = step.letter,
                                        fontSize = 14.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = Color(0xFFFF3B30)
                                    )
                                }

                                Spacer(modifier = Modifier.width(12.dp))

                                Column(modifier = Modifier.weight(1f)) {
                                    Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        horizontalArrangement = Arrangement.SpaceBetween
                                    ) {
                                        Text(
                                            text = step.action,
                                            fontSize = 14.sp,
                                            fontWeight = FontWeight.Bold,
                                            color = Color.White
                                        )
                                        Text(
                                            text = step.durationText,
                                            fontSize = 11.sp,
                                            fontWeight = FontWeight.SemiBold,
                                            color = Color(0xFFFF9500)
                                        )
                                    }

                                    Spacer(modifier = Modifier.height(2.dp))

                                    Text(
                                        text = step.explanation,
                                        fontSize = 12.sp,
                                        color = ThemeColors.textSecondary,
                                        lineHeight = 16.sp
                                    )
                                }
                            }
                        }
                    }

                    // 6 Clinical Recovery Milestones
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = "PHYSIOLOGICAL RECOVERY ROADMAP",
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        color = ThemeColors.textSecondary,
                        letterSpacing = 1.sp
                    )

                    HabitsGuidance.recoveryMilestones.forEach { milestone ->
                        val color = Color(android.graphics.Color.parseColor(milestone.hexColor))
                        GlassCard(
                            modifier = Modifier.fillMaxWidth(),
                            cornerRadius = 14.dp,
                            padding = 12.dp
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Box(
                                    modifier = Modifier
                                        .size(36.dp)
                                        .clip(CircleShape)
                                        .background(color.copy(alpha = 0.18f))
                                        .border(1.dp, color.copy(alpha = 0.4f), CircleShape),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Icon(
                                        imageVector = when (milestone.timeframe) {
                                            "20 Minutes" -> Icons.Rounded.Favorite
                                            "12 Hours", "72 Hours" -> Icons.Rounded.Air
                                            "48 Hours" -> Icons.Rounded.AutoAwesome
                                            "2–4 Weeks" -> Icons.Rounded.VerifiedUser
                                            else -> Icons.Rounded.EmojiEvents
                                        },
                                        contentDescription = null,
                                        tint = color,
                                        modifier = Modifier.size(18.dp)
                                    )
                                }

                                Spacer(modifier = Modifier.width(12.dp))

                                Column(modifier = Modifier.weight(1f)) {
                                    Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        horizontalArrangement = Arrangement.SpaceBetween
                                    ) {
                                        Text(
                                            text = milestone.benefit,
                                            fontSize = 13.sp,
                                            fontWeight = FontWeight.Bold,
                                            color = Color.White
                                        )
                                        Text(
                                            text = milestone.timeframe,
                                            fontSize = 11.sp,
                                            fontWeight = FontWeight.Bold,
                                            color = color
                                        )
                                    }

                                    Spacer(modifier = Modifier.height(2.dp))

                                    Text(
                                        text = milestone.physiologicalChange,
                                        fontSize = 11.sp,
                                        color = ThemeColors.textSecondary,
                                        lineHeight = 15.sp
                                    )
                                }
                            }
                        }
                    }
                }

                Spacer(modifier = Modifier.height(30.dp))
            }
        }
    }
}
