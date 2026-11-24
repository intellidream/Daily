# Cross-Platform Smokes Widget Persistence & Android Glance Refresh Optimization (2026)

## 1. Overview
Resolves three targeted regressions without altering macOS widget behavior, UI scroll fluidity, or Supabase egress:
1. **iOS**: Logging Smokes directly from OS widgets (`SmokesWidget` / `WidgetIntents`) was lost or reverted during cross-process sync and foreground refreshes.
2. **Windows 11 (`Daily.WinUI` + `Daily.WidgetsHost`)**: Desktop Smokes widget additions could fail under SQLite lock contention, log under an empty `UserId` (`""`), mismatch metadata format, or execute an outdated `Daily.WidgetsHost.exe`.
3. **Android**: Glance Home Screen widgets refreshed slowly because updates executed serially across all widgets, waited behind network I/O on startup/`onResume()`, fired duplicate renders on interactive taps, lacked Health/Cosmos callbacks, and rebuilt static vector bitmaps per composition.

---

## 2. iOS (`DailyCore` + `iOS/Daily`)

### Root Causes Identified
1. **Missing Darwin Mutation Listener on iOS**: Unlike macOS, `iOS/Daily` had no Darwin notification listener for `WidgetDataCoordinator.darwinMutationNotificationName`, so widget-side mutations were not reloaded or flushed to Supabase while the iOS app remained active or backgrounded.
2. **Volatile Cross-Process Pending Queue & Foreground Races**:
   - `WidgetIntents` (`LogSmokeIntent`, `LogCigaretteIntent`, `LogHeatedIntent`) appended records only to `UserDefaults(suiteName:)` (`offline_habits_queue`), without an atomic App Group container file or consistent `synchronize()` calls across process boundaries.
   - [`HabitsService.swift`](file:///Users/mihai/Source/Daily/DailyCore/Sources/DailyCore/Services/HabitsService.swift) could run concurrent `flushOfflineQueue()` passes, did not preserve flushed entries in `recentlyPushedRecords`, could overwrite newer `offline_habits_queue` additions written mid-flush, and allowed duplicate foreground calls (`willEnterForegroundNotification` and [`DailyApp.swift`](file:///Users/mihai/Source/Daily/iOS/Daily/App/DailyApp.swift)) to overwrite newer widget bridge totals with stale server `SELECT` results.

### Solution Implemented
- **Atomic Pending Queue & Synchronized Writes ([`WidgetDataCoordinator.swift`](file:///Users/mihai/Source/Daily/DailyCore/Sources/DailyCore/Services/WidgetDataCoordinator.swift))**:
  - Added atomic container file `daily_habits_pending_queue_v1.json` alongside synchronized `offline_habits_queue` defaults via `readPendingHabitLogs()`, `enqueuePendingHabitLog()`, `removePendingHabitLogs(ids:)`, and lock-protected `appendOfflineHabitQueue()`.
- **Single-Flight Flush & Foreground Coalescing ([`HabitsService.swift`](file:///Users/mihai/Source/Daily/DailyCore/Sources/DailyCore/Services/HabitsService.swift))**:
  - Coalesced `flushOfflineQueue()` through `performFlushOfflineQueuePass()`, tracked flushed IDs in `recentlyPushedRecords`, removed only confirmed IDs via `removePendingHabitLogs(ids:)`, merged bridged pending records across `loadLocalSettingsAndQueue()` / `reloadFromLocalStorage()` / `saveDailyTotals()`, and introduced `syncForForegroundTransition(dayRolledOver:)` (flushing queued widget mutations before loading server totals).
- **iOS Darwin Listener ([`WidgetDarwinMutationListener.swift`](file:///Users/mihai/Source/Daily/iOS/Daily/Services/WidgetDarwinMutationListener.swift), [`DailyApp.swift`](file:///Users/mihai/Source/Daily/iOS/Daily/App/DailyApp.swift))**:
  - Added `@MainActor` `WidgetDarwinMutationListener` started in `DailyApp.init()`, acquiring a `UIApplication` background task on widget mutations to reload `SmartLedgerStore`, `TagdosStore`, and `HabitsService` and flush pending changes to Supabase without triggering extra `SELECT` egress on unchanged stores.
- **Unit Test ([`HabitsServiceTests.swift`](file:///Users/mihai/Source/Daily/DailyCore/Tests/DailyCoreTests/HabitsServiceTests.swift))**:
  - Added `testAtomicPendingHabitQueuePreservation()`.

---

## 3. Windows 11 (`Services` + `Daily.WidgetsHost` + `Daily.WinUI`)

### Root Causes Identified
1. **Stale Host Executable Resolution**: [`WidgetsHostIpc.cs`](file:///Users/mihai/Source/Daily/WinUI/Daily.WinUI/DesktopWidgets/WidgetsHostIpc.cs) preferred an older `Daily.WidgetsHost.exe` located in `AppContext.BaseDirectory` over the newer architecture-matched `Daily.WidgetsHost` build output and left an older running host alive.
2. **Cross-Process SQLite Locking**: [`DatabaseService.cs`](file:///Users/mihai/Source/Daily/Services/DatabaseService.cs) opened `Daily.db3` under `WINUI_NATIVE` without SQLite `WAL` journal mode or `busy_timeout`, causing `SQLiteException` lock contention between `Daily.WinUI.exe` and `Daily.WidgetsHost.exe`.
3. **Orphaned Blank `UserId` & Metadata Format Mismatch**: [`WidgetsHostServices.cs`](file:///Users/mihai/Source/Daily/WinUI/Daily.WidgetsHost/Services/WidgetsHostServices.cs) wrote `UserId = ""` (ignored by authenticated queries and sync pushes until [`HabitsRepository.cs`](file:///Users/mihai/Source/Daily/Services/HabitsRepository.cs) expanded `MigrateGuestDataAsync`), while [`DesktopSmokesWidgetView.xaml.cs`](file:///Users/mihai/Source/Daily/WinUI/Daily.WinUI/DesktopWidgets/Views/DesktopSmokesWidgetView.xaml.cs) logged non-canonical `unit`/`Metadata` strings (`"cigarette"` / `"heated"`).

### Solution Implemented
- [`DatabaseService.cs`](file:///Users/mihai/Source/Daily/Services/DatabaseService.cs): Enabled `PRAGMA journal_mode=WAL` and `PRAGMA busy_timeout=5000` under `#if WINUI_NATIVE`.
- [`HabitsRepository.cs`](file:///Users/mihai/Source/Daily/Services/HabitsRepository.cs): Expanded `MigrateGuestDataAsync` to adopt blank/null/`"guest"` `UserId` rows (habits logs and goals) normalized to lowercase, and wired `habits:external-changed` in [`App.xaml.cs`](file:///Users/mihai/Source/Daily/WinUI/Daily.WinUI/App.xaml.cs) to migrate guest/blank rows before refreshing and pushing.
- [`WidgetsHostServices.cs`](file:///Users/mihai/Source/Daily/WinUI/Daily.WidgetsHost/Services/WidgetsHostServices.cs): Added `ResolveActiveUserIdAsync()` for `AddLogAsync` and `UpdateGoalAsync`, and updated `GetDailyBreakdownAsync` to parse `"type"`, `"drink"`, and legacy fallback strings.
- [`DesktopSmokesWidgetView.xaml.cs`](file:///Users/mihai/Source/Daily/WinUI/Daily.WinUI/DesktopWidgets/Views/DesktopSmokesWidgetView.xaml.cs): Updated `+ Cig` and `+ Heat` handlers (`LogSmokeAsync`) to pass canonical unit `"cigs"` and JSON metadata (`{"type":"Cigarette"}` / `{"type":"Heated Tobacco"}`), logging failures to `%USERPROFILE%\daily_widgetshost_debug.log`.
- [`WidgetsHostIpc.cs`](file:///Users/mihai/Source/Daily/WinUI/Daily.WinUI/DesktopWidgets/WidgetsHostIpc.cs): Updated `GetHostExecutablePath()` to compare build timestamps between `AppContext.BaseDirectory` and the architecture-matched `WinUI\Daily.WidgetsHost\bin` output, and updated `EnsureHostRunning()` to replace outdated running host processes cleanly.

---

## 4. Android (Glance Home Screen Widgets)

### Root Causes Identified
1. Serial `updateAll(context)` invocations inside [`WidgetActionCallbacks.kt`](file:///Users/mihai/Source/Daily/Android/app/src/main/java/com/intellidream/daily/glance/WidgetActionCallbacks.kt).
2. Startup widget refresh in [`DailyApp.kt`](file:///Users/mihai/Source/Daily/Android/app/src/main/java/com/intellidream/daily/DailyApp.kt) and resume refresh in [`MainActivity.kt`](file:///Users/mihai/Source/Daily/Android/app/src/main/java/com/intellidream/daily/MainActivity.kt) blocked behind `weatherRepository.refreshWeather` and `smartLedgerRepository.syncWithCloud()`.
3. Full `updateAllWidgets` broadcasts on SmartLedger edits and double widget renders on Ledger/TagDoS Glance button taps.
4. Missing widget update callbacks on Health summary and Cosmos condition updates, and repeated `Bitmap` allocations inside [`WidgetVisualGraphics.kt`](file:///Users/mihai/Source/Daily/Android/app/src/main/java/com/intellidream/daily/glance/WidgetVisualGraphics.kt).

### Solution Implemented
- [`WidgetActionCallbacks.kt`](file:///Users/mihai/Source/Daily/Android/app/src/main/java/com/intellidream/daily/glance/WidgetActionCallbacks.kt): Parallelized all `WidgetUpdateHelper` updates using `coroutineScope { launch { ... } }`, added scoped `updateTagdosWidgets`, `updateHabitsWidgets`, `updateHealthWidgets`, `updateFinanceWidgets`, and `updateCosmosWidgets`, and suppressed duplicate repository callbacks on interactive Glance taps (`notifyWidgets = false`).
- [`SmartLedgerRepository.kt`](file:///Users/mihai/Source/Daily/Android/core-database/src/main/java/com/intellidream/daily/database/SmartLedgerRepository.kt) & [`TagdosRepository.kt`](file:///Users/mihai/Source/Daily/Android/core-database/src/main/java/com/intellidream/daily/database/TagdosRepository.kt): Added `notifyWidgets: Boolean = true` parameter and `onTagdosWidgetsChanged` callback.
- [`HealthDataRepository.kt`](file:///Users/mihai/Source/Daily/Android/core-health/src/main/java/com/intellidream/daily/health/HealthDataRepository.kt) & [`CosmosLiveRepository.kt`](file:///Users/mihai/Source/Daily/Android/app/src/main/java/com/intellidream/daily/cosmos/CosmosLiveRepository.kt): Added `onHealthSummaryUpdated` (for today's summary) and `onConditionsUpdated`.
- [`DailyApp.kt`](file:///Users/mihai/Source/Daily/Android/app/src/main/java/com/intellidream/daily/DailyApp.kt) & [`MainActivity.kt`](file:///Users/mihai/Source/Daily/Android/app/src/main/java/com/intellidream/daily/MainActivity.kt): Wired scoped widget callbacks after repository initialization and unblocked startup/`onResume()` Glance updates from network I/O.
- [`WidgetVisualGraphics.kt`](file:///Users/mihai/Source/Daily/Android/app/src/main/java/com/intellidream/daily/glance/WidgetVisualGraphics.kt): Added `iconBitmapCache` (`LruCache<String, Bitmap>(96)`) for `createVectorIconBitmap`.

---

## 5. Verification Summary
- **`DailyCore` Swift Tests**: `swift test --package-path DailyCore --filter "HabitsServiceTests|HealthServiceTests"` passed **52/52 tests across 2 suites** (`0.120s`), including `"Atomic Pending Habit Queue Preserves Concurrent Widget Mutations"`.
- **macOS (`MacOS/Daily.xcodeproj`)**: `xcodebuild -project MacOS/Daily.xcodeproj -scheme Daily -configuration Debug -destination 'platform=macOS' build` succeeded (`** BUILD SUCCEEDED **`).
- **iOS (`iOS/Daily.xcodeproj`)**:
  - `SimulaDuo` simulator: built (`** BUILD SUCCEEDED **`), installed, and launched `com.intellidream.daily`; confirmed `DailyWidgetsExtension.appex/Metadata.appintents/extract.actionsdata` (`12781` bytes) and App Group bridge hydration (`smokesTotal: 26`, `waterTotalMl: 1400`).
  - `generic/platform=iOS`: built and signed with `Apple Development` (`** BUILD SUCCEEDED **`); physical installation to `Schmitz` could not connect (`CoreDeviceError 4000 / Connection reset by peer`, device `available (paired)`).
- **Android**:
  - `./gradlew assembleDebug` and `./gradlew testDebugUnitTest` succeeded cleanly.
  - `Medium_Phone_API_36.1` emulator: verified `DailyApp` startup, interactive Smokes widget taps (`Heat` -> `Cig`, updating count `0 -> 1 -> 2` alongside `Daily Executive` in `68ms–250ms` via logcat `AppWidgetServiceImpl`).
  - Physical `Pixel 9 Pro`: installed `app-debug.apk`, launched `com.intellidream.daily.debug` (`PID 11461`), and verified zero crashes with active Glance widget refreshes (`109, 111, 112, 114`).
- **Windows 11 (`"Windows 11"` ARM64 VM)**:
  - Built `WinUI\Daily.WidgetsHost\Daily.WidgetsHost.csproj` (`0 Error(s)`, `29.13s`) and `WinUI\Daily.WinUI\Daily.WinUI.csproj` (`0 Error(s)`, `51.95s`) for `ARM64`.
  - Launched both `Daily.WinUI.exe` (`PID 6800`) and `Daily.WidgetsHost.exe` (`PID 10260`, loaded from `WinUI\Daily.WidgetsHost\bin\ARM64\Debug\...`); verified SQLite `journal_mode = wal`, migration and Supabase sync of the prior orphaned blank-`UserId` record (`d176fd4a-afc1-402b-b2b4-5f166ae155b9`, `orphan_count = 0`), and live UI/widget display parity (`Smokes 28 / 40 smokes`).
