# Medium Web OAuth Authentication Parity & Dialog Expansion (2026)

## 1. Overview & Problem Statement
On WinUI 3, Medium authentication has represented the ecosystem gold standard: tapping "Login to Medium" opens an expansive secondary window with a full `WebView2` pointing to `https://medium.com/m/signin`. This allows users to authenticate using any supported federated provider (Facebook, Google, Apple) or email, automatically detecting their authenticated handle (`/@<username>` or `<user>.medium.com`) and configuring their Reading List RSS feed without manual typing.

On non-WinUI platforms (iOS, macOS, and Android), users reported significant usability regressions:
1. **Dialog Failed to Expand**:
   - On macOS, the sheet dialog collapsed into a tiny horizontal strip showing only the manual username text field; the WebKit view was invisible.
   - On Android, there was no web-based dialog at all — only a text-only `AlertDialog` prompting for a username.
2. **Facebook Login Unusable**:
   - Because embedded webviews lacked popup window delegation (`WKUIDelegate` on Apple platforms, `WebChromeClient.onCreateWindow` on Android) and third-party cookie permissions, tapping "Sign in with Facebook" failed silently or remained unresponsive. Users were forced to fall back to manual handle entry.

---

## 2. Root Cause Analysis

### A. macOS Sheet Collapsing & Missing Intrinsic Dimensions
- In SwiftUI on macOS, presenting a view inside `.sheet(...)` relies on the content's intrinsic size unless explicit frame dimensions are defined.
- `NSViewRepresentable` wrapping `WKWebView` returns an intrinsic size of `(-1, -1)` (no intrinsic size). Consequently, SwiftUI collapsed the sheet to the minimal size of its sibling views — a tiny 60px high bar showing only the manual `@` handle input.

### B. iOS & macOS WebKit Popup Dropping
- Medium's web sign-in buttons (specifically Facebook and Google OAuth) frequently use `window.open(...)` or `<a target="_blank">`.
- In WebKit, if `WKUIDelegate.webView(_:createWebViewWith:for:windowFeatures:)` is not implemented, all `window.open` calls and `target="_blank"` requests (`navigationAction.targetFrame == nil`) are discarded by default.
- Additionally, generic in-app browser user agents are often blocked or restricted by Facebook and Google OAuth endpoints.

### C. Android Text-Only Limitation
- In `Android/app/src/main/java/com/intellidream/daily/presentation/SettingsScreen.kt`, the Medium connection trigger was wired directly to an `AlertDialog` containing only an `OutlinedTextField`. No `WebView` component existed in the Android presentation layer for Medium sign-in.

---

## 3. Architectural Resolution & Parity Engineering

### A. Android: Native Compose `MediumLoginSheet`
Created `Android/app/src/main/java/com/intellidream/daily/presentation/MediumLoginSheet.kt`:
1. **Adaptive Modal Dialog**:
   - Built on `Dialog(properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false))` with a smooth 65% black scrim.
   - Adapts automatically to hardware form factors:
     - On standard smartphones: 94% height bottom sheet with rounded top corners (`24.dp`) and a drag handle.
     - On foldables and tablets (`configuration.screenWidthDp >= 600`): Centered 720dp modal card with uniform `24.dp` corners.
2. **Dual-Mode Authentication**:
   - Preserves a sleek top bar for manual handle entry with `@` prefix and "Connect" button.
   - Embeds a full-height Android `WebView` loading `https://medium.com/m/signin`.
3. **OAuth Popup Delegation**:
   - Configured `WebChromeClient.onCreateWindow` to route popup window transports back into the primary WebView:
     ```kotlin
     override fun onCreateWindow(view: WebView?, isDialog: Boolean, isUserGesture: Boolean, resultMsg: Message?): Boolean {
         val transport = resultMsg?.obj as? WebView.WebViewTransport
         transport?.webView = view
         resultMsg?.sendToTarget()
         return true
     }
     ```
4. **Third-Party Cookies & Mobile User-Agent**:
   - Enabled `CookieManager.setAcceptThirdPartyCookies(webView, true)` and set a modern Chrome Mobile User-Agent to ensure seamless Facebook OAuth redirects.
5. **Intelligent URL Detection**:
   - Monitors `shouldOverrideUrlLoading`, `onPageStarted`, and `onPageFinished`.
   - Recognizes `/@<username>`, `<user>.medium.com`, and handles `/me` redirects to isolate the username, save settings, and dismiss the dialog automatically.
6. **Cookie Cleanup on Disconnect**:
   - Disconnecting an account triggers `CookieManager.removeAllCookies(null)`, preventing subsequent sessions from being locked to the previous account.

