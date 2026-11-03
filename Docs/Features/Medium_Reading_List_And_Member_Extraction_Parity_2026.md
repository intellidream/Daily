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

## 4. Verification & Testing

| Platform / Module | Test Suite / Command | Result | Verification Notes |
| :--- | :--- | :--- | :--- |
| **DailyCore (Swift)** | `swift test --package-path DailyCore --filter NewsServiceTests` | **Passed (20/20)** | Added `testMediumImageOptimizationAndReadingListParsing` validating Miro CDN URL regex and scraped article deserialization |
| **Android (Kotlin)** | `./gradlew :core-model:testDebugUnitTest :core-database:testDebugUnitTest` | **Passed** | Added `testMediumImageOptimizationAndScrapedItemParsing` in `NewsParsersTest.kt` |
| **macOS Native** | `xcodebuild -project MacOS/Daily.xcodeproj -scheme Daily -configuration Debug -destination 'platform=macOS' build` | **BUILD SUCCEEDED** | Signed atomically with Apple Development credentials |
| **iOS Native** | `xcodebuild -project iOS/Daily.xcodeproj -scheme Daily -configuration Debug -destination 'id=00008140-000E2C863EFB001C' build` | **BUILD SUCCEEDED** | Clean build with embedded `DailyWidgetsExtension` |
| **Android App** | `./gradlew assembleDebug` | **BUILD SUCCEEDED** | Verified R8 / DEX compilation without regressions |
| **Physical iPhone Schmitz** | `xcrun devicectl device install app --device 00008140-000E2C863EFB001C` | **Installed** | Deployed live to iPhone 16 Pro |
| **Physical Pixel 9 Pro Trapper** | `adb -s adb-48231FDAP0011V-Ma9KPE._adb-tls-connect._tcp install -r` | **Installed** | Deployed live to Google Pixel 9 Pro |

---

## 5. Paywall & Security Compliance
- Zero unauthorized paywall circumvention or proxy bypasses are used.
- The headless WebViews directly leverage the user's authentic session cookies acquired during legitimate sign-in in Settings -> Features.
- If the user is a paid member, stories render in full. If the user is not a member, Medium displays standard previews, mirroring WinUI and desktop browser behavior identically.
