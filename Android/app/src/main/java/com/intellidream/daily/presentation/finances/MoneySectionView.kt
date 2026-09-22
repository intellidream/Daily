package com.intellidream.daily.presentation.finances

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.AddCircle
import androidx.compose.material.icons.rounded.ArrowDownward
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.Balance
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.MedicalServices
import androidx.compose.material.icons.rounded.Savings
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Remove
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.ParsedSmartLedger
import com.intellidream.daily.model.SmartLedgerItem
import com.intellidream.daily.model.SmartLedgerSection

@Composable
fun MoneySectionView(
    ledger: ParsedSmartLedger,
    onOpenEditor: () -> Unit,
    onSelectItem: (SmartLedgerItem) -> Unit,
    onAddItem: (String) -> Unit,
    onAdjustItem: ((SmartLedgerItem, Double) -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(18.dp)
    ) {
        // Net Worth Hero Card
        NetWorthHeroCard(
            ledger = ledger,
            onOpenEditor = onOpenEditor
        )

        // Dynamic Section Cards
        ledger.sections.forEach { section ->
            LedgerSectionCard(
                section = section,
                onSelectItem = onSelectItem,
                onAddItem = { onAddItem(section.name) },
                onAdjustItem = onAdjustItem
            )
        }
    }
}

@Composable
private fun NetWorthHeroCard(
    ledger: ParsedSmartLedger,
    onOpenEditor: () -> Unit
) {
    GlassCard(
        modifier = Modifier.fillMaxWidth(),
        cornerRadius = 22.dp,
        padding = 20.dp
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        text = "TOTAL NET WORTH",
                        color = ThemeColors.fgMutedDark,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        letterSpacing = 1.2.sp
                    )
                    Text(
                        text = ledger.formattedNetWorth,
                        color = Color.White,
                        fontSize = 32.sp,
                        fontWeight = FontWeight.Bold
                    )
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "Est.",
                            color = ThemeColors.fgMutedDark,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Medium
                        )
                        Text(
                            text = ledger.formattedNetWorthEUR,
                            color = ThemeColors.accentGreen,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }

                // Edit Ledger Button
                Box(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(ThemeColors.accentGreen.copy(alpha = 0.18f))
                        .border(1.dp, ThemeColors.accentGreen.copy(alpha = 0.40f), CircleShape)
                        .clickable(onClick = onOpenEditor)
                        .padding(horizontal = 12.dp, vertical = 7.dp)
                ) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(5.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.Edit,
                            contentDescription = null,
                            tint = ThemeColors.accentGreen,
                            modifier = Modifier.size(13.dp)
                        )
                        Text(
                            text = "Edit Ledger",
                            color = ThemeColors.accentGreen,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }
            }

            // 4 Breakdown Badges
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                MetricBadge(
                    label = "DEPOZITE",
                    value = ledger.formattedBadge(ledger.depositTotal),
                    color = ThemeColors.accentGreen,
                    modifier = Modifier.weight(1f)
                )
                MetricBadge(
                    label = "SOLD",
                    value = ledger.formattedBadge(ledger.balanceTotal),
                    color = ThemeColors.accentCyan,
                    modifier = Modifier.weight(1f)
                )
                MetricBadge(
                    label = "INCOMING",
                    value = ledger.formattedBadge(ledger.incomingTotal),
                    color = ThemeColors.accentPurple,
                    modifier = Modifier.weight(1f)
                )
                if (ledger.dentistTotal > 0) {
                    MetricBadge(
                        label = "DENTIST",
                        value = ledger.formattedBadge(ledger.dentistTotal),
                        color = ThemeColors.accentPink,
                        modifier = Modifier.weight(1f)
                    )
                }
            }
        }
    }
}

@Composable
private fun MetricBadge(
    label: String,
    value: String,
    color: Color,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .background(color.copy(alpha = 0.12f))
            .border(1.dp, color.copy(alpha = 0.25f), RoundedCornerShape(12.dp))
            .padding(horizontal = 8.dp, vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        Text(
            text = label,
            color = color,
            fontSize = 9.sp,
            fontWeight = FontWeight.Bold,
            maxLines = 1
        )
        Text(
            text = value,
            color = Color.White,
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold,
            maxLines = 1
        )
    }
}

