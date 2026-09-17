package com.intellidream.daily.presentation.finances

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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
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
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.ThemeColors

@Composable
fun AddLedgerItemSheet(
    defaultSectionName: String = "Outgoing",
    onAddItem: (sectionName: String, key: String, amount: Double, note: String?) -> Unit,
    onDismiss: () -> Unit
) {
    var selectedSection by remember { mutableStateOf(defaultSectionName) }
    var itemName by remember { mutableStateOf("") }
    var amountText by remember { mutableStateOf("") }
    var noteText by remember { mutableStateOf("") }

    val availableSections = listOf("Incoming", "Outgoing", "Deposit")
    val isScaled = !selectedSection.equals("Deposit", ignoreCase = true)

    val cleanAmount = amountText.trim().replace(",", ".").toDoubleOrNull()
    val isValid = itemName.isNotBlank() && cleanAmount != null

    val convertedAmountPreview = remember(amountText, isScaled) {
        val num = amountText.trim().replace(",", ".").toDoubleOrNull()
        if (num != null) {
            if (isScaled) {
                val lei = num * 100.0
                "${lei.toLong()} Lei (${num.toLong()})"
            } else {
                "${num.toLong()} Lei"
            }
        } else ""
    }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color(0xFF060D1A))
                .padding(horizontal = 20.dp, vertical = 20.dp)
        ) {
            Column(
                modifier = Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.spacedBy(18.dp)
            ) {
                // Toolbar
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    IconButton(onClick = onDismiss) {
                        Icon(
                            imageVector = Icons.Rounded.Close,
                            contentDescription = "Închide",
                            tint = Color.White
                        )
                    }

                    Text(
                        text = "Adaugă Categorie",
                        color = Color.White,
                        fontSize = 17.sp,
                        fontWeight = FontWeight.Bold
                    )

                    Text(
                        text = "Adaugă",
                        color = if (isValid) ThemeColors.accentGreen else ThemeColors.fgMutedDark.copy(alpha = 0.4f),
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier
                            .clip(CircleShape)
                            .then(
                                if (isValid) {
                                    Modifier.clickable {
                                        onAddItem(
                                            selectedSection,
                                            itemName.trim(),
                                            cleanAmount!!,
                                            noteText.trim().ifEmpty { null }
                                        )
                                        onDismiss()
                                    }
                                } else Modifier
                            )
                            .padding(horizontal = 8.dp, vertical = 6.dp)
                    )
                }

                // Section Selector
                GlassCard(
                    modifier = Modifier.fillMaxWidth(),
                    cornerRadius = 18.dp,
                    padding = 14.dp
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(
                            text = "SECȚIUNE DESTINAȚIE",
                            color = ThemeColors.fgMutedDark,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                            letterSpacing = 1.1.sp
                        )

                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(12.dp))
                                .background(Color.White.copy(alpha = 0.06f))
                                .padding(3.dp),
                            horizontalArrangement = Arrangement.SpaceEvenly
                        ) {
                            availableSections.forEach { sec ->
                                val isSelected = selectedSection.equals(sec, ignoreCase = true)
                                Box(
                                    modifier = Modifier
                                        .weight(1f)
                                        .clip(RoundedCornerShape(10.dp))
                                        .background(
                                            if (isSelected) ThemeColors.accentGreen.copy(alpha = 0.35f)
                                            else Color.Transparent
                                        )
                                        .clickable { selectedSection = sec }
                                        .padding(vertical = 8.dp),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Text(
                                        text = sec,
                                        color = if (isSelected) Color.White else ThemeColors.fgMutedDark,
                                        fontSize = 13.sp,
                                        fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Medium
                                    )
                                }
                            }
                        }
                    }
                }

                // Inputs Card
                GlassCard(
                    modifier = Modifier.fillMaxWidth(),
                    cornerRadius = 18.dp,
                    padding = 16.dp
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                        // Category Name
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(
                                text = "NUME CATEGORIE / CHELTUIALĂ",
                                color = ThemeColors.fgMutedDark,
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold,
                                letterSpacing = 1.1.sp
                            )
                            OutlinedTextField(
                                value = itemName,
                                onValueChange = { itemName = it },
                                placeholder = { Text("ex: Sala, Restaurant, Uber, Bonus", color = ThemeColors.fgMutedDark) },
                                modifier = Modifier.fillMaxWidth(),
                                colors = OutlinedTextFieldDefaults.colors(
                                    focusedContainerColor = Color.White.copy(alpha = 0.06f),
                                    unfocusedContainerColor = Color.White.copy(alpha = 0.04f),
                                    focusedBorderColor = ThemeColors.accentGreen,
                                    unfocusedBorderColor = Color.White.copy(alpha = 0.12f)
                                ),
                                shape = RoundedCornerShape(12.dp)
                            )
                        }

                        // Amount
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(
                                    text = if (isScaled) "VALOARE RAW DSL (1 = 100 LEI)" else "SUMĂ LEI",
                                    color = ThemeColors.fgMutedDark,
                                    fontSize = 10.sp,
                                    fontWeight = FontWeight.Bold,
                                    letterSpacing = 1.1.sp
                                )
                                if (convertedAmountPreview.isNotEmpty()) {
                                    Text(
                                        text = convertedAmountPreview,
                                        color = ThemeColors.accentGreen,
                                        fontSize = 12.sp,
                                        fontWeight = FontWeight.Bold
                                    )
                                }
                            }
                            OutlinedTextField(
                                value = amountText,
                                onValueChange = { amountText = it },
                                placeholder = { Text(if (isScaled) "ex: 151 sau 49" else "ex: 5000", color = ThemeColors.fgMutedDark) },
                                modifier = Modifier.fillMaxWidth(),
                                colors = OutlinedTextFieldDefaults.colors(
                                    focusedContainerColor = Color.White.copy(alpha = 0.06f),
                                    unfocusedContainerColor = Color.White.copy(alpha = 0.04f),
                                    focusedBorderColor = ThemeColors.accentGreen,
                                    unfocusedBorderColor = Color.White.copy(alpha = 0.12f)
                                ),
                                shape = RoundedCornerShape(12.dp)
                            )
                        }

                        // Note
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(
                                text = "NOTĂ SAU DETALII (OPȚIONAL)",
                                color = ThemeColors.fgMutedDark,
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold,
                                letterSpacing = 1.1.sp
                            )
                            OutlinedTextField(
                                value = noteText,
                                onValueChange = { noteText = it },
                                placeholder = { Text("ex: abonament anual, comision", color = ThemeColors.fgMutedDark) },
                                modifier = Modifier.fillMaxWidth(),
                                colors = OutlinedTextFieldDefaults.colors(
                                    focusedContainerColor = Color.White.copy(alpha = 0.06f),
                                    unfocusedContainerColor = Color.White.copy(alpha = 0.04f),
                                    focusedBorderColor = ThemeColors.accentGreen,
                                    unfocusedBorderColor = Color.White.copy(alpha = 0.12f)
                                ),
                                shape = RoundedCornerShape(12.dp)
                            )
                        }
                    }
                }
            }
        }
    }
}
