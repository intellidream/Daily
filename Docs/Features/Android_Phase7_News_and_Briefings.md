# Android Phase 7: News, Feed Aggregation, Distraction-Free Reader & Medium Integration

## 1. Overview
Phase 7 delivers complete native Android parity for the **News & Briefings** ecosystem, matching 100% of the iOS `DailyCore` News architecture, multi-format feed aggregation (RSS 2.0, Atom, WordPress REST WP-JSON v2), distraction-free readability extraction, smart TF-IDF recommendation engine, local-first Room persistence (`synced_at` dirty tracking), and Medium public reading list synchronization.

---

## 2. Architecture & Domain Models (`core-model/com.intellidream.daily.model`)

### 2.1 Domain Models (`NewsModels.kt`)
- **`FeedCategory`**:
  - `All` (`Feed` icon)
  - `Local` (`Map` icon)
  - `Markets` (`TrendingUp` icon)
  - `World` (`Public` icon)
  - `Tech` (`Memory` / `Code` icon)
  - `Science` (`RocketLaunch` icon)
  - Includes `iconName` string mapping for Compose Material Icons rendering.
- **`FeedType`**:
  - `Rss`
  - `Atom`
  - `WpJson` (WordPress REST API v2 `/wp-json/wp/v2/posts?per_page=20&_embed`)
- **`FeedSource`**:
  - Encapsulates feed source metadata: `id`, `name`, `url`, `iconUrl`, `type`, `category`, `isEnabled`, `displayOrder`.
- **`NewsArticle`**:
  - Core domain model containing `id`, `title`, `link`, `publishDate`, `imageUrl`, `description`, `content`, `author`, `publicationName`, `publicationIconUrl`, `category`, and computed `mediumUsername`.
  - Helper functions: `extractMediumUsername(article)` and `optimizeMediumImageUrl(url)`.
- **`SavedArticleType`**:
  - `ReadLater`
  - `Favorite`
- **`SavedArticle`**:
  - User-saved article item containing `id`, `articleLink`, `articleTitle`, `imageUrl`, `description`, `author`, `publicationName`, `publicationIconUrl`, `articleType`, `articleDate`, `createdAt`, `updatedAt`, `isDeleted`.

---

## 3. Feed Parsers & Content Extraction

### 3.1 RSS & Atom XML Parser (`FeedParser.kt`)
- Pure Kotlin implementation using `XmlPullParser`.
- Resolves:
  - `<item>` and `<entry>` elements.
  - Channel logo and icon fallbacks (`<image><url>`, `<icon>`, `<logo>`).
  - Atom links (`<link href="..." rel="alternate"/>` vs `<link rel="enclosure"/>`).
  - Media thumbnails (`<media:content>`, `<media:thumbnail>`).
  - Atom author hierarchies (`<author><name>...</name></author>`).
  - HTML entity decoding (`&amp;`, `&quot;`, `&#39;`, `&lt;`, `&gt;`).
  - RFC 822 / RFC 1123, ISO 8601, and Unix timestamp parsing across locales.

### 3.2 WordPress REST JSON Parser (`WpJsonParser.kt`)
- Uses `kotlinx.serialization.json` for pure multiplatform/JVM unit test compatibility.
- Extracts post `id`, `link`, `title.rendered`, `date_gmt`, `excerpt.rendered`, `content.rendered`.
- Resolves featured media thumbnails from embedded objects (`_embedded["wp:featuredmedia"][0]["source_url"]`).
- Resolves author display names from embedded objects (`_embedded["author"][0]["name"]`).

### 3.3 Distraction-Free Article Extractor (`ArticleExtractor.kt`)
- Extracts clean readability content from raw web page HTML using `Regex`:
  - Strips scripts, styles, iframes, ads, navigation, sidebars, and comments.
  - Removes tracking and layout noise.
  - Scores candidate content containers by paragraph density, punctuation, and length.
  - Extracts OpenGraph and Twitter Card metadata (`og:image`, `og:title`, `og:description`).

### 3.4 Smart Recommendation Engine (`SmartRecommendationEngine.kt`)
- Content-based TF-IDF and term-overlap recommendation algorithm:
  - Computes word frequency vectors for current article title and excerpt.
  - Filters stop-words (English and Romanian).
  - Calculates cosine similarity against candidate articles in the local cache.
  - Generates real-time top-8 related stories ranked by score.

---

## 4. Local-First Room SQLite Database (`core-database`)

### 4.1 Schema Version 4 & Entities
- **`FeedSourceEntity`**:
  - Primary Key: `id: String`
  - Columns: `name`, `url`, `icon_url`, `type`, `category`, `is_enabled`, `display_order`, `synced_at`
