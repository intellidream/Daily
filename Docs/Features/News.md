# Feature: News Reader (RSS Feed & Article Reader)

The News Reader is a core feature that provides users with a distraction-free, fast, and personalized news consumption experience. It aggregates articles from multiple RSS/WordPress JSON sources, sanitizes and reformats them for readability, syncs user-saved items (Read Later and Favorites) cross-platform, and presents intelligent, localized recommendations.

---

## 1. Functional Specification

### 1.1 Feed Subscription & Source Management
- **Categorized News Picker**: Feeds are organized into predefined categories (e.g., Tech, Markets, World, Local) to help users browse their topics of interest.
- **Custom RSS/WP-JSON Subscriptions**: Users can subscribe to custom sources by providing a feed URL and a display name. The app automatically fetches the website favicon (using the Google Favicon API fallback) and auto-detects whether the source uses a traditional XML RSS format or a WordPress JSON API (`wp-json`).
- **Atomic Loading & Cycles**: Users can swap between active feeds, pull to refresh, or cycle through publications sequentially using cycle controls.

### 1.2 Interactive Reader View (Distraction-Free Mode)
- **Fast-Path Extraction (SmartReader)**: By default, the app uses a backend scraping and parsing algorithm (`SmartReader`) to download and parse the raw webpage content. It extracts the core article text, author, and main image, stripping away headers, sidebars, scripts, and advertisements.
- **Featured Image Deduplication**: To avoid double-rendering, the engine compares the webpage's extracted featured image with the inline body images. It aggressively cleans up and removes any duplicate inline image tags and their empty parent containers.
- **Author Sanitization**: Standardizes author credits by cleaning up web junk (like "Social Links" or "See all articles") and automatically separates multiple concatenated titles (e.g., converting "Jane DoeSenior Editor" to "Jane Doe, Senior Editor").
- **WebView2 Web Scraping Fallback**: If the fast-path parser fails to find readable content (due to JS-dependent pages or heavy dynamic rendering), the app falls back to a hidden browser automation step:
  - It loads the article URL in a web view instance.
  - Automatically runs an injected JavaScript cleanup script to strip away cookie walls, GDPR consents, newsletter popups, paywall frames, and modal overlays.
  - Polls the DOM until JS-rendered content is present, extracts the full HTML, and parses it again.
  - If parsing still fails, it renders the raw webpage in the view.

### 1.3 Saved Lists (Offline / Sync Ready)
- **Read Later**: A bookmarking stack allowing users to save articles for future reading.
- **Favorites**: A starred article collection for keeping track of long-term references.
- Both lists support toggling items from inside the reader view toolbar or from the main list.

### 1.4 Smart Recommendations
- Suggests up to 20 related articles while the user is reading.
- Uses term-frequency heuristics, category matching, and a round-robin fairness strategy to build the recommendation set (see Technical Architecture).

---

## 2. Technical Architecture & Data Model

### 2.1 Dependency Injection & Services
- `IRssFeedService` / `RssFeedService`: Handles listing available feeds, downloading XML/JSON feeds, background pre-fetching, and full-article text scraping.
- `IRssArticleService` / `RssArticleService`: Manages saved articles (Read Later and Favorites) in the local database and coordinates sync events.
- `IDatabaseService` / `DatabaseService`: Coordinates local SQLite database connections and table initializations.
- `IRenderedHtmlService` / `MauiWebViewRenderedHtmlService`: (Platform-specific) Extracts fully rendered JS content on mobile web view runtimes.

### 2.2 Data Models & Schema
The database stores user subscriptions and saved articles, which are synchronized with Supabase:

#### Local Database Schema (SQLite / Mobile Sync)
- **`LocalRssSubscription`**:
  - `Id` (Guid String)
  - `UserId` (String)
  - `Name` (String)
  - `Url` (String)
  - `Category` (String)
  - `IconUrl` (String)
  - `CreatedAt` (DateTime)
  - `IsDeleted` (Boolean)
- **`LocalSavedArticle`**:
  - `Id` (Guid String)
  - `UserId` (String)
  - `Title` (String)
  - `ArticleUrl` (String) (Primary key for uniqueness)
  - `ArticleDate` (DateTime)
  - `ImageUrl` (String)
  - `Description` (String)
  - `Author` (String)
  - `Type` (Integer: Favorite = 1, ReadLater = 2)
  - `PublicationName` (String)
  - `PublicationIconUrl` (String)
  - `CreatedAt` (DateTime)

### 2.3 Smart Recommendation Algorithm Flow
When a user opens an article, the recommendation engine (`GetSmartRecommendations(RssItem currentItem)`) executes:

```mermaid
graph TD
    A["Start: Opened Article"] --> B["Tokenize Title and Description"]
    B --> C["Filter Out Stop Words and Short Tokens"]
    C --> D["Weight Keywords: Title = 5.0, Desc = 1.0"]
    D --> E["Select Top 15 Profile Keywords"]
    E --> F["Gather Candidate Articles: Active Feed + Cache + Saved Lists"]
    F --> G["Deduplicate Candidates by URL/Title"]
    G --> H["Calculate Scores: Keyword Matches + Category Bonus +20"]
    H --> I["Sort into Matching and Fallback Pools"]
    I --> J["Round-Robin Select by Publication Name"]
    J --> K["Return 20 Recommended Articles"]
```

- **Fairness Guarantee**: The Round-Robin selection rotates through distinct publication names (e.g. taking one TechCrunch article, then one Wired article, then one VentureBeat article) to prevent a single source from filling the entire list.
- **Background Pre-fetching**: On startup, a background task (`PreFetchAllFeedsInBackground`) loops through all inactive feeds and downloads their feed items, caching them in `_allFeedsCache` so recommendation candidates are available instantly.

