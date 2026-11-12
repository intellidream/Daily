# iOS & macOS OS Widgets Overhaul & Morning Date-Rollover Refresh (2026)

## 1. Overview
This document details the architecture and UI/UX upgrades for the **iOS and macOS WidgetKit extensions (`DailyWidgets`)** and the **iOS Morning / Date-Rollover Widget Synchronization Pipeline**:

1. **iOS Morning & "Today" Navigation Widget Refresh Fix**: Ensures that when the calendar date rolls over past midnight (`00:00`)—including when the user previously used the app after `00:00` and manually navigated back to "Yesterday"—or when the user taps **"Today"** in the Health or Habits hubs or pulls to refresh on Dashboard, `HealthDataService` and `HabitsService` immediately reset/refresh Today's telemetry, update all App Group widget snapshots (`WidgetDataCoordinator`), and reload WidgetKit timelines without requiring an app restart.
2. **Procedural Monkey Mascot in Widgets (`WidgetMonkeyMascotView`)**: Replaces the generic `"🧘‍♂️"` person emoji with the authentic Daily procedural vector monkey mascot across all moods (`Zen`, `Curious`, `Busy`, `Overheated`) in both `CombinedWidget` and `StressWidget`.
3. **Executive Widget (`CombinedWidget`) Full 6-Variant Overhaul**: Removes redundant outer padding so all widgets align with native Apple OS widget margins, unifies information density across Small, Medium, and Large variants (both **With Brief** and **Regular / Without Brief**), and integrates `CosmosWidgetSnapshot` alongside Sleep, Stress, Hydration, Smokes, Money, and TagDoS.
4. **Standalone Widgets Alignment (`Stress`, `Cosmos`, and All Medium & Large Variants)**:
   - Preserves the Small (`systemSmall`) layouts of `BubblesWidget`, `SmokesWidget`, `MoneyWidget`, `TagdosWidget`, and `SleepWidget` 100% untouched.
   - Aligns `StressWidget` and `CosmosWidget` Small (`systemSmall`) variants with the visual language of the other small widgets while retaining all key telemetry and adding `.systemLarge` support.
   - Upgrades Medium (`systemMedium`) and Large (`systemLarge`) variants across all 7 standalone widgets (`Bubbles`, `Smokes`, `Money`, `Tagdos`, `Sleep`, `Stress`, `Cosmos`) to occupy full horizontal and vertical space and surface rich, actionable telemetry.

---

## 2. iOS Morning / Date-Rollover & "Today" Selection Widget Refresh Fix

### Root Causes Identified
1. **Post-Midnight Manual "Yesterday" Pinning**: When the user used the app after `00:00` (so `lastKnownCalendarDay` was already the new calendar day) and manually tapped back to `Yesterday` in Health or Habits to inspect or log late-night data, `checkMidnightRolloverIfNeeded()` saw `lastKnownCalendarDay == todayStart` the next morning and did not reset `selectedDate` back to `Today`. Because `Calendar.current.isDateInToday(selectedDate)` was `false`, foreground refreshes did not write to `WidgetDataCoordinator`.
2. **Throttled / Cached Path When Tapping "Today"**:
   - In `HealthDataService.changeDate(to:)` / `jumpToToday()`, if Today's cache was within the 5-minute throttle window, `loadDataForSelectedDate` returned early via `reapplyCurrentDeviceFilter()`. However, `reapplyCurrentDeviceFilter()` only updated `updateSleepSnapshot` and omitted `updateStressSnapshot()`. Furthermore, if Today had no health records yet, stale Yesterday widget snapshots remained in `GroupDefaults`.
   - In `HabitsService.changeDate(to:)` / `jumpToToday()`, switching back to Today called `loadDataForSelectedDate()` without `forceRefresh: true` and did not immediately push local Today totals to `saveDailyTotals()`.

