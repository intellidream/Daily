package com.intellidream.daily.presentation.news

import androidx.compose.animation.AnimatedVisibility
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
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Clear
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.KeyboardArrowUp
import androidx.compose.material.icons.rounded.RssFeed
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.intellidream.daily.database.NewsRepository
import com.intellidream.daily.designsystem.DailyAsyncImage
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.FeedCategory
import com.intellidream.daily.model.FeedSearchResult
import com.intellidream.daily.model.FeedType
import kotlinx.coroutines.launch

@Composable
fun NewsFeedsManagementSheet(
    repository: NewsRepository,
    onDismiss: () -> Unit
) {
    val feeds by repository.feeds.collectAsState()
    val scope = rememberCoroutineScope()
    val haptic = LocalHapticFeedback.current

    var searchQuery by remember { mutableStateOf("") }
    var searchResults by remember { mutableStateOf<List<FeedSearchResult>>(emptyList()) }
    var isSearching by remember { mutableStateOf(false) }

    var isAddingCustom by remember { mutableStateOf(false) }
    var customName by remember { mutableStateOf("") }
    var customUrl by remember { mutableStateOf("") }
    var customCategory by remember { mutableStateOf(FeedCategory.Tech) }
    var showCategoryDropdown by remember { mutableStateOf(false) }

    fun performSearch() {
        if (searchQuery.isBlank()) return
        isSearching = true
        scope.launch {
            searchResults = repository.discoverFeeds(searchQuery)
            isSearching = false
        }
    }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color(0xFF070E1A))
                .statusBarsPadding()
                .navigationBarsPadding()
        ) {
            Column(modifier = Modifier.fillMaxSize()) {
                // Top Header Bar
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = "Manage Feeds",
                        color = Color.White,
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold
                    )

                    TextButton(onClick = onDismiss) {
                        Text(
                            text = "Done",
                            color = ThemeColors.accentCyan,
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }

                // Scrollable Content
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = 20.dp, vertical = 8.dp),
                    verticalArrangement = Arrangement.spacedBy(18.dp)
                ) {
                    // Discovery Search Box
                    GlassCard(cornerRadius = 16.dp, padding = 6.dp) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 8.dp, vertical = 4.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Icon(
                                imageVector = Icons.Rounded.Search,
                                contentDescription = null,
                                tint = ThemeColors.textMuted,
                                modifier = Modifier.size(18.dp)
                            )

                            OutlinedTextField(
                                value = searchQuery,
                                onValueChange = { searchQuery = it },
                                placeholder = {
                                    Text(
                                        text = "Search feeds or enter URL...",
                                        color = ThemeColors.textMuted,
                                        fontSize = 13.sp
                                    )
                                },
                                singleLine = true,
                                keyboardOptions = KeyboardOptions(
                                    keyboardType = KeyboardType.Uri,
                                    imeAction = ImeAction.Search
                                ),
                                keyboardActions = KeyboardActions(onSearch = { performSearch() }),
                                colors = OutlinedTextFieldDefaults.colors(
                                    focusedTextColor = Color.White,
                                    unfocusedTextColor = Color.White,
                                    focusedBorderColor = Color.Transparent,
                                    unfocusedBorderColor = Color.Transparent,
                                    focusedContainerColor = Color.Transparent,
                                    unfocusedContainerColor = Color.Transparent
                                ),
                                modifier = Modifier.weight(1f)
                            )

                            if (searchQuery.isNotEmpty()) {
                                IconButton(
                                    onClick = {
                                        searchQuery = ""
                                        searchResults = emptyList()
                                    },
                                    modifier = Modifier.size(24.dp)
                                ) {
                                    Icon(
                                        imageVector = Icons.Rounded.Clear,
                                        contentDescription = "Clear",
                                        tint = ThemeColors.textMuted,
                                        modifier = Modifier.size(16.dp)
                                    )
                                }
                            }

                            TextButton(onClick = { performSearch() }) {
                                Text(
                                    text = "Search",
                                    color = ThemeColors.accentCyan,
                                    fontSize = 13.sp,
                                    fontWeight = FontWeight.Bold
                                )
                            }
                        }
                    }

                    // Searching progress
                    if (isSearching) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 16.dp),
                            horizontalArrangement = Arrangement.Center,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            CircularProgressIndicator(
                                color = ThemeColors.accentCyan,
                                strokeWidth = 2.5.dp,
                                modifier = Modifier.size(20.dp)
                            )
                            Spacer(modifier = Modifier.width(10.dp))
                            Text(
                                text = "Searching Feedly & Websites...",
                                color = ThemeColors.textSecondary,
                                fontSize = 13.sp
                            )
                        }
                    }

                    // Discovered Feeds
                    if (searchResults.isNotEmpty()) {
                        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            Text(
                                text = "DISCOVERED FEEDS",
                                color = ThemeColors.accentCyan,
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold,
                                letterSpacing = 0.6.sp
                            )

                            searchResults.forEach { result ->
                                val isSubscribed = feeds.any { it.url == result.url }

                                GlassCard(cornerRadius = 14.dp, padding = 12.dp) {
                                    Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                                    ) {
                                        if (result.iconUrl.isNotBlank()) {
                                            DailyAsyncImage(
                                                url = result.iconUrl,
                                                contentDescription = null,
                                                modifier = Modifier
                                                    .size(28.dp)
                                                    .clip(CircleShape),
                                                contentScale = ContentScale.Crop
                                            )
                                        } else {
                                            Icon(
                                                imageVector = Icons.Rounded.RssFeed,
                                                contentDescription = null,
                                                tint = ThemeColors.accentCyan,
                                                modifier = Modifier.size(28.dp)
                                            )
                                        }

                                        Column(modifier = Modifier.weight(1f)) {
                                            Text(
                                                text = result.name,
                                                color = Color.White,
                                                fontSize = 13.sp,
                                                fontWeight = FontWeight.SemiBold,
                                                maxLines = 1,
                                                overflow = TextOverflow.Ellipsis
                                            )
                                            Text(
                                                text = result.url,
                                                color = ThemeColors.textMuted,
                                                fontSize = 10.sp,
                                                maxLines = 1,
                                                overflow = TextOverflow.Ellipsis
                                            )
                                        }

                                        if (isSubscribed) {
                                            Icon(
                                                imageVector = Icons.Rounded.CheckCircle,
                                                contentDescription = "Subscribed",
                                                tint = ThemeColors.accentCyan,
                                                modifier = Modifier.size(20.dp)
                                            )
                                        } else {
                                            Box(
                                                modifier = Modifier
                                                    .clip(CircleShape)
                                                    .background(ThemeColors.accentCyan.copy(alpha = 0.15f))
                                                    .border(1.dp, ThemeColors.accentCyan.copy(alpha = 0.30f), CircleShape)
                                                    .clickable {
                                                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                                        scope.launch {
                                                            repository.addFeed(result.name, result.url, FeedCategory.Other)
                                                        }
                                                    }
                                                    .padding(horizontal = 10.dp, vertical = 5.dp)
                                            ) {
                                                Text(
                                                    text = "Subscribe",
                                                    color = ThemeColors.accentCyan,
                                                    fontSize = 11.sp,
                                                    fontWeight = FontWeight.Bold
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Custom Feed Card
                    GlassCard(cornerRadius = 16.dp, padding = 16.dp) {
                        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Icon(
                                        imageVector = Icons.Rounded.Add,
                                        contentDescription = null,
                                        tint = ThemeColors.accentBlue,
                                        modifier = Modifier.size(18.dp)
                                    )
                                    Spacer(modifier = Modifier.width(6.dp))
                                    Text(
                                        text = "Add Custom Feed",
                                        color = Color.White,
                                        fontSize = 14.sp,
                                        fontWeight = FontWeight.Bold
                                    )
                                }

                                TextButton(onClick = { isAddingCustom = !isAddingCustom }) {
                                    Text(
                                        text = if (isAddingCustom) "Cancel" else "Open",
                                        color = ThemeColors.accentCyan,
                                        fontSize = 12.sp,
                                        fontWeight = FontWeight.SemiBold
                                    )
                                }
                            }

                            AnimatedVisibility(visible = isAddingCustom) {
                                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                    OutlinedTextField(
                                        value = customName,
                                        onValueChange = { customName = it },
                                        placeholder = { Text("Feed Name (e.g. Tech Weekly)", color = ThemeColors.textMuted, fontSize = 13.sp) },
                                        singleLine = true,
                                        colors = OutlinedTextFieldDefaults.colors(
                                            focusedTextColor = Color.White,
                                            unfocusedTextColor = Color.White,
                                            focusedBorderColor = ThemeColors.accentCyan,
                                            unfocusedBorderColor = Color.White.copy(alpha = 0.15f),
                                            focusedContainerColor = Color.White.copy(alpha = 0.05f),
                                            unfocusedContainerColor = Color.White.copy(alpha = 0.03f)
                                        ),
                                        shape = RoundedCornerShape(12.dp),
                                        modifier = Modifier.fillMaxWidth()
                                    )

                                    OutlinedTextField(
                                        value = customUrl,
                                        onValueChange = { customUrl = it },
                                        placeholder = { Text("Feed or WP-JSON URL", color = ThemeColors.textMuted, fontSize = 13.sp) },
                                        singleLine = true,
                                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                                        colors = OutlinedTextFieldDefaults.colors(
                                            focusedTextColor = Color.White,
                                            unfocusedTextColor = Color.White,
                                            focusedBorderColor = ThemeColors.accentCyan,
                                            unfocusedBorderColor = Color.White.copy(alpha = 0.15f),
                                            focusedContainerColor = Color.White.copy(alpha = 0.05f),
                                            unfocusedContainerColor = Color.White.copy(alpha = 0.03f)
                                        ),
                                        shape = RoundedCornerShape(12.dp),
                                        modifier = Modifier.fillMaxWidth()
                                    )

                                    // Category selector
                                    Box {
                                        Row(
                                            modifier = Modifier
                                                .fillMaxWidth()
                                                .clip(RoundedCornerShape(12.dp))
                                                .background(Color.White.copy(alpha = 0.04f))
                                                .border(1.dp, Color.White.copy(alpha = 0.15f), RoundedCornerShape(12.dp))
                                                .clickable { showCategoryDropdown = true }
                                                .padding(horizontal = 14.dp, vertical = 12.dp),
                                            verticalAlignment = Alignment.CenterVertically,
                                            horizontalArrangement = Arrangement.SpaceBetween
                                        ) {
                                            Text(
                                                text = "Category: ${customCategory.displayName}",
                                                color = Color.White,
                                                fontSize = 13.sp
                                            )
                                            Icon(
                                                imageVector = if (showCategoryDropdown) Icons.Rounded.KeyboardArrowUp else Icons.Rounded.KeyboardArrowDown,
                                                contentDescription = null,
                                                tint = ThemeColors.textMuted,
                                                modifier = Modifier.size(16.dp)
                                            )
                                        }

                                        DropdownMenu(
                                            expanded = showCategoryDropdown,
                                            onDismissRequest = { showCategoryDropdown = false },
                                            modifier = Modifier
                                                .background(Color(0xFF0D182E))
                                                .border(1.dp, Color.White.copy(alpha = 0.18f), RoundedCornerShape(14.dp))
                                        ) {
                                            FeedCategory.entries.filter { it != FeedCategory.All }.forEach { cat ->
                                                DropdownMenuItem(
                                                    text = { Text(cat.displayName, color = Color.White, fontSize = 13.sp) },
                                                    onClick = {
                                                        customCategory = cat
                                                        showCategoryDropdown = false
                                                    }
                                                )
                                            }
                                        }
                                    }

                                    // Save Button
                                    Box(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .clip(RoundedCornerShape(12.dp))
                                            .background(
                                                Brush.horizontalGradient(
                                                    listOf(ThemeColors.accentBlue, ThemeColors.accentCyan)
                                                )
                                            )
                                            .clickable {
                                                if (customName.isNotBlank() && customUrl.isNotBlank()) {
                                                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                                    scope.launch {
                                                        repository.addFeed(customName.trim(), customUrl.trim(), customCategory)
                                                        customName = ""
                                                        customUrl = ""
                                                        isAddingCustom = false
                                                    }
                                                }
                                            }
                                            .padding(vertical = 12.dp),
                                        contentAlignment = Alignment.Center
                                    ) {
                                        Text(
                                            text = "Save Feed Subscription",
                                            color = Color.White,
                                            fontSize = 14.sp,
                                            fontWeight = FontWeight.Bold
                                        )
                                    }
                                }
                            }
                        }
                    }

                    // Subscriptions List
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text(
                            text = "YOUR SUBSCRIPTIONS (${feeds.size})",
                            color = ThemeColors.accentCyan,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold,
                            letterSpacing = 0.6.sp
                        )

                        feeds.forEach { feed ->
                            GlassCard(cornerRadius = 14.dp, padding = 12.dp) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                                ) {
                                    if (feed.resolvedIconUrl.isNotBlank()) {
                                        DailyAsyncImage(
                                            url = feed.resolvedIconUrl,
                                            contentDescription = null,
                                            modifier = Modifier
                                                .size(24.dp)
                                                .clip(CircleShape),
                                            contentScale = ContentScale.Crop
                                        )
                                    }

                                    Column(modifier = Modifier.weight(1f)) {
                                        Text(
                                            text = feed.name,
                                            color = Color.White,
                                            fontSize = 14.sp,
                                            fontWeight = FontWeight.SemiBold,
                                            maxLines = 1,
                                            overflow = TextOverflow.Ellipsis
                                        )

                                        Row(
                                            verticalAlignment = Alignment.CenterVertically,
                                            horizontalArrangement = Arrangement.spacedBy(6.dp)
                                        ) {
                                            Text(
                                                text = feed.category.displayName,
                                                color = ThemeColors.accentCyan,
                                                fontSize = 10.sp,
                                                fontWeight = FontWeight.Bold
                                            )
                                            Text(text = "•", color = ThemeColors.textMuted, fontSize = 8.sp)
                                            Text(
                                                text = if (feed.type == FeedType.WpJson) "WordPress JSON" else "RSS / Atom",
                                                color = ThemeColors.textMuted,
                                                fontSize = 10.sp
                                            )
                                        }
                                    }

                                    IconButton(
                                        onClick = {
                                            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                            scope.launch {
                                                repository.deleteFeed(feed.id)
                                            }
                                        },
                                        modifier = Modifier
                                            .size(28.dp)
                                            .clip(CircleShape)
                                            .background(Color.White.copy(alpha = 0.06f))
                                    ) {
                                        Icon(
                                            imageVector = Icons.Rounded.Delete,
                                            contentDescription = "Delete",
                                            tint = Color(0xFFFF5252).copy(alpha = 0.85f),
                                            modifier = Modifier.size(15.dp)
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
