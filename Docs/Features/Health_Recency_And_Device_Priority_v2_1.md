# Lean Health v2.1 — Recency-First Arbitration, Hourly Activity Envelope & Unified Device Priority

**Date:** November 5, 2026  
**Engine Version:** `2.1`  
**Platforms:** Supabase (`PostgreSQL` + `health-engine` Edge Function), `DailyCore` (`iOS` / `macOS` / `watchOS`), `Android` (`Jetpack Compose` + `Health Connect`), `Windows 11` (`WinUI 3`)

---

## 1. Motivation & Problem Statement

In multi-wearable real-world usage (e.g., wearing **Oura Ring** + **Pixel Watch 5** overnight/morning via iPhone HealthKit, then removing them and putting on **OnePlus Watch 3** paired to **Pixel 9 Pro** via Health Connect / OHealth), static priority arbitration (`#1 Oura Ring`, `#2 Pixel Watch 5`, ..., `#5 OnePlus Watch 3`) caused stale readings to overshadow active sensors:

1. **Stale Live Vitals (`Heart Rate`, `SpO2`, `Weight`)**: Static device rank selected an hours-old Oura Ring or Pixel Watch 5 value over a fresh reading captured minutes ago on OnePlus Watch 3.
2. **Watch-Switch Step Loss vs. Simultaneous-Wear Double Counting**: Picking a single top-ranked device for the entire day lost afternoon steps after switching watches, while summing daily totals double-counted steps when wearing a ring and watch simultaneously.
3. **Cross-Sensor Autonomic Stress Skew**: Stress calculation previously compared the afternoon watch's active heart rate against another device's resting heart rate or against an un-worn morning device's `0`-step hourly array (falsely classifying active walking HR as sedentary sympathetic stress).
4. **Hardcoded Priority Order**: Users had no UI to customize or reset their preferred wearable tie-break order across platforms.

All v2.1 enhancements preserve the **Lean Health 4-table schema** with **zero new database tables**, **zero increase in background polling frequency**, and **zero increase in Supabase egress**.

---

## 2. Three-Class Metric Arbitration Model (`v2.1`)

Every health metric in `"All Devices"` mode is governed by one of three deterministic classes implemented identically in `supabase/functions/health-engine/engine.ts`, `DailyCore` (`HealthDataService.swift`), `Android` (`HealthDataRepository.kt`), and `WinUI 3` (`HealthHubService.cs` / `HealthDetailPage.xaml.cs`):

### Class A — Live / Spot Metrics (Recency-First)
Applies to **`Latest Heart Rate`**, **`Current Autonomic Stress`**, **`SpO2` (`Oxygen Saturation`)**, and **`Weight`**.
- **Rule**: The device with the newest real physiological reading timestamp (`latest_hr_at` / `vitals_timestamps[metric]`) wins, regardless of static priority rank.
- **Simultaneous-Wear Tie-Breaker**: User priority order is applied **only** when two or more wearables recorded real samples within the simultaneous wear window:
  - `<= 15 minutes` for `Latest Heart Rate` (and latest 5-minute intraday HR bucket collisions).
  - `<= 30 minutes` for `SpO2` and `Weight`.
- **Anti-Sync-Inflation Guard**: Sync timestamps (`updated_at`) are never substituted when comparing against real physiological timestamps (`latest_hr_at` or `vitals_timestamps`), preventing an idle background sync of an unworn ring from masquerading as a fresh reading.

### Class B — Cumulative Activity (Hourly Active-Wearer Envelope `0..23`)
Applies to **`Steps`**, **`Hourly Steps`**, and **`Active Calories`**.
- **Rule**: For each hour `h` in `0..23`:
  - Filter candidate rows with `hourly_steps[h] > 0` (preferring dedicated wearables over phones when any wearable recorded steps in hour `h`).
  - Select the winning device for hour `h` by **Unified Device Priority** (or highest steps on equal rank).
  - Sum the 24 hourly winners, floored by `maxSingleDeviceSteps` (`totalSteps = max(sum(mergedHourly), maxSingleDeviceSteps)`) so devices reporting daily totals before hourly breakdowns never lose steps.
- **Active Calories**: Merged proportionally per hour using each device's `hourlySteps[h] / deviceHourlySum * deviceActiveCalories`, floored by `maxSingleDeviceCalories`.
- **Result**: Zero double-counting when wearing Oura Ring + Pixel Watch 5 together, and 100% step continuity when switching to OnePlus Watch 3 mid-day.

### Class C — Nocturnal & Baseline Metrics (Session Quality + User Priority)
Applies to **`Primary Sleep Session`**, **`Nightly HRV (`SDNN` / `RMSSD`)`**, **`Respiratory Rate`**, **`Wrist/Skin Temperature`**, and **`Daily Resting Heart Rate`**.
- **Rule**: Sleep clustering prefers sessions with full sleep-stage telemetry (`deep + rem + light > 0`) and breaks ties using the user's **Unified Device Priority**. Baseline recovery metrics follow the user's priority order (`1` = `#1` highest priority).

---

## 3. Autonomic Stress Accuracy Improvements

1. **Merged Hourly Activity Gating**: Sedentary vs. active HR classification uses the **Class B merged `hourlySteps[0..23]` envelope**, eliminating false high-stress spikes when a morning device sits on a desk (`0` steps) while the user walks wearing an afternoon watch.
2. **Sensor-Matched RHR Baseline**: Stress HR elevation (`currentSedentaryBpm - restingBpm`) anchors `restingBpm` to the **same sensor** that produced the active HR points (falling back to global RHR only if that sensor has not yet computed RHR), preventing cross-sensor optical PPG offset bias.
3. **Active Sensor Attribution**: `CanonicalStressSummary.source_device` reflects the active sensor driving the latest stress evaluation.