### Architectural Solution
- **[`DailyCore/Sources/DailyCore/Services/HealthDataService.swift`](file:///Users/mihai/Source/Daily/DailyCore/Sources/DailyCore/Services/HealthDataService.swift)**:
  - Added `lastPastDateNavigationAt: Date?` tracking whenever the user navigates to a past date.
  - Made `checkMidnightRolloverIfNeeded()` `public` and enhanced it so that if `selectedDate` is not Today and either the calendar day rolled over OR `> 30 minutes` have elapsed since the user manually navigated to a past date (e.g., waking up in the morning after post-midnight usage), `selectedDate` automatically resets to `Date()` (Today) and invalidates `lastSuccessfulLoadTime[todayKey]`.
  - Updated `jumpToToday()` and `changeDate(to:)` to invalidate `lastSuccessfulLoadTime[todayKey]` and force a fresh load when selecting Today.
  - Updated `reapplyCurrentDeviceFilter()` so that whenever `selectedDeviceFilter == nil && Calendar.current.isDateInToday(selectedDate)`, both `WidgetDataCoordinator.shared.updateSleepSnapshot(...)` and `WidgetDataCoordinator.shared.updateStressSnapshot(...)` (or `clearStressSnapshot()`) are synchronized to App Group storage.
  - Updated the empty-day branch for Today to clear stale sleep/stress snapshots via `WidgetDataCoordinator.shared.clearSleepSnapshot()` and `clearStressSnapshot()`.
- **[`DailyCore/Sources/DailyCore/Services/HabitsService.swift`](file:///Users/mihai/Source/Daily/DailyCore/Sources/DailyCore/Services/HabitsService.swift)**:
  - Added `lastKnownTodayStart` and `lastPastDateNavigationAt` tracking and a public `checkMidnightRolloverIfNeeded() -> Bool`.
  - Invoked `checkMidnightRolloverIfNeeded()` in `willEnterForegroundNotification`, `willBecomeActiveNotification`, and `loadDataForSelectedDate`.
  - Updated `changeDate(to:)` and `jumpToToday()` so selecting Today immediately loads local Today logs, calls `saveDailyTotals()` (updating `WidgetDataCoordinator` + `WidgetCenter`), and triggers `loadDataForSelectedDate(forceRefresh: true)`.
- **[`iOS/Daily/App/DailyApp.swift`](file:///Users/mihai/Source/Daily/iOS/Daily/App/DailyApp.swift) & [`iOS/Daily/Views/Dashboard/DashboardView.swift`](file:///Users/mihai/Source/Daily/iOS/Daily/Views/Dashboard/DashboardView.swift)**:
  - On `scenePhase == .active`, `DailyApp` runs `TagdosStore.shared.loadFromStorage()`, `TagdosStore.shared.syncWithWidgets()`, `HabitsService.shared.checkMidnightRolloverIfNeeded()`, `HealthDataService.shared.checkMidnightRolloverIfNeeded()`, refreshes services, and reloads all WidgetKit timelines.
  - On pull-to-refresh (`.refreshable`) in `DashboardView`, if `HealthDataService.shared.selectedDate` or `HabitsService.shared.selectedDate` was left on a past date, it resets to `Date()` (Today) before refreshing and syncs `TagdosStore.shared.syncWithWidgets()`.

---

## 3. Executive Widget (`CombinedWidget`) Overhaul (iOS & macOS)

### Key Improvements in [`iOS/DailyWidgets/CombinedWidget.swift`](file:///Users/mihai/Source/Daily/iOS/DailyWidgets/CombinedWidget.swift) & [`MacOS/DailyWidgets/CombinedWidget.swift`](file:///Users/mihai/Source/Daily/MacOS/DailyWidgets/CombinedWidget.swift)
- **Native Edge-to-Edge Container Alignment**: Removed extra `.padding(10)` / `.padding(11)` / `.padding(14)` inside `CombinedWidgetView.body` so all 6 variants use Apple's standard `.containerBackground` margins identically to native iOS/macOS widgets.
- **Small With Brief (`smallMorningView`)**:
  - **Row 1**: Greeting header + current weather icon & temperature pill.
  - **Row 2**: Compact **Sleep** card (`totalAsleepFormatted` + `sleepScore`) on the left and a compact **Stress** indicator (`WidgetMonkeyMascotView` + `currentScore` + single-line `currentMood.rawValue`) on the right.
  - **Row 3 (Money Line)**: Compact financial status row showing Net Worth (`formattedNetWorth`), EUR equivalent, and Card balance.
  - **Row 4 (TagDoS Focus)**: Displays `2–3` important TagDoS driving/focus items across active streams (`morningFocusItems(limit: 2)`).
  - **Row 5 (Bottom Pills)**: **Hydration** (`Water`), **Smokes**, and **Cosmos** (`moon.stars.fill` + `stargazingScore%`) pills.
- **Medium With Brief (`mediumMorningView`)**:
  - Includes all information from the Small With Brief variant plus richer medium telemetry:
  - Left column: Sleep card (duration, score, bedtime/wake, RHR/HRV), Stress card (`WidgetMonkeyMascotView`, score, single-line mood, RHR/HRV), and TagDoS Focus card (`2–3` priority items + total active count).
  - Right column: Hydration tile (with interactive `+250` button and progress bar), Smokes tile (count/baseline + elapsed time + interactive `+1` button), Money tile (Net Worth Lei + EUR), and Cosmos tile (stargazing score, verdict, moon phase & illumination).
- **Large With Brief (`largeMorningView`)**:
  - Full 5-section executive dashboard: Morning Brief header with weather details, Sleep & Stress hero cards, 2x2 grid for Hydration, Smokes, Money (Net Worth + Card/Cash/Outgoing), and Cosmos (Stargazing score, verdict, moon illumination, best window), Multi-Stream TagDoS Pipeline card (`S1–S3`), and 6 interactive quick-action buttons.
- **Executive Without Brief (`smallRegularView`, `mediumRegularView`, `largeRegularView`)**:
  - Uses `WidgetMonkeyMascotView` instead of `"🧘‍♂️"`, enforces single-line stress mood labels (`lineLimit(1)` + `minimumScaleFactor(0.72)` + `fixedSize(horizontal: true, vertical: false)`), and surfaces all 7 Daily pillars (`Sleep`, `Stress`, `Hydration`, `Smokes`, `Money`, `Cosmos`, `TagDoS`) cleanly across Small, Medium, and Large sizes.

---

## 4. Standalone Widgets Overhaul (iOS & macOS)

- **`StressWidget` ([`iOS/DailyWidgets/StressWidget.swift`](file:///Users/mihai/Source/Daily/iOS/DailyWidgets/StressWidget.swift), [`MacOS/DailyWidgets/StressWidget.swift`](file:///Users/mihai/Source/Daily/MacOS/DailyWidgets/StressWidget.swift))**:
  - Added `.systemLarge` support alongside `.systemSmall` and `.systemMedium`.
  - Replaced emoji with `WidgetMonkeyMascotView`, enforced single-line mood badge, and added 4-band distribution bar + biometric cards (`Resting HR`, `HRV SDNN`, `Peak Stress`, `Readings`) in Medium and Large.
- **`CosmosWidget` ([`iOS/DailyWidgets/CosmosWidget.swift`](file:///Users/mihai/Source/Daily/iOS/DailyWidgets/CosmosWidget.swift), [`MacOS/DailyWidgets/CosmosWidget.swift`](file:///Users/mihai/Source/Daily/MacOS/DailyWidgets/CosmosWidget.swift))**:
  - Added `.systemLarge` support alongside `.systemSmall` and `.systemMedium`.
  - Aligned `smallView` with the circular top-left gauge design of the other small widgets while preserving stargazing score, verdict, moon phase, illumination, best window, cloud cover, and Kp index.
  - Upgraded `mediumView` and added `largeView` with full atmospheric telemetry (`Cloud Cover`, `Kp Index`, `Humidity`, `Visibility`), solar/lunar rise & set schedules, and visible planets.
- **`BubblesWidget`, `SmokesWidget`, `MoneyWidget`, `TagdosWidget`, `SleepWidget` (Medium & Large Variants Only)**:
  - **Small (`smallView`)**: Preserved 100% untouched as instructed.
  - **Medium (`mediumView`) & Large (`largeView`)**: Upgraded to fill full horizontal and vertical widget bounds (`.frame(maxWidth: .infinity, maxHeight: .infinity)`) with rich breakdown pills, proportional progress bars, multi-stream TagDoS pipelines (up to 3 streams in Medium, 5 in Large), nocturnal vitals (`RHR`, `HRV`, `Efficiency`) in Sleep Medium & Large, and 2x2 account/flow cards in Money Large.
