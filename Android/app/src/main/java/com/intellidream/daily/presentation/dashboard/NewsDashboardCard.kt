package com.intellidream.daily.presentation.dashboard

import androidx.compose.foundation.background
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Feed
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
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.database.NewsRepository
import com.intellidream.daily.designsystem.DailyAsyncImage
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.GlassIntensity
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.AppSettings
import com.intellidream.daily.model.DashboardWidgetSize
import com.intellidream.daily.model.NewsArticle

@Composable
fun NewsDashboardCard(
    size: DashboardWidgetSize,
    repository: NewsRepository,
    settings: AppSettings,
    onTap: () -> Unit,
    onLongClick: () -> Unit = {}
) {
    val topHeadline by repository.topHeadline.collectAsState()
    val articles by repository.articles.collectAsState()
    val isLoading by repository.isLoading.collectAsState()

    val cardHeight = when (size) {
        DashboardWidgetSize.Small -> 155.dp
        DashboardWidgetSize.Wide -> 160.dp
        DashboardWidgetSize.Tall, DashboardWidgetSize.Large -> 324.dp
    }

    val glassIntensity = when (settings.glassIntensity) {
        com.intellidream.daily.model.GlassIntensity.Subtle -> GlassIntensity.Subtle
        com.intellidream.daily.model.GlassIntensity.Medium -> GlassIntensity.Medium
        com.intellidream.daily.model.GlassIntensity.Prominent -> GlassIntensity.Prominent
    }

    GlassCard(
        modifier = Modifier
            .fillMaxWidth()
            .height(cardHeight),
        cornerRadius = 20.dp,
        padding = if (size == DashboardWidgetSize.Small) 14.dp else 18.dp,
        intensity = glassIntensity,
        onClick = onTap,
        onLongClick = onLongClick
    ) {
        when (size) {
            DashboardWidgetSize.Small -> SmallNewsContent(topHeadline, isLoading)
            DashboardWidgetSize.Wide -> WideNewsContent(topHeadline, isLoading)
            DashboardWidgetSize.Tall -> TallNewsContent(topHeadline, articles, isLoading)
            DashboardWidgetSize.Large -> LargeNewsContent(topHeadline, articles, isLoading)
        }
    }
}

// MARK: - Small (1x1)
@Composable
private fun SmallNewsContent(top: NewsArticle?, isLoading: Boolean) {
    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.SpaceBetween,
        horizontalAlignment = Alignment.Start
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = Icons.Rounded.Feed,
                contentDescription = null,
                tint = ThemeColors.accentCyan,
                modifier = Modifier.size(16.dp)
            )
            val pub = top?.publicationName
            if (pub != null) {
                Text(
                    text = pub,
                    color = ThemeColors.accentBlue,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }

        if (top != null) {
            Text(
                text = top.title,
                color = Color.White,
                fontSize = 13.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 3,
                overflow = TextOverflow.Ellipsis,
                lineHeight = 17.sp
            )
            Text(
                text = top.relativeTimeFormatted,
                color = ThemeColors.textMuted,
                fontSize = 10.sp,
                fontWeight = FontWeight.Medium
            )
        } else {
            Text(
                text = if (isLoading) "Loading headlines..." else "Tap to explore news",
                color = ThemeColors.textSecondary,
                fontSize = 12.sp
            )
        }
    }
}

// MARK: - Wide (2x1)
@Composable
private fun WideNewsContent(top: NewsArticle?, isLoading: Boolean) {
    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = Icons.Rounded.Feed,
                    contentDescription = null,
                    tint = ThemeColors.accentCyan,
                    modifier = Modifier.size(16.dp)
                )
                Spacer(modifier = Modifier.width(6.dp))
                Text(
                    text = "News & Briefings",
                    color = ThemeColors.accentCyan,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                Text(
                    text = "Explore Feeds",
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

        if (top != null) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.Top
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = top.title,
                        color = Color.White,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                        lineHeight = 18.sp
                    )
                    Spacer(modifier = Modifier.height(6.dp))
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        Text(
                            text = top.publicationName ?: "Briefing",
                            color = ThemeColors.accentBlue,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.SemiBold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                        Text(
                            text = "•",
                            color = ThemeColors.textMuted,
                            fontSize = 9.sp
                        )
                        Text(
                            text = top.relativeTimeFormatted,
                            color = ThemeColors.textMuted,
                            fontSize = 11.sp
                        )
                    }
                }

                if (!top.imageUrl.isNullOrBlank()) {
                    DailyAsyncImage(
                        url = top.imageUrl,
                        contentDescription = top.title,
                        modifier = Modifier
                            .size(58.dp)
                            .clip(RoundedCornerShape(10.dp)),
                        contentScale = ContentScale.Crop
                    )
                }
            }
        } else {
            Column {
                Text(
                    text = if (isLoading) "Loading latest news briefings..." else "Daily Intelligence and Top Stories",
                    color = Color.White,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "Tap to explore feeds & articles",
                    color = ThemeColors.textSecondary,
                    fontSize = 12.sp
                )
            }
        }
    }
}

