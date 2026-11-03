# Medium Reading List & Member Article Extraction Parity (November 2026)

## 1. Overview & Problem Context
Following the completion of Medium OAuth login parity across iOS, macOS, and Android, users reported two operational defects:
1. **Medium Reading List Failed to Load**: Navigating to the Medium Reading List feed returned an empty list or errors across iOS, macOS, and Android.
2. **Medium Stories Did Not Enter Member Logged-In Mode**: When opening Medium articles (both from reading lists and from separate Medium author feeds such as `@ev` or `@marclou`), stories failed to recognize the user's active paid/member session. The app fell back to truncated paywall previews instead of displaying the complete, member-unlocked article text available on WinUI (the gold standard).

---

## 2. Root Cause Analysis

### A. Medium Reading List Loading Defect
- **Medium lacks an RSS feed for Reading Lists**:
  - `DailyCore/NewsService.swift` and Android's `NewsRepository.kt` formerly attempted to load `https://medium.com/feed/@username` as an RSS feed.
  - `https://medium.com/feed/@username` is an RSS feed of stories **published** by that user, *not* their saved reading list! If the user had not published their own articles, the feed returned zero items.
  - The actual Medium Reading List URL (`https://medium.com/@username/list/reading-list`) is an authenticated HTML/Single Page Application (SPA) driven by React and client-side GraphQL; it cannot be parsed by standard XML/RSS parsers.
- **WinUI's Gold Standard Strategy**:
  - WinUI navigates a background `WebView2` (sharing the authenticated user profile and session cookies) to `https://medium.com/@username/list/reading-list`.
  - Once rendered, WinUI executes a DOM scraping script (`document.querySelectorAll('article')`), extracting `title`, `url`, `author`, `imageUrl`, and `description`, deserializing the JSON array into `RssItem` models.

### B. Member Article Extraction Defect
- **Unauthenticated Headless HTTP GET**:
  - iOS/macOS `ArticleExtractor.swift` and Android's `NewsRepository.kt` fetched article HTML using anonymous `URLSession` / `HttpURLConnection` without cookies.
  - Medium detected an unauthenticated visitor and returned server-rendered paywall teaser HTML (1-2 paragraphs + "Member-only story").
  - Furthermore, Medium uses client-side hydration (React/Next.js) for paid member content. Without a JavaScript engine and authenticated cookies, the member payload was never rendered.
- **WinUI's Gold Standard Strategy**:
  - In `RssFeedDetailPage.xaml.cs`, WinUI forces `needsWebViewFallback = true` for any URL containing `medium.com` or publication named `Medium`.
  - It navigates `ReaderWebView` directly to the story URL with the user's authenticated session cookies.
  - It waits for page settlement and hydration, runs an overlay cleanup script (removing cookie banners, GDPR modals, and paywalls), checks for `article, main, [itemprop="articleBody"]` content (>200 characters or >500 characters body text), extracts the rendered DOM, and runs Mozilla Readability.

---

## 3. Implementation Details

### A. iOS & macOS (DailyCore & WebKit)
- **`ArticleExtractor.swift`**:
  - Defined `ScrapedMediumItem` (`Codable, Sendable`) to model scraped Medium story cards.
  - Added `nonisolated public static func optimizeMediumImageUrl(_ url: String) -> String` to replace Miro CDN thumbnail dimensions (`v2/resize:fill:...`) with high-resolution `v2/resize:fit:800`.
  - In `extract(from:baseArticle:)`, added early detection:
    ```swift
    let isMedium = safeUrlString.contains("medium.com") || (baseArticle?.publicationName?.contains("Medium") == true)
    #if canImport(WebKit)
    if isMedium {
        if let mediumArticle = await HeadlessReadabilityParser.shared.extractMediumArticle(
            url: url,
            baseArticle: baseArticle,
            extractor: self
        ), let content = mediumArticle.content, content.count > 100 {
            return mediumArticle
        }
    }
    #endif
    ```
  - In `HeadlessReadabilityParser`:
    - Implemented `NavigationObserver: NSObject, WKNavigationDelegate` with continuation completion and a 12-second safety timeout.
    - Implemented `createAuthenticatedWebView()` configuring `config.websiteDataStore = .default()`, JavaScript execution, and desktop/mobile Safari User-Agent.
    - Implemented `extractMediumArticle(url:baseArticle:extractor:)`: navigates to the article URL with authenticated cookies, delays 2.0s for React hydration, executes overlay cleanup, polls for the populated article DOM, and passes the unlocked HTML into Readability.
    - Implemented `scrapeMediumReadingList(urlString:)`: navigates to the reading list URL, polls for `<article>` items, executes WinUI's exact scraping JavaScript, deserializes JSON, splits `"Author in Publication"`, optimizes Miro CDN images, and returns `[NewsArticle]`.
