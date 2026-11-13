package com.intellidream.daily.presentation.news

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Balance
import androidx.compose.material.icons.rounded.PieChart
import androidx.compose.material.icons.rounded.VisibilityOff
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.designsystem.DailyAsyncImage
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.ArticleFramingTag
import com.intellidream.daily.model.BiasDistribution
import com.intellidream.daily.model.BlindspotType
import com.intellidream.daily.model.FactualityTier
import com.intellidream.daily.model.MediaBias
import com.intellidream.daily.model.MediaDietSnapshot
import com.intellidream.daily.model.MediaOutletProfile
import com.intellidream.daily.model.StoryCluster

object PerspectivesPalette {
    val leftBlue = Color(0xFF3B82F6)
    val leanLeftSky = Color(0xFF60A5FA)
    val centerSilver = Color(0xFFCBD5E1)
    val leanRightCoral = Color(0xFFFB7185)
    val rightRose = Color(0xFFE11D48)
    val independentPurple = Color(0xFFA855F7)
    val blindspotAmber = Color(0xFFF59E0B)
    val factHighEmerald = Color(0xFF10B981)
    val factMixedAmber = Color(0xFFFBBF24)
    val factLowRose = Color(0xFFF43F5E)

    fun colorForBias(bias: MediaBias): Color = when (bias) {
        MediaBias.Left -> leftBlue
        MediaBias.LeanLeft -> leanLeftSky
        MediaBias.Center -> centerSilver
        MediaBias.LeanRight -> leanRightCoral
        MediaBias.Right -> rightRose
        MediaBias.IndependentCreator -> independentPurple
        MediaBias.Unrated -> Color.White.copy(alpha = 0.55f)
    }

    fun colorForFactuality(tier: FactualityTier): Color = when (tier) {
        FactualityTier.VeryHigh, FactualityTier.High -> factHighEmerald
        FactualityTier.Mixed -> factMixedAmber
        FactualityTier.Low -> factLowRose
    }

    fun colorForFraming(tag: ArticleFramingTag): Color = when (tag) {
        ArticleFramingTag.Reporting -> centerSilver
        ArticleFramingTag.Opinion -> Color(0xFFC084FC)
        ArticleFramingTag.Investigation -> ThemeColors.accentCyan
        ArticleFramingTag.Sensational -> blindspotAmber
    }
}

/**
 * Sleek Variant A micro-pill displayed inline next to the publication title (`Center · High` or `Independent · High`),
 * plus optional non-standard framing tag (`Opinion` / `Investigation` / `Sensational`).
 */
@Composable
fun OutletMicroBadge(
    profile: MediaOutletProfile,
    framing: ArticleFramingTag = ArticleFramingTag.Reporting,
    onClick: (() -> Unit)? = null
) {
    val biasColor = PerspectivesPalette.colorForBias(profile.bias)
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp)
    ) {
        if (profile.bias != MediaBias.Unrated) {
            Row(
                modifier = Modifier
                    .clip(CircleShape)
                    .background(biasColor.copy(alpha = 0.13f))
                    .border(0.7.dp, biasColor.copy(alpha = 0.34f), CircleShape)
                    .let { mod -> if (onClick != null) mod.clickable { onClick() } else mod }
                    .padding(horizontal = 6.dp, vertical = 2.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Box(
                    modifier = Modifier
                        .size(5.dp)
                        .clip(CircleShape)
                        .background(biasColor)
                )
                Text(
                    text = "${profile.bias.shortCode} · ${profile.factuality.displayName}",
                    color = Color.White.copy(alpha = 0.88f),
                    fontSize = 9.5.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1
                )
            }
        }

        val framingLabel = framing.badgeLabel
        if (framingLabel != null) {
            val fColor = PerspectivesPalette.colorForFraming(framing)
            Box(
                modifier = Modifier
                    .clip(CircleShape)
                    .background(fColor.copy(alpha = 0.14f))
                    .border(0.7.dp, fColor.copy(alpha = 0.35f), CircleShape)
                    .padding(horizontal = 6.dp, vertical = 2.dp)
            ) {
                Text(
                    text = framingLabel,
                    color = fColor,
                    fontSize = 9.5.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1
                )
            }
        }
    }
}

/**
 * Proportional Left / Center / Right Ground News-style Liquid Glass Bias Spectrum Bar.
 */
