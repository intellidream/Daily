package com.intellidream.daily.presentation.prism

import android.annotation.SuppressLint
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.net.Uri
import android.os.Message
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.Canvas as ComposeCanvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material.icons.automirrored.rounded.OpenInNew
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Article
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Bookmark
import androidx.compose.material.icons.rounded.BookmarkBorder
import androidx.compose.material.icons.rounded.Checklist
import androidx.compose.material.icons.rounded.ChevronLeft
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.ContentPaste
import androidx.compose.material.icons.rounded.Crop
import androidx.compose.material.icons.rounded.DeleteOutline
import androidx.compose.material.icons.rounded.FormatQuote
import androidx.compose.material.icons.rounded.Image
import androidx.compose.material.icons.rounded.Language
import androidx.compose.material.icons.rounded.Link
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.OpenInFull
import androidx.compose.material.icons.rounded.PushPin
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.RssFeed
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Send
import androidx.compose.material.icons.rounded.Shield
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material.icons.rounded.StarBorder
import androidx.compose.material.icons.rounded.VisibilityOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.intellidream.daily.database.NewsRepository
import com.intellidream.daily.database.PrismRepository
import com.intellidream.daily.database.TagdosRepository
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.AppSettings
import com.intellidream.daily.model.FeedCategory
import com.intellidream.daily.model.NewsArticle
import com.intellidream.daily.model.PrismClip
import com.intellidream.daily.model.PrismClipType
import com.intellidream.daily.model.PrismCoPilotAction
import com.intellidream.daily.model.PrismCoPilotTurn
import com.intellidream.daily.model.PrismSearchEngine
import com.intellidream.daily.model.PrismShieldRules
import com.intellidream.daily.network.PrismRemoteService
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.io.ByteArrayInputStream
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

private const val MOBILE_CHROME_UA =
    "Mozilla/5.0 (Linux; Android 15; Pixel 9 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36"

private const val PRISM_OBSERVER_JS = """
(function() {
    if (window.__prismAndroidObserver) return;
    window.__prismAndroidObserver = true;

    function sniffMeta() {
        try {
            var rss = document.querySelector('link[rel="alternate"][type*="rss"], link[rel="alternate"][type*="atom"], link[rel="alternate"][type*="feed+json"]');
            var rssUrl = rss ? rss.href : '';
            var rssTitle = rss ? (rss.title || document.title || '') : '';
            var host = (location.hostname || '').toLowerCase();
            if (!rssUrl && host.endsWith('.substack.com') && host !== 'www.substack.com' && host !== 'open.substack.com') {
                rssUrl = location.protocol + '//' + host + '/feed';
                rssTitle = document.title || host;
            }
            var og = document.querySelector('meta[property="og:image"], meta[name="twitter:image"]');
            if (window.PrismBridge) {
                window.PrismBridge.onMetadata(document.title || '', og ? og.content : '', rssUrl, rssTitle);
            }
        } catch (e) {}
    }
    sniffMeta();

    var selTimer = null;
    document.addEventListener('selectionchange', function() {
        clearTimeout(selTimer);
        selTimer = setTimeout(function() {
            try {
                var sel = window.getSelection();
                var txt = sel ? sel.toString().trim() : '';
                if (txt.length >= 3 && sel.rangeCount > 0) {
                    var r = sel.getRangeAt(0).getBoundingClientRect();
                    window.PrismBridge.onSelection(txt.slice(0, 4000), r.left + r.width / 2, r.top, r.bottom, window.innerWidth, window.innerHeight);
                } else {
                    window.PrismBridge.onSelectionCleared();
                }
            } catch (e) {}
        }, 180);
    }, { passive: true });

    var imgTimer = null;
    document.addEventListener('touchstart', function(ev) {
        var img = ev.target && ev.target.closest ? ev.target.closest('img') : null;
        if (!img || !(img.currentSrc || img.src)) return;
        if ((img.width || 0) < 72 && (img.height || 0) < 72) return;
        clearTimeout(imgTimer);
        imgTimer = setTimeout(function() {
            window.PrismBridge.onImageCandidate(img.currentSrc || img.src, img.alt || document.title || 'Web Image');
        }, 560);
    }, { passive: true });
    document.addEventListener('touchmove', function() { clearTimeout(imgTimer); }, { passive: true });
    document.addEventListener('touchend', function() { clearTimeout(imgTimer); }, { passive: true });

    var scTimer = null;
    window.addEventListener('scroll', function() {
        if (scTimer) return;
        scTimer = setTimeout(function() {
            scTimer = null;
            window.PrismBridge.onScroll(Math.round(window.scrollY || 0));
        }, 420);
    }, { passive: true });

    window.__prismExtractContext = function() {
        var sel = window.getSelection ? window.getSelection().toString().trim() : '';
        var mainEl = document.querySelector('article, main, [role="main"]') || document.body;
        var text = mainEl ? (mainEl.innerText || '').replace(/\n{3,}/g, '\n\n').trim().slice(0, 16000) : '';
        return JSON.stringify({ title: document.title || '', url: location.href, selectedText: sel.slice(0, 3500), bodyText: text });
    };
})();
"""

private data class AndroidSelectionState(
    val text: String,
    val centerXRatio: Float,
    val topYRatio: Float
)

