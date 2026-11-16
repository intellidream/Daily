# iOS Sleep & Morning Brief Widget Refresh Architecture (2026)

## 1. Overview
Fixes the iOS-specific regression where **SleepWidget** and **Morning Brief** (**Executive `CombinedWidget`** morning mode before `12:00`) failed to refresh on the iOS Home Screen while updating properly on macOS, Android, and Windows—without increasing Supabase egress, triggering unnecessary AI API calls, or degrading scrolling/UI performance.

---

## 2. Root Causes Identified

1. **Missing Atomic App Group File Bridges for Non-Habits Widgets (`cfprefsd` Cross-Process Lag on iOS)**:
   - Prior work fixed `Bubbles` and `Smokes` using `daily_habits_widget_bridge_v1.json`, whereas **Sleep**, **Stress**, **Smart Briefing (`daily_smart_summary_cache_v4`)**, **Weather**, **TagDoS**, **Cosmos**, and **Money** still relied exclusively on `UserDefaults(suiteName:)` (`cfprefsd`), and widget readers (`fetchSleepSnapshot()`, `fetchStressSnapshot()`, `fetchWeatherSnapshot()`, `fetchTagdosSnapshot()`, `fetchCosmosSnapshot()`, `fetchMoneySnapshot()`, `fetchCombinedSnapshot()`) did not even call `.synchronize()` prior to decoding.
   - `SmartBriefingService.saveCachedBriefing(_:)` wrote `daily_smart_summary_cache_v4` without `.synchronize()`, without an atomic file bridge, and without calling `WidgetDataCoordinator.shared.reloadTimelines(kinds: [WidgetKind.combined])`.
2. **Stale Cross-Day / Wrong-Slot Records & Broken ISO-8601 Fallback Decoding**:
   - `SleepWidgetSnapshot` and `StressWidgetSnapshot` lacked `dateKey` scoping, while `fetchSleepSnapshot()` and `fetchStressSnapshot()` decoded `health_daily_summary_\(dKey)` using default `JSONDecoder()` instead of ISO-8601 date decoding (silently failing on `computedAt: Date`), and looped across `dayOffset in 0...2` / `0...1`—returning yesterday's sleep/stress even when today was explicitly empty.
   - `WidgetDataCoordinator.fetchCombinedSnapshot()` decoded `daily_smart_summary_cache_v4` without checking `Calendar.current.isDate(record.createdAt, inSameDayAs: now)` or `record.slot == currentSlot`, and preferred stale briefing metrics over live today `WeatherWidgetSnapshot` / `SleepWidgetSnapshot`.
3. **iOS Warm-Resume Lifecycle, Midnight Rollover Race & HealthKit Sleep Arrival**:
   - On iOS (unlike macOS cold relaunches), the app frequently remains suspended in memory overnight, so `DashboardView.task` does not re-run in the morning and `UIApplication.willEnterForegroundNotification` / background tasks could consume `checkMidnightRolloverIfNeeded()` before `DailyApp.onChange(of: scenePhase)` evaluated `habitsRolledOver || healthRolledOver`.
   - `DailyApp` on foreground resume did not refresh stale `WeatherService` or synchronize `SmartBriefingService` across day/slot boundaries, and `DashboardView.task` / `SmartBriefing` SwiftUI `.task` cancellation cancelled in-flight `WeatherService.refreshWeather()` URLSession calls (`NSURLErrorCancelled -999`).
   - `HealthDataService` lacked batching across `applyCanonicalSummary` -> `applyLeanSleepSessions` -> `reapplyCurrentDeviceFilter` (firing duplicate widget writes/reloads in milliseconds) and `HealthKitManager` lacked an `HKObserverQuery` on `.sleepAnalysis` to invalidate `refreshIfStale()` when Apple Watch delivered morning sleep while iOS was suspended/active.
4. **Diurnal & Midnight Timeline Boundaries**:
   - `CombinedTimelineProvider` and `SleepTimelineProvider` scheduled fixed `+15m` / `+30m` reloads that could drift past `00:00`, `05:00`, and `12:00`.

---

## 3. Solution Implemented

