# Android Habits Consistency Map & 7-Day Performance Parity Architecture

## 1. Overview
This document details the architectural fix and complete cross-platform parity implementation for the **Habits Tracker** in **DayOne Android** (`com.intellidream.daily`).

Previously, both the **Consistency Map (112-day heatmap / 16 full weeks)** and the **7-Day Performance bar chart** for both **Bubbles** (Water Hydration) and **Smokes** (Tobacco Harm Reduction) only displayed data for the past 1–2 days that the user had explicitly navigated to, rendering the rest of the historical window as empty (`0` / `-`). 

With this implementation, Android matches iOS 1:1 using a dual-table remote sync engine, Supabase RPC aggregation, Room database cache merging, instant (0ms) SharedPreferences persistence, and full visual parity for intensity levels and interactive detail pills.

---

## 2. Root Cause Analysis
1. **Local-Only Query on Un-synced Room Database**:
   - `HabitsRepository.kt` computed both `weeklyTrend` (7 days) and `consistencyHeatmap` (112 days) exclusively via `dao.getAllActiveLogs()`.
   - Android's `syncLogs()` previously fetched logs only for the single selected calendar date (`_selectedDate.value` from `getStartOfDay` to `getEndOfDay`).
   - Consequently, Room only stored records for the 1–2 dates the user explicitly viewed in that session. All other historical dates were missing locally.
2. **Missing Remote Consistency & Financial RPC Endpoints**:
   - iOS leverages Supabase RPC `get_habits_consistency` and `get_smokes_financials`, with fallbacks to `habits_daily_summaries` (`gte("date", startStr)`) and `habits_logs` (`gte("logged_at", startIso112)`).
   - Android lacked the data models, serialization handlers, and remote service routines to fetch and cache these aggregates.

---

## 3. Architecture & Data Contracts

### 3.1 Domain & DTO Models (`core-model/com.intellidream.daily.model.HabitModels.kt`)
- **`HabitsConsistencyRow`**: Deserializes historical consistency rows containing:
  - `date: String` (`YYYY-MM-DD`).
  - `habit_type: String` (`water` or `smokes`).
  - `total_volume_ml: Double` (deserialized via `FlexibleDoubleSerializer` supporting strings, ints, or floats).
  - `log_count: Int`.
  - `intensity_level: Int` (`0` to `4`).
  - `goal_met: Boolean`.
  - `under_limit: Boolean`.
- **`HabitsDailySummaryRow`**: Deserializes summary rows from the `habits_daily_summaries` fallback table.
- **`SmokesFinancialsRpcResult`**: Deserializes lifetime smoke cessation financials from `get_smokes_financials`:
  - `total_avoided: Double`, `money_saved: Double`, `hours_regained: Double`, `total_smoked: Double`, `days_tracked: Int`.
- **`FlexibleDoubleSerializer` & `FlexibleNullableDoubleSerializer`**:
  - Handles heterogeneous Supabase RPC responses that may return numbers as strings, integers, or floating-point literals without runtime deserialization crashes.

### 3.2 Remote Data Layer (`core-network/com.intellidream.daily.network.HabitRemoteService.kt`)
- **`fetchHabitsConsistency(userId, startDateStr, endDateStr, startIso112)`**:
  - **Primary**: Calls Supabase RPC `get_habits_consistency` with `buildJsonObject { put("p_user_id", userId); put("p_start_date", startDateStr); put("p_end_date", endDateStr) }`.
  - **Fallback 1**: Queries `habits_daily_summaries` with `gte("date", startDateStr)`.
  - **Fallback 2**: Queries `habits_logs` table directly (`gte("logged_at", startIso112)`, limit 5000) and transforms active records to daily totals.
- **`fetchSmokesFinancials(sinceIso)`**:
  - Calls Supabase RPC `get_smokes_financials` with `buildJsonObject { put("p_since", sinceIso) }` for server-calculated financial savings and cigarettes avoided.

### 3.3 Offline-First Repository Cache (`core-database/com.intellidream.daily.database.HabitsRepository.kt`)
- **Persistent Daily Totals Cache (0ms Startup)**:
  - Backed by `SharedPreferences` (`habits_daily_cache`) storing `water_daily_totals` and `smokes_daily_totals` as JSON maps.
  - Loaded synchronously upon repository instantiation, guaranteeing instant historical chart rendering before network calls finish.
