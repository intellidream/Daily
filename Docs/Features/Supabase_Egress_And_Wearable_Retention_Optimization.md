# Consumer-Only Wearable Health Architecture, 7-Day Intraday HR Retention & Cross-Platform Supabase Egress Optimization

**Date:** November 5, 2026  
**Engine Version:** `2.1`  
**Platforms:** Supabase (`PostgreSQL`, `pg_cron`, `health-engine` Edge Function), `DailyCore` (`iOS` / `macOS` / `watchOS` / `WidgetKit`), `WatchOS` (`DailyWatch`), `WearOS` (`DailyWear`), `Android` (`Jetpack Compose` + `Room` + `Health Connect`), `Windows 11` (`WinUI 3` + Shared `.NET 10` Services)

---

## 1. Motivation & Forensic Findings

Following the Lean Health v2.1 rollout, a three-part production audit across `watchOS`, `Wear OS`, PostgreSQL retention tables, and live Supabase API/Realtime traffic identified three high-impact architectural optimizations:

1. **Redundant Direct Health Uploads from Smartwatches**:
   - Companion phones (**iPhone 16 Pro / Schmitz** via Apple HealthKit + BLE, **Pixel 9 Pro / Trapper** and **Galaxy Z Fold 8 / Radar** via Health Connect / Fitbit / OHealth) already ingest full multi-sensor telemetry (`HR`, `HRV`, `SpO2`, `Sleep Stages`, `Steps`, `Active Energy`, `Respiratory Rate`, `Skin Temperature`, `Weight`), buffer offline workouts/runs on the watch hardware when away from the phone, and upload once with unified source attribution.
   - Direct HealthKit -> Supabase uploads from `Apple Watch Ultra 2` (`DailyWatch`) drained watch radio battery over Wi-Fi/LTE, triggered duplicate `health-engine` invocations, and risked partial step/HR snapshots before full BLE reconciliation.
2. **Stale Rows in `public.health_intraday_heart_rate`**:
   - High-density 5-minute per-device HR buckets (`up to 288 buckets/day/device`) were previously kept for 90 days alongside `health_daily_vitals` and `health_sleep_sessions`, even though per-device 5-minute switching is only needed for the recent 7-day window and `health_daily_summary.summary.cardiovascular` already archives the canonical `All Devices` HR curve, HR zones, and min/avg/max BPM for 90 days (plus permanent scalar Trends columns).
3. **Elevated Supabase Egress Across REST, Edge Functions & Realtime**:
   - 7-day `Trends` and 14-day backfill queries executed `SELECT *` on `health_daily_summary` (~25–35 KB JSONB/day) and `health_sleep_sessions` (full `stages` hypnogram JSONB) instead of lightweight scalar projections.
   - Watch `Pulse Studio` views downloaded the full `health_daily_summary` JSONB (~26 KB) instead of the ~650 B of scalar + stress/cardio summary fields displayed on wrist.
   - `health-engine` returned the full ~35 KB computed summary body to phone uploaders that immediately discarded the HTTP response (`_ = try? await ...`).
   - Realtime `postgres_changes` listeners triggered un-debounced multi-device re-fetch storms (including self-echoes when a device received its own upload broadcast, missing `channel.subscribe()`/`user_id` filter on Android, and global cache `.Clear()` every 3 minutes on Windows).
   - PostgREST `UPSERT`/`INSERT`/`PATCH` calls defaulted to `Prefer: return=representation` even when callers ignored the returned rows.
   - Non-Health sync pipelines (`SyncService.cs`, `TagdosStore.swift`, `TagdosService.cs`, `SmartLedgerStore.swift`, `FinancesService.cs`, `FinanceRemoteService.kt`, `SavedArticlesService.swift`, `NewsRemoteService.kt`) performed full-table pulls or full-collection pushes instead of incremental `updated_at` watermarks and single-item dirty upserts.
   - Android's `NewsRepository` seeded `"seed_*"` non-UUID IDs and empty `createdAt = ""` strings into `rss_subscriptions`, causing `POST /rest/v1/rss_subscriptions` to fail with HTTP `400` and stay `isDirty = true` across every sync cycle.

