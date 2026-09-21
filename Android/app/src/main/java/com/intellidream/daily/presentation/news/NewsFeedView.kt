package com.intellidream.daily.presentation.news

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.BookmarkRemove
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Clear
import androidx.compose.material.icons.rounded.Code
import androidx.compose.material.icons.rounded.FilterList
import androidx.compose.material.icons.rounded.FormatListBulleted
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.Memory
import androidx.compose.material.icons.rounded.Newspaper
import androidx.compose.material.icons.rounded.Palette
import androidx.compose.material.icons.rounded.Public
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.RocketLaunch
import androidx.compose.material.icons.rounded.RssFeed
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.StarBorder
import androidx.compose.material.icons.rounded.TrendingUp
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshContainer
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.database.NewsRepository
import com.intellidream.daily.designsystem.DailyAsyncImage
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.AppSettings
import com.intellidream.daily.model.FeedCategory
import com.intellidream.daily.model.FeedSource
import com.intellidream.daily.model.NewsArticle
import kotlinx.coroutines.launch

enum class NewsSubTab(val displayName: String) {
    Live("Live Feed"),
    ReadLater("Read Later"),
    Favorites("Favorites")
}

fun categoryIcon(category: FeedCategory): androidx.compose.ui.graphics.vector.ImageVector = when (category) {
    FeedCategory.All -> Icons.Rounded.Newspaper
    FeedCategory.Local -> Icons.Rounded.Public
    FeedCategory.Markets -> Icons.Rounded.TrendingUp
    FeedCategory.World -> Icons.Rounded.Public
    FeedCategory.Tech -> Icons.Rounded.Memory
    FeedCategory.Coding -> Icons.Rounded.Code
    FeedCategory.Space -> Icons.Rounded.RocketLaunch
    FeedCategory.Other -> Icons.Rounded.RssFeed
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NewsFeedView(
    repository: NewsRepository,
    settings: AppSettings,
    onNavigateBack: () -> Unit
) {
    val feeds by repository.feeds.collectAsState()
    val selectedFeed by repository.selectedFeed.collectAsState()
    val selectedCategory by repository.selectedCategory.collectAsState()
    val liveArticles by repository.articles.collectAsState()
    val readLaterArticles by repository.readLaterArticles.collectAsState()
    val favoriteArticles by repository.favoriteArticles.collectAsState()
    val isLoading by repository.isLoading.collectAsState()

    var activeSubTab by remember { mutableStateOf(NewsSubTab.Live) }
    var searchQuery by remember { mutableStateOf("") }
    var isSearchExpanded by remember { mutableStateOf(false) }
    var selectedArticleForReader by remember { mutableStateOf<NewsArticle?>(null) }
    var showManageFeedsSheet by remember { mutableStateOf(false) }

    val scope = rememberCoroutineScope()
    val haptic = LocalHapticFeedback.current
    val focusManager = LocalFocusManager.current

    val currentArticles = when (activeSubTab) {
        NewsSubTab.Live -> liveArticles
        NewsSubTab.ReadLater -> readLaterArticles
        NewsSubTab.Favorites -> favoriteArticles
    }

    val filteredArticles = remember(currentArticles, searchQuery) {
        val query = searchQuery.trim().lowercase()
        if (query.isBlank()) currentArticles
        else {
            currentArticles.filter {
                it.title.lowercase().contains(query) ||
                        (it.description?.lowercase()?.contains(query) == true) ||
                        (it.author?.lowercase()?.contains(query) == true)
            }
        }
    }

    val pullRefreshState = rememberPullToRefreshState()
    if (pullRefreshState.isRefreshing) {
        LaunchedEffect(true) {
            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
            if (activeSubTab == NewsSubTab.Live) {
                if (selectedCategory == FeedCategory.All) {
                    repository.loadAllNews(forceRefresh = true)
                } else {
                    repository.loadFeed(selectedFeed, forceRefresh = true)
                }
            }
            if (repository.currentUserId != "guest") {
                repository.syncWithSupabase(repository.currentUserId)
            }
            pullRefreshState.endRefresh()
        }
    }

    LaunchedEffect(Unit) {
        if (liveArticles.isEmpty()) {
            repository.loadAllNews()
        }
        if (repository.currentUserId != "guest") {
            repository.syncWithSupabase(repository.currentUserId)
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 20.dp, vertical = 8.dp)
        ) {
            // Pinned Top Glass Header Bar
            NewsHeaderBar(
                searchQuery = searchQuery,
                isSearchExpanded = isSearchExpanded,
                selectedCategory = selectedCategory,
                onSearchQueryChange = { searchQuery = it },
                onSearchExpandedChange = { isSearchExpanded = it },
                onNavigateBack = onNavigateBack,
                onSelectCategory = { cat ->
                    scope.launch {
                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                        repository.selectCategory(cat)
                    }
                },
                onOpenManageFeeds = { showManageFeedsSheet = true }
            )

            Spacer(modifier = Modifier.height(14.dp))

            // Sub-Tab Switcher (Live Feed / Read Later / Favorites)
            SubTabSwitcher(
                activeSubTab = activeSubTab,
                readLaterCount = readLaterArticles.size,
                favoritesCount = favoriteArticles.size,
                onSelectSubTab = { tab ->
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    activeSubTab = tab
                }
            )

            Spacer(modifier = Modifier.height(14.dp))

            // Source Picker Row (Only visible when in Live Feed mode)
            if (activeSubTab == NewsSubTab.Live) {
                FeedPickerRow(
                    selectedFeed = selectedFeed,
                    feeds = feeds,
                    storiesCount = filteredArticles.size,
                    mediumUsername = settings.newsMediumUsername,
                    mediumReadingListUrl = settings.newsMediumReadingListUrl,
                    repository = repository,
                    onSelectFeed = { feed ->
                        scope.launch {
                            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                            repository.selectFeed(feed)
                        }
                    }
                )
                Spacer(modifier = Modifier.height(12.dp))
            }

            // Article List with Pull to Refresh
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .nestedScroll(pullRefreshState.nestedScrollConnection)
            ) {
                if (isLoading && filteredArticles.isEmpty()) {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center
                    ) {
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(16.dp)
                        ) {
                            CircularProgressIndicator(
                                color = ThemeColors.accentCyan,
                                strokeWidth = 3.dp,
                                modifier = Modifier.size(36.dp)
                            )
                            Text(
                                text = "Fetching latest briefings from sources...",
                                color = ThemeColors.textSecondary,
                                fontSize = 13.sp,
                                fontWeight = FontWeight.Medium
                            )
                        }
                    }
                } else if (filteredArticles.isEmpty()) {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center
                    ) {
                        EmptyNewsState(
                            subTab = activeSubTab,
                            onRefresh = {
                                scope.launch {
                                    repository.loadFeed(selectedFeed, forceRefresh = true)
                                }
                            }
                        )
                    }
                } else {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        verticalArrangement = Arrangement.spacedBy(14.dp),
                        contentPadding = PaddingValues(bottom = 90.dp)
                    ) {
                        items(filteredArticles, key = { it.link }) { article ->
                            NewsArticleCard(
                                article = article,
                                isReadLater = repository.isReadLater(article.link),
                                isFavorite = repository.isFavorite(article.link),
                                isMediumSubscribed = if (article.isMediumItem) {
                                    val u = article.mediumUsername ?: article.author?.removePrefix("@") ?: ""
                                    repository.isSubscribedToMediumAuthor(u)
                                } else false,
                                onTap = { selectedArticleForReader = article },
                                onToggleReadLater = {
                                    scope.launch { repository.toggleReadLater(article) }
                                },
                                onToggleFavorite = {
                                    scope.launch { repository.toggleFavorite(article) }
                                },
                                onFollowMediumAuthor = { user ->
                                    scope.launch {
                                        if (repository.isSubscribedToMediumAuthor(user)) {
                                            repository.unsubscribeFromMediumAuthor(user)
                                        } else {
                                            repository.subscribeToMediumAuthor(user, article.author)
                                        }
                                    }
                                }
                            )
                        }
                    }
                }

                PullToRefreshContainer(
                    state = pullRefreshState,
                    modifier = Modifier.align(Alignment.TopCenter),
                    containerColor = Color(0xFF0D182E),
                    contentColor = ThemeColors.accentCyan
                )
            }
        }
    }

    // Distraction-free Article Reader Modal
    selectedArticleForReader?.let { article ->
        NewsReaderSheet(
            article = article,
            candidatePool = filteredArticles,
            repository = repository,
            isDark = settings.theme != com.intellidream.daily.model.AppTheme.Light,
            onDismiss = { selectedArticleForReader = null }
        )
    }

    // Feeds Management Sheet
    if (showManageFeedsSheet) {
        NewsFeedsManagementSheet(
            repository = repository,
            onDismiss = { showManageFeedsSheet = false }
        )
    }
}

