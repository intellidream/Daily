# Unified Health Architecture — Forensic Canonical Unification & Multi-Device Isolation (v2.0)

**Date**: November 2, 2026  
**Scope**: PostgreSQL / Supabase (`akkfouifxztnfwwiclwg`), `health-engine` Edge Function v2.0, Apple (`DailyCore`, `iOS`, `macOS`, `watchOS`), Android (`core-network`, `core-model`, `core-health`, `app`), and Windows 11 (`WinUI 3`).

---

## 1. Executive Summary & Root Causes Resolved

Following the initial Phase 1–4 Lean Health migration, a deep forensic audit across live PostgreSQL tables, device SQLite/Room caches, HealthKit, and Health Connect uncovered seven systemic root causes behind missing wearable telemetry, duplicate/strange device names, and leaked metrics during device switching:

1. **Android Ktor `CIO` DNS Failure (`Unable to resolve host`)**: `Trapper (Pixel 9 Pro)` and `Radar (Galaxy Z Fold 8)` had read real **Pixel Watch 5** steps and sleep (`515 min`, `20` stages) into local Room `health_telemetry`, but Ktor's `CIO` engine failed DNS resolution on Wi-Fi, trapping all wearable uploads offline.
2. **Legacy iOS Build Writing Raw Compound Rows (`health_telemetry`)**: Older device builds lacked lean-table code and continued inserting compound `"Host - Sensor"` strings (`"Trapper - J974281264b2c3d35b6191b71d63887dd"`, `"Trapper - International"`, `"Schmitz - Oura"`) into `public.health_telemetry` and `public.health_sources`.
3. **Android ISO-8601 vs Epoch `Long` Deserialization Crash**: `HealthSleepSessionRecord.startTime` / `endTime` in Kotlin expected epoch `Long` without `@Serializable(with = TimestampSerializer::class)`, causing PostgREST `TIMESTAMPTZ` responses from `public.health_sleep_sessions` to fail deserialization silently and return `emptyList()`.
4. **Wake-Date (`local_date`) Attribution Bug**: Sessions starting before midnight (e.g. `22:45` on Day `N-1`, waking `07:15` on Day `N`) were stamped with start-date instead of wake-date in `HealthConnectManager.kt` and `HealthTelemetryManager.swift`.
5. **Sticky Monotonic Step Guard (`maxOf`) & Incremental Slice Overwrites**:
   - `max(_totalStepsToday, ...)` in `HealthDataService.swift` and `HealthDataRepository.kt` prevented `All Devices` (`1,400` steps) from dropping down to a lower-step device (`312` steps) when switching filters.
   - `syncUnsyncedTelemetry` built `HealthDailyVitalsRecord` only from newly unsynced deltas rather than full-day local telemetry, risking partial overwrites of `steps` and `hourly_steps`.
6. **Cross-Device Leaks During Device Filtering**:
   - `health-engine` v1 only emitted a consolidated summary without per-device views (`all_devices_view`), and UI views on Apple, Android, and Windows leaked consolidated Sleep Efficiency, Restorative %, Sleep Verdict, Stress Score, Monkey Mood, HR Zones, and 7-day Trends when a specific device was selected.
   - Device selectors previously listed historical devices from `health_sources` even on dates when those devices recorded zero signal, and failed to reset to `All Devices` when navigating to dates lacking data for the selected filter.
7. **Windows `HealthHubService` `"Canonical"` Attribution Bug**: `FetchMetricsForDateAsync` and `GetHealthTelemetryAsync` stamped metrics and intraday points with `SourceDevice = "Canonical"`, polluting `AvailableDevices` and breaking per-device filtering on Windows 11.

---

## 2. Seven Canonical Hardware Identities

All platforms, SQL normalization triggers, and `health-engine` v2.0 strictly normalize every raw hardware/package string into **7 canonical physical devices** (excluding virtual/desktop/platform aggregators like `Canonical`, `Mac`, `Windows`, `Apple Health`, `Health Connect`, `Google Fit`, `StressWatch`):

| Canonical Display Name | `health_sources.id` | Device Kind | Priority | Signature Hex |
| :--- | :--- | :--- | :---: | :---: |
| `Oura Ring` | `oura_ring` | Smart Ring | `100` | `#00E5FF` |
| `Apple Watch Ultra 2` | `apple_watch_ultra_2` | Smartwatch | `90` | `#FF2D55` |
| `Pixel Watch 5` | `pixel_watch_5` | Smartwatch | `90` | `#4285F4` |
| `OnePlus Watch 3` | `oneplus_watch_3` | Smartwatch | `85` | `#F50514` |
| `Schmitz (iPhone)` | `schmitz_iphone` | Smartphone | `40` | `#A2AAAD` |
| `Trapper (Pixel 9 Pro)` | `trapper_pixel9` | Smartphone | `40` | `#34A853` |
| `Radar (Galaxy Z Fold 8)` | `radar_fold8` | Smartphone | `40` | `#8E8FFA` |

---

## 3. Database & `health-engine` v2.0 Architecture