---

## 3. UI/UX & Styling

### 3.1 Custom Title Bar & Metadata Sync
- The reader view features a toolbar containing a back button, publication name, publication icon, and quick action buttons (Favorite/Read Later).
- In WinUI, the custom `AppTitleBar` coordinates authentication profile photos and light/dark theme toggles.

### 3.2 Dynamic Scroll Fade (WinUI)
- The smart recommendations list is a horizontally scrollable container.
- An event listener (`RecommendationsScrollViewer_ViewChanged`) calculates the position of each item relative to the scroll viewport bounds using `container.TransformToVisual(RecommendationsScrollViewer)`.
- It dynamically applies a linear opacity fade-out to items entering the left and right edges (fade zone = 36px), creating a smooth, premium glass-like visual edge transition.

---

## 4. Platform Implementation Differences (WinUI vs. MAUI / Blazor Hybrid)

| Characteristic | WinUI Implementation | MAUI / Blazor Hybrid Implementation |
| :--- | :--- | :--- |
| **Reader View Tech** | Native XAML `WebView2` Control | Blazor Hybrid DOM / Razor Markup |
| **HTML Display** | `ReaderWebView.NavigateToString(html)` with embedded styling template | `@((MarkupString)selectedItem.Content)` injected inside a `<MudPaper>` container |
| **Styles & Theme** | Dynamic XAML properties and `UpdateWebViewBackground()` which overrides default HTML bg color | Cascading MudBlazor styling themes and custom CSS variables |
| **Fallback Scraping** | Uses the desktop WebView2 browser engine, injecting Javascript scripts directly into chromium | Utilizes `IRenderedHtmlService` to orchestrate platform-native WebView elements on iOS/Android |
| **Recommendations UI** | Horizontal `ScrollViewer` + `ItemsControl` with manual scroll fade-out calculations | Standard MudBlazor list layout wrapped in a `<MudSwipeArea>` |
| **Navigation Flows** | Multi-level frame navigation inside `MainWindow.xaml` | Detail navigation service mapping URLs to Blazor components (`NavService`) |
| **Gestures** | Mouse-hover and scroll-wheel drag behaviors | Touch gestures: Swiping left-to-right on a MudSwipeArea closes the reader |

---

## 5. Desktop WebView2 Packaged MSIX & Lifecycle Requirements (WinUI)

When running the application in a packaged MSIX context (or under unpackaged distribution mode), the native XAML `WebView2` control is subject to strict security, lifecycle, and threading requirements:

### 5.1 Outbound Network Access (Internet Capability)
Because the application runs in a sandboxed container, WebView2's sandboxed Chromium processes cannot access external websites unless the manifest explicitly enables network access.
- **Requirement**: [Package.appxmanifest](file:///c:/Users/mihai/source/repos/Daily/WinUI/Daily.WinUI/Package.appxmanifest) must contain `<Capability Name="internetClient" />` to allow outbound HTTP requests and webpage rendering.

### 5.2 Single-Threaded Apartment (STA) COM Model
WebView2 and WinUI components require the calling UI thread to run in Single-Threaded Apartment (STA) mode. 
- **Gotcha**: If `[System.STAThreadAttribute]` is placed on the same line as an XML documentation comment closing tag (e.g. `/// </summary>    [System.STAThreadAttribute]`), the compiler parses it as comment text and ignores it. This starts the app's main thread in MTA mode, causing all subsequent `EnsureCoreWebView2Async` calls to fail with `System.InvalidOperationException: Cannot change thread mode after it is set` (`RPC_E_CHANGED_MODE`).
- **Requirement**: Always place the `[System.STAThreadAttribute]` attribute on its own line immediately above the `Main` entry point in [App.xaml.cs](file:///c:/Users/mihai/source/repos/Daily/WinUI/Daily.WinUI/App.xaml.cs).

### 5.3 Visual Tree / Visibility Constraint
WinUI 3's WebView2 control will refuse to initialize its underlying browser engine if the control's `Visibility` property is `Collapsed`, or if its parent container is collapsed.
- **Requirement**: Set `ReaderWebView.Visibility = Visibility.Visible;` and `ReaderWebView.Opacity = 0.0;` to place the control into the active visual tree before calling `EnsureCoreWebView2Async()`. Once initialized and loaded, transition `Opacity` to `1.0`. Avoid pre-initializing WebView2 controls during page load if they are collapsed by default.

### 5.4 Concurrent Initialization Shielding
Calling `EnsureCoreWebView2Async()` concurrently on the same WebView2 instance before the first call completes causes deadlocks, crashes, or runtime hangs.
- **Requirement**: Shield WebView2 initialization using a shared, stateful `Task` reference (`_webViewInitTask`) to ensure multiple navigations or loaded event triggers safely await the exact same task. If the initialization task enters a faulted or canceled state, reset the task reference to `null` to allow automatic retry recovery.

### 5.5 Null Core Guard & Native UI Fallback
If the client machine lacks the Evergreen WebView2 Runtime or if initialization fails, calling `NavigateToString()` on a null `CoreWebView2` will crash the application process.
- **Requirement**: Always verify `ReaderWebView.CoreWebView2 != null` before invoking `NavigateToString`. If the core is null, use a native XAML fallback (e.g., stop the progress ring and update a status `TextBlock` natively) to show a friendly error instead of crashing.

### 5.6 Parallel Recommendations Retrieval Protection
When retrieving recommendation feed items concurrently in the briefing engine or page UI, individual feed loading tasks must be wrapped in local try-catch blocks. This prevents a single network or feed-parse exception from aborting the entire parallel `Task.WhenAll` batch operations, ensuring that the remaining feeds load successfully.
