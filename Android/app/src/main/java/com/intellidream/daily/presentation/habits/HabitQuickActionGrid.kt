package com.intellidream.daily.presentation.habits

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Bolt
import androidx.compose.material.icons.rounded.Coffee
import androidx.compose.material.icons.rounded.Eco
import androidx.compose.material.icons.rounded.EmojiFoodBeverage
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.Psychology
import androidx.compose.material.icons.rounded.Science
import androidx.compose.material.icons.rounded.Timer
import androidx.compose.material.icons.rounded.WaterDrop
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.HabitType
import com.intellidream.daily.model.SmokePreset
import com.intellidream.daily.model.WaterPreset

@Composable
fun HabitQuickActionGrid(
    habitType: HabitType,
    onLogWater: (preset: WaterPreset, multiplier: Int) -> Unit,
    onLogCustomWater: (amountMl: Double, drinkName: String) -> Unit,
    onLogSmoke: (preset: SmokePreset, multiplier: Int) -> Unit,
    onOpenCravingEmergency: () -> Unit,
    modifier: Modifier = Modifier
) {
    var showCustomDialog by remember { mutableStateOf(false) }
    var customAmountText by remember { mutableStateOf("250") }
    var customDrinkName by remember { mutableStateOf("Water") }
    var selectedMultiplier by remember { mutableStateOf(1) }

    val haptic = androidx.compose.ui.platform.LocalHapticFeedback.current

    Column(modifier = modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 4.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = if (habitType == HabitType.WATER) "QUICK INTAKE" else "QUICK LOG",
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                color = ThemeColors.textSecondary,
                letterSpacing = 1.sp
            )

            // Multiplier Selector Pill Bar: 1x, 2x, 3x, 5x
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                listOf(1, 2, 3, 5).forEach { mult ->
                    val isSelected = selectedMultiplier == mult
                    Box(
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(
                                if (isSelected) {
                                    if (habitType == HabitType.WATER) ThemeColors.accentCyan.copy(alpha = 0.35f)
                                    else Color(0xFFFF4D4D).copy(alpha = 0.35f)
                                } else Color.White.copy(alpha = 0.06f)
                            )
                            .border(
                                width = 1.dp,
                                color = if (isSelected) {
                                    if (habitType == HabitType.WATER) ThemeColors.accentCyan
                                    else Color(0xFFFF4D4D)
                                } else Color.Transparent,
                                shape = CircleShape
                            )
                            .clickable {
                                haptic.performHapticFeedback(androidx.compose.ui.hapticfeedback.HapticFeedbackType.LongPress)
                                selectedMultiplier = mult
                            }
                            .padding(horizontal = 8.dp, vertical = 3.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = "${mult}x",
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold,
                            color = if (isSelected) Color.White else ThemeColors.textSecondary
                        )
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(6.dp))

        if (habitType == HabitType.WATER) {
            // 2-Column Grid (3 pairs of 2 buttons)
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                // Row 1: Coffee & Small Water
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    QuickActionChip(
                        title = "Coffee",
                        subtitle = "+${(100 * selectedMultiplier)} ml",
                        icon = Icons.Rounded.Coffee,
                        color = Color(0xFFF59E0B),
                        onClick = { onLogWater(WaterPreset.COFFEE, selectedMultiplier) },
                        modifier = Modifier.weight(1f)
                    )
                    QuickActionChip(
                        title = "Small Water",
                        subtitle = "+${(150 * selectedMultiplier)} ml",
                        icon = Icons.Rounded.WaterDrop,
                        color = Color(0xFF38BDF8),
                        onClick = { onLogWater(WaterPreset.SMALL_WATER, selectedMultiplier) },
                        modifier = Modifier.weight(1f)
                    )
                }

                // Row 2: Large Water & Bottle
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    QuickActionChip(
                        title = "Large Water",
                        subtitle = "+${(300 * selectedMultiplier)} ml",
                        icon = Icons.Rounded.WaterDrop,
                        color = ThemeColors.accentCyan,
                        onClick = { onLogWater(WaterPreset.LARGE_WATER, selectedMultiplier) },
                        modifier = Modifier.weight(1f)
                    )
                    QuickActionChip(
                        title = "Bottle",
                        subtitle = "+${(500 * selectedMultiplier)} ml",
                        icon = Icons.Rounded.Science,
                        color = Color(0xFF06B6D4),
                        onClick = { onLogWater(WaterPreset.BOTTLE, selectedMultiplier) },
                        modifier = Modifier.weight(1f)
                    )
                }

                // Row 3: Tea & Custom
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    QuickActionChip(
                        title = "Tea",
                        subtitle = "+${(250 * selectedMultiplier)} ml",
                        icon = Icons.Rounded.EmojiFoodBeverage,
                        color = Color(0xFF84CC16),
                        onClick = { onLogWater(WaterPreset.TEA, selectedMultiplier) },
                        modifier = Modifier.weight(1f)
                    )
                    QuickActionChip(
                        title = "Custom",
                        subtitle = "Enter ml",
                        icon = Icons.Rounded.Add,
                        color = Color.White,
                        onClick = { showCustomDialog = true },
                        modifier = Modifier.weight(1f)
                    )
                }
            }
        } else {
            // Smokes 2-Column Grid (2 pairs of 2 buttons) + Emergency Protocol Card
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                // Row 1: Cigarette & Heated
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    QuickActionChip(
                        title = "Cigarette",
                        subtitle = if (selectedMultiplier > 1) "+$selectedMultiplier Logs" else "+1 Log",
                        icon = Icons.Rounded.LocalFireDepartment,
                        color = Color(0xFFEF4444),
                        onClick = { onLogSmoke(SmokePreset.CIGARETTE, selectedMultiplier) },
                        modifier = Modifier.weight(1f)
                    )
                    QuickActionChip(
                        title = "Heated",
                        subtitle = if (selectedMultiplier > 1) "+$selectedMultiplier Logs" else "+1 Log",
                        icon = Icons.Rounded.Bolt,
                        color = Color(0xFF3B82F6),
                        onClick = { onLogSmoke(SmokePreset.HEATED, selectedMultiplier) },
                        modifier = Modifier.weight(1f)
                    )
                }

                // Row 2: Rolled & Cigarillo
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    QuickActionChip(
                        title = "Rolled",
                        subtitle = if (selectedMultiplier > 1) "+$selectedMultiplier Logs" else "+1 Log",
                        icon = Icons.Rounded.Eco,
                        color = Color(0xFFF97316),
                        onClick = { onLogSmoke(SmokePreset.ROLLED, selectedMultiplier) },
                        modifier = Modifier.weight(1f)
                    )
                    QuickActionChip(
                        title = "Cigarillo",
                        subtitle = if (selectedMultiplier > 1) "+$selectedMultiplier Logs" else "+1 Log",
                        icon = Icons.Rounded.LocalFireDepartment,
                        color = Color(0xFFA855F7),
                        onClick = { onLogSmoke(SmokePreset.CIGARILLO, selectedMultiplier) },
                        modifier = Modifier.weight(1f)
                    )
                }

                // Emergency 4D Craving Protocol Action Card
                GlassCard(
                    modifier = Modifier.fillMaxWidth(),
                    cornerRadius = 14.dp,
                    padding = 12.dp,
                    onClick = onOpenCravingEmergency
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier.weight(1f)
                        ) {
                            Box(
                                modifier = Modifier
                                    .size(36.dp)
                                    .clip(CircleShape)
                                    .background(Color(0xFFFF3B30).copy(alpha = 0.2f))
                                    .border(1.dp, Color(0xFFFF3B30).copy(alpha = 0.5f), CircleShape),
                                contentAlignment = Alignment.Center
                            ) {
                                Icon(
                                    imageVector = Icons.Rounded.Timer,
                                    contentDescription = null,
                                    tint = Color(0xFFFF3B30),
                                    modifier = Modifier.size(18.dp)
                                )
                            }

                            Spacer(modifier = Modifier.width(12.dp))

                            Column {
                                Text(
                                    text = "4D Craving Protocol",
                                    fontSize = 14.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = Color.White
                                )
                                Text(
                                    text = "Delay • Breathe • Water • Distract (5 min)",
                                    fontSize = 11.sp,
                                    color = ThemeColors.textSecondary
                                )
                            }
                        }

                        Box(
                            modifier = Modifier
                                .clip(CircleShape)
                                .background(Color(0xFFFF3B30).copy(alpha = 0.15f))
                                .border(1.dp, Color(0xFFFF3B30).copy(alpha = 0.35f), CircleShape)
                                .padding(horizontal = 10.dp, vertical = 5.dp)
                        ) {
                            Text(
                                text = "START",
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color(0xFFFF3B30)
                            )
                        }
                    }
                }
            }
        }
    }

    // Custom Water Intake Dialog
    if (showCustomDialog) {
        AlertDialog(
            onDismissRequest = { showCustomDialog = false },
            title = {
                Text(
                    text = "Custom Water Intake",
                    color = Color.White,
                    fontWeight = FontWeight.Bold
                )
            },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(
                        text = "Enter volume in milliliters (ml):",
                        fontSize = 13.sp,
                        color = ThemeColors.textSecondary
                    )

                    OutlinedTextField(
                        value = customAmountText,
                        onValueChange = { customAmountText = it },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedBorderColor = ThemeColors.accentCyan,
                            unfocusedBorderColor = Color.White.copy(alpha = 0.2f),
                            focusedTextColor = Color.White,
                            unfocusedTextColor = Color.White
                        ),
                        modifier = Modifier.fillMaxWidth()
                    )

                    Row(
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        listOf(150, 250, 400, 600).forEach { amt ->
                            Box(
                                modifier = Modifier
                                    .weight(1f)
                                    .clip(RoundedCornerShape(8.dp))
                                    .background(Color.White.copy(alpha = 0.08f))
                                    .clickable { customAmountText = amt.toString() }
                                    .padding(vertical = 6.dp),
                                contentAlignment = Alignment.Center
                            ) {
                                Text(
                                    text = "${amt}ml",
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = ThemeColors.accentCyan
                                )
                            }
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        val amt = customAmountText.toDoubleOrNull() ?: 250.0
                        onLogCustomWater(amt, customDrinkName)
                        showCustomDialog = false
                    }
                ) {
                    Text("Add", color = ThemeColors.accentCyan, fontWeight = FontWeight.Bold)
                }
            },
            dismissButton = {
                TextButton(onClick = { showCustomDialog = false }) {
                    Text("Cancel", color = ThemeColors.textSecondary)
                }
            },
            containerColor = Color(0xFF0F1A2A),
            shape = RoundedCornerShape(18.dp)
        )
    }
}

@Composable
fun QuickActionChip(
    title: String,
    icon: ImageVector,
    color: Color,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    subtitle: String? = null
) {
    val haptic = androidx.compose.ui.platform.LocalHapticFeedback.current
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(14.dp))
            .background(Color.White.copy(alpha = 0.06f))
            .border(1.dp, Color.White.copy(alpha = 0.12f), RoundedCornerShape(14.dp))
            .clickable {
                haptic.performHapticFeedback(androidx.compose.ui.hapticfeedback.HapticFeedbackType.LongPress)
                onClick()
            }
            .padding(horizontal = 12.dp, vertical = 11.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(34.dp)
                    .clip(CircleShape)
                    .background(color.copy(alpha = 0.15f))
                    .border(1.dp, color.copy(alpha = 0.35f), CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = color,
                    modifier = Modifier.size(17.dp)
                )
            }

            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    text = title,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White
                )
                if (subtitle != null) {
                    Text(
                        text = subtitle,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = color
                    )
                }
            }
        }
    }
}
