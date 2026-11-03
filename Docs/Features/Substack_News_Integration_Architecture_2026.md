# Substack News Integration Architecture (2026)

## 1. Executive Summary

This document specifies the end-to-end architecture and implementation details for native Substack integration across all supported client platforms in Daily: **macOS**, **iOS**, **Android**, and **Windows 11 (WinUI 3)**.

The feature extends Daily's News Reader and RSS engine to support:
1. **Interactive In-App Web Authentication**: Seamless login to `https://substack.com/sign-in` via platform web engines (WKWebView on Darwin, Android WebKit WebView, and Microsoft Edge WebView2 on Windows) with automated extraction of `substack.sid` / `connect.sid` session cookies and `window._preloads.user` account handle.
2. **Substack Account Management & Session Status**: Real-time session monitoring displaying `@handle (Session Active)` with live cookie validation, `(Session Inactive - Reconnect)` fallback, and zero-prompt token storage.
3. **Substack Inbox Source Feed**: A dedicated feed source (`substack_inbox`) added to feed switchers, fetching newsletters and subscriptions directly from `https://substack.com/inbox` using authenticated headless DOM bridges.
4. **Distraction-Free Reader Mode & Noise Stripping**: High-fidelity full-article extraction for subscriber posts with aggressive noise cleaning (stripping `.subscription-widget-wrap`, `.subscribe-widget`, `.post-footer`, `.like-button-container`, `.comment-widget`) and teaser detection (`isSubstackTeaser`).
5. **Retina Image Optimization**: Intelligent rewrite of `substackcdn.com` media URLs (`w_\d+` -> `w_1200`) for high-DPI displays.
6. **One-Tap Publication Subscriptions**: `+ Subscribe` / `Subscribed` button on Substack article cards and reader action bars to add publication RSS feeds (`https://{slug}.substack.com/feed` or `https://substack.com/@{handle}/feed`) directly to custom RSS feeds.
7. **Zero-Regression Guarantee**: Complete preservation of existing news publication features (ZF, Recorder, Politico, Republica, Medium).

---

## 2. Architecture & Contracts

### 2.1 Schema & Data Models

#### Shared Models (`DailyCore` & Android `core-model` & WinUI `Daily.WinUI`)
- **`AppSettings`**:
  - Swift: `public var newsSubstackUsername: String?`
  - Kotlin: `val newsSubstackUsername: String? = null`
  - C#: `public string? SubstackUsername { get; set; }`
- **`NewsModels` / `RssModels`**:
  - `isSubstackItem`: Boolean flag identifying if an item belongs to Substack (`substack.com` or `Substack Inbox`).
  - `extractSubstackInfo(from url)`: Resolves `(slug, feedUrl)` from both subdomain formats (`https://{slug}.substack.com/...`) and root profile formats (`https://substack.com/@{handle}/...`).
  - `optimizeSubstackImageUrl(url)`: Replaces low-res width clamps (`w_\d+`) with `w_1200` on `substackcdn.com` and `substack-post-media`.
  - `isSubstackTeaser(content)`: Detects whether an article is a paywalled preview (`this post is for paid subscribers`, `subscribe to unlock`, `subscription-widget-wrap`).
  - `stripSubstackTrackingAndNoise(html)`: Regex-based purifier removing subscription widgets, share popups, like footers, and tracking containers.

---

## 3. Platform Implementations

### 3.1 macOS & iOS (Swift & SwiftUI)

- **DailyCore Layer (`DailyCore`)**:
  - `AppSettings.swift`: Added `newsSubstackUsername` to `AppSettings`, coding keys, decoder, and encoder.
  - `NewsModels.swift`: Added `isSubstackItem`, `substackPublicationSlug`, `substackFeedUrl`, and `extractSubstackInfo(from:)`.
  - `FeedParser.swift`: Applied `optimizeSubstackImageUrl` during XML enclosure and thumbnail parsing.
  - `ArticleExtractor.swift`: Added `scrapeSubstackInbox()`, `extractSubstackArticle()`, `isSubstackTeaser()`, `stripSubstackTrackingAndNoise()`, and cookie validation.
  - `NewsService.swift`: Added `substackInboxFeedSource`, `subscribeToSubstackPublication()`, and `isSubscribedToSubstack()`.
- **macOS Native App (`MacOS/Daily`)**:
  - `SubstackLoginSheet.swift`: WKWebView modal with custom user agent, cookie observer for `substack.sid` / `connect.sid`, and `window._preloads.user` evaluator.
  - `FeaturesSettingsSection.swift`: Refactored into modular subviews (`MediumSetupSubSection`, `SubstackSetupSubSection`) to eliminate Swift 6 type-checker compilation timeouts.
  - `NewsArticleCard.swift`, `NewsFeedView.swift`, `NewsReaderView.swift`: Integrated `+ Subscribe` buttons and Substack Inbox feed source.
