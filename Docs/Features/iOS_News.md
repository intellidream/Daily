# Feature: iOS News & Briefings (Liquid Glass Experience & Multiplatform Core)

This document details the design, architecture, and implementation of the **News & Briefings** feature for the native DayOne iOS application and its shared multiplatform foundation (`DailyCore`), adhering strictly to the WinUI 3 desktop reading experience, resilient multi-format feed ingestion, and modern tactile glassmorphism.

---

## 1. Functional Specification

### 1.1 Resilient Multi-Flavor Feed Ingestion
The news engine supports feeds across diverse digital publishing formats:
- **Standard RSS 2.0 & RSS 0.9x**: Parses `<item>`, `<title>`, `<description>`, `<link>`, `<pubDate>`, and `<content:encoded>`.
- **Atom Feeds**: Parses `<entry>`, `<title>`, `<summary>`, `<content>`, `<link rel="alternate">`, and `<published>` / `<updated>` timestamps.
- **RDF / RSS 1.0**: Handles namespace-prefixed Dublin Core metadata (`dc:date`, `dc:creator`).
- **WordPress REST API (`/wp-json/wp/v2/posts?_embed`)**: Native JSON decoding for modern WordPress sites (e.g. *Zona IT*), extracting rendered titles, excerpt summaries, HTML content, author objects, and high-resolution featured media attachments (`wp:featuredmedia`).
- **Media & Enclosure Detection**: Automatically detects and extracts hero thumbnails from `<enclosure type="image/...">`, `<media:content>`, `<media:thumbnail>`, or falls back to scraping inline `<img>` tags.
- **Robust Entity Decoding**: Decodes standard XML/HTML entities (`&quot;`, `&amp;`, `&lt;`, `&gt;`, `&apos;`, `&nbsp;`, `&mdash;`, `&rsquo;`, `&rdquo;`, `&hellip;`) as well as decimal (`&#539;`, `&#259;`) and hexadecimal numeric entities to guarantee pristine Romanian diacritics and typography.

### 1.2 Feed Categories & Parallel Aggregator ("All News")
- **Category Taxonomy**: Articles are classified across `Local` (🇷🇴 Republica, Digi24, ZF, HotNews, Biziday, Economica.net), `Markets` (CNBC, Economist, ZF), `World` (BBC, NPR, Politico, DW), `Tech` (TechCrunch, Verge, Ars Technica, Zona IT, Windows Central), and `General` (Google News).
- **Parallel Aggregator (`withTaskGroup`)**: When "All News" is selected, `NewsService` fetches all subscribed feeds concurrently with async task groups, deduplicating articles by URL/title and sorting chronologically so the user gets a consolidated real-time briefing in seconds.
- **In-Memory Caching (15 Minutes)**: To conserve cellular bandwidth and guarantee zero-latency tab switching, articles per feed are cached in memory for 15 minutes.

### 1.3 Mozilla Readability Engine & Resilient Extraction Pipeline
Modelled after WinUI's high-fidelity extraction pipeline and upgraded with official Mozilla Readability:
- **Headless Readability Parser (`HeadlessReadabilityParser`)**:
  - Employs an in-memory compiled base64 payload of Mozilla `readability.min.js` executed inside a headless `@MainActor` `WKWebView`.
  - Ingests article HTML with `baseURL: url` to automatically resolve all relative paths for images and hyperlinks across Romanian and international publications.
  - Returns a clean JSON payload `{ title, byline, content, excerpt }` parsed by official Mozilla heuristics.
  - Completely eliminates previous article truncation issues on sites like **Republica** (recovering from truncated ~1.2k marketing snippets to the complete ~33k character investigative article) and **Windows Central** (recovering from ~2.8k "up-next" teaser blocks to the complete ~29k character tech reporting body).
- **Scored Heuristic Fallback Engine**:
  - If WebKit evaluation times out or encounters restrictions, a multi-stage DOM scorer evaluates all candidate containers (`article`, `[itemprop=articleBody]`, `.article-body`, `main`, etc.).
  - Explicitly filters out ad, marketing, teaser, recirculation, and recommendation containers (`marketing`, `upnext`, `teaser`, `social`, `recirculation`, `newsletter`).
  - Scores containers by text length, paragraph count, and comma density.
- **Featured Image Deduplication**: Employs regex matching (`<img[^>]*src=["\']([^"\']+)["\'][^>]*>`) against the hero image URL. If the lead image is duplicated inside the first 800 characters of the body, it is surgically excised (including wrapping `<figure>` or `<p>` containers) to prevent redundant double headers.
- **Medium Miro CDN Optimization**: Automatically cleans and optimizes Medium CDN images (`v2/resize:fit:800/format:webp`) for crisp, high-performance display on mobile retina displays.
- **Author Sanitization**: Cleans author strings by stripping prefix keywords ("By ", "De către ", "Author: "), stripping email/social links ("@...", "Follow on Twitter"), and eliminating boilerplate strings.