@Composable
private fun LedgerSectionCard(
    section: SmartLedgerSection,
    onSelectItem: (SmartLedgerItem) -> Unit,
    onAddItem: () -> Unit,
    onAdjustItem: ((SmartLedgerItem, Double) -> Unit)? = null
) {
    val (icon, color, title) = getSectionStyle(section.name)
    val haptic = LocalHapticFeedback.current

    GlassCard(
        modifier = Modifier.fillMaxWidth(),
        cornerRadius = 20.dp,
        padding = 18.dp
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            // Header
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = icon,
                        contentDescription = null,
                        tint = color,
                        modifier = Modifier.size(18.dp)
                    )
                    Text(
                        text = title,
                        color = color,
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold
                    )

                    if (!section.name.equals("Balance", ignoreCase = true) && !section.name.equals("Dentist", ignoreCase = true)) {
                        Box(
                            modifier = Modifier
                                .clip(CircleShape)
                                .background(color.copy(alpha = 0.12f))
                                .border(1.dp, color.copy(alpha = 0.25f), CircleShape)
                                .clickable(onClick = onAddItem)
                                .padding(horizontal = 8.dp, vertical = 4.dp)
                        ) {
                            Row(
                                horizontalArrangement = Arrangement.spacedBy(4.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(
                                    imageVector = Icons.Rounded.Add,
                                    contentDescription = "Adaugă",
                                    tint = color,
                                    modifier = Modifier.size(11.dp)
                                )
                                Text(
                                    text = "Adaugă",
                                    color = color,
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.Bold
                                )
                            }
                        }
                    }
                }

                // Section Total Badge
                Box(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(color.copy(alpha = 0.15f))
                        .padding(horizontal = 9.dp, vertical = 4.dp)
                ) {
                    Text(
                        text = section.formattedTotal,
                        color = Color.White,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
            }

            // Items List
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                section.items.forEach { item ->
                    if (item.isPureNote) {
                        // Pure note row
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(8.dp))
                                .background(Color.White.copy(alpha = 0.03f))
                                .padding(horizontal = 10.dp, vertical = 6.dp)
                        ) {
                            Text(
                                text = item.key,
                                color = ThemeColors.fgMutedDark,
                                fontSize = 11.sp,
                                fontStyle = androidx.compose.ui.text.font.FontStyle.Italic
                            )
                        }
                    } else {
                        // Interactive Item Row
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(12.dp))
                                .background(Color.White.copy(alpha = 0.04f))
                                .border(1.dp, Color.White.copy(alpha = 0.06f), RoundedCornerShape(12.dp))
                                .padding(horizontal = 12.dp, vertical = 10.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(
                                modifier = Modifier.weight(1f),
                                verticalArrangement = Arrangement.spacedBy(4.dp)
                            ) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    // Horizontally scrollable title allowing left-right dragging, tap opens quick adjust
                                    Row(
                                        modifier = Modifier.weight(1f, fill = false),
                                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        Box(
                                            modifier = Modifier
                                                .weight(1f, fill = false)
                                                .horizontalScroll(rememberScrollState())
                                                .clickable { onSelectItem(item) }
                                        ) {
                                            Text(
                                                text = item.displayName,
                                                color = Color.White,
                                                fontSize = 13.sp,
                                                fontWeight = FontWeight.SemiBold,
                                                maxLines = 1
                                            )
                                        }

                                        Icon(
                                            imageVector = Icons.Rounded.Tune,
                                            contentDescription = "Adjust",
                                            tint = ThemeColors.fgMutedDark.copy(alpha = 0.7f),
                                            modifier = Modifier
                                                .size(13.dp)
                                                .clickable { onSelectItem(item) }
                                        )
                                    }

                                    Spacer(modifier = Modifier.width(6.dp))

                                    // Amount badges and inline steppers
                                    Row(
                                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        Column(
                                            horizontalAlignment = Alignment.End,
                                            verticalArrangement = Arrangement.spacedBy(1.dp)
                                        ) {
                                            Text(
                                                text = item.formattedCalculatedAmount,
                                                color = Color.White,
                                                fontSize = 13.sp,
                                                fontWeight = FontWeight.Bold
                                            )
                                            if (item.currency == "EUR") {
                                                Text(
                                                    text = "~${item.formattedLeiAmount}",
                                                    color = ThemeColors.fgMutedDark,
                                                    fontSize = 10.sp,
                                                    fontWeight = FontWeight.Medium
                                                )
                                            } else if (item.isScaled && item.rawAmount > 0) {
                                                Text(
                                                    text = "(${item.formattedRawAmount})",
                                                    color = ThemeColors.fgMutedDark,
                                                    fontSize = 10.sp
                                                )
                                            }
                                        }

                                        // Inline Glass Stepper Controls [ - ] [ + ]
                                        if (onAdjustItem != null) {
                                            Row(
                                                horizontalArrangement = Arrangement.spacedBy(4.dp),
                                                verticalAlignment = Alignment.CenterVertically
                                            ) {
                                                Box(
                                                    modifier = Modifier
                                                        .size(26.dp)
                                                        .clip(CircleShape)
                                                        .background(Color.White.copy(alpha = 0.08f))
                                                        .border(1.dp, Color.White.copy(alpha = 0.20f), CircleShape)
                                                        .clickable {
                                                            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                                            val delta = if (item.isScaled) -1.0 else -100.0
                                                            onAdjustItem(item, delta)
                                                        },
                                                    contentAlignment = Alignment.Center
                                                ) {
                                                    Icon(
                                                        imageVector = Icons.Rounded.Remove,
                                                        contentDescription = "Decrease",
                                                        tint = Color.White,
                                                        modifier = Modifier.size(11.dp)
                                                    )
                                                }

                                                Box(
                                                    modifier = Modifier
                                                        .size(26.dp)
                                                        .clip(CircleShape)
                                                        .background(color.copy(alpha = 0.25f))
                                                        .border(1.dp, color.copy(alpha = 0.45f), CircleShape)
                                                        .clickable {
                                                            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                                            val delta = if (item.isScaled) 1.0 else 100.0
                                                            onAdjustItem(item, delta)
                                                        },
                                                    contentAlignment = Alignment.Center
                                                ) {
                                                    Icon(
                                                        imageVector = Icons.Rounded.Add,
                                                        contentDescription = "Increase",
                                                        tint = Color.White,
                                                        modifier = Modifier.size(11.dp)
                                                    )
                                                }
                                            }
                                        }
                                    }
                                }

                                // Progress bar for percentage of section if applicable
                                if (item.percentageOfSection > 0) {
                                    Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        Box(
                                            modifier = Modifier
                                                .weight(1f)
                                                .height(4.dp)
                                                .clip(CircleShape)
                                                .background(Color.White.copy(alpha = 0.08f))
                                        ) {
                                            Box(
                                                modifier = Modifier
                                                    .fillMaxWidth(fraction = item.percentageOfSection.toFloat().coerceIn(0.04f, 1f))
                                                    .fillMaxHeight()
                                                    .clip(CircleShape)
                                                    .background(
                                                        Brush.horizontalGradient(
                                                            listOf(color, color.copy(alpha = 0.65f))
                                                        )
                                                    )
                                            )
                                        }

                                        Text(
                                            text = String.format(java.util.Locale.US, "%.1f%%", item.percentageOfSection * 100),
                                            color = color,
                                            fontSize = 10.sp,
                                            fontWeight = FontWeight.SemiBold
                                        )
                                    }
                                }

                                // Informative notes pills underneath
                                if (item.notes.isNotEmpty()) {
                                    Row(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .horizontalScroll(rememberScrollState()),
                                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                                    ) {
                                        item.notes.forEach { note ->
                                            Box(
                                                modifier = Modifier
                                                    .clip(CircleShape)
                                                    .background(Color.White.copy(alpha = 0.06f))
                                                    .clickable { onSelectItem(item) }
                                                    .padding(horizontal = 7.dp, vertical = 3.dp)
                                            ) {
                                                Text(
                                                    text = note,
                                                    color = ThemeColors.fgMutedDark,
                                                    fontSize = 10.sp,
                                                    fontWeight = FontWeight.Medium
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private fun getSectionStyle(sectionName: String): Triple<ImageVector, Color, String> {
    return when (sectionName.lowercase()) {
        "incoming" -> Triple(Icons.Rounded.ArrowDownward, ThemeColors.accentPurple, "Incoming")
        "outgoing" -> Triple(Icons.Rounded.ArrowUpward, ThemeColors.accentOrange, "Outgoing")
        "deposit" -> Triple(Icons.Rounded.Savings, ThemeColors.accentGreen, "Deposit")
        "balance" -> Triple(Icons.Rounded.Balance, ThemeColors.accentCyan, "Balance")
        "dentist" -> Triple(Icons.Rounded.MedicalServices, ThemeColors.accentPink, "Dentist")
        else -> Triple(Icons.Rounded.Balance, ThemeColors.accentCyan, sectionName)
    }
}
