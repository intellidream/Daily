package com.intellidream.daily.presentation.dashboard

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.FormatQuote
import androidx.compose.material.icons.rounded.Image
import androidx.compose.material.icons.rounded.Language
import androidx.compose.material.icons.rounded.Link
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.database.PrismRepository
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.DashboardWidgetSize
import com.intellidream.daily.model.PrismClipType

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun PrismDashboardCard(
    size: DashboardWidgetSize,
    repository: PrismRepository,
    onOpenHub: () -> Unit,
    onLongClick: () -> Unit = {}
) {
    val clips by repository.clips.collectAsState()
    val pins by repository.pinnedSites.collectAsState()

    val cardModifier = when (size) {
        DashboardWidgetSize.Small -> Modifier.fillMaxWidth().height(155.dp)
        DashboardWidgetSize.Tall, DashboardWidgetSize.Large -> Modifier.fillMaxWidth().height(324.dp)
        DashboardWidgetSize.Wide -> Modifier.fillMaxWidth()
    }

    GlassCard(
        modifier = cardModifier.combinedClickable(
            onClick = onOpenHub,
            onLongClick = onLongClick
        ),
        cornerRadius = 20.dp,
        padding = if (size == DashboardWidgetSize.Small) 14.dp else 18.dp
    ) {
        when (size) {
            DashboardWidgetSize.Small -> {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.Language,
                            contentDescription = null,
                            tint = ThemeColors.accentCyan,
                            modifier = Modifier.size(16.dp)
                        )
                        Box(
                            modifier = Modifier
                                .clip(CircleShape)
                                .background(ThemeColors.accentCyan.copy(alpha = 0.16f))
                                .padding(horizontal = 8.dp, vertical = 2.dp)
                        ) {
                            Text(
                                text = "${clips.size}",
                                color = ThemeColors.accentCyan,
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold
                            )
                        }
                    }

                    Spacer(modifier = Modifier.weight(1f))

                    val latest = clips.firstOrNull()
                    if (latest != null) {
                        Text(
                            text = latest.title,
                            color = Color.White,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Bold,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis
                        )
                        Text(
                            text = latest.domain,
                            color = ThemeColors.textSecondary,
                            fontSize = 10.5.sp,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    } else {
                        Text(
                            text = "Prism Web",
                            color = Color.White,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Bold
                        )
                        Text(
                            text = "Browse & clip",
                            color = ThemeColors.textSecondary,
                            fontSize = 11.sp
                        )
                    }
                }
            }

            DashboardWidgetSize.Wide -> {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
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
                                imageVector = Icons.Rounded.Language,
                                contentDescription = null,
                                tint = ThemeColors.accentCyan,
                                modifier = Modifier.size(16.dp)
                            )
                            Text(
                                text = "Prism & Web Studio",
                                color = ThemeColors.accentCyan,
                                fontSize = 14.sp,
                                fontWeight = FontWeight.SemiBold
                            )
                        }
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                text = "${clips.size} Saved",
                                color = ThemeColors.accentCyan,
                                fontSize = 11.sp,
                                fontWeight = FontWeight.SemiBold
                            )
                            Icon(
                                imageVector = Icons.Rounded.ChevronRight,
                                contentDescription = null,
                                tint = ThemeColors.accentCyan,
                                modifier = Modifier.size(14.dp)
                            )
                        }
                    }

                    Row(
                        modifier = Modifier.horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        pins.take(6).forEach { pin ->
                            Row(
                                modifier = Modifier
                                    .clip(CircleShape)
                                    .background(Color.White.copy(alpha = 0.08f))
                                    .border(1.dp, Color.White.copy(alpha = 0.12f), CircleShape)
                                    .clickable {
                                        repository.requestOpenUrlInPrism(pin.url, pin.title)
                                        onOpenHub()
                                    }
                                    .padding(horizontal = 10.dp, vertical = 6.dp),
                                horizontalArrangement = Arrangement.spacedBy(5.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(
                                    imageVector = Icons.Rounded.Language,
                                    contentDescription = null,
                                    tint = ThemeColors.accentCyan,
                                    modifier = Modifier.size(12.dp)
                                )
                                Text(
                                    text = pin.title,
                                    color = Color.White,
                                    fontSize = 11.5.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    maxLines = 1
                                )
                            }
                        }
                    }

                    clips.firstOrNull()?.let { latest ->
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(
                                imageVector = clipTypeIcon(latest.parsedType),
                                contentDescription = null,
                                tint = Color(latest.parsedType.accentHex),
                                modifier = Modifier.size(13.dp)
                            )
                            Text(
                                text = if (latest.parsedType == PrismClipType.Quote && latest.contentText.isNotBlank()) "\"${latest.contentText}\"" else latest.title,
                                color = Color.White.copy(alpha = 0.88f),
                                fontSize = 12.sp,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.weight(1f)
                            )
                            Text(
                                text = latest.domain,
                                color = ThemeColors.textSecondary,
                                fontSize = 10.5.sp,
                                maxLines = 1
                            )
                        }
                    }
                }
            }

            DashboardWidgetSize.Tall, DashboardWidgetSize.Large -> {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Rounded.Language, null, tint = ThemeColors.accentCyan, modifier = Modifier.size(16.dp))
                            Text("Prism Studio", color = ThemeColors.accentCyan, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                        }
                        Text("${clips.size} clips", color = ThemeColors.accentCyan, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                    }

                    HorizontalDivider(color = Color.White.copy(alpha = 0.08f))

                    if (clips.isEmpty()) {
                        Text(
                            text = "Open any web page with persistent logins, clip quotes or images, and synthesize insights with Co-Pilot.",
                            color = ThemeColors.textSecondary,
                            fontSize = 12.sp
                        )
                    } else {
                        clips.take(4).forEach { clip ->
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clip(RoundedCornerShape(10.dp))
                                    .background(Color.White.copy(alpha = 0.05f))
                                    .padding(8.dp),
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(
                                    imageVector = clipTypeIcon(clip.parsedType),
                                    contentDescription = null,
                                    tint = Color(clip.parsedType.accentHex),
                                    modifier = Modifier.size(14.dp)
                                )
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(clip.title, color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    Text(clip.domain, color = ThemeColors.textSecondary, fontSize = 10.sp, maxLines = 1)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private fun clipTypeIcon(type: PrismClipType) = when (type) {
    PrismClipType.Link -> Icons.Rounded.Link
    PrismClipType.Quote -> Icons.Rounded.FormatQuote
    PrismClipType.Image -> Icons.Rounded.Image
    PrismClipType.AiSummary -> Icons.Rounded.AutoAwesome
}
