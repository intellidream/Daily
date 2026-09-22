package com.intellidream.daily.presentation.finances

import androidx.compose.animation.Crossfade
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
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.rounded.TrendingUp
import androidx.compose.material.icons.rounded.AccountBalanceWallet
import androidx.compose.material.icons.rounded.Public
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.database.FinanceDataRepository
import com.intellidream.daily.database.SmartLedgerRepository
import com.intellidream.daily.designsystem.calmBoundedSwipeGesture
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.FinanceSubTab
import com.intellidream.daily.model.SmartLedgerItem

@Composable
fun FinancesMainView(
    smartLedgerRepository: SmartLedgerRepository,
    financeDataRepository: FinanceDataRepository,
    onNavigateBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val activeSubTab by financeDataRepository.activeSubTab.collectAsState()
    val ledger by smartLedgerRepository.parsedLedger.collectAsState()
    val rawText by smartLedgerRepository.rawText.collectAsState()
    val macroIndicators by financeDataRepository.macroIndicators.collectAsState()
    val heatmapData by financeDataRepository.heatmapData.collectAsState()
    val watchlistQuotes by financeDataRepository.watchlistQuotes.collectAsState()

    var showingEditorSheet by remember { mutableStateOf(false) }
    var selectedAdjustItem by remember { mutableStateOf<SmartLedgerItem?>(null) }
    var showingAddItemSheet by remember { mutableStateOf(false) }
    var targetSectionForNewItem by remember { mutableStateOf("Outgoing") }

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(brush = ThemeColors.backgroundGradient)
            .statusBarsPadding()
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            // Header Bar
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp, vertical = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Back Button
                Box(
                    modifier = Modifier
                        .size(38.dp)
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.12f))
                        .border(1.dp, Color.White.copy(alpha = 0.25f), CircleShape)
                        .clickable(onClick = onNavigateBack),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowLeft,
                        contentDescription = "Back",
                        tint = Color.White,
                        modifier = Modifier.size(20.dp)
                    )
                }

                // Sub-Tab Capsule Switcher
                Row(
                    modifier = Modifier
                        .weight(1f)
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.08f))
                        .border(1.dp, Color.White.copy(alpha = 0.15f), CircleShape)
                        .padding(3.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    FinanceSubTab.entries.forEach { tab ->
                        val isSelected = activeSubTab == tab
                        val icon = when (tab) {
                            FinanceSubTab.World -> Icons.Rounded.Public
                            FinanceSubTab.Stocks -> Icons.AutoMirrored.Rounded.TrendingUp
                            FinanceSubTab.Money -> Icons.Rounded.AccountBalanceWallet
                        }

                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .clip(CircleShape)
                                .background(
                                    if (isSelected) {
                                        Brush.linearGradient(
                                            listOf(
                                                ThemeColors.accentGreen.copy(alpha = 0.70f),
                                                ThemeColors.accentGreen.copy(alpha = 0.40f)
                                            )
                                        )
                                    } else Brush.linearGradient(listOf(Color.Transparent, Color.Transparent))
                                )
                                .then(
                                    if (isSelected) {
                                        Modifier.border(1.dp, Color.White.copy(alpha = 0.35f), CircleShape)
                                    } else Modifier
                                )
                                .clickable { financeDataRepository.setActiveSubTab(tab) }
                                .padding(vertical = 8.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Row(
                                horizontalArrangement = Arrangement.spacedBy(4.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(
                                    imageVector = icon,
                                    contentDescription = null,
                                    tint = if (isSelected) Color.White else ThemeColors.fgMutedDark,
                                    modifier = Modifier.size(13.dp)
                                )
                                Text(
                                    text = tab.title,
                                    color = if (isSelected) Color.White else ThemeColors.fgMutedDark,
                                    fontSize = 13.sp,
                                    fontWeight = FontWeight.SemiBold
                                )
                            }
                        }
                    }
                }
            }

            val tabs = FinanceSubTab.entries
            val currentTabIndex = tabs.indexOf(activeSubTab)

            // Scrollable Content
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .calmBoundedSwipeGesture(
                        currentIndex = currentTabIndex,
                        maxIndex = tabs.lastIndex,
                        onIndexChange = { newIdx ->
                            if (newIdx in tabs.indices) {
                                financeDataRepository.setActiveSubTab(tabs[newIdx])
                            }
                        }
                    )
                    .padding(horizontal = 20.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                item {
                    Spacer(modifier = Modifier.height(4.dp))
                }

                item {
                    Crossfade(targetState = activeSubTab, label = "financeSubTabTransition") { tab ->
                        when (tab) {
                            FinanceSubTab.World -> {
                                WorldSectionView(
                                    macroIndicators = macroIndicators,
                                    heatmapData = heatmapData
                                )
                            }
                            FinanceSubTab.Stocks -> {
                                StocksSectionView(
                                    quotes = watchlistQuotes
                                )
                            }
                            FinanceSubTab.Money -> {
                                MoneySectionView(
                                    ledger = ledger,
                                    onOpenEditor = { showingEditorSheet = true },
                                    onSelectItem = { selectedAdjustItem = it },
                                    onAddItem = { sec ->
                                        targetSectionForNewItem = sec
                                        showingAddItemSheet = true
                                    },
                                    onAdjustItem = { item, delta ->
                                        smartLedgerRepository.adjustItem(item.lineIndex, delta)
                                    }
                                )
                            }
                        }
                    }
                }

                item {
                    Spacer(modifier = Modifier.height(110.dp)) // Clearance for bottom floating capsule
                }
            }
        }

        // Sheets
        if (showingEditorSheet) {
            SmartLedgerEditorSheet(
                initialText = rawText,
                onSave = { smartLedgerRepository.saveLedgerText(it) },
                onDismiss = { showingEditorSheet = false }
            )
        }

        selectedAdjustItem?.let { item ->
            SmartLedgerQuickAdjustSheet(
                item = item,
                onSaveAmount = { newRaw ->
                    smartLedgerRepository.setItemAmount(item.lineIndex, newRaw)
                },
                onDelete = {
                    smartLedgerRepository.deleteItem(item.lineIndex)
                },
                onDismiss = { selectedAdjustItem = null }
            )
        }

        if (showingAddItemSheet) {
            AddLedgerItemSheet(
                defaultSectionName = targetSectionForNewItem,
                onAddItem = { sec, key, amount, note ->
                    smartLedgerRepository.addItem(sec, key, amount, note)
                },
                onDismiss = { showingAddItemSheet = false }
            )
        }
    }
}
