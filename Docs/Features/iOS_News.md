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

### 1.3 Fast-Path Readability Engine & Content Sanitization
Modelled after WinUI's extraction pipeline:
- **Fast-Path Reader**: Fetches full article HTML with realistic browser user-agent headers and heuristic DOM extraction (finding main `<article>` tags or scoring parent `<div>` containers by paragraph density).
- **Featured Image Deduplication**: Employs regex matching (`<img[^>]*src=["\']([^"\']+)["\'][^>]*>`) against the hero image URL. If the lead image is duplicated inside the first 800 characters of the body, it is surgically excised (including wrapping `<figure>` or `<p>` containers) to prevent redundant double headers.
- **Author Sanitization**: Cleans author strings by stripping prefix keywords ("By ", "De către ", "Author: "), stripping email/social links ("@...", "Follow on Twitter"), and eliminating boilerplate strings (e.g. "NavigationContributor", "Staff Writer").

### 1.4 Distraction-Free Liquid Glass Reader Mode
- **Interactive Full-Screen Sheet**: Opening an article launches a dedicated distraction-free reader modal sheet with dark `#1A1423` background.
- **Top Glass Toolbar**: Floating glass capsule featuring:
  - Dismiss button (`xmark`)
  - Publication favicon and source name pill
  - Interactive font size toggle (`AA`) scaling from Small (16px) to Regular (18px), Large (20px), and Extra Large (24px)
  - Quick action toggles: "Read Later" bookmark and "Favorites" star
  - Safari external link button to view the original live web page
- **Liquid Glass Web Container**: Encapsulated `WKWebView` with transparent background rendering the WinUI-style HTML/CSS template:
  - Custom fluid serif/sans typography (`-apple-system`, `SF Pro Display`, `Georgia`)
  - Glowing publication badge and author/date metadata line
  - Hero image with smooth rounded corners (`border-radius: 14px`)
  - Responsive embedded images, blockquotes, and styled typography
- **Expandable Related Stories Carousel**: Anchored to the bottom of the reader is a floating glass capsule presenting smart contextual recommendations powered by the recommendation engine.

### 1.5 Supabase-Synced "Read Later" & "Favorites"
- **Dual Offline / Cloud Persistence**:
  - Local caching in `GroupDefaults` (`dayone_read_later_articles`, `dayone_favorite_articles`) enables instant offline access without network latency.
  - Asynchronous background synchronization with Supabase table `rss_saved_articles`.
- **Deterministic GUIDs**: Generates deterministic MD5 UUIDs using `MD5(userId + ":" + articleUrl + ":" + articleType)` matching WinUI's synchronization contract.

### 1.6 Smart Article Recommendations
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
- **`DailyCore/Sources/DailyCore/Services/FeedParser.swift`**:
  - Resilient `XMLParser` delegate handling RSS 2.0, Atom, and RDF feeds with CDATA support, regex tag extraction fallback, and comprehensive HTML entity decoding.
- **`DailyCore/Sources/DailyCore/Services/WpJsonParser.swift`**:
  - JSON decoder extracting articles from WordPress REST endpoints (`/wp-json/wp/v2/posts?_embed`).
- **`DailyCore/Sources/DailyCore/Services/ArticleExtractor.swift`**:
  - Readability extractor with hero image deduplication and author cleaning.
- **`DailyCore/Sources/DailyCore/Services/SavedArticlesService.swift`**:
  - `@MainActor` singleton managing bookmarks and favorites with local caching and Supabase synchronization.
- **`DailyCore/Sources/DailyCore/Services/SmartRecommendationEngine.swift`**:
  - Keyword extraction and similarity scoring engine.
- **`DailyCore/Sources/DailyCore/Services/NewsService.swift`**:
  - Master coordinator managing feed loading, parallel All News aggregation, 15-minute caching, search filtering, and Feedly API discovery.

### 2.2 Native iOS UI (`iOS/Daily`)
- **`iOS/Daily/DesignSystem/FloatingGlassCapsule.swift`**:
  - Added `.news` tab (`newspaper.fill`) to the primary 4-tab navigation capsule.
- **`iOS/Daily/Views/News/NewsFeedView.swift`**:
  - Main news view with search bar, horizontal category filter pills, sub-tab switcher (Live Feed, Read Later, Favorites with live counter badges), feed source selector, and pull-to-refresh.
- **`iOS/Daily/Views/News/NewsArticleCard.swift`**:
  - Tactile Liquid Glass card displaying publication favicon, title, clean excerpt, thumbnail, relative time ("2m ago"), and quick action buttons.
- **`iOS/Daily/Views/News/ArticleWebView.swift`**:
  - `UIViewRepresentable` wrapping `WKWebView` with dark Liquid Glass theme injection and dynamic font size updates.
- **`iOS/Daily/Views/News/NewsReaderView.swift`**:
  - Full-screen distraction-free reader modal with glass toolbar and related articles footer.
- **`iOS/Daily/Views/News/SmartRecommendationsCarousel.swift`**:
  - Horizontal recommendation pills anchored inside the reader sheet.
- **`iOS/Daily/Views/News/NewsFeedsManagementSheet.swift`**:
  - Subscription management sheet with add/remove, custom RSS validation, and Feedly search.
- **`iOS/Daily/Views/Dashboard/DashboardView.swift`**:
  - Real-time top briefing card displaying the latest news headline with direct tap-to-navigate integration.

---

## 3. Verification & Test Suite

1. **DailyCore Unit Tests (`DailyCoreTests/NewsServiceTests.swift`)**:
   - `testRssFeedParsing`: Validated XML parsing of RSS 2.0 channel with enclosures.
   - `testAtomFeedParsing`: Validated Atom feed parsing with `<entry>` and `<summary>`.
   - `testWpJsonParsing`: Validated WordPress REST API JSON decoding and featured media extraction.
   - `testHtmlEntityDecoding`: Verified decoding of named (`&quot;`, `&mdash;`) and numeric Romanian diacritics (`&#539;`, `&#259;`).
   - `testImageDeduplication`: Verified regex stripping of duplicate hero images in body.
   - `testAuthorCleaning`: Verified removal of "By", "De către", and trailing email handles.
   - `testDeterministicSavedArticleGuid`: Validated MD5 GUID generation against expected test vectors.
   - `testSmartRecommendationEngine`: Verified keyword extraction, title/desc weighting, and stop-word filtering.
   - **Result**: 14/14 tests passing (`swift test` 100% green).

2. **Xcode Build & Verification**:
   - Clean compilation for iOS 18.0+ Simulator (`** BUILD SUCCEEDED **`).

3. **Visual & Behavioral Verification (`SimulaPhone`)**:
   - Verified 4-tab Floating Glass Capsule with `.news` tab.
   - Verified live news aggregation across Romanian (HotNews, Economica.net, Digi24) and global feeds (CNBC, BBC, Verge).
   - Verified category filter chips (Local, Markets, World, Tech, All News).
   - Verified sub-tabs: Live Feed, Read Later, and Favorites.
   - Verified distraction-free Liquid Glass reader mode with top toolbar, font size scaling, hero image rendering, and bottom related stories carousel.