// MARK: - Header Bar with Search and Category Dropdown
@Composable
private fun NewsHeaderBar(
    searchQuery: String,
    isSearchExpanded: Boolean,
    selectedCategory: FeedCategory,
    onSearchQueryChange: (String) -> Unit,
    onSearchExpandedChange: (Boolean) -> Unit,
    onNavigateBack: () -> Unit,
    onSelectCategory: (FeedCategory) -> Unit,
    onOpenManageFeeds: () -> Unit
) {
    var showCategoryMenu by remember { mutableStateOf(false) }
    val focusManager = LocalFocusManager.current

    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        // Back Button
        Box(
            modifier = Modifier
                .size(36.dp)
                .clip(CircleShape)
                .background(Color.White.copy(alpha = 0.08f))
                .border(1.dp, Color.White.copy(alpha = 0.12f), CircleShape)
                .clickable {
                    if (isSearchExpanded) {
                        onSearchExpandedChange(false)
                        onSearchQueryChange("")
                        focusManager.clearFocus()
                    } else {
                        onNavigateBack()
                    }
                },
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = Icons.AutoMirrored.Rounded.ArrowBack,
                contentDescription = "Back",
                tint = Color.White,
                modifier = Modifier.size(16.dp)
            )
        }

        // Expanding Search Field
        Box(
            modifier = Modifier
                .weight(1f)
                .height(36.dp)
                .clip(CircleShape)
                .background(Color.White.copy(alpha = 0.06f))
                .border(
                    width = 1.dp,
                    color = if (isSearchExpanded) ThemeColors.accentCyan else Color.White.copy(alpha = 0.10f),
                    shape = CircleShape
                )
                .padding(horizontal = 10.dp),
            contentAlignment = Alignment.CenterStart
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                Icon(
                    imageVector = Icons.Rounded.Search,
                    contentDescription = null,
                    tint = if (isSearchExpanded) ThemeColors.accentCyan else ThemeColors.textMuted,
                    modifier = Modifier.size(15.dp)
                )

                BasicTextField(
                    value = searchQuery,
                    onValueChange = {
                        onSearchQueryChange(it)
                        onSearchExpandedChange(true)
                    },
                    singleLine = true,
                    textStyle = TextStyle(
                        color = Color.White,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Normal
                    ),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                    cursorBrush = SolidColor(ThemeColors.accentCyan),
                    modifier = Modifier
                        .weight(1f)
                        .onFocusChanged { focusState ->
                            if (focusState.isFocused) {
                                onSearchExpandedChange(true)
                            }
                        },
                    decorationBox = { innerTextField ->
                        if (searchQuery.isEmpty()) {
                            Text(
                                text = "Search articles...",
                                color = ThemeColors.textMuted,
                                fontSize = 13.sp
                            )
                        }
                        innerTextField()
                    }
                )

                if (searchQuery.isNotEmpty()) {
                    Box(
                        modifier = Modifier
                            .size(20.dp)
                            .clip(CircleShape)
                            .clickable { onSearchQueryChange("") },
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.Clear,
                            contentDescription = "Clear",
                            tint = ThemeColors.textMuted,
                            modifier = Modifier.size(14.dp)
                        )
                    }
                }
            }
        }

        // Right Actions: Manage Feeds & Category Menu, or Cancel when search expanded
        if (isSearchExpanded) {
            Text(
                text = "Cancel",
                color = ThemeColors.accentCyan,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier
                    .clickable {
                        onSearchExpandedChange(false)
                        onSearchQueryChange("")
                        focusManager.clearFocus()
                    }
                    .padding(horizontal = 6.dp, vertical = 6.dp)
            )
        } else {
            // Manage Feeds Button
            Box(
                modifier = Modifier
                    .size(36.dp)
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.08f))
                    .border(1.dp, Color.White.copy(alpha = 0.12f), CircleShape)
                    .clickable(onClick = onOpenManageFeeds),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Rounded.Tune,
                    contentDescription = "Manage Feeds",
                    tint = Color.White.copy(alpha = 0.85f),
                    modifier = Modifier.size(16.dp)
                )
            }

            // Category Selector Menu
            Box {
                Box(
                    modifier = Modifier
                        .size(36.dp)
                        .clip(CircleShape)
                        .background(ThemeColors.accentCyan.copy(alpha = 0.15f))
                        .border(1.dp, ThemeColors.accentCyan.copy(alpha = 0.30f), CircleShape)
                        .clickable { showCategoryMenu = true },
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = categoryIcon(selectedCategory),
                        contentDescription = "Category",
                        tint = ThemeColors.accentCyan,
                        modifier = Modifier.size(16.dp)
                    )
                }

                DropdownMenu(
                    expanded = showCategoryMenu,
                    onDismissRequest = { showCategoryMenu = false },
                    modifier = Modifier
                        .background(Color(0xFF0D182E))
                        .border(1.dp, Color.White.copy(alpha = 0.18f), RoundedCornerShape(14.dp))
                ) {
                    FeedCategory.entries.forEach { category ->
                        DropdownMenuItem(
                            text = {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Row(
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                                    ) {
                                        Icon(
                                            imageVector = categoryIcon(category),
                                            contentDescription = null,
                                            tint = if (selectedCategory == category) ThemeColors.accentCyan else Color.White.copy(alpha = 0.7f),
                                            modifier = Modifier.size(15.dp)
                                        )
                                        Text(
                                            text = category.displayName,
                                            color = Color.White,
                                            fontSize = 13.sp
                                        )
                                    }
                                    if (selectedCategory == category) {
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
                                showCategoryMenu = false
                                onSelectCategory(category)
                            }
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Sub-Tab Switcher
@Composable
private fun SubTabSwitcher(
    activeSubTab: NewsSubTab,
    readLaterCount: Int,
    favoritesCount: Int,
    onSelectSubTab: (NewsSubTab) -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(CircleShape)
            .background(Color.White.copy(alpha = 0.06f))
            .border(1.dp, Color.White.copy(alpha = 0.10f), CircleShape)
            .padding(4.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            NewsSubTab.entries.forEach { tab ->
                val isSelected = activeSubTab == tab

                Box(
                    modifier = Modifier
                        .weight(1f)
                        .clip(CircleShape)
                        .background(if (isSelected) Color.White.copy(alpha = 0.15f) else Color.Transparent)
                        .clickable { onSelectSubTab(tab) }
                        .padding(vertical = 8.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Text(
                            text = tab.displayName,
                            color = if (isSelected) Color.White else Color.White.copy(alpha = 0.60f),
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold
                        )

                        // Count badges
                        if (tab == NewsSubTab.ReadLater && readLaterCount > 0) {
                            Box(
                                modifier = Modifier
                                    .clip(CircleShape)
                                    .background(ThemeColors.accentCyan)
                                    .padding(horizontal = 6.dp, vertical = 2.dp)
                            ) {
                                Text(
                                    text = "$readLaterCount",
                                    color = Color.White,
                                    fontSize = 10.sp,
                                    fontWeight = FontWeight.Bold
                                )
                            }
                        } else if (tab == NewsSubTab.Favorites && favoritesCount > 0) {
                            Box(
                                modifier = Modifier
                                    .clip(CircleShape)
                                    .background(Color(0xFFFFD700))
                                    .padding(horizontal = 6.dp, vertical = 2.dp)
                            ) {
                                Text(
                                    text = "$favoritesCount",
                                    color = Color.Black,
                                    fontSize = 10.sp,
                                    fontWeight = FontWeight.Bold
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Feed Publication Picker Row
@Composable
private fun FeedPickerRow(
    selectedFeed: FeedSource,
    feeds: List<FeedSource>,
    storiesCount: Int,
    mediumUsername: String?,
    mediumReadingListUrl: String?,
    repository: NewsRepository,
    onSelectFeed: (FeedSource) -> Unit
) {
    var showPickerMenu by remember { mutableStateOf(false) }

    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Box {
            Row(
                modifier = Modifier
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.08f))
                    .border(1.dp, Color.White.copy(alpha = 0.12f), CircleShape)
                    .clickable { showPickerMenu = true }
                    .padding(horizontal = 12.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Icon(
                    imageVector = Icons.Rounded.FormatListBulleted,
                    contentDescription = null,
                    tint = ThemeColors.accentCyan,
                    modifier = Modifier.size(13.dp)
                )

                Text(
                    text = "Source: ${selectedFeed.name}",
                    color = Color.White.copy(alpha = 0.90f),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold
                )

                Icon(
                    imageVector = Icons.Rounded.KeyboardArrowDown,
                    contentDescription = null,
                    tint = ThemeColors.textMuted,
                    modifier = Modifier.size(14.dp)
                )
            }

            DropdownMenu(
                expanded = showPickerMenu,
                onDismissRequest = { showPickerMenu = false },
                modifier = Modifier
                    .background(Color(0xFF0D182E))
                    .border(1.dp, Color.White.copy(alpha = 0.18f), RoundedCornerShape(14.dp))
            ) {
                DropdownMenuItem(
                    text = {
                        Text(
                            text = "All News (Consolidated)",
                            color = Color.White,
                            fontSize = 13.sp,
                            fontWeight = if (selectedFeed.id == "all_news") FontWeight.Bold else FontWeight.Normal
                        )
                    },
                    onClick = {
                        showPickerMenu = false
                        onSelectFeed(repository.allNewsFeedSource)
                    }
                )

                val mediumSource = repository.mediumReadingListFeedSource(mediumUsername, mediumReadingListUrl)
                if (mediumSource != null) {
                    HorizontalDivider(color = Color.White.copy(alpha = 0.12f), modifier = Modifier.padding(vertical = 4.dp))
                    DropdownMenuItem(
                        text = {
                            Text(
                                text = "Medium Reading List",
                                color = Color.White,
                                fontSize = 13.sp,
                                fontWeight = if (selectedFeed.id == mediumSource.id) FontWeight.Bold else FontWeight.Normal
                            )
                        },
                        onClick = {
                            showPickerMenu = false
                            onSelectFeed(mediumSource)
                        }
                    )
                }

                HorizontalDivider(color = Color.White.copy(alpha = 0.12f), modifier = Modifier.padding(vertical = 4.dp))

                feeds.forEach { feed ->
                    DropdownMenuItem(
                        text = {
                            Text(
                                text = feed.name,
                                color = Color.White,
                                fontSize = 13.sp,
                                fontWeight = if (selectedFeed.id == feed.id) FontWeight.Bold else FontWeight.Normal
                            )
                        },
                        onClick = {
                            showPickerMenu = false
                            onSelectFeed(feed)
                        }
                    )
                }
            }
        }

        Text(
            text = "$storiesCount stories",
            color = ThemeColors.textMuted,
            fontSize = 11.sp,
            fontWeight = FontWeight.Medium
        )
    }
}

// MARK: - Empty State
@Composable
private fun EmptyNewsState(
    subTab: NewsSubTab,
    onRefresh: () -> Unit
) {
    GlassCard(cornerRadius = 18.dp, padding = 32.dp) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Icon(
                imageVector = when (subTab) {
                    NewsSubTab.Live -> Icons.Rounded.Newspaper
                    NewsSubTab.ReadLater -> Icons.Rounded.BookmarkRemove
                    NewsSubTab.Favorites -> Icons.Rounded.StarBorder
                },
                contentDescription = null,
                tint = ThemeColors.accentCyan.copy(alpha = 0.75f),
                modifier = Modifier.size(42.dp)
            )

            Text(
                text = when (subTab) {
                    NewsSubTab.Live -> "No Articles Available"
                    NewsSubTab.ReadLater -> "No Read Later Articles"
                    NewsSubTab.Favorites -> "No Favorites Saved"
                },
                color = Color.White,
                fontSize = 16.sp,
                fontWeight = FontWeight.Bold
            )

            Text(
                text = when (subTab) {
                    NewsSubTab.Live -> "Try selecting another feed or pulling to refresh."
                    NewsSubTab.ReadLater, NewsSubTab.Favorites -> "Save articles while reading by tapping the bookmark or star button."
                },
                color = ThemeColors.textSecondary,
                fontSize = 13.sp,
                modifier = Modifier.padding(horizontal = 16.dp),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center
            )

            if (subTab == NewsSubTab.Live) {
                Box(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(ThemeColors.accentCyan.copy(alpha = 0.12f))
                        .border(1.dp, ThemeColors.accentCyan.copy(alpha = 0.25f), CircleShape)
                        .clickable { onRefresh() }
                        .padding(horizontal = 16.dp, vertical = 8.dp)
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.Refresh,
                            contentDescription = null,
                            tint = ThemeColors.accentCyan,
                            modifier = Modifier.size(14.dp)
                        )
                        Text(
                            text = "Refresh Feed",
                            color = ThemeColors.accentCyan,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }
            }
        }
    }
}
