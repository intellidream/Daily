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
- **`DailyCoreTests`**: `HealthServiceTests` (`30` tests, `0` failures) covering `testMultiPassRecencyAwareStageDeduplicationAndCoalescing`, `testSleepStageRecordUtcZEncodingAndNaiveUtcDecoding`, `testMergeLeanSleepSessionsReclassificationAndTruncationGuard`, and `testSleepUploadFingerprintPersistenceAndUserIsolation`.
- **Android Unit Tests**: `:core-health:testDebugUnitTest` (`GoldenFixturesTest`: 2, `LeanHealthBuildersTest`: 11, `SleepUploadFingerprintStoreTest`: 1, `StressAnalysisEngineTest`: 6 — `20` tests, `0` failures) and `:core-model:testDebugUnitTest` (`AstronomyServiceTest`: 5, `NewsParsersTest`: 21, `NewsPerspectivesTest`: 4, `PrismModelsTest`: 3, `SleepModelsTest`: 4, `SmartLedgerParserTest`: 1 — `38` tests, `0` failures), plus `:app:assembleDebug` build passed.
- **.NET Health Tests**: `Tests/Daily.Health.Tests/Daily.Health.Tests.csproj` (`15` tests passed, `0` failed, `0` skipped) including `TestNaiveAndExplicitUtcIsoTimestampsParseEquivalently`.
- **Live Device E2E (iOS Physical Device `Schmitz` + Remote Supabase)**: Confirmed HealthKit re-ingestion pushed updated `2026-11-15` session metrics matching Oura Ring (`duration_seconds = 35310` / `9h 49m`, `rem_seconds = 6570` / `1h 50m`, `deep_seconds = 5970` / `1h 40m`, `92` coalesced stages with `0` adjacent duplicate stages and explicit UTC `Z` timestamps), reflected across iOS Simulator (`SimulaDuo`). Confirmed `trg_z_touch_sleep_ingested_at` refreshes `ingested_at` (`2026-11-15T14:57:58Z`) on `UPDATE` and deployed `health-engine` v17 persisted matching summary metrics (`computed_at = 2026-11-15T14:58:00Z`).

---

## 4. Egress, WAL & Cold-Launch Upload Optimizations (`20261115000002` + Persistent `sleepFp`)

To eliminate redundant `health_sleep_sessions` writes, WAL/dead-tuple churn, `supabase_realtime` fan-out (`SELECT` storms across connected devices), and cold-launch upload re-evaluations after sleep synchronization:

1. **Server-Side Conditional `ingested_at` & Redundant-Update Suppression (`supabase/migrations/20261115000002_sleep_conditional_ingested_at_and_suppress_noop.sql`)**:
   - Replaces `public.trg_fn_touch_sleep_ingested_at()` (`BEFORE UPDATE`) so it compares all 20 content/priority/selection columns (`IS DISTINCT FROM`, executing alphabetically after `trg_guard_health_sleep_sessions`). If unchanged, it resets `NEW.ingested_at := OLD.ingested_at`; only genuine sleep/stage/priority modifications set `NEW.ingested_at := now()`.
   - Adds `trg_zz_suppress_redundant_sleep_updates` (`BEFORE UPDATE FOR EACH ROW EXECUTE FUNCTION pg_catalog.suppress_redundant_updates_trigger()`) running alphabetically last so identical upserts short-circuit inside PostgreSQL with zero heap writes, zero dead tuples, and zero `supabase_realtime` broadcast events.
   - Applied remotely on Supabase project `akkfouifxztnfwwiclwg`.
2. **Client-Side Persistent Sleep Upload Fingerprint Cache (`SleepUploadFingerprintStore`)**:
   - **`DailyCore/Sources/DailyCore/Services/HealthDataService.swift`** (shared across `iOS` & `macOS`): Persists a schema-versioned (`v2|`) per-user `sleepFp` map (`health_sleep_upload_fp_cache_v1` in App Group `UserDefaults`), including duration, stage totals, boundary seconds, selection flag, and a 64-bit FNV-1a digest of stage types and boundaries. Automatically prunes entries older than `14` days, clears on `.unauthenticated` sign-out, isolates strictly by normalized `userId`, and self-heals if a confirmed online `remoteSleepFetch` returns `[]` while local sleep records exist.
   - **`Android/core-health/.../HealthDataRepository.kt` & `Android/core-network/.../HealthRemoteService.kt`**: Mirrors the identical `v2|` + FNV-1a `SleepUploadFingerprintStore` backed by `SharedPreferences` (`daily_health_sleep_fp_v1`), preserving cold-launch hydration on `local_user -> <userId>` while clearing on sign-out and self-healing via `fetchSleepSessionsOrNull(...)` when a confirmed online server query returns empty.