### 1.4 Medium Ecosystem Integration (WinUI Parity)
- **Dedicated Settings Hub (`FeaturesSettingsSection.swift`)**:
  - "MEDIUM SETUP" card featuring live connection status badge (e.g. `Linked as @username` in emerald green vs `Not Configured`).
  - Reading list URL configuration text field (`https://medium.com/@{username}/list/reading-list`) with automatic default derivation.
  - "Login to Medium" / "Change Account" sheet trigger and safe "Disconnect" confirmation alert.
- **Medium Login Sheet (`MediumLoginSheet.swift`)**:
  - Rapid `@username` handle entry bar with immediate connection.
  - Embedded `WKWebView` pointing to `https://medium.com/m/signin` with navigation delegate monitoring redirects to automatically capture authenticated user profiles.
- **Reading List & Author Feed Subscriptions**:
  - `NewsService` exposes `mediumReadingListFeedSource` directly at the top of the feed picker menu when configured.
  - Author follow button ("Follow" / "Following") in `NewsArticleCard` and `NewsReaderView`, allowing one-tap subscription to `https://medium.com/feed/@{author}`.

### 1.5 Distraction-Free Liquid Glass Reader Mode
- **Interactive Full-Screen Sheet**: Opening an article launches a dedicated distraction-free reader modal sheet with dark `#1A1423` background.
- **Top Glass Toolbar**: Floating glass capsule featuring:
  - Dismiss button (`xmark`)
  - Publication favicon and source name pill
  - Medium Author follow badge when viewing Medium posts
  - Interactive font size toggle (`AA`) scaling from Small (16px) to Regular (18px), Large (20px), and Extra Large (24px)
  - Quick action toggles: "Read Later" bookmark and "Favorites" star
  - Safari external link button to view the original live web page
- **Liquid Glass Web Container**: Encapsulated `WKWebView` with transparent background rendering the WinUI-style HTML/CSS template:
  - Custom fluid serif/sans typography (`-apple-system`, `SF Pro Display`, `Georgia`)
  - Glowing publication badge and author/date metadata line
  - Hero image with smooth rounded corners (`border-radius: 14px`)
  - Responsive embedded images, blockquotes, and styled typography
- **Expandable Related Stories Carousel**: Anchored to the bottom of the reader is a floating glass capsule presenting smart contextual recommendations powered by the recommendation engine.

### 1.6 Supabase-Synced "Read Later" & "Favorites"
- **Dual Offline / Cloud Persistence**:
  - Local caching in `GroupDefaults` (`dayone_read_later_articles`, `dayone_favorite_articles`) enables instant offline access without network latency.
  - Asynchronous background synchronization with Supabase table `rss_saved_articles`.
- **Deterministic GUIDs**: Generates deterministic MD5 UUIDs using `MD5(userId + ":" + articleUrl + ":" + articleType)` matching WinUI's synchronization contract.

### 1.7 Smart Article Recommendations
- **TF Keyword Scoring**: Analyzes title keywords (weight 5.0) and description keywords (weight 1.0) while filtering out English and Romanian stop words ("și", "în", "la", "cu", "pentru", "este", etc.).
- **Source Diversity**: Rotates recommended articles round-robin among diverse publications so recommendations are never monopolized by a single outlet.

---

## 2. Technical Architecture & File Map

### 2.1 Multiplatform Core (`DailyCore`)
Shared between iOS and upcoming macOS apps without any UIKit dependencies:
- **`DailyCore/Sources/DailyCore/Models/NewsModels.swift`**:
  - `FeedType` (`.rss`, `.atom`, `.wpJson`)
  - `FeedCategory` (`.all`, `.local`, `.markets`, `.world`, `.tech`, `.general`)
  - `FeedSource`: Identifies feed name, category, type, and source URL.
  - `NewsArticle`: Core article entity conforming to `Identifiable`, `Codable`, and `Hashable`.
  - `SavedArticle`: Schema for saved articles with deterministic ID generation.
  - `RssSubscription`: Model for user subscriptions with order indexing.
- **`DailyCore/Sources/DailyCore/Models/AppSettings.swift`**:
  - Added `newsMediumReadingListUrl` alongside `newsMediumUsername`.
- **`DailyCore/Sources/DailyCore/Services/ReadabilityScript.swift`**:
  - In-memory compiled base64 payload of Mozilla `readability.min.js`.
- **`DailyCore/Sources/DailyCore/Services/ArticleExtractor.swift`**:
  - `HeadlessReadabilityParser` powered by WebKit + heuristic fallback DOM scorer with anti-recirculation filtering.
  - Featured image deduplication and Miro CDN image URL optimizer.
