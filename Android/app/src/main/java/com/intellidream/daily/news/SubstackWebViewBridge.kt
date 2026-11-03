package com.intellidream.daily.news

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.webkit.CookieManager
import android.webkit.WebView
import android.webkit.WebViewClient
import com.intellidream.daily.model.ArticleExtractor
import com.intellidream.daily.model.FeedCategory
import com.intellidream.daily.model.NewsArticle
import com.intellidream.daily.model.optimizeSubstackImageUrl
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONArray
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

    suspend fun scrapeInbox(): List<NewsArticle>? = withContext(Dispatchers.Main) {
        withTimeoutOrNull(25000L) {
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

                continuation.invokeOnCancellation {
                    cleanup()
                }

                val handler = Handler(Looper.getMainLooper())

                webView.webViewClient = object : WebViewClient() {
                    private var hasScraped = false

                    override fun onPageFinished(view: WebView?, loadedUrl: String?) {
                        super.onPageFinished(view, loadedUrl)
                        if (hasScraped) return

                        var attempts = 0
                        val maxAttempts = 8

                        val checkRunnable = object : Runnable {
                            override fun run() {
                                if (hasScraped || !continuation.isActive) return
                                attempts++

                                webView.evaluateJavascript("document.querySelectorAll('a[href*=\"/p/\"], [class*=\"post\"]').length") { countStr ->
                                    val count = countStr?.toIntOrNull() ?: 0
                                    if (count > 0 || attempts >= maxAttempts) {
                                        hasScraped = true
                                        executeScrapeScript()
                                    } else {
                                        handler.postDelayed(this, 800)
                                    }
                                }
                            }
                        }

                        handler.postDelayed(checkRunnable, 1500)
                    }

                    private fun executeScrapeScript() {
                        webView.evaluateJavascript(SCRAPING_INBOX_JS) { jsonResult ->
                            cleanup()
                            if (jsonResult.isNullOrBlank() || jsonResult == "null" || jsonResult == "\"[]\"" || jsonResult == "[]") {
                                if (continuation.isActive) continuation.resume(null)
                                return@evaluateJavascript
                            }

                            try {
                                val rawJson = if (jsonResult.startsWith("\"") && jsonResult.endsWith("\"")) {
                                    org.json.JSONTokener(jsonResult).nextValue().toString()
                                } else {
                                    jsonResult
                                }

                                val jsonArray = JSONArray(rawJson)
                                val list = mutableListOf<NewsArticle>()

                                for (i in 0 until jsonArray.length()) {
                                    val item = jsonArray.getJSONObject(i)
                                    val title = item.optString("title").trim()
                                    val storyUrl = item.optString("url").trim()
                                    val author = item.optString("author", "Substack").trim()
                                    val pubName = item.optString("publication", "Substack").trim()
                                    val imageUrl = item.optString("imageUrl", "")
                                    val desc = item.optString("description", "")

                                    if (title.isBlank() || storyUrl.isBlank()) continue

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
                                    continuation.resume(if (list.isNotEmpty()) list else null)
                                }
                            } catch (_: Throwable) {
                                if (continuation.isActive) continuation.resume(null)
                            }
                        }
                    }
                }

                webView.loadUrl("https://substack.com/inbox")
            }
        }
    }

    suspend fun extractArticle(url: String, baseArticle: NewsArticle? = null): NewsArticle? = withContext(Dispatchers.Main) {
        withTimeoutOrNull(25000L) {
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
                            val uri = android.net.Uri.parse(url)
                            val host = uri.host
                            if (host != null && (host.endsWith(".substack.com") || host.contains("substack"))) {
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

                continuation.invokeOnCancellation {
                    cleanup()
                }

                val handler = Handler(Looper.getMainLooper())

                webView.webViewClient = object : WebViewClient() {
                    private var hasExtracted = false

                    override fun onPageFinished(view: WebView?, loadedUrl: String?) {
                        super.onPageFinished(view, loadedUrl)
                        if (hasExtracted) return

                        val pollRunnable = object : Runnable {
                            private var polls = 0
                            private val maxPolls = 8

                            override fun run() {
                                if (hasExtracted || !continuation.isActive) return
                                polls++

                                webView.evaluateJavascript(EXTRACT_SUBSTACK_JS) { jsonResult ->
                                    if (!jsonResult.isNullOrBlank() && jsonResult != "null" && jsonResult != "\"\"") {
                                        val content = if (jsonResult.startsWith("\"") && jsonResult.endsWith("\"")) {
                                            try {
                                                org.json.JSONTokener(jsonResult).nextValue().toString()
                                            } catch (_: Throwable) { jsonResult }
                                        } else jsonResult

                                        val isTeaser = ArticleExtractor.isSubstackTeaser(content)
                                        if (content.length > 250 && (!isTeaser || polls >= maxPolls)) {
                                            hasExtracted = true
                                            cleanup()

                                            val cleaned = ArticleExtractor.stripSubstackTrackingAndNoise(content)
                                            val updated = (baseArticle ?: NewsArticle(
                                                id = UUID.randomUUID().toString(),
                                                title = "Substack Article",
                                                link = url,
                                                publishDate = System.currentTimeMillis()
                                            )).copy(
                                                content = cleaned,
                                                description = baseArticle?.description ?: cleaned.take(200)
                                            )
                                            if (continuation.isActive) continuation.resume(updated)
                                            return@evaluateJavascript
                                        }
                                    }

                                    if (polls < maxPolls) {
                                        handler.postDelayed(this, 1000)
                                    } else {
                                        hasExtracted = true
                                        cleanup()
                                        if (continuation.isActive) continuation.resume(null)
                                    }
                                }
                            }
                        }

                        handler.postDelayed(pollRunnable, 1200)
                    }
                }

                webView.loadUrl(url)
            }
        }
    }

    companion object {
        const val SUBSTACK_USER_AGENT = "Mozilla/5.0 (Linux; Android 15; Pixel 9 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36"

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
                // Remove modals and overlays
                var overlays = document.querySelectorAll('.subscription-widget-wrap, .paywall-content-cta, .login-modal, [class*="modal"]');
                overlays.forEach(function(el) {
                    if (el.querySelectorAll('p').length < 3) el.remove();
                });
                
                var body = document.querySelector('.available-content, article.post, .entry-content, div.post-content, main');
                if (body) {
                    var clone = body.cloneNode(true);
                    var junk = clone.querySelectorAll('.post-footer, .like-button-container, .comments-section, button, script, style');
                    junk.forEach(function(j) { j.remove(); });
                    return clone.innerHTML;
                }
                return '';
            })()
        """.trimIndent()
    }
}
