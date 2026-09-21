# iOS Combined Widget, Smart Briefing Refinements & Swipeable Hub Tabs

## 1. Overview

This document details the architecture and implementation of the combined multi-metric iOS widget, morning summary briefing integration, Smart Briefing frequency safeguards, OpenWeather SF Symbol condition mapping, and fluid swipeable hub navigation.

---

## 2. Combined iOS Widget (`CombinedWidget`)

### 2.1 Multi-Metric Architecture
The Combined Widget aggregates data across five major daily domains into a single high-density widget supporting `.systemSmall`, `.systemMedium`, and `.systemLarge`:
- **Water Tracker**: Daily target, current progress, remaining intake, and completion percentage.
- **Smokes Tracker**: Daily count, target limit, delta vs limit, and color-coded status (green for within target, orange/red for exceeding).
- **Sleep Studio**: Duration (hours & minutes), calibrated restorative sleep score, bedtime / wake-up interval, and efficiency indicator.
- **Money / Net Worth**: Total net worth formatted concurrently in Romanian Leu (`RON`) and Euro (`EUR`), with daily change delta.
- **TagDoS Focus**: Current active stream, top pending actionable tasks, and completion ratio.

### 2.2 Diurnal Modes (Morning Briefing vs Regular)
- **Morning Mode (05:00 - 11:59)**:
  - The widget transforms into a compact Morning Summary Card.
  - Displays greeting, weather condition with SF Symbol and temperature, key health readiness highlight, and top focus priority.
  - Tapping anywhere on the morning card deep-links directly via `daily://summary` into the full interactive Smart Briefing modal sheet.
- **Regular Mode (12:00 - 04:59)**:
  - Small: Executive 3-Ring Gauges (Sleep score %, Water hydration %, Smokes quota usage) + full-width Net Worth pill concurrently in RON and EUR + TagDoS priority stream pill. Eliminates excess inner padding to maximize edge-to-edge canvas density.
  - Medium: 4-column balanced card stack featuring icons, primary metrics, sub-labels, and progress indicators.
  - Large: Comprehensive control panel featuring deep telemetry cards for Water, Smokes, Sleep, Finances (dual currency), and a 2-stream TagDoS checklist preview.

### 2.3 Shared Data Coordinator (`WidgetDataCoordinator`)
- Extended `WidgetDataCoordinator.fetchCombinedSnapshot()` to assemble `CombinedWidgetSnapshot` concurrently from App Group shared storage (`group.com.intellidream.daily`).
- Bundles:
  - `WaterWidgetSnapshot`
  - `SmokesWidgetSnapshot`
  - `SleepWidgetSnapshot`
  - `MoneyWidgetSnapshot`
  - `TagdosWidgetSnapshot`
  - `BriefingSummarySnippet` (composed of `headline`, `weatherSummary`, `weatherIcon`, `temperature`, `keyFocus`)

---

## 3. Smart Briefing Refinements

### 3.1 Strict Once-Per-Day Automatic Presentation
- **Problem**: Previously, morning auto-presentation evaluated hash mismatches of data metrics, causing the briefing sheet to repeatedly present every time the app became active or on launch if water or vitals updated.
- **Fix**:
  - Enforced a strict day-key guard in `SmartBriefingService.checkAutomaticMorningPresentation()`:
    ```swift
    guard lastShownDay != todayKey else { return false }
    ```
  - Removed volatile hash tracking that invalidated the display state within the morning window.
  - Automatically records the dismissal / read status for `todayKey` in `markBriefingAsRead()`.
  - Android parity: Aligned `SmartBriefingRepository.kt` with equivalent `last_shown_day` validation.