### PostgreSQL Migration (`20261102000005_canonical_unification_and_clean_lean.sql`)
- **`public.canonical_device_name(raw_source, raw_host)`**: Deterministic SQL function normalizing any raw or legacy `"Host - Sensor"` string (including obfuscated Android pedometer IDs like `J97428...`, Fitbit/Wear companion packages, Oura, HeyTap/OnePlus, Samsung Health) to the 7 canonical names, or `NULL` for virtual/desktop engines.
- **Database Guard Triggers**:
  - `trg_guard_health_sources`: Blocks virtual engines and merges canonical `display_name`.
  - `trg_guard_health_sleep_sessions`, `trg_guard_health_daily_vitals`, `trg_guard_health_intraday_hr`: Enforces canonical `source_device_key` on every `INSERT`/`UPDATE`.
  - `trg_sink_legacy_health_telemetry`: `BEFORE INSERT` trigger on `public.health_telemetry` that routes any legacy vitals/HR rows into `health_daily_vitals` / `health_intraday_heart_rate` and returns `NULL`, guaranteeing **`public.health_telemetry` remains permanently at 0 rows**.

### `supabase/functions/health-engine` v2.0
- Reads exclusively from `health_sleep_sessions`, `health_daily_vitals`, `health_intraday_heart_rate`, and `health_sources`.
- Deduplicates canonical device buckets, computes per-device Stress & HRV/RHR autonomic strain, and emits `all_devices_view` inside `health_daily_summary.summary` alongside consolidated `All Devices` metrics (`engine_version = "2.0"`).

---

## 4. Native Cross-Platform Implementation

### Apple (`DailyCore`, `iOS`, `macOS`, `watchOS`)
- **`HealthKitManager.swift`**: Queries every `HKSource` via `HKSourceQuery`, skips virtual/companion echo sources, attributes phone pedometer/vitals to `"Schmitz (iPhone)"` and ring/watch samples to `"Oura Ring"` / `"Apple Watch Ultra 2"`, restricts non-sleep vitals (`RHR`, `HRV`, `SpO2`, `RespiratoryRate`) strictly to `00:00..24:00` of the calendar day so devices worn the previous evening (`D-1 18:00..23:59`) never bleed onto day `D`, and uses `HKStatisticsCollectionQuery` (`cumulativeSum`) per source so overlapping Apple Watch + iPhone steps never double-count.
- **`HealthDataService.swift`**: Merges remote + local lean records, enforces calendar-date matching inside `groupIntradayHeartRateIntoBuckets`, scopes `availableSources` strictly to devices with signal on `selectedDate` (auto-resetting `selectedSourceFilter = nil` when absent), computes honest per-device Sleep Verdict/Tips, Stress Studio metrics, HR zones, and 7-day Trends, and purges pre-v2 UserDefaults caches.
- **`HealthTelemetryManager.swift` (`watchOS`)**: Stamps `"Apple Watch Ultra 2"` canonically and attributes overnight sleep/vitals to wake-date `local_date`.

### Android (`core-network`, `core-model`, `core-health`, `app`)
- **`SupabaseClientManager.kt` & `core-network`**: Configured shared `OkHttpClient` with a resilient Cloudflare DoH (`1.1.1.1` / `1.0.0.1`) fallback (`resilientDns`) when system/VPN Private DNS (e.g. idle Tailscale MagicDNS `100.100.1.1` on `Radar`) fails, plus `ensureSessionReady()` so cold-start PostgREST calls wait for `SessionStatus` / SharedPreferences JWT initialization instead of falling back to the anon key (`RLS` violation).
- **`LeanHealthModels.kt`, `HealthRemoteService.kt` & `AndroidManifest.xml`**: Added `TimestampSerializer` on `HealthSleepSessionRecord` `startTime`/`endTime`, `hasSignal` on `HealthDailyVitalsRecord`, explicit `onConflict` keys on PostgREST upserts, and `READ_HEALTH_DATA_IN_BACKGROUND` + `READ_HEALTH_DATA_HISTORY` permissions for lock-screen sync resiliency.
- **`HealthConnectManager.kt` & `SleepClusteringEngine.kt`**: Canonical `resolveCanonicalSourceKey`, Google Fit echo skipping, strict `00:00..24:00` daytime vitals window (preventing `D-1` device bleed), wake-date sleep attribution, and strict per-device sleep clustering without cross-device fallback.
- **`HealthDataRepository.kt`**: Room v2 maintenance purge of legacy `% - %` rows, full-day telemetry aggregation before lean upserts, `allSessions` multi-tracker sleep sync, `hrvRmssdNightly` support, date-scoped `availableSources` with auto-reset, and complete per-device isolation across Overview, Sleep, Stress, Vitals, and 7-day Trends.

### Windows 11 (`WinUI 3` & Shared C# `Models/Health`)
- **`DeviceSource.cs` & `HealthDailySummaryModels.cs`**: 1:1 canonical 7-device mapping, fixed `CanonicalHeartRateZones` (`resting`/`fat_burn`/`cardio`/`peak`) and `IntradayStressPoint` (`score`), and added PostgREST models `HealthSleepSessionRecord`, `HealthDailyVitalsRecord`, and `HealthIntradayHeartRateRecord`.
- **`HealthHubService.cs` & `HealthDetailPage.xaml.cs`**: Added parallel lean-table queries, Realtime listeners on `health_daily_vitals` and `health_sleep_sessions`, SQLite purge of pre-`2.0` summaries, date-scoped `AvailableDevices` with auto-reset to `All Devices`, and honest per-device isolation across all 5 Health Studio tabs.
