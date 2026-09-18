package com.intellidream.daily.network

import com.intellidream.daily.model.FeedSearchResult
import com.intellidream.daily.model.RssSubscription
import com.intellidream.daily.model.SavedArticle
import io.github.jan.supabase.postgrest.postgrest
import io.ktor.client.HttpClient
import io.ktor.client.engine.cio.CIO
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.statement.bodyAsText
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import org.json.JSONObject
import java.net.URI
import java.net.URLEncoder
import java.util.regex.Pattern

class NewsRemoteService(
    private val clientManager: SupabaseClientManager = SupabaseClientManager
) {
    private val httpClient = HttpClient(CIO) {
        install(HttpTimeout) {
            requestTimeoutMillis = 8000L
            connectTimeoutMillis = 8000L
            socketTimeoutMillis = 8000L
        }
    }

    private val json = Json { ignoreUnknownKeys = true }

    suspend fun fetchUrl(url: String): String? = withContext(Dispatchers.IO) {
        try {
            val response = httpClient.get(url) {
                header("User-Agent", "Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36")
                header("Accept", "application/rss+xml, application/atom+xml, application/json, text/xml, text/html, */*")
            }
            response.bodyAsText()
        } catch (_: Exception) {
            null
        }
    }

    suspend fun searchFeedly(query: String): List<FeedSearchResult> = withContext(Dispatchers.IO) {
        val trimmed = query.trim()
        if (trimmed.isBlank()) return@withContext emptyList()

        // 1. Direct website URL sniffing if looks like URL
        if (trimmed.startsWith("http://") || trimmed.startsWith("https://") || trimmed.contains(".")) {
            var target = trimmed
            if (!target.startsWith("http://") && !target.startsWith("https://")) {
                target = "https://$target"
            }
            val sniffed = sniffWebsiteFeeds(target)
            if (sniffed.isNotEmpty()) return@withContext sniffed
        }

        // 2. Feedly Cloud Search API
        try {
            val encoded = URLEncoder.encode(trimmed, "UTF-8")
            val feedlyUrl = "https://cloud.feedly.com/v3/search/feeds?query=$encoded"
            val body = fetchUrl(feedlyUrl) ?: return@withContext emptyList()

            val jsonObject = JSONObject(body)
            val resultsArray = jsonObject.optJSONArray("results") ?: return@withContext emptyList()

            val results = mutableListOf<FeedSearchResult>()
            for (i in 0 until resultsArray.length()) {
                val item = resultsArray.getJSONObject(i)
                var feedId = item.optString("feedId", "").ifEmpty { item.optString("id", "") }
                if (feedId.isBlank()) continue
                if (feedId.startsWith("feed/")) {
                    feedId = feedId.removePrefix("feed/")
                }
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

    suspend fun pullSubscriptions(userId: String): List<RssSubscription> = withContext(Dispatchers.IO) {
        try {
            val res = clientManager.client.postgrest["rss_subscriptions"]
                .select {
                    filter {
                        eq("user_id", userId)
                    }
                }
            json.decodeFromString<List<RssSubscription>>(res.data)
        } catch (_: Exception) {
            emptyList()
        }
    }

    suspend fun pushSubscription(subscription: RssSubscription): Boolean = withContext(Dispatchers.IO) {
        try {
            clientManager.client.postgrest["rss_subscriptions"].upsert(subscription)
            true
        } catch (_: Exception) {
            false
        }
    }

    suspend fun pullSavedArticles(userId: String): List<SavedArticle> = withContext(Dispatchers.IO) {
        try {
            val res = clientManager.client.postgrest["rss_saved_articles"]
                .select {
                    filter {
                        eq("user_id", userId)
                    }
                }
            json.decodeFromString<List<SavedArticle>>(res.data)
        } catch (_: Exception) {
            emptyList()
        }
    }

    suspend fun pushSavedArticle(article: SavedArticle): Boolean = withContext(Dispatchers.IO) {
        try {
            clientManager.client.postgrest["rss_saved_articles"].upsert(article)
            true
        } catch (_: Exception) {
            false
        }
    }
}
