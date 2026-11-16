# macOS Executive, Sleep & Stress Widget Refresh Parity (2026)

## 1. Overview
Restores reliable real-time and lifecycle-driven refreshes for the **Executive (`CombinedWidget`)**, **Sleep (`SleepWidget`)**, and **Stress (`StressWidget`)** macOS Desktop / Notification Center widgets following the iOS atomic bridge overhaul—preserving full backward compatibility across widget extension processes and full iOS parity without increasing Supabase egress.

---

## 2. Root Causes Identified

1. **Legacy `UserDefaults` Schema Break + Resident `DailyWidgetsExtension` on macOS (`chronod`)**:
   - In the previous iOS fix, `WidgetDataCoordinator` replaced the payload format of `daily_sleep_widget_snapshot_v1` and `daily_stress_widget_snapshot_v1` in App Group `UserDefaults` from flat `SleepWidgetSnapshot` / `StressWidgetSnapshot` structs to `SleepWidgetBridgeEnvelope` / `StressWidgetBridgeEnvelope` (`{ dateKey, snapshot }`).
   - Meanwhile, macOS `chronod` kept the prior resident `DailyWidgetsExtension` process running across DerivedData rebuilds, while every other widget (`Bubbles`, `Smokes`, `Money`, `TagDoS`, `Cosmos`, `Weather`) retained its original `UserDefaults` schema.
   - As a result, whenever a resident macOS extension instance read `daily_sleep_widget_snapshot_v1` or `daily_stress_widget_snapshot_v1`, decoding failed and **Sleep**, **Stress**, and **Executive** (which embeds both Sleep and Stress) stopped updating.
