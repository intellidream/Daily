package com.intellidream.daily.presentation

import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.os.Message
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Key
import androidx.compose.material.icons.rounded.Security
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.network.SupabaseAdminCrypto
import com.intellidream.daily.network.SupabaseAdminRepository
import com.intellidream.daily.network.SupabaseCliLoginHandshake
import kotlinx.coroutines.launch

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun SupabaseAdminLoginSheet(
    onDismiss: () -> Unit,
    onAuthenticated: () -> Unit
) {
    val context = LocalContext.current
    val repo = remember {
        SupabaseAdminRepository.shared.also { it.initializeIfNeeded(context) }
    }
    val scope = rememberCoroutineScope()
    val isAuthenticating by repo.isAuthenticating.collectAsState()
    val repoError by repo.errorMessage.collectAsState()

    val handshake = remember { SupabaseCliLoginHandshake("Android") }
    var showPatBar by remember { mutableStateOf(false) }
    var patInput by remember { mutableStateOf("") }
    var isLoadingWeb by remember { mutableStateOf(true) }
    var localError by remember { mutableStateOf<String?>(null) }

    val configuration = LocalConfiguration.current
    val isFoldable = configuration.screenWidthDp >= 600

    BackHandler { onDismiss() }

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
                .background(Color.Black.copy(alpha = 0.78f))
                .statusBarsPadding(),
            contentAlignment = Alignment.Center
        ) {
            Column(
                modifier = Modifier
                    .then(
                        if (isFoldable) {
                            Modifier
                                .widthIn(max = 760.dp)
                                .fillMaxHeight(0.92f)
                                .padding(16.dp)
                                .clip(RoundedCornerShape(24.dp))
                                .border(1.dp, Color.White.copy(alpha = 0.14f), RoundedCornerShape(24.dp))
                        } else {
                            Modifier.fillMaxSize()
                        }
                    )
                    .background(ThemeColors.bgStop1)
            ) {
                // Header Bar
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Color.Black.copy(alpha = 0.35f))
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Security,
                        contentDescription = null,
                        tint = ThemeColors.accentCyan,
                        modifier = Modifier.size(20.dp)
                    )
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = "Supabase Admin Sign In",
                            color = Color.White,
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Bold
                        )
                        Text(
                            text = "GitHub OAuth · P-256 ECDH · 100% Read-Only",
                            color = ThemeColors.fgMutedDark,
                            fontSize = 11.sp
                        )
                    }

                    Row(
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(ThemeColors.accentCyan.copy(alpha = 0.14f))
                            .border(1.dp, ThemeColors.accentCyan.copy(alpha = 0.35f), CircleShape)
                            .clickable { showPatBar = !showPatBar }
                            .padding(horizontal = 10.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.Key,
                            contentDescription = null,
                            tint = ThemeColors.accentCyan,
                            modifier = Modifier.size(13.dp)
                        )
                        Text(
                            text = if (showPatBar) "Hide PAT" else "PAT (sbp_...)",
                            color = ThemeColors.accentCyan,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                    }

                    IconButton(onClick = onDismiss, modifier = Modifier.size(32.dp)) {
                        Icon(
                            imageVector = Icons.Rounded.Close,
                            contentDescription = "Close",
                            tint = Color.White
                        )
                    }
                }

                AnimatedVisibility(visible = showPatBar) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(Color.White.copy(alpha = 0.06f))
                            .padding(horizontal = 16.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .clip(RoundedCornerShape(10.dp))
                                .background(Color.Black.copy(alpha = 0.35f))
                                .border(1.dp, Color.White.copy(alpha = 0.14f), RoundedCornerShape(10.dp))
                                .padding(horizontal = 12.dp, vertical = 10.dp)
                        ) {
                            if (patInput.isEmpty()) {
                                Text(
                                    text = "Paste Personal Access Token (sbp_...)",
                                    color = ThemeColors.textMuted,
                                    fontSize = 12.sp
                                )
                            }
                            BasicTextField(
                                value = patInput,
                                onValueChange = { patInput = it },
                                singleLine = true,
                                visualTransformation = PasswordVisualTransformation(),
                                textStyle = TextStyle(
                                    color = Color.White,
                                    fontSize = 12.sp,
                                    fontFamily = FontFamily.Monospace
                                ),
                                cursorBrush = SolidColor(ThemeColors.accentCyan),
                                modifier = Modifier.fillMaxWidth()
                            )
                        }

                        Box(
                            modifier = Modifier
                                .clip(CircleShape)
                                .background(ThemeColors.accentCyan)
                                .clickable(enabled = patInput.isNotBlank() && !isAuthenticating) {
                                    localError = null
                                    scope.launch {
                                        runCatching { repo.connectWithPersonalAccessToken(patInput) }
                                            .onSuccess { onAuthenticated() }
                                            .onFailure { localError = it.message }
                                    }
                                }
                                .padding(horizontal = 14.dp, vertical = 9.dp)
                        ) {
                            Text(
                                text = "Connect",
                                color = Color.Black,
                                fontSize = 12.sp,
                                fontWeight = FontWeight.Bold
                            )
                        }
                    }
                }

                val errText = localError ?: repoError
                if (!errText.isNullOrBlank()) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(ThemeColors.error.copy(alpha = 0.18f))
                            .padding(horizontal = 16.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = errText,
                            color = Color.White,
                            fontSize = 12.sp,
                            modifier = Modifier.weight(1f)
                        )
                        Text(
                            text = "Dismiss",
                            color = ThemeColors.accentCyan,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier.clickable {
                                localError = null
                                repo.clearError()
                            }
                        )
                    }
                }

                HorizontalDivider(color = Color.White.copy(alpha = 0.12f))

                // Embedded WebView
                Box(modifier = Modifier.fillMaxSize()) {
                    AndroidView(
                        modifier = Modifier.fillMaxSize(),
                        factory = { ctx ->
                            var delivered = false
                            var recoveredRedirect = false

                            WebView(ctx).apply {
                                val mainWebView = this
                                layoutParams = ViewGroup.LayoutParams(
                                    ViewGroup.LayoutParams.MATCH_PARENT,
                                    ViewGroup.LayoutParams.MATCH_PARENT
                                )
                                settings.javaScriptEnabled = true
                                settings.domStorageEnabled = true
                                settings.javaScriptCanOpenWindowsAutomatically = true
                                settings.setSupportMultipleWindows(true)
                                settings.userAgentString = settings.userAgentString
                                    .replace("; wv", "")

                                CookieManager.getInstance().setAcceptCookie(true)
                                CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)

                                addJavascriptInterface(
                                    object {
                                        @JavascriptInterface
                                        fun onCliHandshake(deviceCode: String, dashJson: String?) {
                                            if (delivered || deviceCode.isBlank()) return
                                            delivered = true
                                            scope.launch {
                                                runCatching {
                                                    repo.completeCliHandshake(handshake, deviceCode, dashJson)
                                                }.onSuccess {
                                                    onAuthenticated()
                                                }.onFailure {
                                                    localError = it.message
                                                }
                                            }
                                        }
                                    },
                                    "DayOneSupabaseBridge"
                                )

                                webChromeClient = object : WebChromeClient() {
                                    override fun onCreateWindow(
                                        view: WebView?,
                                        isDialog: Boolean,
                                        isUserGesture: Boolean,
                                        resultMsg: Message?
                                    ): Boolean {
                                        val transport = resultMsg?.obj as? WebView.WebViewTransport ?: return false
                                        val tempWebView = WebView(ctx).apply {
                                            webViewClient = object : WebViewClient() {
                                                override fun shouldOverrideUrlLoading(
                                                    v: WebView?,
                                                    req: WebResourceRequest?
                                                ): Boolean {
                                                    req?.url?.toString()?.let { mainWebView.loadUrl(it) }
                                                    return true
                                                }
                                            }
                                        }
                                        transport.webView = tempWebView
                                        resultMsg.sendToTarget()
                                        return true
                                    }
                                }

                                webViewClient = object : WebViewClient() {
                                    override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                                        isLoadingWeb = true
                                    }

                                    override fun onPageCommitVisible(view: WebView?, url: String?) {
                                        isLoadingWeb = false
                                    }

                                    override fun onPageFinished(view: WebView?, url: String?) {
                                        isLoadingWeb = false
                                        val current = url ?: return

                                        if (!delivered) {
                                            SupabaseAdminCrypto.extractDeviceCode(current)?.let { code ->
                                                delivered = true
                                                view?.evaluateJavascript("window.localStorage.getItem('supabase.dashboard.auth.token')") { raw ->
                                                    val unquoted = raw?.trim()?.removeSurrounding("\"")
                                                        ?.replace("\\\"", "\"")
                                                        ?.replace("\\\\", "\\")
                                                    scope.launch {
                                                        runCatching {
                                                            repo.completeCliHandshake(handshake, code, unquoted)
                                                        }.onSuccess { onAuthenticated() }
                                                            .onFailure { localError = it.message }
                                                    }
                                                }
                                                return
                                            }

                                            if (!recoveredRedirect && SupabaseAdminCrypto.shouldRecoverCliLoginRedirect(current)) {
                                                recoveredRedirect = true
                                                view?.loadUrl(handshake.loginUrl)
                                                return
                                            }
                                        }

                                        // Inject SPA History pushState listener for Next.js router.push(?device_code=...)
                                        view?.evaluateJavascript(
                                            """
                                            (function() {
                                              if (window.__dayOneCliHooked) return;
                                              window.__dayOneCliHooked = true;
                                              var sent = null;
                                              function check() {
                                                try {
                                                  if ((location.hostname || '').toLowerCase().indexOf('supabase.com') === -1) return;
                                                  var p = new URLSearchParams(location.search || '');
                                                  var c = p.get('device_code');
                                                  if (c && c !== sent) {
                                                    sent = c;
                                                    var d = '';
                                                    try { d = localStorage.getItem('supabase.dashboard.auth.token') || ''; } catch (e) {}
                                                    window.DayOneSupabaseBridge.onCliHandshake(c, d);
                                                  }
                                                } catch (e) {}
                                              }
                                              setInterval(check, 450);
                                              check();
                                            })();
                                            """.trimIndent(),
                                            null
                                        )
                                    }
                                }

                                loadUrl(handshake.loginUrl)
                            }
                        }
                    )

                    if (isLoadingWeb || isAuthenticating) {
                        Box(
                            modifier = Modifier
                                .align(Alignment.Center)
                                .clip(RoundedCornerShape(16.dp))
                                .background(ThemeColors.bgStop1.copy(alpha = 0.92f))
                                .border(1.dp, Color.White.copy(alpha = 0.14f), RoundedCornerShape(16.dp))
                                .padding(20.dp)
                        ) {
                            Column(
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.spacedBy(10.dp)
                            ) {
                                CircularProgressIndicator(
                                    color = ThemeColors.accentCyan,
                                    modifier = Modifier.size(26.dp),
                                    strokeWidth = 2.5.dp
                                )
                                Text(
                                    text = if (isAuthenticating) "Decrypting ECDH Management Token..." else "Loading Supabase Cloud Login...",
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
