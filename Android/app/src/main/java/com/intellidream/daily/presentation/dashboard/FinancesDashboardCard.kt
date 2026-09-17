package com.intellidream.daily.presentation.dashboard

import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.rounded.TrendingUp
import androidx.compose.material.icons.rounded.AccountBalanceWallet
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.database.FinanceDataRepository
import com.intellidream.daily.database.SmartLedgerRepository
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.DashboardWidgetSize
import com.intellidream.daily.model.MacroIndicator
import com.intellidream.daily.model.ParsedSmartLedger
import com.intellidream.daily.model.SmartLedgerItem
import com.intellidream.daily.model.StockQuote
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.util.Locale

@Composable
fun FinancesDashboardCard(
    size: DashboardWidgetSize,
    smartLedgerRepository: SmartLedgerRepository,
    financeDataRepository: FinanceDataRepository,
    onOpenHub: () -> Unit,
    onLongClick: (() -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    val ledger by smartLedgerRepository.parsedLedger.collectAsState()
    val macroIndicators by financeDataRepository.macroIndicators.collectAsState()
    val watchlistQuotes by financeDataRepository.watchlistQuotes.collectAsState()

    val cardHeight = when (size) {
        DashboardWidgetSize.Small -> 155.dp
        DashboardWidgetSize.Wide -> 160.dp
        DashboardWidgetSize.Tall -> 324.dp
        DashboardWidgetSize.Large -> 324.dp
    }

    GlassCard(
        modifier = modifier
            .fillMaxWidth()
            .height(cardHeight),
        cornerRadius = 20.dp,
        padding = if (size == DashboardWidgetSize.Small) 12.dp else 16.dp,
        onClick = onOpenHub,
        onLongClick = onLongClick
    ) {
        when (size) {
            DashboardWidgetSize.Small -> SmallFinancesContent(ledger)
            DashboardWidgetSize.Wide -> WideFinancesContent(ledger)
            DashboardWidgetSize.Tall -> TallFinancesContent(ledger, macroIndicators)
            DashboardWidgetSize.Large -> LargeFinancesContent(ledger, macroIndicators, watchlistQuotes)
        }
    }
}

// MARK: - 1x1 Small Compact Net Worth Glance
@Composable
private fun SmallFinancesContent(ledger: ParsedSmartLedger) {
    val cardAmount = getAccountAmount(ledger, "Card")
    val cashAmount = getAccountAmount(ledger, "Cash")

    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        // Header
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = Icons.Rounded.AccountBalanceWallet,
                    contentDescription = null,
                    tint = ThemeColors.accentGreen,
                    modifier = Modifier.size(14.dp)
                )
                Text(
                    text = "Money",
                    color = ThemeColors.accentGreen,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }

            // EUR Pill
            Box(
                modifier = Modifier
                    .clip(CircleShape)
                    .background(ThemeColors.accentCyan.copy(alpha = 0.15f))
                    .padding(horizontal = 6.dp, vertical = 2.dp)
            ) {
                Text(
                    text = ledger.formattedNetWorthEUR,
                    color = ThemeColors.accentCyan,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold
                )
            }
        }

        // Net Worth
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                text = "NET WORTH",
                color = ThemeColors.fgMutedDark,
                fontSize = 9.sp,
                fontWeight = FontWeight.Bold
            )
            Text(
                text = formatCompactLei(ledger.netWorth),
                color = Color.White,
                fontSize = 22.sp,
                fontWeight = FontWeight.Bold
            )
        }

        // Liquidity Footer
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(3.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(
                    modifier = Modifier
                        .size(4.dp)
                        .clip(CircleShape)
                        .background(ThemeColors.accentCyan)
                )
                Text(
                    text = "Crd ${formatCompactNumber(cardAmount)}",
                    color = ThemeColors.accentCyan,
                    fontSize = 9.5.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }

            Text(
                text = "·",
                color = Color.White.copy(alpha = 0.3f),
                fontSize = 9.sp
            )

            Row(
                horizontalArrangement = Arrangement.spacedBy(3.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(
                    modifier = Modifier
                        .size(4.dp)
                        .clip(CircleShape)
                        .background(ThemeColors.accentGreen)
                )
                Text(
                    text = "Csh ${formatCompactNumber(cashAmount)}",
                    color = ThemeColors.accentGreen,
                    fontSize = 9.5.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }
    }
}

// MARK: - 2x1 Wide Standard 3-Column Split
@Composable
private fun WideFinancesContent(ledger: ParsedSmartLedger) {
    val cardAmount = getAccountAmount(ledger, "Card")
    val cashAmount = getAccountAmount(ledger, "Cash")

    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        // Header
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = Icons.Rounded.AccountBalanceWallet,
                    contentDescription = null,
                    tint = ThemeColors.accentGreen,
                    modifier = Modifier.size(16.dp)
                )
                Text(
                    text = "Finances & Money",
                    color = ThemeColors.accentGreen,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }

            Row(
                horizontalArrangement = Arrangement.spacedBy(2.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Open Hub",
                    color = ThemeColors.accentGreen,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold
                )
                Icon(
                    imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                    contentDescription = null,
                    tint = ThemeColors.accentGreen,
                    modifier = Modifier.size(14.dp)
                )
            }
        }

        // 3 Columns: Net Worth | Monthly Flow | Deposits & Liquid
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Col 1: Net Worth
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                Text(
                    text = "NET WORTH",
                    color = ThemeColors.fgMutedDark,
                    fontSize = 9.sp,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = ledger.formattedBadge(ledger.netWorth),
                    color = Color.White,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1
                )
                Text(
                    text = ledger.formattedNetWorthEUR,
                    color = ThemeColors.accentCyan,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }

            VerticalDivider(
                modifier = Modifier
                    .height(38.dp)
                    .padding(horizontal = 8.dp),
                color = Color.White.copy(alpha = 0.15f)
            )

            // Col 2: Monthly Flow
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                Text(
                    text = "MONTHLY FLOW",
                    color = ThemeColors.fgMutedDark,
                    fontSize = 9.sp,
                    fontWeight = FontWeight.Bold
                )
                Row(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("In", color = ThemeColors.fgMutedDark, fontSize = 10.sp)
                    Text(
                        text = formatCompactLei(ledger.incomingTotal),
                        color = ThemeColors.accentGreen,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
                Row(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("Out", color = ThemeColors.fgMutedDark, fontSize = 10.sp)
                    Text(
                        text = formatCompactLei(ledger.outgoingTotal),
                        color = ThemeColors.accentPink,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
            }

            VerticalDivider(
                modifier = Modifier
                    .height(38.dp)
                    .padding(horizontal = 8.dp),
                color = Color.White.copy(alpha = 0.15f)
            )

            // Col 3: Deposits & Liquid
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                Text(
                    text = "DEPOSITS & LIQUID",
                    color = ThemeColors.fgMutedDark,
                    fontSize = 9.sp,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = ledger.formattedBadge(ledger.depositTotal),
                    color = ThemeColors.accentPurple,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1
                )
                Text(
                    text = "Crd ${formatCompactNumber(cardAmount)} · Csh ${formatCompactNumber(cashAmount)}",
                    color = ThemeColors.fgMutedDark,
                    fontSize = 10.sp,
                    maxLines = 1
                )
            }
        }
    }
}

