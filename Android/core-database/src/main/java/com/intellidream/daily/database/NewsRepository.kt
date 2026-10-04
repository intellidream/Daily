package com.intellidream.daily.database

import com.intellidream.daily.database.dao.NewsDao
import com.intellidream.daily.database.entity.CachedFeedArticleEntity
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
    var syncHandler: NewsSyncHandler? = null,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
) {

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

    private var syncJob: kotlinx.coroutines.Job? = null
    private var subsJob: kotlinx.coroutines.Job? = null
    private var readLaterJob: kotlinx.coroutines.Job? = null
    private var favoritesJob: kotlinx.coroutines.Job? = null

    var currentUserId: String = "guest"
        set(value) {
            field = value
            observeDb(value)
        }

    init {
        observeDb(currentUserId)
        scope.launch {
            val localCached = dao.getAllCachedArticles()
            if (localCached.isNotEmpty()) {
                val articles = localCached.map { it.toNewsArticle() }
                _articles.value = articles
                feedCache["all_news"] = articles to System.currentTimeMillis()
            }
            loadAllNews()
        }
    }

    private fun observeDb(userId: String) {
        syncJob?.cancel()
        subsJob?.cancel()
        readLaterJob?.cancel()
        favoritesJob?.cancel()

        if (userId != "guest") {
            syncJob = scope.launch {
                syncWithSupabase(userId)
            }
        }
        subsJob = scope.launch {
            dao.observeSubscriptions(userId).collect { entities ->
                if (entities.isNotEmpty()) {
                    // Group by normalized URL to detect and heal any duplicate entries in Room
                    val grouped = entities.groupBy { normalizeFeedUrl(it.url) }
                    val distinctEntities = mutableListOf<RssSubscriptionEntity>()
                    val redundantIds = mutableListOf<String>()

                    for ((_, group) in grouped) {
                        if (group.size == 1) {
                            distinctEntities.add(group.first())
                        } else {
                            // Pick preferred entity: remote Supabase ID (not starting with "seed_") or first
                            val preferred = group.firstOrNull { !it.id.startsWith("seed_") } ?: group.first()
                            distinctEntities.add(preferred)
                            group.filter { it.id != preferred.id }.forEach { redundantIds.add(it.id) }
                        }
                    }

                    if (redundantIds.isNotEmpty()) {
                        scope.launch {
                            for (id in redundantIds) {
                                dao.deleteSubscriptionPermanently(id)
                            }
                        }
                    }

                    _feeds.value = distinctEntities.map { entity ->
                        val feed = entity.toFeedSource()
                        if (feed.url.contains("economica.net/rss")) {
                            feed.copy(url = "https://www.economica.net/feed")
                        } else {
                            feed
                        }
                    }
                } else {
                    // Seed default feeds to Room
                    val seedEntities = defaultFeeds.map { RssSubscriptionEntity.fromFeedSource(it, userId) }
                    dao.upsertSubscriptions(seedEntities)
                    _feeds.value = defaultFeeds
                }
            }
        }

        readLaterJob = scope.launch {
            dao.observeSavedArticles(userId, SavedArticleType.ReadLater.value).collect { entities ->
                _readLaterArticles.value = entities.map { it.toNewsArticle() }
            }
        }

        favoritesJob = scope.launch {
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

        // 1. In-memory cache check
        if (!forceRefresh) {
            val cached = feedCache[feed.url]
            if (cached != null && cached.first.isNotEmpty() && System.currentTimeMillis() - cached.second < cacheDurationMillis) {
                _articles.value = cached.first
                return@withContext
            }
            // 2. Room local cache fallback
            val localRoom = dao.getCachedArticlesForFeed(feed.url)
            if (localRoom.isNotEmpty()) {
                val models = localRoom.map { it.toNewsArticle() }
                feedCache[feed.url] = models to System.currentTimeMillis()
                _articles.value = models
            }
        }

        _isLoading.value = _articles.value.isEmpty()
        _errorMessage.value = null

        try {
            val items = kotlinx.coroutines.withTimeoutOrNull(8000L) {
                fetchFeedItems(feed)
            } ?: emptyList()
            if (items.isNotEmpty()) {
                feedCache[feed.url] = items to System.currentTimeMillis()
                _articles.value = items
                dao.upsertCachedArticles(items.map { CachedFeedArticleEntity.fromNewsArticle(it, feed.url) })
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
            if (cached != null && cached.first.isNotEmpty()) {
                _articles.value = cached.first
                if (System.currentTimeMillis() - cached.second < cacheDurationMillis) {
                    return@withContext
                }
            } else {
                val localRoom = dao.getAllCachedArticles()
                if (localRoom.isNotEmpty()) {
                    val models = localRoom.map { it.toNewsArticle() }
                    feedCache["all_news"] = models to System.currentTimeMillis()
                    _articles.value = models
                }
            }
        }

        _isLoading.value = _articles.value.isEmpty()
        _errorMessage.value = null

        val activeFeeds = _feeds.value.ifEmpty { defaultFeeds }

        try {
            val aggregated = coroutineScope {
                activeFeeds.map { feed ->
                    async {
                        try {
                            kotlinx.coroutines.withTimeoutOrNull(8000L) {
                                fetchFeedItems(feed).take(4)
                            } ?: emptyList()
                        } catch (_: Throwable) {
                            emptyList()
                        }
                    }
                }.awaitAll().flatten()
            }.sortedByDescending { it.publishDate }

            if (aggregated.isNotEmpty()) {
                feedCache["all_news"] = aggregated to System.currentTimeMillis()
                _articles.value = aggregated
                dao.upsertCachedArticles(aggregated.map { CachedFeedArticleEntity.fromNewsArticle(it, "all_news") })
            } else if (_articles.value.isEmpty()) {
                _errorMessage.value = "Unable to load latest news briefings."
            }
        } catch (e: Throwable) {
            if (_articles.value.isEmpty()) {
                _errorMessage.value = "Unable to load latest news briefings."
            }
        } finally {
            _isLoading.value = false
        }
    }

    private suspend fun fetchFeedItems(feed: FeedSource): List<NewsArticle> = withContext(Dispatchers.IO) {
        val targetUrl = when {
            feed.url.contains("economica.net/rss") -> "https://www.economica.net/feed"
            else -> feed.url
        }
        val body = syncHandler?.fetchUrl(targetUrl) ?: downloadString(targetUrl) ?: return@withContext emptyList()

        try {
            if (feed.type == FeedType.WpJson || targetUrl.contains("wp-json", ignoreCase = true)) {
                val parser = WpJsonParser(feed)
                parser.parse(body)
            } else {
                val parser = FeedParser(feed)
                parser.parse(body)
            }
        } catch (_: Throwable) {
            emptyList()
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
        } catch (_: Throwable) {
            article
        }
    }

    private fun downloadString(urlString: String): String? {
        var currentUrl = urlString
        var redirects = 0
        while (redirects < 5) {
            var conn: HttpURLConnection? = null
            try {
                val url = URL(currentUrl)
                conn = url.openConnection() as HttpURLConnection
                conn.instanceFollowRedirects = true
                conn.connectTimeout = 8000
                conn.readTimeout = 10000
                conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 15; Pixel 9 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36")
                conn.setRequestProperty("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8,application/rss+xml,application/atom+xml,application/json")
                conn.setRequestProperty("Accept-Language", "ro-RO,ro;q=0.9,en-US;q=0.8,en;q=0.7")
                val responseCode = conn.responseCode
                if (responseCode in 300..399) {
                    val location = conn.getHeaderField("Location")
                    if (!location.isNullOrBlank()) {
                        currentUrl = if (location.startsWith("http://") || location.startsWith("https://")) {
                            location
                        } else {
                            URL(url, location).toString()
                        }
                        redirects++
                        continue
                    }
                }
                if (responseCode in 200..299) {
                    val rawStream = conn.inputStream
                    val isGzip = "gzip".equals(conn.contentEncoding, ignoreCase = true)
                    val inStream = if (isGzip) java.util.zip.GZIPInputStream(rawStream) else rawStream

                    val contentType = conn.contentType ?: ""
                    val charset = extractCharset(contentType) ?: Charsets.UTF_8

                    return BufferedReader(InputStreamReader(inStream, charset)).use { it.readText() }
                } else {
                    return null
                }
            } catch (_: Exception) {
                return null
            } finally {
                try { conn?.disconnect() } catch (_: Exception) {}
            }
        }
        return null
    }

    private fun extractCharset(contentType: String): java.nio.charset.Charset? {
        val parts = contentType.split(";")
        for (part in parts) {
            val trimmed = part.trim()
            if (trimmed.startsWith("charset=", ignoreCase = true)) {
                val name = trimmed.substring("charset=".length).trim('"', '\'')
                try {
                    return java.nio.charset.Charset.forName(name)
                } catch (_: Exception) {}
            }
        }
        return null
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
        val norm = normalizeFeedUrl(url)
        val existing = _feeds.value.firstOrNull { normalizeFeedUrl(it.url) == norm }
        if (existing != null) {
            return
        }
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
                val localMap = localEntities.associateBy { normalizeFeedUrl(it.url) }

                val toInsert = mutableListOf<RssSubscriptionEntity>()
                val obsoleteLocalIds = mutableListOf<String>()

                for (remote in remoteSubs) {
                    val normUrl = normalizeFeedUrl(remote.url)
                    val local = localMap[normUrl]
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
                    } else if (local.id != remote.id) {
                        obsoleteLocalIds.add(local.id)
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
                                createdAt = local.createdAt,
                                syncedAt = System.currentTimeMillis()
                            )
                        )
                    } else if (local.isDeleted != remote.isDeleted || local.name != remote.name) {
                        toInsert.add(
                            local.copy(
                                name = remote.name,
                                isDeleted = remote.isDeleted,
                                category = remote.category,
                                displayOrder = remote.displayOrder,
                                syncedAt = System.currentTimeMillis()
                            )
                        )
                    }
                }
                for (oldId in obsoleteLocalIds) {
                    dao.deleteSubscriptionPermanently(oldId)
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
                    if (local == null || local.isDeleted != remote.isDeleted || local.articleType != remote.articleType) {
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

    fun normalizeFeedUrl(url: String): String = Companion.normalizeFeedUrl(url)

    companion object {
        fun normalizeFeedUrl(url: String): String {
            var u = url.trim().lowercase()
            if (u.endsWith("/")) {
                u = u.dropLast(1)
            }
            if (u.contains("economica.net/rss")) {
                u = u.replace("economica.net/rss", "economica.net/feed")
            }
            return u
        }

        val defaultFeeds: List<FeedSource> = listOf(
            // 🇷🇴 Local
            FeedSource(id = "seed_republica", name = "Republica", url = "https://republica.ro/rss", category = FeedCategory.Local, displayOrder = 0),
            FeedSource(id = "seed_digi24", name = "Digi24", url = "https://www.digi24.ro/rss", category = FeedCategory.Local, displayOrder = 1),
            FeedSource(id = "seed_zf", name = "Ziarul Financiar", url = "https://www.zf.ro/rss/", category = FeedCategory.Local, displayOrder = 2),
            FeedSource(id = "seed_hotnews", name = "HotNews", url = "https://www.hotnews.ro/rss", category = FeedCategory.Local, displayOrder = 3),
            FeedSource(id = "seed_biziday", name = "Biziday", url = "https://www.biziday.ro/feed/", category = FeedCategory.Local, displayOrder = 4),
            FeedSource(id = "seed_economica", name = "Economica.net", url = "https://www.economica.net/feed", category = FeedCategory.Local, displayOrder = 5),

            // 📈 Markets
            FeedSource(id = "seed_cnbc", name = "CNBC", url = "https://www.cnbc.com/id/100003114/device/rss/rss.html", category = FeedCategory.Markets, displayOrder = 6),
            FeedSource(id = "seed_economist", name = "The Economist", url = "https://www.economist.com/finance-and-economics/rss.xml", category = FeedCategory.Markets, displayOrder = 7),

            // 🌍 World
            FeedSource(id = "seed_bbc", name = "BBC News", url = "https://feeds.bbci.co.uk/news/rss.xml", category = FeedCategory.World, displayOrder = 8),
            FeedSource(id = "seed_npr", name = "NPR", url = "https://feeds.npr.org/1001/rss.xml", category = FeedCategory.World, displayOrder = 9),
            FeedSource(id = "seed_politico", name = "Politico Europe", url = "https://www.politico.eu/feed/", category = FeedCategory.World, displayOrder = 10),
            FeedSource(id = "seed_dw", name = "Deutsche Welle", url = "https://rss.dw.com/rdf/rss-en-all", category = FeedCategory.World, displayOrder = 11),
            FeedSource(id = "seed_google_news", name = "Google News", url = "https://news.google.com/rss?hl=en-US&gl=US&ceid=US:en", category = FeedCategory.World, displayOrder = 12),

            // 💡 Tech
            FeedSource(id = "seed_techcrunch", name = "TechCrunch", url = "https://techcrunch.com/feed/", category = FeedCategory.Tech, displayOrder = 13),
            FeedSource(id = "seed_theverge", name = "The Verge", url = "https://www.theverge.com/rss/index.xml", category = FeedCategory.Tech, displayOrder = 14),
            FeedSource(id = "seed_arstechnica", name = "Ars Technica", url = "https://feeds.arstechnica.com/arstechnica/index", category = FeedCategory.Tech, displayOrder = 15),
            FeedSource(id = "seed_zonait", name = "Zona IT", url = "https://zonait.ro/wp-json/wp/v2/posts?per_page=20&_embed", type = FeedType.WpJson, category = FeedCategory.Tech, displayOrder = 16),
            FeedSource(id = "seed_windowscentral", name = "Windows Central", url = "https://www.windowscentral.com/feeds.xml", category = FeedCategory.Tech, displayOrder = 17)
        )
    }
}