- **`DailyCore/Sources/DailyCore/Services/FeedParser.swift`**:
  - Resilient `XMLParser` delegate handling RSS 2.0, Atom, and RDF feeds with CDATA support, regex tag extraction fallback, and comprehensive HTML entity decoding.
- **`DailyCore/Sources/DailyCore/Services/WpJsonParser.swift`**:
  - JSON decoder extracting articles from WordPress REST endpoints (`/wp-json/wp/v2/posts?_embed`).
- **`DailyCore/Sources/DailyCore/Services/SavedArticlesService.swift`**:
  - `@MainActor` singleton managing bookmarks and favorites with local caching and Supabase synchronization.
- **`DailyCore/Sources/DailyCore/Services/SmartRecommendationEngine.swift`**:
  - Keyword extraction and similarity scoring engine.
- **`DailyCore/Sources/DailyCore/Services/NewsService.swift`**:
  - Master coordinator managing feed loading, parallel All News aggregation, Medium reading list integration, 15-minute caching, search filtering, and Feedly API discovery.

### 2.2 Native iOS UI (`iOS/Daily`)
- **`iOS/Daily/DesignSystem/FloatingGlassCapsule.swift`**:
  - Added `.news` tab (`newspaper.fill`) to the primary navigation capsule.
- **`iOS/Daily/Views/News/NewsFeedView.swift`**:
  - Main news view with search bar, horizontal category filter pills, sub-tab switcher, feed source selector (with Medium Reading List entry), and pull-to-refresh.
- **`iOS/Daily/Views/News/NewsArticleCard.swift`**:
  - Tactile Liquid Glass card displaying publication favicon, title, clean excerpt, thumbnail, relative time ("2m ago"), quick action buttons, and Medium author follow button.
- **`iOS/Daily/Views/News/ArticleWebView.swift`**:
  - `UIViewRepresentable` wrapping `WKWebView` with dark Liquid Glass theme injection and dynamic font size updates.
- **`iOS/Daily/Views/News/NewsReaderView.swift`**:
  - Full-screen distraction-free reader modal with glass toolbar, author follow pill, and related articles footer.
- **`iOS/Daily/Views/News/SmartRecommendationsCarousel.swift`**:
  - Horizontal recommendation pills anchored inside the reader sheet.
- **`iOS/Daily/Views/News/NewsFeedsManagementSheet.swift`**:
  - Subscription management sheet with add/remove, custom RSS validation, and Feedly search.
- **`iOS/Daily/Views/Settings/FeaturesSettingsSection.swift`**:
  - Added dedicated "MEDIUM SETUP" card with connection status, custom reading list URL input, login sheet trigger, and disconnect alert.
- **`iOS/Daily/Views/Settings/MediumLoginSheet.swift`**:
  - Dedicated sheet for Medium authentication via `@username` or embedded WebKit sign-in.
- **`iOS/Daily/Views/Dashboard/DashboardView.swift`**:
  - Real-time top briefing card displaying the latest news headline with direct tap-to-navigate integration.

---

## 3. Verification & Test Suite

1. **DailyCore Unit Tests (`DailyCoreTests/NewsServiceTests.swift` & `HabitsServiceTests.swift`)**:
   - `testRssFeedParsing`, `testAtomFeedParsing`, `testWpJsonParsing`.
   - `testHtmlEntityDecoding`: Romanian diacritics decoding.
   - `testImageDeduplication`: Verified regex stripping of duplicate hero images in body.
   - `testAuthorCleaning`: Verified removal of boilerplate and author handles.
   - `testDeterministicSavedArticleGuid`: Validated MD5 GUID generation.
   - `testSmartRecommendationEngine`: Verified keyword extraction and ranking.
   - **Result**: 32/32 tests passing across all test suites (`swift test` 100% green).

2. **Xcode Build & Verification**:
   - Clean compilation for iOS 18.0+ Simulator (`** BUILD SUCCEEDED **`).
   - Clean compilation for physical device destination (`iPhone 17,1` / arm64).

3. **Live Article Extraction Verification (`SimulaPhone`)**:
   - **Republica**: Verified full extraction of investigative articles without truncation (e.g. Florin Negruțiu PISA analysis, 32k+ characters with author image).
   - **Windows Central**: Verified full extraction of tech articles without "up-next" truncation (e.g. Sean Endicott Surface Easter egg article, 28k+ characters with device imagery).
   - **Zona IT**: Verified WordPress REST API decoding and full content rendering.
   - **Settings Hub**: Verified "MEDIUM SETUP" card rendering, status indicators, and URL binding.

4. **Physical Device Deployment (`iPhone 16 Pro - Schmitz`)**:
   - Built and code-signed with iOS Team Provisioning Profile.
   - Successfully deployed via `xcrun devicectl device install app` to `62990754-1EE9-5A95-A45E-F4A69DA6E591`.
   - Launched and running live via `xcrun devicectl device process launch`.

