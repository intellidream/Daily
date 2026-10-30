package com.intellidream.daily.wearos.presentation.orbit

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
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
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Remove
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.Text
import com.intellidream.daily.wearos.data.WatchSmartLedgerRepository
import com.intellidream.daily.wearos.data.WearLedgerItemData
import kotlinx.coroutines.launch

@Composable
fun SmartLedgerCard(
    modifier: Modifier = Modifier,
    isPageActive: Boolean = true
) {
    val context = LocalContext.current
    val repository = remember { WatchSmartLedgerRepository.getInstance(context) }
    val scope = rememberCoroutineScope()

    val parsed by repository.parsed.collectAsState()
    val isSyncing by repository.isSyncing.collectAsState()

    // Battery & CPU optimization: sync only when Orbit page is active and cache is stale (> 10m old)
    LaunchedEffect(isPageActive) {
        if (isPageActive) {
            repository.syncWithSupabase(force = false)
        }
    }

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

            if (isSyncing) {
                CircularProgressIndicator(
                    modifier = Modifier.size(11.dp),
                    strokeWidth = 1.5.dp,
                    indicatorColor = Color(0xFF10B981)
                )
            }
        }

        Spacer(modifier = Modifier.height(6.dp))

        // Net worth line
        Text(
            text = parsed.netWorthFormatted,
            fontSize = 15.sp,
            fontWeight = FontWeight.Bold,
            color = Color.White
        )
        Text(
            text = parsed.netWorthEURFormatted,
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold,
            color = Color(0xFF34D399)
        )

        Spacer(modifier = Modifier.height(6.dp))

        // Chips: Deposits & Balance
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
                    Text(text = "DEPOSITS", fontSize = 7.sp, fontWeight = FontWeight.Bold, color = Color(0xFF10B981))
                    Text(
                        text = parsed.depositsFormatted,
                        fontSize = 9.sp,
                        fontWeight = FontWeight.Bold,
                        fontFamily = FontFamily.Monospace,
                        color = Color.White
                    )
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
                    Text(text = "BALANCE", fontSize = 7.sp, fontWeight = FontWeight.Bold, color = Color(0xFF00E5FF))
                    Text(
                        text = parsed.balanceFormatted,
                        fontSize = 9.sp,
                        fontWeight = FontWeight.Bold,
                        fontFamily = FontFamily.Monospace,
                        color = Color.White
                    )
                }
            }
        }

        if (parsed.items.isNotEmpty()) {
            Spacer(modifier = Modifier.height(8.dp))

            Text(
                text = "QUICK ADJUST (1-TAP)",
                fontSize = 8.sp,
                fontWeight = FontWeight.Bold,
                color = Color(0xFF94A3B8)
            )

            Spacer(modifier = Modifier.height(4.dp))

            // Dynamic quick items from smart ledger Outgoing section
            parsed.items.take(4).forEach { item ->
                QuickItemRow(
                    item = item,
                    onMinus = {
                        val step = if (item.isScaled) 1.0 else 50.0
                        repository.adjustItem(item.lineIndex, -step)
                    },
                    onPlus = {
                        val step = if (item.isScaled) 1.0 else 50.0
                        repository.adjustItem(item.lineIndex, step)
                    }
                )
                Spacer(modifier = Modifier.height(4.dp))
            }
        }
    }
}


@Composable
private fun QuickItemRow(
    item: WearLedgerItemData,
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
