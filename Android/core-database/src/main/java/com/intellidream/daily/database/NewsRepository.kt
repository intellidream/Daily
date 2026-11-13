package com.intellidream.daily.database

import com.intellidream.daily.database.dao.NewsDao
import com.intellidream.daily.database.entity.CachedFeedArticleEntity
import com.intellidream.daily.database.entity.RssSubscriptionEntity
import com.intellidream.daily.database.entity.SavedArticleEntity
import com.intellidream.daily.model.ArticleExtractor
import com.intellidream.daily.model.ArticleFramingTag
import com.intellidream.daily.model.FeedCategory
import com.intellidream.daily.model.FeedParser
import com.intellidream.daily.model.FeedSearchResult
import com.intellidream.daily.model.FeedSource
import com.intellidream.daily.model.FeedType
import com.intellidream.daily.model.FramingDifferenceItem
import com.intellidream.daily.model.FactualityTier
import com.intellidream.daily.model.MediaBias
import com.intellidream.daily.model.MediaDietSnapshot
import com.intellidream.daily.model.MediaIntelligenceRegistry
import com.intellidream.daily.model.MediaOutletProfile
import com.intellidream.daily.model.NewsArticle
import com.intellidream.daily.model.PerspectiveComparison
import com.intellidream.daily.model.RemoteMediaOutletProfileRow
import com.intellidream.daily.model.RemoteNewsReadingStatsRow
import com.intellidream.daily.model.RssSubscription
import com.intellidream.daily.model.SavedArticle
import com.intellidream.daily.model.SavedArticleType
import com.intellidream.daily.model.StoryCluster
import com.intellidream.daily.model.StoryClusterEngine
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
    suspend fun scrapeMediumReadingList(readingListUrl: String): List<NewsArticle>? = null
    suspend fun extractMediumArticle(url: String, baseArticle: NewsArticle? = null): NewsArticle? = null
    suspend fun scrapeSubstackInbox(): List<NewsArticle>? = null
    suspend fun extractSubstackArticle(url: String, baseArticle: NewsArticle? = null): NewsArticle? = null
    suspend fun fetchSubstackSubscriptions(handle: String? = null): List<FeedSearchResult> = emptyList()
    fun hasAuthenticatedSubstackSession(): Boolean = false
    suspend fun pullOutletDeltas(watermarkIso: String): List<RemoteMediaOutletProfileRow> = emptyList()
    suspend fun fetchPerspectiveCache(clusterHash: String): PerspectiveComparison? = null
    suspend fun savePerspectiveCache(comparison: PerspectiveComparison): Boolean = false
    suspend fun pullReadingStats(userId: String, yearMonth: String): MediaDietSnapshot? = null
    suspend fun pushReadingStats(row: RemoteNewsReadingStatsRow): Boolean = false
    suspend fun generateGeminiPerspectiveComparison(cluster: StoryCluster, languageCode: String, apiKey: String): PerspectiveComparison? = null
}

