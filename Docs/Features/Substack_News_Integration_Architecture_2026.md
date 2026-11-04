# Substack News Integration Architecture (2026)

## 1. Executive Summary

This document specifies the end-to-end architecture and implementation details for native Substack integration across all supported client platforms in Daily: **macOS**, **iOS**, **Android**, and **Windows 11 (WinUI 3)**.

The feature extends Daily's News Reader and RSS engine to support:
1. **Interactive In-App Web Authentication**: Seamless login to `https://substack.com/sign-in` via platform web engines (`WKWebView` on Darwin, Android WebKit `WebView`, and Microsoft Edge `WebView2` on Windows) with automated extraction of `substack.sid` / `connect.sid` session cookies and account handle detection (`window._preloads.user` + profile DOM link fallback).
2. **Substack Account Management & Automated Subscription Sync**:
   - Real-time session monitoring displaying `@handle (Session Active)` with live cookie validation and `(Session Inactive - Reconnect)` fallback.
   - Automatic & one-tap **Sync Subscriptions** (`Sync Substack`) importing all existing user Substack newsletters into Daily's feeds and Supabase via authenticated same-origin `https://substack.com/api/v1/subscriptions` (capturing both public & private subscriptions and custom domains) combined with public `https://substack.com/api/v1/user/{handle}/public_profile`.
3. **API-First Substack Inbox (`substack_inbox`)**:
   - Primary fast path via Substack's authenticated JSON API (`https://substack.com/api/v1/reader/posts?limit=35` joined with `/api/v1/subscriptions`) returning real ISO-8601 `post_date` timestamps, newsletter `logo_url` icons, `publication.name`, `canonical_url` (including custom domains), and pre-hydrated clean `body_html` for instant 0ms Reader opening.
   - Multi-tier resilience: falls back to `/inbox` DOM scraping and finally aggregates subscribed Substack RSS feeds if offline or signed out.
4. **Distraction-Free Editorial Reader & Pencraft Purification**:
   - **API-First Extraction**: Queries `https://{host}/api/v1/posts/{slug}` for clean `body_html` + `subtitle` + `audience` without website chrome, and upgrades subscriber-only (`only_paid`) or bonus-content posts via same-origin authenticated `https://substack.com/api/v1/posts/by-id/{id}` (unlocking paid newsletters even on custom domains such as `pragmaticengineer.com` or `stratechery.com` where third-party cookies do not travel).
   - **6-Pass Pencraft HTML Purifier (`stripSubstackTrackingAndNoise`)**: Strips Pencraft image action overlay toolbars/SVGs (`.image-link-expand`, `button.restack-image`, `button.view-image`), unwraps `<picture>` and strips low-res 424px `<source srcset>` thumbnails so crisp `w_1200` `<img src>` always renders, removes nested `.subscription-widget-wrap` / `<form>` widgets, strips 1x1 `eotrx.substackcdn.com` tracking pixels, and strips inline Subscribe/Share CTA buttons while preserving legitimate external link buttons.
   - **S3 UUID Cover Image Deduplication**: Normalizes `substackcdn.com` / `substack-post-media` URLs by their percent-decoded S3 asset UUID filename so cover images are never duplicated even when RSS and body HTML carry different `$s_!...!` CDN signature tokens.
   - **Substack Reader Typography CSS**: Dedicated styling across macOS, iOS, WinUI 3, and Android for `.substack-subtitle`, `.captioned-image-container`, `.image-caption`, `.pullquote`, `.callout-block`, `.embedded-post-wrap`, `.button-wrapper a.button`, `.footnote`, and `.substack-paid-card`.
5. **Substack Publisher Discovery & One-Tap Subscriptions**:
   - **Parallel Substack Search**: Queries `https://substack.com/api/v1/top/search?query={q}&page=0` in parallel alongside Feedly in Manage Feeds / Feed Discovery, plus direct `@handle`, `*.substack.com`, `open.substack.com/pub/{slug}`, and custom-domain Substack feed resolution (`https://{custom_domain}/feed`), while strictly rejecting invalid root `https://substack.com/feed`.
   - **Always-Visible `+ Subscribe` / `Subscribed` Controls**: Displayed on all Substack article cards (even when `author` metadata is absent) and directly in the Reader top toolbar across all four platforms.
6. **Zero-Regression Guarantee**: Strict isolation of `isSubstack` and `isSubstackTeaser` checks so Ziarul Financiar (ZF), Recorder, Politico, Republica, Medium, WordPress JSON, and standard RSS feeds remain 100% untouched.

---

## 2. Platform Implementations

### 2.1 macOS & iOS (`DailyCore`, `MacOS/Daily`, `iOS/Daily`)
- **`DailyCore/Sources/DailyCore/Models/NewsModels.swift`**: Upgraded `isSubstackItem` (including custom-domain Substack detection via `substackcdn.com` / `substack-post-media` / `captioned-image-container`), `extractSubstackPublicationSlug`, `extractSubstackFeedUrl`, and `extractSubstackInfo`.
- **`DailyCore/Sources/DailyCore/Services/ArticleExtractor.swift`**:
  - Fixed `isSubstackTeaser`, added `hasSubstackBonusPaywall`, upgraded 6-pass `stripSubstackTrackingAndNoise`, and S3 UUID `normalizeImageUrl` + `deduplicateFeaturedImage`.
  - Upgraded `HeadlessReadabilityParser` with warm `https://substack.com/404` `WKWebView` origin runner (`callAsyncJavaScript`), `fetchSubstackUserSubscriptions(handle:)`, API-first `scrapeSubstackInbox()`, and 3-tier `extractSubstackArticle(url:baseArticle:extractor:)`.