### B. macOS: Frame Sizing & WKUIDelegate
Updated `MacOS/Daily/Views/Settings/MediumLoginSheet.swift`:
1. **Explicit Desktop Sheet Sizing**:
   - Added `.frame(minWidth: 720, idealWidth: 800, maxWidth: 960, minHeight: 680, idealHeight: 780, maxHeight: 920)` to `NavigationStack`, ensuring the sheet opens fully expanded with a prominent WebKit reading area.
2. **WKUIDelegate & Target Frame Interception**:
   - Implemented `WKUIDelegate.webView(_:createWebViewWith:for:windowFeatures:)` and handled `navigationAction.targetFrame == nil` in `decidePolicyFor navigationAction` by redirecting the request into `webView.load(navigationAction.request)`.
3. **Desktop Safari User-Agent**:
   - Configured `customUserAgent` matching macOS Safari 18.2.
4. **Cookie Storage & Cleanup**:
   - Utilizes shared `WKWebsiteDataStore.default()`, and purges `medium.com` cookies upon account disconnection in `FeaturesSettingsSection.swift`.

### C. iOS: Large Sheet Presentation & OAuth Interception
Updated `iOS/Daily/Views/Settings/MediumLoginSheet.swift` and `FeaturesSettingsSection.swift`:
1. **Large Presentation Detents**:
   - Configured `.presentationDetents([.large])` and `.presentationDragIndicator(.visible)` so the sheet expands to full modal height immediately.
2. **WKUIDelegate & Target Frame Interception**:
   - Added popup interception routing `target="_blank"` and `window.open` requests into the existing `WKWebView`.
3. **Mobile Safari User-Agent**:
   - Configured iOS 18 Safari User-Agent to satisfy Facebook OAuth verification.
4. **Cookie Storage & Cleanup**:
   - Automatically purges `medium.com` cookies upon account disconnection.

---

## 4. Verification & Testing Matrix

| Platform | Verification Method | Status | Notes |
| :--- | :--- | :--- | :--- |
| **DailyCore (Swift)** | `swift test --package-path DailyCore --filter NewsServiceTests` | Passed (19/19) | Added `testMediumOAuthRedirectUrlParsing` validating handles, subdomains, and `/me` redirects |
| **Android (Kotlin)** | `./gradlew :core-model:testDebugUnitTest` | Passed | Added `testMediumOAuthRedirectUrlParsing` validating URL patterns |
| **macOS Native** | `xcodebuild -project MacOS/Daily.xcodeproj -scheme Daily` | Build Succeeded | Clean compilation, valid codesign with `Daily.debug.dylib` |
| **iOS Native** | `xcodebuild -project iOS/Daily.xcodeproj -scheme Daily` | Build Succeeded | Clean compilation, valid codesign with team provisioning |
| **iPhone 16 Pro ("Schmitz")** | `xcrun devicectl device install app` | Deployed | Installed successfully on physical device |
| **Google Pixel 9 Pro ("Trapper")**| `adb install -r app-debug.apk` | Deployed | Streamed install succeeded (`Success`) |
| **Parallels Windows 11 VM** | Cross-platform reference | Verified | Gold standard baseline preserved with zero changes |

---

## 5. Summary of Files Changed

- `Android/app/src/main/java/com/intellidream/daily/presentation/MediumLoginSheet.kt` (New Compose sheet with embedded WebView & popup support)
- `Android/app/src/main/java/com/intellidream/daily/presentation/SettingsScreen.kt` (Wired `MediumLoginSheet` and cookie cleanup on disconnect)
- `Android/core-model/src/test/java/com/intellidream/daily/model/NewsParsersTest.kt` (Added `testMediumOAuthRedirectUrlParsing`)
- `MacOS/Daily/Views/Settings/MediumLoginSheet.swift` (Configured sheet frame, `WKUIDelegate`, and Safari user agent)
- `MacOS/Daily/Views/Settings/FeaturesSettingsSection.swift` (Added WebKit cookie cleanup on disconnect)
- `iOS/Daily/Views/Settings/MediumLoginSheet.swift` (Configured `.large` detents, `WKUIDelegate`, and Safari user agent)
- `iOS/Daily/Views/Settings/FeaturesSettingsSection.swift` (Configured `.large` detents and WebKit cookie cleanup on disconnect)
- `DailyCore/Tests/DailyCoreTests/NewsServiceTests.swift` (Added `testMediumOAuthRedirectUrlParsing`)
- `Docs/Features/News.md` (Updated with section 6.8)
- `Docs/Features/Medium_OAuth_Web_Login_Parity_And_Dialog_Expansion_2026.md` (Comprehensive documentation)
