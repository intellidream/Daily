package com.intellidream.daily.presentation.news

import android.annotation.SuppressLint
import android.content.Intent
import android.net.Uri
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Bookmark
import androidx.compose.material.icons.rounded.BookmarkBorder
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.KeyboardArrowUp
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.OpenInBrowser
import androidx.compose.material.icons.rounded.PersonAdd
import androidx.compose.material.icons.rounded.Share
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material.icons.rounded.StarBorder
import androidx.compose.material.icons.rounded.TextFields
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import kotlinx.coroutines.launch
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.intellidream.daily.database.NewsRepository
import com.intellidream.daily.designsystem.DailyAsyncImage
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.NewsArticle
import com.intellidream.daily.model.SmartRecommendationEngine
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun NewsReaderSheet(
    article: NewsArticle,
    candidatePool: List<NewsArticle>,
    repository: NewsRepository,
    isDark: Boolean = true,
    onDismiss: () -> Unit
) {
    var currentArticle by remember { mutableStateOf(article) }
    var isLoadingFull by remember { mutableStateOf(true) }
    var fontSizeMultiplier by remember { mutableDoubleStateOf(1.0) }
    var recommendations by remember { mutableStateOf<List<NewsArticle>>(emptyList()) }
    var showRecommendations by remember { mutableStateOf(true) }
    var showMenu by remember { mutableStateOf(false) }
    var showTextSizeSubmenu by remember { mutableStateOf(false) }

    val context = LocalContext.current
    val haptic = LocalHapticFeedback.current

    val isReadLater = repository.isReadLater(currentArticle.link)
    val isFavorite = repository.isFavorite(currentArticle.link)
    val coroutineScope = rememberCoroutineScope()

    LaunchedEffect(currentArticle.link) {
        isLoadingFull = true
        recommendations = SmartRecommendationEngine.shared.getRecommendations(
            currentArticle = currentArticle,
            candidatePool = if (candidatePool.isNotEmpty()) candidatePool else repository.articles.value,
            limit = 8
        )
        val extracted = repository.fetchFullArticle(currentArticle)
        currentArticle = extracted
        isLoadingFull = false
    }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(
            usePlatformDefaultWidth = false,
            decorFitsSystemWindows = false
        )
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color(if (isDark) 0xFF1A1423 else 0xFFEDE5D9))
                .statusBarsPadding()
                .navigationBarsPadding()
        ) {
            Column(modifier = Modifier.fillMaxSize()) {
                // Top Glass Toolbar
                ReaderTopToolbar(
                    article = currentArticle,
                    isReadLater = isReadLater,
                    isFavorite = isFavorite,
                    fontSizeMultiplier = fontSizeMultiplier,
                    onDismiss = onDismiss,
                    onToggleReadLater = {
                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                        coroutineScope.launch {
                            repository.toggleReadLater(currentArticle)
                        }
                    },
                    onToggleFavorite = {
                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                        coroutineScope.launch {
                            repository.toggleFavorite(currentArticle)
                        }
                    },
                    onSelectFontSize = { fontSizeMultiplier = it },
                    onShare = {
                        val sendIntent = Intent().apply {
                            action = Intent.ACTION_SEND
                            putExtra(Intent.EXTRA_TEXT, "${currentArticle.title}\n\n${currentArticle.link}")
                            type = "text/plain"
                        }
                        context.startActivity(Intent.createChooser(sendIntent, "Share Article"))
                    },
                    onOpenInBrowser = {
                        try {
                            val browserIntent = Intent(Intent.ACTION_VIEW, Uri.parse(currentArticle.link))
                            context.startActivity(browserIntent)
                        } catch (_: Exception) {}
                    },
                    onFollowMedium = { user ->
                        coroutineScope.launch {
                            repository.subscribeToMediumAuthor(user, currentArticle.author)
                        }
                    }
                )

                // Article Body Content
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                ) {
                    if (isLoadingFull) {
                        Column(
                            modifier = Modifier.fillMaxSize(),
                            verticalArrangement = Arrangement.Center,
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            CircularProgressIndicator(
                                color = ThemeColors.accentCyan,
                                strokeWidth = 3.dp,
                                modifier = Modifier.size(36.dp)
                            )
                            Spacer(modifier = Modifier.height(16.dp))
                            Text(
                                text = "Extracting Distraction-Free Article...",
                                color = ThemeColors.textSecondary,
                                fontSize = 13.sp,
                                fontWeight = FontWeight.Medium
                            )
                        }
                    } else {
                        val readerHtml = remember(currentArticle, isDark, fontSizeMultiplier) {
                            generateReaderHtml(currentArticle, isDark, fontSizeMultiplier)
                        }

                        AndroidView(
                            factory = { ctx ->
                                WebView(ctx).apply {
                                    setBackgroundColor(0x00000000)
                                    settings.javaScriptEnabled = true
                                    settings.domStorageEnabled = true
                                    webViewClient = WebViewClient()
                                    loadDataWithBaseURL(currentArticle.link, readerHtml, "text/html", "UTF-8", null)
                                }
                            },
                            update = { webView ->
                                webView.loadDataWithBaseURL(currentArticle.link, readerHtml, "text/html", "UTF-8", null)
                            },
                            modifier = Modifier.fillMaxSize()
                        )
                    }

                    // Floating Bottom Recommendations Bar
                    if (recommendations.isNotEmpty()) {
                        FloatingRecommendationsBar(
                            recommendations = recommendations,
                            isExpanded = showRecommendations,
                            onToggleExpand = { showRecommendations = !showRecommendations },
                            onSelectRecommendation = { currentArticle = it },
                            modifier = Modifier
                                .align(Alignment.BottomCenter)
                                .padding(horizontal = 16.dp, vertical = 12.dp)
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ReaderTopToolbar(
    article: NewsArticle,
    isReadLater: Boolean,
    isFavorite: Boolean,
    fontSizeMultiplier: Double,
    onDismiss: () -> Unit,
    onToggleReadLater: () -> Unit,
    onToggleFavorite: () -> Unit,
    onSelectFontSize: (Double) -> Unit,
    onShare: () -> Unit,
    onOpenInBrowser: () -> Unit,
    onFollowMedium: (String) -> Unit
) {
    var showMenu by remember { mutableStateOf(false) }
    var showSizeSubmenu by remember { mutableStateOf(false) }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(Color.Black.copy(alpha = 0.40f))
            .border(width = 0.5.dp, color = Color.White.copy(alpha = 0.12f), shape = RoundedCornerShape(0.dp))
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        // Dismiss Button
        IconButton(
            onClick = onDismiss,
            modifier = Modifier
                .size(32.dp)
                .clip(CircleShape)
                .background(Color.White.copy(alpha = 0.08f))
        ) {
            Icon(
                imageVector = Icons.Rounded.Close,
                contentDescription = "Dismiss",
                tint = Color.White,
                modifier = Modifier.size(18.dp)
            )
        }

        // Publication Title (horizontal scroll for long names)
        Row(
            modifier = Modifier
                .weight(1f)
                .horizontalScroll(rememberScrollState()),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
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
                text = article.publicationName ?: "Reader",
                color = Color.White,
                fontSize = 13.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 1
            )
        }

        // Read Later Toggle
        IconButton(
            onClick = onToggleReadLater,
            modifier = Modifier
                .size(32.dp)
                .clip(CircleShape)
                .background(
                    if (isReadLater) ThemeColors.accentCyan.copy(alpha = 0.20f)
                    else Color.White.copy(alpha = 0.08f)
                )
        ) {
            Icon(
                imageVector = if (isReadLater) Icons.Rounded.Bookmark else Icons.Rounded.BookmarkBorder,
                contentDescription = "Read Later",
                tint = if (isReadLater) ThemeColors.accentCyan else Color.White.copy(alpha = 0.85f),
                modifier = Modifier.size(16.dp)
            )
        }

        // Favorite Toggle
        IconButton(
            onClick = onToggleFavorite,
            modifier = Modifier
                .size(32.dp)
                .clip(CircleShape)
                .background(
                    if (isFavorite) Color(0xFFFFD700).copy(alpha = 0.20f)
                    else Color.White.copy(alpha = 0.08f)
                )
        ) {
            Icon(
                imageVector = if (isFavorite) Icons.Rounded.Star else Icons.Rounded.StarBorder,
                contentDescription = "Favorite",
                tint = if (isFavorite) Color(0xFFFFD700) else Color.White.copy(alpha = 0.85f),
                modifier = Modifier.size(16.dp)
            )
        }

        // More Options Menu
        Box {
            IconButton(
                onClick = { showMenu = true },
                modifier = Modifier
                    .size(32.dp)
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.08f))
            ) {
                Icon(
                    imageVector = Icons.Rounded.MoreVert,
                    contentDescription = "Options",
                    tint = Color.White,
                    modifier = Modifier.size(18.dp)
                )
            }

            DropdownMenu(
                expanded = showMenu,
                onDismissRequest = {
                    showMenu = false
                    showSizeSubmenu = false
                },
                modifier = Modifier
                    .background(Color(0xFF0D182E))
                    .border(1.dp, Color.White.copy(alpha = 0.18f), RoundedCornerShape(14.dp))
            ) {
                DropdownMenuItem(
                    leadingIcon = {
                        Icon(
                            imageVector = Icons.Rounded.Share,
                            contentDescription = null,
                            tint = Color.White,
                            modifier = Modifier.size(16.dp)
                        )
                    },
                    text = { Text("Share Article", color = Color.White, fontSize = 13.sp) },
                    onClick = {
                        showMenu = false
                        onShare()
                    }
                )

                DropdownMenuItem(
                    leadingIcon = {
                        Icon(
                            imageVector = Icons.Rounded.OpenInBrowser,
                            contentDescription = null,
                            tint = Color.White,
                            modifier = Modifier.size(16.dp)
                        )
                    },
                    text = { Text("Open in Browser", color = Color.White, fontSize = 13.sp) },
                    onClick = {
                        showMenu = false
                        onOpenInBrowser()
                    }
                )

                HorizontalDivider(color = Color.White.copy(alpha = 0.12f), modifier = Modifier.padding(vertical = 4.dp))

                // Text Size Trigger
                DropdownMenuItem(
                    leadingIcon = {
                        Icon(
                            imageVector = Icons.Rounded.TextFields,
                            contentDescription = null,
                            tint = ThemeColors.accentCyan,
                            modifier = Modifier.size(16.dp)
                        )
                    },
                    text = { Text("Text Size", color = Color.White, fontSize = 13.sp) },
                    onClick = { showSizeSubmenu = !showSizeSubmenu }
                )

                if (showSizeSubmenu) {
                    val sizes = listOf(
                        "Small" to 0.85,
                        "Default" to 1.0,
                        "Large" to 1.15,
                        "Extra Large" to 1.3
                    )
                    sizes.forEach { (label, mult) ->
                        DropdownMenuItem(
                            text = {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Text(label, color = Color.White.copy(alpha = 0.9f), fontSize = 12.sp)
                                    if (kotlin.math.abs(fontSizeMultiplier - mult) < 0.05) {
                                        Icon(
                                            imageVector = Icons.Rounded.Check,
                                            contentDescription = null,
                                            tint = ThemeColors.accentCyan,
                                            modifier = Modifier.size(14.dp)
                                        )
                                    }
                                }
                            },
                            onClick = {
                                onSelectFontSize(mult)
                                showMenu = false
                                showSizeSubmenu = false
                            }
                        )
                    }
                }

                if (article.isMediumItem) {
                    val mediumUser = extractMediumUsername(article)
                    if (mediumUser != null) {
                        HorizontalDivider(color = Color.White.copy(alpha = 0.12f), modifier = Modifier.padding(vertical = 4.dp))
                        DropdownMenuItem(
                            leadingIcon = {
                                Icon(
                                    imageVector = Icons.Rounded.PersonAdd,
                                    contentDescription = null,
                                    tint = ThemeColors.accentCyan,
                                    modifier = Modifier.size(16.dp)
                                )
                            },
                            text = { Text("Follow @$mediumUser", color = ThemeColors.accentCyan, fontSize = 13.sp) },
                            onClick = {
                                showMenu = false
                                onFollowMedium(mediumUser)
                            }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun FloatingRecommendationsBar(
    recommendations: List<NewsArticle>,
    isExpanded: Boolean,
    onToggleExpand: () -> Unit,
    onSelectRecommendation: (NewsArticle) -> Unit,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .shadow(16.dp, RoundedCornerShape(22.dp))
            .clip(RoundedCornerShape(22.dp))
            .background(Color(0xFF0D121E).copy(alpha = 0.92f))
            .border(1.dp, Color.White.copy(alpha = 0.15f), RoundedCornerShape(22.dp))
            .padding(vertical = 10.dp)
    ) {
        Column(modifier = Modifier.fillMaxWidth()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onToggleExpand() }
                    .padding(horizontal = 16.dp, vertical = 2.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Icon(
                        imageVector = Icons.Rounded.AutoAwesome,
                        contentDescription = null,
                        tint = ThemeColors.accentCyan,
                        modifier = Modifier.size(14.dp)
                    )
                    Text(
                        text = "Related Stories",
                        color = Color.White,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold
                    )
                }

                Icon(
                    imageVector = if (isExpanded) Icons.Rounded.KeyboardArrowDown else Icons.Rounded.KeyboardArrowUp,
                    contentDescription = null,
                    tint = ThemeColors.textMuted,
                    modifier = Modifier.size(16.dp)
                )
            }

            AnimatedVisibility(visible = isExpanded) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState())
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    recommendations.forEach { item ->
                        Box(
                            modifier = Modifier
                                .clip(CircleShape)
                                .background(Color.White.copy(alpha = 0.10f))
                                .border(1.dp, Color.White.copy(alpha = 0.15f), CircleShape)
                                .clickable { onSelectRecommendation(item) }
                                .padding(horizontal = 12.dp, vertical = 6.dp)
                        ) {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(6.dp)
                            ) {
                                if (!item.publicationIconUrl.isNullOrBlank()) {
                                    DailyAsyncImage(
                                        url = item.publicationIconUrl,
                                        contentDescription = null,
                                        modifier = Modifier
                                            .size(14.dp)
                                            .clip(CircleShape),
                                        contentScale = ContentScale.Crop
                                    )
                                }
                                Text(
                                    text = item.title,
                                    color = Color.White,
                                    fontSize = 12.sp,
                                    fontWeight = FontWeight.Medium,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    modifier = Modifier.width(200.dp)
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

private fun generateReaderHtml(article: NewsArticle, isDark: Boolean, fontSizeMultiplier: Double): String {
    val textColor = if (isDark) "#E0E0E0" else "#1A1A1A"
    val linkColor = if (isDark) "#00D2FF" else "#0066CC"
    val metaColor = if (isDark) "#A0A0A0" else "#666666"
    val bodyBackground = if (isDark) "#1A1423" else "#EDE5D9"
    val baseFontSize = (18.0 * fontSizeMultiplier).toInt()

    val featuredImageHtml = if (!article.imageUrl.isNullOrBlank()) {
        "<img class='featured-image' src='${article.imageUrl}' alt='Featured Image' />"
    } else ""

    val formatter = SimpleDateFormat("MMM d, yyyy · h:mm a", Locale.getDefault())
    val dateStr = formatter.format(Date(article.publishDate))

    val authorHtml = if (!article.author.isNullOrBlank()) " &bull; <span>By ${article.author}</span>" else ""
    val metaHtml = "<div class='meta'><span>Published: $dateStr</span>$authorHtml</div>"

    val contentBody = article.content ?: article.description ?: "<p>No content preview available.</p>"

    return """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset='utf-8'/>
        <meta name='viewport' content='width=device-width, initial-scale=1.0, maximum-scale=3.0, user-scalable=yes'/>
        <style>
            * { box-sizing: border-box; }
            html, body { min-height: 100%; background: transparent; }
            body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
                background: $bodyBackground;
                color: $textColor;
                line-height: 1.65;
                margin: 0;
                padding: 0;
                font-size: ${baseFontSize}px;
                -webkit-text-size-adjust: 100%;
            }
            .article-wrap {
                max-width: 720px;
                margin: 0 auto;
                padding: 20px 18px 80px 18px;
            }
            h1.title {
                font-size: ${(baseFontSize * 1.6).toInt()}px;
                font-weight: 800;
                line-height: 1.25;
                margin: 0 0 12px 0;
                letter-spacing: -0.5px;
            }
            .meta {
                font-size: 13px;
                color: $metaColor;
                margin-bottom: 24px;
                border-bottom: 1px solid ${if (isDark) "rgba(255,255,255,0.12)" else "rgba(0,0,0,0.12)"};
                padding-bottom: 14px;
            }
            .featured-image {
                width: 100%;
                max-height: 380px;
                object-fit: cover;
                border-radius: 16px;
                margin: 12px 0 24px 0;
                box-shadow: 0 8px 24px rgba(0,0,0,0.25);
            }
            p { margin-bottom: 20px; }
            a { color: $linkColor; text-decoration: none; font-weight: 500; }
            a:hover { text-decoration: underline; }
            img { max-width: 100%; height: auto; border-radius: 12px; margin: 20px 0; display: block; }
            figure { margin: 20px 0; }
            figcaption { font-size: 12px; color: $metaColor; text-align: center; margin-top: 6px; }
            blockquote {
                margin: 24px 0;
                padding: 12px 20px;
                border-left: 4px solid $linkColor;
                background: ${if (isDark) "rgba(255,255,255,0.04)" else "rgba(0,0,0,0.04)"};
                border-radius: 0 8px 8px 0;
                font-style: italic;
            }
            ul, ol { margin: 16px 0 24px 20px; padding-left: 10px; }
            li { margin-bottom: 8px; }
            code {
                font-family: monospace;
                font-size: 0.9em;
                background: ${if (isDark) "rgba(255,255,255,0.08)" else "rgba(0,0,0,0.06)"};
                padding: 2px 6px;
                border-radius: 4px;
            }
            pre {
                background: ${if (isDark) "#120D1A" else "#E2D8C7"};
                padding: 14px;
                border-radius: 10px;
                overflow-x: auto;
            }
        </style>
    </head>
    <body>
        <div class='article-wrap'>
            <h1 class='title'>${article.title}</h1>
            $metaHtml
            $featuredImageHtml
            <div class='content-body'>
                $contentBody
            </div>
        </div>
    </body>
    </html>
    """.trimIndent()
}
