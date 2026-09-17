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

@OptIn(ExperimentalLayoutApi::class)
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

    Column(modifier = modifier.fillMaxWidth()) {
        Text(
            text = if (habitType == HabitType.WATER) "QUICK INTAKE" else "LOG SMOKE OR CRAVING",
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold,
            color = ThemeColors.textSecondary,
            letterSpacing = 1.sp,
            modifier = Modifier.padding(horizontal = 4.dp, vertical = 6.dp)
        )

        if (habitType == HabitType.WATER) {
            FlowRow(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                QuickActionChip(
                    title = "+100 Coffee",
                    icon = Icons.Rounded.Coffee,
                    color = Color(0xFFF59E0B),
                    onClick = { onLogWater(WaterPreset.COFFEE, 1) }
                )
                QuickActionChip(
                    title = "+150 Water",
                    icon = Icons.Rounded.WaterDrop,
                    color = Color(0xFF38BDF8),
                    onClick = { onLogWater(WaterPreset.SMALL_WATER, 1) }
                )
                QuickActionChip(
                    title = "+300 Water",
                    icon = Icons.Rounded.WaterDrop,
                    color = ThemeColors.accentCyan,
                    onClick = { onLogWater(WaterPreset.LARGE_WATER, 1) }
                )
                QuickActionChip(
                    title = "+500 Bottle",
                    icon = Icons.Rounded.Science,
                    color = Color(0xFF06B6D4),
                    onClick = { onLogWater(WaterPreset.BOTTLE, 1) }
                )
                QuickActionChip(
                    title = "+250 Tea",
                    icon = Icons.Rounded.EmojiFoodBeverage,
                    color = Color(0xFF84CC16),
                    onClick = { onLogWater(WaterPreset.TEA, 1) }
                )
                QuickActionChip(
                    title = "+ Custom",
                    icon = Icons.Rounded.Add,
                    color = Color.White,
                    onClick = { showCustomDialog = true }
                )
            }
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                FlowRow(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    QuickActionChip(
                        title = "+1 Cigarette",
                        icon = Icons.Rounded.LocalFireDepartment,
                        color = Color(0xFFEF4444),
                        onClick = { onLogSmoke(SmokePreset.CIGARETTE, 1) }
                    )
                    QuickActionChip(
                        title = "+1 Heated",
                        icon = Icons.Rounded.Bolt,
                        color = Color(0xFF3B82F6),
                        onClick = { onLogSmoke(SmokePreset.HEATED, 1) }
                    )
                    QuickActionChip(
                        title = "+1 Rolled",
                        icon = Icons.Rounded.Eco,
                        color = Color(0xFFF97316),
                        onClick = { onLogSmoke(SmokePreset.ROLLED, 1) }
                    )
                    QuickActionChip(
                        title = "+1 Cigarillo",
                        icon = Icons.Rounded.LocalFireDepartment,
                        color = Color(0xFFA855F7),
                        onClick = { onLogSmoke(SmokePreset.CIGARILLO, 1) }
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
                        Row(verticalAlignment = Alignment.CenterVertically) {
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
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .clip(CircleShape)
            .background(color.copy(alpha = 0.12f))
            .border(1.dp, color.copy(alpha = 0.35f), CircleShape)
            .clickable(onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 7.dp)
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(5.dp)
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = color,
                modifier = Modifier.size(13.dp)
            )
            Text(
                text = title,
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                color = color
            )
        }
    }
}