// MARK: - 1x2 Tall Vertical 50/50 Split
@Composable
private fun TallFinancesContent(ledger: ParsedSmartLedger, macroIndicators: List<MacroIndicator>) {
    val cardAmount = getAccountAmount(ledger, "Card")
    val topOutgoing = getTopOutgoing(ledger)

    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        // Header
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = Icons.Rounded.AccountBalanceWallet,
                    contentDescription = null,
                    tint = ThemeColors.accentGreen,
                    modifier = Modifier.size(15.dp)
                )
                Text(
                    text = "Finances",
                    color = ThemeColors.accentGreen,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }
            Icon(
                imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                contentDescription = null,
                tint = ThemeColors.accentGreen,
                modifier = Modifier.size(14.dp)
            )
        }

        // Top: Net Worth Card
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                text = "NET WORTH",
                color = ThemeColors.fgMutedDark,
                fontSize = 9.sp,
                fontWeight = FontWeight.Bold
            )
            Text(
                text = ledger.formattedBadge(ledger.netWorth),
                color = Color.White,
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold
            )
            Text(
                text = ledger.formattedNetWorthEUR,
                color = ThemeColors.accentCyan,
                fontSize = 11.sp,
                fontWeight = FontWeight.SemiBold
            )
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.padding(top = 2.dp)
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text("Dep", color = ThemeColors.fgMutedDark, fontSize = 9.sp)
                    Text(
                        text = formatCompactLei(ledger.depositTotal),
                        color = ThemeColors.accentPurple,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
                Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text("Crd", color = ThemeColors.fgMutedDark, fontSize = 9.sp)
                    Text(
                        text = formatCompactLei(cardAmount),
                        color = ThemeColors.accentCyan,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
            }
        }

        HorizontalDivider(color = Color.White.copy(alpha = 0.12f))

        // Middle: Top Outgoing Allocations
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                text = "TOP OUTGOING",
                color = ThemeColors.fgMutedDark,
                fontSize = 9.sp,
                fontWeight = FontWeight.Bold
            )
            topOutgoing.take(2).forEach { item ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = item.displayName,
                        color = Color.White,
                        fontSize = 11.sp,
                        maxLines = 1,
                        modifier = Modifier.weight(1f, fill = false)
                    )
                    Text(
                        text = formatCompactLei(item.calculatedAmount),
                        color = ThemeColors.accentPink,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
            }
        }

        HorizontalDivider(color = Color.White.copy(alpha = 0.12f))

        // Bottom: Global Macro Pulse (Top 3)
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                text = "GLOBAL PULSE",
                color = ThemeColors.fgMutedDark,
                fontSize = 9.sp,
                fontWeight = FontWeight.Bold
            )
            macroIndicators.take(3).forEach { indicator ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(indicator.emoji, fontSize = 10.sp)
                        Text(
                            text = indicator.name,
                            color = Color.White,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Medium,
                            maxLines = 1
                        )
                    }
                    Text(
                        text = indicator.formattedChangePercent,
                        color = if (indicator.isPositive) ThemeColors.accentGreen else ThemeColors.accentPink,
                        fontSize = 9.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
            }
        }
    }
}

