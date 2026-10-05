# Unified Health & Vitals — Phase P5: Android Data Layer & UI Parity

**Document Version:** 1.0  
**Date:** October 5, 2026  
**Status:** Completed & Verified Live on Android Emulator (`Medium_Phone_API_36.1`)  
**Scope:** Android (`Android/core-model`, `Android/core-database`, `Android/core-network`, `Android/core-health`, `Android/app`)

---

## 1. Executive Summary

Phase P5 brings the native Android application into **complete mathematical and architectural parity** with the canonical backend architecture established in P1–P3 and the iOS implementation in P4:
1. **Canonical Schema Ingestion**: Android natively ingests canonical daily summaries from `public.health_daily_summary` (`summary_version = 1`) via `HealthRemoteService`.
2. **Room Database Cache (`health_daily_summary_cache`)**: Persists daily summary payloads locally in Room, providing instantaneous (<300ms) cold start rendering and offline availability.
3. **Reactive Realtime Sync**: Connected to Supabase Realtime on `public.health_daily_summary`, instantly updating UI states when the canonical engine computes a new summary.
4. **Local Fallback Engines Maintained**: Local on-device Kotlin engines (`SleepClusteringEngine`, `calculateDailySteps`, `StressAnalysisEngine`) remain fully functional as provisional fallbacks.
5. **Zero Fake / Synthetic Data**: Eliminated `generateHistoricalValue` and random metric generation. When telemetry is absent, honest empty states (`--`, "No Telemetry", "No Sleep Data Recorded") are rendered.
6. **UI Parity Gaps Closed**: Implemented `StressOverviewPreviewCard` on the Overview tab with the mini `MonkeyMascotView` (`MonkeySize.MINI`), autonomic balance indicator, and deep-link tap to Stress Studio. Added device type leading icons in `DeviceSelectorMenu`.

---

## 2. Architecture & Data Flow

```
┌────────────────────────────────────────────────────────┐
│             Android Health & Vitals Hub                │
└────────────────────────────────────────────────────────┘
                           │
             ┌─────────────┴─────────────┐
             ▼                           ▼
┌─────────────────────────┐   ┌──────────────────────────┐
│   Room Database Cache   │   │  Supabase Remote Service │
│ (health_daily_summary)  │   │  (health_daily_summary)  │
└─────────────────────────┘   └──────────────────────────┘
             │                           │
             ▼                           ▼
┌────────────────────────────────────────────────────────┐
│                  HealthDataRepository                  │
│       • Cached-first load (<300ms)                     │
│       • Supabase Realtime subscription                 │
│       • Local Engine fallback if uncomputed            │
│       • Honest 7-day trend aggregator                  │
│       • Virtual engine upload suppression              │
└────────────────────────────────────────────────────────┘
                           │
             ┌─────────────┴─────────────┐
             ▼                           ▼
┌─────────────────────────┐   ┌──────────────────────────┐
│      OverviewSection    │   │      Sub-Studio Views    │
│ • Dual Activity Rings   │   │ • SleepStudioView        │
│ • Hourly Step Cadence   │   │ • StressStudioView       │
│ • SleepOverviewPreview  │   │ • VitalsSection          │
│ • StressOverviewPreview │   │ • HealthTrendsView       │
│ • VitalsGrid            │   │                          │
└─────────────────────────┘   └──────────────────────────┘
```

---

## 3. Key Components & Implementation Details

### A. Core Models (`core-model`)
- **`HealthDailySummaryModels.kt`**:
  - `HealthDailySummaryRecord`: Database record mapping to `public.health_daily_summary` (`user_id`, `local_date`, `computed_at`, `engine_version`, `raw_watermark`, `steps`, `active_kcal`, `sleep_asleep_s`, `sleep_score`, `stress_avg`, `rhr`, `hrv_sdnn`, `hrv_rmssd`, `weight`, `spo2`, `summary`).
  - `DailyHealthSummaryPayload`: Root JSON payload containing `sleep`, `activity`, `cardiovascular`, `stress`, and `vitals`.
  - `CanonicalSleepSummary`, `CanonicalSleepGuidance`, `CanonicalSleepVerdict`, `CanonicalSleepTip`, `CanonicalSleepAIContext`.
  - `CanonicalActivitySummary`, `CanonicalCardiovascularSummary`, `CanonicalStressSummary`, `CanonicalHeartRateZones`, `CanonicalAutonomicBalance`, `CanonicalStressDrivers`.