@Composable
fun BiasSpectrumBar(
    distribution: BiasDistribution,
    blindspot: BlindspotType = BlindspotType.None,
    uniqueOutlets: Int,
    compact: Boolean = false,
    onOpenPerspectives: (() -> Unit)? = null
) {
    val leftW = distribution.leftFraction.coerceAtLeast(if (distribution.leftCount > 0) 0.08f else 0f)
    val centerW = distribution.centerFraction.coerceAtLeast(if (distribution.centerCount > 0 || distribution.ratedPoliticalCount == 0) 0.08f else 0f)
    val rightW = distribution.rightFraction.coerceAtLeast(if (distribution.rightCount > 0) 0.08f else 0f)
    val sumW = (leftW + centerW + rightW).coerceAtLeast(0.01f)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(Color.White.copy(alpha = 0.045f))
            .border(0.7.dp, Color.White.copy(alpha = 0.10f), RoundedCornerShape(12.dp))
            .let { mod -> if (onOpenPerspectives != null) mod.clickable { onOpenPerspectives() } else mod }
            .padding(horizontal = 10.dp, vertical = if (compact) 7.dp else 9.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        // Segmented proportional bar
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(if (compact) 6.dp else 7.5.dp)
                .clip(CircleShape)
                .background(Color.White.copy(alpha = 0.08f)),
            horizontalArrangement = Arrangement.spacedBy(1.5.dp)
        ) {
            if (leftW > 0f) {
                Box(
                    modifier = Modifier
                        .weight(leftW / sumW)
                        .fillMaxHeight()
                        .background(PerspectivesPalette.leftBlue)
                )
            }
            if (centerW > 0f) {
                Box(
                    modifier = Modifier
                        .weight(centerW / sumW)
                        .fillMaxHeight()
                        .background(PerspectivesPalette.centerSilver)
                )
            }
            if (rightW > 0f) {
                Box(
                    modifier = Modifier
                        .weight(rightW / sumW)
                        .fillMaxHeight()
                        .background(PerspectivesPalette.rightRose)
                )
            }
        }

        // Labels + Blindspot / Perspectives CTA
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = "L ${distribution.leftPercentInt}%",
                    color = PerspectivesPalette.leanLeftSky,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = "C ${distribution.centerPercentInt}%",
                    color = PerspectivesPalette.centerSilver,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = "R ${distribution.rightPercentInt}%",
                    color = PerspectivesPalette.leanRightCoral,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold
                )
            }

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                if (blindspot.isBlindspot) {
                    Row(
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(PerspectivesPalette.blindspotAmber.copy(alpha = 0.16f))
                            .border(0.7.dp, PerspectivesPalette.blindspotAmber.copy(alpha = 0.40f), CircleShape)
                            .padding(horizontal = 6.dp, vertical = 1.5.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(3.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.VisibilityOff,
                            contentDescription = null,
                            tint = PerspectivesPalette.blindspotAmber,
                            modifier = Modifier.size(10.dp)
                        )
                        Text(
                            text = "Blindspot",
                            color = PerspectivesPalette.blindspotAmber,
                            fontSize = 9.5.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }

                if (onOpenPerspectives != null) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(3.dp)
                    ) {
                        Text(
                            text = "$uniqueOutlets sources · Perspectives",
                            color = ThemeColors.accentCyan,
                            fontSize = 10.5.sp,
                            fontWeight = FontWeight.Bold
                        )
                        Icon(
                            imageVector = Icons.AutoMirrored.Rounded.ArrowForward,
                            contentDescription = null,
                            tint = ThemeColors.accentCyan,
                            modifier = Modifier.size(11.dp)
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun MediaDietHeaderButton(
    snapshot: MediaDietSnapshot,
    size: Dp = 36.dp,
    onClick: () -> Unit
) {
    Box(
        modifier = Modifier
            .size(size)
            .clip(CircleShape)
            .background(PerspectivesPalette.independentPurple.copy(alpha = 0.15f))
            .border(1.dp, PerspectivesPalette.independentPurple.copy(alpha = 0.34f), CircleShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Icon(
            imageVector = Icons.Rounded.PieChart,
            contentDescription = "Media Diet (${snapshot.totalArticlesRead} read)",
            tint = Color(0xFFD8B4FE),
            modifier = Modifier.size(17.dp)
        )
    }
}

/**
 * Rich multi-source event card displayed in the `Perspectives` & `Blindspots` sub-tab.
 */
@Composable
fun StoryClusterCard(
    cluster: StoryCluster,
    onOpenArticle: () -> Unit,
    onOpenPerspectives: () -> Unit,
    onInspectProfile: (MediaOutletProfile) -> Unit
) {
    val distinctOutlets = remember(cluster.id, cluster.uniqueOutletCount) {
        cluster.items.distinctBy { it.profile.domain }.take(6)
    }

    GlassCard(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onOpenPerspectives() },
        cornerRadius = 20.dp,
        padding = 16.dp
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // Top Row: Multi-source pill + Blindspot badge + time
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Row(
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(ThemeColors.accentCyan.copy(alpha = 0.14f))
                            .border(0.8.dp, ThemeColors.accentCyan.copy(alpha = 0.35f), CircleShape)
                            .padding(horizontal = 8.dp, vertical = 3.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.Balance,
                            contentDescription = null,
                            tint = ThemeColors.accentCyan,
                            modifier = Modifier.size(12.dp)
                        )
                        Text(
                            text = "${cluster.uniqueOutletCount} Outlets",
                            color = ThemeColors.accentCyan,
                            fontSize = 10.5.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }

                    if (cluster.blindspot.isBlindspot) {
                        Row(
                            modifier = Modifier
                                .clip(CircleShape)
                                .background(PerspectivesPalette.blindspotAmber.copy(alpha = 0.16f))
                                .border(0.8.dp, PerspectivesPalette.blindspotAmber.copy(alpha = 0.42f), CircleShape)
                                .padding(horizontal = 8.dp, vertical = 3.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            Icon(
                                imageVector = Icons.Rounded.VisibilityOff,
                                contentDescription = null,
                                tint = PerspectivesPalette.blindspotAmber,
                                modifier = Modifier.size(11.dp)
                            )
                            Text(
                                text = cluster.blindspot.badgeTitle,
                                color = PerspectivesPalette.blindspotAmber,
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold
                            )
                        }
                    }
                }

                Text(
                    text = cluster.leadArticle.relativeTimeFormatted,
                    color = ThemeColors.textMuted,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Medium
                )
            }

            // Body: Lead Headline + Thumbnail
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(14.dp),
                verticalAlignment = Alignment.Top
            ) {
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Text(
                        text = cluster.leadArticle.title,
                        color = Color.White,
                        fontSize = 15.5.sp,
                        fontWeight = FontWeight.Bold,
                        maxLines = 3,
                        overflow = TextOverflow.Ellipsis,
                        lineHeight = 20.5.sp
                    )
                    if (cluster.anchorEntities.isNotEmpty()) {
                        Text(
                            text = cluster.anchorEntities.take(4).joinToString(" · "),
                            color = ThemeColors.textMuted,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Medium,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }

                if (!cluster.leadArticle.imageUrl.isNullOrBlank()) {
                    DailyAsyncImage(
                        url = cluster.leadArticle.imageUrl,
                        contentDescription = null,
                        modifier = Modifier
                            .size(82.dp)
                            .clip(RoundedCornerShape(14.dp))
                            .border(1.dp, Color.White.copy(alpha = 0.14f), RoundedCornerShape(14.dp))
                            .clickable { onOpenArticle() },
                        contentScale = ContentScale.Crop
                    )
                }
            }

            // Outlet Chips Row
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                distinctOutlets.take(4).forEach { item ->
                    val bColor = PerspectivesPalette.colorForBias(item.profile.bias)
                    Row(
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(Color.White.copy(alpha = 0.06f))
                            .border(0.6.dp, bColor.copy(alpha = 0.35f), CircleShape)
                            .clickable { onInspectProfile(item.profile) }
                            .padding(horizontal = 7.dp, vertical = 3.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        Box(
                            modifier = Modifier
                                .size(5.dp)
                                .clip(CircleShape)
                                .background(bColor)
                        )
                        Text(
                            text = item.profile.name,
                            color = Color.White.copy(alpha = 0.86f),
                            fontSize = 10.sp,
                            fontWeight = FontWeight.SemiBold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }
                if (cluster.uniqueOutletCount > 4) {
                    Text(
                        text = "+${cluster.uniqueOutletCount - 4}",
                        color = ThemeColors.textMuted,
                        fontSize = 10.5.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
            }

            // Full Bias Spectrum Bar
            BiasSpectrumBar(
                distribution = cluster.distribution,
                blindspot = cluster.blindspot,
                uniqueOutlets = cluster.uniqueOutletCount,
                compact = false,
                onOpenPerspectives = onOpenPerspectives
            )
        }
    }
}