---

## 2. Pillar 1 — 100% Consumer-Only Smartwatches for Health (`watchOS` & `Wear OS`)

- **Zero Direct Health Uploads from Wrist**:
  - `WatchOS` (`DailyWatchApp.swift`, `HealthTelemetryManager.swift`): Disabled HealthKit observer queries, background delivery registrations, and direct Supabase uploads to `health_daily_vitals`, `health_intraday_heart_rate`, `health_sleep_sessions`, and `health-engine`. Local foreground HealthKit reads remain available strictly for on-wrist UI responsiveness while `WatchPulseStore` consumes canonical `health_daily_summary` telemetry from Supabase (cached in App Group `UserDefaults` with a 15-minute TTL + manual refresh button).
  - `WearOS` (`WatchPulseRepository.kt`): Confirmed 100% consumer-only for Health (`Pulse Studio`), reading canonical summaries with local `SharedPreferences` caching and 15-minute TTL throttling.
- **Standalone Watch Actions Preserved**:
  - Direct Wi-Fi/LTE Supabase sync and offline queue replay (`OfflineSyncManager.swift`, `WatchHabitStore.swift`, `WatchTagdosStore.swift`, `WatchSmartLedgerStore.swift`) remain 100% active for **Habits (`Water` & `Smokes`)**, **TagDoS**, and **Smart Ledger**.
- **Zero-Network Watch Complications (`DailyWatchWidget.swift`)**:
  - Switched `WidgetKit` timeline provider to read instant local App Group `UserDefaults` hydrated by `DailyWatch` / companion `WCSession`, eliminating background widget REST calls and watch battery wakeups.
- **Bounded Pairing Polling (`WatchSessionManager.swift` & `WatchSessionManager.kt`)**:
  - Capped 2.5-second pairing PIN polling to 120 attempts (5 minutes) so uncompleted pairing screens never poll indefinitely.

---

## 3. Pillar 2 — 7-Day Rolling Retention on `health_intraday_heart_rate` + 90-Day Curve Preservation

Migration: `supabase/migrations/20261105000002_intraday_hr_7d_retention_and_egress.sql`

- **Database Retention (`public.apply_health_data_retention()`)**:
  - Executed daily at `03:00 UTC` via `pg_cron`:
    - `public.health_intraday_heart_rate`: prunes rows where `local_date < CURRENT_DATE - INTERVAL '7 days'`.
    - `public.health_sleep_sessions`, `public.health_daily_vitals`: retain 90 days.
    - `public.health_daily_summary`: retains scalar columns (`steps`, `active_kcal`, `sleep_asleep_s`, `sleep_score`, `stress_avg`, `rhr`, `hrv_sdnn`, `hrv_rmssd`, `weight`, `spo2`) permanently and nulls heavy `summary` JSONB only after 90 days.
- **Zero-Data-Loss Historical Curve Guards (Days `8..90`)**:
  - **`health-engine` (`supabase/functions/health-engine/engine.ts`)**: When recomputing a historical day (`>7` days old) where `health_intraday_heart_rate` is empty and no single-device filter is active, `archivedCardiovascular` preserves the existing `summary.cardiovascular` curve (`intraday_hr`), `hr_zones`, `avg_bpm`, `min_bpm`, `max_bpm`, and `resting_hr_bpm` from `health_daily_summary`.
  - **`DailyCore` (`HealthDataService.swift`)**: Skips querying/uploading `health_intraday_heart_rate` for dates older than 7–8 days, and preserves `summary.cardiovascular` when `intradayHRBuckets` is empty in `All Devices` mode.
  - **`Android` (`HealthDataRepository.kt`)**: Added `resolveArchivedCardiovascularFallback(...)` inside `applyLeanIntradayHeartRate(...)` so `All Devices` preserves the archived `summary.cardiovascular` curve and zones when 5-minute buckets are absent, plus 7-day upload / 8-day fetch cutoffs.
  - **`WinUI 3` (`HealthHubService.cs`)**: Short-circuits `GetLeanIntradayHeartRateAsync` for dates `>8` days old (0 HTTP requests) and reconstructs single-day `"heart_rate"` telemetry directly from `Summary.Cardiovascular.IntradayHeartRate` inside `GetHealthTelemetryAsync` even when `health_daily_vitals` still has 90-day hourly steps.