- **iOS Native App (`iOS/Daily`)**:
  - `SubstackLoginSheet.swift`: UIKit `UIViewRepresentable` WKWebView sheet with `presentationDetents([.large])`.
  - Full UI parity with macOS for article cards, reader view, and settings.
  - Verified on **iOS Simulator (SimulaPhone)** and physical **iPhone Schmitz** via `xcrun devicectl`.

### 3.2 Android (Kotlin & Jetpack Compose)

- **`core-model` & `core-database`**:
  - `AppSettings.kt`: Added `newsSubstackUsername`.
  - `NewsModels.kt`: Added Substack slug extraction and image optimization.
  - `ArticleExtractor.kt`: Added `isSubstackTeaser()`, `stripSubstackTrackingAndNoise()`, and cookie checker.
  - `NewsRepository.kt`: Added Substack Inbox feed routing, full article extraction fallback via `NewsSyncHandler`, and publication subscription persistence.
- **`app` Presentation Layer**:
  - `SubstackWebViewBridge.kt`: Headless WebKit implementation for inbox scraping and subscriber article extraction using cookie injection and evaluated JavaScript.
  - `SubstackLoginSheet.kt`: Modern Compose modal dialog embedding Android `WebView`, progress bar, and handle configuration.
  - `DailyApp.kt`: Instantiated bridge and registered sync handlers on application startup.
  - `SettingsScreen.kt`, `NewsArticleCard.kt`, `NewsFeedView.kt`, `NewsReaderSheet.kt`: Full UI integration.
  - Verified on **Android Emulator** and physical **Google Pixel 9 Pro ("Trapper")** via wireless `adb`.

### 3.3 Windows 11 (WinUI 3 & .NET 10)

- **Shared Services (`Services/RssFeedService.cs`)**:
  - Added `OptimizeSubstackImageUrl(string url)` with `Regex.Replace(url, @"w_\d+", "w_1200")`.
  - Integrated into RSS image parsing pipelines.
- **WinUI App (`WinUI/Daily.WinUI`)**:
  - `RssItemViewModel.cs`: Added `IsSubstackItem` and `CanSubscribe`.
  - `FeaturesPage.xaml` & `FeaturesPage.xaml.cs`: Added Substack Setup card, `SubstackLoginWindow` with WebView2 navigation to `https://substack.com/sign-in`, live session check, and cookie manager synchronization.
  - `RssFeedDetailPage.xaml` & `RssFeedDetailPage.xaml.cs`: Added `_substackInboxSource`, `LoadSubstackInboxAsync()` using `BackgroundWebView`, Substack noise cleanup in reader fallback, and `+ Subscribe` button for Substack publications.
  - `RssFeedWidgetControl.xaml.cs`: Integrated Substack Inbox into the desktop dashboard widget feed picker and background loader.
  - Verified natively on Parallels **Windows 11 VM (ARM64)** with 0 build errors.

---

## 4. Verification Matrix

| Platform | Verification Environment | Build Command | Status |
| :--- | :--- | :--- | :--- |
| **DailyCore** | macOS CLI / SwiftPM | `swift test --filter NewsServiceTests` | **PASSED (25/25 tests)** |
| **macOS** | Host Mac (Apple Silicon) | `xcodebuild -project MacOS/Daily.xcodeproj -scheme Daily ... build` | **BUILD SUCCEEDED** |
| **iOS Simulator** | SimulaPhone (iOS 18.2) | `xcodebuild -project iOS/Daily.xcodeproj -scheme Daily ... build` | **BUILD SUCCEEDED** |
| **iOS Device** | iPhone Schmitz | `xcrun devicectl device install app` | **DEPLOYED & VERIFIED** |
| **Android** | Gradle Daemon | `./gradlew assembleDebug` | **BUILD SUCCESSFUL** |
| **Android Device** | Pixel 9 Pro Trapper | `adb install -r app-debug.apk` | **DEPLOYED & VERIFIED** |
| **Windows 11** | Parallels VM (ARM64) | `dotnet build -c Debug -p:Platform=ARM64` | **0 Errors, 0 Regressions** |

---

## 5. Non-Regression Safeguards

1. **Ziarul Financiar (ZF)**: Preserved specialized headline and section extraction, preventing generic teaser overwrites.
2. **Recorder**: Preserved default feed configuration and audio/video link handling.
3. **Politico**: Preserved `.article__content` multi-chunk container assembly and ad-separator stripping.
4. **Republica**: Preserved short article extraction heuristic.
5. **Medium**: Maintained complete separation between Medium and Substack session cookies, Reading List scrapers, and publication subscriber channels.
