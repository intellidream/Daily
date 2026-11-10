# Prism (`daily://prism`) — Assisted Web Capture & AI Studio Architecture

**Date:** November 10, 2026  
**Status:** Implemented & Live-Verified Across Supabase, `DailyCore`, `macOS`, `iOS` (+ Foldable & Share Extension), `Android` (+ Foldable & Share Target), and `Windows 11 WinUI 3` (+ `WebView2` & Hardware NPU)  
**Verification Matrix:**
- **Supabase Cloud (`akkfouifxztnfwwiclwg`):** Migration `20261110000001_prism_web_studio.sql` applied live (`HTTP 201`), verified `prism_clips` (`rls=true`), `prism_pinned_sites` (`rls=true`), private bucket `prism-clips` (`public=false`), 12 RLS policies, `updated_at` triggers, and `supabase_realtime` publication.
- **`DailyCore` (Swift 6):** `swift test --filter PrismTests` — **5/5 passed (0 failures)**.
- **`macOS` Native:** `xcodebuild -project MacOS/Daily.xcodeproj -scheme Daily -configuration Debug -destination 'platform=macOS' build` — **`** BUILD SUCCEEDED **`**, verified live at **`0.0%` idle CPU** over 65+ minutes.
- **`iOS` + Foldable + Physical Hardware:** `xcodebuild` Simulator & Device (`Daily.app` + `DailyShareExtension.appex`) — **`** BUILD SUCCEEDED **`**, verified live on **`Simula Phone`**, **`SimulaDuo`**, and physical **iPhone 16 Pro ("Schmitz")** (`-startTabPrism`).
- **`Android` + Foldable:** `:core-model:testDebugUnitTest` & `assembleDebug` — **`BUILD SUCCESSFUL`**, verified live on **`Medium_Phone_API_36.1`** (compact Bottom Thumb Omnibox + `+RSS` auto-sniffing + `Intent.ACTION_SEND` Share Sheet) and unfolded **Foldable Dual-Pane** (`2208×1840`).
- **`Windows 11` (`WinUI 3` ARM64):** `dotnet build -c Debug -p:Platform=ARM64` — **`0 Error(s)`**, `Daily.Prism.Tests` — **6/6 passed**, MSIX registered (`Add-AppxPackage -Register`), launched live into `65% / 35%` Research Split with live Supabase Vault hydration (`Vault (10)`).

---

## 1. Executive Summary

**Prism** (`daily://prism`) introduces a sleek, safe, native Assisted Web Capture & AI Research Studio integrated natively into the **DayOne / Daily** ecosystem:

1. **Persistent Login Cache Shared with `News`:**
   - Reuses the persistent default `WKWebsiteDataStore` (`macOS` / `iOS`), `CookieManager` (`Android`), and `%LocalAppData%\Daily.WinUI\WebView2` profile (`Windows 11`), sharing authenticated sessions seamlessly with `News` (Medium, Substack, GitHub, X, Google) plus dedicated OAuth SSO popup delegation and 1-tap ephemeral **InPrivate / Private Tab** browsing.
2. **Single-Active-Engine Tab Hibernation (`0.0%` Idle CPU):**
   - Supports cloud-synced **Pinned Speed Dial** sites plus up to 8 open tabs while keeping **at most 1 live WebView** mounted in RAM at any time (`0.0%` idle background CPU verified on `macOS` and `Windows 11`).
3. **Prism Shield (Zero-Overhead Tracker & Ad Blocker):**
   - Built-in deterministic tracker/ad filter (`WKContentRuleList` on Apple platforms, `WebViewClient.shouldInterceptRequest` on Android, `CoreWebView2.WebResourceRequested` on WinUI 3) with 1-tap per-domain toggle.
4. **Dedicated Prism Vault + Ecosystem Bridges:**
   - Captures **Links**, **Quotes** (via floating text-selection pill), **Images** (long-press / right-click context menu + interactive **Viewport Region Crop** compressed to max 1600px JPEG ~80–180 KB), and **AI Notes**, synced via Supabase Realtime + Lean `updated_at` watermarks, with 1-tap bridges to **`TagDoS` (`#prism`)** and **`News` Read Later / RSS Subscriptions**.
