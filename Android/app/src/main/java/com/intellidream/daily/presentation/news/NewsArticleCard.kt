package com.intellidream.daily.presentation.news

import android.content.Intent
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
import androidx.compose.material.icons.rounded.Bookmark
import androidx.compose.material.icons.rounded.BookmarkBorder
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.Share
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material.icons.rounded.StarBorder
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.designsystem.DailyAsyncImage
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.NewsArticle

@Composable
fun NewsArticleCard(
    article: NewsArticle,
    isReadLater: Boolean,
    isFavorite: Boolean,
    isMediumSubscribed: Boolean = false,
    onTap: () -> Unit,
    onToggleReadLater: () -> Unit,
    onToggleFavorite: () -> Unit,
    onFollowMediumAuthor: ((String) -> Unit)? = null
) {
    val context = LocalContext.current
    val haptic = LocalHapticFeedback.current

    GlassCard(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onTap() },
        cornerRadius = 20.dp,
        padding = 16.dp
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // Header: Publication, Category Pill & Relative Time
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                // Publication Favicon
                if (!article.publicationIconUrl.isNullOrBlank()) {
                    DailyAsyncImage(
                        url = article.publicationIconUrl,
                        contentDescription = null,
                        modifier = Modifier
                            .size(18.dp)
                            .clip(CircleShape),
                        contentScale = ContentScale.Crop
                    )
                }

                Text(
                    text = article.publicationName ?: "News",
                    color = ThemeColors.accentCyan,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )

                val cat = article.category
                if (cat != null) {
                    Box(
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(Color.White.copy(alpha = 0.08f))
                            .border(1.dp, Color.White.copy(alpha = 0.12f), CircleShape)
                            .padding(horizontal = 7.dp, vertical = 2.dp)
                    ) {
                        Text(
                            text = cat.displayName,
                            color = Color.White.copy(alpha = 0.8f),
                            fontSize = 10.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }

                Spacer(modifier = Modifier.weight(1f))

                Text(
                    text = article.relativeTimeFormatted,
                    color = ThemeColors.textMuted,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Medium
                )
            }

            // Body: Title, Description & Thumbnail
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(14.dp),
                verticalAlignment = Alignment.Top
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = article.title,
                        color = Color.White,
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold,
                        maxLines = 3,
                        overflow = TextOverflow.Ellipsis,
                        lineHeight = 20.sp
                    )

                    val desc = article.description
                    if (!desc.isNullOrBlank()) {
                        Spacer(modifier = Modifier.height(6.dp))
                        Text(
                            text = desc,
                            color = ThemeColors.textSecondary,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Normal,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                            lineHeight = 18.sp
                        )
                    }
                }

                if (!article.imageUrl.isNullOrBlank()) {
                    DailyAsyncImage(
                        url = article.imageUrl,
                        contentDescription = article.title,
                        modifier = Modifier
                            .size(88.dp)
                            .clip(RoundedCornerShape(14.dp))
                            .border(1.dp, Color.White.copy(alpha = 0.15f), RoundedCornerShape(14.dp)),
                        contentScale = ContentScale.Crop
                    )
                }
            }

            // Actions Footer: Author, Follow, Read Later, Favorite, Share
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                val author = article.author
                if (!author.isNullOrBlank()) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                        modifier = Modifier.weight(1f, fill = false)
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.Person,
                            contentDescription = null,
                            tint = ThemeColors.textMuted,
                            modifier = Modifier.size(12.dp)
                        )
                        Text(
                            text = author,
                            color = ThemeColors.textMuted,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Medium,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )

                        if (article.isMediumItem) {
                            val mediumUser = extractMediumUsername(article)
                            if (mediumUser != null) {
                                Spacer(modifier = Modifier.width(4.dp))
                                Box(
                                    modifier = Modifier
                                        .clip(CircleShape)
                                        .background(
                                            if (isMediumSubscribed) Color.White.copy(alpha = 0.06f)
                                            else ThemeColors.accentCyan.copy(alpha = 0.12f)
                                        )
                                        .clickable {
                                            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                            onFollowMediumAuthor?.invoke(mediumUser)
                                        }
                                        .padding(horizontal = 6.dp, vertical = 2.dp)
                                ) {
                                    Row(
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(3.dp)
                                    ) {
                                        Icon(
                                            imageVector = if (isMediumSubscribed) Icons.Rounded.CheckCircle else Icons.Rounded.Person,
                                            contentDescription = null,
                                            tint = if (isMediumSubscribed) Color.White.copy(alpha = 0.6f) else ThemeColors.accentCyan,
                                            modifier = Modifier.size(10.dp)
                                        )
                                        Text(
                                            text = if (isMediumSubscribed) "Following" else "Follow",
                                            color = if (isMediumSubscribed) Color.White.copy(alpha = 0.6f) else ThemeColors.accentCyan,
                                            fontSize = 10.sp,
                                            fontWeight = FontWeight.Bold
                                        )
                                    }
                                }
                            }
                        }
                    }
                }

                Spacer(modifier = Modifier.weight(1f))

                // Read Later Toggle
                IconButton(
                    onClick = {
                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                        onToggleReadLater()
                    },
                    modifier = Modifier
                        .size(32.dp)
                        .clip(CircleShape)
                        .background(
                            if (isReadLater) ThemeColors.accentCyan.copy(alpha = 0.18f)
                            else Color.White.copy(alpha = 0.06f)
                        )
                ) {
                    Icon(
                        imageVector = if (isReadLater) Icons.Rounded.Bookmark else Icons.Rounded.BookmarkBorder,
                        contentDescription = "Read Later",
                        tint = if (isReadLater) ThemeColors.accentCyan else ThemeColors.textMuted,
                        modifier = Modifier.size(16.dp)
                    )
                }

                // Favorite Toggle
                IconButton(
                    onClick = {
                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                        onToggleFavorite()
                    },
                    modifier = Modifier
                        .size(32.dp)
                        .clip(CircleShape)
                        .background(
                            if (isFavorite) Color(0xFFFFD700).copy(alpha = 0.18f)
                            else Color.White.copy(alpha = 0.06f)
                        )
                ) {
                    Icon(
                        imageVector = if (isFavorite) Icons.Rounded.Star else Icons.Rounded.StarBorder,
                        contentDescription = "Favorite",
                        tint = if (isFavorite) Color(0xFFFFD700) else ThemeColors.textMuted,
                        modifier = Modifier.size(16.dp)
                    )
                }

                // Share Button
                IconButton(
                    onClick = {
                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                        val sendIntent = Intent().apply {
                            action = Intent.ACTION_SEND
                            putExtra(Intent.EXTRA_TEXT, "${article.title}\n\n${article.link}")
                            type = "text/plain"
                        }
                        context.startActivity(Intent.createChooser(sendIntent, "Share Article"))
                    },
                    modifier = Modifier
                        .size(32.dp)
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.06f))
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Share,
                        contentDescription = "Share",
                        tint = ThemeColors.textMuted,
                        modifier = Modifier.size(14.dp)
                    )
                }
            }
        }
    }
}

internal fun extractMediumUsername(article: NewsArticle): String? {
    if (!article.link.contains("medium.com")) return null
    return try {
        val uri = java.net.URI(article.link)
        val path = uri.path
        if (path != null && path.startsWith("/@")) {
            path.removePrefix("/@").substringBefore("/")
        } else if (uri.host?.contains(".medium.com") == true) {
            val sub = uri.host.substringBefore(".medium.com")
            if (sub != "www" && sub != "api") sub else null
        } else null
    } catch (_: Exception) {
        null
    }
}