---

## 4. Pillar 3 — Cross-Platform Supabase Egress Optimizations

### 4.1 Scalar Column Projections, Slim Watch Payloads & Compact Engine Responses
- **Scalar `Trends` & Backfill Queries (~93% Smaller Payloads)**:
  - Replaced `SELECT *` on multi-day `health_daily_summary` range queries with scalar column projections (`id,user_id,local_date,computed_at,engine_version,raw_watermark,steps,active_kcal,sleep_asleep_s,sleep_score,stress_avg,rhr,hrv_sdnn,hrv_rmssd,weight,spo2`) across `DailyCore` (`HealthDataService.swift`), `Android` (`HealthRemoteService.kt`), and `WinUI 3` (`HealthHubService.cs`).
  - Replaced `SELECT *` on multi-day `health_sleep_sessions` range queries with scalar stage-summary columns (omitting the heavy `stages` JSONB array) and added `hasGranularSleepStages` / `HasGranularSleepStages` helpers across Swift, Kotlin, and C# models so stage-capable wearables are still accurately detected when `stages` is omitted.
  - Added 30-minute in-memory `Trends` range caches across `DailyCore`, `Android`, and `WinUI 3` (with live Today overlay and SQLite historical hit detection on Windows so previously cached historical ranges make **0 HTTP calls** while preserving existing `SummaryJson` in SQLite).
- **Slim Watch `Pulse Studio` Queries (~97% Smaller Payloads)**:
  - `WatchPulseStore.swift` (`watchOS`) and `WatchPulseRepository.kt` (`Wear OS`) now project PostgREST JSON paths (`local_date,steps,active_kcal,sleep_asleep_s,sleep_score,stress_avg,rhr,hrv_sdnn,hrv_rmssd,spo2,summary->stress->current_score,summary->stress->monkey_mood,summary->cardiovascular->latest_bpm,summary->cardiovascular->resting_hr_bpm`), reducing each watch sync from ~26 KB to ~650 B.
  - `health-engine` supports `slim_watch: true` for watch-triggered recomputations and `compact: true` (`131 B` acknowledgment JSON instead of ~35 KB) for all `DailyCore`, `Android`, and `WinUI 3` engine triggers.

### 4.2 Realtime Fan-Out Deduplication, Self-Echo Suppression & Polling Cadence
- **`DailyCore` (`HealthDataService.swift`)**:
  - Suppressed Realtime self-echoes for `10s` after local HealthKit uploads, coalesced multi-table Realtime bursts with a `5s` debounce, avoided redundant HTTP re-fetches when `health_daily_summary` Realtime payloads already carry the updated row, and moved the active fallback timer from `5m` to `15m` while Realtime is connected.
- **`Android` (`HealthDataRepository.kt`)**:
  - Fixed `setupRealtimeSubscription` by applying `filter("user_id", FilterOperator.EQ, targetUserId)` and calling `channel.subscribe()`, added `10s` upload self-echo suppression + `5s` Realtime debounce, and relaxed the active sync loop to `15m` when Realtime is joined (`5m` fallback only if disconnected).
- **`WinUI 3` (`HealthHubService.cs`, `HabitsService.cs`, `FinancesService.cs`, `TagdosService.cs`)**:
  - Stopped `PullDeltasAsync()` from calling `.Clear()` on `_memoryCache`, `_sleepCache`, `_vitalsCache`, and `_hrCache` (evicting only `today` / `_selectedDate` lean caches).
  - Moved the periodic background timer from `3m` to `15m`, added `5s` debounce on `OnRealtimeLeanTableReceived`, added single-flight `GetOrAdd` deduplication on `GetLeanSleepSessionsAsync`, `GetLeanDailyVitalsAsync`, `GetLeanIntradayHeartRateAsync`, and `GetHealthSourcesAsync` (eliminating parallel cold-start stampedes from `SmartBriefingService`), and stopped tearing down/re-subscribing joined Realtime channels on routine `AuthState.TokenRefreshed` events.