---

## 4. Database Schema, Trigger Guards & RPCs (`Supabase`)

Migration: `supabase/migrations/20261105000001_lean_health_v2_1_recency_and_priority.sql`

- **`public.health_daily_vitals`**:
  - `latest_heart_rate double precision` — raw latest BPM reading per `(user_id, local_date, source_id)`.
  - `latest_hr_at timestamptz` — exact physiological sample timestamp of `latest_heart_rate`.
  - `vitals_timestamps jsonb NOT NULL DEFAULT '{}'::jsonb` — exact sample timestamps per spot vital (`spo2`, `weight_kg`, `resting_heart_rate`, `hrv_sdnn_ms`, `hrv_rmssd_ms`, `respiratory_rate`, `body_temp_delta_c`).
  - Updated `trg_fn_guard_health_daily_vitals()` so `COALESCE(NEW.latest_hr_at, OLD.latest_hr_at)` preserves fresher readings on partial upserts and merges `OLD.vitals_timestamps || NEW.vitals_timestamps` monotonically.
- **`public.health_sources`**:
  - `is_custom_priority boolean NOT NULL DEFAULT false` — locks user-defined order against default rank overwrites in `trg_fn_guard_health_sources()`.
  - Added `public.health_sources` to `supabase_realtime` publication for instant cross-device priority sync.
  - Normalized default priority ranks to 1-based (`1..99`).
  - Added `SECURITY DEFINER` RPCs:
    - `public.save_health_source_priorities(ordered_source_ids text[])` — atomically assigns `1..N` to `priority_sleep` & `priority_activity` with `is_custom_priority = true` across canonical sibling rows.
    - `public.reset_health_source_priorities()` — restores canonical default priority ranks and clears `is_custom_priority`.
- **`health-engine` Edge Function (`v2.1`)**:
  - Reads `public.health_sources` in parallel with sleep, vitals, and intraday HR.
  - Emits `latest_bpm`, `latest_bpm_at`, and `latest_source_device` inside `summary.cardiovascular`, plus `latest_heart_rate` inside `summary.vitals` and `source_device` inside `summary.stress`.

---

## 5. Cross-Platform Client & UI Implementation

### Upload Pipeline & Smart Engine Trigger (`iOS`, `watchOS`, `Android`)
- **Strict Upload Order**: `health_sleep_sessions` -> `health_intraday_heart_rate` -> `health_daily_vitals` -> `health-engine` invocation, ensuring all raw tables are committed before canonical recomputation.
- **Data-Change Fingerprint Debounce**: Replaced blind `180s` invocation drops with a payload-fingerprint check so any genuine change in `latestBpm`, `latestHrAt`, `steps`, or `sleep` triggers `health-engine` immediately while identical repeat syncs remain throttled.
- **`watchOS` Standalone Fix (`HealthTelemetryManager.swift`)**: Changed `HKQuantitySample` query sort to descending (`ascending: false`), filtered strictly to Apple Watch hardware samples, and populated `latest_heart_rate` + `latest_hr_at`.
- **`Android` Priority Inversion Fix (`HealthDataRepository.kt`)**: Replaced legacy `sortedByDescending` priority calls with `sortedBy { effectivePriorityRank(...) }` so rank `1` (`#1`) consistently wins ties.

### Heart & Vitals Hero, Vitals Grid & Dashboard Cards (`iOS`, `macOS`, `Android`, `WinUI 3`)
- **Heart Rate Curve Hero**: Prominently displays **`Latest BPM`** alongside exact reading time (`HH:mm`) and the active wearable badge, while preserving compact **`Daily Avg`** and **`Resting HR`** pills.
- **Vitals Grid**: Added dedicated **`Latest HR`** card with timestamp/source attribution alongside **`Resting HR`**, plus automatic `HRV (SDNN)` -> `HRV (RMSSD)` fallback for Android/Oura/Health Connect sources.
- **Dashboard & Glance Widgets**: Prefer live `Latest BPM` (falling back cleanly to `Resting HR` only if no intraday HR exists today).

### Unified Device Priority Settings (`iOS`, `macOS`, `Android`, `WinUI 3`)
- Single unified **Device Priority** list (`#1` highest priority -> `#N`) accessible both from **Settings -> Features -> Health** and directly from the **Health Hub** header/device selector.
- Supports instant **Move Up / Move Down** reordering and **Reset to Default**, persisted via `save_health_source_priorities` / `reset_health_source_priorities` RPCs, synchronized live across all devices via Supabase Realtime, and followed immediately by `health-engine` recomputation.

---

## 6. Automated Test Coverage

- **Swift (`DailyCoreTests/HealthServiceTests.swift` & `GoldenFixturesTests.swift`)**: 24/24 unit tests + golden fixtures passing (covering Class A Recency-First `> 15m` override vs `<= 15m` priority tie-break, Class B disjoint-hour sum + simultaneous-wear dedup, and custom `HealthSourceRecord` priority ranks).
- **Android (`:core-health:testDebugUnitTest` — `LeanHealthBuildersTest.kt` & `GoldenFixturesTest.kt`)**: 15/15 JUnit tests passing (covering Recency-First HR, Hourly Active-Wearer step envelope, custom priority tie-break, 5-min HR bucket builder, and cross-platform golden fixtures).
- **Windows / .NET 10 (`Tests/Daily.Health.Tests/HealthHubServiceTests.cs` & `GoldenFixturesTest.cs`)**: 12/12 xUnit tests passing (covering `ArbitrateLatestHeartRate` recency & tie-break, `ArbitrateHourlyActivity` disjoint vs simultaneous wear, `ArbitrateSpotVital` `SpO2` recency, SQLite cache round-trip, and golden fixtures).
