package com.intellidream.daily.presentation

import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.net.Uri
import android.os.Message
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.intellidream.daily.designsystem.ThemeColors

/**
 * Modern authentication sheet for Substack supporting both browser-based OAuth/redirect login
 * and direct publication/handle configuration.
 */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun SubstackLoginSheet(
    initialUsername: String? = null,
    clearExistingSession: Boolean = false,
    onDismiss: () -> Unit,
    onConnect: (String) -> Unit
) {
    val focusManager = LocalFocusManager.current
    var manualUsername by remember { mutableStateOf(initialUsername ?: "") }
    var isLoadingWeb by remember { mutableStateOf(true) }
    var detectedCompleted by remember { mutableStateOf(false) }

    val configuration = LocalConfiguration.current
    val isFoldable = configuration.screenWidthDp >= 600

    BackHandler {
        onDismiss()
    }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(
            usePlatformDefaultWidth = false,
            decorFitsSystemWindows = false
        )
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = 0.7f))
                .statusBarsPadding()
                .navigationBarsPadding()
                .imePadding(),
            contentAlignment = Alignment.Center
        ) {
            Column(
                modifier = Modifier
                    .then(
                        if (isFoldable) {
                            Modifier
                                .widthIn(max = 680.dp)
                                .fillMaxHeight(0.92f)
                        } else {
                            Modifier.fillMaxSize()
                        }
                    )
                    .clip(RoundedCornerShape(if (isFoldable) 24.dp else 16.dp))
                    .background(Color(0xFF0F141C))
                    .border(
                        width = 1.dp,
                        color = Color.White.copy(alpha = 0.15f),
                        shape = RoundedCornerShape(if (isFoldable) 24.dp else 16.dp)
                    )
            ) {
                // Header Bar
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Box(
                            modifier = Modifier
                                .size(28.dp)
                                .clip(CircleShape)
                                .background(ThemeColors.accentCyan.copy(alpha = 0.15f)),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                text = "S",
                                color = ThemeColors.accentCyan,
                                fontWeight = FontWeight.Black,
                                fontSize = 14.sp
                            )
                        }
                        Text(
                            text = "Connect Substack",
                            color = Color.White,
                            fontSize = 17.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }

                    IconButton(
                        onClick = onDismiss,
                        modifier = Modifier.size(36.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.Close,
                            contentDescription = "Close",
                            tint = Color.White.copy(alpha = 0.7f)
                        )
                    }
                }

                HorizontalDivider(color = Color.White.copy(alpha = 0.12f))

                // Direct Handle / Publication Slug Input Bar
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 10.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(Color.White.copy(alpha = 0.08f))
                            .border(1.dp, Color.White.copy(alpha = 0.12f), RoundedCornerShape(12.dp))
                            .padding(horizontal = 12.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        Text(
                            text = "@",
                            color = ThemeColors.accentCyan,
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Bold
                        )

                        BasicTextField(
                            value = manualUsername,
                            onValueChange = { manualUsername = it },
                            singleLine = true,
                            textStyle = TextStyle(
                                color = Color.White,
                                fontSize = 14.sp
                            ),
                            cursorBrush = SolidColor(ThemeColors.accentCyan),
                            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                            keyboardActions = KeyboardActions(onDone = {
                                val clean = manualUsername.trim().removePrefix("@")
                                if (clean.isNotEmpty()) {
                                    onConnect(clean)
                                    onDismiss()
                                }
                            }),
                            modifier = Modifier.weight(1f),
                            decorationBox = { innerTextField ->
                                if (manualUsername.isEmpty()) {
                                    Text(
                                        text = "Enter Substack handle or publication (e.g. pragmatic)",
                                        color = ThemeColors.textMuted,
                                        fontSize = 13.sp
                                    )
                                }
                                innerTextField()
                            }
                        )

                        val canConnect = manualUsername.trim().removePrefix("@").isNotEmpty()
                        Box(
                            modifier = Modifier
                                .clip(CircleShape)
                                .background(if (canConnect) ThemeColors.accentCyan else Color.White.copy(alpha = 0.15f))
                                .clickable(enabled = canConnect) {
                                    val clean = manualUsername.trim().removePrefix("@")
                                    if (clean.isNotEmpty()) {
                                        onConnect(clean)
                                        onDismiss()
                                    }
                                }
                                .padding(horizontal = 14.dp, vertical = 6.dp)
                        ) {
                            Text(
                                text = "Connect",
                                color = if (canConnect) Color.Black else ThemeColors.textMuted,
                                fontSize = 12.sp,
                                fontWeight = FontWeight.Bold
                            )
                        }
                    }

                    Text(
                        text = "Or sign in below to unlock your Substack Inbox and paid newsletters",
                        color = ThemeColors.fgMutedDark,
                        fontSize = 11.sp
                    )
                }

                HorizontalDivider(color = Color.White.copy(alpha = 0.12f))

                // WebKit Browser View with Third-Party OAuth & Magic Link Support
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f)
                        .background(Color(0xFF0F141C))
                ) {
                    AndroidView(
                        factory = { ctx ->
                            WebView(ctx).apply {
                                layoutParams = ViewGroup.LayoutParams(
                                    ViewGroup.LayoutParams.MATCH_PARENT,
                                    ViewGroup.LayoutParams.MATCH_PARENT
                                )
                                setBackgroundColor(0xFF0F141C.toInt())

                                settings.apply {
                                    javaScriptEnabled = true
                                    domStorageEnabled = true
                                    javaScriptCanOpenWindowsAutomatically = true
                                    setSupportMultipleWindows(true)
                                    userAgentString = "Mozilla/5.0 (Linux; Android 15; Pixel 9 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36"
                                }

                                val cookieManager = CookieManager.getInstance()
                                cookieManager.setAcceptCookie(true)
                                cookieManager.setAcceptThirdPartyCookies(this, true)

                                if (clearExistingSession) {
                                    val substackCookies = cookieManager.getCookie("https://substack.com")
                                    if (!substackCookies.isNullOrBlank()) {
                                        substackCookies.split(";").forEach { c ->
                                            val name = c.substringBefore("=").trim()
                                            cookieManager.setCookie("https://substack.com", "$name=; Max-Age=0")
                                        }
                                        cookieManager.flush()
                                    }
                                }

                                fun verifySession(loadedUrl: String?, webView: WebView?) {
                                    if (loadedUrl.isNullOrBlank() || detectedCompleted || webView == null) return
                                    val uri = try { Uri.parse(loadedUrl) } catch (_: Exception) { return }
                                    val host = uri.host?.lowercase() ?: return
                                    if (!host.contains("substack.com")) return

                                    val path = uri.path ?: ""
                                    if (path.startsWith("/sign-in") || path.startsWith("/login") || path.startsWith("/account/login")) {
                                        return
                                    }

                                    val preloadJs = """
                                        (function() {
                                            try {
                                                if (window._preloads && window._preloads.user) {
                                                    var u = window._preloads.user;
                                                    return JSON.stringify({
                                                        id: u.id,
                                                        handle: u.handle || u.username,
                                                        name: u.name,
                                                        email: u.email
                                                    });
                                                }
                                                var profileLink = document.querySelector('a[href*="substack.com/@"], a[href^="/@"]');
                                                if (profileLink) {
                                                    var href = profileLink.getAttribute('href') || '';
                                                    var idx = href.indexOf('/@');
                                                    if (idx >= 0) {
                                                        var h = href.substring(idx + 2).split('/')[0].split('?')[0];
                                                        if (h) return JSON.stringify({ handle: h });
                                                    }
                                                }
                                            } catch (e) {}
                                            return null;
                                        })()
                                    """.trimIndent()

                                    webView.evaluateJavascript(preloadJs) { resultStr ->
                                        if (detectedCompleted) return@evaluateJavascript
                                        var detectedHandle: String? = null
                                        if (!resultStr.isNullOrBlank() && resultStr != "null") {
                                            try {
                                                val cleanJson = if (resultStr.startsWith("\"") && resultStr.endsWith("\"")) {
                                                    org.json.JSONTokener(resultStr).nextValue().toString()
                                                } else resultStr
                                                val obj = org.json.JSONObject(cleanJson)
                                                detectedHandle = obj.optString("handle").ifEmpty { obj.optString("name") }
                                            } catch (_: Throwable) {}
                                        }

                                        val cookies = cookieManager.getCookie("https://substack.com") ?: ""
                                        val hasAuthCookies = com.intellidream.daily.model.ArticleExtractor.hasAuthenticatedSubstackCookies(cookies)

                                        if (detectedHandle.isNullOrEmpty() && path.startsWith("/@")) {
                                            val parts = path.removePrefix("/@").split("/")
                                            detectedHandle = parts.firstOrNull()?.trim()
                                        }

                                        if (hasAuthCookies || !detectedHandle.isNullOrEmpty()) {
                                            val resolvedHandle = detectedHandle?.takeIf { it.isNotBlank() }
                                                ?: manualUsername.trim().removePrefix("@").ifEmpty { "substack" }
                                            detectedCompleted = true
                                            cookieManager.flush()
                                            onConnect(resolvedHandle)
                                            onDismiss()
                                        }
                                    }
                                }

                                webChromeClient = object : WebChromeClient() {
                                    override fun onProgressChanged(view: WebView?, newProgress: Int) {
                                        isLoadingWeb = newProgress < 90
                                    }

                                    override fun onCreateWindow(
                                        view: WebView?,
                                        isDialog: Boolean,
                                        isUserGesture: Boolean,
                                        resultMsg: Message?
                                    ): Boolean {
                                        val transport = resultMsg?.obj as? WebView.WebViewTransport
                                        transport?.webView = view
                                        resultMsg?.sendToTarget()
                                        return true
                                    }
                                }

                                webViewClient = object : WebViewClient() {
                                    override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                                        return false
                                    }

                                    override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                                        super.onPageStarted(view, url, favicon)
                                        verifySession(url, view)
                                    }

                                    override fun onPageFinished(view: WebView?, url: String?) {
                                        super.onPageFinished(view, url)
                                        isLoadingWeb = false
                                        verifySession(url, view)
                                    }
                                }

                                loadUrl("https://substack.com/sign-in")
                            }
                        },
                        modifier = Modifier.fillMaxSize()
                    )

                    if (isLoadingWeb) {
                        Box(
                            modifier = Modifier
                                .fillMaxSize()
                                .background(Color(0xFF0F141C)),
                            contentAlignment = Alignment.Center
                        ) {
                            Column(
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.spacedBy(12.dp)
                            ) {
                                CircularProgressIndicator(
                                    color = ThemeColors.accentCyan,
                                    strokeWidth = 3.dp,
                                    modifier = Modifier.size(36.dp)
                                )
                                Text(
                                    text = "Loading Substack...",
                                    color = ThemeColors.fgMutedDark,
                                    fontSize = 12.sp
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