- **Unified Atomic App Group File Bridges & Change-Gated Reloads ([`WidgetDataCoordinator.swift`](file:///Users/mihai/Source/Daily/DailyCore/Sources/DailyCore/Services/WidgetDataCoordinator.swift), [`SmartLedgerStore.swift`](file:///Users/mihai/Source/Daily/DailyCore/Sources/DailyCore/Services/SmartLedgerStore.swift))**:
  - Added `daily_sleep_widget_bridge_v1.json`, `daily_stress_widget_bridge_v1.json`, `daily_briefing_widget_bridge_v1.json`, `daily_weather_widget_bridge_v1.json`, `daily_weather_coords_v1.json`, `daily_tagdos_widget_bridge_v1.json`, `daily_cosmos_widget_bridge_v1.json`, and `daily_money_widget_bridge_v1.txt` written atomically under `bridgeLock` alongside synchronized `groupDefaults`.
  - Added canonical payload deduplication (`canonicalSemanticData`, stripping `lastUpdated`/`updatedAt`) inside `persistBridgeValue` so redundant writes with identical content do not consume iOS WidgetKit reload budget.
  - Scoped Sleep and Stress bridges via `{ dateKey, snapshot }` envelopes and Today-only (`dayOffset == 0`) ISO-8601 `health_daily_summary_\(todayKey)` fallback.
  - Updated `fetchCombinedSnapshot` to require `isDate(record.createdAt, inSameDayAs: now) && record.slot == currentSlot` and overlay fresh live `Weather` and `Sleep` snapshots onto `BriefingSummarySnippet`.
  - Added `consumePendingWidgetRolloverReload(for:defaults:)` and `nextBoundaryAlignedDate(after:defaultIntervalMinutes:boundaryHours:)`.
- **Smart Briefing & Weather Resilience ([`SmartBriefingService.swift`](file:///Users/mihai/Source/Daily/DailyCore/Sources/DailyCore/Services/SmartBriefingService.swift), [`WeatherService.swift`](file:///Users/mihai/Source/Daily/DailyCore/Sources/DailyCore/Services/WeatherService.swift))**:
  - Updated `SmartBriefingService.saveCachedBriefing(_:)` and `loadCachedBriefing()` to update/clear `WidgetDataCoordinator.shared` atomically and trigger targeted `WidgetKind.combined` reloads; added `syncForForegroundTransition(dayOrSlotChanged:)` and zero-network `refreshLocalWidgetBriefingIfNeeded()`.
  - Wrapped `WeatherService.refreshWeather(force:)` in a singleton `activeRefreshTask` immune to SwiftUI view `.task` cancellations, added `refreshWeatherIfStale(maxAge:)`, cached App Group coordinates fallback, and invoked `SmartBriefingService.shared.refreshLocalWidgetBriefingIfNeeded()` after updating `WeatherWidgetSnapshot`.
- **HealthKit Observer & Batched Sync ([`HealthDataService.swift`](file:///Users/mihai/Source/Daily/DailyCore/Sources/DailyCore/Services/HealthDataService.swift), [`HealthKitManager.swift`](file:///Users/mihai/Source/Daily/iOS/Daily/Services/HealthKitManager.swift))**:
  - Reset stale day sleep state and cooldown timestamps on `checkMidnightRolloverIfNeeded()`, added `markLocalHealthDataDirty()` and zero-egress-when-unchanged `refreshFromLocalProviderIfNeeded()`, and batched `suppressWidgetSnapshotUpdates` across pre-merge canonical preview vs final `reapplyCurrentDeviceFilter()`.
  - Added an `HKObserverQuery` on `.sleepAnalysis` inside `HealthKitManager` that marks `HealthDataService.shared.markLocalHealthDataDirty()` immediately (zero background network traffic) and refreshes live in foreground when `UIApplication.shared.applicationState == .active`.
- **iOS Warm-Resume & Boundary Timelines ([`iOS/Daily/App/DailyApp.swift`](file:///Users/mihai/Source/Daily/iOS/Daily/App/DailyApp.swift), [`iOS/Daily/Views/Dashboard/DashboardView.swift`](file:///Users/mihai/Source/Daily/iOS/Daily/Views/Dashboard/DashboardView.swift), [`CombinedWidget.swift`](file:///Users/mihai/Source/Daily/iOS/DailyWidgets/CombinedWidget.swift), [`SleepWidget.swift`](file:///Users/mihai/Source/Daily/iOS/DailyWidgets/SleepWidget.swift), [`MacOS/DailyWidgets/CombinedWidget.swift`](file:///Users/mihai/Source/Daily/MacOS/DailyWidgets/CombinedWidget.swift), [`MacOS/DailyWidgets/SleepWidget.swift`](file:///Users/mihai/Source/Daily/MacOS/DailyWidgets/SleepWidget.swift))**:
  - Updated `DailyApp.onChange(of: scenePhase)` to evaluate `consumePendingWidgetRolloverReload()`, refresh stale weather, synchronize Smart Briefing state, and trigger full/targeted timeline reloads without relying on un-raced service rollover booleans.
  - Updated Dashboard `.refreshable` to sync `SmartBriefingService.shared.refreshLocalWidgetBriefingIfNeeded()`, and aligned `CombinedTimelineProvider` (`0, 5, 12, 17, 21`) and `SleepTimelineProvider` (`0, 6, 8, 10`) timelines to diurnal/midnight boundaries.

---

## 4. Verification Summary
- **Swift Tests (`DailyCore`)**:
  - `swift test --package-path DailyCore --filter "HealthServiceTests|HabitsServiceTests"`: **47/47 passed** (`0.078s`), including `testAtomicSleepBridgeOverridesStaleDefaultsAndRejectsYesterdaySummary`, `testMorningBriefRejectsStaleYesterdayOrWrongSlotBriefingAndUsesLiveSnapshots`, and `testBoundaryAlignedTimelineDatesAndRolloverTracker` in [`HealthServiceTests.swift`](file:///Users/mihai/Source/Daily/DailyCore/Tests/DailyCoreTests/HealthServiceTests.swift).
  - Full `swift test --package-path DailyCore`: **74/78** Swift Testing cases passed across 9 suites plus XCTest suites (`AstronomyServiceTests`, `NewsServiceTests`), with only the 4 pre-existing unrelated issues in `"Dashboard Layout & Widget Models Tests"`.
- **iOS Simulator (`SimulaDuo`)**: Built & launched `Daily.app` + `DailyWidgetsExtension.appex`, verified all atomic container files (`daily_sleep_widget_bridge_v1.json`, `daily_briefing_widget_bridge_v1.json`, `daily_weather_widget_bridge_v1.json`, `daily_stress_widget_bridge_v1.json`, `daily_habits_widget_bridge_v1.json`, `daily_tagdos_widget_bridge_v1.json`, `daily_cosmos_widget_bridge_v1.json`, `daily_money_widget_bridge_v1.txt`) populated cleanly alongside live Morning Briefing + Weather (`7° Light Rain`) + Sleep (`6h 49m`) UI.
- **Physical iPhone (`Schmitz`)**: Built with native Team signing, installed, and launched `com.intellidream.daily` live via `xcrun devicectl`.
- **macOS (`Daily.app`)**: Built cleanly with native `Apple Development` signing and launched live (`Daily.app` + `DailyWidgetsExtension.appex`).
