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
import com.intellidream.daily.model.optimizeMediumImageUrl
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONArray
import java.util.Date
import java.util.UUID
import kotlin.coroutines.resume

@SuppressLint("SetJavaScriptEnabled")
class MediumWebViewBridge(private val context: Context) {

    suspend fun scrapeReadingList(url: String): List<NewsArticle>? = withContext(Dispatchers.Main) {
        withTimeoutOrNull(25000L) {
            suspendCancellableCoroutine { continuation ->
                val webView = WebView(context).apply {
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = true
                    settings.userAgentString = "Mozilla/5.0 (Linux; Android 15; Pixel 9 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36"
                    try {
                        val cm = CookieManager.getInstance()
                        cm.setAcceptCookie(true)
                        cm.setAcceptThirdPartyCookies(this, true)
                        val mediumCookies = cm.getCookie("https://medium.com")
                        if (!mediumCookies.isNullOrBlank() && !url.contains("://medium.com")) {
                            val uri = android.net.Uri.parse(url)
                            val host = uri.host
                            if (host != null && host.endsWith(".medium.com")) {
                                mediumCookies.split(";").forEach { cookieStr ->
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

                                webView.evaluateJavascript("document.querySelectorAll('article').length") { countStr ->
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
                        webView.evaluateJavascript(SCRAPING_JS) { jsonResult ->
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
                                    var author = item.optString("author", "Medium").trim()
                                    val imageUrl = item.optString("imageUrl", "")
                                    val desc = item.optString("description", "")

                                    if (title.isBlank() || storyUrl.isBlank()) continue

                                    var pubName = "Medium"
                                    val inIdx = author.indexOf(" in ")
                                    if (inIdx > 0) {
                                        pubName = author.substring(inIdx + 4).trim()
                                        author = author.substring(0, inIdx).trim()
                                    }

                                    val optimizedImg = optimizeMediumImageUrl(imageUrl)

                                    list.add(
                                        NewsArticle(
                                            id = UUID.randomUUID().toString(),
                                            title = title,
                                            link = storyUrl,
                                            publishDate = System.currentTimeMillis(),
                                            imageUrl = optimizedImg.ifEmpty { null },
                                            description = desc.ifEmpty { "Author: $author. Read this story on Medium." },
                                            content = null,
                                            author = author,
                                            publicationName = pubName,
                                            publicationIconUrl = "https://www.google.com/s2/favicons?domain=medium.com&sz=64",
                                            category = FeedCategory.Tech
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

                webView.loadUrl(url)
            }
        }
    }

    suspend fun extractArticle(url: String, baseArticle: NewsArticle? = null): NewsArticle? = withContext(Dispatchers.Main) {
        withTimeoutOrNull(25000L) {
            suspendCancellableCoroutine { continuation ->
                val webView = WebView(context).apply {
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = true
                    settings.userAgentString = "Mozilla/5.0 (Linux; Android 15; Pixel 9 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36"
                    try {
                        val cm = CookieManager.getInstance()
                        cm.setAcceptCookie(true)
                        cm.setAcceptThirdPartyCookies(this, true)
                        val mediumCookies = cm.getCookie("https://medium.com")
                        if (!mediumCookies.isNullOrBlank() && !url.contains("://medium.com")) {
                            val uri = android.net.Uri.parse(url)
                            val host = uri.host
                            if (host != null && host.endsWith(".medium.com")) {
                                mediumCookies.split(";").forEach { cookieStr ->
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

                        val cleanupJs = """
                            (function(){
                                var selectors=['#cmp-app-container','.cookie-banner','#cookie-consent','.gdpr-modal',
                                '[class*="cookie"]','[id*="cookie"]','[class*="consent"]','[class*="paywall"]',
                                '[id*="consent"]','[class*="overlay"]','[id*="piano"]'];
                                selectors.forEach(function(s){
                                    document.querySelectorAll(s).forEach(function(e){
                                        if(e.tagName==='ARTICLE'||e.tagName==='MAIN'||e.tagName==='SECTION') return;
                                        if(e.querySelectorAll('p').length>=2||(e.innerText||'').length>300) return;
                                        e.remove();
                                    });
                                });
                                var upsells=['.meteredContentUpsell','[data-testid="paywall-dialog"]','[data-testid="upgrade-banner"]','[data-testid="postPaywallBanner"]'];
                                upsells.forEach(function(s){
                                    document.querySelectorAll(s).forEach(function(e){
                                        if(e.querySelectorAll('p').length<2&&(e.innerText||'').length<300) e.remove();
                                    });
                                });
                                document.body.style.overflow='auto';document.documentElement.style.overflow='auto';
                                var main=document.querySelector('article')||document.querySelector('main')||document.querySelector('[role="main"]');
                                if(main){main.style.display='block';main.style.visibility='visible';main.style.opacity='1';}
                            })()
                        """.trimIndent()

                        val extractJs = """
                            (function(){
                                var selectors='article, main, [itemprop="articleBody"], .article-body, .article-content, .post-content, .entry-content, .layout-article-body';
                                var el=document.querySelector(selectors);
                                if(el && el.innerText && el.innerText.length > 200) {
                                    var clone = el.cloneNode(true);
                                    var junk = clone.querySelectorAll('button, [data-testid*="clap"], [data-testid*="response"], .responsesStream, [data-testid="postSidebar"]');
                                    junk.forEach(function(j){ j.remove(); });
                                    return '<html><head><meta charset="utf-8"/></head><body>'+clone.outerHTML+'</body></html>';
                                }
                                if(document.body && document.body.innerText && document.body.innerText.length > 500) {
                                    return document.documentElement.outerHTML;
                                }
                                return null;
                            })()
                        """.trimIndent()

                        var attempts = 0
                        val maxAttempts = 12
                        var lastLen = 0
                        var stableCount = 0

                        val pollRunnable = object : Runnable {
                            override fun run() {
                                if (hasExtracted || !continuation.isActive) return
                                attempts++

                                // Hydration scroll triggers on early iterations
                                if (attempts == 2) {
                                    webView.evaluateJavascript("window.scrollTo(0, document.body.scrollHeight / 2);", null)
                                } else if (attempts == 4) {
                                    webView.evaluateJavascript("window.scrollTo(0, document.body.scrollHeight);", null)
                                } else if (attempts == 6) {
                                    webView.evaluateJavascript("window.scrollTo(0, 0);", null)
                                }

                                if (attempts % 4 == 0) {
                                    webView.evaluateJavascript(cleanupJs, null)
                                }

                                val lenCheckJs = "(function(){ var el = document.querySelector('article') || document.querySelector('main') || document.body; return el && el.innerText ? el.innerText.length : 0; })()"
                                webView.evaluateJavascript(lenCheckJs) { lenStr ->
                                    val curLen = lenStr?.toIntOrNull() ?: 0

                                    if (curLen > 300) {
                                        if (curLen == lastLen) {
                                            stableCount++
                                        } else {
                                            stableCount = 0
                                            lastLen = curLen
                                        }
                                    }

                                    val isReady = (curLen > 3000 && stableCount >= 2) ||
                                                  (attempts >= 8 && curLen > 1000 && stableCount >= 2) ||
                                                  (attempts >= 11 && curLen > 500) ||
                                                  attempts >= maxAttempts

                                    if (isReady) {
                                        hasExtracted = true
                                        webView.evaluateJavascript(extractJs) { htmlResult ->
                                            cleanup()
                                            if (htmlResult.isNullOrBlank() || htmlResult == "null") {
                                                if (continuation.isActive) continuation.resume(null)
                                                return@evaluateJavascript
                                            }

                                            try {
                                                val rawHtml = if (htmlResult.startsWith("\"") && htmlResult.endsWith("\"")) {
                                                    org.json.JSONTokener(htmlResult).nextValue().toString()
                                                } else {
                                                    htmlResult
                                                }

                                                if (rawHtml.length > 100) {
                                                    val parsed = ArticleExtractor.shared.parseHtml(rawHtml, url, baseArticle)
                                                    if (continuation.isActive) continuation.resume(parsed)
                                                } else {
                                                    if (continuation.isActive) continuation.resume(null)
                                                }
                                            } catch (_: Throwable) {
                                                if (continuation.isActive) continuation.resume(null)
                                            }
                                        }
                                    } else {
                                        handler.postDelayed(this, 600)
                                    }
                                }
                            }
                        }

                        // Start polling after 1.5s initial settle time
                        handler.postDelayed(pollRunnable, 1500)
                    }
                }

                webView.loadUrl(url)
            }
        }
    }

    companion object {
        private val SCRAPING_JS = """
            (function() {
                var articles = [];
                var items = document.querySelectorAll('article');
                
                function getStoryUrl(item) {
                    var titleEl = item.querySelector('h2');
                    if (titleEl) {
                        var a = titleEl.querySelector('a') || titleEl.closest('a');
                        if (a && a.href) return a.href;
                    }
                    
                    var links = item.querySelectorAll('a');
                    for (var i = 0; i < links.length; i++) {
                        var href = links[i].href;
                        if (!href) continue;
                        
                        var urlObj;
                        try {
                            urlObj = new URL(href);
                        } catch(e) {
                            continue;
                        }
                        var pathname = urlObj.pathname;
                        
                        if (pathname.includes('/tag/') || pathname.includes('/tagged/') || pathname.includes('/me') || pathname === '/' || pathname === '') {
                            continue;
                        }
                        
                        var parts = pathname.split('/').filter(Boolean);
                        if (parts.length === 1 && parts[0].startsWith('@')) {
                            continue;
                        }
                        
                        if (pathname.includes('/p/') || parts.length >= 2 || (parts.length === 1 && !parts[0].startsWith('@'))) {
                            return href;
                        }
                    }
                    return '';
                }

                function getAuthorInfo(item) {
                    var links = item.querySelectorAll('a');
                    for (var i = 0; i < links.length; i++) {
                        var href = links[i].href;
                        if (!href) continue;
                        
                        try {
                            var urlObj = new URL(href);
                            if (urlObj.hostname === 'medium.com' && urlObj.pathname.startsWith('/@')) {
                                var parts = urlObj.pathname.split('/').filter(Boolean);
                                if (parts.length === 1) {
                                    return {
                                        url: href,
                                        name: (links[i].innerText || links[i].textContent || '').trim()
                                    };
                                }
                            }
                            if (urlObj.hostname.endsWith('.medium.com') && urlObj.hostname.split('.').length === 3) {
                                var sub = urlObj.hostname.split('.')[0];
                                if (sub !== 'www' && sub !== 'api' && urlObj.pathname === '/') {
                                    return {
                                        url: href,
                                        name: (links[i].innerText || links[i].textContent || '').trim()
                                    };
                                }
                            }
                        } catch(e) {}
                    }
                    return null;
                }

                items.forEach(function(item) {
                    try {
                        var titleEl = item.querySelector('h2');
                        var title = titleEl ? titleEl.innerText : '';
                        
                        var storyUrl = getStoryUrl(item);
                        var authorInfo = getAuthorInfo(item);
                        
                        var authorName = authorInfo ? authorInfo.name : '';
                        var authorUrl = authorInfo ? authorInfo.url : '';

                        if (!authorName) {
                            var authorEl = item.querySelector('p');
                            if (authorEl) {
                                authorName = authorEl.innerText;
                            }
                        }
                        
                        var description = '';
                        var h3El = item.querySelector('h3');
                        if (h3El) {
                            description = h3El.innerText;
                        } else {
                            var pElements = item.querySelectorAll('p');
                            pElements.forEach(function(p) {
                                var txt = p.innerText || '';
                                if (txt.length > 30 && !txt.includes('min read') && !txt.includes('member-only')) {
                                    description = txt;
                                }
                            });
                        }
                        
                        var img = item.querySelector('img');
                        var imageUrl = img ? img.src : '';
                        
                        title = title.trim();
                        authorName = (authorName || '').trim();
                        description = (description || '').trim();
                        
                        if (title && storyUrl) {
                            articles.push({
                                title: title,
                                url: storyUrl,
                                author: authorName || 'Medium',
                                authorUrl: authorUrl || '',
                                imageUrl: imageUrl,
                                description: description
                            });
                        }
                    } catch(e) { }
                });
                return JSON.stringify(articles);
            })();
        """.trimIndent()
    }
}