5. **Prism Co-Pilot (Cloud + On-Device NPU + Offline Fallback):**
   - 4 instant 1-tap actions (`TL;DR Summary`, `Tasks → TagDoS`, `Key Facts & Numbers`, `Explain Selection`) + custom contextual Q&A powered by `gemini-2.5-flash`, **Qualcomm Hexagon Phi Silica NPU / Local AI** on Windows 11 (`ISmartIntelligenceService`), and zero-latency offline extractive synthesis.
6. **Adaptive Form-Factor Ergonomics:**
   - **Compact Phones (`Simula Phone`, iPhone 16 Pro `Schmitz`, `Medium_Phone_API_36.1`, `Trapper`):** Auto-collapsing Bottom Liquid Glass Thumb Omnibox + `.medium`/`.large` Studio bottom sheet.
   - **Foldables (`SimulaDuo`, Galaxy Z Fold 8 `RADAR`) & Desktop (`macOS` `⌘9`, `WinUI 3` `Ctrl+0`):** Dual-Pane Detail Hub + 1-tap **`65% / 35%` Full Research Split** + Desktop **Pop-Out Research Window**.
   - **Smartwatches (`watchOS` / `Wear OS`):** Intentionally untouched (`0` WebView footprint on wrist per Smartwatch Battery Policy; tasks bridged to TagDoS sync automatically to watches).

---

## 2. Supabase Cloud Schema & Storage (`20261110000001_prism_web_studio.sql`)

- **`public.prism_clips`:**
  - `id UUID PRIMARY KEY`, `user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE`, `clip_type TEXT CHECK IN ('link','quote','image','ai_summary')`, `title`, `source_url`, `domain`, `content_text`, `user_note`, `tags TEXT[]`, `preview_image_url`, `storage_path`, `image_width`, `image_height`, `is_favorite`, `is_deleted`, `tagdos_note_id`, `created_at`, `updated_at`.
  - Strict `auth.uid() = user_id` RLS policies (`SELECT`, `INSERT`, `UPDATE`, `DELETE`), composite `(user_id, updated_at DESC)` + GIN `tags` indexes, `updated_at` trigger, and `supabase_realtime` publication.
- **`public.prism_pinned_sites`:**
  - Deterministic UUID v5 per `(user_id, normalized_url)` across all 4 platforms to prevent duplicate starter/pinned Speed Dial entries, with full RLS and `supabase_realtime` publication.
- **Private Storage Bucket `prism-clips`:**
  - `public = false`, `5 MB` file size limit, `image/jpeg`, `image/png`, `image/webp` MIME enforcement, and `storage.foldername(name)[1] = auth.uid()::text` RLS policies.

---

## 3. Platform-by-Platform Architecture

### A. `DailyCore` (Swift 6)
- `DailyCore/Sources/DailyCore/Models/PrismModels.swift`: Domain & Codable models, deterministic UUID v5 generator, Omnibox URL/search resolver, and `PrismShieldRules` `WKContentRuleList` JSON builder.
- `DailyCore/Sources/DailyCore/Services/PrismAttachmentManager.swift`: Local cache + max-1600px JPEG compression + authenticated Supabase Storage upload/download.
- `DailyCore/Sources/DailyCore/Services/PrismWebScripts.swift`: JS observer for text selection coordinates, `<img>` context/long-press candidates, RSS `<link rel="alternate">` + Substack `/feed` auto-sniffing, and DOM article extraction.
- `DailyCore/Sources/DailyCore/Services/PrismCoPilotService.swift`: `gemini-2.5-flash` structured JSON synthesis + deterministic offline extractive fallback.
- `DailyCore/Sources/DailyCore/Services/PrismStore.swift`: `@MainActor ObservableObject` managing Single-Active-Engine tab hibernation, Vault CRUD, Lean `updated_at` watermark sync, Realtime channels, and `TagDoS` / `News` bridges.
- `DailyCore/Tests/DailyCoreTests/PrismTests.swift`: 5/5 Swift Testing unit tests passing.

