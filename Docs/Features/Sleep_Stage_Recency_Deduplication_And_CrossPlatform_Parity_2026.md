# Sleep Stage Recency Deduplication, Sync Reclassification & Cross-Platform Parity

**Date:** November 15, 2026  
**Scope:** Option 1 (`Varianta 1`) — Native HealthKit / Health Connect Sleep Stage Attribution, UTC Serialization, Reclassification Merge Guards & Cross-Platform Rounding Parity  
**Platforms:** `iOS` / `macOS` / `watchOS` (`DailyCore`), `Android` / `Wear OS`, `Windows 11` (`WinUI 3`), `Supabase` (`health-engine` + PostgreSQL migration)

---

## 1. Root Cause Analysis

When third-party companion apps (e.g., Oura App writing into Apple Health / HealthKit, or wearables writing into Android Health Connect) write sleep stages across multiple sync passes, overlapping or refined stage intervals can coexist briefly or remain un-collapsed:

1. **Inverted Deduplication Order (Stale Overwriting Fresh)**: Previously, stage interval subtraction processed earlier/longer segments in start-time order (`seen` interval clipping) without ordering by sample recency, allowing older initial passes or un-coalesced fragmented blocks to mask newer reclassified stages (`REM`, `Deep`, `Light`), leaving adjacent identical-stage fragments and missing minutes in Daily compared to Apple Health.
2. **Merge Guard Blocking Legitimate Same-Host Reclassifications**: `mergeLeanSleepSessions` blocked updates whenever a newly recalculated sleep session had slightly fewer asleep seconds than the cached/remote value, locking stale stage totals (`REM` / `Deep`) while also risking accidental overwrites during transient short-duration sync windows, and omitting stage totals (`deepSeconds`, `remSeconds`, `lightSeconds`, `awakeSeconds`) from dirty-check fingerprints. Stale local cache also merged *after* fresh silent Supabase fetches.
3. **HealthKit Query Ordering Without `creationDate`**: `HKCategorySample` (`HKObject`) has no public `.creationDate` property in HealthKit; sorting by `startDate` via `HKSampleQuery` discarded HealthKit's insertion order.
4. **Timezone-Naive Stage Timestamp Drift & Integer Truncation Skew**: ISO timestamps serialized or received without explicit `'Z'` UTC designators could drift across clients when parsed with local assumptions (`DateTime.TryParse` without `AssumeUniversal`), and integer truncation (`seconds / 60`) caused `1m` display discrepancies across widgets, watches, and WinUI compared to `Math.Round` / `round()`.
5. **`health_sleep_sessions.ingested_at` on `UPDATE`**: Upserting reclassified stages updated existing session columns without refreshing `ingested_at`, preventing delta queries ordered/filtered by `ingested_at` from detecting stage updates.

---

## 2. Implemented Fixes

### 2.1 Apple Ecosystem (`DailyCore`, `iOS`, `macOS`, `watchOS`)
- **`iOS/Daily/Services/HealthKitManager.swift`**: Switched `fetchSleepStages(targetDate:)` from `HKSampleQuery` to `HKAnchoredObjectQuery(..., anchor: nil, limit: HKObjectQueryNoLimit)`, preserving HealthKit anchor/insertion order and synthesizing monotonic `createdAt` timestamps (`Date(timeIntervalSince1970: 1_700_000_000.0 + Double(index))`) so newer HealthKit reclassifications override older passes.
- **`DailyCore/Sources/DailyCore/Services/SleepClusteringEngine.swift`**: Replaced `normalizeAndDeduplicateStages(_:)` with a recency-aware interval painter's algorithm (`stageSpecificity`), splitting/overwriting older intervals where newer overlapping stages exist, discarding `< 10s` slivers, and coalescing adjacent identical `stageType` segments separated by `<= 1.0s`.
- **`DailyCore/Sources/DailyCore/Models/HealthModels.swift`**: Updated `SleepStageRecord` encoding to emit explicit UTC `'Z'` fractional ISO8601 timestamps and decoding to treat timezone-naive ISO timestamps explicitly as UTC before falling back.
- **`DailyCore/Sources/DailyCore/Services/HealthDataService.swift`**: Exposed `mergeLeanSleepSessions(_:preferFreshLocal:)` allowing legitimate same-host reclassifications (`durationSeconds >= prev - 600` or improved `deep + rem` with `>= 90%` duration while still rejecting transient truncations), fixing cache vs. remote precedence (`preferFreshLocal: false` during remote hydration, `true` during live HealthKit ingestion), and expanding sync fingerprints (`signature`, `sleepFp`) to include stage durations and boundaries.
- **`WatchOS/DailyWatch/DailyWatch Watch App/WatchPulseStore.swift`**: Switched `sleepDurationFormatted` from integer truncation to nearest-minute rounding (`Int(round(Double(asleepSeconds) / 60.0))`).

