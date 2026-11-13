# News Perspectives, Blindspots, Source Transparency & Media Diet Architecture

**Date:** November 14, 2026  
**Status:** Implemented & Live-Verified Across Supabase, `DailyCore`, `macOS`, `iOS` (+ Foldable & Physical iPhone), `Android` (+ Foldable & Physical Pixel 9 Pro), and `Windows 11 WinUI 3` (+ `Phi-Silica NPU`)  
**Verification Matrix:**
- **Canonical Media Intelligence Seed Catalog:** `209` verified international, European, and Romanian publications (`101.3 KB` embedded JSON across Swift, Kotlin, and .NET 10) with 5-step editorial bias (`Left`, `Lean Left`, `Center`, `Lean Right`, `Right`, plus `Independent`), European/Romanian contextual descriptors (`biasContext`), 5-tier factuality scores, ownership categories, and funding transparency summaries.
- **`DailyCore` (Swift 6):** `swift test --package-path DailyCore --filter "NewsPerspectivesTests|NewsServiceTests"` — **30/30 passed (0 failures)**.
- **`macOS` Native (`MacOS/Daily`):** `xcodebuild -project MacOS/Daily.xcodeproj -scheme Daily -configuration Debug -destination 'platform=macOS' build` with atomic `Apple Development` (`7LZ9ZT2Z5B`) signing — **`** BUILD SUCCEEDED **`**, verified live on host Mac.
- **`iOS` + Foldable + Physical Hardware (`iOS/Daily`):** Simulator & Device builds — **`** BUILD SUCCEEDED **`**, verified live on **`Simula Phone`**, **`SimulaDuo`** (`63% / 37%` foldable split), and installed on physical **iPhone ("Schmitz")** (`databaseSequenceNumber: 5980`).
- **`Android` + Foldable + Physical Hardware (`Android/`):** `:core-model:testDebugUnitTest` (**38/38 passed**) & `:app:assembleDebug` (**`BUILD SUCCESSFUL`**), verified live on **`Medium_Phone_API_36.1`** and physical **Google Pixel 9 Pro ("Trapper")** (`PID 3296`, zero crashes), with adaptive `62% / 38%` foldable split ready for **Samsung Galaxy Z Fold 8 ("RADAR")**.
- **`Windows 11` (`WinUI 3` ARM64 + `Phi-Silica NPU`):** `dotnet build WinUI\Daily.WinUI\Daily.WinUI.csproj -c Debug -p:Platform=ARM64` — **`0 Error(s)`**, MSIX registered (`5E79C9CD-7CAD-4C34-8223-D6A8F1E74763_1.1.0.0_arm64__1z32rh13vfry6`), verified running live (`Daily.WinUI` `Responding = True` + `Daily.WidgetsHost` `Responding = True`).
- **Smartwatches (`watchOS` & `Wear OS`):** Intentionally untouched (`0` CPU/RAM/network impact on wrist per Smartwatch Performance & Battery Policy).

---

## 1. Executive Summary & Design Principles

**Perspectives** brings Ground News–caliber media intelligence natively into the **Daily** News ecosystem while preserving zero-regression feed loading, 120Hz scrolling fluidity, and strict Supabase storage/egress discipline:

1. **Universal 5-Step Bias Axis + European & Romanian Context:**
   - Visual bars use the universal 5-step spectrum (`Left` / `Lean Left` / `Center` / `Lean Right` / `Right` + `Independent` for Substack/Medium creators), enriched inside **Source Transparency** popovers/sheets/flyouts with calibrated European and Romanian labels (`biasContext`, e.g., *Civic Reformist*, *Investigative Non-Profit*, *Pro-Market Financial*, *Public Service Media*).
2. **Variant A ("Sleek Minimal") Card Density:**
   - Standard single-source cards display only an ultra-discreet micro-pill next to the publication (`C · High`, `IND · Mostly`) plus non-standard framing badges (`Opinion`, `Investigation`, `Analysis`, `Sensational`) when applicable.
   - The colored **Bias Spectrum Bar**, **`N sources · Perspectives →`** action pill, and **`Left/Right Blindspot`** badges appear **only** when a story is covered by $\ge 2$ distinct publications (`cluster.hasMultipleSources`).
3. **Zero-LLM Deterministic Bilingual Clustering (`< 8 ms`):**
   - `StoryClusterEngine` groups English and Romanian articles covering the same underlying event within a 54-hour window using institutional phrase normalization (`European Central Bank` / `Banca Centrală Europeană` $\rightarrow$ `ECB`), decimal rate unification (`2.25%` / `2,25%`), diacritic-folded entity extraction, cross-lingual synonyms, Dice/Jaccard similarity against cluster leads, and native unpacking of Google News RSS `<ol><li>` multi-publisher clusters.
4. **On-Demand Cross-Spectrum Discovery & Multi-Tier Framing Synthesis:**
   - Background feed loading incurs **zero** external search churn. Opening **Perspectives** or clicking **Expand Spectrum** queries `Google News RSS Search (when:3d)` with a polite `6s` rate-limited `GDELT DOC 2.0` fallback to pull 15–25 cross-spectrum outlets.
   - Framing comparison cascades cleanly through: **(0)** shared 72h Supabase `news_perspective_cache` $\rightarrow$ **(1)** `Gemini 2.5 Flash` structured JSON $\rightarrow$ **(2)** on-device **`Apple FoundationModels`** (`macOS`/`iOS`) or **`Qualcomm Hexagon Phi-Silica NPU` / Local GGUF** (`Windows 11`) $\rightarrow$ **(3)** instant `< 1 ms` deterministic headline/framing synthesis.

