package com.intellidream.daily.presentation.news

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Public
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.database.NewsRepository
import com.intellidream.daily.designsystem.DailyAsyncImage
import com.intellidream.daily.designsystem.DailyLiquidLoadingIndicator
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.MediaBias
import com.intellidream.daily.model.MediaOutletProfile
import com.intellidream.daily.model.NewsArticle
import com.intellidream.daily.model.PerspectiveComparison
import com.intellidream.daily.model.StoryCluster
import kotlinx.coroutines.launch

private enum class SpectrumFilter(val label: String) {
    All("All"),
    Left("Left"),
    Center("Center"),
    Right("Right"),
    Independent("Indep.")
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PerspectivesComparisonSheet(
    initialCluster: StoryCluster,
    repository: NewsRepository,
    geminiApiKey: String?,
    onSelectArticle: (NewsArticle) -> Unit,
    onInspectProfile: (MediaOutletProfile) -> Unit,
    onDismiss: () -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Color(0xFF0B1426),
        contentColor = Color.White,
        shape = RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp)
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .fillMaxHeight(0.88f)
        ) {
            PerspectivesComparisonPane(
                initialCluster = initialCluster,
                repository = repository,
                geminiApiKey = geminiApiKey,
                onSelectArticle = { art ->
                    onDismiss()
                    onSelectArticle(art)
                },
                onInspectProfile = onInspectProfile,
                onClose = onDismiss
            )
        }
    }
}

/**
 * Reusable Perspectives comparison pane used both inside [PerspectivesComparisonSheet] on compact phones (`Trapper`)
 * and inline as a side-by-side 38% split column inside `NewsReaderSheet` on unfolded foldables (`RADAR`).
 */