---

## 5. Multi-Android Monotonic Session Guard, Fingerprint Self-Heal & Cross-Client Cache/Realtime Sync (`20261116000001`)

Investigation of a cross-platform mismatch (`2026-11-16`, Pixel Watch 5 sole wearable: Android phones showed finalized `REM 2h 3m` / `Deep 1h 1m` ending `10:12`, while `iOS`, `macOS`, and `WinUI` temporarily displayed `REM 1h 35m` / `Deep 1h 0m` ending `09:14`) identified five cooperating causes and resolved them across all layers:

1. **Server-Side Monotonic Non-Regression Guard (`supabase/migrations/20261116000001_sleep_monotonic_session_guard.sql`)**:
   - Extends `public.trg_fn_guard_health_sleep_sessions()` (`BEFORE UPDATE` on `public.health_sleep_sessions`) to block stale/lagging secondary hosts (e.g., a second Android phone whose Health Connect/Fitbit sync still holds an earlier `09:14` snapshot) from overwriting a completed sleep session backwards (`NEW.end_time < OLD.end_time - 60s` with shorter `duration_seconds`, or cross-host fewer `deep + rem` stages without longer duration), while still allowing genuine Light/Core-to-REM/Deep stage upgrades.
   - Pairs directly with `trg_zz_suppress_redundant_sleep_updates` so blocked stale overwrites emit zero heap writes, zero `ingested_at` updates, and zero Realtime broadcasts.
2. **Client-Side Stale-Remote Fingerprint Self-Heal (`DailyCore` + `Android`)**:
   - Added `SleepUploadFingerprintStore.shouldInvalidateStaleRemoteSleep(...)` in both `DailyCore/Sources/DailyCore/Services/HealthDataService.swift` and `Android/core-health/.../HealthDataRepository.kt` so an up-to-date host (`Trapper`) automatically invalidates its cached `sleepFp` and re-uploads once if Supabase currently holds an older/truncated session for the same `(sessionType, canonicalDevice)`, without generating extra writes when remote matches local.
3. **Android Room Obsolete Stage Replacement (`Android/core-database/.../HealthDaos.kt` & `HealthDataRepository.kt`)**:
   - Added `@Transaction replaceSleepTelemetryForDate(...)` to clear obsolete `sleep%` rows per `(userId, localDate)` before inserting fresh Health Connect sleep stages so adjusted/removed preliminary segments (e.g., shifted stage boundaries or removed transient awake blocks) do not accumulate in local `health_telemetry`.
4. **Apple Ecosystem Zombie Realtime & Foreground Recovery (`DailyCore/.../HealthDataService.swift`)**:
   - Replaced `realtimeChannel != nil` checks in `setupRealtimeSubscription()` and `startActiveSyncLoop()` with `realtimeChannel?.status == .subscribed` (plus `.subscribing` guard and 15s reconnect throttle) so dropped WebSockets reconnect automatically on `refreshIfStale()` and active polling cadence falls back cleanly to 5m until rejoined.
   - Reduced Today's `refreshIfStale()` staleness window to `90s` when Realtime is `.subscribed` and `30s` when disconnected, preventing multi-minute stale sleep views when resuming `iOS` or `macOS`.
5. **`WinUI` & `.NET Models` Cache TTL, Stage Durations & Dashboard Reload (`Models/Health`, `WinUI`)**:
   - **`Models/Health/HealthDailySummaryModels.cs` & `SleepSession.cs`**: Derived stage duration from `(end_time - start_time)` in `ToDomainSleepSession` when JSONB stage elements omit `duration_seconds`, and aligned stage/efficiency percentages to `Math.Round(..., MidpointRounding.AwayFromZero)`.
   - **`WinUI/Daily.WinUI/Services/HealthHubService.cs` & `MainWindow.xaml.cs`**: Added mutable-date cache TTL (`90s` when all Realtime channels `.IsJoined`, `30s` when degraded) on `_sleepCache`, `_vitalsCache`, `_hrCache`, and background summary refreshes; verified all lean Realtime channels in `IsRealtimeHealthy`; ensured `PullDeltasAsync()` reconnects Realtime and refreshes sleep alongside summaries; and added a `60s` Health delta catch-up cooldown on `MainWindow_Activated`.
   - **`WinUI/Daily.WinUI/Controls/HealthWidgetControl.xaml.cs` & `Views/HealthDetailPage.xaml.cs`**: Reloaded `_primarySleepSession` and `_metrics` inside `HealthWidgetControl.OnDailySummaryChanged` and added single-flight coalescing (`_isLoadingData` / `_reloadPending`) in both controls so rapid Realtime events never race out-of-order.