- **`HealthModels.kt` & `StressModels.kt`**:
  - Enabled `@OptIn(ExperimentalSerializationApi::class)` and `@JsonNames` for dual snake_case / camelCase deserialization across `SleepStageRecord`, `SleepSession`, `NapSession`, `IntradayHeartRatePoint`, and `IntradayStressPoint`.

### B. Room Database Cache (`core-database`)
- **`HealthEntities.kt`**:
  - `HealthDailySummaryEntity` (table `health_daily_summary_cache`, indexes on `user_id, date_key` [unique] and `date_key`).
- **`HealthDaos.kt`**:
  - `HealthDailySummaryDao`:
    - `upsertSummary(entity: HealthDailySummaryEntity)`
    - `getSummary(userId: String, dateKey: String): HealthDailySummaryEntity?`
    - `getSummariesInRange(userId: String, startDateKey: String, endDateKey: String): List<HealthDailySummaryEntity>`
- **`DailyDatabase.kt`**:
  - Registered `HealthDailySummaryEntity`, exposed `healthDailySummaryDao()`, bumped database version to `8`.

### C. Remote Service (`core-network`)
- **`HealthRemoteService.kt`**:
  - `fetchDailySummary(userId: String, date: String): DailyHealthSummaryPayload?`
  - `fetchDailySummariesBetween(userId: String, startDate: String, endDate: String): List<HealthDailySummaryRecord>`
  - `triggerCanonicalEngine(date: String): Boolean`
  - Exported Room and Supabase dependencies via `api()` to consuming modules.

### D. Repository Layer (`core-health`)
- **`HealthDataRepository.kt`**:
  - Injected `HealthDailySummaryDao`.
  - `loadDataForSelectedDate`: Checks Room cache first, then Supabase remote summary, falling back to local computation if pending.
  - `applyCanonicalSummary`: Unpacks canonical sleep, activity, cardiovascular, stress, and vitals into reactive `StateFlow`s.
  - `setupRealtimeSubscription`: Subscribes to Supabase Realtime changes on `health_daily_summary` for the active user.
  - `loadHistoricalTrends`: Reads 7-day history honestly from Room cached summaries and Supabase summary records.
  - Removed `generateHistoricalValue` entirely.
  - `syncVitalsToSupabase` & `syncUnsyncedVitals`: Suppresses virtual/computed engine records (`stress-engine`, `computed`, `canonical`, `habits`, and virtual devices).

### E. UI Presentation Parity (`app`)
- **`HealthMainView.kt`**:
  - Created `StressOverviewPreviewCard` on `OverviewSection` matching iOS design with mini `MonkeyMascotView` (`MonkeySize.MINI`), autonomic balance indicator, level badge, and tap interaction to open Stress Studio.
  - Added leading icons to `DeviceSelectorMenu` (`Icons.Rounded.Devices`, `Icons.Rounded.Favorite`, `Icons.Rounded.Watch`, `Icons.Rounded.Edit`).

---

## 4. Verification & Testing

### A. Unit Tests
- Executed `./gradlew testDebugUnitTest` and `:core-health:testDebugUnitTest --tests "*GoldenFixturesTest*"`.
- Result: **100% tests passed** across all modules.

### B. Live Emulator Inspection (`Medium_Phone_API_36.1` / `emulator-5554`)
- **Overview Tab**: Activity Rings (0 / 10,000 steps, 0 kcal), Step Cadence Histogram, Sleep Card (empty fallback), Stress & Autonomic Balance Card (`-- No Telemetry` with mini Monkey mascot), Vitals Grid.
- **Sleep Studio**: Honest empty state ("No Sleep Data Recorded").
- **Stress Studio**: Animated breathing Zen Monkey mascot, `-- / 100 STRESS`, "NO TELEMETRY RECORDED", Autonomic Tone Telemetry card, and Stanford Huberman Physiological Sigh guided breathwork player.
- **Trends Tab**: 7-day evolution bars with honest `--` metrics (zero synthetic numbers).
- **Device Selector Menu**: Dropdown displaying device type leading icons with checkmarks.