@Composable
fun PerspectivesComparisonPane(
    initialCluster: StoryCluster,
    repository: NewsRepository,
    geminiApiKey: String?,
    onSelectArticle: (NewsArticle) -> Unit,
    onInspectProfile: (MediaOutletProfile) -> Unit,
    onClose: (() -> Unit)? = null
) {
    var activeCluster by remember(initialCluster.id) { mutableStateOf(initialCluster) }
    var comparison by remember(initialCluster.id) { mutableStateOf<PerspectiveComparison?>(null) }
    var isExpanding by remember(initialCluster.id) { mutableStateOf(false) }
    var isComparing by remember(initialCluster.id) { mutableStateOf(true) }
    var selectedFilter by remember { mutableStateOf(SpectrumFilter.All) }
    val scope = rememberCoroutineScope()

    LaunchedEffect(initialCluster.id) {
        isComparing = true
        // Auto-expand cross-spectrum on-demand when fewer than 3 outlets are currently clustered
        if (!activeCluster.isExpandedExternally && activeCluster.uniqueOutletCount < 3) {
            isExpanding = true
            activeCluster = repository.expandClusterCoverage(activeCluster)
            isExpanding = false
        }
        comparison = repository.compareClusterPerspectives(activeCluster, geminiApiKey)
        isComparing = false
    }

    val filteredItems = remember(activeCluster, selectedFilter) {
        when (selectedFilter) {
            SpectrumFilter.All -> activeCluster.items
            SpectrumFilter.Left -> activeCluster.items.filter { it.profile.bias.bucket == MediaBias.SpectrumBucket.Left }
            SpectrumFilter.Center -> activeCluster.items.filter { it.profile.bias.bucket == MediaBias.SpectrumBucket.Center }
            SpectrumFilter.Right -> activeCluster.items.filter { it.profile.bias.bucket == MediaBias.SpectrumBucket.Right }
            SpectrumFilter.Independent -> activeCluster.items.filter {
                it.profile.bias == MediaBias.IndependentCreator || it.profile.ownershipType.isIndependentOrNonProfit
            }
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF0B1426))
            .padding(horizontal = 16.dp, vertical = 10.dp)
    ) {
        // Header Row
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Icon(
                    imageVector = Icons.Rounded.AutoAwesome,
                    contentDescription = null,
                    tint = ThemeColors.accentCyan,
                    modifier = Modifier.size(18.dp)
                )
                Column {
                    Text(
                        text = "Perspectives",
                        color = Color.White,
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        text = "${activeCluster.uniqueOutletCount} distinct sources",
                        color = ThemeColors.textMuted,
                        fontSize = 11.sp
                    )
                }
            }

            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                // On-demand Cross-Spectrum Expansion button
                Row(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(ThemeColors.accentCyan.copy(alpha = 0.14f))
                        .border(0.8.dp, ThemeColors.accentCyan.copy(alpha = 0.35f), CircleShape)
                        .clickable(enabled = !isExpanding) {
                            scope.launch {
                                isExpanding = true
                                activeCluster = repository.expandClusterCoverage(activeCluster, force = true)
                                isExpanding = false
                                isComparing = true
                                comparison = repository.compareClusterPerspectives(activeCluster, geminiApiKey, forceRefresh = true)
                                isComparing = false
                            }
                        }
                        .padding(horizontal = 10.dp, vertical = 5.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Icon(
                        imageVector = if (isExpanding) Icons.Rounded.Refresh else Icons.Rounded.Public,
                        contentDescription = null,
                        tint = ThemeColors.accentCyan,
                        modifier = Modifier.size(12.dp)
                    )
                    Text(
                        text = if (isExpanding) "Expanding..." else "Expand Spectrum",
                        color = ThemeColors.accentCyan,
                        fontSize = 10.5.sp,
                        fontWeight = FontWeight.Bold
                    )
                }

                if (onClose != null) {
                    IconButton(onClick = onClose, modifier = Modifier.size(30.dp)) {
                        Icon(
                            imageVector = Icons.Rounded.Close,
                            contentDescription = "Close",
                            tint = ThemeColors.textMuted,
                            modifier = Modifier.size(18.dp)
                        )
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(10.dp))

        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            contentPadding = PaddingValues(bottom = 28.dp)
        ) {
            item {
                BiasSpectrumBar(
                    distribution = activeCluster.distribution,
                    blindspot = activeCluster.blindspot,
                    uniqueOutlets = activeCluster.uniqueOutletCount,
                    compact = false
                )
            }

            // AI / Deterministic Multi-Perspective Synthesis Card
            item {
                if (isComparing && comparison == null) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 18.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        DailyLiquidLoadingIndicator(
                            color = ThemeColors.accentCyan,
                            size = 36.dp,
                            label = "Synthesizing framing across outlets..."
                        )
                    }
                } else {
                    comparison?.let { comp ->
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(16.dp))
                                .background(Color.White.copy(alpha = 0.05f))
                                .border(1.dp, Color.White.copy(alpha = 0.11f), RoundedCornerShape(16.dp))
                                .padding(14.dp),
                            verticalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.SpaceBetween,
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Text(
                                    text = if (comp.isAiGenerated) "AI Framing Synthesis" else "Spectrum Framing Overview",
                                    color = ThemeColors.accentCyan,
                                    fontSize = 12.sp,
                                    fontWeight = FontWeight.Bold
                                )
                                Text(
                                    text = comp.languageCode.uppercase(),
                                    color = ThemeColors.textMuted,
                                    fontSize = 10.sp,
                                    fontWeight = FontWeight.Bold
                                )
                            }

                            Text(
                                text = comp.summaryText,
                                color = Color.White.copy(alpha = 0.92f),
                                fontSize = 13.sp,
                                lineHeight = 18.5.sp
                            )

                            if (comp.commonFacts.isNotEmpty()) {
                                Text(
                                    text = "Shared Facts",
                                    color = PerspectivesPalette.factHighEmerald,
                                    fontSize = 11.5.sp,
                                    fontWeight = FontWeight.Bold
                                )
                                comp.commonFacts.forEach { fact ->
                                    Text(
                                        text = "• $fact",
                                        color = ThemeColors.textSecondary,
                                        fontSize = 12.sp,
                                        lineHeight = 17.sp
                                    )
                                }
                            }

                            if (comp.framingDifferences.isNotEmpty()) {
                                Text(
                                    text = "How Coverage Differs",
                                    color = Color(0xFFC084FC),
                                    fontSize = 11.5.sp,
                                    fontWeight = FontWeight.Bold
                                )
                                comp.framingDifferences.forEach { diff ->
                                    Column(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .clip(RoundedCornerShape(10.dp))
                                            .background(Color.White.copy(alpha = 0.04f))
                                            .padding(8.dp),
                                        verticalArrangement = Arrangement.spacedBy(2.dp)
                                    ) {
                                        Text(
                                            text = diff.perspectiveLabel,
                                            color = Color.White,
                                            fontSize = 11.sp,
                                            fontWeight = FontWeight.Bold
                                        )
                                        Text(
                                            text = diff.angle,
                                            color = ThemeColors.textSecondary,
                                            fontSize = 12.sp,
                                            lineHeight = 16.5.sp
                                        )
                                    }
                                }
                            }

                            if (comp.omissions.isNotEmpty()) {
                                Text(
                                    text = "Blindspots & Nuances",
                                    color = PerspectivesPalette.blindspotAmber,
                                    fontSize = 11.5.sp,
                                    fontWeight = FontWeight.Bold
                                )
                                comp.omissions.forEach { om ->
                                    Text(
                                        text = "• $om",
                                        color = ThemeColors.textSecondary,
                                        fontSize = 12.sp,
                                        lineHeight = 17.sp
                                    )
                                }
                            }
                        }
                    }
                }
            }

            // Spectrum Filter Chips
            item {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    SpectrumFilter.entries.forEach { filter ->
                        val selected = selectedFilter == filter
                        Box(
                            modifier = Modifier
                                .clip(CircleShape)
                                .background(if (selected) ThemeColors.accentCyan.copy(alpha = 0.20f) else Color.White.copy(alpha = 0.06f))
                                .border(
                                    width = 0.8.dp,
                                    color = if (selected) ThemeColors.accentCyan else Color.White.copy(alpha = 0.12f),
                                    shape = CircleShape
                                )
                                .clickable { selectedFilter = filter }
                                .padding(horizontal = 12.dp, vertical = 6.dp)
                        ) {
                            Text(
                                text = filter.label,
                                color = if (selected) Color.White else ThemeColors.textMuted,
                                fontSize = 11.5.sp,
                                fontWeight = FontWeight.SemiBold
                            )
                        }
                    }
                }
            }

            // Coverage Items List
            items(filteredItems, key = { it.article.link }) { cov ->
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(14.dp))
                        .background(Color.White.copy(alpha = 0.05f))
                        .border(0.8.dp, Color.White.copy(alpha = 0.10f), RoundedCornerShape(14.dp))
                        .clickable { onSelectArticle(cov.article) }
                        .padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        if (!cov.article.publicationIconUrl.isNullOrBlank()) {
                            DailyAsyncImage(
                                url = cov.article.publicationIconUrl,
                                contentDescription = null,
                                modifier = Modifier
                                    .size(15.dp)
                                    .clip(CircleShape),
                                contentScale = ContentScale.Crop
                            )
                        }
                        Text(
                            text = cov.profile.name,
                            color = ThemeColors.accentCyan,
                            fontSize = 11.5.sp,
                            fontWeight = FontWeight.Bold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier
                                .weight(1f, fill = false)
                                .clickable { onInspectProfile(cov.profile) }
                        )
                        OutletMicroBadge(
                            profile = cov.profile,
                            framing = cov.framing,
                            onClick = { onInspectProfile(cov.profile) }
                        )
                    }

                    Text(
                        text = cov.article.title,
                        color = Color.White,
                        fontSize = 13.5.sp,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 3,
                        overflow = TextOverflow.Ellipsis,
                        lineHeight = 18.sp
                    )

                    Text(
                        text = "${cov.profile.countryFlag} ${cov.profile.ownershipType.displayName}",
                        color = ThemeColors.textMuted,
                        fontSize = 10.5.sp
                    )
                }
            }
        }
    }
}
