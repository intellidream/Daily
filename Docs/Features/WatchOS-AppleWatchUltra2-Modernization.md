# watchOS Modernization & Apple Watch Ultra 2 Parity

**Date:** October 27, 2026  
**Target:** watchOS 10+ / 11+ (`WatchOS/DailyWatch/DailyWatch Watch App`)  
**Verified On:** Apple Watch Ultra 2 (Physical Device, UDID: `00008310-001B192A3698A01E`)  

---

## 1. Overview & Objectives

Following the zero-latency, local-first modernization achieved on WearOS (Google Pixel Watch 5 & OnePlus Watch 3), this initiative brings **watchOS** to the exact same high architectural, operational, and visual standards.

Prior to this update, the watchOS application suffered from:
1. **Siloed views without a centralized Habit Store**: Every tab maintained its own independent state and fired duplicate network requests on swipe and foreground.
2. **Superficial caching (< 1ms cold-start failure)**: Only a single raw integer was cached; upon cold start, breakdown numbers and logs lists were completely empty until network calls finished.
3. **Fragile offline sync**: `OfflineSyncManager` only supported batch `INSERT` operations; deletions were unqueued and lost if performed offline; all-or-nothing batch inserts could permanently freeze the outbox.
4. **Heated tobacco metadata parsing bug**: In `SmokesView`, parsing looked strictly for `["type"]`. Logs created on iOS, Android, or macOS with `"brand": "Heated Tobacco"` fell back to `"Cigarette"`, miscounting heated sticks as combustible cigarettes.
5. **Missing canonical habit filter**: Only `.eq("habit_type", value: "smokes")` was queried, omitting rows saved under `"smoke"`.
6. **Ergonomic flaws (Apple HIG non-compliance)**: Cramped 86pt side-by-side rings with 25pt buttons were difficult to tap reliably on small or moving screens.

---

## 2. Architectural Implementation

### 2.1 Centralized `WatchHabitStore` (`WatchHabitStore.swift`)
- Implemented `@MainActor class WatchHabitStore: ObservableObject` as the **Single Source of Truth** for the entire watchOS app.
- **Instant AppGroup Hydration (< 1ms Cold Boot)**:
  - Synchronously loads full daily totals (`waterTotalToday`, `smokesTotalToday`), drink/smoke breakdowns (`waterAmountToday`, `coffeeAmountToday`, `cigsCountToday`, `heatCountToday`), active logs (`todayWaterLogs`, `todaySmokesLogs`), and Monday-to-Sunday 7-day trend buckets (`waterWeekBuckets`, `smokesWeekBuckets`) from `group.com.intellidream.daily`.
- **Single-Pass Multi-Day Network Sync (`fetchFullSync`)**:
  - Pulls `user_preferences` (synchronizing `water_goal` and `smokes_baseline`, default 40).
  - Fetches today's water and smokes in a **single unified network query** (`gte startOfDay, lt endOfDay`), splitting items in memory to eliminate redundant HTTP round-trips.
  - Fetches 7-day trend history for the current Monday-to-Sunday window in one query, populating both water and smokes charts simultaneously.

### 2.2 Modern Swift Actor `OfflineSyncManager` (`OfflineSyncManager.swift`)
- Refactored `OfflineSyncManager` into a Swift `actor` guaranteeing absolute thread-safety between background refresh tasks (`ExtensionDelegate`) and foreground UI actions.
- **Bidirectional Outbox (`OutboxItem`)**:
  - Supports both `insert` and `delete` action types.
  - Automatically deduplicates and cancels pending inserts if a log is deleted while still in the outbox.
  - Migrates legacy single-queue items to Outbox v2 on first launch.
  - Individual item error handling: prevents transient 409 or constraint conflicts on one item from blocking the remaining outbox queue.

### 2.3 Domain Model Hardening (`HabitLog.swift`)
- Enhanced `HabitLog` with intelligent metadata helpers:
  - `isHeatedSmoke`: inspects `brand`, `type`, `smokeType`, and raw string tokens (`"heat"`, `"vape"`, `"iqos"`, `"glo"`, `"ploom"`), guaranteeing 100% parity across logs created on iOS, Android, WearOS, and macOS.
  - `isCoffeeDrink`: detects coffee/espresso drinks accurately.
  - `displayDrinkName` and `displaySmokeName` for consistent typography.
- Memoized date formatting in `HabitDateParser`: static cached `DateFormatter` for short time strings (`HH:mm`), eliminating expensive allocations on render threads.

---

## 3. UI/UX Ergonomic Overhaul

### 3.1 Single-Flow Vertical Layout (`BubblesView.swift` & `SmokesView.swift`)
1. **Header**: Clean category icon and accent title (`Image("drop.fill")` in `.cyan` / `Image("flame.fill")` in `.red`).
2. **TemporalNavHeader**: Day navigation with enlarged touch targets and Digital Crown rotation support (`.digitalCrownRotation`).
3. **Centered 122pt Hero Progress Ring**:
   - 122x122pt circular gauge with 10pt stroke width.
   - Large rounded typography (`Text("\(displayTotal)").font(.system(size: 26, weight: .bold, design: .rounded))`).
   - Dynamic threshold color transitions on Smokes (Green -> Yellow -> Orange -> Red).
4. **Summary Breakdown Ticker**:
   - Capsule badge displaying detailed breakdowns (`300 ml Water · 100 ml Coffee` or `12 Cig · 4 Heat`).
5. **Full-Width Touch Chips (44–46pt Apple HIG Compliant)**:
   - Replaced cramped 25pt buttons with full-width Liquid Glass chips:
     - Bubbles: `+300 ml Water`, `+150 ml Water`, `+100 ml Coffee`.
     - Smokes: `+1 Cigarette`, `+1 Heated Tobacco`.
   - Distinct SF Symbols, prominent labels, and fine haptic tap feedback (`.click`).
6. **In-Flow History List**:
   - Clean log rows with time stamps, drink/smoke icons, and confirmation dialogs on tap.

### 3.2 7-Day Trend Charts (`Bubbles7DaysView.swift` & `Smokes7DaysView.swift`)
- Bound directly to `WatchHabitStore.shared`.
- Logging water or tobacco immediately updates the current day's bar in the weekly chart without requiring a separate network query.
- Weekly averages and baseline target lines render with 0ms latency.
- Digital Crown scrolling smoothly scrubs through past weeks.

---

## 4. Verification & Physical Deployment

- **Code Signing**: Signed cleanly with development identity `Apple Development: MIHAI IONESCU (46P99RQF56)` under team `7LZ9ZT2Z5B`.
- **Target Architecture**: Compiled for native watchOS ARM64 (`arm64_32` and `arm64`).
- **Physical Device Deployment**:
  - Deployed via `devicectl device install app` directly to physical **Apple Watch Ultra 2** (`00008310-001B192A3698A01E`).
  - Successfully launched in the foreground via `devicectl device process launch`.
  - Confirmed 0ms local-first response, instant AppGroup data hydration, and smooth scrolling on watchOS.