### 4.3 Minimal Write Representations & Upload Fingerprint Deduplication
- Added `returning: .minimal` (`supabase-swift`), `ReturnType.Minimal` (`postgrest-csharp`), and `Prefer: return=minimal` (raw REST/RPC calls) across `DailyCore`, `WatchOS`, `Android`, and shared `.NET` services (`SyncService.cs`, `TagdosService.cs`, `FinancesService.cs`) wherever response bodies are unused.
- Added in-memory per-day upload fingerprints in `HealthDataService.swift` and `HealthDataRepository.kt` so unchanged `health_sleep_sessions`, `health_intraday_heart_rate`, `health_daily_vitals`, and `health_sources` payloads are never re-uploaded on foreground/observer wakeups.

### 4.4 Incremental `updated_at` Watermarks & Non-Health Sync Fixes
- **PostgreSQL `updated_at` Triggers & Indexes (`20261105000002`)**:
  - Backfilled `updated_at`, set `DEFAULT timezone('utc'::text, now())`, attached `trg_fn_touch_updated_at_utc()`, and created `(user_id, updated_at)` indexes on `habits_daily_summaries`, `habits_logs`, `habits_goals`, `rss_subscriptions`, `rss_saved_articles`, and `smart_ledgers`.
- **Incremental Sync & Single-Row Dirty Pushes**:
  - `SyncService.cs`: Added incremental `updated_at` watermarks on `habits_logs`, `habits_goals`, `rss_subscriptions`, and `smart_ledgers`, `is_deleted=false` cold filtering on `rss_saved_articles`, lightweight `.Select("id,updated_at")` conflict checks on `smart_ledgers`, and a 24-hour throttle on `PruneRemoteLogsAsync`.
  - `TagdosStore.swift` & `TagdosService.cs`: Replaced full-collection re-uploads on single task/note edits with single-row upserts + `6s` Realtime self-echo suppression and `2.5s` debounce.
  - `SmartLedgerStore.swift`, `FinancesService.cs`, `FinanceRemoteService.kt`: Eliminated full `SELECT * FROM smart_ledgers` pre-checks before upserting by caching the canonical ledger UUID per user and querying `.Select("id")` once on cold miss.
  - `SavedArticlesService.swift`, `NewsService.swift`, `NewsRemoteService.kt`: Added incremental `updated_at` watermarks and `is_deleted=false` cold-pull filters.
  - `HabitsService.swift`: Added `120s` foreground sync cooldown and `15m` TTL on consistency history & preferences fetches.
- **Android `POST 400 /rest/v1/rss_subscriptions` Fix (`NewsModels.kt`, `NewsRepository.kt`)**:
  - Changed `createdAt` default from `""` to `null` (avoiding PostgreSQL `invalid input syntax for type timestamp with time zone: ""`), replaced `"seed_*"` feed IDs with deterministic UUIDv3 strings, skipped seeding local rows under `"guest"`, and added an automatic self-healing migration in `syncWithSupabase` that purges `"guest"` rows and upgrades legacy `"seed_*"` IDs to valid UUIDs.

---

## 5. Automated Test Verification

- **Swift (`DailyCoreTests`)**: All 65 Swift Testing + XCTest suites passing (`swift test --package-path DailyCore`), including `testArchivedCardiovascularCurvePreservedAfter7DayRetention` and `testScalarSleepProjectionHasGranularStages`.
- **Android (`:core-health:testDebugUnitTest`, `:core-database`, `:core-network`)**: All JUnit tests + Kotlin compilation passing, including `testArchivedCardiovascularCurvePreservedAfter7DayIntradayPrune` and `testScalarSleepAndSummaryProjectionsDecodeCleanly`.
- **Windows / .NET 10 (`Tests/Daily.Health.Tests`)**: All xUnit tests passing, including `TestHistoricalIntradayHeartRatePreservedAfter7DayRetention` and `TestScalarSleepProjectionDetectsGranularStages`.