@OptIn(ExperimentalMaterial3Api::class)
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun PrismMainView(
    prismRepository: PrismRepository,
    prismRemoteService: PrismRemoteService,
    tagdosRepository: TagdosRepository,
    newsRepository: NewsRepository,
    settings: AppSettings,
    onUpdateSettings: ((AppSettings) -> AppSettings) -> Unit,
    isFullResearchModeExternal: Boolean = false,
    onToggleFullResearchMode: (() -> Unit)? = null,
    onNavigateBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val haptic = LocalHapticFeedback.current
    val focusManager = LocalFocusManager.current
    val scope = rememberCoroutineScope()

    val tabs by prismRepository.tabs.collectAsState()
    val activeTabId by prismRepository.activeTabId.collectAsState()
    val clips by prismRepository.clips.collectAsState()
    val pinnedSites by prismRepository.pinnedSites.collectAsState()
    val pendingUrl by prismRepository.pendingUrlRequest.collectAsState()
    val clipboardCandidate by prismRepository.clipboardCandidateUrl.collectAsState()

    val activeTab = remember(tabs, activeTabId) {
        tabs.firstOrNull { it.id == activeTabId } ?: tabs.firstOrNull()
    }

    var currentUrl by remember { mutableStateOf(activeTab?.url.orEmpty()) }
    var omniboxInput by remember { mutableStateOf(activeTab?.url.orEmpty()) }
    var pageTitle by remember { mutableStateOf(activeTab?.title ?: "Start Page") }
    var isLoading by remember { mutableStateOf(false) }
    var loadProgress by remember { mutableFloatStateOf(0f) }
    var canGoBack by remember { mutableStateOf(false) }
    var canGoForward by remember { mutableStateOf(false) }
    var ogImageUrl by remember { mutableStateOf<String?>(null) }
    var detectedRssUrl by remember { mutableStateOf<String?>(activeTab?.detectedRssUrl) }
    var detectedRssTitle by remember { mutableStateOf<String?>(activeTab?.detectedRssTitle) }

    var isBottomOmniboxCollapsed by remember { mutableStateOf(false) }
    var lastScrollY by remember { mutableIntStateOf(0) }

    var selectionState by remember { mutableStateOf<AndroidSelectionState?>(null) }
    var imageCandidate by remember { mutableStateOf<Pair<String, String>?>(null) }
    var oauthPopupTransport by remember { mutableStateOf<Message?>(null) }

    var isReaderMode by remember { mutableStateOf(false) }
    var readerArticle by remember { mutableStateOf<NewsArticle?>(null) }
    var isExtractingReader by remember { mutableStateOf(false) }

    var isRegionCropMode by remember { mutableStateOf(false) }
    var cropStart by remember { mutableStateOf<Offset?>(null) }
    var cropEnd by remember { mutableStateOf<Offset?>(null) }

    var showStudioSheet by remember { mutableStateOf(false) }
    var isWideSideStudioVisible by remember { mutableStateOf(isFullResearchModeExternal) }
    var activeStudioPaneTab by remember { mutableIntStateOf(0) } // 0 = Co-Pilot, 1 = Vault

    val turns = remember { mutableStateListOf<PrismCoPilotTurn>() }
    var isGeneratingTurn by remember { mutableStateOf(false) }

    var showMoreMenu by remember { mutableStateOf(false) }
    var showAddPinDialog by remember { mutableStateOf(false) }
    var toastMessage by remember { mutableStateOf<String?>(null) }

    fun showToast(msg: String) {
        haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
        toastMessage = msg
        scope.launch {
            delay(2200)
            if (toastMessage == msg) toastMessage = null
        }
    }

    // Single-Active WebView instance
    val webViewHolder = remember { mutableStateOf<WebView?>(null) }

    // Inspect clipboard on entry
    LaunchedEffect(Unit) {
        val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
        val clipTxt = cm?.primaryClip?.getItemAt(0)?.coerceToText(context)?.toString()
        prismRepository.checkClipboardCandidate(clipTxt, settings.prismClipboardDetectEnabled)
    }

    // React to external URL requests (from Dashboard Speed Dial, News, Share Intent)
    LaunchedEffect(pendingUrl) {
        val req = prismRepository.consumePendingUrlRequest()
        if (!req.isNullOrBlank()) {
            currentUrl = req
            omniboxInput = req
            isReaderMode = false
            webViewHolder.value?.loadUrl(req)
        }
    }

    // Sync active tab switches (hibernating previous tab & restoring target tab URL/scroll)
    LaunchedEffect(activeTabId) {
        val tab = prismRepository.activeTab() ?: return@LaunchedEffect
        selectionState = null
        isReaderMode = tab.isReaderMode
        detectedRssUrl = tab.detectedRssUrl
        detectedRssTitle = tab.detectedRssTitle
        currentUrl = tab.url
        omniboxInput = tab.url
        pageTitle = tab.title
        isBottomOmniboxCollapsed = false
        if (!tab.isStartPage && webViewHolder.value?.url != tab.url) {
            webViewHolder.value?.loadUrl(tab.url)
        }
    }

    DisposableEffect(Unit) {
        onDispose {
            try {
                CookieManager.getInstance().flush()
                webViewHolder.value?.onPause()
            } catch (_: Exception) {}
        }
    }

    val currentSearchEngine = PrismSearchEngine.fromId(settings.prismSearchEngine)
    val currentDomain = remember(currentUrl) { PrismSearchEngine.extractCleanDomain(currentUrl) }
    val isShieldActiveForDomain = remember(settings.prismShieldEnabled, settings.prismShieldAllowlist, currentDomain) {
        settings.prismShieldEnabled && (currentDomain.isEmpty() || settings.prismShieldAllowlist.none { it.equals(currentDomain, ignoreCase = true) })
    }

    fun toggleShieldForDomain() {
        if (currentDomain.isEmpty()) {
            onUpdateSettings { it.copy(prismShieldEnabled = !it.prismShieldEnabled) }
        } else {
            onUpdateSettings { s ->
                val list = s.prismShieldAllowlist.toMutableList()
                val existing = list.indexOfFirst { it.equals(currentDomain, ignoreCase = true) }
                if (!s.prismShieldEnabled) {
                    list.removeAll { it.equals(currentDomain, ignoreCase = true) }
                    s.copy(prismShieldEnabled = true, prismShieldAllowlist = list)
                } else if (existing >= 0) {
                    list.removeAt(existing)
                    s.copy(prismShieldAllowlist = list)
                } else {
                    list.add(currentDomain)
                    s.copy(prismShieldAllowlist = list)
                }
            }
        }
        webViewHolder.value?.reload()
        showToast(if (!isShieldActiveForDomain) "Prism Shield Enabled" else "Shield Paused for Domain")
    }

    fun navigateOmnibox(raw: String) {
        focusManager.clearFocus()
        val resolved = PrismSearchEngine.resolveOmniboxInput(raw, currentSearchEngine)
        if (resolved == null) {
            showToast("Blocked or invalid address")
            return
        }
        isReaderMode = false
        selectionState = null
        currentUrl = resolved
        omniboxInput = resolved
        prismRepository.updateActiveTabMetadata(url = resolved, isReaderMode = false, detectedRssUrl = null, detectedRssTitle = null)
        webViewHolder.value?.loadUrl(resolved)
    }

    fun toggleReaderMode() {
        if (currentUrl.isBlank()) return
        if (isReaderMode) {
            isReaderMode = false
            prismRepository.updateActiveTabMetadata(isReaderMode = false)
            return
        }
        isReaderMode = true
        isExtractingReader = true
        prismRepository.updateActiveTabMetadata(isReaderMode = true)
        val base = NewsArticle(
            title = pageTitle.ifBlank { currentDomain },
            link = currentUrl,
            imageUrl = ogImageUrl.orEmpty(),
            publicationName = currentDomain,
            publicationIconUrl = PrismSearchEngine.faviconUrl(currentUrl)
        )
        scope.launch {
            readerArticle = newsRepository.fetchFullArticle(base)
            isExtractingReader = false
        }
    }

    suspend fun extractDomContext(): Pair<String, String> {
        val wv = webViewHolder.value ?: return "" to ""
        return kotlinx.coroutines.suspendCancellableCoroutine { cont ->
            wv.evaluateJavascript("window.__prismExtractContext ? window.__prismExtractContext() : ''") { raw ->
                try {
                    val unescaped = org.json.JSONTokener(raw ?: "\"\"").nextValue()?.toString().orEmpty()
                    if (unescaped.isNotBlank()) {
                        val obj = JSONObject(unescaped)
                        cont.resumeWith(Result.success(obj.optString("bodyText", "") to obj.optString("selectedText", "")))
                    } else {
                        cont.resumeWith(Result.success("" to ""))
                    }
                } catch (_: Exception) {
                    cont.resumeWith(Result.success("" to ""))
                }
            }
        }
    }

    fun executeCoPilotAction(action: PrismCoPilotAction, overrideSelection: String? = null) {
        if (currentUrl.isBlank()) return
        isGeneratingTurn = true
        scope.launch {
            val (bodyText, selText) = extractDomContext()
            val turn = prismRemoteService.runCoPilotAction(
                action = action,
                pageTitle = pageTitle,
                pageUrl = currentUrl,
                bodyText = bodyText,
                selectedText = overrideSelection ?: selText,
                apiKey = settings.geminiApiKey
            )
            turns.add(0, turn)
            isGeneratingTurn = false
        }
    }

    BoxWithConstraints(modifier = modifier.fillMaxSize()) {
        val isWideFoldable = maxWidth >= 600.dp

        Box(modifier = Modifier.fillMaxSize()) {
            Column(modifier = Modifier.fillMaxSize()) {
                // Top Header Bar
                PrismTopBar(
                    isWideFoldable = isWideFoldable,
                    tabs = tabs,
                    activeTabId = activeTab?.id,
                    omniboxInput = omniboxInput,
                    onOmniboxChange = { omniboxInput = it },
                    onOmniboxSubmit = { navigateOmnibox(omniboxInput) },
                    currentUrl = currentUrl,
                    canGoBack = canGoBack || isReaderMode,
                    isLoading = isLoading,
                    isShieldActive = isShieldActiveForDomain,
                    isReaderMode = isReaderMode,
                    isRegionCropMode = isRegionCropMode,
                    detectedRssUrl = detectedRssUrl,
                    isFullResearchModeExternal = isFullResearchModeExternal,
                    canToggleFullResearchMode = onToggleFullResearchMode != null,
                    isWideStudioVisible = isWideSideStudioVisible,
                    clipsCount = clips.size,
                    showMoreMenu = showMoreMenu,
                    onSetShowMoreMenu = { showMoreMenu = it },
                    currentSearchEngine = currentSearchEngine,
                    onSelectSearchEngine = { se -> onUpdateSettings { it.copy(prismSearchEngine = se.id) } },
                    onNavigateBack = onNavigateBack,
                    onWebBack = {
                        if (isReaderMode) isReaderMode = false else webViewHolder.value?.goBack()
                    },
                    onReload = {
                        if (isLoading) webViewHolder.value?.stopLoading() else webViewHolder.value?.reload()
                    },
                    onToggleShield = ::toggleShieldForDomain,
                    onSelectTab = { prismRepository.selectTab(it) },
                    onCloseTab = { prismRepository.closeTab(it) },
                    onNewTab = { prismRepository.openNewTab(isPrivate = it) },
                    onSaveBookmark = {
                        prismRepository.saveLinkClip(currentUrl, pageTitle, ogImageUrl)
                        showToast("Saved Link to Prism Vault")
                    },
                    onTogglePin = {
                        prismRepository.togglePinSite(pageTitle, currentUrl)
                        showToast("Updated Speed Dial")
                    },
                    onToggleReader = ::toggleReaderMode,
                    onToggleCrop = { isRegionCropMode = !isRegionCropMode },
                    onOpenExternal = {
                        try {
                            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(currentUrl)))
                        } catch (_: Exception) {}
                    },
                    onSubscribeRss = { rss ->
                        scope.launch {
                            newsRepository.addFeed(
                                name = (detectedRssTitle ?: pageTitle).ifBlank { currentDomain },
                                url = rss,
                                category = FeedCategory.Tech
                            )
                        }
                        showToast("Subscribed in News Hub!")
                    },
                    onToggleFullResearchMode = {
                        onToggleFullResearchMode?.invoke()
                        if (!isFullResearchModeExternal) isWideSideStudioVisible = true
                    },
                    onToggleWideStudio = { isWideSideStudioVisible = !isWideSideStudioVisible }
                )

                if (isLoading) {
                    LinearProgressIndicator(
                        progress = { loadProgress.coerceIn(0.08f, 1f) },
                        modifier = Modifier.fillMaxWidth().height(2.dp),
                        color = ThemeColors.accentCyan,
                        trackColor = Color.Transparent
                    )
                } else {
                    HorizontalDivider(color = Color.White.copy(alpha = 0.08f))
                }

                // Main Split Canvas (65% Web + 35% Studio on Unfolded RADAR, or Full Bleed on Trapper)
                Row(modifier = Modifier.weight(1f).fillMaxWidth()) {
                    Box(modifier = Modifier.weight(if (isWideFoldable && isWideSideStudioVisible) 0.64f else 1f).fillMaxHeight()) {
                        when {
                            activeTab?.isStartPage != false -> {
                                PrismStartPage(
                                    pinnedSites = pinnedSites,
                                    recentClips = clips.take(5),
                                    clipboardCandidate = clipboardCandidate,
                                    isWide = isWideFoldable,
                                    onOpenUrl = ::navigateOmnibox,
                                    onSaveClipboard = { url ->
                                        prismRepository.dismissClipboardCandidate()
                                        prismRepository.saveLinkClip(url, PrismSearchEngine.extractCleanDomain(url))
                                        showToast("Saved Clipboard Link")
                                    },
                                    onDismissClipboard = { prismRepository.dismissClipboardCandidate() },
                                    onAddPinClick = { showAddPinDialog = true },
                                    onDeletePin = { prismRepository.deletePinnedSite(it) },
                                    onOpenAllClips = {
                                        activeStudioPaneTab = 1
                                        if (isWideFoldable) isWideSideStudioVisible = true else showStudioSheet = true
                                    }
                                )
                            }

                            isReaderMode -> {
                                PrismReaderCanvas(
                                    isExtracting = isExtractingReader,
                                    article = readerArticle
                                )
                            }

                            else -> {
                                BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
                                    val density = LocalDensity.current
                                    val widthPx = with(density) { maxWidth.toPx() }
                                    val heightPx = with(density) { maxHeight.toPx() }

                                    AndroidView(
                                        factory = { ctx ->
                                            WebView(ctx).apply {
                                                layoutParams = android.view.ViewGroup.LayoutParams(
                                                    android.view.ViewGroup.LayoutParams.MATCH_PARENT,
                                                    android.view.ViewGroup.LayoutParams.MATCH_PARENT
                                                )
                                                this.settings.javaScriptEnabled = true
                                                this.settings.domStorageEnabled = true
                                                this.settings.databaseEnabled = true
                                                this.settings.cacheMode = if (activeTab?.isPrivate == true) WebSettings.LOAD_NO_CACHE else WebSettings.LOAD_DEFAULT
                                                this.settings.userAgentString = MOBILE_CHROME_UA
                                                this.settings.setSupportMultipleWindows(true)
                                                this.settings.javaScriptCanOpenWindowsAutomatically = true
                                                this.settings.mediaPlaybackRequiresUserGesture = false

                                                val cm = CookieManager.getInstance()
                                                cm.setAcceptCookie(true)
                                                cm.setAcceptThirdPartyCookies(this, true)

                                                addJavascriptInterface(
                                                    object {
                                                        @JavascriptInterface
                                                        fun onMetadata(title: String, ogImg: String, rssUrl: String, rssTitle: String) {
                                                            post {
                                                                if (title.isNotBlank()) pageTitle = title
                                                                ogImageUrl = ogImg.takeIf { it.isNotBlank() }
                                                                detectedRssUrl = rssUrl.takeIf { it.isNotBlank() }
                                                                detectedRssTitle = rssTitle.takeIf { it.isNotBlank() }
                                                                prismRepository.updateActiveTabMetadata(
                                                                    title = title,
                                                                    detectedRssUrl = detectedRssUrl,
                                                                    detectedRssTitle = detectedRssTitle
                                                                )
                                                            }
                                                        }

                                                        @JavascriptInterface
                                                        fun onSelection(text: String, cx: Float, topY: Float, bottomY: Float, vw: Float, vh: Float) {
                                                            post {
                                                                selectionState = AndroidSelectionState(
                                                                    text = text,
                                                                    centerXRatio = (cx / max(1f, vw)).coerceIn(0.15f, 0.85f),
                                                                    topYRatio = (topY / max(1f, vh)).coerceIn(0.08f, 0.82f)
                                                                )
                                                            }
                                                        }

                                                        @JavascriptInterface
                                                        fun onSelectionCleared() {
                                                            post { selectionState = null }
                                                        }

                                                        @JavascriptInterface
                                                        fun onImageCandidate(src: String, alt: String) {
                                                            post {
                                                                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                                                imageCandidate = src to alt
                                                            }
                                                        }

                                                        @JavascriptInterface
                                                        fun onScroll(sy: Int) {
                                                            post {
                                                                val delta = sy - lastScrollY
                                                                if (sy > 90 && delta > 20 && !isBottomOmniboxCollapsed) {
                                                                    isBottomOmniboxCollapsed = true
                                                                } else if ((delta < -16 || sy <= 40) && isBottomOmniboxCollapsed) {
                                                                    isBottomOmniboxCollapsed = false
                                                                }
                                                                lastScrollY = sy
                                                                prismRepository.updateActiveTabMetadata(scrollY = sy)
                                                            }
                                                        }
                                                    },
                                                    "PrismBridge"
                                                )

                                                webViewClient = object : WebViewClient() {
                                                    override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                                                        val scheme = request?.url?.scheme?.lowercase().orEmpty()
                                                        return scheme !in setOf("https", "http", "about", "blob")
                                                    }

                                                    override fun shouldInterceptRequest(view: WebView?, request: WebResourceRequest?): WebResourceResponse? {
                                                        val reqUrl = request?.url?.toString().orEmpty()
                                                        if (PrismShieldRules.shouldBlockRequest(
                                                                requestUrl = reqUrl,
                                                                pageUrl = currentUrl,
                                                                shieldEnabled = settings.prismShieldEnabled,
                                                                allowlist = settings.prismShieldAllowlist
                                                            )
                                                        ) {
                                                            return WebResourceResponse("text/plain", "utf-8", 204, "No Content", emptyMap(), ByteArrayInputStream(ByteArray(0)))
                                                        }
                                                        return super.shouldInterceptRequest(view, request)
                                                    }

                                                    override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                                                        isLoading = true
                                                        selectionState = null
                                                        if (!url.isNullOrBlank() && url != "about:blank") {
                                                            currentUrl = url
                                                            omniboxInput = url
                                                            prismRepository.updateActiveTabMetadata(url = url)
                                                        }
                                                    }

                                                    override fun onPageFinished(view: WebView?, url: String?) {
                                                        isLoading = false
                                                        canGoBack = view?.canGoBack() == true
                                                        canGoForward = view?.canGoForward() == true
                                                        view?.evaluateJavascript(PRISM_OBSERVER_JS, null)
                                                        CookieManager.getInstance().flush()
                                                    }
                                                }

                                                webChromeClient = object : WebChromeClient() {
                                                    override fun onProgressChanged(view: WebView?, newProgress: Int) {
                                                        loadProgress = newProgress / 100f
                                                    }

                                                    override fun onReceivedTitle(view: WebView?, title: String?) {
                                                        if (!title.isNullOrBlank()) {
                                                            pageTitle = title
                                                            prismRepository.updateActiveTabMetadata(title = title)
                                                        }
                                                    }

                                                    override fun onCreateWindow(
                                                        view: WebView?,
                                                        isDialog: Boolean,
                                                        isUserGesture: Boolean,
                                                        resultMsg: Message?
                                                    ): Boolean {
                                                        if (!isUserGesture || resultMsg == null) return false
                                                        oauthPopupTransport = resultMsg
                                                        return true
                                                    }
                                                }

                                                webViewHolder.value = this
                                                if (currentUrl.isNotBlank()) loadUrl(currentUrl)
                                            }
                                        },
                                        update = { wv ->
                                            canGoBack = wv.canGoBack()
                                            canGoForward = wv.canGoForward()
                                        },
                                        modifier = Modifier.fillMaxSize()
                                    )

                                    // Floating Selection Pill
                                    selectionState?.let { sel ->
                                        val pillX = ((widthPx * sel.centerXRatio) - with(density) { 125.dp.toPx() }).roundToInt().coerceAtLeast(16)
                                        val pillY = (heightPx * sel.topYRatio - with(density) { 46.dp.toPx() }).roundToInt().coerceAtLeast(16)
                                        Row(
                                            modifier = Modifier
                                                .offset { IntOffset(pillX, pillY) }
                                                .clip(CircleShape)
                                                .background(Color(0xFF0A1020).copy(alpha = 0.96f))
                                                .border(1.dp, Color.White.copy(alpha = 0.22f), CircleShape)
                                                .padding(5.dp),
                                            horizontalArrangement = Arrangement.spacedBy(6.dp)
                                        ) {
                                            PrismPillChip("Quote", ThemeColors.accentCyan, Color.Black) {
                                                prismRepository.saveQuoteClip(sel.text, currentUrl, pageTitle)
                                                selectionState = null
                                                showToast("Saved Quote to Vault")
                                            }
                                            PrismPillChip("→ TagDoS", Color(0xFFFFB300).copy(alpha = 0.2f), Color(0xFFFFB300)) {
                                                prismRepository.saveQuoteClip(sel.text, currentUrl, pageTitle)
                                                tagdosRepository.createQuickNote(
                                                    title = "💎 $pageTitle",
                                                    content = "> ${sel.text}\n\n🔗 $currentUrl\n#prism"
                                                )
                                                selectionState = null
                                                showToast("Sent Quote to TagDoS (#prism)")
                                            }
                                            PrismPillChip("Explain", Color(0xFFA855F7).copy(alpha = 0.2f), Color(0xFFA855F7)) {
                                                val txt = sel.text
                                                selectionState = null
                                                activeStudioPaneTab = 0
                                                if (isWideFoldable) isWideSideStudioVisible = true else showStudioSheet = true
                                                executeCoPilotAction(PrismCoPilotAction.ExplainSelection, txt)
                                            }
                                        }
                                    }

                                    // Long-Press Image Save Banner
                                    imageCandidate?.let { (imgSrc, imgAlt) ->
                                        Row(
                                            modifier = Modifier
                                                .align(Alignment.TopCenter)
                                                .padding(14.dp)
                                                .clip(CircleShape)
                                                .background(Color(0xFF0A1020).copy(alpha = 0.95f))
                                                .border(1.dp, Color(0xFF10B981).copy(alpha = 0.45f), CircleShape)
                                                .padding(horizontal = 14.dp, vertical = 8.dp),
                                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                                            verticalAlignment = Alignment.CenterVertically
                                        ) {
                                            Icon(Icons.Rounded.Image, null, tint = Color(0xFF10B981), modifier = Modifier.size(16.dp))
                                            Text("Save Image to Prism Vault?", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                                            PrismPillChip("Save", Color(0xFF10B981), Color.Black) {
                                                imageCandidate = null
                                                scope.launch {
                                                    prismRepository.saveImageClip(remoteImageUrl = imgSrc, sourceUrl = currentUrl, title = imgAlt.ifBlank { pageTitle })
                                                    showToast("Image Saved to Vault")
                                                }
                                            }
                                            Icon(
                                                Icons.Rounded.Close,
                                                contentDescription = "Dismiss",
                                                tint = Color.White.copy(alpha = 0.65f),
                                                modifier = Modifier.size(16.dp).clickable { imageCandidate = null }
                                            )
                                        }
                                    }

                                    // Interactive Viewport Region Crop Overlay
                                    if (isRegionCropMode) {
                                        Box(
                                            modifier = Modifier
                                                .fillMaxSize()
                                                .background(Color.Black.copy(alpha = 0.26f))
                                                .pointerInput(Unit) {
                                                    detectDragGestures(
                                                        onDragStart = { start ->
                                                            cropStart = start
                                                            cropEnd = start
                                                        },
                                                        onDrag = { change, _ ->
                                                            cropEnd = change.position
                                                        },
                                                        onDragEnd = {
                                                            val s = cropStart
                                                            val e = cropEnd
                                                            isRegionCropMode = false
                                                            cropStart = null
                                                            cropEnd = null
                                                            val wv = webViewHolder.value
                                                            if (s != null && e != null && wv != null && wv.width > 10 && wv.height > 10) {
                                                                val left = min(s.x, e.x).roundToInt().coerceIn(0, wv.width - 1)
                                                                val top = min(s.y, e.y).roundToInt().coerceIn(0, wv.height - 1)
                                                                val rw = abs(e.x - s.x).roundToInt().coerceAtMost(wv.width - left)
                                                                val rh = abs(e.y - s.y).roundToInt().coerceAtMost(wv.height - top)
                                                                if (rw > 20 && rh > 20) {
                                                                    val fullBmp = Bitmap.createBitmap(wv.width, wv.height, Bitmap.Config.ARGB_8888)
                                                                    wv.draw(Canvas(fullBmp))
                                                                    val cropped = Bitmap.createBitmap(fullBmp, left, top, rw, rh)
                                                                    scope.launch {
                                                                        prismRepository.saveImageClip(
                                                                            bitmap = cropped,
                                                                            sourceUrl = currentUrl,
                                                                            title = "${pageTitle.ifBlank { "Visual Crop" }} (Snapshot)",
                                                                            tags = listOf("snapshot")
                                                                        )
                                                                        showToast("Visual Region Saved to Vault")
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    )
                                                }
                                        ) {
                                            val s = cropStart
                                            val e = cropEnd
                                            if (s != null && e != null) {
                                                ComposeCanvas(modifier = Modifier.fillMaxSize()) {
                                                    val tl = Offset(min(s.x, e.x), min(s.y, e.y))
                                                    val sz = Size(abs(e.x - s.x), abs(e.y - s.y))
                                                    drawRect(Color(0xFF00E5FF).copy(alpha = 0.15f), topLeft = tl, size = sz)
                                                    drawRect(
                                                        Color(0xFF00E5FF),
                                                        topLeft = tl,
                                                        size = sz,
                                                        style = Stroke(width = 4f, pathEffect = PathEffect.dashPathEffect(floatArrayOf(14f, 10f)))
                                                    )
                                                }
                                            }
                                            Row(
                                                modifier = Modifier
                                                    .align(Alignment.TopCenter)
                                                    .padding(top = 12.dp)
                                                    .clip(CircleShape)
                                                    .background(Color.Black.copy(alpha = 0.85f))
                                                    .padding(horizontal = 14.dp, vertical = 8.dp),
                                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                                                verticalAlignment = Alignment.CenterVertically
                                            ) {
                                                Icon(Icons.Rounded.Crop, null, tint = ThemeColors.accentCyan, modifier = Modifier.size(15.dp))
                                                Text("Drag region to capture", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                                                Text(
                                                    "Cancel",
                                                    color = ThemeColors.accentCyan,
                                                    fontSize = 12.sp,
                                                    fontWeight = FontWeight.Bold,
                                                    modifier = Modifier.clickable { isRegionCropMode = false }
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Docked 35% Right Studio Pane on Unfolded Foldable (`RADAR`)
                    if (isWideFoldable && isWideSideStudioVisible) {
                        Box(modifier = Modifier.fillMaxHeight().width(1.dp).background(Color.White.copy(alpha = 0.10f)))
                        PrismStudioContent(
                            activeTab = activeStudioPaneTab,
                            onSelectTab = { activeStudioPaneTab = it },
                            clips = clips,
                            turns = turns,
                            isGeneratingTurn = isGeneratingTurn,
                            currentUrl = currentUrl,
                            pageTitle = pageTitle,
                            prismRepository = prismRepository,
                            onRunCoPilotAction = { executeCoPilotAction(it) },
                            onSubmitCustomQuestion = { q ->
                                isGeneratingTurn = true
                                scope.launch {
                                    val (bodyText, selText) = extractDomContext()
                                    val turn = prismRemoteService.askCoPilotQuestion(q, pageTitle, currentUrl, bodyText, selText, settings.geminiApiKey)
                                    turns.add(0, turn)
                                    isGeneratingTurn = false
                                }
                            },
                            onSendClipToTagdos = { clip ->
                                val tagFooter = (listOf("prism") + clip.tags).distinct().joinToString(" ") { "#$it" }
                                tagdosRepository.createQuickNote(
                                    title = "💎 ${clip.title}",
                                    content = "${if (clip.contentText.isNotBlank()) "> ${clip.contentText}\n\n" else ""}🔗 ${clip.sourceUrl}\n$tagFooter"
                                )
                                showToast("Mirrored to TagDoS (#prism)")
                            },
                            onSendTasksToTagdos = { tasksList ->
                                tagdosRepository.createQuickNote(
                                    title = "🎯 Tasks: $pageTitle",
                                    content = tasksList.joinToString("\n") { "- [ ] $it" } + "\n\n🔗 $currentUrl\n#prism #tasks"
                                )
                                showToast("Sent Tasks to TagDoS")
                            },
                            onSendToReadLater = { clip ->
                                scope.launch {
                                    newsRepository.toggleReadLater(
                                        NewsArticle(
                                            title = clip.title,
                                            link = clip.sourceUrl,
                                            description = clip.contentText,
                                            publicationName = clip.domain
                                        )
                                    )
                                    showToast("Added to News Read Later")
                                }
                            },
                            onOpenUrl = ::navigateOmnibox,
                            onClose = { isWideSideStudioVisible = false },
                            modifier = Modifier.weight(0.36f).fillMaxHeight()
                        )
                    }
                }
            }

            // Bottom Liquid Glass Thumb Omnibox on Compact Smartphones (`Trapper`)
            if (!isWideFoldable) {
                PrismCompactBottomOmnibox(
                    isCollapsed = isBottomOmniboxCollapsed && currentUrl.isNotBlank(),
                    currentDomain = currentDomain,
                    omniboxInput = omniboxInput,
                    onOmniboxChange = { omniboxInput = it },
                    onSubmit = { navigateOmnibox(omniboxInput) },
                    canGoBack = canGoBack || isReaderMode,
                    isLoading = isLoading,
                    isShieldActive = isShieldActiveForDomain,
                    isBookmarked = clips.any { it.parsedType == PrismClipType.Link && it.sourceUrl == currentUrl },
                    clipsCount = clips.size,
                    hasLoadedUrl = currentUrl.isNotBlank(),
                    onExpand = { isBottomOmniboxCollapsed = false },
                    onBack = { if (isReaderMode) isReaderMode = false else webViewHolder.value?.goBack() },
                    onToggleShield = ::toggleShieldForDomain,
                    onBookmark = {
                        prismRepository.saveLinkClip(currentUrl, pageTitle, ogImageUrl)
                        showToast("Saved Link to Vault")
                    },
                    onReload = { if (isLoading) webViewHolder.value?.stopLoading() else webViewHolder.value?.reload() },
                    onOpenStudio = { showStudioSheet = true },
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .navigationBarsPadding()
                        .padding(horizontal = 14.dp, vertical = 10.dp)
                )
            }

            // Toast Pill
            AnimatedVisibility(
                visible = toastMessage != null,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = if (isWideFoldable) 24.dp else 78.dp)
            ) {
                Box(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(Color.Black.copy(alpha = 0.88f))
                        .border(1.dp, ThemeColors.accentCyan.copy(alpha = 0.45f), CircleShape)
                        .padding(horizontal = 14.dp, vertical = 8.dp)
                ) {
                    Text(toastMessage.orEmpty(), color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }

    // Compact Phone Bottom Sheet for Studio (`Co-Pilot` + `Vault`)
    if (showStudioSheet) {
        ModalBottomSheet(
            onDismissRequest = { showStudioSheet = false },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false),
            containerColor = Color(0xFF090F1E)
        ) {
            PrismStudioContent(
                activeTab = activeStudioPaneTab,
                onSelectTab = { activeStudioPaneTab = it },
                clips = clips,
                turns = turns,
                isGeneratingTurn = isGeneratingTurn,
                currentUrl = currentUrl,
                pageTitle = pageTitle,
                prismRepository = prismRepository,
                onRunCoPilotAction = { executeCoPilotAction(it) },
                onSubmitCustomQuestion = { q ->
                    isGeneratingTurn = true
                    scope.launch {
                        val (bodyText, selText) = extractDomContext()
                        val turn = prismRemoteService.askCoPilotQuestion(q, pageTitle, currentUrl, bodyText, selText, settings.geminiApiKey)
                        turns.add(0, turn)
                        isGeneratingTurn = false
                    }
                },
                onSendClipToTagdos = { clip ->
                    val tagFooter = (listOf("prism") + clip.tags).distinct().joinToString(" ") { "#$it" }
                    tagdosRepository.createQuickNote(
                        title = "💎 ${clip.title}",
                        content = "${if (clip.contentText.isNotBlank()) "> ${clip.contentText}\n\n" else ""}🔗 ${clip.sourceUrl}\n$tagFooter"
                    )
                    showToast("Mirrored to TagDoS (#prism)")
                },
                onSendTasksToTagdos = { tasksList ->
                    tagdosRepository.createQuickNote(
                        title = "🎯 Tasks: $pageTitle",
                        content = tasksList.joinToString("\n") { "- [ ] $it" } + "\n\n🔗 $currentUrl\n#prism #tasks"
                    )
                    showToast("Sent Tasks to TagDoS")
                },
                onSendToReadLater = { clip ->
                    scope.launch {
                        newsRepository.toggleReadLater(
                            NewsArticle(
                                title = clip.title,
                                link = clip.sourceUrl,
                                description = clip.contentText,
                                publicationName = clip.domain
                            )
                        )
                        showToast("Added to News Read Later")
                    }
                },
                onOpenUrl = {
                    showStudioSheet = false
                    navigateOmnibox(it)
                },
                onClose = { showStudioSheet = false },
                modifier = Modifier.fillMaxWidth().heightIn(min = 420.dp, max = 680.dp)
            )
        }
    }

    // OAuth Popup Dialog (`window.open` SSO flows)
    oauthPopupTransport?.let { msg ->
        Dialog(
            onDismissRequest = { oauthPopupTransport = null },
            properties = DialogProperties(usePlatformDefaultWidth = false)
        ) {
            Box(
                modifier = Modifier
                    .widthIn(max = 640.dp)
                    .fillMaxWidth(0.94f)
                    .fillMaxHeight(0.86f)
                    .clip(RoundedCornerShape(22.dp))
                    .background(Color(0xFF0D1324))
            ) {
                Column(modifier = Modifier.fillMaxSize()) {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(12.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("Sign In", color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Bold)
                        Text(
                            "Close",
                            color = ThemeColors.accentCyan,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier.clickable { oauthPopupTransport = null }
                        )
                    }
                    AndroidView(
                        factory = { ctx ->
                            WebView(ctx).apply {
                                this.settings.javaScriptEnabled = true
                                this.settings.domStorageEnabled = true
                                this.settings.userAgentString = MOBILE_CHROME_UA
                                CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
                                webViewClient = WebViewClient()
                                webChromeClient = object : WebChromeClient() {
                                    override fun onCloseWindow(window: WebView?) {
                                        oauthPopupTransport = null
                                    }
                                }
                                val transport = msg.obj as? WebView.WebViewTransport
                                transport?.webView = this
                                msg.sendToTarget()
                            }
                        },
                        modifier = Modifier.weight(1f).fillMaxWidth()
                    )
                }
            }
        }
    }

    if (showAddPinDialog) {
        var pinTitle by remember { mutableStateOf("") }
        var pinUrl by remember { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { showAddPinDialog = false },
            title = { Text("Pin to Speed Dial") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    OutlinedTextField(value = pinTitle, onValueChange = { pinTitle = it }, label = { Text("Title") })
                    OutlinedTextField(value = pinUrl, onValueChange = { pinUrl = it }, label = { Text("URL (e.g. github.com)") })
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    val resolved = PrismSearchEngine.resolveOmniboxInput(pinUrl)
                    if (resolved != null) prismRepository.togglePinSite(pinTitle, resolved)
                    showAddPinDialog = false
                }) { Text("Pin") }
            },
            dismissButton = {
                TextButton(onClick = { showAddPinDialog = false }) { Text("Cancel") }
            }
        )
    }
}

@Composable
private fun PrismTopBar(
    isWideFoldable: Boolean,
    tabs: List<com.intellidream.daily.model.PrismTabState>,
    activeTabId: String?,
    omniboxInput: String,
    onOmniboxChange: (String) -> Unit,
    onOmniboxSubmit: () -> Unit,
    currentUrl: String,
    canGoBack: Boolean,
    isLoading: Boolean,
    isShieldActive: Boolean,
    isReaderMode: Boolean,
    isRegionCropMode: Boolean,
    detectedRssUrl: String?,
    isFullResearchModeExternal: Boolean,
    canToggleFullResearchMode: Boolean,
    isWideStudioVisible: Boolean,
    clipsCount: Int,
    showMoreMenu: Boolean,
    onSetShowMoreMenu: (Boolean) -> Unit,
    currentSearchEngine: PrismSearchEngine,
    onSelectSearchEngine: (PrismSearchEngine) -> Unit,
    onNavigateBack: () -> Unit,
    onWebBack: () -> Unit,
    onReload: () -> Unit,
    onToggleShield: () -> Unit,
    onSelectTab: (String) -> Unit,
    onCloseTab: (String) -> Unit,
    onNewTab: (Boolean) -> Unit,
    onSaveBookmark: () -> Unit,
    onTogglePin: () -> Unit,
    onToggleReader: () -> Unit,
    onToggleCrop: () -> Unit,
    onOpenExternal: () -> Unit,
    onSubscribeRss: (String) -> Unit,
    onToggleFullResearchMode: () -> Unit,
    onToggleWideStudio: () -> Unit
) {
    Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .size(34.dp)
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.08f))
                    .border(1.dp, Color.White.copy(alpha = 0.12f), CircleShape)
                    .clickable(onClick = onNavigateBack),
                contentAlignment = Alignment.Center
            ) {
                Icon(Icons.Rounded.ChevronLeft, contentDescription = "Back", tint = Color.White, modifier = Modifier.size(20.dp))
            }

            if (isWideFoldable) {
                IconButton(onClick = onWebBack, enabled = canGoBack, modifier = Modifier.size(32.dp)) {
                    Icon(Icons.AutoMirrored.Rounded.ArrowBack, null, tint = if (canGoBack) Color.White else Color.White.copy(alpha = 0.3f), modifier = Modifier.size(18.dp))
                }
                IconButton(onClick = onReload, modifier = Modifier.size(32.dp)) {
                    Icon(if (isLoading) Icons.Rounded.Close else Icons.Rounded.Refresh, null, tint = Color.White, modifier = Modifier.size(18.dp))
                }

                // Wide Omnibox
                Row(
                    modifier = Modifier
                        .weight(1f)
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.08f))
                        .border(1.dp, Color.White.copy(alpha = 0.14f), CircleShape)
                        .padding(horizontal = 12.dp, vertical = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        Icons.Rounded.Shield,
                        contentDescription = "Prism Shield",
                        tint = if (isShieldActive) Color(0xFF10B981) else ThemeColors.textSecondary,
                        modifier = Modifier.size(16.dp).clickable(onClick = onToggleShield)
                    )
                    BasicTextField(
                        value = omniboxInput,
                        onValueChange = onOmniboxChange,
                        singleLine = true,
                        textStyle = TextStyle(color = Color.White, fontSize = 13.5.sp),
                        cursorBrush = SolidColor(ThemeColors.accentCyan),
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Go),
                        keyboardActions = KeyboardActions(onGo = { onOmniboxSubmit() }),
                        modifier = Modifier.weight(1f),
                        decorationBox = { inner ->
                            if (omniboxInput.isEmpty()) {
                                Text("Search with ${currentSearchEngine.displayName} or enter URL...", color = ThemeColors.textSecondary, fontSize = 13.sp)
                            }
                            inner()
                        }
                    )
                    if (!detectedRssUrl.isNullOrBlank()) {
                        PrismPillChip("+RSS", Color(0xFF10B981).copy(alpha = 0.2f), Color(0xFF10B981)) {
                            onSubscribeRss(detectedRssUrl)
                        }
                    }
                }

                if (currentUrl.isNotBlank()) {
                    IconButton(onClick = onSaveBookmark, modifier = Modifier.size(32.dp)) {
                        Icon(Icons.Rounded.Bookmark, null, tint = ThemeColors.accentCyan, modifier = Modifier.size(18.dp))
                    }
                    IconButton(onClick = onToggleReader, modifier = Modifier.size(32.dp)) {
                        Icon(Icons.Rounded.Article, null, tint = if (isReaderMode) ThemeColors.accentCyan else Color.White, modifier = Modifier.size(18.dp))
                    }
                    IconButton(onClick = onToggleCrop, modifier = Modifier.size(32.dp)) {
                        Icon(Icons.Rounded.Crop, null, tint = if (isRegionCropMode) Color(0xFF10B981) else Color.White, modifier = Modifier.size(18.dp))
                    }
                }

                IconButton(onClick = onToggleFullResearchMode, modifier = Modifier.size(32.dp)) {
                    Icon(Icons.Rounded.OpenInFull, "Research Split", tint = if (isFullResearchModeExternal) ThemeColors.accentCyan else Color.White, modifier = Modifier.size(17.dp))
                }

                Row(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(if (isWideStudioVisible) ThemeColors.accentCyan else Color.White.copy(alpha = 0.10f))
                        .clickable(onClick = onToggleWideStudio)
                        .padding(horizontal = 12.dp, vertical = 7.dp),
                    horizontalArrangement = Arrangement.spacedBy(5.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Rounded.AutoAwesome, null, tint = if (isWideStudioVisible) Color.Black else Color.White, modifier = Modifier.size(14.dp))
                    Text("Studio", color = if (isWideStudioVisible) Color.Black else Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                }
            } else {
                // Compact Phone Tab Strip + Overflow Menu
                Row(
                    modifier = Modifier.weight(1f).horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    tabs.forEach { tab ->
                        val active = (tab.id == activeTabId)
                        Row(
                            modifier = Modifier
                                .clip(CircleShape)
                                .background(if (active) ThemeColors.accentBlue.copy(alpha = 0.26f) else Color.White.copy(alpha = 0.06f))
                                .clickable { onSelectTab(tab.id) }
                                .padding(horizontal = 10.dp, vertical = 6.dp),
                            horizontalArrangement = Arrangement.spacedBy(5.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            if (tab.isPrivate) {
                                Icon(Icons.Rounded.VisibilityOff, null, tint = Color(0xFFA855F7), modifier = Modifier.size(12.dp))
                            }
                            Text(
                                text = tab.title.ifBlank { "Tab" },
                                color = if (active) Color.White else Color.White.copy(alpha = 0.7f),
                                fontSize = 11.5.sp,
                                fontWeight = if (active) FontWeight.SemiBold else FontWeight.Medium,
                                maxLines = 1,
                                modifier = Modifier.widthIn(max = 96.dp),
                                overflow = TextOverflow.Ellipsis
                            )
                            if (tabs.size > 1 && active) {
                                Icon(
                                    Icons.Rounded.Close,
                                    contentDescription = "Close Tab",
                                    tint = Color.White.copy(alpha = 0.6f),
                                    modifier = Modifier.size(12.dp).clickable { onCloseTab(tab.id) }
                                )
                            }
                        }
                    }
                }

                if (!detectedRssUrl.isNullOrBlank()) {
                    PrismPillChip("+RSS", Color(0xFF10B981).copy(alpha = 0.2f), Color(0xFF10B981)) {
                        onSubscribeRss(detectedRssUrl)
                    }
                }

                if (canToggleFullResearchMode) {
                    IconButton(onClick = onToggleFullResearchMode, modifier = Modifier.size(32.dp)) {
                        Icon(
                            Icons.Rounded.OpenInFull,
                            contentDescription = "Full Research Split",
                            tint = ThemeColors.accentCyan,
                            modifier = Modifier.size(17.dp)
                        )
                    }
                }
            }

            Box {
                IconButton(onClick = { onSetShowMoreMenu(true) }, modifier = Modifier.size(34.dp)) {
                    Icon(Icons.Rounded.MoreVert, "More", tint = Color.White)
                }
                DropdownMenu(expanded = showMoreMenu, onDismissRequest = { onSetShowMoreMenu(false) }) {
                    DropdownMenuItem(
                        text = { Text("New Tab") },
                        leadingIcon = { Icon(Icons.Rounded.Add, null) },
                        onClick = { onSetShowMoreMenu(false); onNewTab(false) }
                    )
                    DropdownMenuItem(
                        text = { Text("New Private Tab") },
                        leadingIcon = { Icon(Icons.Rounded.VisibilityOff, null) },
                        onClick = { onSetShowMoreMenu(false); onNewTab(true) }
                    )
                    if (currentUrl.isNotBlank()) {
                        DropdownMenuItem(
                            text = { Text(if (isReaderMode) "Exit Reader Mode" else "Reader Mode") },
                            leadingIcon = { Icon(Icons.Rounded.Article, null) },
                            onClick = { onSetShowMoreMenu(false); onToggleReader() }
                        )
                        DropdownMenuItem(
                            text = { Text("Capture Visual Region") },
                            leadingIcon = { Icon(Icons.Rounded.Crop, null) },
                            onClick = { onSetShowMoreMenu(false); onToggleCrop() }
                        )
                        DropdownMenuItem(
                            text = { Text("Pin / Unpin Speed Dial") },
                            leadingIcon = { Icon(Icons.Rounded.PushPin, null) },
                            onClick = { onSetShowMoreMenu(false); onTogglePin() }
                        )
                        DropdownMenuItem(
                            text = { Text("Open in System Browser") },
                            leadingIcon = { Icon(Icons.AutoMirrored.Rounded.OpenInNew, null) },
                            onClick = { onSetShowMoreMenu(false); onOpenExternal() }
                        )
                    }
                    PrismSearchEngine.entries.forEach { se ->
                        DropdownMenuItem(
                            text = { Text("Search: ${se.displayName}${if (se == currentSearchEngine) " ✓" else ""}") },
                            leadingIcon = { Icon(Icons.Rounded.Search, null) },
                            onClick = { onSetShowMoreMenu(false); onSelectSearchEngine(se) }
                        )
                    }
                }
            }
        }

        if (isWideFoldable) {
            Row(
                modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                tabs.forEach { tab ->
                    val active = (tab.id == activeTabId)
                    Row(
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(if (active) ThemeColors.accentBlue.copy(alpha = 0.24f) else Color.White.copy(alpha = 0.05f))
                            .clickable { onSelectTab(tab.id) }
                            .padding(horizontal = 10.dp, vertical = 5.dp),
                        horizontalArrangement = Arrangement.spacedBy(5.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            tab.title.ifBlank { "Tab" },
                            color = if (active) Color.White else Color.White.copy(alpha = 0.68f),
                            fontSize = 11.5.sp,
                            maxLines = 1,
                            modifier = Modifier.widthIn(max = 140.dp),
                            overflow = TextOverflow.Ellipsis
                        )
                        if (tabs.size > 1) {
                            Icon(
                                Icons.Rounded.Close,
                                null,
                                tint = Color.White.copy(alpha = 0.5f),
                                modifier = Modifier.size(12.dp).clickable { onCloseTab(tab.id) }
                            )
                        }
                    }
                }
                Box(
                    modifier = Modifier
                        .size(24.dp)
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.08f))
                        .clickable { onNewTab(false) },
                    contentAlignment = Alignment.Center
                ) {
                    Icon(Icons.Rounded.Add, null, tint = Color.White, modifier = Modifier.size(14.dp))
                }
            }
        }
    }
}

@Composable
private fun PrismCompactBottomOmnibox(
    isCollapsed: Boolean,
    currentDomain: String,
    omniboxInput: String,
    onOmniboxChange: (String) -> Unit,
    onSubmit: () -> Unit,
    canGoBack: Boolean,
    isLoading: Boolean,
    isShieldActive: Boolean,
    isBookmarked: Boolean,
    clipsCount: Int,
    hasLoadedUrl: Boolean,
    onExpand: () -> Unit,
    onBack: () -> Unit,
    onToggleShield: () -> Unit,
    onBookmark: () -> Unit,
    onReload: () -> Unit,
    onOpenStudio: () -> Unit,
    modifier: Modifier = Modifier
) {
    if (isCollapsed) {
        Row(
            modifier = modifier
                .clip(CircleShape)
                .background(Color(0xFF080E1C).copy(alpha = 0.90f))
                .border(1.dp, Color.White.copy(alpha = 0.16f), CircleShape)
                .clickable(onClick = onExpand)
                .padding(horizontal = 16.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(Icons.Rounded.Shield, null, tint = ThemeColors.accentCyan, modifier = Modifier.size(13.dp))
            Text(currentDomain, color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
        }
    } else {
        Row(
            modifier = modifier
                .fillMaxWidth()
                .clip(CircleShape)
                .background(Color(0xFF070D1B).copy(alpha = 0.95f))
                .border(1.dp, Color.White.copy(alpha = 0.16f), CircleShape)
                .padding(horizontal = 10.dp, vertical = 7.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                Icons.Rounded.ChevronLeft,
                contentDescription = "Back",
                tint = if (canGoBack) Color.White else Color.White.copy(alpha = 0.28f),
                modifier = Modifier.size(22.dp).clickable(enabled = canGoBack, onClick = onBack)
            )
            Icon(
                Icons.Rounded.Shield,
                contentDescription = "Shield",
                tint = if (isShieldActive) Color(0xFF10B981) else ThemeColors.textSecondary,
                modifier = Modifier.size(17.dp).clickable(onClick = onToggleShield)
            )
            BasicTextField(
                value = omniboxInput,
                onValueChange = onOmniboxChange,
                singleLine = true,
                textStyle = TextStyle(color = Color.White, fontSize = 13.5.sp),
                cursorBrush = SolidColor(ThemeColors.accentCyan),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Go),
                keyboardActions = KeyboardActions(onGo = { onSubmit() }),
                modifier = Modifier.weight(1f),
                decorationBox = { inner ->
                    if (omniboxInput.isEmpty()) {
                        Text("Search or enter URL...", color = ThemeColors.textSecondary, fontSize = 13.sp)
                    }
                    inner()
                }
            )
            if (hasLoadedUrl) {
                Icon(
                    if (isBookmarked) Icons.Rounded.Bookmark else Icons.Rounded.BookmarkBorder,
                    contentDescription = "Save Link",
                    tint = ThemeColors.accentCyan,
                    modifier = Modifier.size(19.dp).clickable(onClick = onBookmark)
                )
                Icon(
                    if (isLoading) Icons.Rounded.Close else Icons.Rounded.Refresh,
                    contentDescription = "Reload",
                    tint = Color.White.copy(alpha = 0.85f),
                    modifier = Modifier.size(18.dp).clickable(onClick = onReload)
                )
            }
            Row(
                modifier = Modifier
                    .clip(CircleShape)
                    .background(ThemeColors.accentCyan)
                    .clickable(onClick = onOpenStudio)
                    .padding(horizontal = 10.dp, vertical = 6.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(Icons.Rounded.AutoAwesome, null, tint = Color.Black, modifier = Modifier.size(14.dp))
                if (clipsCount > 0) {
                    Text("$clipsCount", color = Color.Black, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}

@Composable
private fun PrismStartPage(
    pinnedSites: List<com.intellidream.daily.model.PrismPinnedSite>,
    recentClips: List<PrismClip>,
    clipboardCandidate: String?,
    isWide: Boolean,
    onOpenUrl: (String) -> Unit,
    onSaveClipboard: (String) -> Unit,
    onDismissClipboard: () -> Unit,
    onAddPinClick: () -> Unit,
    onDeletePin: (String) -> Unit,
    onOpenAllClips: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 18.dp, vertical = 16.dp)
            .padding(bottom = if (isWide) 24.dp else 86.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp)
    ) {
        if (!clipboardCandidate.isNullOrBlank()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(16.dp))
                    .background(ThemeColors.accentCyan.copy(alpha = 0.10f))
                    .border(1.dp, ThemeColors.accentCyan.copy(alpha = 0.30f), RoundedCornerShape(16.dp))
                    .padding(14.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(Icons.Rounded.ContentPaste, null, tint = ThemeColors.accentCyan, modifier = Modifier.size(18.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text("Copied Link Detected", color = Color.White, fontSize = 12.5.sp, fontWeight = FontWeight.Bold)
                    Text(clipboardCandidate, color = ThemeColors.textSecondary, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                PrismPillChip("Open", ThemeColors.accentCyan, Color.Black) { onOpenUrl(clipboardCandidate) }
                PrismPillChip("Clip", Color.White.copy(alpha = 0.12f), Color.White) { onSaveClipboard(clipboardCandidate) }
                Icon(Icons.Rounded.Close, null, tint = ThemeColors.textSecondary, modifier = Modifier.size(16.dp).clickable(onClick = onDismissClipboard))
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("Pinned Speed Dial", color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.Bold)
            Text("+ Add", color = ThemeColors.accentCyan, fontSize = 12.5.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.clickable(onClick = onAddPinClick))
        }

        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            pinnedSites.chunked(2).forEach { pair ->
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    pair.forEach { site ->
                        Row(
                            modifier = Modifier
                                .weight(1f)
                                .clip(RoundedCornerShape(14.dp))
                                .background(Color.White.copy(alpha = 0.06f))
                                .border(1.dp, Color.White.copy(alpha = 0.10f), RoundedCornerShape(14.dp))
                                .clickable { onOpenUrl(site.url) }
                                .padding(12.dp),
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(Icons.Rounded.Language, null, tint = ThemeColors.accentCyan, modifier = Modifier.size(18.dp))
                            Column(modifier = Modifier.weight(1f)) {
                                Text(site.title, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Text(site.domain, color = ThemeColors.textSecondary, fontSize = 10.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                            Icon(
                                Icons.Rounded.Close,
                                null,
                                tint = Color.White.copy(alpha = 0.35f),
                                modifier = Modifier.size(13.dp).clickable { onDeletePin(site.id) }
                            )
                        }
                    }
                    if (pair.size == 1) Spacer(modifier = Modifier.weight(1f))
                }
            }
        }

        if (recentClips.isNotEmpty()) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("Recent Vault Clippings", color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                Text("All Clips →", color = ThemeColors.accentCyan, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.clickable(onClick = onOpenAllClips))
            }

            recentClips.forEach { clip ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(14.dp))
                        .background(Color.White.copy(alpha = 0.05f))
                        .clickable { onOpenUrl(clip.sourceUrl) }
                        .padding(12.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Rounded.Bookmark, null, tint = Color(clip.parsedType.accentHex), modifier = Modifier.size(18.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(clip.title, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(clip.contentText.ifBlank { clip.domain }, color = ThemeColors.textSecondary, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
    }
}

@Composable
private fun PrismReaderCanvas(isExtracting: Boolean, article: NewsArticle?) {
    if (isExtracting) {
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                CircularProgressIndicator(color = ThemeColors.accentCyan)
                Text("Extracting Distraction-Free View...", color = ThemeColors.textSecondary, fontSize = 13.sp)
            }
        }
    } else if (article != null) {
        val html = """
            <!DOCTYPE html><html><head><meta name='viewport' content='width=device-width,initial-scale=1'/>
            <style>body{background:#120E1C;color:#ECECEC;font-family:sans-serif;line-height:1.68;padding:18px;max-width:740px;margin:auto}
            img{max-width:100%;height:auto;border-radius:12px}a{color:#00E5FF}</style></head>
            <body><h1>${article.title}</h1>${article.content ?: article.description.orEmpty()}</body></html>
        """.trimIndent()
        AndroidView(
            factory = { ctx ->
                WebView(ctx).apply {
                    setBackgroundColor(0x00000000)
                    loadDataWithBaseURL(article.link, html, "text/html", "UTF-8", null)
                }
            },
            modifier = Modifier.fillMaxSize()
        )
    }
}

@Composable
private fun PrismStudioContent(
    activeTab: Int,
    onSelectTab: (Int) -> Unit,
    clips: List<PrismClip>,
    turns: List<PrismCoPilotTurn>,
    isGeneratingTurn: Boolean,
    currentUrl: String,
    pageTitle: String,
    prismRepository: PrismRepository,
    onRunCoPilotAction: (PrismCoPilotAction) -> Unit,
    onSubmitCustomQuestion: (String) -> Unit,
    onSendClipToTagdos: (PrismClip) -> Unit,
    onSendTasksToTagdos: (List<String>) -> Unit,
    onSendToReadLater: (PrismClip) -> Unit,
    onOpenUrl: (String) -> Unit,
    onClose: () -> Unit,
    modifier: Modifier = Modifier
) {
    var searchQuery by remember { mutableStateOf("") }
    var selectedType by remember { mutableStateOf<PrismClipType?>(null) }
    var customQuestion by remember { mutableStateOf("") }

    Column(modifier = modifier.background(Color(0xFF090F1E))) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                modifier = Modifier.clip(CircleShape).background(Color.White.copy(alpha = 0.06f)).padding(4.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                PrismPillChip("✨ Co-Pilot", if (activeTab == 0) ThemeColors.accentBlue else Color.Transparent, Color.White) { onSelectTab(0) }
                PrismPillChip("Vault (${clips.size})", if (activeTab == 1) ThemeColors.accentBlue else Color.Transparent, Color.White) { onSelectTab(1) }
            }
            Icon(Icons.Rounded.Close, "Close", tint = Color.White.copy(alpha = 0.7f), modifier = Modifier.size(20.dp).clickable(onClick = onClose))
        }

        HorizontalDivider(color = Color.White.copy(alpha = 0.08f))

        if (activeTab == 0) {
            Row(
                modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 14.dp, vertical = 10.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                PrismCoPilotAction.entries.forEach { action ->
                    PrismPillChip(action.title, Color(action.accentHex).copy(alpha = 0.16f), Color.White) {
                        if (currentUrl.isNotBlank() && !isGeneratingTurn) onRunCoPilotAction(action)
                    }
                }
            }

            LazyColumn(
                modifier = Modifier.weight(1f).fillMaxWidth(),
                contentPadding = PaddingValues(14.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                if (isGeneratingTurn) {
                    item {
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                            CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp, color = ThemeColors.accentCyan)
                            Text("Synthesizing page insights...", color = ThemeColors.textSecondary, fontSize = 12.5.sp)
                        }
                    }
                }
                if (turns.isEmpty() && !isGeneratingTurn) {
                    item {
                        Text(
                            text = if (currentUrl.isBlank()) "Open any web page to generate summaries, extract tasks to TagDoS, or ask questions."
                            else "Tap a quick chip above or ask anything about \"$pageTitle\".",
                            color = ThemeColors.textSecondary,
                            fontSize = 12.5.sp
                        )
                    }
                }
                items(turns, key = { it.id }) { turn ->
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(14.dp))
                            .background(Color.White.copy(alpha = 0.06f))
                            .padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Text(turn.prompt, color = ThemeColors.accentCyan, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                        Text(turn.responseMarkdown, color = Color.White, fontSize = 12.5.sp)
                        turn.keyBullets.forEach { b ->
                            Text("• $b", color = Color.White.copy(alpha = 0.86f), fontSize = 12.sp)
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            PrismPillChip("Save to Vault", ThemeColors.accentCyan.copy(alpha = 0.16f), ThemeColors.accentCyan) {
                                prismRepository.saveAiSummaryClip(turn)
                            }
                            if (turn.extractedTasks.isNotEmpty()) {
                                PrismPillChip("→ TagDoS", Color(0xFFFFB300).copy(alpha = 0.16f), Color(0xFFFFB300)) {
                                    onSendTasksToTagdos(turn.extractedTasks)
                                }
                            }
                        }
                    }
                }
            }

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(12.dp)
                    .clip(RoundedCornerShape(14.dp))
                    .background(Color.White.copy(alpha = 0.08f))
                    .padding(horizontal = 12.dp, vertical = 9.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                BasicTextField(
                    value = customQuestion,
                    onValueChange = { customQuestion = it },
                    singleLine = true,
                    textStyle = TextStyle(color = Color.White, fontSize = 13.sp),
                    cursorBrush = SolidColor(ThemeColors.accentCyan),
                    modifier = Modifier.weight(1f),
                    decorationBox = { inner ->
                        if (customQuestion.isEmpty()) Text("Ask about this page...", color = ThemeColors.textSecondary, fontSize = 13.sp)
                        inner()
                    }
                )
                Icon(
                    Icons.Rounded.Send,
                    contentDescription = "Send",
                    tint = if (customQuestion.isNotBlank() && currentUrl.isNotBlank()) ThemeColors.accentCyan else Color.White.copy(alpha = 0.25f),
                    modifier = Modifier.size(20.dp).clickable(enabled = customQuestion.isNotBlank() && currentUrl.isNotBlank()) {
                        val q = customQuestion
                        customQuestion = ""
                        onSubmitCustomQuestion(q)
                    }
                )
            }
        } else {
            val filtered = clips.filter { c ->
                (selectedType == null || c.parsedType == selectedType) &&
                    (searchQuery.isBlank() || "${c.title} ${c.domain} ${c.contentText} ${c.userNote}".contains(searchQuery, ignoreCase = true))
            }

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 14.dp, vertical = 8.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .background(Color.White.copy(alpha = 0.07f))
                    .padding(horizontal = 10.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(Icons.Rounded.Search, null, tint = ThemeColors.textSecondary, modifier = Modifier.size(15.dp))
                BasicTextField(
                    value = searchQuery,
                    onValueChange = { searchQuery = it },
                    singleLine = true,
                    textStyle = TextStyle(color = Color.White, fontSize = 13.sp),
                    cursorBrush = SolidColor(ThemeColors.accentCyan),
                    modifier = Modifier.weight(1f),
                    decorationBox = { inner ->
                        if (searchQuery.isEmpty()) Text("Search clips...", color = ThemeColors.textSecondary, fontSize = 12.5.sp)
                        inner()
                    }
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 14.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                PrismPillChip("All", if (selectedType == null) ThemeColors.accentCyan.copy(alpha = 0.24f) else Color.White.copy(alpha = 0.06f), Color.White) {
                    selectedType = null
                }
                PrismClipType.entries.forEach { t ->
                    PrismPillChip(t.displayName, if (selectedType == t) Color(t.accentHex).copy(alpha = 0.28f) else Color.White.copy(alpha = 0.06f), Color.White) {
                        selectedType = if (selectedType == t) null else t
                    }
                }
            }

            LazyColumn(
                modifier = Modifier.weight(1f).fillMaxWidth(),
                contentPadding = PaddingValues(14.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                items(filtered, key = { it.id }) { clip ->
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(14.dp))
                            .background(Color.White.copy(alpha = 0.06f))
                            .padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                            Text(clip.domain.ifBlank { clip.parsedType.displayName }, color = Color(clip.parsedType.accentHex), fontSize = 11.sp, fontWeight = FontWeight.Bold)
                            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                Icon(
                                    if (clip.isFavorite) Icons.Rounded.Star else Icons.Rounded.StarBorder,
                                    null,
                                    tint = if (clip.isFavorite) Color(0xFFFFD166) else Color.White.copy(alpha = 0.45f),
                                    modifier = Modifier.size(16.dp).clickable { prismRepository.toggleFavoriteClip(clip.id) }
                                )
                                Icon(
                                    Icons.Rounded.DeleteOutline,
                                    null,
                                    tint = Color.White.copy(alpha = 0.45f),
                                    modifier = Modifier.size(16.dp).clickable { prismRepository.deleteClip(clip) }
                                )
                            }
                        }

                        Text(
                            clip.title,
                            color = Color.White,
                            fontSize = 13.5.sp,
                            fontWeight = FontWeight.Bold,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.clickable { onOpenUrl(clip.sourceUrl) }
                        )

                        if (clip.parsedType == PrismClipType.Image) {
                            PrismClipThumbnailAndroid(clip = clip, repository = prismRepository)
                        }

                        if (clip.contentText.isNotBlank()) {
                            Text(clip.contentText, color = Color.White.copy(alpha = 0.86f), fontSize = 12.sp, maxLines = 5, overflow = TextOverflow.Ellipsis)
                        }

                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            PrismPillChip("→ TagDoS", Color(0xFFFFB300).copy(alpha = 0.15f), Color(0xFFFFB300)) {
                                onSendClipToTagdos(clip)
                            }
                            PrismPillChip("Read Later", ThemeColors.accentCyan.copy(alpha = 0.15f), ThemeColors.accentCyan) {
                                onSendToReadLater(clip)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun PrismClipThumbnailAndroid(clip: PrismClip, repository: PrismRepository) {
    var bmp by remember(clip.id) { mutableStateOf<Bitmap?>(null) }
    LaunchedEffect(clip.id) {
        val file = repository.loadOrDownloadClipImage(clip)
        if (file != null && file.exists()) {
            bmp = BitmapFactory.decodeFile(file.absolutePath)
        }
    }
    bmp?.let {
        Image(
            bitmap = it.asImageBitmap(),
            contentDescription = clip.title,
            modifier = Modifier.fillMaxWidth().heightIn(max = 170.dp).clip(RoundedCornerShape(10.dp))
        )
    }
}

@Composable
private fun PrismPillChip(label: String, bg: Color, fg: Color, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .clip(CircleShape)
            .background(bg)
            .clickable(onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 5.dp)
    ) {
        Text(label, color = fg, fontSize = 11.sp, fontWeight = FontWeight.Bold, maxLines = 1)
    }
}