- **Reactive Cache Merging**:
  - Exposes `_waterDailyTotals` and `_smokesDailyTotals` `StateFlow`s.
  - Combines remote daily aggregates with active local Room records (`HabitLogEntity`), ensuring immediate local UI updates when a user logs intake without waiting for network ACK.
- **Calculation Engines**:
  - **`calculateSevenDayHistory(today, mergedMap, target)`**: Generates 7 data points ending today with day label, value, progress, and goal status.
  - **`calculateConsistencyHeatmap(today, habitType, mergedMap, target)`**: Computes all 112 calendar cells (16 full weeks, 7 days per week), mapping values to 5 intensity levels (`0` through `4`).
- **Comprehensive Sync Flow (`syncLogs`)**:
  - Step 1: Push pending local dirty records (`synced_at == null`).
  - Step 2: Fetch current selected date logs for timeline rendering.
  - Step 3: Fetch 112-day consistency aggregates via `fetchHabitsConsistency()`, upsert active records into Room, and save merged totals to SharedPreferences.
  - Step 4: Fetch smokes financials via `fetchSmokesFinancials()` or derive from daily totals.

---

## 4. UI Polish & Visual Parity (`app/presentation/habits/HabitsMainView.kt`)

### 4.1 7-Day Performance Chart
- Displays `"-"` for days with 0 intake instead of `0L` or `0`, matching iOS styling.
- Bar coloring matches goal completion:
  - **Bubbles (Water)**: Cyan / Teal gradient when goal met; subtle translucent cyan when below goal.
  - **Smokes**: Emerald gradient when under limit; orange/red gradient when over limit.
- Formats volume intelligently: values $\ge 1000$ ml formatted as liters (e.g., `1.5L`), $< 1000$ ml formatted as `ml`.

### 4.2 112-Day Consistency Heatmap (16 Weeks)
- **Cell Intensity Matrix (1:1 with iOS)**:
  - **Bubbles (Water)**:
    - Level 0: Neutral dark gray (`Color.White.copy(alpha = 0.06f)`).
    - Level 1: 30% Cyan (`#00E5FF`).
    - Level 2: 55% Cyan (`#00E5FF`).
    - Level 3: 85% Royal Blue (`#2979FF`).
    - Level 4: Mint Green (`#00FFB2`, Goal Met).
  - **Smokes**:
    - Level 0: Neutral dark gray (`Color.White.copy(alpha = 0.06f)`).
    - Level 1: Mint Green (`#00FFB2`, $\le 50\%$ limit).
    - Level 2: Yellow (`#FFEA00`, $50\% - 80\%$).
    - Level 3: Orange (`#FF9100`, $80\% - 100\%$).
    - Level 4: Red (`#FF5252`, $> 100\%$ limit).
- **Interactive Inspection**:
  - Tapping any square in the 16-week matrix opens the interactive detail pill showing formatted date, logged volume/count, target comparison, and status tags:
    - `Goal Met ✓` / `In Progress` for Bubbles.
    - `Smoke Free ✨` / `Under Limit ✓` / `Over Limit ✕` for Smokes.
  - Includes a "View Day →" action button to navigate directly to that date's timeline.

---

## 5. Verification Matrix

| Device / Environment | Display Type | Verification Result |
| :--- | :--- | :--- |
| **Google Pixel 9 Pro Fold Emulator (`emulator-5556`)** | Inner Foldable (851dp, 2076x2152) | **Verified**: 7-Day chart and 112-Day consistency heatmap render cleanly in the right pane; UI dump confirms 16-week matrix layout and legend. |
| **Samsung Galaxy Z Fold 8 ("RADAR", `SM-F971B`)** | Physical Foldable (Inner & Cover) | **Verified**: Streamed install over adb port 5038, launched live, smooth 120Hz scrolling and responsive touch interaction on heatmaps. |
| **Google Pixel 9 Pro ("Trapper", `48231FDAP0011V`)** | Physical Compact Phone | **Verified**: Streamed install over adb port 5038, single-pane layout renders 7-day bars and consistency heatmap without clipping. |