- **`SavedArticleEntity`**:
  - Primary Key: `id: String`
  - Indexes on `article_link` and `article_type` for sub-millisecond tab filtering.
  - Columns: `article_link`, `article_title`, `image_url`, `description`, `author`, `publication_name`, `publication_icon_url`, `article_type`, `article_date`, `created_at`, `updated_at`, `is_deleted`, `synced_at`

### 4.2 Repository Pattern (`NewsRepository.kt`)
- Reactive StateFlow: `articles`, `savedArticles`, `feeds`, `isLoading`, `errorMessage`.
- Default feeds pre-seeded across 4 categories:
  - **Local**: Republica, Digi24, Ziarul Financiar, HotNews, Biziday, Economica.net
  - **Markets**: CNBC, The Economist
  - **World**: BBC News, NPR, Politico Europe, Deutsche Welle, Google News
  - **Tech**: TechCrunch, The Verge, Ars Technica, Zona IT (WP-JSON), Windows Central
- Medium Reading List & Subscriptions:
  - `mediumReadingListFeedSource(username, customUrl)`
  - `isSubscribedToMediumAuthor(username)`
  - `subscribeToMediumAuthor(username, authorName)`
  - `unsubscribeFromMediumAuthor(username)`
- Dual-way Supabase Sync:
  - Pushes pending local additions/deletions with dirty tracking (`synced_at = 0`).
  - Pulls cloud updates from `user_saved_articles` and `user_custom_feeds`.

---

## 5. UI Presentation (`app/src/main/java/com/intellidream/daily/presentation/news`)

### 5.1 NewsFeedView (`NewsFeedView.kt`)
- **Top Bar**: Search bar with animated expansion, category selector dropdown with category icons, and Medium sync pill.
- **Pill Tab Selector**: "Live Feed", "Read Later (count)", "Favorites (count)".
- **Source Filter**: Interactive dropdown filtering by individual publication source.
- **Pull-To-Refresh**: Integrated Material 3 `PullToRefreshContainer` with haptic feedback and cyan progress spinner.
- **Adaptive Grid**: Optimized for 120Hz smooth scrolling on modern AMOLED displays.

### 5.2 NewsArticleCard (`NewsArticleCard.kt`)
- Liquid Glass styling with prominent border and elevation.
- Category badge with emoji, publication name, publication icon, relative timestamp.
- Hero thumbnail with 16:9 aspect ratio or compact end-thumbnail layout.
- Medium author chip with one-tap follow/unfollow toggle.
- Action buttons: Read Later bookmark toggle, Favorite star toggle, native Android Share intent.

### 5.3 NewsReaderSheet (`NewsReaderSheet.kt`)
- Full-screen modal distraction-free reader dialog.
- Top Glass Toolbar: Close button, source name, Read Later toggle, Favorite toggle, Options menu (Share, Open in Browser, Text Size submenu: Small, Default, Large, Extra Large, Medium Follow).
- Distraction-Free Article View: Styled HTML rendering with custom typography, clean dark/light mode CSS, and responsive layout.
- Floating Bottom Recommendations Bar: Collapsible chip list of AI/TF-IDF related stories from `SmartRecommendationEngine`.

### 5.4 Settings Integration (`SettingsScreen.kt`)
- **News & Briefings Settings Card**:
  - Auto-Refresh on Startup switch
  - Show Article Images switch
  - Medium Setup Card: Status pill (`• @username` or `Not Configured`), Reading List URL customizer, Change Account dialog, and Disconnect button.

---

## 6. Verification & Hardware Deployment

### 6.1 Automated Unit Tests
- `core-model/src/test/java/com/intellidream/daily/model/NewsParsersTest.kt`:
  - `testRssFeedParsing()`: PASSED
  - `testAtomFeedParsing()`: PASSED
  - `testWpJsonParser()`: PASSED
  - `testMediumUsernameExtraction()`: PASSED
  - `testArticleExtractorHtmlStripping()`: PASSED
  - `testSmartRecommendationEngine()`: PASSED
- Total: 6/6 tests passed.

### 6.2 Target Devices
1. **Android Phone Emulator** (`Medium_Phone_API_36.1` / `emulator-5558`):
   - Verified live feed rendering, search expansion, reader sheet typography, bookmark/favorite state persistence, and Medium login dialog.
2. **Google Pixel 9 Pro** (`adb-48231FDAP0011V-Ma9KPE._adb-tls-connect._tcp` / `caiman`):
   - Streamed install succeeded (`Success`).
   - App running live in background with 0 crashes (`PID 31842`).
3. **Samsung Galaxy S25 Edge**:
   - Ready for deployment as soon as device is connected via USB/WiFi ADB.
