package com.intellidream.daily.news

import android.annotation.SuppressLint
import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.webkit.CookieManager
import android.webkit.WebView
import android.webkit.WebViewClient
import com.intellidream.daily.model.ArticleExtractor
import com.intellidream.daily.model.FeedCategory
import com.intellidream.daily.model.FeedSearchResult
import com.intellidream.daily.model.NewsArticle
import com.intellidream.daily.model.optimizeSubstackImageUrl
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.util.Locale
import java.util.UUID
import kotlin.coroutines.resume

@SuppressLint("SetJavaScriptEnabled")
class SubstackWebViewBridge(private val context: Context) {

    fun hasAuthenticatedSession(): Boolean {
        return try {
            val cm = CookieManager.getInstance()
            val cookies = cm.getCookie("https://substack.com")
            ArticleExtractor.hasAuthenticatedSubstackCookies(cookies)
        } catch (_: Throwable) {
            false
        }
    }

    /**
     * Evaluates an async JavaScript body inside [webView] by storing its resolved Promise value
     * into a temporary window slot and polling until completion (Android WebView.evaluateJavascript
     * does not natively await JS Promises).
     */
    private suspend fun evaluateAsyncJs(
        webView: WebView,
        asyncBody: String,
        timeoutMs: Long = 12000L
    ): String? = withContext(Dispatchers.Main) {
        val slot = "__dailySubstackAsync_" + UUID.randomUUID().toString().replace("-", "")
        val bootScript = """
            (function() {
                window['$slot'] = { done: false, val: '' };
                (async function() {
                    try {
                        var res = await (async function() {
                            $asyncBody
                        })();
                        window['$slot'] = { done: true, val: (res === undefined || res === null) ? '' : String(res) };
                    } catch (e) {
                        window['$slot'] = { done: true, val: '' };
                    }
                })();
                return 'started';
            })();
        """.trimIndent()

        suspend fun evalOnce(script: String): String? = suspendCancellableCoroutine { cont ->
            try {
                webView.evaluateJavascript(script) { raw ->
                    if (cont.isActive) cont.resume( decodeEvalString(raw) )
                }
            } catch (_: Throwable) {
                if (cont.isActive) cont.resume(null)
            }
        }

        evalOnce(bootScript)

        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            delay(140L)
            val pollJson = evalOnce("window['$slot'] ? JSON.stringify(window['$slot']) : ''")
            if (!pollJson.isNullOrBlank()) {
                try {
                    val obj = JSONObject(pollJson)
                    if (obj.optBoolean("done", false)) {
                        evalOnce("try { delete window['$slot']; } catch(e) {} ''")
                        val v = obj.optString("val", "")
                        return@withContext v.ifEmpty { null }
                    }
                } catch (_: Throwable) {}
            }
        }
        evalOnce("try { delete window['$slot']; } catch(e) {} ''")
        null
    }

    private fun decodeEvalString(raw: String?): String? {
        if (raw.isNullOrBlank() || raw == "null") return null
        return if (raw.startsWith("\"") && raw.endsWith("\"")) {
            try {
                JSONTokener(raw).nextValue()?.toString()
            } catch (_: Throwable) {
                raw
            }
        } else {
            raw
        }
    }

    private suspend fun <T> withSubstackOriginWebView(
        originUrl: String = "https://substack.com/404",
        timeoutMs: Long = 18000L,
        block: suspend (WebView) -> T?
    ): T? = withContext(Dispatchers.Main) {
        withTimeoutOrNull(timeoutMs) {
            var webView: WebView? = null
            try {
                val wv = WebView(context).apply {
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = true
                    settings.userAgentString = SUBSTACK_USER_AGENT
                    try {
                        val cm = CookieManager.getInstance()
                        cm.setAcceptCookie(true)
                        cm.setAcceptThirdPartyCookies(this, true)
                    } catch (_: Throwable) {}
                }
                webView = wv

                val loaded = withTimeoutOrNull(8000L) {
                    suspendCancellableCoroutine<Boolean> { cont ->
                        wv.webViewClient = object : WebViewClient() {
                            private var done = false
                            override fun onPageFinished(view: WebView?, url: String?) {
                                super.onPageFinished(view, url)
                                if (!done) {
                                    done = true
                                    if (cont.isActive) cont.resume(true)
                                }
                            }
                        }
                        wv.loadUrl(originUrl)
                    }
                } ?: false

                if (!loaded) return@withTimeoutOrNull null
                block(wv)
            } catch (_: Throwable) {
                null
            } finally {
                try {
                    webView?.stopLoading()
                    webView?.destroy()
                } catch (_: Throwable) {}
            }
        }
    }

    /**
     * Fetches the signed-in user's full Substack subscriptions (including private subscriptions
     * and custom-domain newsletters) via same-origin `/api/v1/subscriptions`.
     */
    suspend fun fetchAuthenticatedSubscriptions(): List<FeedSearchResult> {
        if (!hasAuthenticatedSession()) return emptyList()

        val asyncSubsJs = """
            const res = await fetch('https://substack.com/api/v1/subscriptions', {
                credentials: 'include',
                headers: { 'Accept': 'application/json' }
            });
            if (!res.ok) return '';
            const data = await res.json();
            const pubsById = {};
            if (Array.isArray(data.publications)) {
                data.publications.forEach(p => { if (p && p.id) pubsById[p.id] = p; });
            }
            const out = [];
            const subs = Array.isArray(data.subscriptions) ? data.subscriptions : (Array.isArray(data) ? data : []);
            subs.forEach(s => {
                const p = s.publication || pubsById[s.publication_id];
                if (p && (p.subdomain || p.custom_domain)) {
                    out.push({
                        name: p.name || p.subdomain || '',
                        subdomain: p.subdomain || '',
                        custom_domain: p.custom_domain || '',
                        logo_url: p.logo_url || p.author_photo_url || ''
                    });
                }
            });
            if (out.length === 0 && Array.isArray(data.publications)) {
                data.publications.forEach(p => {
                    if (p && (p.subdomain || p.custom_domain)) {
                        out.push({
                            name: p.name || p.subdomain || '',
                            subdomain: p.subdomain || '',
                            custom_domain: p.custom_domain || '',
                            logo_url: p.logo_url || ''
                        });
                    }
                });
            }
            return JSON.stringify(out);
        """.trimIndent()

        val jsonStr = withSubstackOriginWebView { wv ->
            evaluateAsyncJs(wv, asyncSubsJs, timeoutMs = 10000L)
        } ?: return emptyList()

        return parseSubscriptionJsonArray(jsonStr)
    }

    private fun parseSubscriptionJsonArray(jsonStr: String): List<FeedSearchResult> {
        if (jsonStr.isBlank()) return emptyList()
        val out = mutableListOf<FeedSearchResult>()
        val seen = mutableSetOf<String>()
        try {
            val arr = JSONArray(jsonStr)
            for (i in 0 until arr.length()) {
                val obj = arr.optJSONObject(i) ?: continue
                val subdomain = obj.optString("subdomain", "").trim().lowercase(Locale.ROOT)
                val customDomain = obj.optString("custom_domain", "").trim().lowercase(Locale.ROOT)
                val feedUrl = when {
                    customDomain.isNotBlank() && customDomain.contains(".") && !customDomain.contains("substack.com") ->
                        "https://$customDomain/feed"
                    subdomain.isNotBlank() ->
                        "https://$subdomain.substack.com/feed"
                    else -> continue
                }
                if (!seen.add(feedUrl)) continue
                val name = obj.optString("name", "").trim().ifEmpty { subdomain.replaceFirstChar { it.uppercase() } }
                val logo = obj.optString("logo_url", "").trim().ifEmpty { "https://substack.com/favicon.ico" }
                val site = if (customDomain.isNotBlank()) "https://$customDomain" else "https://$subdomain.substack.com"
                out.add(FeedSearchResult(name = name, url = feedUrl, iconUrl = logo, website = site))
            }
        } catch (_: Throwable) {}
        return out
    }

    /**
     * Fetches the user's Substack Inbox using Substack's authenticated JSON API
     * (`/api/v1/reader/posts` joined with `/api/v1/subscriptions` for real publication logos,
     * names, canonical URLs, timestamps, and pre-hydrated clean `body_html`), with DOM fallback.
     */
    suspend fun scrapeInbox(): List<NewsArticle>? {
        if (hasAuthenticatedSession()) {
            val apiItems = fetchInboxViaReaderApi()
            if (!apiItems.isNullOrEmpty()) {
                return apiItems
            }
        }
        return scrapeInboxDomFallback()
    }

    private suspend fun fetchInboxViaReaderApi(): List<NewsArticle>? {
        val readerApiJs = """
            const [postsRes, subsRes] = await Promise.all([
                fetch('https://substack.com/api/v1/reader/posts?limit=35', {
                    credentials: 'include',
                    headers: { 'Accept': 'application/json' }
                }),
                fetch('https://substack.com/api/v1/subscriptions', {
                    credentials: 'include',
                    headers: { 'Accept': 'application/json' }
                }).catch(() => null)
            ]);
            if (!postsRes.ok) return '';
            const postsData = await postsRes.json();
            const pubsById = {};
            if (subsRes && subsRes.ok) {
                try {
                    const subsData = await subsRes.json();
                    if (Array.isArray(subsData.publications)) {
                        subsData.publications.forEach(p => { if (p && p.id) pubsById[p.id] = p; });
                    }
                    if (Array.isArray(subsData.subscriptions)) {
                        subsData.subscriptions.forEach(s => {
                            if (s && s.publication && s.publication.id) pubsById[s.publication.id] = s.publication;
                        });
                    }
                } catch (e) {}
            }
            if (Array.isArray(postsData.publications)) {
                postsData.publications.forEach(p => { if (p && p.id) pubsById[p.id] = p; });
            }
            const rawPosts = Array.isArray(postsData.posts) ? postsData.posts : (Array.isArray(postsData) ? postsData : []);
            const mapped = [];
            rawPosts.forEach(p => {
                if (!p || !p.title) return;
                const pub = p.publication || pubsById[p.publication_id] || {};
                const sub = pub.subdomain || '';
                const custom = pub.custom_domain || '';
                let url = p.canonical_url || '';
                if (!url && p.slug) {
                    if (custom) url = 'https://' + custom + '/p/' + p.slug;
                    else if (sub) url = 'https://' + sub + '.substack.com/p/' + p.slug;
                }
                if (!url) return;
                let author = '';
                if (Array.isArray(p.publishedBylines) && p.publishedBylines.length > 0 && p.publishedBylines[0].name) {
                    author = p.publishedBylines[0].name;
                }
                mapped.push({
                    id: p.id ? String(p.id) : url,
                    title: p.title || '',
                    subtitle: p.subtitle || p.description || p.truncated_body_text || '',
                    url: url,
                    date: p.post_date || '',
                    imageUrl: p.cover_image || '',
                    author: author || pub.author_name || pub.name || 'Substack',
                    publication: pub.name || sub || 'Substack',
                    publicationIcon: pub.logo_url || pub.author_photo_url || 'https://substack.com/favicon.ico',
                    bodyHtml: p.body_html || ''
                });
            });
            return JSON.stringify(mapped);
        """.trimIndent()

        val jsonStr = withSubstackOriginWebView(timeoutMs = 20000L) { wv ->
            evaluateAsyncJs(wv, readerApiJs, timeoutMs = 14000L)
        } ?: return null

        return try {
            val arr = JSONArray(jsonStr)
            val results = mutableListOf<NewsArticle>()
            for (i in 0 until arr.length()) {
                val item = arr.optJSONObject(i) ?: continue
                val title = item.optString("title", "").trim()
                val storyUrl = item.optString("url", "").trim()
                if (title.isBlank() || storyUrl.isBlank()) continue

                val subtitle = item.optString("subtitle", "").trim()
                val author = item.optString("author", "Substack").trim()
                val pubName = item.optString("publication", "Substack").trim()
                val pubIcon = item.optString("publicationIcon", "https://substack.com/favicon.ico").trim()
                val rawImg = item.optString("imageUrl", "").trim()
                val optImg = if (rawImg.isNotEmpty()) optimizeSubstackImageUrl(rawImg) else null
                val dateStr = item.optString("date", "").trim()
                val publishEpoch = parseIsoMillis(dateStr) ?: System.currentTimeMillis()

                val rawBody = item.optString("bodyHtml", "").trim()
                var cleanBody: String? = null
                if (rawBody.length > 250 && !ArticleExtractor.isSubstackTeaser(rawBody)) {
                    var purified = ArticleExtractor.stripSubstackTrackingAndNoise(rawBody)
                    if (!optImg.isNullOrBlank()) {
                        purified = ArticleExtractor.shared.deduplicateFeaturedImage(purified, optImg)
                    }
                    if (subtitle.isNotBlank() && !purified.contains(subtitle, ignoreCase = true)) {
                        purified = "<p class=\"substack-subtitle\">${escapeHtml(subtitle)}</p>\n$purified"
                    }
                    cleanBody = purified
                }

                results.add(
                    NewsArticle(
                        id = item.optString("id", "").ifBlank { UUID.randomUUID().toString() },
                        title = title,
                        link = storyUrl,
                        publishDate = publishEpoch,
                        imageUrl = optImg,
                        description = subtitle.ifEmpty { "By $author on $pubName" },
                        content = cleanBody,
                        author = author,
                        publicationName = pubName,
                        publicationIconUrl = pubIcon.ifEmpty { "https://substack.com/favicon.ico" },
                        category = FeedCategory.Other
                    )
                )
            }
            results.ifEmpty { null }
        } catch (_: Throwable) {
            null
        }
    }

    private suspend fun scrapeInboxDomFallback(): List<NewsArticle>? = withContext(Dispatchers.Main) {
        withTimeoutOrNull(22000L) {
            suspendCancellableCoroutine { continuation ->
                val webView = WebView(context).apply {
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = true
                    settings.userAgentString = SUBSTACK_USER_AGENT
                    try {
                        val cm = CookieManager.getInstance()
                        cm.setAcceptCookie(true)
                        cm.setAcceptThirdPartyCookies(this, true)
                    } catch (_: Throwable) {}
                }

                val cleanup = {
                    try {
                        webView.stopLoading()
                        webView.destroy()
                    } catch (_: Throwable) {}
                }

                continuation.invokeOnCancellation { cleanup() }
                val handler = Handler(Looper.getMainLooper())

                webView.webViewClient = object : WebViewClient() {
                    private var hasScraped = false

                    override fun onPageFinished(view: WebView?, loadedUrl: String?) {
                        super.onPageFinished(view, loadedUrl)
                        if (hasScraped) return

                        var attempts = 0
                        val maxAttempts = 7
                        val checkRunnable = object : Runnable {
                            override fun run() {
                                if (hasScraped || !continuation.isActive) return
                                attempts++
                                webView.evaluateJavascript("document.querySelectorAll('a[href*=\"/p/\"]').length") { countStr ->
                                    val count = countStr?.toIntOrNull() ?: 0
                                    if (count > 0 || attempts >= maxAttempts) {
                                        hasScraped = true
                                        webView.evaluateJavascript(SCRAPING_INBOX_JS) { jsonResult ->
                                            cleanup()
                                            val rawJson = decodeEvalString(jsonResult)
                                            if (rawJson.isNullOrBlank() || rawJson == "[]") {
                                                if (continuation.isActive) continuation.resume(null)
                                                return@evaluateJavascript
                                            }
                                            try {
                                                val jsonArray = JSONArray(rawJson)
                                                val list = mutableListOf<NewsArticle>()
                                                for (i in 0 until jsonArray.length()) {
                                                    val item = jsonArray.getJSONObject(i)
                                                    val title = item.optString("title").trim()
                                                    val storyUrl = item.optString("url").trim()
                                                    if (title.isBlank() || storyUrl.isBlank()) continue
                                                    val author = item.optString("author", "Substack").trim()
                                                    val pubName = item.optString("publication", "Substack").trim()
                                                    val imageUrl = item.optString("imageUrl", "")
                                                    val desc = item.optString("description", "")
                                                    val optimizedImg = optimizeSubstackImageUrl(imageUrl)
                                                    list.add(
                                                        NewsArticle(
                                                            id = UUID.randomUUID().toString(),
                                                            title = title,
                                                            link = storyUrl,
                                                            publishDate = System.currentTimeMillis(),
                                                            imageUrl = optimizedImg.ifEmpty { null },
                                                            description = desc.ifEmpty { "By $author on $pubName" },
                                                            content = null,
                                                            author = author,
                                                            publicationName = pubName,
                                                            publicationIconUrl = "https://substack.com/favicon.ico",
                                                            category = FeedCategory.Other
                                                        )
                                                    )
                                                }
                                                if (continuation.isActive) {
                                                    continuation.resume(list.ifEmpty { null })
                                                }
                                            } catch (_: Throwable) {
                                                if (continuation.isActive) continuation.resume(null)
                                            }
                                        }
                                    } else {
                                        handler.postDelayed(this, 800)
                                    }
                                }
                            }
                        }
                        handler.postDelayed(checkRunnable, 1200)
                    }
                }
                webView.loadUrl("https://substack.com/inbox")
            }
        }
    }

    /**
     * Extracts a clean distraction-free Substack article using:
     * 1. Public/custom-domain JSON API `/api/v1/posts/{slug}` (instant, zero UI chrome)
     * 2. Same-origin authenticated `/api/v1/posts/by-id/{id}` via `substack.com` session cookies
     *    (unlocks paid subscriber posts & bonus sections even on custom domains)
     * 3. Focused `.body.markup` / `.available-content` DOM fallback
     */
    suspend fun extractArticle(url: String, baseArticle: NewsArticle? = null): NewsArticle? {
        val hasAuth = hasAuthenticatedSession()
        val slugTarget = resolveSubstackApiSlugTarget(url)

        var publicCandidate: NewsArticle? = null
        var discoveredPostId: String? = baseArticle?.id?.takeIf { it.all { ch -> ch.isDigit() } }

        // Step 1: Fast JSON API lookup (/api/v1/posts/{slug})
        if (slugTarget != null) {
            val (apiHost, slug) = slugTarget
            val apiJsonStr = fetchJsonString("https://$apiHost/api/v1/posts/$slug")
            if (!apiJsonStr.isNullOrBlank()) {
                val parsed = parsePostApiObject(apiJsonStr, url, baseArticle, hasAuth)
                if (parsed != null) {
                    if (!parsed.postId.isNullOrBlank()) {
                        discoveredPostId = parsed.postId
                    }
                    if (!parsed.needsAuthenticatedUpgrade && (parsed.article.content?.length ?: 0) > 200) {
                        return parsed.article
                    }
                    publicCandidate = parsed.article
                }
            }
        }

        // Step 2: Same-origin authenticated `/api/v1/posts/by-id/{id}` (unlocks custom domains & paid subscriber posts)
        val pid = discoveredPostId
        if (hasAuth && !pid.isNullOrBlank()) {
            val byIdJs = """
                const res = await fetch('https://substack.com/api/v1/posts/by-id/$pid', {
                    credentials: 'include',
                    headers: { 'Accept': 'application/json' }
                });
                if (!res.ok) return '';
                return await res.text();
            """.trimIndent()

            val authJsonStr = withSubstackOriginWebView(timeoutMs = 15000L) { wv ->
                evaluateAsyncJs(wv, byIdJs, timeoutMs = 10000L)
            }
            if (!authJsonStr.isNullOrBlank()) {
                val parsedAuth = parsePostApiObject(authJsonStr, url, publicCandidate ?: baseArticle, hasAuth = false)
                if (parsedAuth != null && (parsedAuth.article.content?.length ?: 0) > 100) {
                    return parsedAuth.article
                }
            }
        }

        if (publicCandidate != null && (publicCandidate.content?.length ?: 0) > 200) {
            return publicCandidate
        }

        // Step 3: Clean DOM fallback targeting `.body.markup, .available-content`
        val domExtracted = extractDomFallback(url, publicCandidate ?: baseArticle)
        return domExtracted ?: publicCandidate
    }

    private data class ParsedSubstackApiPost(
        val article: NewsArticle,
        val postId: String?,
        val needsAuthenticatedUpgrade: Boolean
    )

    private fun parsePostApiObject(
        rawJson: String,
        fallbackUrl: String,
        baseArticle: NewsArticle?,
        hasAuth: Boolean
    ): ParsedSubstackApiPost? {
        return try {
            val root = JSONObject(rawJson)
            val post = root.optJSONObject("post") ?: root
            var bodyHtml = post.optString("body_html", "").trim()
            if (bodyHtml.isBlank()) return null

            val postId = post.opt("id")?.toString()?.takeIf { it.isNotBlank() && it != "null" }
            val audience = post.optString("audience", "everyone")
            val isTeaser = ArticleExtractor.isSubstackTeaser(bodyHtml) || bodyHtml.length < 250
            val hasBonus = ArticleExtractor.hasSubstackBonusPaywall(bodyHtml)
            val needsUpgrade = hasAuth && (audience == "only_paid" || isTeaser || hasBonus)

            val title = post.optString("title", "").trim().ifEmpty { baseArticle?.title ?: "Substack Article" }
            val subtitle = post.optString("subtitle", "").trim()
            val canonicalUrl = post.optString("canonical_url", "").trim().ifEmpty { baseArticle?.link ?: fallbackUrl }
            val rawCover = post.optString("cover_image", "").trim().ifEmpty { baseArticle?.imageUrl ?: "" }
            val optCover = if (rawCover.isNotEmpty()) optimizeSubstackImageUrl(rawCover) else null

            var author = baseArticle?.author
            val bylines = post.optJSONArray("publishedBylines")
            if (bylines != null && bylines.length() > 0) {
                val firstAuthor = bylines.optJSONObject(0)?.optString("name", "")?.trim()
                if (!firstAuthor.isNullOrBlank()) author = firstAuthor
            }

            val pubObj = root.optJSONObject("publication") ?: post.optJSONObject("publication")
            val pubName = pubObj?.optString("name", "")?.trim()?.takeIf { it.isNotBlank() } ?: baseArticle?.publicationName
            val pubIcon = pubObj?.optString("logo_url", "")?.trim()?.takeIf { it.isNotBlank() } ?: baseArticle?.publicationIconUrl

            val dateStr = post.optString("post_date", "").trim()
            val publishDate = parseIsoMillis(dateStr) ?: baseArticle?.publishDate ?: System.currentTimeMillis()

            bodyHtml = ArticleExtractor.stripSubstackTrackingAndNoise(bodyHtml)
            if (!optCover.isNullOrBlank()) {
                bodyHtml = ArticleExtractor.shared.deduplicateFeaturedImage(bodyHtml, optCover)
            }
            if (subtitle.isNotBlank() && !bodyHtml.contains(subtitle, ignoreCase = true)) {
                bodyHtml = "<p class=\"substack-subtitle\">${escapeHtml(subtitle)}</p>\n$bodyHtml"
            }

            if (audience == "only_paid" && (bodyHtml.length < 700 || ArticleExtractor.isSubstackTeaser(bodyHtml))) {
                val displayPub = escapeHtml(pubName ?: "this publication")
                bodyHtml += """
                    <div class="paywall-card substack-paid-card">
                        <div class="paywall-icon">🔒</div>
                        <h3>Substack Paid Story</h3>
                        <p>This post is exclusive to paid subscribers of $displayPub.</p>
                        <a href="${escapeHtml(canonicalUrl)}" class="open-browser-btn">Unlock on Substack</a>
                    </div>
                """.trimIndent()
            }

            val built = NewsArticle(
                id = baseArticle?.id ?: postId ?: UUID.randomUUID().toString(),
                title = title,
                link = canonicalUrl,
                publishDate = publishDate,
                imageUrl = optCover,
                description = subtitle.ifEmpty { baseArticle?.description },
                content = bodyHtml,
                author = author,
                publicationName = pubName,
                publicationIconUrl = pubIcon,
                category = baseArticle?.category ?: FeedCategory.Other
            )

            ParsedSubstackApiPost(
                article = built,
                postId = postId,
                needsAuthenticatedUpgrade = needsUpgrade
            )
        } catch (_: Throwable) {
            null
        }
    }

    private fun resolveSubstackApiSlugTarget(urlString: String): Pair<String, String>? {
        return try {
            val uri = Uri.parse(urlString.trim())
            val host = uri.host?.lowercase(Locale.ROOT) ?: return null
            val segments = uri.pathSegments ?: return null

            // Handle https://open.substack.com/pub/{pub}/p/{slug}
            if (host == "open.substack.com" && segments.size >= 4 &&
                segments[0].equals("pub", ignoreCase = true) &&
                segments[2].equals("p", ignoreCase = true)
            ) {
                val pub = segments[1].trim()
                val slug = segments[3].trim()
                if (pub.isNotEmpty() && slug.isNotEmpty()) {
                    return Pair("$pub.substack.com", slug)
                }
            }

            val pIdx = segments.indexOfFirst { it.equals("p", ignoreCase = true) }
            if (pIdx >= 0 && pIdx + 1 < segments.size) {
                val slug = segments[pIdx + 1].trim()
                if (slug.isNotEmpty() && host != "substack.com" && host != "www.substack.com") {
                    return Pair(host, slug)
                }
            }
            null
        } catch (_: Throwable) {
            null
        }
    }

    private suspend fun fetchJsonString(apiUrl: String): String? = withContext(Dispatchers.IO) {
        var conn: HttpURLConnection? = null
        try {
            val url = URL(apiUrl)
            conn = (url.openConnection() as HttpURLConnection).apply {
                connectTimeout = 8000
                readTimeout = 9000
                setRequestProperty("User-Agent", SUBSTACK_USER_AGENT)
                setRequestProperty("Accept", "application/json")
                try {
                    val cm = CookieManager.getInstance()
                    val cookies = cm.getCookie(apiUrl) ?: cm.getCookie("https://substack.com")
                    if (!cookies.isNullOrBlank()) {
                        setRequestProperty("Cookie", cookies)
                    }
                } catch (_: Throwable) {}
            }
            if (conn.responseCode in 200..299) {
                BufferedReader(InputStreamReader(conn.inputStream, Charsets.UTF_8)).use { it.readText() }
            } else {
                null
            }
        } catch (_: Throwable) {
            null
        } finally {
            try { conn?.disconnect() } catch (_: Throwable) {}
        }
    }

    private suspend fun extractDomFallback(url: String, baseArticle: NewsArticle?): NewsArticle? = withContext(Dispatchers.Main) {
        withTimeoutOrNull(20000L) {
            suspendCancellableCoroutine { continuation ->
                val webView = WebView(context).apply {
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = true
                    settings.userAgentString = SUBSTACK_USER_AGENT
                    try {
                        val cm = CookieManager.getInstance()
                        cm.setAcceptCookie(true)
                        cm.setAcceptThirdPartyCookies(this, true)
                        val substackCookies = cm.getCookie("https://substack.com")
                        if (!substackCookies.isNullOrBlank() && !url.contains("://substack.com")) {
                            val uri = Uri.parse(url)
                            val host = uri.host
                            if (host != null && host.endsWith(".substack.com")) {
                                substackCookies.split(";").forEach { cookieStr ->
                                    cm.setCookie("https://$host", cookieStr.trim())
                                }
                                cm.flush()
                            }
                        }
                    } catch (_: Throwable) {}
                }

                val cleanup = {
                    try {
                        webView.stopLoading()
                        webView.destroy()
                    } catch (_: Throwable) {}
                }

                continuation.invokeOnCancellation { cleanup() }
                val handler = Handler(Looper.getMainLooper())

                webView.webViewClient = object : WebViewClient() {
                    private var hasExtracted = false

                    override fun onPageFinished(view: WebView?, loadedUrl: String?) {
                        super.onPageFinished(view, loadedUrl)
                        if (hasExtracted) return

                        val pollRunnable = object : Runnable {
                            private var polls = 0
                            private val maxPolls = 6

                            override fun run() {
                                if (hasExtracted || !continuation.isActive) return
                                polls++

                                webView.evaluateJavascript(EXTRACT_SUBSTACK_JS) { jsonResult ->
                                    val content = decodeEvalString(jsonResult)
                                    if (!content.isNullOrBlank()) {
                                        val isTeaser = ArticleExtractor.isSubstackTeaser(content)
                                        if (content.length > 200 && (!isTeaser || polls >= maxPolls)) {
                                            hasExtracted = true
                                            cleanup()

                                            var cleaned = ArticleExtractor.stripSubstackTrackingAndNoise(content)
                                            val featImg = baseArticle?.imageUrl
                                            if (!featImg.isNullOrBlank()) {
                                                cleaned = ArticleExtractor.shared.deduplicateFeaturedImage(cleaned, featImg)
                                            }
                                            val updated = (baseArticle ?: NewsArticle(
                                                id = UUID.randomUUID().toString(),
                                                title = "Substack Article",
                                                link = url,
                                                publishDate = System.currentTimeMillis()
                                            )).copy(
                                                content = cleaned
                                            )
                                            if (continuation.isActive) continuation.resume(updated)
                                            return@evaluateJavascript
                                        }
                                    }

                                    if (polls < maxPolls) {
                                        handler.postDelayed(this, 900)
                                    } else {
                                        hasExtracted = true
                                        cleanup()
                                        if (continuation.isActive) continuation.resume(null)
                                    }
                                }
                            }
                        }
                        handler.postDelayed(pollRunnable, 1000)
                    }
                }
                webView.loadUrl(url)
            }
        }
    }

    private fun parseIsoMillis(iso: String): Long? {
        if (iso.isBlank()) return null
        return try {
            Instant.parse(iso).toEpochMilli()
        } catch (_: Throwable) {
            null
        }
    }

    private fun escapeHtml(text: String): String {
        return text
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace("\"", "&quot;")
    }

    companion object {
        const val SUBSTACK_USER_AGENT = "Mozilla/5.0 (Linux; Android 15; Pixel 9 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36"

        private val SCRAPING_INBOX_JS = """
            (function() {
                var results = [];
                var cards = document.querySelectorAll('a[href*="/p/"], div[class*="reader2-post"], div[class*="inbox-item"]');
                var seenUrls = new Set();

                cards.forEach(function(card) {
                    var linkEl = card.tagName === 'A' ? card : card.querySelector('a[href*="/p/"]');
                    if (!linkEl) return;
                    var href = linkEl.href;
                    if (!href || seenUrls.has(href)) return;
                    seenUrls.add(href);

                    var titleEl = card.querySelector('h1, h2, h3, [class*="title"]');
                    var title = titleEl ? (titleEl.innerText || '').trim() : '';
                    if (!title) return;

                    var authorEl = card.querySelector('[class*="author"], [class*="byline"]');
                    var author = authorEl ? (authorEl.innerText || '').trim() : 'Substack';

                    var pubEl = card.querySelector('[class*="publication"], [class*="pub-name"]');
                    var pub = pubEl ? (pubEl.innerText || '').trim() : 'Substack';

                    var descEl = card.querySelector('[class*="subtitle"], [class*="description"], p');
                    var desc = descEl ? (descEl.innerText || '').trim() : '';

                    var imgEl = card.querySelector('img[src*="substack"]');
                    var img = imgEl ? (imgEl.src || '') : '';

                    results.push({
                        title: title,
                        url: href,
                        author: author,
                        publication: pub,
                        description: desc,
                        imageUrl: img
                    });
                });
                return JSON.stringify(results.slice(0, 30));
            })()
        """.trimIndent()

        private val EXTRACT_SUBSTACK_JS = """
            (function() {
                var junk = document.querySelectorAll('.subscription-widget-wrap, .subscription-widget-wrap-editor, .subscribe-widget, .paywall-content-cta, .login-modal, .post-ufi, .post-footer, .like-button-container, .share-dialog, .comment-widget, .comments-page, .image-link-expand, button.restack-image, button.view-image');
                junk.forEach(function(el) { el.remove(); });

                var bodyMarkup = document.querySelector('.body.markup, .available-content, [data-testid="post-body"]');
                if (bodyMarkup && (bodyMarkup.innerText || '').trim().length > 120) {
                    return bodyMarkup.innerHTML;
                }

                var article = document.querySelector('article.post, article, .entry-content, div.post-content');
                if (article && (article.innerText || '').trim().length > 200) {
                    var clone = article.cloneNode(true);
                    var dupHeader = clone.querySelectorAll('.post-header, header, h1, script, style');
                    dupHeader.forEach(function(el) { el.remove(); });
                    return clone.innerHTML;
                }
                return '';
            })()
        """.trimIndent()
    }
}
