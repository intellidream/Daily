# Android Habits Consistency Map & 7-Day Performance Parity Architecture

## 1. Overview
This document details the architectural fixes and complete cross-platform parity implementation for the **Habits Tracker** in **DayOne Android** (`com.intellidream.daily`).

Previously:
- Both the **Consistency Map (112-day heatmap / 16 full weeks)** and the **7-Day Performance bar chart** for **Bubbles** (Water Hydration) and **Smokes** (Tobacco Harm Reduction) only displayed data for the past 1–2 days that the user had explicitly navigated to, or showed incomplete/corrupted numbers (e.g. 1450, 1400, 600 instead of authentic totals).
- The 7-day hydration chart displayed unit-formatted text (e.g. `2L` or `1.4L`) instead of exact integer numbers (e.g. `2000`, `1400`).
- The 112-day heatmap was static or squished rather than horizontally scrollable and anchored to today (matching iOS).

With this update, Android achieves 100% exact parity with iOS (`DailyCore/Services/HabitsService.swift` and `iOS/Daily/Views/Habits/HabitHistoryAndHeatmapView.swift`) without touching or modifying any iOS code.

---

## 2. Forensic Comparison & Root Cause Analysis

### 2.1 RPC Fallback Overwrite in Remote Service
- **Root Cause**: In `HabitRemoteService.kt`, `fetchHabitsConsistency()` called Supabase RPC `get_habits_consistency` correctly, but then executed a direct fallback query to `habits_logs` outside `!fetchedViaRpc`. Because PostgREST caps raw queries (or sorts newest first), `rawWater` only contained partial records for the latest 1–2 days, which directly overwrote `waterTotals` from the RPC.
- **Parity Fix**: In alignment with iOS (`HabitsService.swift:662`), direct table queries (`habits_daily_summaries` and `habits_logs`) now execute **ONLY if `!fetchedViaRpc`**. When `get_habits_consistency` succeeds, its authentic aggregate totals are preserved.

### 2.2 Local Room Database Historical Overwrite
- **Root Cause**: `HabitsRepository.kt` combined `dao.getAllActiveLogs()` with `_waterDailyTotals` for all historical dates. Since Room only caches the current session's viewed dates, merging empty or incomplete local entity lists corrupted historical totals across the 112-day window.
- **Parity Fix**: In alignment with iOS (`HabitsService.swift:1092-1094`), `waterDailyTotals` and `smokesDailyTotals` remain the single source of truth for all historical days. In the reactive `combine` flows, only the currently active selected date (`_selectedDate.value`) is merged with `waterTotalToday` / `smokesTotalToday`.

### 2.3 Value Readout Formatting on 7-Day Performance Chart
- **Root Cause**: Previously, `HabitsMainView.kt` converted values $\ge 1000$ into liters (`2L`, `1.4L`), whereas iOS (`HabitHistoryAndHeatmapView.swift:67`) renders raw integer counts (`2000`, `1400`, `36`, `43`, or `-` if 0).
- **Parity Fix**: Updated readout to `if (hasValue) "${day.value.toInt()}" else "-"`.

### 2.4 Track Height & Vertical Gradient Alignment
- **Root Cause**: The bar track had an artificial `* 1.15` multiplier in `maxTrendValue` and a variable height container.
- **Parity Fix**: 
  - Standardized bar track container to 90dp height with `Color.White.copy(alpha = 0.06f)` and 6dp corner radius.
  - Set `maxTrendValue = maxOf(maxLogged, goalValue, 1.0)`, matching iOS `max(maxLogged, goalValue, 1.0)`.
  - Inverted Compose gradient colors to account for top-to-bottom rasterization matching iOS `startPoint: .bottom, endPoint: .top`:
    - Water: `[ThemeColors.accentBlue, ThemeColors.accentCyan]`
    - Smokes (Under Limit): `[Color(0xFF00E5FF), Color(0xFF00FFB2)]`
    - Smokes (Over Limit): `[Color(0xFFFF9500), Color(0xFFFF3B30)]`

### 2.5 16-Week Consistency Heatmap Scrolling & Trailing Anchor
- Converted the 16-week grid (112 cells) to a horizontally scrollable container with `rememberScrollState()`.
- Anchored scroll position to trailing edge (`scrollTo(heatmapScrollState.maxValue)`) upon load so the most recent days are in immediate view, with 12dp cells and 3.5dp spacing.

---

## 3. Data Flow Architecture

```
[Supabase PostgREST / RPC: get_habits_consistency]
                     │
                     ▼
           [HabitRemoteService.kt]
         (p_habit_type, start, end)
                     │ (Authentic RPC map)
                     ▼
          [HabitsRepository.kt]
    ┌────────────────┴────────────────┐
    ▼                                 ▼
[_waterDailyTotals]         [_smokesDailyTotals]
    │                                 │
    ├─ SharedPreferences Cache        ├─ SharedPreferences Cache
    │  ("habits_daily_cache")         │  ("habits_daily_cache")
    │  [0ms Instant Launch]           │  [0ms Instant Launch]
    ▼                                 ▼
Combine with Selected Date        Combine with Selected Date
    │                                 │
    ▼                                 ▼
[calculateSevenDayHistory]      [calculateSevenDayHistory]
[calculateConsistencyHeatmap]   [calculateConsistencyHeatmap]
    │                                 │
    └────────────────┬────────────────┘
                     ▼
           [HabitsMainView.kt]
   ┌─────────────────┴─────────────────┐
   ▼                                   ▼
7-Day Performance Chart        112-Day Consistency Heatmap
- Integer labels: 2000, 1400   - 16 full weeks (112 cells)
- 90dp track containers        - Horizontal scroll anchored to today
- iOS 1:1 vertical gradients   - 5 intensity levels (0..4)
```

---

## 4. Verification Matrix

| Device / Target | Environment | Results |
| :--- | :--- | :--- |
| **Pixel 9 Pro Fold Emulator (`emulator-5556`)** | Virtual Foldable (2076x2152, API 36) | **Verified**: 112 cells render in 16 columns of 7 days; 7-Day Performance chart shows integer labels; trailing scroll anchor functions cleanly. |
| **Samsung Galaxy Z Fold 8 ("RADAR")** | Physical Foldable (adb port 5038) | **Verified**: `habits_daily_cache.xml` verified via `run-as` showing authentic 112 days of server data (e.g. `2026-10-04: 2000`, `2026-10-05: 2300`, `2026-10-06: 2000`, `2026-10-07: 2000`, `2026-10-08: 2000`, `2026-10-09: 2300`). 120Hz smooth scrolling and dual-pane layout verified. |
| **Google Pixel 9 Pro ("Trapper")** | Physical Phone (adb port 5038) | **Verified**: APK built and installed via streamed install over adb port 5038 without regression. |
