package com.intellidream.daily.presentation.news

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.BlindspotType
import com.intellidream.daily.model.MediaDietSnapshot

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MediaDietSheet(
    snapshot: MediaDietSnapshot,
    onDismiss: () -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Color(0xFF0E1729),
        contentColor = Color.White,
        shape = RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Column {
                    Text(
                        text = "Personal Media Diet",
                        color = Color.White,
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        text = "${snapshot.yearMonth} · ${snapshot.balanceSummaryLabel}",
                        color = ThemeColors.accentCyan,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                }
                IconButton(onClick = onDismiss) {
                    Icon(
                        imageVector = Icons.Rounded.Close,
                        contentDescription = "Close",
                        tint = ThemeColors.textMuted
                    )
                }
            }

            // Spectrum Balance Bar
            BiasSpectrumBar(
                distribution = snapshot.distribution,
                blindspot = BlindspotType.None,
                uniqueOutlets = snapshot.totalArticlesRead,
                compact = false
            )

            // 2x2 KPI Grid
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                DietMetricTile(
                    modifier = Modifier.weight(1f),
                    title = "Articles Read",
                    value = "${snapshot.totalArticlesRead}",
                    subtitle = "In ${snapshot.yearMonth}",
                    accent = ThemeColors.accentCyan
                )
                DietMetricTile(
                    modifier = Modifier.weight(1f),
                    title = "High Factuality",
                    value = "${snapshot.highFactualityPercent}%",
                    subtitle = "High & Very High sources",
                    accent = PerspectivesPalette.factHighEmerald
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                DietMetricTile(
                    modifier = Modifier.weight(1f),
                    title = "Independent Media",
                    value = "${snapshot.independentOwnershipPercent}%",
                    subtitle = "Reader & non-profit funded",
                    accent = PerspectivesPalette.independentPurple
                )
                DietMetricTile(
                    modifier = Modifier.weight(1f),
                    title = "Blindspots Read",
                    value = "${snapshot.blindspotsRead}",
                    subtitle = "Cross-spectrum stories",
                    accent = PerspectivesPalette.blindspotAmber
                )
            }
        }
    }
}

@Composable
private fun DietMetricTile(
    modifier: Modifier = Modifier,
    title: String,
    value: String,
    subtitle: String,
    accent: Color
) {
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(16.dp))
            .background(Color.White.copy(alpha = 0.05f))
            .border(1.dp, accent.copy(alpha = 0.25f), RoundedCornerShape(16.dp))
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Text(
            text = title,
            color = ThemeColors.textMuted,
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold
        )
        Text(
            text = value,
            color = accent,
            fontSize = 22.sp,
            fontWeight = FontWeight.ExtraBold
        )
        Text(
            text = subtitle,
            color = ThemeColors.textSecondary,
            fontSize = 11.sp
        )
    }
}
