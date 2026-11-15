# Eager Habits Widget Synchronization & `N - 1` Lag Elimination Across All Platforms (2026)

## 1. Overview
Fixes the regression where **Smokes**, **Bubbles**, and **Executive (`Combined`)** OS widgets trailed **1 unit behind (`N - 1`)** or stalled indefinitely after in-app logging—only catching up after restarting the app—across **iOS**, **macOS**, **Android**, and **Windows 11 (`Daily.WinUI` + `Daily.WidgetsHost`)**, without increasing Supabase egress or impacting UI fluidity.

---

## 2. iOS & macOS (`DailyCore` + `iOS/Daily`)

### Root Causes Identified
1. **Cross-Process `cfprefsd` App Group Lag**: `HabitsService` wrote totals and day logs into `UserDefaults(suiteName:)` without `.synchronize()` or an atomic App Group container file, then immediately invoked `WidgetCenter.shared.reloadAllTimelines()`. `DailyWidgetsExtension` often woke before `cfprefsd` flushed the newest `N` write, rendering stale `N - 1` state.
2. **Pre-Mutation `await` & Concurrent Supabase `SELECT` Overwrite**: `logSmoke` / `logWater` suspended on auth/financials before or around writes while concurrent `loadDataForSelectedDate` refreshes overwrote in-flight optimistic `todaysSmokesLogs` and `smokesDailyTotals` with stale server `SELECT` results (`N - 1`). Meanwhile the `INSERT` completed right afterward, explaining why restarting the app reconciled the count.
3. **Unconditional `WidgetCenter.shared.reloadAllTimelines()` Storms**: Foregrounding and habit mutations repeatedly called `reloadAllTimelines()` across all widgets instead of targeted `WidgetCenter.shared.reloadTimelines(ofKind:)` gated by change detection, consuming WidgetKit reload budget and triggering system coalescing/throttling.

