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
fun CustomSmokeDialog(
    show: Boolean,
    onDismiss: () -> Unit,
    onLog: (type: String, offsetMinutes: Int) -> Unit
) {
    if (!show) return

    var selectedType by remember { mutableStateOf("Cigarette") }
    var selectedOffsetMinutes by remember { mutableIntStateOf(0) }

    val presets = remember {
        listOf(
            Pair("Cigarette", DailyWearColors.SmokeRed),
            Pair("Heated Tobacco", DailyWearColors.HeatIndigo),
            Pair("Rolled", Color(0xFFF97316)),
            Pair("Cigarillo", Color(0xFFA855F7))
        )
    }

    val timeOffsets = remember {
        listOf(
            Pair("Now", 0),
            Pair("-15m", 15),
            Pair("-30m", 30),
            Pair("-1h", 60)
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
                    text = "Custom Smoke",
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Bold,
                    color = DailyWearColors.SmokeRed
                )

                Spacer(Modifier.height(6.dp))

                // Presets 2x2 Grid
                Text(
                    text = "TYPE",
                    fontSize = 9.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White.copy(alpha = 0.5f),
                    modifier = Modifier.fillMaxWidth(0.9f)
                )

                Spacer(Modifier.height(4.dp))

                presets.chunked(2).forEach { row ->
                    Row(
                        modifier = Modifier.fillMaxWidth(0.92f),
                        horizontalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        row.forEach { (name, color) ->
                            val isSelected = selectedType == name
                            Box(
                                modifier = Modifier
                                    .weight(1f)
                                    .clip(RoundedCornerShape(8.dp))
                                    .background(if (isSelected) color.copy(alpha = 0.25f) else Color.White.copy(alpha = 0.10f))
                                    .border(1.dp, if (isSelected) color else Color.Transparent, RoundedCornerShape(8.dp))
                                    .clickable { selectedType = name }
                                    .padding(horizontal = 6.dp, vertical = 6.dp),
                                contentAlignment = Alignment.Center
                            ) {
                                Text(
                                    text = name,
                                    fontSize = 10.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = Color.White
                                )
                            }
                        }
                    }
                    Spacer(Modifier.height(4.dp))
                }

                Spacer(Modifier.height(6.dp))

                // Time Offsets
                Text(
                    text = "TIME LOGGED",
                    fontSize = 9.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White.copy(alpha = 0.5f),
                    modifier = Modifier.fillMaxWidth(0.9f)
                )

                Spacer(Modifier.height(4.dp))

                Row(
                    modifier = Modifier.fillMaxWidth(0.92f),
                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    timeOffsets.forEach { (label, minutes) ->
                        val isSelected = selectedOffsetMinutes == minutes
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .clip(RoundedCornerShape(6.dp))
                                .background(if (isSelected) Color.White.copy(alpha = 0.25f) else Color.White.copy(alpha = 0.10f))
                                .border(1.dp, if (isSelected) Color.White.copy(alpha = 0.4f) else Color.Transparent, RoundedCornerShape(6.dp))
                            .clickable { selectedOffsetMinutes = minutes }
                            .padding(vertical = 4.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                text = label,
                                fontSize = 10.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = if (isSelected) Color.White else Color.White.copy(alpha = 0.6f)
                            )
                        }
                    }
                }

                Spacer(Modifier.height(8.dp))

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
                            onLog(selectedType, selectedOffsetMinutes)
                            onDismiss()
                        },
                        colors = ButtonDefaults.buttonColors(backgroundColor = DailyWearColors.SmokeRed),
                        modifier = Modifier
                            .weight(1f)
                            .height(32.dp)
                    ) {
                        Text("Log", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Color.White)
                    }
                }
            }
        }
    }
}
