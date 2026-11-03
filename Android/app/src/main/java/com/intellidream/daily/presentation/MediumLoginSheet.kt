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
import androidx.compose.foundation.interaction.MutableInteractionSource
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
 * Modern authentication sheet for Medium supporting both browser-based OAuth/redirect login
 * (including Facebook, Google, Apple) and direct handle configuration.
 */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun MediumLoginSheet(
    initialUsername: String? = null,
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
                .background(Color.Black.copy(alpha = 0.65f))
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    onClick = onDismiss
                ),
            contentAlignment = if (isFoldable) Alignment.Center else Alignment.BottomCenter
        ) {
            val sheetShape = if (isFoldable) RoundedCornerShape(24.dp) else RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp)

            Column(
                modifier = Modifier
                    .then(
                        if (isFoldable) {
                            Modifier
                                .widthIn(max = 720.dp)
                                .fillMaxHeight(0.88f)
                        } else {
                            Modifier
                                .fillMaxWidth()
                                .fillMaxHeight(0.94f)
                        }
                    )
                    .clip(sheetShape)
                    .background(Color(0xFF120D1A))
                    .border(1.dp, Color.White.copy(alpha = 0.15f), sheetShape)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                        onClick = { focusManager.clearFocus() }
                    )
                    .imePadding()
            ) {
                // Drag handle (non-foldable only)
                if (!isFoldable) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 10.dp, bottom = 4.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Box(
                            modifier = Modifier
                                .width(36.dp)
                                .height(4.dp)
                                .clip(CircleShape)
                                .background(Color.White.copy(alpha = 0.25f))
                        )
                    }
                }

                // Header Bar
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 18.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = "Login to Medium",
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )

                    IconButton(
                        onClick = onDismiss,
                        modifier = Modifier.size(32.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.Close,
                            contentDescription = "Close",
                            tint = ThemeColors.accentCyan,
                            modifier = Modifier.size(20.dp)
                        )
                    }
                }

                HorizontalDivider(color = Color.White.copy(alpha = 0.10f))

                // Quick Direct Handle Setup Bar
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Color.Black.copy(alpha = 0.35f))
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(14.dp))
                            .background(Color.White.copy(alpha = 0.08f))
                            .border(1.dp, Color.White.copy(alpha = 0.12f), RoundedCornerShape(14.dp))
                            .padding(horizontal = 14.dp, vertical = 8.dp),
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
                                        text = "Enter Medium handle (e.g. johndoe)",
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
                        text = "Or sign in below to automatically detect your Medium account & reading list",
                        color = ThemeColors.fgMutedDark,
                        fontSize = 11.sp
                    )
                }

                HorizontalDivider(color = Color.White.copy(alpha = 0.12f))

                // WebKit Browser View with Third-Party OAuth Support
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f)
                        .background(Color(0xFF120D1A))
                ) {
                    AndroidView(
                        factory = { ctx ->
                            WebView(ctx).apply {
                                layoutParams = ViewGroup.LayoutParams(
                                    ViewGroup.LayoutParams.MATCH_PARENT,
                                    ViewGroup.LayoutParams.MATCH_PARENT
                                )
                                setBackgroundColor(0xFF120D1A.toInt())

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

                                fun checkUrl(url: String?, webView: WebView?): Boolean {
                                    if (url.isNullOrBlank() || detectedCompleted) return false
                                    val uri = try { Uri.parse(url) } catch (_: Exception) { return false }
                                    val host = uri.host?.lowercase() ?: return false

                                    if (host.contains("medium.com")) {
                                        val path = uri.path ?: ""
                                        if (path.startsWith("/@")) {
                                            val parts = path.removePrefix("/@").split("/")
                                            val detected = parts.firstOrNull()?.trim()
                                            if (!detected.isNullOrEmpty()) {
                                                detectedCompleted = true
                                                onConnect(detected)
                                                onDismiss()
                                                return true
                                            }
                                        } else if (host != "medium.com" && host != "www.medium.com" && host != "api.medium.com" && host.endsWith(".medium.com")) {
                                            val sub = host.substringBefore(".medium.com").trim()
                                            if (sub.isNotEmpty()) {
                                                detectedCompleted = true
                                                onConnect(sub)
                                                onDismiss()
                                                return true
                                            }
                                        } else if (path == "/" || path == "" || path == "/?source=logo") {
                                            webView?.post {
                                                webView.loadUrl("https://medium.com/me")
                                            }
                                        }
                                    }
                                    return false
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
                                        // Route popups (such as Facebook OAuth or Google sign-in) back into the primary WebView
                                        val transport = resultMsg?.obj as? WebView.WebViewTransport
                                        transport?.webView = view
                                        resultMsg?.sendToTarget()
                                        return true
                                    }
                                }

                                webViewClient = object : WebViewClient() {
                                    override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                                        val url = request?.url?.toString() ?: return false
                                        if (checkUrl(url, view)) {
                                            return true
                                        }
                                        return false
                                    }

                                    override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                                        isLoadingWeb = true
                                        checkUrl(url, view)
                                    }

                                    override fun onPageFinished(view: WebView?, url: String?) {
                                        isLoadingWeb = false
                                        checkUrl(url, view)
                                    }
                                }

                                loadUrl("https://medium.com/m/signin")
                            }
                        },
                        modifier = Modifier.fillMaxSize()
                    )

                    if (isLoadingWeb) {
                        Box(
                            modifier = Modifier
                                .fillMaxSize()
                                .background(Color(0xFF120D1A).copy(alpha = 0.85f)),
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
                                    text = "Loading Medium...",
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