- **`NewsService.swift`**:
  - Updated `mediumReadingListFeedSource` to fall back to `https://medium.com/@<cleanUser>/list/reading-list`.
  - In `fetchFeedItems`, for `feed.id == "medium_reading_list"`, invokes `HeadlessReadabilityParser.shared.scrapeMediumReadingList(urlString: readingListUrl)`.

### B. Android (Kotlin, Room & WebView Interop)
- **`NewsModels.kt`**:
  - Added `ScrapedMediumArticle` data class and `optimizeMediumImageUrl(url: String)` function matching WinUI's Miro CDN regex replacement.
- **`NewsRepository.kt`**:
  - Extended `NewsSyncHandler` with optional methods:
    ```kotlin
    suspend fun scrapeMediumReadingList(readingListUrl: String): List<NewsArticle>? = null
    suspend fun extractMediumArticle(url: String, baseArticle: NewsArticle? = null): NewsArticle? = null
    ```
  - In `fetchFeedItems(feed)`, if `feed.id == "medium_reading_list"`, delegates to `syncHandler?.scrapeMediumReadingList(feed.url)`.
  - In `fetchFullArticle(article)`, if `isMedium`, delegates to `syncHandler?.extractMediumArticle(article.link, article)` before falling back to HTTP extraction.
  - In `downloadString`, retrieves cookies via `CookieManager.getInstance().getCookie(...)` and sets the `Cookie` header on `HttpURLConnection`.
  - Updated `mediumReadingListFeedSource` fallback URL to `https://medium.com/@$clean/list/reading-list`.
- **`NewsRemoteService.kt`**:
  - In `fetchUrl(url)`, attaches `Cookie` header from `CookieManager.getInstance()`.
- **`MediumWebViewBridge.kt`**:
  - Implemented `MediumWebViewBridge(context: Context)` in `com.intellidream.daily.news`:
    - `scrapeReadingList(url: String)`: executes headless WebView on `Dispatchers.Main` with `CookieManager` enabled, polls for `<article>`, runs the WinUI scraping script, and parses results into `[NewsArticle]`.
    - `extractArticle(url: String, baseArticle: NewsArticle?)`: loads the article in WebView with user session cookies, waits 2s for React hydration, strips overlay popups, extracts the member article body, and parses with `ArticleExtractor.shared.parseHtml`.
- **`DailyApp.kt`**:
  - Instantiates `MediumWebViewBridge(this)` and wires `scrapeMediumReadingList` and `extractMediumArticle` to `newsHandler`.

---

## 5. Complete Article Rendering & Member Hydration Resolution (Update)

### A. Root Causes of Incomplete Medium Articles
Even when logged in, users observed that Medium articles across all platforms were truncated after a few paragraphs:
1. **Destructive Selector Deletion (`cleanupScript`)**:
   - The overlay cleanup script previously executed:
     `selectors = [..., '[class*="paywall"]', '[class*="overlay"]', ...]; selectors.forEach(s => document.querySelectorAll(s).forEach(e => e.remove()));`
   - In Medium's React application, member-only article bodies or post containers have classes containing `paywall` (e.g. `postPaywall`, `meteredContent`, `paywall-content`).
   - Removing all elements matching `[class*="paywall"]` stripped out the actual story body, leaving only the preview teaser!
2. **Premature Extraction Loop Termination**:
   - In WinUI, iOS/macOS (`ArticleExtractor.swift`), and Android (`MediumWebViewBridge.kt`), the extraction loops broke on the very first second (when character count exceeded 200–500 chars), capturing only the server-rendered preview before React hydrated the full member story payload.
3. **RSS `<content:encoded>` Bypassed**:
   - Medium author and tag RSS feeds already contain the entire article in `<content:encoded>`.
   - Forcing WebView scraping for every Medium article unconditionally discarded the complete article already present in `item.Content`.

### B. Architectural Solution Across All Platforms
1. **High-Value Content Fast-Path Preservation**:
   - In WinUI (`RssFeedDetailPage.xaml.cs`), iOS/macOS (`ArticleExtractor.swift`), and Android (`NewsRepository.kt`):
     If `item.Content` already contains > 250 characters and does not contain paywall truncation markers (`"Continue reading on Medium"`, `"member-only story"`), the content is preserved and rendered directly without web scraping overhead or risks.
2. **Content-Guarded Cleanup Script**:
   - `cleanupScript` enforces strict content safety guards:
     ```javascript
     selectors.forEach(function(s){
         document.querySelectorAll(s).forEach(function(e){
             if(e.tagName==='ARTICLE'||e.tagName==='MAIN'||e.tagName==='SECTION') return;
             if(e.querySelectorAll('p').length>=2||(e.innerText||'').length>300) return;
             e.remove();
         });
     });
     ```
   - Target only explicit upsell modals (`.meteredContentUpsell`, `[data-testid="paywall-dialog"]`, `[data-testid="upgrade-banner"]`, `[data-testid="postPaywallBanner"]`) when they do not contain real story paragraphs.
