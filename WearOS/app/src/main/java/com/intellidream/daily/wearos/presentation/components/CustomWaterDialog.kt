package com.intellidream.daily.wearos.presentation.components

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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.ButtonDefaults
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.dialog.Dialog
import com.intellidream.daily.wearos.presentation.theme.DailyWearColors

@Composable
fun CustomWaterDialog(
    show: Boolean,
    onDismiss: () -> Unit,
    onLog: (amount: Int, type: String) -> Unit
) {
    if (!show) return

    var amountMl by remember { mutableIntStateOf(250) }
    var selectedDrink by remember { mutableStateOf("Glass") }
    var multiplier by remember { mutableIntStateOf(1) }

    val presets = remember {
        listOf(
            Triple("Glass", 250, DailyWearColors.WaterCyan),
            Triple("Bottle", 500, Color(0xFF06B6D4)),
            Triple("Tea", 250, Color(0xFF10B981)),
            Triple("Coffee", 100, DailyWearColors.CoffeeOrange),
            Triple("Small", 150, DailyWearColors.WaterCyan),
            Triple("Large", 300, DailyWearColors.WaterCyan)
        )
    }

    Dialog(showDialog = show, onDismissRequest = onDismiss) {
        val scrollState = rememberScrollState()
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black),
            contentAlignment = Alignment.Center
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(scrollState)
                    .padding(horizontal = 8.dp, vertical = 6.dp)
            ) {
                Text(
                    text = "Custom Water",
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Bold,
                    color = DailyWearColors.WaterCyan
                )

                Spacer(Modifier.height(4.dp))

                // Hero Amount Display
                val totalAmount = amountMl * multiplier
                Text(
                    text = "$totalAmount ml",
                    fontSize = 24.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White
                )

                if (multiplier > 1) {
                    Text(
                        text = "(${multiplier}× $amountMl ml $selectedDrink)",
                        fontSize = 10.sp,
                        color = Color.White.copy(alpha = 0.6f)
                    )
                } else {
                    Text(
                        text = selectedDrink,
                        fontSize = 11.sp,
                        color = Color.White.copy(alpha = 0.6f)
                    )
                }

                Spacer(Modifier.height(6.dp))

                // Amount Stepper (-25 / +25)
                Row(
                    modifier = Modifier.fillMaxWidth(0.85f),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Button(
                        onClick = { amountMl = maxOf(50, amountMl - 25) },
                        colors = ButtonDefaults.secondaryButtonColors(),
                        modifier = Modifier.width(36.dp).height(28.dp)
                    ) {
                        Text("-25", fontSize = 10.sp, fontWeight = FontWeight.Bold)
                    }

                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        (1..4).forEach { m ->
                            Box(
                                modifier = Modifier
                                    .clip(RoundedCornerShape(6.dp))
                                    .background(if (multiplier == m) DailyWearColors.WaterCyan else Color.White.copy(alpha = 0.12f))
                                    .clickable { multiplier = m }
                                    .padding(horizontal = 6.dp, vertical = 4.dp)
                            ) {
                                Text(
                                    text = "${m}×",
                                    fontSize = 10.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = if (multiplier == m) Color.Black else Color.White
                                )
                            }
                        }
                    }

                    Button(
                        onClick = { amountMl = minOf(1200, amountMl + 25) },
                        colors = ButtonDefaults.secondaryButtonColors(),
                        modifier = Modifier.width(36.dp).height(28.dp)
                    ) {
                        Text("+25", fontSize = 10.sp, fontWeight = FontWeight.Bold)
                    }
                }

                Spacer(Modifier.height(8.dp))

                // Presets Grid
                presets.chunked(2).forEach { row ->
                    Row(
                        modifier = Modifier.fillMaxWidth(0.92f),
                        horizontalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        row.forEach { (name, amt, color) ->
                            val isSelected = selectedDrink == name
                            Box(
                                modifier = Modifier
                                    .weight(1f)
                                    .clip(RoundedCornerShape(8.dp))
                                    .background(if (isSelected) color.copy(alpha = 0.25f) else Color.White.copy(alpha = 0.10f))
                                    .border(1.dp, if (isSelected) color else Color.Transparent, RoundedCornerShape(8.dp))
                                    .clickable {
                                        selectedDrink = name
                                        amountMl = amt
                                    }
                                    .padding(horizontal = 6.dp, vertical = 5.dp),
                                contentAlignment = Alignment.Center
                            ) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Text(
                                        text = name,
                                        fontSize = 10.sp,
                                        fontWeight = FontWeight.SemiBold,
                                        color = Color.White
                                    )
                                    Spacer(Modifier.width(3.dp))
                                    Text(
                                        text = "$amt",
                                        fontSize = 8.sp,
                                        color = Color.White.copy(alpha = 0.6f)
                                    )
                                }
                            }
                        }
                    }
                    Spacer(Modifier.height(4.dp))
                }

                Spacer(Modifier.height(6.dp))

                // Action Buttons
                Row(
                    modifier = Modifier.fillMaxWidth(0.92f),
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Button(
                        onClick = onDismiss,
                        colors = ButtonDefaults.secondaryButtonColors(),
                        modifier = Modifier
                            .weight(1f)
                            .height(32.dp)
                    ) {
                        Text("Cancel", fontSize = 11.sp)
                    }

                    Button(
                        onClick = {
                            onLog(totalAmount, selectedDrink)
                            onDismiss()
                        },
                        colors = ButtonDefaults.buttonColors(backgroundColor = DailyWearColors.WaterCyan),
                        modifier = Modifier
                            .weight(1f)
                            .height(32.dp)
                    ) {
                        Text("Log", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Color.Black)
                    }
                }
            }
        }
    }
}
