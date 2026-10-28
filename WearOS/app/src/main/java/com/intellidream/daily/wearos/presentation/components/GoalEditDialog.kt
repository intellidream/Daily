package com.intellidream.daily.wearos.presentation.components

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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
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
fun GoalEditDialog(
    show: Boolean,
    isWater: Boolean,
    currentValue: Int,
    onDismiss: () -> Unit,
    onSave: (Int) -> Unit
) {
    if (!show) return

    var targetValue by remember(currentValue) { mutableIntStateOf(currentValue) }
    val step = if (isWater) 100 else 1
    val minVal = if (isWater) 500 else 1
    val maxVal = if (isWater) 6000 else 100

    Dialog(showDialog = show, onDismissRequest = onDismiss) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black),
            contentAlignment = Alignment.Center
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
                modifier = Modifier.padding(8.dp)
            ) {
                Text(
                    text = if (isWater) "Edit Water Goal" else "Edit Daily Baseline",
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    color = if (isWater) DailyWearColors.WaterCyan else DailyWearColors.SmokeRed
                )

                Spacer(Modifier.height(4.dp))

                Text(
                    text = "$targetValue",
                    fontSize = 32.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White
                )

                Text(
                    text = if (isWater) "ml per day" else "cigarettes / day",
                    fontSize = 10.sp,
                    color = Color.White.copy(alpha = 0.6f)
                )

                Spacer(Modifier.height(8.dp))

                // Increment / Decrement Steppers
                Row(
                    modifier = Modifier.fillMaxWidth(0.9f),
                    horizontalArrangement = Arrangement.SpaceEvenly
                ) {
                    Button(
                        onClick = {
                            targetValue = maxOf(minVal, targetValue - step)
                        },
                        colors = ButtonDefaults.secondaryButtonColors(),
                        modifier = Modifier
                            .width(44.dp)
                            .height(32.dp)
                    ) {
                        Text("-", fontSize = 16.sp, fontWeight = FontWeight.Bold)
                    }

                    Button(
                        onClick = {
                            targetValue = minOf(maxVal, targetValue + step)
                        },
                        colors = ButtonDefaults.secondaryButtonColors(),
                        modifier = Modifier
                            .width(44.dp)
                            .height(32.dp)
                    ) {
                        Text("+", fontSize = 16.sp, fontWeight = FontWeight.Bold)
                    }
                }

                Spacer(Modifier.height(8.dp))

                // Actions Row
                Row(
                    modifier = Modifier.fillMaxWidth(0.85f),
                    horizontalArrangement = Arrangement.SpaceBetween
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

                    Spacer(Modifier.width(8.dp))

                    Button(
                        onClick = {
                            onSave(targetValue)
                            onDismiss()
                        },
                        colors = ButtonDefaults.buttonColors(
                            backgroundColor = if (isWater) DailyWearColors.WaterCyan else DailyWearColors.SmokeRed
                        ),
                        modifier = Modifier
                            .weight(1f)
                            .height(32.dp)
                    ) {
                        Text("Save", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = if (isWater) Color.Black else Color.White)
                    }
                }
            }
        }
    }
}