---

## 2. Supabase Cloud Schema & Storage/Egress Guardrails

Migration: `supabase/migrations/20261114000001_perspectives_media_intelligence.sql`

- **Zero Raw RSS Storage & Zero New Realtime Channels:** Raw RSS items and story clusters are never stored in PostgreSQL, and none of the 3 tables are added to `supabase_realtime`.
- **`public.media_outlet_profiles`:** Global read-only override catalog synced via a 24-hour `updated_at > watermark` delta query (`0 B/day` egress when unchanged).
- **`public.news_perspective_cache`:** Ephemeral 72-hour shared AI framing cache keyed by deterministic SHA-256 `cluster_hash`, automatically purged hourly by `pg_cron` (`purge_expired_news_perspective_cache`) and written with `Prefer: return=minimal`.
- **`public.news_reading_stats`:** Aggregated **Media Diet** counters storing strictly **1 row per user per month** (`PRIMARY KEY (user_id, period_month)`, ~`350 bytes/month`, ~`4.2 KB/year`), synced via 60-second debounced `Prefer: return=minimal` upserts.

---

## 3. Platform-by-Platform File Manifest

### A. Canonical Seed Catalog (`209` Outlets)
- `DailyCore/Sources/DailyCore/Resources/News/media_intelligence_seed.json`
- `Android/core-model/src/main/resources/media_intelligence_seed.json`
- `Android/app/src/main/assets/news/media_intelligence_seed.json`
- `Models/Resources/media_intelligence_seed.json`

### B. `DailyCore` (Swift 6)
- `DailyCore/Sources/DailyCore/Models/NewsIntelligenceModels.swift`
- `DailyCore/Sources/DailyCore/Models/NewsModels.swift`
- `DailyCore/Sources/DailyCore/Services/FeedParser.swift`
- `DailyCore/Sources/DailyCore/Services/MediaIntelligenceRegistry.swift`
- `DailyCore/Sources/DailyCore/Services/ArticleFramingAnalyzer.swift`
- `DailyCore/Sources/DailyCore/Services/StoryClusterEngine.swift`
- `DailyCore/Sources/DailyCore/Services/NewsPerspectiveService.swift`
- `DailyCore/Sources/DailyCore/Services/MediaDietStore.swift`
- `DailyCore/Sources/DailyCore/Services/NewsService.swift`
- `DailyCore/Tests/DailyCoreTests/NewsPerspectivesTests.swift` (`30/30` tests passing)

### C. `macOS` (`MacOS/Daily`) & `iOS` (`iOS/Daily`)
- `MacOS/Daily/Views/News/` & `iOS/Daily/Views/News/`:
  - `BiasSpectrumBar.swift`
  - `SourceTransparencyPopover.swift`
  - `PerspectivesComparisonPane.swift`
  - `MediaDietSheet.swift`
  - `NewsArticleCard.swift`, `NewsFeedView.swift`, `NewsReaderView.swift` (`⌘⇧P` inspector on macOS; adaptive `63% / 37%` split on `SimulaDuo` foldable and `.large` sheet on compact iPhones).

### D. `Android` (`Android/`)
- `:core-model`: `NewsIntelligenceModels.kt`, `MediaIntelligenceRegistry.kt`, `ArticleFramingAnalyzer.kt`, `StoryClusterEngine.kt`, `FeedParser.kt`, `NewsModels.kt`, `NewsPerspectivesTest.kt` (`38/38` JUnit tests passing).
- `:core-network` & `:core-database`: `NewsRemoteService.kt`, `NewsRepository.kt`.
- `:app`: `BiasSpectrumBar.kt`, `SourceTransparencySheet.kt`, `PerspectivesComparisonSheet.kt`, `MediaDietSheet.kt`, `NewsArticleCard.kt`, `NewsFeedView.kt`, `NewsReaderSheet.kt`, `DailyApp.kt` (120Hz `remember` memoization + `62% / 38%` foldable split).

### E. `Windows 11` (`WinUI 3` + Shared C# Core)
- `Models/NewsIntelligenceModels.cs`, `Models/RssModels.cs`
- `Services/MediaIntelligenceRegistry.cs`, `Services/StoryClusterEngine.cs`, `Services/RssFeedService.cs`
- `WinUI/Daily.WinUI/Services/NewsPerspectiveService.cs` (`Gemini 2.5 Flash` + `Phi-Silica NPU` via `ISmartIntelligenceService` + deterministic lens)
- `WinUI/Daily.WinUI/ViewModels/RssItemViewModel.cs`
- `WinUI/Daily.WinUI/Views/RssFeedDetailPage.xaml` & `RssFeedDetailPage.xaml.cs` (`Perspectives` Pivot tab, `Media Diet` dialog, `Source Transparency` flyout, and `Ctrl+Shift+P` side-by-side Reader comparison pane).
