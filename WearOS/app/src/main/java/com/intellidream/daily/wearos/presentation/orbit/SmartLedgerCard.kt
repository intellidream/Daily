package com.intellidream.daily.wearos.presentation.orbit

import android.content.Context
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.Remove
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.Text

data class WearLedgerQuickItem(
    val id: String,
    val name: String,
    val count: Double,
    val unitPrice: Double,
    val isScaled: Boolean,
    val currency: String = "Lei"
) {
    val totalAmount: Double get() = if (isScaled) count * unitPrice else count
    val displayAmount: String get() {
        return if (totalAmount % 1 == 0.0) "${totalAmount.toInt()} $currency" else String.format("%.1f %s", totalAmount, currency)
    }
    val subtitle: String get() {
        return if (isScaled) {
            val countStr = if (count % 1 == 0.0) "${count.toInt()}" else String.format("%.1f", count)
            "$countStr × ${unitPrice.toInt()} Lei"
        } else "Fix / Lunar"
    }
}

@Composable
fun SmartLedgerCard(
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val prefs = remember { context.getSharedPreferences("daily_prefs", Context.MODE_PRIVATE) }

    var netWorth by remember { mutableStateOf(prefs.getString("ledger_net_worth", "128.450 Lei") ?: "128.450 Lei") }
    var netWorthEUR by remember { mutableStateOf(prefs.getString("ledger_net_worth_eur", "~25.690 €") ?: "~25.690 €") }
    var deposits by remember { mutableStateOf(prefs.getString("ledger_deposits", "74.000 Lei") ?: "74.000 Lei") }
    var sold by remember { mutableStateOf(prefs.getString("ledger_sold", "53.156 Lei") ?: "53.156 Lei") }

    var tigariCount by remember { mutableStateOf(prefs.getFloat("ledger_tigari_count", 10.0f).toDouble()) }
    var coraCount by remember { mutableStateOf(prefs.getFloat("ledger_cora_count", 1.0f).toDouble()) }
    var carAmount by remember { mutableStateOf(prefs.getFloat("ledger_car_amount", 500.0f).toDouble()) }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(Color(0xFF0F2018))
            .border(1.dp, Color(0xFF10B981).copy(alpha = 0.35f), RoundedCornerShape(14.dp))
            .padding(10.dp)
    ) {
        // Header
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = Icons.Default.CreditCard,
                    contentDescription = null,
                    tint = Color(0xFF10B981),
                    modifier = Modifier.size(12.dp)
                )
                Spacer(modifier = Modifier.width(4.dp))
                Text(
                    text = "SMART LEDGER",
                    fontSize = 9.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color(0xFF10B981)
                )
            }
        }

        Spacer(modifier = Modifier.height(6.dp))

        // Net worth line
        Text(
            text = netWorth,
            fontSize = 15.sp,
            fontWeight = FontWeight.Bold,
            color = Color.White
        )
        Text(
            text = netWorthEUR,
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold,
            color = Color(0xFF34D399)
        )

        Spacer(modifier = Modifier.height(6.dp))

        // Chips: Depozite & Sold
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Box(
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(8.dp))
                    .background(Color(0x2610B981))
                    .padding(horizontal = 6.dp, vertical = 4.dp)
            ) {
                Column {
                    Text(text = "DEPOZITE", fontSize = 7.sp, fontWeight = FontWeight.Bold, color = Color(0xFF10B981))
                    Text(text = deposits, fontSize = 9.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace, color = Color.White)
                }
            }

            Box(
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(8.dp))
                    .background(Color(0x2600E5FF))
                    .padding(horizontal = 6.dp, vertical = 4.dp)
            ) {
                Column {
                    Text(text = "SOLD", fontSize = 7.sp, fontWeight = FontWeight.Bold, color = Color(0xFF00E5FF))
                    Text(text = sold, fontSize = 9.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace, color = Color.White)
                }
            }
        }

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = "QUICK ADJUST (1-TAP)",
            fontSize = 8.sp,
            fontWeight = FontWeight.Bold,
            color = Color(0xFF94A3B8)
        )

        Spacer(modifier = Modifier.height(4.dp))

        // Item 1: Tigari
        QuickItemRow(
            item = WearLedgerQuickItem("tigari", "Țigări", tigariCount, 26.50, true),
            onMinus = {
                tigariCount = maxOf(0.0, tigariCount - 1.0)
                prefs.edit().putFloat("ledger_tigari_count", tigariCount.toFloat()).apply()
            },
            onPlus = {
                tigariCount += 1.0
                prefs.edit().putFloat("ledger_tigari_count", tigariCount.toFloat()).apply()
            }
        )

        Spacer(modifier = Modifier.height(4.dp))

        // Item 2: Cora
        QuickItemRow(
            item = WearLedgerQuickItem("cora", "Cora / Market", coraCount, 150.0, true),
            onMinus = {
                coraCount = maxOf(0.0, coraCount - 1.0)
                prefs.edit().putFloat("ledger_cora_count", coraCount.toFloat()).apply()
            },
            onPlus = {
                coraCount += 1.0
                prefs.edit().putFloat("ledger_cora_count", coraCount.toFloat()).apply()
            }
        )

        Spacer(modifier = Modifier.height(4.dp))

        // Item 3: Car
        QuickItemRow(
            item = WearLedgerQuickItem("car", "Benzină / Mașină", carAmount, 1.0, false),
            onMinus = {
                carAmount = maxOf(0.0, carAmount - 50.0)
                prefs.edit().putFloat("ledger_car_amount", carAmount.toFloat()).apply()
            },
            onPlus = {
                carAmount += 50.0
                prefs.edit().putFloat("ledger_car_amount", carAmount.toFloat()).apply()
            }
        )
    }
}

@Composable
private fun QuickItemRow(
    item: WearLedgerQuickItem,
    onMinus: () -> Unit,
    onPlus: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(Color(0x0FFFFFFF))
            .padding(horizontal = 6.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(text = item.name, fontSize = 10.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
            Text(text = item.subtitle, fontSize = 8.sp, color = Color(0xFF94A3B8))
        }

        Text(
            text = item.displayAmount,
            fontSize = 10.sp,
            fontWeight = FontWeight.Bold,
            fontFamily = FontFamily.Monospace,
            color = Color(0xFF34D399),
            modifier = Modifier.padding(end = 4.dp)
        )

        Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            Box(
                modifier = Modifier
                    .size(22.dp)
                    .clip(CircleShape)
                    .background(Color(0x26FFFFFF))
                    .clickable { onMinus() },
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.Remove,
                    contentDescription = "Minus",
                    tint = Color.White,
                    modifier = Modifier.size(10.dp)
                )
            }

            Box(
                modifier = Modifier
                    .size(22.dp)
                    .clip(CircleShape)
                    .background(Color(0x4010B981))
                    .clickable { onPlus() },
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.Add,
                    contentDescription = "Plus",
                    tint = Color.White,
                    modifier = Modifier.size(10.dp)
                )
            }
        }
    }
}