3. **Scroll Hydration & Dynamic Stabilization Loop**:
   - The WebView extraction triggers smooth scroll events (`window.scrollTo(0, document.body.scrollHeight / 2)`, `window.scrollTo(0, document.body.scrollHeight)`, `window.scrollTo(0, 0)`) to activate Medium's `IntersectionObserver` / lazy rendering.
   - The extraction loop tracks character length and paragraph count across iterations, waiting for text stabilization before extracting.
   - Cleaned `<article>` clone strips out interactive claps, responses stream, and follow buttons before passing to readability.
4. **Publication-Specific Snippet Classification & Subdomain Cookie Parity**:
   - Universal `isMediumTeaser` classifier detects not only generic `"Continue reading on Medium"`, but also publication-specific variants (e.g. `"Continue reading on Starts With A Bang! »"`, `"Continue reading on Towards Data Science »"`), as well as RSS feed markers (`medium-feed-item`, `medium-feed-link`, `medium-feed-snippet`).
   - Ensures that feeds with teasers never bypass headless extraction or present stub snippets to the user.
   - Synchronizes root `.medium.com` session cookies to author and publication subdomains (e.g. `malshikay.medium.com`, `towardsdatascience.com`) across WebKit, Android WebView, and WinUI CoreWebView2.
5. **Resilient Fallback**:
   - If SmartReader or Readability returns truncated text or fails to parse, the system safely falls back to the cleaned `<article>` DOM so no paragraphs are lost.

---

## 6. Phase 3 Forensic Repair: OAuth Cookie Persistence, Subdomain De-Poisoning & Apollo-Aware Extraction (macOS & DailyCore)

