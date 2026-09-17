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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.SmartLedgerItem
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.util.Locale

@Composable
fun SmartLedgerQuickAdjustSheet(
    item: SmartLedgerItem,
    onSaveAmount: (newRaw: Double) -> Unit,
    onDelete: () -> Unit,
    onDismiss: () -> Unit
) {
    val initialRawStr = if ((item.rawAmount % 1.0) == 0.0) {
        "${item.rawAmount.toLong()}"
    } else {
        String.format(Locale.US, "%.2f", item.rawAmount)
    }

    var inputAmountText by remember { mutableStateOf(initialRawStr) }
    var showDeleteConfirmation by remember { mutableStateOf(false) }

    val sectionColor = when (item.sectionName.lowercase()) {
        "incoming" -> ThemeColors.accentPurple
        "outgoing" -> ThemeColors.accentOrange
        "deposit" -> ThemeColors.accentGreen
        "dentist" -> ThemeColors.accentPink
        else -> ThemeColors.accentCyan
    }

    // Live converted amount calculation
    val parsedCurrentInput = inputAmountText.trim().replace(",", ".").toDoubleOrNull() ?: item.rawAmount
    val liveCalculatedAmount = if (item.isScaled) parsedCurrentInput * 100.0 else parsedCurrentInput

    val formattedLiveCalculated: String = remember(liveCalculatedAmount) {
        val symbols = DecimalFormatSymbols(Locale("ro", "RO")).apply {
            groupingSeparator = '.'
            decimalSeparator = ','
        }
        val hasDecimals = (liveCalculatedAmount % 1.0) != 0.0
        val pattern = if (hasDecimals) "#,##0.00" else "#,##0"
        "${DecimalFormat(pattern, symbols).format(liveCalculatedAmount)} Lei"
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
                        text = item.displayName,
                        color = Color.White,
                        fontSize = 17.sp,
                        fontWeight = FontWeight.Bold
                    )

                    Text(
                        text = "Salvează",
                        color = ThemeColors.accentGreen,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier
                            .clip(CircleShape)
                            .clickable {
                                onSaveAmount(parsedCurrentInput)
                                onDismiss()
                            }
                            .padding(horizontal = 8.dp, vertical = 6.dp)
                    )
                }

                // Hero Info Card
                GlassCard(
                    modifier = Modifier.fillMaxWidth(),
                    cornerRadius = 20.dp,
                    padding = 18.dp
                ) {
                    Column(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Box(
                                modifier = Modifier
                                    .clip(CircleShape)
                                    .background(sectionColor.copy(alpha = 0.15f))
                                    .padding(horizontal = 10.dp, vertical = 4.dp)
                            ) {
                                Text(
                                    text = item.sectionName.uppercase(),
                                    color = sectionColor,
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.Bold
                                )
                            }

                            if (item.percentageOfSection > 0) {
                                Text(
                                    text = String.format(Locale.US, "%.1f%% din secțiune", item.percentageOfSection * 100),
                                    color = ThemeColors.fgMutedDark,
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.SemiBold
                                )
                            }
                        }

                        Text(
                            text = item.displayName,
                            color = Color.White,
                            fontSize = 20.sp,
                            fontWeight = FontWeight.Bold
                        )

                        Text(
                            text = formattedLiveCalculated,
                            color = ThemeColors.accentGreen,
                            fontSize = 24.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }

                // Quick Delta Chips Section
                GlassCard(
                    modifier = Modifier.fillMaxWidth(),
                    cornerRadius = 18.dp,
                    padding = 16.dp
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text(
                            text = "AJUSTARE RAPIDĂ",
                            color = ThemeColors.fgMutedDark,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                            letterSpacing = 1.1.sp
                        )

                        val deltas = if (item.isScaled) listOf(-10.0, -5.0, -1.0, 1.0, 5.0, 10.0)
                        else listOf(-100.0, -50.0, -10.0, 10.0, 50.0, 100.0)

                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            deltas.forEach { delta ->
                                val deltaLabel = if (delta > 0) "+${delta.toInt()}" else "${delta.toInt()}"
                                val isPositive = delta > 0
                                Box(
                                    modifier = Modifier
                                        .clip(RoundedCornerShape(10.dp))
                                        .background(
                                            (if (isPositive) ThemeColors.accentGreen else ThemeColors.accentPink).copy(alpha = 0.14f)
                                        )
                                        .border(
                                            1.dp,
                                            (if (isPositive) ThemeColors.accentGreen else ThemeColors.accentPink).copy(alpha = 0.35f),
                                            RoundedCornerShape(10.dp)
                                        )
                                        .clickable {
                                            val current = inputAmountText.toDoubleOrNull() ?: item.rawAmount
                                            val updated = (current + delta).coerceAtLeast(0.0)
                                            inputAmountText = if ((updated % 1.0) == 0.0) "${updated.toLong()}" else String.format(Locale.US, "%.2f", updated)
                                        }
                                        .padding(horizontal = 8.dp, vertical = 8.dp)
                                ) {
                                    Text(
                                        text = deltaLabel,
                                        color = if (isPositive) ThemeColors.accentGreen else ThemeColors.accentPink,
                                        fontSize = 12.sp,
                                        fontWeight = FontWeight.Bold
                                    )
                                }
                            }
                        }
                    }
                }

                // Exact Amount Editor
                GlassCard(
                    modifier = Modifier.fillMaxWidth(),
                    cornerRadius = 18.dp,
                    padding = 16.dp
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text(
                            text = if (item.isScaled) "VALOARE RAW DSL (1 = 100 LEI)" else "SUMĂ LEI",
                            color = ThemeColors.fgMutedDark,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                            letterSpacing = 1.1.sp
                        )

                        OutlinedTextField(
                            value = inputAmountText,
                            onValueChange = { inputAmountText = it },
                            modifier = Modifier.fillMaxWidth(),
                            textStyle = androidx.compose.ui.text.TextStyle(
                                fontSize = 18.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color.White
                            ),
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

                Spacer(modifier = Modifier.weight(1f))

                // Delete Action Button
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(14.dp))
                        .background(ThemeColors.error.copy(alpha = 0.12f))
                        .border(1.dp, ThemeColors.error.copy(alpha = 0.35f), RoundedCornerShape(14.dp))
                        .clickable { showDeleteConfirmation = true }
                        .padding(vertical = 12.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.Delete,
                            contentDescription = null,
                            tint = ThemeColors.error,
                            modifier = Modifier.size(16.dp)
                        )
                        Text(
                            text = "Șterge Categoria",
                            color = ThemeColors.error,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }
            }

            if (showDeleteConfirmation) {
                AlertDialog(
                    onDismissRequest = { showDeleteConfirmation = false },
                    title = { Text("Sigur dorești să ștergi această categorie?") },
                    text = { Text("Această acțiune va elimina linia din Smart Ledger și va recalcula automat soldul și totalurile.") },
                    confirmButton = {
                        TextButton(
                            onClick = {
                                onDelete()
                                showDeleteConfirmation = false
                                onDismiss()
                            }
                        ) {
                            Text("Șterge Categoria", color = ThemeColors.error)
                        }
                    },
                    dismissButton = {
                        TextButton(onClick = { showDeleteConfirmation = false }) {
                            Text("Anulează", color = Color.White)
                        }
                    }
                )
            }
        }
    }
}