### 3.2 Dynamic OpenWeather SF Symbol Mapping
- **Problem**: OpenWeather condition codes (`01d`, `02d`, `10d`, etc.) were previously passed raw to `Image(systemName:)`, causing broken glyphs in the Weather card.
- **Fix**:
  - Integrated `WeatherConditionHelper.sfSymbol(for: iconCode)` and `conditionColorHex(for: iconCode)` in `SmartBriefingOverlayView.swift`.
  - Maps rain (`cloud.rain.fill`), sunny/clear (`sun.max.fill`), partly cloudy (`cloud.sun.fill`), snow (`cloud.snow.fill`), thunderstorm (`cloud.bolt.rain.fill`), and mist (`cloud.fog.fill`) to high-fidelity SF Symbols with condition-specific tinted glows.
  - Added fallback description synthesis in `buildCardItems()` ensuring the Weather card reliably renders even if Gemini AI returns an empty `weatherText` string while telemetry is present.
  - Automatically refreshes briefing data on sheet opening (`getOrGenerateBriefing(forceRefresh: true)`), removing the need for manual refresh buttons.

### 3.3 Deep Link Routing (`daily://summary`)
- Streamlined `DailyApp.swift` by removing an outer unhandled `.onOpenURL` closure that intercepted URLs before reaching child views.
- Bound `SmartBriefingService.shared` as `@ObservedObject` in `DashboardView.swift` to ensure seamless presentation of `isBriefingPresented` across deep-link activations.

---

## 4. Calm & Bounded Swipeable Hub Tabs

Refined the tab swipe mechanics to deliver a calm, weighted feel matching `FloatingGlassCapsule`:
- **Problem**: Unbounded linear coordinate mapping (`value.location.x / segmentWidth`) previously caused runaway transitions where a single swipe gesture skipped past interior tabs (such as *Sleep Studio* or *Heart & Vitals* in Health, or *Stocks* in Finances) to extreme tabs.
- **Calm Bounded Mechanics**:
  - **Natural Direction & Threshold**: Dragging right (`translation.width > 35` / `> 0`) advances to the tab to the right (+1), and dragging left (`translation.width < -35` / `< 0`) retreats to the tab to the left (-1), perfectly mirroring horizontal spatial pill arrangement and `FloatingGlassCapsule`.
  - **Single-Step Lock**: Added `hasSwitchedInDrag` state locking that allows at most **ONE** tab transition per continuous swipe, completely eliminating overshoot or skipping of interior tabs.
  - **Weighted Spring Physics**: Switched animation to `.spring(response: 0.38, dampingFraction: 0.82)` to prevent jitter, bounce, or twitchiness.
  - **Content ScrollView Swipe**: Tuned horizontal dominance guard (`abs(dx) > abs(dy) * 1.8 && abs(dx) > 55`) and preserved edge-swipe back (`startX > 60`) so vertical scrolling and list interactions remain silky-smooth.
- **Enabled Across All Hubs**:
  - **Habits Hub** (`HabitsMainView.swift`): Bubbles $\leftrightarrow$ Smokes
  - **Health Hub** (`HealthMainView.swift`): Overview $\leftrightarrow$ Sleep Studio $\leftrightarrow$ Heart & Vitals $\leftrightarrow$ Trends
  - **Finances Hub** (`FinancesMainView.swift`): World $\leftrightarrow$ Stocks $\leftrightarrow$ Money
  - **TagDoS Hub** (`TagdosNotesHubView.swift`): S1 $\leftrightarrow$ S2 $\leftrightarrow$ S3 $\leftrightarrow$ S4 $\leftrightarrow$ S5 $\leftrightarrow$ Notes

---

## 5. Verification & Testing

1. **DailyCore Unit Tests**:
   - Ran `swift test --package-path DailyCore`.
   - All 44 tests across 6 test suites passed with 0 failures.
2. **SimulaPhone Simulator**:
   - Clean Xcode build and installation.
   - Tested widget rendering across small, medium, and large layouts.
   - Tested deep link activation via `xcrun simctl openurl <sim-uuid> daily://summary` (instant presentation of morning briefing).
   - Verified swipe gestures across all four hubs.
3. **Physical Device (iPhone 16 Pro "Schmitz")**:
   - Built with Apple Development signing certificate and team provisioning profile.
   - Deployed via `xcrun devicectl device install app --device 62990754-1EE9-5A95-A45E-F4A69DA6E591`.
   - Launched and verified deep link payload activation via `xcrun devicectl device process launch`.