### B. `macOS` Native (`MacOS/`)
- `MacOS/Daily/Views/Prism/`: `PrismWebEngineModel.swift`, `PrismMainView.swift`, `PrismSideStudioPane.swift`, `PrismWindowManager.swift`.
- `MacOS/Daily/Views/Dashboard/PrismDashboardCard.swift`: Small, Wide, Tall, and Large Liquid Glass Dashboard widget variants.
- Integrated into `FloatingGlassCapsule` & Collapsible Sidebar (`⌘9`), `MenuBarCompanionView` quick-jump, and `NewsReaderView` / `ArticleWebView` link routing.

### C. `iOS` + Foldable + Share Extension (`iOS/`)
- `iOS/Daily/Views/Prism/`: `PrismWebEngineModel.swift`, `PrismMainView.swift` (Bottom Liquid Glass Thumb Omnibox on compact iPhones + `65% / 35%` Research Split on `SimulaDuo`), `PrismSideStudioPane.swift`.
- `iOS/DailyShare/`: `ShareViewController.swift`, `Info.plist` (`DailyShareExtension.appex` target embedded & signed for physical iPhone **Schmitz**).

### D. `Android` + Foldable (`Android/`)
- `core-model`: `PrismModels.kt` + JUnit suite `PrismModelsTest.kt`.
- `core-database`: `PrismEntities.kt`, `PrismDao.kt`, `DailyDatabase.kt` (`version = 10` with non-destructive `MIGRATION_9_10`), `PrismRepository.kt` (IO-dispatched cold-start zero-stall Room flows + max-1600px JPEG scaling).
- `core-network`: `PrismRemoteService.kt` (lazy Ktor CIO Storage client + PostgREST watermark sync + Gemini Co-Pilot).
- `app`: `PrismMainView.kt`, `PrismDashboardCard.kt`, `Intent.ACTION_SEND` Share Sheet target (`text/plain` & `image/*`), Dual-Pane + `OpenInFull` Research Split, and `NewsReaderSheet` / `TagdosQuickNotesView` Prism link bridges.

### E. `Windows 11` (`WinUI 3` + `WebView2` + Hardware NPU)
- `Models/PrismModels.cs` + `Tests/Daily.Prism.Tests/PrismModelsTests.cs` (6/6 xUnit tests passing; `Newtonsoft.Json` `BaseModel` PostgREST entities + `SQLite` entities).
- `WinUI/Daily.WinUI/Services/IPrismService.cs` & `PrismService.cs`: SQLite + Supabase watermark sync (`ReturnType.Minimal`), `Windows.Graphics.Imaging` max-1600px JPEG encoder, and 3-tier Co-Pilot (`Gemini 2.5 Flash` → `ISmartIntelligenceService` **`PhiSilicaNpuEngine` / Local AI** → deterministic offline fallback).
- `WinUI/Daily.WinUI/Views/PrismDetailPage.xaml(.cs)` & `Controls/PrismWidgetControl.xaml(.cs)`: Single-flight `EnsureCoreWebView2Async` sharing `%LocalAppData%\Daily.WinUI\WebView2` cookies with `News`, native `IsInPrivateModeEnabled` controller for Private tabs, `WebResourceRequested` Prism Shield, right-click `"Save Image to Prism Vault"` context menu item, `CapturePreviewAsync` interactive Region Crop, `Ctrl+0` Sidebar/Capsule shortcut, Taskbar Glance card, and Pop-Out Research Window.

### Supabase Ingress & Egress Sync Contract Update (macOS & iOS)
- **Supabase Swift Overload Resolution Fix**: Removed `: PostgrestResponse<Data>` type annotation on PostgREST queries in `PrismStore.swift`. `execute<T: Decodable>` coerced Foundation `Data` expecting a base64 string, failing on JSON arrays. Using untyped `execute()` returning `PostgrestResponse<Void>` provides raw `res.data` for standard ISO-8601 JSON decoding.
- **Eager Lifecycle Sync Triggers**: Added `PrismStore.shared.syncWithSupabase()` to `AuthService` session hydration/login callbacks, `DailyMacOSApp.init()` eager startup sequence, `RootView.swift` `⌘R` multi-service refresh, `PrismMainView` `.onAppear`, and `PrismSideStudioPane` `.onAppear` with manual `arrow.clockwise` refresh button and realtime sync indicator.
