package com.intellidream.daily.database

import com.intellidream.daily.database.dao.NewsDao
import com.intellidream.daily.database.entity.RssSubscriptionEntity
import com.intellidream.daily.database.entity.SavedArticleEntity
import com.intellidream.daily.model.ArticleExtractor
import com.intellidream.daily.model.FeedCategory
import com.intellidream.daily.model.FeedParser
import com.intellidream.daily.model.FeedSearchResult
import com.intellidream.daily.model.FeedSource
import com.intellidream.daily.model.FeedType
import com.intellidream.daily.model.NewsArticle
import com.intellidream.daily.model.RssSubscription
import com.intellidream.daily.model.SavedArticle
import com.intellidream.daily.model.SavedArticleType
import com.intellidream.daily.model.WpJsonParser
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

interface NewsSyncHandler {
    suspend fun fetchUrl(url: String): String?
    suspend fun searchFeedly(query: String): List<FeedSearchResult>
    suspend fun pullSubscriptions(userId: String): List<RssSubscription>
    suspend fun pushSubscription(subscription: RssSubscription): Boolean
    suspend fun pullSavedArticles(userId: String): List<SavedArticle>
    suspend fun pushSavedArticle(article: SavedArticle): Boolean
}

class NewsRepository(
    private val dao: NewsDao,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
) {
    var syncHandler: NewsSyncHandler? = null

    val allNewsFeedSource = FeedSource(
        id = "all_news",
        name = "All News",
        url = "all_news",
        iconUrl = "",
        type = FeedType.Rss,
        category = FeedCategory.All,
        displayOrder = -1
    )

    private val _feeds = MutableStateFlow<List<FeedSource>>(defaultFeeds)
    val feeds: StateFlow<List<FeedSource>> = _feeds.asStateFlow()

    private val _selectedFeed = MutableStateFlow(allNewsFeedSource)
    val selectedFeed: StateFlow<FeedSource> = _selectedFeed.asStateFlow()

    private val _selectedCategory = MutableStateFlow(FeedCategory.All)
    val selectedCategory: StateFlow<FeedCategory> = _selectedCategory.asStateFlow()

    private val _articles = MutableStateFlow<List<NewsArticle>>(emptyList())
    val articles: StateFlow<List<NewsArticle>> = _articles.asStateFlow()

    val topHeadline: StateFlow<NewsArticle?> = _articles.map { it.firstOrNull() }
        .stateIn(scope, SharingStarted.Eagerly, null)

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    private val _readLaterArticles = MutableStateFlow<List<NewsArticle>>(emptyList())
    val readLaterArticles: StateFlow<List<NewsArticle>> = _readLaterArticles.asStateFlow()

    private val _favoriteArticles = MutableStateFlow<List<NewsArticle>>(emptyList())
    val favoriteArticles: StateFlow<List<NewsArticle>> = _favoriteArticles.asStateFlow()

    private val feedCache = ConcurrentHashMap<String, Pair<List<NewsArticle>, Long>>()
    private val cacheDurationMillis = 15 * 60 * 1000L // 15 minutes

    var currentUserId: String = "guest"
        set(value) {
            field = value
            observeDb(value)
        }

    init {
        observeDb(currentUserId)
        scope.launch {
            loadAllNews()
        }
    }

    private fun observeDb(userId: String) {
        if (userId != "guest") {
            scope.launch {
                syncWithSupabase(userId)
            }
        }
        scope.launch {
            dao.observeSubscriptions(userId).collect { entities ->
                if (entities.isNotEmpty()) {
                    _feeds.value = entities.map { it.toFeedSource() }
                } else {
                    // Seed default feeds to Room
                    val seedEntities = defaultFeeds.map { RssSubscriptionEntity.fromFeedSource(it, userId) }
                    dao.upsertSubscriptions(seedEntities)
                    _feeds.value = defaultFeeds
                }
            }
        }

        scope.launch {
            dao.observeSavedArticles(userId, SavedArticleType.ReadLater.value).collect { entities ->
                _readLaterArticles.value = entities.map { it.toNewsArticle() }
            }
        }

        scope.launch {
            dao.observeSavedArticles(userId, SavedArticleType.Favorite.value).collect { entities ->
                _favoriteArticles.value = entities.map { it.toNewsArticle() }
            }
        }
    }

    // MARK: - Feed Loading

    suspend fun selectFeed(feed: FeedSource) {
        _selectedFeed.value = feed
        loadFeed(feed)
    }

    suspend fun selectCategory(category: FeedCategory) {
        _selectedCategory.value = category
        if (category == FeedCategory.All) {
            _selectedFeed.value = allNewsFeedSource
            loadAllNews()
        } else {
            val matchingFeed = _feeds.value.firstOrNull { it.category == category }
            if (matchingFeed != null) {
                _selectedFeed.value = matchingFeed
                loadFeed(matchingFeed)
            } else {
                _selectedFeed.value = allNewsFeedSource
                loadAllNews()
            }
        }
    }

    suspend fun loadFeed(feed: FeedSource, forceRefresh: Boolean = false) = withContext(Dispatchers.IO) {
        if (feed.url == "all_news") {
            loadAllNews(forceRefresh)
            return@withContext
        }

        // Cache check
        if (!forceRefresh) {
            val cached = feedCache[feed.url]
            if (cached != null && cached.first.isNotEmpty() && System.currentTimeMillis() - cached.second < cacheDurationMillis) {
                _articles.value = cached.first
                return@withContext
            }
        }

        _isLoading.value = true
        _errorMessage.value = null

        try {
            val items = fetchFeedItems(feed)
            if (items.isNotEmpty()) {
                feedCache[feed.url] = items to System.currentTimeMillis()
                _articles.value = items
            } else if (_articles.value.isEmpty()) {
                _errorMessage.value = "Failed to load ${feed.name}."
            }
        } catch (e: Exception) {
            if (_articles.value.isEmpty()) {
                _errorMessage.value = "Failed to load ${feed.name}: ${e.message}"
            }
        } finally {
            _isLoading.value = false
        }
    }

    suspend fun loadAllNews(forceRefresh: Boolean = false) = withContext(Dispatchers.IO) {
        if (!forceRefresh) {
            val cached = feedCache["all_news"]
            if (cached != null && cached.first.isNotEmpty() && System.currentTimeMillis() - cached.second < cacheDurationMillis) {
                _articles.value = cached.first
                return@withContext
            }
        }

        _isLoading.value = true
        _errorMessage.value = null

        val activeFeeds = _feeds.value.ifEmpty { defaultFeeds }

        try {
            val aggregated = coroutineScope {
                activeFeeds.map { feed ->
                    async {
                        try {
                            fetchFeedItems(feed).take(3)
                        } catch (_: Exception) {
                            emptyList()
                        }
                    }
                }.awaitAll().flatten()
            }.sortedByDescending { it.publishDate }

            if (aggregated.isNotEmpty()) {
                feedCache["all_news"] = aggregated to System.currentTimeMillis()
                _articles.value = aggregated
            } else if (_articles.value.isEmpty()) {
                _errorMessage.value = "Unable to load latest news briefings."
            }
        } catch (e: Exception) {
            if (_articles.value.isEmpty()) {
                _errorMessage.value = "Unable to load latest news briefings."
            }
        } finally {
            _isLoading.value = false
        }
    }

    private suspend fun fetchFeedItems(feed: FeedSource): List<NewsArticle> = withContext(Dispatchers.IO) {
        val body = syncHandler?.fetchUrl(feed.url) ?: downloadString(feed.url) ?: return@withContext emptyList()

        if (feed.type == FeedType.WpJson || feed.url.contains("wp-json", ignoreCase = true)) {
            val parser = WpJsonParser(feed)
            parser.parse(body)
        } else {
            val parser = FeedParser(feed)
            parser.parse(body)
        }
    }

    suspend fun fetchFullArticle(article: NewsArticle): NewsArticle = withContext(Dispatchers.IO) {
        try {
            val html = syncHandler?.fetchUrl(article.link) ?: downloadString(article.link)
            if (!html.isNullOrBlank()) {
                ArticleExtractor.shared.parseHtml(html, article.link, article)
            } else {
                article
            }
        } catch (_: Exception) {
            article
        }
    }

    private fun downloadString(urlString: String): String? {
        return try {
            val url = URL(urlString)
            val conn = url.openConnection() as HttpURLConnection
            conn.connectTimeout = 8000
            conn.readTimeout = 8000
            conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36")
            conn.setRequestProperty("Accept", "application/rss+xml, application/atom+xml, application/json, text/xml, text/html, */*")
            if (conn.responseCode in 200..299) {
                BufferedReader(InputStreamReader(conn.inputStream, Charsets.UTF_8)).use { it.readText() }
            } else null
        } catch (_: Exception) {
            null
        }
    }

    // MARK: - Medium Reading List & Subscriptions

    fun mediumReadingListFeedSource(username: String?, customUrl: String?): FeedSource? {
        if (username.isNullOrBlank()) return null
        val targetUrl = customUrl ?: "https://medium.com/feed/@${username.trim().removePrefix("@")}"
        return FeedSource(
            id = "medium_reading_list",
            name = "Medium Reading List",
            url = targetUrl,
            iconUrl = "https://cdn-static-1.medium.com/_/fp/icons/favicon-rebrand-medium.37877227.png",
            type = FeedType.Rss,
            category = FeedCategory.Tech,
            displayOrder = 999
        )
    }

    fun isSubscribedToMediumAuthor(username: String): Boolean {
        val clean = username.trim().removePrefix("@").lowercase()
        val feedUrl = "https://medium.com/feed/@$clean"
        return _feeds.value.any { it.url.equals(feedUrl, ignoreCase = true) }
    }

    suspend fun subscribeToMediumAuthor(username: String, authorName: String? = null, userId: String = currentUserId) {
        val clean = username.trim().removePrefix("@")
        if (clean.isBlank()) return
        val feedUrl = "https://medium.com/feed/@${clean.lowercase()}"
        if (_feeds.value.any { it.url.equals(feedUrl, ignoreCase = true) }) return
        val displayName = authorName ?: "@$clean"
        addFeed(name = "Medium: $displayName", url = feedUrl, category = FeedCategory.Tech, userId = userId)
    }

    suspend fun unsubscribeFromMediumAuthor(username: String, userId: String = currentUserId) {
        val clean = username.trim().removePrefix("@").lowercase()
        val feedUrl = "https://medium.com/feed/@$clean"
        val feed = _feeds.value.firstOrNull { it.url.equals(feedUrl, ignoreCase = true) } ?: return
        deleteFeed(feed.id, userId)
    }

    // MARK: - Feed Management

    suspend fun addFeed(name: String, url: String, category: FeedCategory, userId: String = currentUserId) {
        val type = if (url.contains("wp-json", ignoreCase = true)) FeedType.WpJson else FeedType.Rss
        val newFeed = FeedSource(
            name = name,
            url = url,
            type = type,
            category = category,
            displayOrder = _feeds.value.size
        )
        val entity = RssSubscriptionEntity.fromFeedSource(newFeed, userId)
        dao.upsertSubscription(entity)

        syncHandler?.let { handler ->
            scope.launch {
                val sub = RssSubscription(
                    id = entity.id,
                    userId = userId,
                    name = entity.name,
                    url = entity.url,
                    iconUrl = entity.iconUrl,
                    category = entity.category,
                    displayOrder = entity.displayOrder
                )
                if (handler.pushSubscription(sub)) {
                    dao.markSubscriptionsSynced(listOf(entity.id), System.currentTimeMillis())
                }
            }
        }
    }

    suspend fun deleteFeed(id: String, userId: String = currentUserId) {
        dao.markSubscriptionDeleted(id)
        _feeds.value = _feeds.value.filter { it.id != id }
    }

    suspend fun discoverFeeds(query: String): List<FeedSearchResult> {
        return syncHandler?.searchFeedly(query) ?: emptyList()
    }

    // MARK: - Read Later & Favorite Toggles

    fun isReadLater(url: String): Boolean {
        return _readLaterArticles.value.any { it.link == url }
    }

    fun isFavorite(url: String): Boolean {
        return _favoriteArticles.value.any { it.link == url }
    }

    suspend fun toggleReadLater(article: NewsArticle, userId: String = currentUserId) {
        toggleSavedArticle(article, SavedArticleType.ReadLater, userId)
    }

    suspend fun toggleFavorite(article: NewsArticle, userId: String = currentUserId) {
        toggleSavedArticle(article, SavedArticleType.Favorite, userId)
    }

    private suspend fun toggleSavedArticle(article: NewsArticle, type: SavedArticleType, userId: String) {
        val existing = dao.getSavedArticle(userId, article.link, type.value)
        if (existing != null) {
            val updated = existing.copy(
                isDeleted = !existing.isDeleted,
                updatedAt = System.currentTimeMillis(),
                syncedAt = null
            )
            dao.upsertSavedArticle(updated)
            pushSavedArticleToCloud(updated)
        } else {
            val newEntity = SavedArticleEntity.fromNewsArticle(article, userId, type)
            dao.upsertSavedArticle(newEntity)
            pushSavedArticleToCloud(newEntity)
        }
    }

    private fun pushSavedArticleToCloud(entity: SavedArticleEntity) {
        if (entity.userId == "guest") return
        syncHandler?.let { handler ->
            scope.launch {
                val saved = SavedArticle(
                    id = entity.id,
                    userId = entity.userId,
                    articleUrl = entity.articleUrl,
                    title = entity.title,
                    imageUrl = entity.imageUrl,
                    description = entity.description,
                    author = entity.author,
                    publicationName = entity.publicationName,
                    publicationIconUrl = entity.publicationIconUrl,
                    articleType = entity.articleType,
                    articleDate = java.time.Instant.ofEpochMilli(entity.articleDate).toString(),
                    createdAt = java.time.Instant.ofEpochMilli(entity.createdAt).toString(),
                    updatedAt = entity.updatedAt?.let { java.time.Instant.ofEpochMilli(it).toString() },
                    isDeleted = entity.isDeleted
                )
                if (handler.pushSavedArticle(saved)) {
                    dao.markSavedArticlesSynced(listOf(entity.id), System.currentTimeMillis())
                }
            }
        }
    }

    // MARK: - Supabase Synchronization

    suspend fun syncWithSupabase(userId: String) = withContext(Dispatchers.IO) {
        if (userId == "guest") return@withContext
        val handler = syncHandler ?: return@withContext

        try {
            // 1. Sync Subscriptions
            val remoteSubs = handler.pullSubscriptions(userId)
            if (remoteSubs.isNotEmpty()) {
                val localEntities = dao.getSubscriptions(userId)
                val localMap = localEntities.associateBy { it.url.lowercase() }

                val toInsert = mutableListOf<RssSubscriptionEntity>()
                for (remote in remoteSubs) {
                    val local = localMap[remote.url.lowercase()]
                    if (local == null) {
                        toInsert.add(
                            RssSubscriptionEntity(
                                id = remote.id,
                                userId = userId,
                                name = remote.name,
                                url = remote.url,
                                iconUrl = remote.iconUrl,
                                category = remote.category,
                                displayOrder = remote.displayOrder,
                                isDeleted = remote.isDeleted,
                                createdAt = System.currentTimeMillis(),
                                syncedAt = System.currentTimeMillis()
                            )
                        )
                    }
                }
                if (toInsert.isNotEmpty()) {
                    dao.upsertSubscriptions(toInsert)
                }
            }

            // 2. Push unsynced subscriptions
            val unsyncedSubs = dao.getUnsyncedSubscriptions()
            for (sub in unsyncedSubs) {
                val model = RssSubscription(
                    id = sub.id,
                    userId = sub.userId,
                    name = sub.name,
                    url = sub.url,
                    iconUrl = sub.iconUrl,
                    category = sub.category,
                    displayOrder = sub.displayOrder,
                    isDeleted = sub.isDeleted
                )
                if (handler.pushSubscription(model)) {
                    dao.markSubscriptionsSynced(listOf(sub.id), System.currentTimeMillis())
                }
            }

            // 3. Sync Saved Articles
            val remoteSaved = handler.pullSavedArticles(userId)
            if (remoteSaved.isNotEmpty()) {
                val localArticles = dao.getAllSavedArticles(userId)
                val localMap = localArticles.associateBy { it.id.lowercase() }

                val toUpsert = mutableListOf<SavedArticleEntity>()
                for (remote in remoteSaved) {
                    val local = localMap[remote.id.lowercase()]
                    if (local == null) {
                        toUpsert.add(
                            SavedArticleEntity(
                                id = remote.id,
                                userId = userId,
                                articleUrl = remote.articleUrl,
                                title = remote.title,
                                imageUrl = remote.imageUrl,
                                description = remote.description,
                                author = remote.author,
                                publicationName = remote.publicationName,
                                publicationIconUrl = remote.publicationIconUrl,
                                articleType = remote.articleType,
                                articleDate = try { java.time.Instant.parse(remote.articleDate).toEpochMilli() } catch (_: Exception) { System.currentTimeMillis() },
                                isDeleted = remote.isDeleted,
                                createdAt = try { java.time.Instant.parse(remote.createdAt).toEpochMilli() } catch (_: Exception) { System.currentTimeMillis() },
                                syncedAt = System.currentTimeMillis()
                            )
                        )
                    }
                }
                if (toUpsert.isNotEmpty()) {
                    dao.upsertSavedArticles(toUpsert)
                }
            }

            // 4. Push unsynced saved articles
            val unsyncedArticles = dao.getUnsyncedSavedArticles()
            for (art in unsyncedArticles) {
                val model = SavedArticle(
                    id = art.id,
                    userId = art.userId,
                    articleUrl = art.articleUrl,
                    title = art.title,
                    imageUrl = art.imageUrl,
                    description = art.description,
                    author = art.author,
                    publicationName = art.publicationName,
                    publicationIconUrl = art.publicationIconUrl,
                    articleType = art.articleType,
                    articleDate = java.time.Instant.ofEpochMilli(art.articleDate).toString(),
                    createdAt = java.time.Instant.ofEpochMilli(art.createdAt).toString(),
                    updatedAt = art.updatedAt?.let { java.time.Instant.ofEpochMilli(it).toString() },
                    isDeleted = art.isDeleted
                )
                if (handler.pushSavedArticle(model)) {
                    dao.markSavedArticlesSynced(listOf(art.id), System.currentTimeMillis())
                }
            }
        } catch (_: Exception) {}
    }

    companion object {
        val defaultFeeds: List<FeedSource> = listOf(
            // 🇷🇴 Local
            FeedSource(name = "Republica", url = "https://republica.ro/rss", category = FeedCategory.Local, displayOrder = 0),
            FeedSource(name = "Digi24", url = "https://www.digi24.ro/rss", category = FeedCategory.Local, displayOrder = 1),
            FeedSource(name = "Ziarul Financiar", url = "https://www.zf.ro/rss/", category = FeedCategory.Local, displayOrder = 2),
            FeedSource(name = "HotNews", url = "https://www.hotnews.ro/rss", category = FeedCategory.Local, displayOrder = 3),
            FeedSource(name = "Biziday", url = "https://www.biziday.ro/feed/", category = FeedCategory.Local, displayOrder = 4),
            FeedSource(name = "Economica.net", url = "https://www.economica.net/rss", category = FeedCategory.Local, displayOrder = 5),

            // 📈 Markets
            FeedSource(name = "CNBC", url = "https://www.cnbc.com/id/100003114/device/rss/rss.html", category = FeedCategory.Markets, displayOrder = 6),
            FeedSource(name = "The Economist", url = "https://www.economist.com/finance-and-economics/rss.xml", category = FeedCategory.Markets, displayOrder = 7),

            // 🌍 World
            FeedSource(name = "BBC News", url = "https://feeds.bbci.co.uk/news/rss.xml", category = FeedCategory.World, displayOrder = 8),
            FeedSource(name = "NPR", url = "https://feeds.npr.org/1001/rss.xml", category = FeedCategory.World, displayOrder = 9),
            FeedSource(name = "Politico Europe", url = "https://www.politico.eu/feed/", category = FeedCategory.World, displayOrder = 10),
            FeedSource(name = "Deutsche Welle", url = "https://rss.dw.com/rdf/rss-en-all", category = FeedCategory.World, displayOrder = 11),
            FeedSource(name = "Google News", url = "https://news.google.com/rss?hl=en-US&gl=US&ceid=US:en", category = FeedCategory.World, displayOrder = 12),

            // 💡 Tech
            FeedSource(name = "TechCrunch", url = "https://techcrunch.com/feed/", category = FeedCategory.Tech, displayOrder = 13),
            FeedSource(name = "The Verge", url = "https://www.theverge.com/rss/index.xml", category = FeedCategory.Tech, displayOrder = 14),
            FeedSource(name = "Ars Technica", url = "https://feeds.arstechnica.com/arstechnica/index", category = FeedCategory.Tech, displayOrder = 15),
            FeedSource(name = "Zona IT", url = "https://zonait.ro/wp-json/wp/v2/posts?per_page=20&_embed", type = FeedType.WpJson, category = FeedCategory.Tech, displayOrder = 16),
            FeedSource(name = "Windows Central", url = "https://www.windowscentral.com/feeds.xml", category = FeedCategory.Tech, displayOrder = 17)
        )
    }
}