### 2.2 Android & Wear OS (`core-health`, `app`, `WearOS`)
- **`Android/core-health/.../HealthConnectManager.kt`**: Populates `createdAt = record.metadata.lastModifiedTime.toEpochMilli()` and `sourceId` on sleep sessions and sleep stages read from Health Connect.
- **`Android/core-health/.../SleepClusteringEngine.kt`**: Mirrors the recency-aware stage painter's algorithm and adjacent stage coalescing.
- **`Android/core-health/.../HealthDataRepository.kt`**: Mirrors `mergeLeanSleepSessions(..., preferFreshLocal)` in the repository `companion object` and adds stage metrics to `fp`.
- **`Android/app/.../glance/DailySleepGlanceWidget.kt` & `DailyCombinedGlanceWidget.kt`**: Uses `SleepSession.formatTimeSpan(...)` (`roundToInt()`) for stage durations.
- **`WearOS/app/.../WatchPulseRepository.kt`**: Rounds `sleepDurationFormatted` using `(asleepSeconds / 60.0).roundToInt()`.

### 2.3 Windows 11 (`Models`, `WinUI 3`, `Tests`)
- **`Models/Health/HealthDailySummaryModels.cs`**, **`WinUI/Daily.WinUI/Services/HealthHubService.cs`**, **`WinUI/Daily.WinUI/Views/HealthDetailPage.xaml.cs`**, and **`WinUI/Daily.WinUI/DesktopWidgets/Views/DesktopSleepWidgetView.xaml.cs`**: Added `ParseUtcToLocal` (`DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal`) and standardized stage/sleep minute formatting to `Math.Round(..., MidpointRounding.AwayFromZero)`.

### 2.4 Supabase (`health-engine` & Migration)
- **`supabase/functions/health-engine/engine.ts`**: Added `normalizeIsoAsUtc` helper to `parseUtcDate` and `toEpochMs` so timezone-naive stage timestamps evaluate deterministically as UTC.
- **`supabase/migrations/20261115000001_sleep_update_ingested_at.sql`**: Added `BEFORE UPDATE` trigger `trg_z_touch_sleep_ingested_at` on `public.health_sleep_sessions` to refresh `NEW.ingested_at := now()` when reclassified stage/duration columns change. Applied on remote Supabase project `akkfouifxztnfwwiclwg` alongside `health-engine` deployment (`version 17`, `verify_jwt = false`).

---

## 3. Unit Tests & Verification
- **`DailyCoreTests`**: `HealthServiceTests` (`29` tests, `0` failures) covering `testMultiPassRecencyAwareStageDeduplicationAndCoalescing`, `testSleepStageRecordUtcZEncodingAndNaiveUtcDecoding`, and `testMergeLeanSleepSessionsReclassificationAndTruncationGuard`.
- **Android Unit Tests**: `:core-health:testDebugUnitTest` (`GoldenFixturesTest`: 2, `LeanHealthBuildersTest`: 11, `StressAnalysisEngineTest`: 6) and `:core-model:testDebugUnitTest` (`AstronomyServiceTest`: 5, `NewsParsersTest`: 21, `NewsPerspectivesTest`: 4, `PrismModelsTest`: 3, `SleepModelsTest`: 4, `SmartLedgerParserTest`: 1) all passing.
- **.NET Health Tests**: `Tests/Daily.Health.Tests/Daily.Health.Tests.csproj` (`15` tests passed, `0` failed, `0` skipped) including `TestNaiveAndExplicitUtcIsoTimestampsParseEquivalently`.
- **Live Device E2E (iOS Physical Device `Schmitz` + Remote Supabase)**: Confirmed HealthKit re-ingestion pushed updated `2026-11-15` session metrics matching Oura Ring (`duration_seconds = 35310` / `9h 49m`, `rem_seconds = 6570` / `1h 50m`, `deep_seconds = 5970` / `1h 40m`, `92` coalesced stages with `0` adjacent duplicate stages and explicit UTC `Z` timestamps), reflected across iOS Simulator (`SimulaDuo`). Confirmed `trg_z_touch_sleep_ingested_at` refreshes `ingested_at` (`2026-11-15T14:57:58Z`) on `UPDATE` and deployed `health-engine` v17 persisted matching summary metrics (`computed_at = 2026-11-15T14:58:00Z`).