// MARK: - Tall (1x2)
@Composable
private fun TallNewsContent(top: NewsArticle?, articles: List<NewsArticle>, isLoading: Boolean) {
    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.Top
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = Icons.Rounded.Feed,
                    contentDescription = null,
                    tint = ThemeColors.accentCyan,
                    modifier = Modifier.size(15.dp)
                )
                Spacer(modifier = Modifier.width(6.dp))
                Text(
                    text = "News",
                    color = ThemeColors.accentCyan,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }
            Text(
                text = "Briefing",
                color = ThemeColors.accentBlue,
                fontSize = 10.sp,
                fontWeight = FontWeight.Bold
            )
        }

        Spacer(modifier = Modifier.height(10.dp))

        if (top != null) {
            if (!top.imageUrl.isNullOrBlank()) {
                DailyAsyncImage(
                    url = top.imageUrl,
                    contentDescription = top.title,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(75.dp)
                        .clip(RoundedCornerShape(10.dp)),
                    contentScale = ContentScale.Crop
                )
                Spacer(modifier = Modifier.height(8.dp))
            }

            Text(
                text = top.title,
                color = Color.White,
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 3,
                overflow = TextOverflow.Ellipsis,
                lineHeight = 16.sp
            )

            Spacer(modifier = Modifier.height(4.dp))

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Text(
                    text = top.publicationName ?: "",
                    color = ThemeColors.accentBlue,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(text = "•", color = ThemeColors.textMuted, fontSize = 8.sp)
                Text(text = top.relativeTimeFormatted, color = ThemeColors.textMuted, fontSize = 10.sp)
            }

            Spacer(modifier = Modifier.height(10.dp))
            HorizontalDivider(color = Color.White.copy(alpha = 0.12f))
            Spacer(modifier = Modifier.height(8.dp))

            val secondary = articles.drop(1).firstOrNull()
            if (secondary != null) {
                Text(
                    text = secondary.title,
                    color = Color.White.copy(alpha = 0.9f),
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    lineHeight = 15.sp
                )
                Spacer(modifier = Modifier.height(3.dp))
                Text(
                    text = secondary.relativeTimeFormatted,
                    color = ThemeColors.textMuted,
                    fontSize = 9.sp
                )
            }
        } else {
            Spacer(modifier = Modifier.weight(1f))
            Text(
                text = if (isLoading) "Loading headlines..." else "No headlines loaded",
                color = ThemeColors.textMuted,
                fontSize = 11.sp
            )
            Spacer(modifier = Modifier.weight(1f))
        }
    }
}

// MARK: - Large (2x2)
@Composable
private fun LargeNewsContent(top: NewsArticle?, articles: List<NewsArticle>, isLoading: Boolean) {
    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.Top
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = Icons.Rounded.Feed,
                    contentDescription = null,
                    tint = ThemeColors.accentCyan,
                    modifier = Modifier.size(16.dp)
                )
                Spacer(modifier = Modifier.width(6.dp))
                Text(
                    text = "News & Intelligence",
                    color = ThemeColors.accentCyan,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                Text(
                    text = "All Feeds",
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

        Spacer(modifier = Modifier.height(10.dp))

        if (top != null) {
            // Lead Story
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.Top
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = top.title,
                        color = Color.White,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                        lineHeight = 18.sp
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        Text(
                            text = top.publicationName ?: "",
                            color = ThemeColors.accentBlue,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.SemiBold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                        Text(text = "•", color = ThemeColors.textMuted, fontSize = 9.sp)
                        Text(text = top.relativeTimeFormatted, color = ThemeColors.textMuted, fontSize = 11.sp)
                    }
                }

                if (!top.imageUrl.isNullOrBlank()) {
                    DailyAsyncImage(
                        url = top.imageUrl,
                        contentDescription = top.title,
                        modifier = Modifier
                            .size(70.dp)
                            .clip(RoundedCornerShape(12.dp)),
                        contentScale = ContentScale.Crop
                    )
                }
            }

            Spacer(modifier = Modifier.height(10.dp))
            HorizontalDivider(color = Color.White.copy(alpha = 0.12f))
            Spacer(modifier = Modifier.height(10.dp))

            // Secondary Stories
            val moreStories = articles.drop(1).take(2)
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                moreStories.forEach { story ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = story.title,
                                color = Color.White.copy(alpha = 0.9f),
                                fontSize = 12.sp,
                                fontWeight = FontWeight.SemiBold,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                                lineHeight = 16.sp
                            )
                            Spacer(modifier = Modifier.height(2.dp))
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(4.dp)
                            ) {
                                Text(
                                    text = story.publicationName ?: "",
                                    color = ThemeColors.accentBlue,
                                    fontSize = 10.sp,
                                    fontWeight = FontWeight.Medium,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                                Text(text = "•", color = ThemeColors.textMuted, fontSize = 8.sp)
                                Text(text = story.relativeTimeFormatted, color = ThemeColors.textMuted, fontSize = 10.sp)
                            }
                        }

                        if (!story.imageUrl.isNullOrBlank()) {
                            DailyAsyncImage(
                                url = story.imageUrl,
                                contentDescription = story.title,
                                modifier = Modifier
                                    .size(44.dp)
                                    .clip(RoundedCornerShape(8.dp)),
                                contentScale = ContentScale.Crop
                            )
                        }
                    }
                }
            }
        } else {
            Spacer(modifier = Modifier.weight(1f))
            Text(
                text = if (isLoading) "Loading headlines..." else "Tap to explore news & briefings",
                color = ThemeColors.textMuted,
                fontSize = 13.sp
            )
            Spacer(modifier = Modifier.weight(1f))
        }
    }
}
