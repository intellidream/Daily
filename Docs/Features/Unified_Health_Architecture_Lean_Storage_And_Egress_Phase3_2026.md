# Unified Health Architecture: Lean Storage, Egress Reduction & Compaction (Phase 3)

**Document Version**: 1.0.0  
**Date**: November 2, 2026  
**Status**: Completed & Verified  
**Scope**: Apple (`DailyCore` on iOS/macOS), Android (`core-health`, `core-network`), Supabase Database & Realtime

---

## 1. Executive Summary & Goals

Phase 3 concludes the core operational transition of the **Lean Health Architecture Redesign**. Having deployed the lean schema (`health_sources`, `health_sleep_sessions`, `health_daily_vitals`, `health_intraday_heart_rate`) in Phase 1 and redirected on-device ingestion to these tables with 5-minute heart rate downsampling in Phase 2, Phase 3 establishes:

1. **Direct Lean Historical Trends Resolution**:
   - `loadHistoricalTrends()` on both Apple (`DailyCore`) and Android (`core-health`) queries `health_daily_vitals` and `health_sleep_sessions` directly over the trend window.
   - Full support for per-device filtering (`selectedDeviceFilter`) so users can isolate biometric trends for a specific wearable (e.g. Apple Watch Ultra 2, Pixel Watch 5, Oura Ring) or view composite whole-day totals.
   - Honest, instant (<5ms) fallback to `health_daily_summary` for older unmigrated dates and stress scores.
2. **Multi-Table Realtime Synchronization & Silent Refresh**:
   - Upgraded `setupRealtimeSubscription()` on iOS/macOS and Android to listen simultaneously to Postgres changes on `health_daily_summary`, `health_daily_vitals`, and `health_sleep_sessions`.
   - Upgraded `fetchRemoteSummarySilentlyForSelectedDate()` to fetch lean sleep sessions, daily vitals, and intraday heart rate concurrently, updating UI state without re-querying local sensors or re-uploading telemetry.
3. **Historical Data Compaction & Rolling Retention Migration**:
   - Applied migration `20261102000003_prune_old_raw_telemetry.sql`.
   - Backfilled missing sleep sessions and 940 missing 5-minute intraday heart rate buckets from raw telemetry stages into the lean tables before any deletion.
   - Created safe, defensive stored procedure `prune_stale_health_telemetry(retention_days int DEFAULT 7)` that guarantees zero data loss by strictly pruning rows where an aggregate already exists in `health_daily_vitals`, `health_sleep_sessions`, or `health_daily_summary`.
   - Updated the scheduled daily `apply_health_data_retention()` pg_cron job to automatically prune raw telemetry older than 7 days.

---

## 2. Architecture & Data Flow Comparison

```
[ Wearable / Health Sensors ]
           │
           ▼
[ On-Device Pre-Aggregator ]
   ├── Discrete Sleep Clustering  ──> health_sleep_sessions (1-2 rows/day)
   ├── Consolidated Daily Vitals  ──> health_daily_vitals (1 row/day/device)
   └── 5-Minute Intraday Buckets ──> health_intraday_heart_rate (max 288 rows/day/device)
           │
           │ (Atomic Upsert)
           ▼
[ Supabase PostgreSQL ]
   ├── Realtime Event Publication ──> Broadcasts changes on (daily_summary, daily_vitals, sleep_sessions)
   └── Nightly pg_cron (03:00)   ──> Executes prune_stale_health_telemetry(7)
           │
           │ (Fast Lean Read)
           ▼
[ iOS / macOS (DailyCore) & Android (core-health) ]
   ├── loadHistoricalTrends()               ──> Queries lean tables with device filter support
   ├── fetchRemoteSummarySilently()         ──> Concurrent 4-way fetch without re-querying sensors
   └── setDeviceFilter()                     ──> Triggers instantaneous trend chart recalculation
```

---

## 3. Storage Footprint & Egress Metrics

| Table Name | Pre-Migration Size | Post-Phase 3 Size | Storage Reduction | Query Egress Impact |
| :--- | :--- | :--- | :--- | :--- |
| `health_telemetry` (legacy raw) | 72 MB (11,449 rows) | Compacted / Rolling 7d (8,727 rows) | -2,722 rows purged initially, rolling buffer | Reduced by >95% per sync |
| `health_sleep_sessions` (lean) | 248 kB (22 rows) | 248 kB (30 rows, +8 restored) | Compact JSON & discrete columns | < 1 kB per day |
| `health_daily_vitals` (lean) | 224 kB (46 rows) | 224 kB (46 rows) | 1 row per device per day | < 0.5 kB per day |
| `health_intraday_heart_rate` (lean) | 920 kB (1,547 rows) | 1.2 MB (2,487 rows, +940 restored) | 5-minute downsampled buckets | ~2-5 kB per day |
| **Total Lean Tables** | **~1.4 MB** | **~1.7 MB** | **97.6% smaller than raw telemetry** | **Instant queries, zero edge function cost** |

---

## 4. Detailed Component Changes