// MARK: - 2x2 Large Executive Multi-Panel Hub
@Composable
private fun LargeFinancesContent(
    ledger: ParsedSmartLedger,
    macroIndicators: List<MacroIndicator>,
    watchlistQuotes: List<StockQuote>
) {
    val cardAmount = getAccountAmount(ledger, "Card")
    val cashAmount = getAccountAmount(ledger, "Cash")
    val topOutgoing = getTopOutgoing(ledger)

    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        // Header
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = Icons.AutoMirrored.Rounded.TrendingUp,
                    contentDescription = null,
                    tint = ThemeColors.accentGreen,
                    modifier = Modifier.size(16.dp)
                )
                Text(
                    text = "Finances & Markets",
                    color = ThemeColors.accentGreen,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }

            Row(
                horizontalArrangement = Arrangement.spacedBy(2.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Open Hub",
                    color = ThemeColors.accentGreen,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold
                )
                Icon(
                    imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                    contentDescription = null,
                    tint = ThemeColors.accentGreen,
                    modifier = Modifier.size(14.dp)
                )
            }
        }

        // Upper Panel: Net Worth + Liquid Breakdown
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    text = "NET WORTH",
                    color = ThemeColors.fgMutedDark,
                    fontSize = 9.sp,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = ledger.formattedNetWorth,
                    color = Color.White,
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1
                )
                Text(
                    text = ledger.formattedNetWorthEUR,
                    color = ThemeColors.accentCyan,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold
                )
            }

            Column(
                horizontalAlignment = Alignment.End,
                verticalArrangement = Arrangement.spacedBy(3.dp)
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("Deposits", color = ThemeColors.fgMutedDark, fontSize = 11.sp)
                    Text(
                        text = ledger.formattedBadge(ledger.depositTotal),
                        color = ThemeColors.accentPurple,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("Flow", color = ThemeColors.fgMutedDark, fontSize = 11.sp)
                    Text(
                        text = "${formatCompactNumber(ledger.incomingTotal)} / ${formatCompactNumber(ledger.outgoingTotal)} Lei",
                        color = Color.White,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("Liquid", color = ThemeColors.fgMutedDark, fontSize = 11.sp)
                    Text(
                        text = "${formatCompactNumber(cardAmount)} / ${formatCompactNumber(cashAmount)} Lei",
                        color = ThemeColors.accentCyan,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
            }
        }

        HorizontalDivider(color = Color.White.copy(alpha = 0.12f))

        // Middle Section: Outgoing Allocations (Top 3)
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "KEY OUTGOING ALLOCATIONS",
                    color = ThemeColors.fgMutedDark,
                    fontSize = 9.sp,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = "Total ${ledger.formattedBadge(ledger.outgoingTotal)}",
                    color = ThemeColors.accentPink,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                topOutgoing.take(3).forEach { item ->
                    Box(
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(Color.White.copy(alpha = 0.06f))
                            .border(1.dp, Color.White.copy(alpha = 0.08f), CircleShape)
                            .padding(horizontal = 8.dp, vertical = 3.dp)
                    ) {
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(4.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                text = cleanPillName(item.displayName),
                                color = Color.White,
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Medium,
                                maxLines = 1
                            )
                            Text(
                                text = formatCompactNumber(item.calculatedAmount),
                                color = ThemeColors.accentPink,
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold
                            )
                        }
                    }
                }
            }
        }

        HorizontalDivider(color = Color.White.copy(alpha = 0.12f))

        // Bottom: 2-Column Split (Watchlist on Left | Global Pulse on Right)
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            // Watchlist
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Text(
                    text = "WATCHLIST",
                    color = ThemeColors.fgMutedDark,
                    fontSize = 9.sp,
                    fontWeight = FontWeight.Bold
                )
                watchlistQuotes.take(3).forEach { quote ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = quote.symbol,
                            color = Color.White,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold
                        )
                        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(
                                text = quote.formattedPrice,
                                color = Color.White.copy(alpha = 0.8f),
                                fontSize = 10.sp
                            )
                            Text(
                                text = quote.formattedChangePercent,
                                color = if (quote.isPositive) ThemeColors.accentGreen else ThemeColors.accentPink,
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold
                            )
                        }
                    }
                }
            }

            VerticalDivider(
                modifier = Modifier
                    .height(60.dp)
                    .padding(horizontal = 8.dp),
                color = Color.White.copy(alpha = 0.12f)
            )

            // Global Pulse
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Text(
                    text = "GLOBAL PULSE",
                    color = ThemeColors.fgMutedDark,
                    fontSize = 9.sp,
                    fontWeight = FontWeight.Bold
                )
                macroIndicators.take(3).forEach { indicator ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(3.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(indicator.emoji, fontSize = 10.sp)
                            Text(
                                text = indicator.name.take(10),
                                color = Color.White,
                                fontSize = 10.sp,
                                maxLines = 1
                            )
                        }
                        Text(
                            text = indicator.formattedChangePercent,
                            color = if (indicator.isPositive) ThemeColors.accentGreen else ThemeColors.accentPink,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Helper calculation functions
private fun getAccountAmount(ledger: ParsedSmartLedger, name: String): Double {
    val inc = ledger.sections.firstOrNull { it.name.equals("Incoming", ignoreCase = true) } ?: return 0.0
    val item = inc.items.firstOrNull { it.key.equals(name, ignoreCase = true) } ?: return 0.0
    return item.calculatedAmount
}

private fun getTopOutgoing(ledger: ParsedSmartLedger): List<SmartLedgerItem> {
    val out = ledger.sections.firstOrNull { it.name.equals("Outgoing", ignoreCase = true) } ?: return emptyList()
    return out.items
        .filter { !it.isPureNote && it.calculatedAmount > 0 }
        .sortedByDescending { it.calculatedAmount }
}

private fun formatCompactLei(amount: Double): String {
    return if (amount >= 1000) {
        val k = amount / 1000.0
        val symbols = DecimalFormatSymbols(Locale.US)
        val formatter = DecimalFormat("#.#", symbols)
        "${formatter.format(k)}K Lei"
    } else {
        "${amount.toInt()} Lei"
    }
}

private fun formatCompactNumber(amount: Double): String {
    return if (amount >= 1000) {
        val k = amount / 1000.0
        val symbols = DecimalFormatSymbols(Locale.US)
        val formatter = DecimalFormat("#.#", symbols)
        "${formatter.format(k)}K"
    } else {
        "${amount.toInt()}"
    }
}

private fun cleanPillName(displayName: String): String {
    val slashIdx = displayName.indexOf("/")
    return if (slashIdx > 0) displayName.substring(0, slashIdx).trim() else displayName
}