2. **Missing macOS Lifecycle, Wake, Rollover & `SmartBriefingService` Sync Hooks**:
   - [`DailyMacOSApp.swift`](file:///Users/mihai/Source/Daily/MacOS/Daily/App/DailyMacOSApp.swift) declared an unused `@Environment(\.scenePhase)` and ran initialization once in `init()`, with no listeners for `NSApplication.didBecomeActiveNotification`, `NSWorkspace.didWakeNotification`, or `.NSCalendarDayChanged`, and never synchronized `SmartBriefingService.shared.syncForForegroundTransition(dayOrSlotChanged:)` or `WidgetDataCoordinator.shared.consumePendingWidgetRolloverReload()`.
   - `Cmd+R` (`Sync with Cloud`), [`DashboardView.swift`](file:///Users/mihai/Source/Daily/MacOS/Daily/Views/Dashboard/DashboardView.swift), and [`HeaderGreetingView.swift`](file:///Users/mihai/Source/Daily/MacOS/Daily/Views/Dashboard/HeaderGreetingView.swift) did not refresh local widget briefing bridges or TagDoS/rollover state after Cloud syncs.
3. **Stress Timeline Midnight Alignment (`00:00`)**:
   - Both macOS and iOS [`StressWidget.swift`](file:///Users/mihai/Source/Daily/MacOS/DailyWidgets/StressWidget.swift) providers scheduled raw `+15m` timeline intervals instead of boundary-aligned dates via `WidgetDataCoordinator.nextBoundaryAlignedDate(..., boundaryHours: [0])`.

---

## 3. Solution Implemented

- **Backward-Compatible Envelope Storage in [`WidgetDataCoordinator.swift`](file:///Users/mihai/Source/Daily/DailyCore/Sources/DailyCore/Services/WidgetDataCoordinator.swift)**:
  - Kept the atomic App Group container files (`daily_sleep_widget_bridge_v1.json`, `daily_stress_widget_bridge_v1.json`) and dedicated `UserDefaults` envelope keys (`daily_sleep_widget_envelope_v1`, `daily_stress_widget_envelope_v1`) holding date-scoped `{ dateKey, snapshot }` envelopes (supporting explicit same-day empty clears across midnight).
  - Kept legacy keys (`daily_sleep_widget_snapshot_v1`, `daily_stress_widget_snapshot_v1`) encoded as flat `SleepWidgetSnapshot` / `StressWidgetSnapshot` payloads (`lastUpdated: now`) so any resident extension process continues decoding cleanly.
  - Updated `fetchSleepSnapshot(bridgeDirectoryURL:defaults:now:)` and `fetchStressSnapshot(bridgeDirectoryURL:defaults:now:)` to read (1) atomic bridge file (`Envelope`), (2) dedicated envelope key (`Envelope`), (3) legacy flat key (`Envelope` or same-day `hasData` snapshot), and (4) today-only ISO-8601 `health_daily_summary_\(todayKey)`.
- **macOS Lifecycle, Wake & Midnight Coordinator ([`DailyMacOSApp.swift`](file:///Users/mihai/Source/Daily/MacOS/Daily/App/DailyMacOSApp.swift))**:
  - Added `MacOSLifecycleCoordinator` started from `DailyMacOSApp.init()` observing `NSApplication.didBecomeActiveNotification` (debounced at 15s unless day/slot changed), `NSWorkspace.didWakeNotification`, `.NSCalendarDayChanged`, `scenePhase == .active`, and `Cmd+R` (`Sync with Cloud`).
  - Integrated `HabitsService.checkMidnightRolloverIfNeeded()`, `HealthDataService.checkMidnightRolloverIfNeeded()`, `WidgetDataCoordinator.consumePendingWidgetRolloverReload()`, stale-gated `HealthDataService.refreshIfStale()` / `WeatherService.refreshWeatherIfStale()`, `SmartBriefingService.syncForForegroundTransition(dayOrSlotChanged:)`, and full/targeted `WidgetKit` reloads matching [`DailyApp.swift`](file:///Users/mihai/Source/Daily/iOS/Daily/App/DailyApp.swift).
  - Updated [`DashboardView.swift`](file:///Users/mihai/Source/Daily/MacOS/Daily/Views/Dashboard/DashboardView.swift) and [`HeaderGreetingView.swift`](file:///Users/mihai/Source/Daily/MacOS/Daily/Views/Dashboard/HeaderGreetingView.swift) to call `TagdosStore.shared.syncWithWidgets()` and `SmartBriefingService.shared.refreshLocalWidgetBriefingIfNeeded()` after syncs.
- **Cross-Platform Stress Boundary Alignment ([`MacOS/DailyWidgets/StressWidget.swift`](file:///Users/mihai/Source/Daily/MacOS/DailyWidgets/StressWidget.swift), [`iOS/DailyWidgets/StressWidget.swift`](file:///Users/mihai/Source/Daily/iOS/DailyWidgets/StressWidget.swift))**:
  - Updated both `StressTimelineProvider` implementations to use `WidgetDataCoordinator.nextBoundaryAlignedDate(after: currentDate, defaultIntervalMinutes: 15, boundaryHours: [0])`.

---

## 4. Verification Summary
- **Targeted `DailyCore` Suites**:
  - `swift test --package-path DailyCore --filter "HealthServiceTests|HabitsServiceTests|SmartBriefingTests|StressEngineTests"`: **60/60 tests in 4 suites passed** (`0.099s`), including `testLegacyFlatSleepAndStressDefaultsRemainDecodableAlongsideDateEnvelopes`, `testAtomicSleepBridgeOverridesStaleDefaultsAndRejectsYesterdaySummary`, `testMorningBriefRejectsStaleYesterdayOrWrongSlotBriefingAndUsesLiveSnapshots`, and `testBoundaryAlignedTimelineDatesAndRolloverTracker` in [`HealthServiceTests.swift`](file:///Users/mihai/Source/Daily/DailyCore/Tests/DailyCoreTests/HealthServiceTests.swift).
  - Full `swift test --package-path DailyCore`: **67/67** XCTest cases passed; in Swift Testing (**79 tests across 9 suites**), **76/79 tests passed**, with only 3 pre-existing tests (4 expectation issues: `defaults.count == 7` vs `8` with `"prism"`) failing in `"Dashboard Layout & Widget Models Tests"`.
- **macOS (`MacOS/Daily.xcodeproj`)**:
  - Built cleanly with native `Apple Development` signing (`Team 7LZ9ZT2Z5B`), re-registered `com.intellidream.daily.macos.DailyWidgets` via `pluginkit`, and relaunched both `Daily.app` (`PID 98484`) and `DailyWidgetsExtension.appex` (`PID 98494`). Verified via unified system logs that `SleepWidget`, `widget.stress`, and `widget.combined` timelines reloaded and archived successfully (`11:54:53`–`11:54:57`).
- **iOS (`iOS/Daily.xcodeproj`)**:
  - **`SimulaDuo` Simulator**: Built, installed, and launched `com.intellidream.daily` (`PID 98971`) cleanly.
  - **Physical iPhone (`Schmitz`)**: Built cleanly with native Team signing (`Provisioning Profile: iOS Team Provisioning Profile: com.intellidream.daily`) and installed via `xcrun devicectl`; foreground launch returned `Unable to launch com.intellidream.daily because the device was not, or could not be, unlocked` while the device screen was locked.