class NewsRepository(
    private val dao: NewsDao,
    var syncHandler: NewsSyncHandler? = null,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO),
    private val appContext: android.content.Context? = null
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

    // Perspectives, Blindspots & Personal Media Diet State
    private val _storyClusters = MutableStateFlow<List<StoryCluster>>(emptyList())
    val storyClusters: StateFlow<List<StoryCluster>> = _storyClusters.asStateFlow()

    private val _blindspotClusters = MutableStateFlow<List<StoryCluster>>(emptyList())
    val blindspotClusters: StateFlow<List<StoryCluster>> = _blindspotClusters.asStateFlow()

    private val _clusterByLink = MutableStateFlow<Map<String, StoryCluster>>(emptyMap())
    val clusterByLink: StateFlow<Map<String, StoryCluster>> = _clusterByLink.asStateFlow()

    private val _mediaDietSnapshot = MutableStateFlow(MediaDietSnapshot(yearMonth = currentYearMonthString()))
    val mediaDietSnapshot: StateFlow<MediaDietSnapshot> = _mediaDietSnapshot.asStateFlow()

    private val expansionCache = ConcurrentHashMap<String, Pair<StoryCluster, Long>>()
    private val comparisonCache = ConcurrentHashMap<String, PerspectiveComparison>()
    private val seenReadArticleLinks = ConcurrentHashMap.newKeySet<String>()
    @Volatile
    private var lastGdeltRequestMillis: Long = 0L
    private var dietSyncJob: kotlinx.coroutines.Job? = null

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
        loadCachedPerspectivesState()
        observeDb(currentUserId)
        scope.launch(Dispatchers.Default) {
            _articles.collect { list ->
                val out = StoryClusterEngine.clusterArticles(list)
                _storyClusters.value = out.clusters
                _blindspotClusters.value = out.clusters.filter { it.blindspot.isBlindspot }
                _clusterByLink.value = out.byArticleLink
            }
        }
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
                        var feed = entity.toFeedSource()
                        if (feed.url.startsWith("http://", ignoreCase = true)) {
                            feed = feed.copy(url = "https://" + feed.url.substring(7))
                        }
                        if (feed.url.contains("economica.net/rss")) {
                            feed.copy(url = "https://www.economica.net/feed")
                        } else {
                            feed
                        }
                    }
                } else {
                    if (isValidUuid(userId)) {
                        // Seed default feeds to Room with deterministic valid UUIDs for authenticated user
                        val seedEntities = defaultFeeds.map { feed ->
                            val deterministicId = ensureValidUuid(feed.id, "$userId:${normalizeFeedUrl(feed.url)}")
                            RssSubscriptionEntity.fromFeedSource(feed.copy(id = deterministicId), userId)
                        }
                        dao.upsertSubscriptions(seedEntities)
                    }
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
            val timeoutMs = if (feed.id == "substack_inbox" || feed.id == "medium_reading_list") 22000L else 8000L
            val items = kotlinx.coroutines.withTimeoutOrNull(timeoutMs) {
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
        if (feed.id == "medium_reading_list") {
            val scraped = syncHandler?.scrapeMediumReadingList(feed.url)
            if (!scraped.isNullOrEmpty()) {
                return@withContext scraped
            }
        } else if (feed.id == "substack_inbox") {
            val scraped = syncHandler?.scrapeSubstackInbox()
            if (!scraped.isNullOrEmpty()) {
                return@withContext scraped
            }
            // Fallback: aggregate latest stories from the user's subscribed Substack RSS feeds
            val substackFeeds = _feeds.value.filter {
                it.id != "substack_inbox" && (
                    it.url.contains(".substack.com", ignoreCase = true) ||
                    it.iconUrl.contains("substack", ignoreCase = true)
                )
            }
            if (substackFeeds.isNotEmpty()) {
                val fallbackAggregated = coroutineScope {
                    substackFeeds.map { subFeed ->
                        async {
                            try {
                                kotlinx.coroutines.withTimeoutOrNull(7000L) {
                                    fetchFeedItems(subFeed).take(5)
                                } ?: emptyList()
                            } catch (_: Throwable) {
                                emptyList()
                            }
                        }
                    }.awaitAll().flatten()
                }.sortedByDescending { it.publishDate }
                if (fallbackAggregated.isNotEmpty()) {
                    return@withContext fallbackAggregated
                }
            }
            return@withContext emptyList()
        }

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
            val isMedium = article.link.contains("medium.com") || 
                           article.publicationName?.contains("Medium", ignoreCase = true) == true

            val isSubstack = article.isSubstackItem || 
                             article.link.contains("substack.com") || 
                             article.publicationName?.contains("Substack", ignoreCase = true) == true

            val articleContent = article.content
            val hasSubstantialContent = !articleContent.isNullOrBlank() && 
                                         articleContent.length > 250 && 
                                         !ArticleExtractor.isMediumTeaser(articleContent)

            if (isMedium && hasSubstantialContent) {
                return@withContext article
            }

            val hasSubstantialSubstackContent = !articleContent.isNullOrBlank() && 
                                                articleContent.length > 300 && 
                                                !ArticleExtractor.isSubstackTeaser(articleContent)

            val shouldUpgradeSubstackBonus = isSubstack &&
                                             hasSubstantialSubstackContent &&
                                             ArticleExtractor.hasSubstackBonusPaywall(articleContent) &&
                                             (syncHandler?.hasAuthenticatedSubstackSession() == true)

            if (isSubstack && hasSubstantialSubstackContent && !shouldUpgradeSubstackBonus) {
                var purified = ArticleExtractor.stripSubstackTrackingAndNoise(articleContent!!)
                if (!article.imageUrl.isNullOrBlank()) {
                    purified = ArticleExtractor.shared.deduplicateFeaturedImage(purified, article.imageUrl!!)
                }
                return@withContext article.copy(content = purified)
            }

            if (isMedium) {
                val extractedMedium = syncHandler?.extractMediumArticle(article.link, article)
                val medContent = extractedMedium?.content
                if (extractedMedium != null && !medContent.isNullOrBlank() && medContent.length > 100) {
                    return@withContext extractedMedium
                }
            }

            if (isSubstack) {
                val extractedSubstack = syncHandler?.extractSubstackArticle(article.link, article)
                val subContent = extractedSubstack?.content
                if (extractedSubstack != null && !subContent.isNullOrBlank() && subContent.length > 100) {
                    return@withContext extractedSubstack
                }
            }

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
                if (currentUrl.startsWith("http://", ignoreCase = true)) {
                    currentUrl = "https://" + currentUrl.substring(7)
                }
                val url = URL(currentUrl)
                conn = url.openConnection() as HttpURLConnection
                conn.instanceFollowRedirects = false
                conn.connectTimeout = 8000
                conn.readTimeout = 10000
                conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36")
                conn.setRequestProperty("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8,application/rss+xml,application/atom+xml,application/json")
                conn.setRequestProperty("Accept-Language", "ro-RO,ro;q=0.9,en-US;q=0.8,en;q=0.7")
                try {
                    val cm = android.webkit.CookieManager.getInstance()
                    val cookies = cm.getCookie(currentUrl) ?: cm.getCookie("https://medium.com")
                    if (!cookies.isNullOrBlank()) {
                        conn.setRequestProperty("Cookie", cookies)
                    }
                } catch (_: Throwable) {}
                val responseCode = conn.responseCode
                if (responseCode in 300..399) {
                    val location = conn.getHeaderField("Location")
                    if (!location.isNullOrBlank()) {
                        val rawRedirect = if (location.startsWith("http://") || location.startsWith("https://")) {
                            location
                        } else {
                            URL(url, location).toString()
                        }
                        currentUrl = if (rawRedirect.startsWith("http://", ignoreCase = true)) {
                            "https://" + rawRedirect.substring(7)
                        } else {
                            rawRedirect
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
        val clean = username.trim().removePrefix("@")
        val targetUrl = if (!customUrl.isNullOrBlank()) customUrl else "https://medium.com/@$clean/list/reading-list"
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

    // MARK: - Substack Subscriptions & Inbox

    fun substackInboxFeedSource(username: String?): FeedSource? {
        if (username.isNullOrBlank()) return null
        val clean = username.trim().removePrefix("@")
        if (clean.isBlank()) return null
        return FeedSource(
            id = "substack_inbox",
            name = "Substack Inbox",
            url = "https://substack.com/inbox",
            iconUrl = "https://substack.com/favicon.ico",
            type = FeedType.Rss,
            category = FeedCategory.Other,
            displayOrder = 998
        )
    }

    private fun resolveSubstackFeedTarget(slugOrFeedUrl: String): String? {
        val clean = slugOrFeedUrl.trim()
        if (clean.isBlank()) return null
        val lower = clean.lowercase()
        if (lower == "https://substack.com/feed" || lower == "http://substack.com/feed" || lower == "https://open.substack.com/feed") {
            return null
        }
        return if (lower.startsWith("http://") || lower.startsWith("https://")) {
            clean
        } else {
            val slug = lower.removePrefix("@")
            if (slug.isBlank() || slug == "substack" || slug == "www" || slug == "open") null
            else "https://$slug.substack.com/feed"
        }
    }

    fun isSubscribedToSubstack(slugOrFeedUrl: String): Boolean {
        val feedUrl = resolveSubstackFeedTarget(slugOrFeedUrl) ?: return false
        val targetNorm = normalizeFeedUrl(feedUrl)
        return _feeds.value.any { normalizeFeedUrl(it.url) == targetNorm }
    }

    fun isSubscribedToSubstack(article: NewsArticle): Boolean {
        val feedUrl = com.intellidream.daily.model.extractSubstackFeedUrl(article) ?: return false
        return isSubscribedToSubstack(feedUrl)
    }

    suspend fun subscribeToSubstackPublication(
        slugOrFeedUrl: String,
        publicationName: String? = null,
        iconUrl: String? = null,
        userId: String = currentUserId
    ) {
        val feedUrl = resolveSubstackFeedTarget(slugOrFeedUrl) ?: return
        val targetNorm = normalizeFeedUrl(feedUrl)
        if (_feeds.value.any { normalizeFeedUrl(it.url) == targetNorm }) return
        val fallbackName = slugOrFeedUrl.trim().removePrefix("https://").removePrefix("http://")
            .substringBefore(".substack.com").substringBefore("/").replaceFirstChar { it.uppercase() }
        val displayName = publicationName?.takeIf {
            it.isNotBlank() && !it.equals("Substack", ignoreCase = true) && !it.equals("Substack Inbox", ignoreCase = true)
        } ?: fallbackName
        addFeed(
            name = displayName,
            url = feedUrl,
            category = FeedCategory.Other,
            userId = userId,
            iconUrl = iconUrl ?: ""
        )
    }

    suspend fun unsubscribeFromSubstackPublication(slugOrFeedUrl: String, userId: String = currentUserId) {
        val feedUrl = resolveSubstackFeedTarget(slugOrFeedUrl) ?: return
        val targetNorm = normalizeFeedUrl(feedUrl)
        val feed = _feeds.value.firstOrNull { normalizeFeedUrl(it.url) == targetNorm } ?: return
        deleteFeed(feed.id, userId)
    }

    suspend fun syncSubstackSubscriptions(handle: String? = null, userId: String = currentUserId): Int = withContext(Dispatchers.IO) {
        val discovered = syncHandler?.fetchSubstackSubscriptions(handle) ?: return@withContext 0
        if (discovered.isEmpty()) return@withContext 0
        var addedCount = 0
        for (sub in discovered) {
            val norm = normalizeFeedUrl(sub.url)
            if (_feeds.value.none { normalizeFeedUrl(it.url) == norm }) {
                addFeed(
                    name = sub.name,
                    url = sub.url,
                    category = FeedCategory.Other,
                    userId = userId,
                    iconUrl = sub.iconUrl
                )
                addedCount++
            }
        }
        feedCache.remove("substack_inbox")
        feedCache.remove("all_news")
        addedCount
    }

    // MARK: - Feed Management

    suspend fun addFeed(
        name: String,
        url: String,
        category: FeedCategory,
        userId: String = currentUserId,
        iconUrl: String = ""
    ) {
        val norm = normalizeFeedUrl(url)
        if (norm == "https://substack.com/feed" || norm == "https://www.substack.com/feed" || norm == "https://open.substack.com/feed") {
            return
        }
        val existing = _feeds.value.firstOrNull { normalizeFeedUrl(it.url) == norm }
        if (existing != null) {
            return
        }
        val type = if (url.contains("wp-json", ignoreCase = true)) FeedType.WpJson else FeedType.Rss
        val newFeed = FeedSource(
            name = name,
            url = url,
            iconUrl = iconUrl,
            type = type,
            category = category,
            displayOrder = _feeds.value.size
        )
        val entity = RssSubscriptionEntity.fromFeedSource(
            newFeed.copy(id = ensureValidUuid(newFeed.id, "$userId:$norm")),
            userId
        )
        dao.upsertSubscription(entity)

        if (isValidUuid(userId)) {
            syncHandler?.let { handler ->
                scope.launch {
                    val nowIso = java.time.Instant.ofEpochMilli(entity.createdAt).toString()
                    val sub = RssSubscription(
                        id = entity.id,
                        userId = userId,
                        name = entity.name,
                        url = entity.url,
                        iconUrl = entity.iconUrl,
                        category = entity.category,
                        displayOrder = entity.displayOrder,
                        createdAt = nowIso,
                        updatedAt = nowIso
                    )
                    if (handler.pushSubscription(sub)) {
                        dao.markSubscriptionsSynced(listOf(entity.id), System.currentTimeMillis())
                    }
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
        if (!isValidUuid(userId)) return@withContext
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

            // 2. Push unsynced subscriptions (healing legacy "seed_*" IDs & "guest" rows so HTTP 400 never loops)
            val currentUserSubsByUrl = dao.getSubscriptions(userId).associateBy { normalizeFeedUrl(it.url) }.toMutableMap()
            val unsyncedSubs = dao.getUnsyncedSubscriptions()
            for (sub in unsyncedSubs) {
                val normUrl = normalizeFeedUrl(sub.url)
                if (!isValidUuid(sub.userId)) {
                    // Legacy "guest" row created prior to auth: drop if user already has this URL, else migrate cleanly
                    if (currentUserSubsByUrl.containsKey(normUrl)) {
                        dao.deleteSubscriptionPermanently(sub.id)
                        continue
                    }
                } else if (sub.userId != userId) {
                    continue
                }

                val targetUserId = userId
                val existingSynced = currentUserSubsByUrl[normUrl]
                if (existingSynced != null && existingSynced.id != sub.id && existingSynced.syncedAt != null) {
                    dao.deleteSubscriptionPermanently(sub.id)
                    continue
                }

                val validId = ensureValidUuid(sub.id, "$targetUserId:$normUrl")
                val createdIso = java.time.Instant.ofEpochMilli(sub.createdAt.takeIf { it > 0L } ?: System.currentTimeMillis()).toString()
                val updatedIso = java.time.Instant.ofEpochMilli((sub.updatedAt ?: sub.createdAt).takeIf { it > 0L } ?: System.currentTimeMillis()).toString()

                val model = RssSubscription(
                    id = validId,
                    userId = targetUserId,
                    name = sub.name,
                    url = sub.url,
                    iconUrl = sub.iconUrl,
                    category = sub.category,
                    displayOrder = sub.displayOrder,
                    createdAt = createdIso,
                    updatedAt = updatedIso,
                    isDeleted = sub.isDeleted
                )
                if (handler.pushSubscription(model)) {
                    val syncedNow = System.currentTimeMillis()
                    if (validId != sub.id || sub.userId != targetUserId) {
                        dao.deleteSubscriptionPermanently(sub.id)
                        val migrated = sub.copy(
                            id = validId,
                            userId = targetUserId,
                            syncedAt = syncedNow
                        )
                        dao.upsertSubscription(migrated)
                        currentUserSubsByUrl[normUrl] = migrated
                    } else {
                        dao.markSubscriptionsSynced(listOf(validId), syncedNow)
                    }
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
                                createdAt = remote.createdAt?.let { runCatching { java.time.Instant.parse(it).toEpochMilli() }.getOrNull() } ?: System.currentTimeMillis(),
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
                if (!isValidUuid(art.userId)) {
                    if (art.userId == "guest") {
                        dao.markSavedArticlesSynced(listOf(art.id), System.currentTimeMillis())
                    }
                    continue
                }
                if (art.userId != userId) continue
                val validArtId = ensureValidUuid(art.id, "$userId:${art.articleUrl}:${art.articleType}")
                val model = SavedArticle(
                    id = validArtId,
                    userId = userId,
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
                    updatedAt = java.time.Instant.ofEpochMilli(art.updatedAt ?: System.currentTimeMillis()).toString(),
                    isDeleted = art.isDeleted
                )
                if (handler.pushSavedArticle(model)) {
                    dao.markSavedArticlesSynced(listOf(art.id), System.currentTimeMillis())
                }
            }

            // 5. Incremental 24h Outlet Profile Deltas & Monthly Reading Stats
            syncOutletDeltasIfNeeded(handler)
            syncReadingStatsIfNeeded(userId, handler)
        } catch (_: Exception) {}
    }

    // MARK: - Perspectives, Blindspots & Personal Media Diet Engine

    fun clusterForArticle(article: NewsArticle): StoryCluster? =
        _clusterByLink.value[article.link]

    suspend fun expandClusterCoverage(cluster: StoryCluster, force: Boolean = false): StoryCluster = withContext(Dispatchers.IO) {
        val now = System.currentTimeMillis()
        if (!force) {
            val cached = expansionCache[cluster.id]
            if (cached != null && now - cached.second < 15 * 60_000L) {
                return@withContext cached.first
            }
        }

        val (query, isRomanian) = StoryClusterEngine.buildDiscoveryQuery(cluster.leadArticle)
        if (query.isBlank()) return@withContext cluster

        val discovered = ArrayList<NewsArticle>()
        if (isRomanian) {
            coroutineScope {
                val roDef = async { fetchGoogleNewsSearch(query, "ro", "RO", "RO:ro", cluster.leadArticle.category) }
                val intlDef = async { fetchGoogleNewsSearch(query, "en-US", "US", "US:en", cluster.leadArticle.category) }
                discovered.addAll(roDef.await())
                discovered.addAll(intlDef.await().take(10))
            }
        } else {
            discovered.addAll(fetchGoogleNewsSearch(query, "en-US", "US", "US:en", cluster.leadArticle.category))
        }

        if (discovered.size < 3) {
            discovered.addAll(fetchGdeltFallback(query, cluster.leadArticle.category))
        }

        val merged = withContext(Dispatchers.Default) {
            StoryClusterEngine.mergeExpandedArticles(cluster, discovered)
        }
        expansionCache[cluster.id] = merged to now

        // Update reactive cluster lists in place if present
        val currentList = _storyClusters.value
        val idx = currentList.indexOfFirst { it.id == merged.id }
        if (idx >= 0) {
            val updated = currentList.toMutableList()
            updated[idx] = merged
            _storyClusters.value = updated
            _blindspotClusters.value = updated.filter { it.blindspot.isBlindspot }
        }
        val updatedLinks = _clusterByLink.value.toMutableMap()
        for (item in merged.items) {
            updatedLinks[item.article.link] = merged
        }
        _clusterByLink.value = updatedLinks

        merged
    }

    private suspend fun fetchGoogleNewsSearch(
        query: String,
        hl: String,
        gl: String,
        ceid: String,
        category: FeedCategory?
    ): List<NewsArticle> {
        return try {
            val fullQuery = java.net.URLEncoder.encode("$query when:3d", "UTF-8")
            val searchUrl = "https://news.google.com/rss/search?q=$fullQuery&hl=$hl&gl=$gl&ceid=$ceid"
            val rawXml = syncHandler?.fetchUrl(searchUrl) ?: fetchRawHttp(searchUrl) ?: return emptyList()
            val tempFeed = FeedSource(
                id = "gnews_perspective_search",
                name = "Google News",
                url = searchUrl,
                type = FeedType.Rss,
                category = category ?: FeedCategory.World
            )
            FeedParser(tempFeed).parse(rawXml).take(22)
        } catch (_: Exception) {
            emptyList()
        }
    }

    private suspend fun fetchGdeltFallback(query: String, category: FeedCategory?): List<NewsArticle> {
        val now = System.currentTimeMillis()
        if (now - lastGdeltRequestMillis < 6000L) return emptyList()
        lastGdeltRequestMillis = now

        return try {
            val encoded = java.net.URLEncoder.encode(query, "UTF-8")
            val gdeltUrl = "https://api.gdeltproject.org/api/v2/doc/doc?query=$encoded&mode=ArtList&maxrecords=15&timespan=72h&format=json"
            val rawJson = syncHandler?.fetchUrl(gdeltUrl) ?: fetchRawHttp(gdeltUrl) ?: return emptyList()
            val root = org.json.JSONObject(rawJson)
            val arr = root.optJSONArray("articles") ?: return emptyList()
            val items = ArrayList<NewsArticle>()
            for (i in 0 until arr.length()) {
                val obj = arr.optJSONObject(i) ?: continue
                val title = obj.optString("title", "").trim()
                val url = obj.optString("url", "").trim()
                if (title.isEmpty() || url.isEmpty()) continue
                val domain = obj.optString("domain", "").ifEmpty { MediaIntelligenceRegistry.extractNormalizedHost(url) }
                val profile = MediaIntelligenceRegistry.shared.resolve(url = url, publicationName = domain)
                val socialImg = obj.optString("socialimage", "").takeIf { it.isNotBlank() }
                items.add(
                    NewsArticle(
                        id = url,
                        title = title,
                        link = url,
                        publishDate = now,
                        imageUrl = socialImg,
                        publicationName = profile.name,
                        publicationIconUrl = "https://www.google.com/s2/favicons?domain=${profile.domain}&sz=64",
                        category = category
                    )
                )
            }
            items
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun fetchRawHttp(urlString: String): String? {
        return try {
            val conn = (URL(urlString).openConnection() as HttpURLConnection).apply {
                connectTimeout = 8000
                readTimeout = 8000
                setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 Chrome/130.0.0.0 Mobile Safari/537.36")
            }
            if (conn.responseCode in 200..299) {
                BufferedReader(InputStreamReader(conn.inputStream, Charsets.UTF_8)).use { it.readText() }
            } else null
        } catch (_: Exception) {
            null
        }
    }

    suspend fun compareClusterPerspectives(
        cluster: StoryCluster,
        apiKey: String?,
        forceRefresh: Boolean = false
    ): PerspectiveComparison = withContext(Dispatchers.IO) {
        val minSources = (cluster.uniqueOutletCount - 2).coerceAtLeast(2)
        if (!forceRefresh) {
            val mem = comparisonCache[cluster.id]
            if (mem != null && mem.sourceCount >= minSources) return@withContext mem

            val remote = syncHandler?.fetchPerspectiveCache(cluster.id)
            if (remote != null && remote.sourceCount >= (cluster.uniqueOutletCount - 3).coerceAtLeast(2)) {
                comparisonCache[cluster.id] = remote
                return@withContext remote
            }
        }

        val isRo = StoryClusterEngine.detectRomanian(
            "${cluster.leadArticle.title} ${cluster.leadArticle.description ?: ""}",
            cluster.leadArticle.link
        )
        val langCode = if (isRo) "ro" else "en"
        val cleanKey = apiKey?.trim().orEmpty()

        if (cleanKey.isNotEmpty() && cluster.items.size >= 2) {
            val aiResult = syncHandler?.generateGeminiPerspectiveComparison(cluster, langCode, cleanKey)
            if (aiResult != null) {
                comparisonCache[cluster.id] = aiResult
                scope.launch(Dispatchers.IO) {
                    syncHandler?.savePerspectiveCache(aiResult)
                }
                return@withContext aiResult
            }
        }

        val deterministic = buildDeterministicComparison(cluster, isRo)
        comparisonCache[cluster.id] = deterministic
        deterministic
    }

    private fun buildDeterministicComparison(cluster: StoryCluster, isRomanian: Boolean): PerspectiveComparison {
        val d = cluster.distribution
        val sampleNames = cluster.items.map { it.profile.name }.distinct().sorted().take(4).joinToString(", ")

        val summaryText = if (isRomanian) {
            "Acest subiect este acoperit de ${cluster.uniqueOutletCount} publicații ($sampleNames), cu o distribuție de ${d.leftPercentInt}% Stânga, ${d.centerPercentInt}% Centru și ${d.rightPercentInt}% Dreapta."
        } else {
            "This story is covered across ${cluster.uniqueOutletCount} distinct outlets ($sampleNames), spanning ${d.leftPercentInt}% Left, ${d.centerPercentInt}% Center, and ${d.rightPercentInt}% Right perspectives."
        }

        val facts = ArrayList<String>()
        if (cluster.anchorEntities.isNotEmpty()) {
            facts.add(
                if (isRomanian) "Entități și repere comune în titluri: ${cluster.anchorEntities.joinToString(" • ")}."
                else "Core entities shared across reporting: ${cluster.anchorEntities.joinToString(" • ")}."
            )
        }
        val highFactCount = cluster.items.count {
            it.profile.factuality == FactualityTier.VeryHigh || it.profile.factuality == FactualityTier.High
        }
        if (highFactCount > 0) {
            facts.add(
                if (isRomanian) "$highFactCount din ${cluster.items.size} articole provin din redacții cu factualitate ridicată (High / Very High)."
                else "$highFactCount of ${cluster.items.size} reports originate from High or Very High factuality newsrooms."
            )
        }

        val diffs = ArrayList<FramingDifferenceItem>()
        cluster.items.firstOrNull { it.profile.bias.bucket == MediaBias.SpectrumBucket.Left }?.let { item ->
            diffs.add(
                FramingDifferenceItem(
                    perspectiveLabel = if (isRomanian) "Stânga / Progresist (${item.profile.name})" else "Left / Lean Left (${item.profile.name})",
                    angle = "„${item.article.title}”"
                )
            )
        }
        cluster.items.firstOrNull { it.profile.bias.bucket == MediaBias.SpectrumBucket.Center }?.let { item ->
            diffs.add(
                FramingDifferenceItem(
                    perspectiveLabel = if (isRomanian) "Centru / Echilibrat (${item.profile.name})" else "Center / Wire (${item.profile.name})",
                    angle = "„${item.article.title}”"
                )
            )
        }
        cluster.items.firstOrNull { it.profile.bias.bucket == MediaBias.SpectrumBucket.Right }?.let { item ->
            diffs.add(
                FramingDifferenceItem(
                    perspectiveLabel = if (isRomanian) "Dreapta / Pro-Piață (${item.profile.name})" else "Right / Lean Right (${item.profile.name})",
                    angle = "„${item.article.title}”"
                )
            )
        }
        if (diffs.size < 3) {
            cluster.items.firstOrNull {
                it.profile.bias == MediaBias.IndependentCreator || it.profile.ownershipType.isIndependentOrNonProfit
            }?.let { item ->
                diffs.add(
                    FramingDifferenceItem(
                        perspectiveLabel = if (isRomanian) "Independent / Non-Profit (${item.profile.name})" else "Independent / Non-Profit (${item.profile.name})",
                        angle = "„${item.article.title}”"
                    )
                )
            }
        }

        val omissions = ArrayList<String>()
        if (cluster.blindspot.isBlindspot) {
            omissions.add(cluster.blindspot.explanation)
        }
        val opinionCount = cluster.items.count { it.framing == ArticleFramingTag.Opinion }
        val sensationalCount = cluster.items.count { it.framing == ArticleFramingTag.Sensational }
        if (opinionCount > 0) {
            omissions.add(
                if (isRomanian) "$opinionCount surse tratează subiectul în registru de editorial/opinie, nu doar relatare factuală."
                else "$opinionCount outlet(s) frame this event as editorial commentary rather than straight wire reporting."
            )
        }
        if (sensationalCount > 0) {
            omissions.add(
                if (isRomanian) "Atenție la încadrarea emoțională: $sensationalCount titluri folosesc formulări senzaționaliste."
                else "Note on tone: $sensationalCount headline(s) employ sensational or loaded phrasing."
            )
        }

        return PerspectiveComparison(
            clusterHash = cluster.id,
            storyTitle = cluster.leadArticle.title,
            summaryText = summaryText,
            commonFacts = facts,
            framingDifferences = diffs,
            omissions = omissions,
            languageCode = if (isRomanian) "ro" else "en",
            sourceCount = cluster.uniqueOutletCount,
            isAiGenerated = false
        )
    }

    fun recordArticleRead(article: NewsArticle, wasBlindspot: Boolean = false) {
        val cleanLink = article.link.trim()
        if (cleanLink.isEmpty() || !seenReadArticleLinks.add(cleanLink)) return

        val profile = MediaIntelligenceRegistry.shared.resolve(article)
        val ym = currentYearMonthString()
        val current = _mediaDietSnapshot.value
        val counts = if (current.yearMonth == ym) current.counts.toMutableMap() else HashMap()

        counts["total_read"] = (counts["total_read"] ?: 0) + 1
        counts[profile.bias.rawValue] = (counts[profile.bias.rawValue] ?: 0) + 1
        counts[profile.factuality.rawValue] = (counts[profile.factuality.rawValue] ?: 0) + 1
        if (profile.ownershipType.isIndependentOrNonProfit) {
            counts["independent_own"] = (counts["independent_own"] ?: 0) + 1
        } else {
            counts["corporate_own"] = (counts["corporate_own"] ?: 0) + 1
        }
        val clusterBlindspot = _clusterByLink.value[cleanLink]?.blindspot?.isBlindspot == true
        if (wasBlindspot || clusterBlindspot) {
            counts["blindspots_read"] = (counts["blindspots_read"] ?: 0) + 1
        }

        val updated = MediaDietSnapshot(yearMonth = ym, counts = counts)
        _mediaDietSnapshot.value = updated
        persistMediaDietLocally(updated)
        scheduleDebouncedDietCloudPush(updated)
    }

    private fun scheduleDebouncedDietCloudPush(snapshot: MediaDietSnapshot) {
        val uid = currentUserId
        if (!isValidUuid(uid)) return
        dietSyncJob?.cancel()
        dietSyncJob = scope.launch(Dispatchers.IO) {
            kotlinx.coroutines.delay(60_000L)
            val latest = _mediaDietSnapshot.value
            val row = RemoteNewsReadingStatsRow(
                userId = uid,
                yearMonth = latest.yearMonth,
                counts = latest.counts,
                updatedAt = java.time.Instant.now().toString()
            )
            syncHandler?.pushReadingStats(row)
        }
    }

    private fun loadCachedPerspectivesState() {
        val prefs = appContext?.getSharedPreferences("daily_perspectives_prefs", android.content.Context.MODE_PRIVATE) ?: return
        try {
            val jsonCodec = kotlinx.serialization.json.Json { ignoreUnknownKeys = true }
            prefs.getString("outlet_deltas_v1", null)?.let { raw ->
                val deltas = jsonCodec.decodeFromString<List<MediaOutletProfile>>(raw)
                MediaIntelligenceRegistry.shared.applyRemoteDeltas(deltas)
            }
            val ym = currentYearMonthString()
            prefs.getString("media_diet_$ym", null)?.let { raw ->
                _mediaDietSnapshot.value = jsonCodec.decodeFromString<MediaDietSnapshot>(raw)
            }
        } catch (_: Exception) {}
    }

    private fun persistMediaDietLocally(snapshot: MediaDietSnapshot) {
        val prefs = appContext?.getSharedPreferences("daily_perspectives_prefs", android.content.Context.MODE_PRIVATE) ?: return
        try {
            val encoded = kotlinx.serialization.json.Json.encodeToString(MediaDietSnapshot.serializer(), snapshot)
            prefs.edit().putString("media_diet_${snapshot.yearMonth}", encoded).apply()
        } catch (_: Exception) {}
    }

    private suspend fun syncOutletDeltasIfNeeded(handler: NewsSyncHandler) {
        val prefs = appContext?.getSharedPreferences("daily_perspectives_prefs", android.content.Context.MODE_PRIVATE) ?: return
        val now = System.currentTimeMillis()
        val lastCheck = prefs.getLong("outlet_deltas_last_check", 0L)
        if (lastCheck > 0L && now - lastCheck < 24 * 3600_000L) return

        prefs.edit().putLong("outlet_deltas_last_check", now).apply()
        val watermark = prefs.getString("outlet_deltas_watermark", "2026-11-14T00:00:00Z") ?: "2026-11-14T00:00:00Z"
        val remoteRows = handler.pullOutletDeltas(watermark)
        if (remoteRows.isEmpty()) return

        val jsonCodec = kotlinx.serialization.json.Json { ignoreUnknownKeys = true }
        val existing = prefs.getString("outlet_deltas_v1", null)?.let {
            runCatching { jsonCodec.decodeFromString<List<MediaOutletProfile>>(it) }.getOrNull()
        }.orEmpty().associateBy { it.domain }.toMutableMap()

        var maxWatermark = watermark
        for (row in remoteRows) {
            val mapped = row.toDomainProfile()
            existing[mapped.domain] = mapped
            if (!row.updatedAt.isNullOrBlank() && row.updatedAt!! > maxWatermark) {
                maxWatermark = row.updatedAt!!
            }
        }
        val mergedList = existing.values.toList()
        MediaIntelligenceRegistry.shared.applyRemoteDeltas(mergedList)
        runCatching {
            val encoded = jsonCodec.encodeToString(kotlinx.serialization.builtins.ListSerializer(MediaOutletProfile.serializer()), mergedList)
            prefs.edit()
                .putString("outlet_deltas_v1", encoded)
                .putString("outlet_deltas_watermark", maxWatermark)
                .apply()
        }
    }

    private suspend fun syncReadingStatsIfNeeded(userId: String, handler: NewsSyncHandler) {
        val ym = currentYearMonthString()
        val remote = handler.pullReadingStats(userId, ym) ?: return
        val local = _mediaDietSnapshot.value
        val merged = HashMap<String, Int>()
        merged.putAll(remote.counts)
        if (local.yearMonth == ym) {
            for ((k, v) in local.counts) {
                merged[k] = maxOf(merged[k] ?: 0, v)
            }
        }
        val updated = MediaDietSnapshot(yearMonth = ym, counts = merged)
        _mediaDietSnapshot.value = updated
        persistMediaDietLocally(updated)
    }

    private fun currentYearMonthString(): String {
        val fmt = java.time.format.DateTimeFormatter.ofPattern("yyyy-MM", java.util.Locale.US)
            .withZone(java.time.ZoneId.systemDefault())
        return fmt.format(java.time.Instant.now())
    }

    fun normalizeFeedUrl(url: String): String = Companion.normalizeFeedUrl(url)

    companion object {
        fun isValidUuid(candidate: String?): Boolean {
            if (candidate.isNullOrBlank() || candidate == "guest") return false
            return try {
                UUID.fromString(candidate)
                true
            } catch (_: IllegalArgumentException) {
                false
            }
        }

        fun ensureValidUuid(candidate: String, deterministicSeed: String): String {
            return if (isValidUuid(candidate)) {
                candidate
            } else {
                UUID.nameUUIDFromBytes(deterministicSeed.lowercase(java.util.Locale.ROOT).toByteArray(Charsets.UTF_8)).toString()
            }
        }
        fun isMediumTeaser(content: String?): Boolean = ArticleExtractor.isMediumTeaser(content)

        fun normalizeFeedUrl(url: String): String {
            var u = url.trim().lowercase()
            if (u.startsWith("http://")) {
                u = "https://" + u.substring(7)
            }
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
            FeedSource(id = "seed_recorder", name = "Recorder", url = "https://recorder.ro/feed/", category = FeedCategory.Local, displayOrder = 6),

            // 📈 Markets
            FeedSource(id = "seed_cnbc", name = "CNBC", url = "https://www.cnbc.com/id/100003114/device/rss/rss.html", category = FeedCategory.Markets, displayOrder = 7),
            FeedSource(id = "seed_economist", name = "The Economist", url = "https://www.economist.com/finance-and-economics/rss.xml", category = FeedCategory.Markets, displayOrder = 8),

            // 🌍 World
            FeedSource(id = "seed_bbc", name = "BBC News", url = "https://feeds.bbci.co.uk/news/rss.xml", category = FeedCategory.World, displayOrder = 9),
            FeedSource(id = "seed_npr", name = "NPR", url = "https://feeds.npr.org/1001/rss.xml", category = FeedCategory.World, displayOrder = 10),
            FeedSource(id = "seed_politico", name = "Politico Europe", url = "https://www.politico.eu/feed/", category = FeedCategory.World, displayOrder = 11),
            FeedSource(id = "seed_dw", name = "Deutsche Welle", url = "https://rss.dw.com/rdf/rss-en-all", category = FeedCategory.World, displayOrder = 12),
            FeedSource(id = "seed_google_news", name = "Google News", url = "https://news.google.com/rss?hl=en-US&gl=US&ceid=US:en", category = FeedCategory.World, displayOrder = 13),

            // 💡 Tech
            FeedSource(id = "seed_techcrunch", name = "TechCrunch", url = "https://techcrunch.com/feed/", category = FeedCategory.Tech, displayOrder = 14),
            FeedSource(id = "seed_theverge", name = "The Verge", url = "https://www.theverge.com/rss/index.xml", category = FeedCategory.Tech, displayOrder = 15),
            FeedSource(id = "seed_arstechnica", name = "Ars Technica", url = "https://feeds.arstechnica.com/arstechnica/index", category = FeedCategory.Tech, displayOrder = 16),
            FeedSource(id = "seed_zonait", name = "Zona IT", url = "https://zonait.ro/wp-json/wp/v2/posts?per_page=20&_embed", type = FeedType.WpJson, category = FeedCategory.Tech, displayOrder = 17),
            FeedSource(id = "seed_windowscentral", name = "Windows Central", url = "https://www.windowscentral.com/feeds.xml", category = FeedCategory.Tech, displayOrder = 18)
        )
    }
}