---

## 4. Minimalist Top Search Header, Category Dropdown Menu & Article Sharing

### 4.1 Expanding Search Header & Clean Navigation
- **Unified Search Header**: Removed the static header title and explicit Refresh button. Embedded an expanding `TextField` search bar directly in the top header between the Back button and the right actions. When focused, the search expands smoothly with spring animation, displaying a Cancel button to dismiss.
- **Native Pull-to-Refresh**: Retained smooth iOS native pull-to-refresh (`.refreshable`) on the feed scroll view, eliminating UI clutter.
- **Category Selector Menu**: Replaced horizontal category pill carousels with a discrete 36x36 glass circle button in the top right. Tapping opens a native iOS `Menu` displaying category icons, titles, and checkmarks for the active selection (`Local`, `Tech`, `Markets`, `World`, `General`).
- **Manage Feeds Action**: Positioned the feed management button (`slider.horizontal.3`) immediately adjacent to the category menu.

### 4.2 Distraction-Free Article Reader Sharing
- **Native ShareLink**: Added a 36x36 glass circular share button (`square.and.arrow.up`) in `NewsReaderView` toolbar. Tapping opens the native iOS Share Sheet to easily share the article's web URL and headline across Messages, AirDrop, Notes, and third-party apps.

### 4.3 Floating Navigation Capsule
- Added `News` back to `FloatingGlassCapsule.primaryTabs` (`.dashboard, .news, .health, .habits`), allowing instant one-tap switching between the four primary daily experiences.

---

## 5. Favorites & Read Later Synchronization, Simplified Reader Toolbar & Body Header Cleanup

### 5.1 Resilient Postgres ISO8601 Date Serialization
- **Supabase Timestamp Compatibility**: Implemented custom `init(from decoder: Decoder)` and `encode(to encoder: Encoder)` for `SavedArticle` and `RssSubscription`.
- **Microsecond Normalization**: Extended `HabitDateParser` to automatically truncate Postgres 6-digit microsecond timestamps (`.123456+00:00`) down to 3-digit ISO8601 milliseconds, eliminating decoding failures on date deserialization.
- **Eager Session Hydration Hooks**: Added automatic synchronization hooks in `AuthService` (`checkExistingSession`, Google Sign-In, and Apple Sign-In) and inside `NewsFeedView.swift` (`.task { await savedService.syncWithSupabase() }`), ensuring saved articles and favorites are immediately populated on launch or tab appearance.
- **Deterministic Lowercase UUIDs**: Standardized deterministic MD5 GUIDs to lowercase UUID strings to guarantee 100% parity across WinUI, iOS, and Postgres UUID constraints.

### 5.2 Distraction-Free Reader Toolbar Redesign
- **Prominent Primary Actions**: Retained only the **Read Later** bookmark button (`bookmark` / `bookmark.fill`) and **Favorite** star button (`star` / `star.fill`) directly visible in the top toolbar.
- **Rightmost Expandable Menu (`ellipsis.circle`)**: Collapsed all secondary actions into a single 32x32 glass circular menu button on the far right:
  - **Share Article**: Native iOS `ShareLink`.
  - **Open in Safari**: Direct external link button.
  - **Text Size Submenu**: Discrete sizing options (Small, Default, Large, Extra Large).
  - **Medium Author Follow**: Quick one-tap author subscription when reading Medium stories.
- **Horizontal Scrolling Publication Title**: Wrapped the top publication icon and title in a horizontal `ScrollView` between the dismiss button and action buttons, ensuring long publication names scroll smoothly without truncation, ellipses, or pushing toolbar action buttons off-screen.

### 5.3 Article Body Publication Header Cleanup
- **Body De-duplication**: Excised the redundant `<div class='publication-header'>` and its associated CSS from `ArticleWebView.swift`. The article now opens directly with the headline (`h1.title`), author/timestamp metadata, and content body, keeping branding exclusively within the top navigation bar.

### 5.4 Card Interaction Reliability
- **Touch Collision Prevention**: Refactored `NewsArticleCard` from a wrapping `Button` to a `.contentShape(Rectangle()).onTapGesture { onTap() }` container, allowing child interactive buttons (Read Later, Favorite, Author Follow, and Share) to receive taps with haptics and spring animations without inadvertently opening the article reader.

### 5.5 Dashboard Widget Priority & Layout Repositioning
- **News Widget Elevation**: Moved the Live News Feed Widget Card directly beneath `WeatherDashboardCard` on the main `DashboardView`, giving real-time headlines top priority below weather conditions.
- **Eager Feed Loading**: Updated the `.task` lifecycle hook in `DashboardView` to eagerly fetch headlines alongside weather, health vitals, and habits on app startup.