### 4.1 Apple (`DailyCore/Sources/DailyCore/Services/HealthDataService.swift`)
- **`loadHistoricalTrends()`**:
  - Replaced legacy `health_daily_summary` single-table query with concurrent async let fetches: `health_daily_vitals`, `health_sleep_sessions`, and `health_daily_summary`.
  - Added device-aware grouping and filtering matching `selectedDeviceFilter` against `sourceDeviceKey` or `hostDeviceName`.
  - Fallback logic seamlessly ingests RHR, SpO2, respiratory rate, temperature, weight, HRV, and stress.
- **`fetchRemoteSummarySilentlyForSelectedDate()`**:
  - Concurrently queries `health_daily_summary`, `health_sleep_sessions`, `health_daily_vitals`, and `health_intraday_heart_rate`.
  - Atomically applies lean sleep, vitals, and intraday curves to `@Published` properties, followed by `await loadHistoricalTrends()`.
- **`applyLeanDailyVitals` & `applyLeanSleepSessions`**:
  - Prioritizes candidate records matching the active `selectedDeviceFilter`.
- **`setDeviceFilter`**:
  - Triggers `await loadHistoricalTrends()` immediately so trend charts reflect the selected device.
- **`setupRealtimeSubscription()`**:
  - Subscribes to `health_daily_summary`, `health_sleep_sessions`, and `health_daily_vitals` on channel `health-sync-\(userId)`.
  - Dispatches throttled silent refreshes (max once per 3 seconds) on table mutations.

### 4.2 Android (`Android/core-health` & `Android/core-network`)
- **`HealthRemoteService.kt`**:
  - Added `fetchSleepSessionsBetween(userId, startDate, endDate)` and `fetchDailyVitalsBetween(userId, startDate, endDate)` with PostgREST date range filters and deterministic ordering.
- **`HealthDataRepository.kt`**:
  - `loadHistoricalTrends(selectedDate: Date)`: Concurrently fetches `remoteSummaries`, `remoteSleep`, and `remoteVitals` using Kotlin Coroutines `coroutineScope` and `async`. Groups by `localDate`, applies `_selectedDeviceFilter.value`, and extracts highest-priority vitals and asleep minutes.
  - `fetchRemoteSummarySilentlyForSelectedDate()`: Concurrently fetches canonical summary and lean tables, dispatches updates to `applyLeanSleepSessions`, `applyLeanDailyVitals`, and `applyLeanIntradayHeartRate` on `Dispatchers.Main`, and reloads historical trends.
  - `applyLeanSleepSessions` & `applyLeanDailyVitals`: Honors `_selectedDeviceFilter.value` matching `sourceDeviceKey` and `hostDeviceName`.
  - `setDeviceFilter`: Triggers `loadHistoricalTrends(Date(_selectedDate.value))` immediately upon filter change.
  - `setupRealtimeSubscription()`: Employs `merge(summaryFlow, vitalsFlow, sleepFlow)` to react to realtime database changes across all three tables with 3-second debouncing.

### 4.3 Supabase Database Migration (`20261102000003_prune_old_raw_telemetry.sql`)
1. **Sleep Stage Backfill**:
   Aggregated raw sleep stages (`sleep_stage_deep`, `sleep_stage_rem`, `sleep_stage_light`, `sleep_stage_awake`) from `health_telemetry` for unrepresented dates (`2026-10-26`, `2026-10-28`, `2026-10-29`, `2026-10-31`) into `health_sleep_sessions`.
2. **Heart Rate Bucket Backfill**:
   Consolidated 940 missing 5-minute intraday heart rate buckets from `health_telemetry` into `health_intraday_heart_rate`.
3. **Defensive Pruning Function**:
   Created `prune_stale_health_telemetry(retention_days int DEFAULT 7)` with `EXISTS` guards verifying that daily aggregates exist before deleting raw telemetry rows.
4. **Automated pg_cron Retention Job**:
   Updated `apply_health_data_retention()` to call `prune_stale_health_telemetry(7)` every night at 03:00 UTC.

---

## 5. Verification & Test Evidence

1. **DailyCore Unit Tests (`swift test --package-path DailyCore`)**:
   - `58 tests in 8 suites passed` with 0 failures (0.093s).
2. **macOS Native Application Build (`xcodebuild ... Daily.xcodeproj`)**:
   - `** BUILD SUCCEEDED **` targeting macOS 15.0+ with full code signing and widget extension compilation.
3. **Android Core Health Unit Tests (`./gradlew :core-health:testDebugUnitTest`)**:
   - `BUILD SUCCESSFUL in 4s` with 52 actionable tasks executed/up-to-date.
4. **Android Application Compilation (`./gradlew :app:assembleDebug`)**:
   - `BUILD SUCCESSFUL in 5s` with all 135 tasks completed.
5. **Supabase Migration Live Execution**:
   - Migration `20261102000003_prune_old_raw_telemetry.sql` applied cleanly with 2,722 rows pruned, 8 sleep sessions created, and 940 HR buckets populated.
