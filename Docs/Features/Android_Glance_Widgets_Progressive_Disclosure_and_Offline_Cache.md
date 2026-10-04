# Android Glance Widgets Progressive Disclosure, Offline-First Room Architecture & Ergonomic Parity

## Overview
This document details the architectural refinements, performance enhancements, and progressive disclosure hierarchy implemented in the native Android app (`com.intellidream.daily`). This release brings the Android app and its Jetpack Glance widgets to 1:1 visual, functional, and ergonomic parity with the iOS gold standard while maintaining strictly zero regressions and zero touches to iOS files.

---

## 1. Jetpack Glance Progressive Disclosure Hierarchy (1:1 iOS Parity)

Previously, Android Glance widgets exhibited layout clipping and an inverted responsive hierarchy:
- In small (2x2) mode, widgets lacked proper insets, pushing action buttons and telemetry off the bottom edge or crowding too much secondary information into limited space.
- In medium (4x2) mode, widgets were incorrectly matching the large layout threshold (`height >= 180.dp`), cramming vertically-stacked 4x4 components into a 4x2 cell and clipping buttons in half.

### Architectural Solution
1. **Size Breakpoint Calibration**:
   - `Small (2x2)`: `width < 200.dp`
   - `Medium (4x2)`: `width >= 200.dp && height < 215.dp`
   - `Large (4x4)`: `width >= 200.dp && height >= 215.dp`
2. **Small Layouts (`systemSmall` 2x2 Parity)**:
   - **Daily Bubbles**: 72dp multi-drink arc ring on left (`todayMl / goalMl`), percentage pill on top right, subtle trailing watermark (0.07 alpha, 46dp), and 3 quick action buttons (`100` Coffee, `150` Water, `300` Water) at 26dp height with `12dp` safe bottom padding.
   - **Daily Smokes**: 72dp progress ring on left (`todayTotal / baseline`), elapsed time pill on top right, subtle trailing flame watermark (0.07 alpha, 46dp), and 2 quick action buttons (`Cig` Red, `Heat` Blue) at 26dp height with `12dp` safe bottom padding.
   - **Daily Sleep**: 72dp radial score ring on left (`score / 100`), duration pill on top right, and 2 info pills (`Bed-Wake` schedule, `XX% Eff` efficiency) at 24dp height with `12dp` safe bottom padding.
   - **Daily Stress**: Clean 3-tier structure: Emoji + "STRESS" + Level pill header, 50dp circular score gauge (`score / 100`), and autonomic balance bar (`Rest % / Active %`). Stripped out the bottom HRV container to prevent overcrowding in 2x2.
   - **Daily Money**: Net Worth Lei + EUR pill, Card & Cash liquid balances, and 2 compact adjust buttons (`-100 Crd`, `+100 Crd`) with `12dp` safe bottom padding.
   - **Daily Tagdos**: Tagdos header + active count, Focus Tag driving pill, and clean next tag footer.
   - **Daily Combined**: Mirroring iOS `smallRegularView` with Daily header, 36dp Sleep ring hero, focus chip, and 3 metric capsules (Water, Smokes, Finances EUR).
3. **Medium Layouts (`systemMedium` 4x2 Parity)**:
   - Completely horizontal `Row` architecture (Hero Ring/Gauge on left, Header + Secondary telemetry + 2x2 Action Buttons Grid on right).
   - Smokes: 86dp lungs ring on left; header + `Cgr/Rol` (top row) & `Cig/Heat` (bottom row) on right.
   - Bubbles: 86dp multi-drink ring on left; percentage + liquid breakdown + `300/150` & `100/200` buttons grid on right.
   - Sleep: 82dp radial score ring on left; schedule + hypnogram architecture bar + Deep/REM/Light/Awake stage breakdown on right.
   - Money: 3 clean columns (NET WORTH | FLOW | LIQUID) with 3 adjust buttons (`-100 Crd`, `-100 Csh`, `+100 Crd`).
4. **Large Layouts (`systemLarge` 4x4 Parity)**:
   - Full domain depth: detailed hypnograms, full 5-stream Tagdos tables, complete transaction flows, and all action buttons.

---

## 2. 0ms App Launch & Offline-First Room Cache

### News Module (`core-database` & `presentation`)
- **Entity**: Created `CachedFeedArticleEntity` with composite index `[feed_id, published_at_ms]`, `guid` primary key, title, snippet, author, media URL, read-later flag, and favorite flag.
- **DAO (`NewsDao`)**: Added queries for `getAllCachedArticles()`, `getCachedArticlesForFeed(feedId)`, `upsertCachedArticles()`, and auto-pruning.
- **Database**: Upgraded `DailyDatabase` schema version to 6.
- **Instant Feed Loading**: `NewsRepository` initializes immediately by emitting cached articles from Room DB in 0ms, followed by non-blocking background network refresh and entity caching.
- **Sub-Tab Parity**: Switching between "Read Later" and "Favorites" resets list state, fetches live local status without lag, and updates records cleanly.

### Health Module (`core-health`)
- Health data repository emits cached local biometrics immediately on app launch, eliminating white screens and network latency before syncing with Health Connect and cloud services.

---

## 3. UI Ergonomics & Gesture Polish

1. **Pull-to-Refresh Indicator Bug**:
   - Fixed the persistent dark spinner circle stuck at the top of tabs at rest by strictly guarding with `pullRefreshState.isRefreshing || pullRefreshState.verticalOffset > 0.5f` across all 7 views (`DashboardView`, `HealthMainView`, `HabitsMainView`, `FinancesMainView`, `TagdosNotesHubView`, `NewsFeedView`, `WeatherDetailView`).
2. **Gesture Conflicts Stripped**:
   - Completely removed the conflicting `calmBoundedSwipeGesture` from `LazyColumn` and `Column` containers that hijacked vertical 120Hz scrolling and interfered with bottom dashboard pills and horizontal chips.
3. **Sleep Studio Navigation**:
   - In `SleepStudioView`, tapping the Sleep Score hero ring now uses `BringIntoViewRequester` with smooth scrolling down to the Hypnogram card, matching iOS parity.
4. **Loading Indicator Consistency**:
   - Replaced all raw Android `CircularProgressIndicator` instances with the unified `DailyLiquidLoadingIndicator` featuring cyan/accent neon glow across sheets and cards.

---

## 4. Verification & Delivery Matrix

| Target | Mechanism | Status | Notes |
|---|---|---|---|
| **Kotlin Compilation** | `./gradlew compileDebugKotlin` | **PASS** | 0 errors across all modules |
| **Unit Tests** | `./gradlew testDebugUnitTest` | **PASS** | All core-health, core-model, and core-database tests passed |
| **Debug APK Build** | `./gradlew assembleDebug` | **PASS** | `app-debug.apk` built cleanly |
| **Android Emulator** | `emulator-5554` (`Medium_Phone_API_36.1`) | **VERIFIED** | Screen captures confirm all 7 widgets across Small & Medium sizes render with zero clipping |
| **Google Pixel 9 Pro** | Wireless adb `192.168.3.8:46477` ("TRAPPER") | **DEPLOYED & VERIFIED** | Streamed install Success; PID 13162 verified running |
| **Samsung Galaxy Z Fold 8** | Wireless adb `192.168.3.64:44941` ("RADAR") | **DEPLOYED & VERIFIED** | Streamed install Success; PID 18964 verified running, all 7 widgets active in dumpsys |
| **iOS Core & App** | Gold Standard (`iOS/`, `DailyCore/`, `DailyWidgets/`) | **0 BYTES MODIFIED** | 100% preservation of iOS code |