### Solution Implemented
- **Atomic App Group File Bridge ([`WidgetDataCoordinator.swift`](file:///Users/mihai/Source/Daily/DailyCore/Sources/DailyCore/Services/WidgetDataCoordinator.swift))**:
  - Added `HabitsWidgetBridgeState` (`daily_habits_widget_bridge_v1.json`) inside the App Group container protected by `bridgeLock` (`NSLock`) and written with `.atomic`.
  - `fetchSmokesSnapshot(bridgeFileURL:defaults:)` and `fetchBubblesSnapshot(bridgeFileURL:defaults:)` read the atomic bridge first (validating `dateKey == todayKey` and filtering soft-deleted `deletedIds`), bypassing cross-process `cfprefsd` lag while falling back to synchronized `groupDefaults`.
  - Replaced broad `reloadAllTimelines()` calls across `WidgetDataCoordinator` and [`SmartLedgerStore.swift`](file:///Users/mihai/Source/Daily/DailyCore/Sources/DailyCore/Services/SmartLedgerStore.swift) with `reloadTimelines(kinds:)` using `WidgetDataCoordinator.WidgetKind`.
- **Synchronous Optimistic Commits & Concurrency Guards ([`HabitsService.swift`](file:///Users/mihai/Source/Daily/DailyCore/Sources/DailyCore/Services/HabitsService.swift))**:
  - `logWater`, `logSmoke`, and `deleteLog` now perform all in-memory, `userDefaults.synchronize()`, and atomic `HabitsWidgetBridgeState` writes synchronously on `@MainActor` **before** any `await`, and push `newRecord` to Supabase before `fetchSmokesFinancials`.
  - Added `pendingInFlightRecords`, `recentlyPushedRecords` (15-second guard pruned on confirmation), and `pendingInFlightDeleteIds` so concurrent `loadDataForSelectedDate` fetches merge cleanly without dropping in-flight inserts or resurrecting in-flight deletes.
  - Added `saveDailyTotals(reloadingKinds:)` and foreground change detection so `loadDataForSelectedDate` only reloads affected widget kinds when Today's values, log IDs, goals, or date rollover actually change.
  - Updated `reloadFromLocalStorage()` to adopt newer widget-initiated `HabitsWidgetBridgeState` mutations cleanly and `loadLocalLogsForSelectedDate()` to reset cleanly on empty rollover days.
- **Selective Foreground Reloads ([`iOS/Daily/App/DailyApp.swift`](file:///Users/mihai/Source/Daily/iOS/Daily/App/DailyApp.swift), [`HealthDataService.swift`](file:///Users/mihai/Source/Daily/DailyCore/Sources/DailyCore/Services/HealthDataService.swift))**:
  - `HealthDataService.checkMidnightRolloverIfNeeded()` now returns `Bool` indicating actual rollover; `DailyApp` triggers full `reloadAllTimelines()` only when `habitsRolledOver || healthRolledOver`.
- **Unit Tests ([`HabitsServiceTests.swift`](file:///Users/mihai/Source/Daily/DailyCore/Tests/DailyCoreTests/HabitsServiceTests.swift))**:
  - Added `testAtomicBridgeOverridesStaleDefaults()` and `testAtomicBridgeFiltersDeletedIdsAndIgnoresStaleDates()`.

---

## 3. Android (`core-database` + `app` Glance Widgets)

### Root Causes Identified
1. `HabitsRepository` updated Room and `StateFlow`s on `logWater`, `logSmoke`, `deleteLog`, and `syncLogs`, but unlike `smartLedgerRepository.onLedgerChanged` in [`DailyApp.kt`](file:///Users/mihai/Source/Daily/Android/app/src/main/java/com/intellidream/daily/DailyApp.kt), had no callback wired to refresh Glance widgets.
2. Glance widgets read `selectedDateSmokesLogs.value` / `selectedDateWaterLogs.value` (`StateFlow`s reflecting `_selectedDate` rather than strictly Today, and susceptible to Room Flow emission lag right after `dao.insert`).

### Solution Implemented
- [`HabitLogDao.kt`](file:///Users/mihai/Source/Daily/Android/core-database/src/main/java/com/intellidream/daily/database/dao/HabitLogDao.kt): Added `suspend fun getLogsForDateOnce(habitType, startOfDay, endOfDay)` for direct SQLite reads in Glance `provideGlance`.
- [`HabitsRepository.kt`](file:///Users/mihai/Source/Daily/Android/core-database/src/main/java/com/intellidream/daily/database/HabitsRepository.kt): Added `onHabitsChanged`, `getTodayLogsOnce`, `refreshTodayCachedTotals`, and suspend `logWaterAndPersist` / `logSmokeAndPersist` so `onHabitsChanged` and Glance `ActionCallback`s run **after** Room SQLite insertion commits, plus selective notification on `syncLogs` remote changes and `deleteLog`.
- [`WidgetActionCallbacks.kt`](file:///Users/mihai/Source/Daily/Android/app/src/main/java/com/intellidream/daily/glance/WidgetActionCallbacks.kt) & [`DailyApp.kt`](file:///Users/mihai/Source/Daily/Android/app/src/main/java/com/intellidream/daily/DailyApp.kt): Added `WidgetUpdateHelper.updateHabitsWidgets(context, habitType)` (targeting only `Bubbles`/`Smokes` + `Combined`) and wired `habitsRepository.onHabitsChanged`.
- [`DailySmokesGlanceWidget.kt`](file:///Users/mihai/Source/Daily/Android/app/src/main/java/com/intellidream/daily/glance/DailySmokesGlanceWidget.kt), [`DailyBubblesGlanceWidget.kt`](file:///Users/mihai/Source/Daily/Android/app/src/main/java/com/intellidream/daily/glance/DailyBubblesGlanceWidget.kt), [`DailyCombinedGlanceWidget.kt`](file:///Users/mihai/Source/Daily/Android/app/src/main/java/com/intellidream/daily/glance/DailyCombinedGlanceWidget.kt): Switched `provideGlance` to query `getTodayLogsOnce(...)` directly from committed Room SQLite.

---

## 4. Windows 11 (`Daily.WinUI` + `Daily.WidgetsHost`)

### Root Causes Identified
1. **No Live Service-to-WidgetsHost Refresh Bridge**: `Daily.WinUI` never signaled `Daily.WidgetsHost.exe` over `Daily_WidgetsHost_IpcPipe` when `IHabitsService`, `IFinancesService`, `IHealthHubService`, `ITagdosService`, or `ISyncService` fired updates, leaving desktop widgets stale up to the 15-minute timer.
2. **Multiplier Smoke Undercount**: [`DesktopSmokesWidgetView.xaml.cs`](file:///Users/mihai/Source/Daily/WinUI/Daily.WinUI/DesktopWidgets/Views/DesktopSmokesWidgetView.xaml.cs) and [`DesktopCombinedWidgetView.xaml.cs`](file:///Users/mihai/Source/Daily/WinUI/Daily.WinUI/DesktopWidgets/Views/DesktopCombinedWidgetView.xaml.cs) counted `logs?.Count ?? 0` instead of summing `Math.Max(1, Math.Round(l.Value))`.

### Solution Implemented
- Fixed smoke totals and cigarette/heated breakdowns in [`DesktopSmokesWidgetView.xaml.cs`](file:///Users/mihai/Source/Daily/WinUI/Daily.WinUI/DesktopWidgets/Views/DesktopSmokesWidgetView.xaml.cs) and [`DesktopCombinedWidgetView.xaml.cs`](file:///Users/mihai/Source/Daily/WinUI/Daily.WinUI/DesktopWidgets/Views/DesktopCombinedWidgetView.xaml.cs) to sum `Math.Max(1, Math.Round(l.Value))`.
- Wired `SubscribeWidgetRefreshBridges()` and 120ms-debounced `ScheduleDesktopWidgetsRefresh()` in [`WinUI/Daily.WinUI/App.xaml.cs`](file:///Users/mihai/Source/Daily/WinUI/Daily.WinUI/App.xaml.cs) to `OnHabitsUpdated`, `OnSmartLedgerUpdated`, `OnDailySummaryChanged`, `ITagdosService.DataChanged`, and `ISyncService` pull events -> `DesktopWidgetManager.Instance.RefreshAllWidgets()`.
- Added reverse SQLite mutation notification from [`WidgetsHostServices.cs`](file:///Users/mihai/Source/Daily/WinUI/Daily.WidgetsHost/Services/WidgetsHostServices.cs) (`NotifyMainAppHabitsChanged()` via `DailyWinUI_ProtocolPipe` `"habits:external-changed"`) -> [`Services/HabitsService.cs`](file:///Users/mihai/Source/Daily/Services/HabitsService.cs) `NotifyExternalUpdate()` + background `SyncScope.Habits` push, guarded by `SuppressWidgetRefreshTemporarily()` to prevent IPC echo loops.

---

## 5. Verification Summary
- **`DailyCore` Swift Tests**: `swift test --package-path DailyCore --filter HabitsServiceTests` passed **14/14** tests; full `swift test --package-path DailyCore` passed **71/75** tests across 9 suites with only the 4 pre-existing unrelated failures in `"Dashboard Layout & Widget Models Tests"` (`Default Dashboard Layout Configuration` / `Legacy AppSettings` expecting 7 default widgets).
- **iOS**: Built & launched on `SimulaDuo` (verified `daily_habits_widget_bridge_v1.json` populated in App Group container); built with native Team signing and installed onto physical iPhone **`Schmitz`** (`com.intellidream.daily`).
- **macOS**: Built `MacOS/Daily.xcodeproj` (`platform=macOS`, native Apple Development signing) cleanly and verified live launch (`Daily.app`).
- **Android**: Built `Android` (`./gradlew assembleDebug`, `BUILD SUCCESSFUL`), deployed & launched `com.intellidream.daily.debug` cleanly on physical **Google Pixel 9 Pro ("Trapper")** and **Samsung `SM_F971B`** with clean logcat. (Note: `Medium_Phone_API_36.1` emulator cold-booted/restarted system services during `-no-snapshot-load` after initial APK install and launch.)
- **WinUI (`ARM64`)**: Built both `Daily.WidgetsHost.csproj` and `Daily.WinUI.csproj` (`-c Debug -p:Platform=ARM64`, `0 Error(s)`) natively in Parallels `"Windows 11"`, launched both processes in Session `1`, verified bidirectional named-pipe IPC (`"refresh"` & `"habits:external-changed"`) and confirmed live data consistency across in-app Habits, Executive, and Smokes desktop widgets.
