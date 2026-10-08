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
import androidx.compose.foundation.layout.widthIn
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
import com.intellidream.daily.designsystem.DailyLiquidLoadingIndicator
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
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.fillMaxHeight
import android.view.MotionEvent
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.spring
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.offset
import androidx.compose.ui.input.pointer.pointerInput
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
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlin.math.roundToInt
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

    // Smooth drag-to-dismiss translation offset with spring physics
    val animatableOffset = remember { Animatable(800f) }

    LaunchedEffect(Unit) {
        animatableOffset.animateTo(
            targetValue = 0f,
            animationSpec = spring(dampingRatio = 0.85f, stiffness = 380f)
        )
    }

    fun dismissWithAnimation() {
        coroutineScope.launch {
            animatableOffset.animateTo(
                targetValue = 1600f,
                animationSpec = tween(durationMillis = 180)
            )
            onDismiss()
        }
    }

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
        onDismissRequest = { dismissWithAnimation() },
        properties = DialogProperties(
            usePlatformDefaultWidth = false,
            decorFitsSystemWindows = false
        )
    ) {
        val currentOffset = animatableOffset.value
        val scrimAlpha = (0.50f * (1f - (currentOffset / 800f).coerceIn(0f, 1f))).coerceAtLeast(0f)

        Box(
            modifier = Modifier.fillMaxSize()
        ) {
            // Background Dimming Scrim
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = scrimAlpha))
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                        onClick = { dismissWithAnimation() }
                    )
            )

            val configuration = androidx.compose.ui.platform.LocalConfiguration.current
            val isFoldable = configuration.screenWidthDp >= 600

            // Sheet Card (iOS page sheet style: 95% height, rounded top corners)
            Box(
                modifier = Modifier
                    .widthIn(max = if (isFoldable) 700.dp else androidx.compose.ui.unit.Dp.Unspecified)
                    .fillMaxWidth()
                    .fillMaxHeight(0.95f)
                    .align(Alignment.BottomCenter)
                    .offset { IntOffset(0, currentOffset.roundToInt()) }
                    .clip(RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp))
                    .background(Color(if (isDark) 0xFF1A1423 else 0xFFEDE5D9))
                    .navigationBarsPadding()
            ) {
                Column(
                    modifier = Modifier.fillMaxSize()
                ) {
                    // Top Drag Handle & Toolbar with downward drag gesture
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .pointerInput(Unit) {
                                detectVerticalDragGestures(
                                    onDragEnd = {
                                        if (animatableOffset.value > 150f) {
                                            dismissWithAnimation()
                                        } else {
                                            coroutineScope.launch {
                                                animatableOffset.animateTo(
                                                    0f,
                                                    spring(dampingRatio = 0.82f, stiffness = 450f)
                                                )
                                            }
                                        }
                                    },
                                    onDragCancel = {
                                        coroutineScope.launch {
                                            animatableOffset.animateTo(
                                                0f,
                                                spring(dampingRatio = 0.82f, stiffness = 450f)
                                            )
                                        }
                                    },
                                    onVerticalDrag = { _, dragAmount ->
                                        coroutineScope.launch {
                                            val next = (animatableOffset.value + dragAmount).coerceAtLeast(0f)
                                            animatableOffset.snapTo(next)
                                        }
                                    }
                                )
                            }
                    ) {
                        // Centered Drag Handle Pill
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 10.dp, bottom = 4.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Box(
                                modifier = Modifier
                                    .width(40.dp)
                                    .height(4.5.dp)
                                    .clip(CircleShape)
                                    .background(Color.White.copy(alpha = 0.40f))
                            )
                        }

                        // Top Glass Toolbar
                        ReaderTopToolbar(
                            article = currentArticle,
                            isReadLater = isReadLater,
                            isFavorite = isFavorite,
                            fontSizeMultiplier = fontSizeMultiplier,
                            onDismiss = { dismissWithAnimation() },
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
                    }

                    // Article Body Content
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxWidth()
                    ) {
                        if (isLoadingFull) {
                            DailyLiquidLoadingIndicator(
                                color = ThemeColors.accentCyan,
                                size = 44.dp,
                                label = "Extracting Distraction-Free Article...",
                                modifier = Modifier.fillMaxSize()
                            )
                        } else {
                            val readerHtml = remember(currentArticle, isDark, fontSizeMultiplier) {
                                generateReaderHtml(currentArticle, isDark, fontSizeMultiplier)
                            }

                            AndroidView(
                                factory = { ctx ->
                                    var touchStartY = 0f
                                    var isPullingDownAtTop = false
                                    var initialScrollY = 0

                                    WebView(ctx).apply {
                                        setBackgroundColor(0x00000000)
                                        settings.javaScriptEnabled = true
                                        settings.domStorageEnabled = true
                                        webViewClient = WebViewClient()
                                        tag = "${currentArticle.link}_${readerHtml.hashCode()}"
                                        loadDataWithBaseURL(currentArticle.link, readerHtml, "text/html", "UTF-8", null)

                                        setOnTouchListener { v, event ->
                                            when (event.actionMasked) {
                                                MotionEvent.ACTION_DOWN -> {
                                                    touchStartY = event.rawY
                                                    initialScrollY = v.scrollY
                                                    isPullingDownAtTop = false
                                                }
                                                MotionEvent.ACTION_MOVE -> {
                                                    val deltaY = event.rawY - touchStartY
                                                    if (v.scrollY == 0 && initialScrollY == 0 && deltaY > 30f) {
                                                        isPullingDownAtTop = true
                                                    }
                                                    if (isPullingDownAtTop) {
                                                        val dragDistance = (deltaY - 30f).coerceAtLeast(0f)
                                                        coroutineScope.launch {
                                                            animatableOffset.snapTo(dragDistance)
                                                        }
                                                        return@setOnTouchListener true
                                                    }
                                                }
                                                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                                                    if (isPullingDownAtTop) {
                                                        isPullingDownAtTop = false
                                                        if (animatableOffset.value > 150f) {
                                                            dismissWithAnimation()
                                                        } else {
                                                            coroutineScope.launch {
                                                                animatableOffset.animateTo(
                                                                    0f,
                                                                    spring(dampingRatio = 0.82f, stiffness = 450f)
                                                                )
                                                            }
                                                        }
                                                        return@setOnTouchListener true
                                                    }
                                                }
                                            }
                                            false
                                        }
                                    }
                                },
                                update = { webView ->
                                    val key = "${currentArticle.link}_${readerHtml.hashCode()}"
                                    if (webView.tag != key) {
                                        webView.tag = key
                                        webView.loadDataWithBaseURL(currentArticle.link, readerHtml, "text/html", "UTF-8", null)
                                    }
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
}

@Composable
private fun ReaderActionButton(
    onClick: () -> Unit,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    contentDescription: String?,
    modifier: Modifier = Modifier,
    backgroundColor: Color = Color.White.copy(alpha = 0.10f),
    iconTint: Color = Color.White,
    iconSize: androidx.compose.ui.unit.Dp = 16.dp
) {
    Box(
        modifier = modifier
            .size(34.dp)
            .clip(CircleShape)
            .background(backgroundColor)
            .border(0.5.dp, Color.White.copy(alpha = 0.15f), CircleShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Icon(
            imageVector = icon,
            contentDescription = contentDescription,
            tint = iconTint,
            modifier = Modifier.size(iconSize)
        )
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
        ReaderActionButton(
            onClick = onDismiss,
            icon = Icons.Rounded.Close,
            contentDescription = "Dismiss",
            backgroundColor = Color.White.copy(alpha = 0.10f),
            iconTint = Color.White,
            iconSize = 18.dp
        )

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

        // Action Buttons Row (Grouped with explicit 10.dp spacing to prevent overlap)
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            // Read Later Toggle
            ReaderActionButton(
                onClick = onToggleReadLater,
                icon = if (isReadLater) Icons.Rounded.Bookmark else Icons.Rounded.BookmarkBorder,
                contentDescription = "Read Later",
                backgroundColor = if (isReadLater) ThemeColors.accentCyan.copy(alpha = 0.22f)
                else Color.White.copy(alpha = 0.10f),
                iconTint = if (isReadLater) ThemeColors.accentCyan else Color.White.copy(alpha = 0.85f),
                iconSize = 16.dp
            )

            // Favorite Toggle
            ReaderActionButton(
                onClick = onToggleFavorite,
                icon = if (isFavorite) Icons.Rounded.Star else Icons.Rounded.StarBorder,
                contentDescription = "Favorite",
                backgroundColor = if (isFavorite) Color(0xFFFFD700).copy(alpha = 0.22f)
                else Color.White.copy(alpha = 0.10f),
                iconTint = if (isFavorite) Color(0xFFFFD700) else Color.White.copy(alpha = 0.85f),
                iconSize = 16.dp
            )

            // More Options Menu
            Box {
                ReaderActionButton(
                    onClick = { showMenu = true },
                    icon = Icons.Rounded.MoreVert,
                    contentDescription = "Options",
                    backgroundColor = Color.White.copy(alpha = 0.10f),
                    iconTint = Color.White,
                    iconSize = 18.dp
                )

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

    val contentBody = article.content?.takeIf { it.isNotBlank() }
        ?: article.description?.takeIf { it.isNotBlank() }
        ?: "<p>No content preview available. Tap <strong>Open in Browser</strong> from the top menu to read the full story on the publisher's website.</p>"

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