- **`DailyCore/Sources/DailyCore/Services/NewsService.swift`**: Parallel `searchSubstackPublications` in `discoverFeeds`, `syncSubstackSubscriptions(handle:)`, `iconUrl` preservation in `addFeed`, custom-domain support in `subscribeToSubstackPublication`, and RSS aggregation fallback for `substack_inbox`.
- **`MacOS/Daily` & `iOS/Daily` Views**:
  - `ArticleWebView.swift`: Added Substack editorial CSS rules.
  - `NewsArticleCard.swift` & `NewsReaderView.swift`: Unconditional Substack `+ Subscribe` / `Subscribed` pill on cards and Reader top toolbar.
  - `NewsFeedsManagementSheet.swift`, `FeaturesSettingsSection.swift`, `SubstackLoginSheet.swift`: Added `"Sync Substack"` / `"Sync Subscriptions"` buttons and automatic subscription import upon login.

### 2.2 Windows 11 (`WinUI/Daily.WinUI` & `Services/RssFeedService.cs`)
- **`Services/IRssFeedService.cs` & `Services/RssFeedService.cs`**: Optional `iconUrl` parameter on `AddFeedAsync`, parallel Substack `/api/v1/top/search` discovery in `DiscoverFeedsAsync`, `FetchSubstackPublicSubscriptionsAsync`, and root `substack.com/feed` guard.
- **`WinUI/Daily.WinUI/Views/RssFeedDetailPage.xaml(.cs)` & `Controls/RssFeedWidgetControl.xaml.cs`**:
  - Added `ExecuteAsyncScriptOnWebViewAsync` Promise-polling bridge for `WebView2` (`ExecuteScriptAsync` does not natively await JS Promises).
  - Implemented `ExtractSubstackArticleAsync` (`/api/v1/posts/{slug}` + authenticated `/api/v1/posts/by-id/{id}` + `.body.markup` fallback), `ScrapeSubstackInboxSharedAsync` (`/api/v1/reader/posts` + `/api/v1/subscriptions` join), 6-pass `StripSubstackTrackingAndNoise`, S3 UUID `DeduplicateSubstackFeaturedImage`, Substack Reader CSS, and `ReaderSubscribeButton` in Reader toolbar.
- **`WinUI/Daily.WinUI/Views/FeaturesPage.xaml(.cs)`**: Added `"Sync Substack"` & `"Sync Subscriptions"` buttons, `SubstackSyncWebView`, and automatic subscription sync on login/startup.

### 2.3 Android (`core-model`, `core-network`, `core-database`, `app`)
- **`Android/core-model`**: Upgraded `NewsModels.kt` (`isSubstackItem`, `extractSubstackPublicationSlug`, `extractSubstackFeedUrl`, `extractSubstackInfo`), `ArticleExtractor.kt` (6-pass `stripSubstackTrackingAndNoise`, `isSubstackTeaser`, `hasSubstackBonusPaywall`, S3 UUID `normalizeImageUrl`), and unit tests in `NewsParsersTest.kt`.
- **`Android/core-network/NewsRemoteService.kt`**: Parallel `searchSubstackPublications` (`/api/v1/top/search`) alongside Feedly in `searchFeedly`, `fetchSubstackPublicSubscriptions`, and invalid root feed filtering.
- **`Android/core-database/NewsRepository.kt` & `DailyApp.kt`**: Added `syncSubstackSubscriptions`, Substack RSS fast-path purification & cover deduplication in `fetchFullArticle`, custom-domain subscription support, and Substack Inbox RSS aggregation fallback.
- **`Android/app/news/SubstackWebViewBridge.kt`**: Implemented `evaluateAsyncJs` Promise-polling bridge on `https://substack.com/404`, `fetchAuthenticatedSubscriptions`, API-first `scrapeInbox`, and 3-tier `extractArticle`.
- **`Android/app/presentation`**: Upgraded `NewsArticleCard.kt`, `NewsFeedView.kt`, `NewsReaderSheet.kt` (toolbar `+ Subscribe` pill + Substack Reader CSS), `NewsFeedsManagementSheet.kt` (`Sync Substack`), `SubstackLoginSheet.kt`, and `SettingsScreen.kt` (`Sync Subscriptions` + auto-sync on connect).

---

## 3. Verification Matrix

| Platform | Verification Environment | Build / Test Command | Status |
| :--- | :--- | :--- | :--- |
| **DailyCore** | macOS SwiftPM | `swift test --package-path DailyCore --filter NewsServiceTests` | **PASSED (26/26 tests)** |
| **macOS** | Host Mac (Apple Silicon) | `xcodebuild -project MacOS/Daily.xcodeproj -scheme Daily -configuration Debug -destination 'platform=macOS' build` | **BUILD SUCCEEDED** |
| **iOS Simulator** | SimulaPhone & SimulaDuo | `xcodebuild -project iOS/Daily.xcodeproj -scheme Daily ... build` + `simctl install` | **BUILD SUCCEEDED & INSTALLED** |
| **iOS Device** | iPhone ("Schmitz") | `xcodebuild ... -destination 'generic/platform=iOS' build` | **SIGNED DEVICE BUILD SUCCEEDED** |
| **Windows 11** | Parallels VM (ARM64) | `dotnet build WinUI\Daily.WinUI\Daily.WinUI.csproj -c Debug -p:Platform=ARM64` | **0 Errors, 0 Regressions** |
| **Android** | Unit Tests + Debug APK | `./gradlew :core-model:testDebugUnitTest` & `./gradlew assembleDebug` | **BUILD SUCCESSFUL** |
