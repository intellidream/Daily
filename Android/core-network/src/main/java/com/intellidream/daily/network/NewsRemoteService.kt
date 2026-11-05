package com.intellidream.daily.network

import com.intellidream.daily.model.FeedSearchResult
import com.intellidream.daily.model.RssSubscription
import com.intellidream.daily.model.SavedArticle
import com.intellidream.daily.model.extractSubstackFeedUrl
import com.intellidream.daily.model.extractSubstackPublicationSlug
import io.github.jan.supabase.postgrest.postgrest
import io.ktor.client.HttpClient
import io.ktor.client.engine.cio.CIO
import io.ktor.client.plugins.HttpRedirect
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.statement.bodyAsText
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import org.json.JSONArray
import org.json.JSONObject
import java.net.URI
import java.net.URLEncoder
import java.util.Locale
import java.util.regex.Pattern

class NewsRemoteService(
    private val clientManager: SupabaseClientManager = SupabaseClientManager
) {
    private val httpClient = HttpClient(CIO) {
        install(HttpTimeout) {
            requestTimeoutMillis = 10000L
            connectTimeoutMillis = 10000L
            socketTimeoutMillis = 10000L
        }
        install(HttpRedirect) {
            checkHttpMethod = false
        }
    }

    private val json = Json { ignoreUnknownKeys = true }

    suspend fun fetchUrl(url: String): String? = withContext(Dispatchers.IO) {
        try {
            var safeUrl = url.trim()
            if (safeUrl.startsWith("http://", ignoreCase = true)) {
                safeUrl = "https://" + safeUrl.substring(7)
            }
            val response = httpClient.get(safeUrl) {
                header("User-Agent", "Mozilla/5.0 (Linux; Android 15; Pixel 9 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36")
                header("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8,application/rss+xml,application/atom+xml,application/json")
                header("Accept-Language", "ro-RO,ro;q=0.9,en-US;q=0.8,en;q=0.7")
                try {
                    val cm = android.webkit.CookieManager.getInstance()
                    val cookies = cm.getCookie(safeUrl) ?: cm.getCookie("https://medium.com")
                    if (!cookies.isNullOrBlank()) {
                        header("Cookie", cookies)
                    }
                } catch (_: Throwable) {}
            }
            if (response.status.value in 200..299) {
                response.bodyAsText()
            } else {
                null
            }
        } catch (_: Exception) {
            null
        }
    }

    suspend fun searchFeedly(query: String): List<FeedSearchResult> = withContext(Dispatchers.IO) {
        val trimmed = query.trim()
        if (trimmed.isBlank()) return@withContext emptyList()

        // 0. Direct Substack handle or URL resolution (e.g. @pragmaticengineer, pragmaticengineer.substack.com)
        if (trimmed.startsWith("@") && !trimmed.contains(" ") && !trimmed.contains(".")) {
            val handle = trimmed.removePrefix("@").lowercase(Locale.ROOT)
            val subMatches = searchSubstackPublications(handle)
            if (subMatches.isNotEmpty()) return@withContext subMatches
            return@withContext listOf(
                FeedSearchResult(
                    name = handle.replaceFirstChar { it.uppercase() },
                    url = "https://$handle.substack.com/feed",
                    iconUrl = "https://substack.com/favicon.ico",
                    website = "https://$handle.substack.com"
                )
            )
        }

        // 1. Direct website URL sniffing if looks like URL
        if (trimmed.startsWith("http://") || trimmed.startsWith("https://") || (trimmed.contains(".") && !trimmed.contains(" "))) {
            var target = trimmed
            if (!target.startsWith("http://") && !target.startsWith("https://")) {
                target = "https://$target"
            }
            val directSubstackFeed = extractSubstackFeedUrl(target)
            if (directSubstackFeed != null) {
                val slug = extractSubstackPublicationSlug(target) ?: "Substack"
                return@withContext listOf(
                    FeedSearchResult(
                        name = slug.replaceFirstChar { it.uppercase() },
                        url = directSubstackFeed,
                        iconUrl = "https://substack.com/favicon.ico",
                        website = target
                    )
                )
            }
            val sniffed = sniffWebsiteFeeds(target).filterNot { isInvalidRootSubstackFeed(it.url) }
            if (sniffed.isNotEmpty()) return@withContext sniffed
        }

        // 2. Parallel Substack Publisher Directory + Feedly Cloud Search API
        coroutineScope {
            val substackDeferred = async { searchSubstackPublications(trimmed) }
            val feedlyDeferred = async {
                try {
                    val encoded = URLEncoder.encode(trimmed, "UTF-8")
                    val feedlyUrl = "https://cloud.feedly.com/v3/search/feeds?query=$encoded"
                    val body = fetchUrl(feedlyUrl) ?: return@async emptyList()

                    val jsonObject = JSONObject(body)
                    val resultsArray = jsonObject.optJSONArray("results") ?: return@async emptyList()

                    val results = mutableListOf<FeedSearchResult>()
                    for (i in 0 until resultsArray.length()) {
                        val item = resultsArray.getJSONObject(i)
                        var feedId = item.optString("feedId", "").ifEmpty { item.optString("id", "") }
                        if (feedId.isBlank()) continue
                        if (feedId.startsWith("feed/")) {
                            feedId = feedId.removePrefix("feed/")
                        }
                        if (isInvalidRootSubstackFeed(feedId)) continue
                        val title = item.optString("title", "Unnamed Feed")
                        var icon = item.optString("iconUrl", "").ifEmpty { item.optString("visualUrl", "") }
                        if (icon.isBlank()) {
                            val host = try { URI(feedId).host ?: "" } catch (_: Exception) { "" }
                            if (host.isNotBlank()) {
                                icon = "https://www.google.com/s2/favicons?domain=$host&sz=64"
                            }
                        }
                        val website = item.optString("website", "")
                        results.add(FeedSearchResult(name = title, url = feedId, iconUrl = icon, website = website))
                    }
                    results
                } catch (_: Exception) {
                    emptyList()
                }
            }

            val subList = substackDeferred.await()
            val feedlyList = feedlyDeferred.await()

            val combined = mutableListOf<FeedSearchResult>()
            val seen = mutableSetOf<String>()
            fun norm(u: String) = u.trim().lowercase(Locale.ROOT).removePrefix("http://").removePrefix("https://").trimEnd('/')

            // Interleave top Substack matches alongside Feedly results
            for (r in subList.take(8)) {
                if (seen.add(norm(r.url))) combined.add(r)
            }
            for (r in feedlyList) {
                if (seen.add(norm(r.url))) combined.add(r)
            }
            for (r in subList.drop(8)) {
                if (seen.add(norm(r.url))) combined.add(r)
            }
            combined
        }
    }

    suspend fun searchSubstackPublications(query: String): List<FeedSearchResult> = withContext(Dispatchers.IO) {
        val trimmed = query.trim().removePrefix("@")
        if (trimmed.isBlank()) return@withContext emptyList()
        try {
            val encoded = URLEncoder.encode(trimmed, "UTF-8")
            val apiUrl = "https://substack.com/api/v1/top/search?query=$encoded&page=0"
            val body = fetchUrl(apiUrl) ?: return@withContext emptyList()
            val root = JSONObject(body)
            val pubs: JSONArray = root.optJSONArray("publications")
                ?: root.optJSONArray("results")
                ?: return@withContext emptyList()

            val results = mutableListOf<FeedSearchResult>()
            val seen = mutableSetOf<String>()
            for (i in 0 until pubs.length()) {
                val p = pubs.optJSONObject(i) ?: continue
                val subdomain = p.optString("subdomain", "").trim().lowercase(Locale.ROOT)
                val customDomain = p.optString("custom_domain", "").trim().lowercase(Locale.ROOT)
                val feedUrl = when {
                    customDomain.isNotBlank() && customDomain.contains(".") && !customDomain.contains("substack.com") ->
                        "https://$customDomain/feed"
                    subdomain.isNotBlank() ->
                        "https://$subdomain.substack.com/feed"
                    else -> continue
                }
                if (!seen.add(feedUrl)) continue
                val name = p.optString("name", "").trim().ifEmpty { subdomain.replaceFirstChar { it.uppercase() } }
                val logo = p.optString("logo_url", "").trim()
                    .ifEmpty { p.optString("author_photo_url", "").trim() }
                    .ifEmpty { "https://substack.com/favicon.ico" }
                val website = if (customDomain.isNotBlank()) "https://$customDomain" else "https://$subdomain.substack.com"
                results.add(FeedSearchResult(name = name, url = feedUrl, iconUrl = logo, website = website))
            }
            results
        } catch (_: Exception) {
            emptyList()
        }
    }

    suspend fun fetchSubstackPublicSubscriptions(handle: String?): List<FeedSearchResult> = withContext(Dispatchers.IO) {
        val cleanHandle = (handle ?: "")
            .trim()
            .removePrefix("@")
            .removePrefix("https://")
            .removePrefix("http://")
            .removeSuffix("/")
            .replace(".substack.com", "")
            .trim()
        if (cleanHandle.isBlank()) return@withContext emptyList()

        val results = mutableListOf<FeedSearchResult>()
        val seen = mutableSetOf<String>()

        fun appendPub(p: JSONObject?) {
            if (p == null) return
            val subdomain = p.optString("subdomain", "").trim().lowercase(Locale.ROOT)
            val customDomain = p.optString("custom_domain", "").trim().lowercase(Locale.ROOT)
            val feedUrl = when {
                customDomain.isNotBlank() && customDomain.contains(".") && !customDomain.contains("substack.com") ->
                    "https://$customDomain/feed"
                subdomain.isNotBlank() ->
                    "https://$subdomain.substack.com/feed"
                else -> return
            }
            if (!seen.add(feedUrl)) return
            val name = p.optString("name", "").trim().ifEmpty { subdomain.replaceFirstChar { it.uppercase() } }
            val logo = p.optString("logo_url", "").trim()
                .ifEmpty { p.optString("author_photo_url", "").trim() }
                .ifEmpty { "https://substack.com/favicon.ico" }
            val website = if (customDomain.isNotBlank()) "https://$customDomain" else "https://$subdomain.substack.com"
            results.add(FeedSearchResult(name = name, url = feedUrl, iconUrl = logo, website = website))
        }

        try {
            val encoded = URLEncoder.encode(cleanHandle, "UTF-8")
            val body = fetchUrl("https://substack.com/api/v1/user/$encoded/public_profile") ?: return@withContext emptyList()
            val jsonObj = JSONObject(body)
            val subs = jsonObj.optJSONArray("subscriptions")
            if (subs != null) {
                for (i in 0 until subs.length()) {
                    val s = subs.optJSONObject(i) ?: continue
                    appendPub(s.optJSONObject("publication") ?: s)
                }
            }
            if (results.isEmpty()) {
                appendPub(jsonObj.optJSONObject("primaryPublication"))
            }
        } catch (_: Exception) {}
        results
    }

    private fun isInvalidRootSubstackFeed(url: String): Boolean {
        val lower = url.trim().lowercase(Locale.ROOT).trimEnd('/')
        return lower == "https://substack.com/feed" ||
               lower == "http://substack.com/feed" ||
               lower == "https://www.substack.com/feed" ||
               lower == "https://open.substack.com/feed"
    }

    private suspend fun sniffWebsiteFeeds(urlString: String): List<FeedSearchResult> = withContext(Dispatchers.IO) {
        try {
            val html = fetchUrl(urlString) ?: return@withContext emptyList()
            val uri = URI(urlString)
            val host = uri.host ?: "website.com"

            val linkPattern = Pattern.compile(
                "<link[^>]+(?:type=[\"'](application/rss\\+xml|application/atom\\+xml|application/json)[\"']|rel=[\"']alternate[\"'])[^>]*>",
                Pattern.CASE_INSENSITIVE
            )
            val matcher = linkPattern.matcher(html)
            val results = mutableListOf<FeedSearchResult>()

            while (matcher.find()) {
                val tag = matcher.group(0) ?: continue
                val hrefPattern = Pattern.compile("href=[\"']([^\"']+)[\"']", Pattern.CASE_INSENSITIVE)
                val hrefMatcher = hrefPattern.matcher(tag)

                if (hrefMatcher.find()) {
                    var href = hrefMatcher.group(1) ?: continue
                    if (!href.startsWith("http://") && !href.startsWith("https://")) {
                        href = try {
                            uri.resolve(href).toString()
                        } catch (_: Exception) {
                            "https://$host/$href".replace("//", "/")
                        }
                    }

                    var feedTitle = host
                    val titlePattern = Pattern.compile("title=[\"']([^\"']+)[\"']", Pattern.CASE_INSENSITIVE)
                    val titleMatcher = titlePattern.matcher(tag)
                    if (titleMatcher.find()) {
                        feedTitle = titleMatcher.group(1) ?: host
                    }

                    val icon = "https://www.google.com/s2/favicons?domain=$host&sz=64"
                    results.add(FeedSearchResult(name = feedTitle, url = href, iconUrl = icon, website = urlString))
                }
            }
            results
        } catch (_: Exception) {
            emptyList()
        }
    }

    // MARK: - Supabase Synchronization

    private val lastSubsSyncIsoByUser = java.util.concurrent.ConcurrentHashMap<String, String>()
    private val lastSavedSyncIsoByUser = java.util.concurrent.ConcurrentHashMap<String, String>()

    suspend fun pullSubscriptions(userId: String): List<RssSubscription> = withContext(Dispatchers.IO) {
        try {
            val watermarkIso = lastSubsSyncIsoByUser[userId]
            val syncStartedIso = java.time.Instant.now().minusSeconds(120).toString()
            val res = clientManager.client.postgrest["rss_subscriptions"]
                .select {
                    filter {
                        eq("user_id", userId)
                        if (watermarkIso != null) {
                            gte("updated_at", watermarkIso)
                        }
                    }
                }
            val decoded = json.decodeFromString<List<RssSubscription>>(res.data)
            lastSubsSyncIsoByUser[userId] = syncStartedIso
            decoded
        } catch (e: Exception) {
            android.util.Log.w("NewsRemoteService", "Failed to pull subscriptions: ${e.message}")
            emptyList()
        }
    }

    suspend fun pushSubscription(subscription: RssSubscription): Boolean = withContext(Dispatchers.IO) {
        try {
            clientManager.client.postgrest["rss_subscriptions"].upsert(subscription)
            true
        } catch (e: Exception) {
            android.util.Log.w("NewsRemoteService", "Failed to push subscription (${subscription.id}): ${e.message}")
            false
        }
    }

    suspend fun pullSavedArticles(userId: String): List<SavedArticle> = withContext(Dispatchers.IO) {
        try {
            val watermarkIso = lastSavedSyncIsoByUser[userId]
            val syncStartedIso = java.time.Instant.now().minusSeconds(120).toString()
            val res = clientManager.client.postgrest["rss_saved_articles"]
                .select {
                    filter {
                        eq("user_id", userId)
                        if (watermarkIso != null) {
                            gte("updated_at", watermarkIso)
                        } else {
                            eq("is_deleted", false)
                        }
                    }
                }
            val decoded = json.decodeFromString<List<SavedArticle>>(res.data)
            lastSavedSyncIsoByUser[userId] = syncStartedIso
            decoded
        } catch (e: Exception) {
            android.util.Log.w("NewsRemoteService", "Failed to pull saved articles: ${e.message}")
            emptyList()
        }
    }

    suspend fun pushSavedArticle(article: SavedArticle): Boolean = withContext(Dispatchers.IO) {
        try {
            clientManager.client.postgrest["rss_saved_articles"].upsert(article)
            true
        } catch (e: Exception) {
            android.util.Log.w("NewsRemoteService", "Failed to push saved article (${article.id}): ${e.message}")
            false
        }
    }
}