### A. Forensic Root Causes Discovered
Live inspection inside the sandboxed macOS `Daily.app` container (`WKWebsiteDataStore.default().httpCookieStore` + `window.__APOLLO_STATE__`) revealed why public Medium RSS articles (e.g. Yohan Malshika's *"LINQ Performance"*, `isLocked: false`, containing full `<content:encoded>` in RSS) opened instantly and completely, whereas Member-Only stories (`isLocked: true`, e.g. *"Understanding the SemaphoreSlim in C#"*, *"Why async void Is Dangerous in C#"*, and *Starts With A Bang!*) stalled for ~9–11s and rendered truncated:
1. **Premature OAuth Redirect Cancellation & `WKWebView` Teardown (`MediumLoginSheet.swift`)**:
   - Facebook/Google OAuth redirects through `/m/callback/<provider>` to `https://medium.com/?source=login...` (`url.path == "/"`).
   - Previously, `MediumLoginSheet` intercepted `decidePolicyFor navigationAction` *before* the navigation committed, aborted the redirect by triggering `webView.load("/me")`, and then called `decisionHandler(.cancel)` + `dismiss()` on `/@username` — tearing down the `WKWebView` before `com.apple.WebKit.Networking` flushed `HttpOnly` `uid` and `sid` cookies to disk, while `newsMediumUsername` was already saved in `SettingsService` (causing Settings to show a false green dot and Reading List to load publicly while `uid` fell back to guest `lo_*`).
2. **Cookie Store Contamination from Reader & Offline Parser WebViews**:
   - `ArticleWebView` and `HeadlessReadabilityParser.getOrCreateWebView()` previously used the default `WKWebsiteDataStore.default()` without the shared Safari `User-Agent`. Opening a free Medium RSS article containing `<img src="https://medium.com/_/stat?...">` fired an unauthenticated/bare-WebKit request that wrote a guest `uid=lo_*` cookie and triggered Cloudflare UA mismatch challenges.
3. **RFC 6265 Subdomain Cookie Shadowing**:
   - Copying cookies onto host-only domains (e.g. `domain = malshikay.medium.com`) created host-specific `uid=lo_*` cookies that permanently shadowed parent `.medium.com` member cookies per RFC 6265 §5.4.
4. **In-Memory Caching of Paywall Stubs & Blind 11-Second Polling**:
   - `ArticleContentCache` previously cached truncated member previews (`> 250` chars without `"continue reading on"`), and `extractMediumArticle` polled 14 times even when `window.__APOLLO_STATE__` already reported all expected words in the DOM (or `isLocked == true && viewer == null`).

### B. Architectural Fixes Implemented (`DailyCore` & `MacOS`)
1. **Commit-Safe OAuth Verification (`MediumLoginSheet.swift`)**:
   - Never cancels normal navigations or OAuth redirects in `decidePolicyFor navigationAction` (only routes `targetFrame == nil` popups into the frame).
   - Verifies authentication exclusively in `didFinish` by inspecting `window.__APOLLO_STATE__.ROOT_QUERY.viewer` AND confirming live non-guest cookies (`uid` not prefixed with `lo_` + `sid` present) via `ArticleExtractor.hasAuthenticatedMediumCookies`, sanitizing cookies, clearing `ArticleContentCache`, and allowing `WKHTTPCookieStore` to flush before dismissing.
2. **True Session Status in Settings (`FeaturesSettingsSection.swift`)**:
   - Evaluates `HeadlessReadabilityParser.shared.hasAuthenticatedMediumSession()` live so Settings distinguishes between an active member session (`🟢 @username`) and an inactive/expired cookie jar (`🟠 @username · Session Inactive` with a one-click **Reconnect Medium Session** action), without adding intrusive banners inside `NewsReaderView`.
3. **Isolated `.nonPersistent()` Reader & Readability WebViews + Tracking Pixel Cleanup**:
   - Both `ArticleWebView` and `HeadlessReadabilityParser.getOrCreateWebView()` now use `WKWebsiteDataStore.nonPersistent()`, and `ArticleExtractor.stripMediumTrackingAndNoise` strips `medium.com/_/stat` 1x1 pixels and inline `"stories in your inbox"` prompts.
   - Unified `HeadlessReadabilityParser.mediumSafariUserAgent` across `MediumLoginSheet` and `createAuthenticatedWebView()`.
4. **Subdomain De-Poisoning & Fast `__APOLLO_STATE__` Extraction (`ArticleExtractor.swift`)**:
   - `sanitizeMediumCookies()` purges all host-only `uid`/`sid`/`xsrf`/`cf_clearance` cookies on `*.medium.com` subdomains and stale `lo_*` cookies so `.medium.com` cookies apply cleanly across all author subdomains (`malshikay.medium.com`, etc.), plus routes custom publication domains through `medium.com/p/<postId>` handshake when needed.
   - `extractMediumArticleDetailed` compares live `<article>` word/block counts against `window.__APOLLO_STATE__` (`Post.wordCount`, `Post.isLocked`, `ROOT_QUERY.viewer`), cutting extraction latency to **~1.5–2.1s** and strictly preventing `ArticleContentCache` from caching paywall-truncated previews (`isPaywallTruncated == true`).

---

## 7. Verification & Testing

| Platform / Module | Test Suite / Command | Result | Verification Notes |
| :--- | :--- | :--- | :--- |
| **DailyCore (Swift)** | `swift test --package-path DailyCore --filter NewsServiceTests` | **Passed (25/25)** | Added `testMediumSessionCookieAuthenticationAndSubdomainSanitization` and `testMediumTrackingPixelAndInlineNewsletterCleanup` |
| **Android (Kotlin)** | `./gradlew :core-model:testDebugUnitTest :core-database:testDebugUnitTest` | **Passed** | Added `testMediumTeaserClassification` in `NewsParsersTest.kt` |
| **macOS Native** | `xcodebuild -project MacOS/Daily.xcodeproj -scheme Daily -configuration Debug -destination 'platform=macOS' build` | **BUILD SUCCEEDED** | Signed atomically with Apple Development credentials (`7LZ9ZT2Z5B`), verified live launch |
| **Windows 11 VM** | `dotnet build -c Debug -p:Platform=ARM64` | **BUILD SUCCEEDED** | Native WinUI build with CoreWebView2 cookie sync and hydration |
| **iOS Native** | `xcodebuild -project iOS/Daily.xcodeproj -scheme Daily -configuration Debug -destination 'id=00008140-000E2C863EFB001C' build` | **BUILD SUCCEEDED** | Clean build with embedded `DailyWidgetsExtension` |
| **Android App** | `./gradlew assembleDebug` | **BUILD SUCCEEDED** | Verified R8 / DEX compilation without regressions |
| **Physical iPhone Schmitz** | `xcrun devicectl device install app --device 00008140-000E2C863EFB001C` | **Installed** | Deployed live to iPhone 16 Pro |
| **Physical Pixel 9 Pro Trapper** | `adb -s adb-48231FDAP0011V-Ma9KPE._adb-tls-connect._tcp install -r` | **Installed** | Deployed live to Google Pixel 9 Pro |

---

## 8. Paywall & Security Compliance
- Zero unauthorized paywall circumvention or proxy bypasses are used.
- The headless WebViews directly leverage the user's authentic session cookies acquired during legitimate sign-in in Settings -> Features.
- If the user is a paid member, stories render in full. If the user is not a member, Medium displays standard previews, mirroring WinUI and desktop browser behavior identically.
