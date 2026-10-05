# Unified Health & Vitals: P0 Security & P1 Canonical Contract & Schema v2

**Document Date:** October 5, 2026  
**Implementation Phase:** P0 (Security Hardening) & P1 (Canonical Data Contract & Schema v2)  
**Status:** Implemented, Compiled & Validated Across All Platforms, Verified on Live Supabase Database  

---

## 1. Executive Summary

As part of the cross-platform unification of the Health & Vitals system (Option C: Canonical Server Engine with Thin Client Renderers and Provisional Local Fallbacks), Phases P0 and P1 have been executed:
1. **P0 Security Hardening**: Addressed critical vulnerabilities in watch pairing tables and RPC functions, purged stale credentials, and secured git hygiene.
2. **P1 Canonical Contract & Codegen**: Established a single source of truth for health metrics (`HealthSpec/metric_registry.json`), built an automated codegen tool (`HealthSpec/generate_contracts.js`), and validated generated contracts across all 4 target programming languages (Swift, Kotlin, C#, TypeScript).
3. **P1 Schema v2 Migration**: Evolved the live Supabase database with normalized telemetry ingest, deduplication triggers, dirty-day tracking, and the single canonical `health_daily_summary` table with Supabase Realtime enabled.

---

## 2. Phase P0: Security Hardening

### 2.1 Watch Pairing Tables RLS Lockdown
- **`paired_watches`**: Dropped permissive `USING (true)` policies for anonymous users (`Anon select paired watches by id` and `Anon update paired watches clear tokens`). Replaced with strictly scoped policies:
  - `Anon fetch watch with pending token`: Allows anonymous watches to select *only* if `pending_access_token IS NOT NULL AND is_active = true`.
  - `Anon clear pending watch tokens`: Allows anonymous watches to clear tokens *only* where `pending_access_token IS NOT NULL` with check `pending_access_token IS NULL`.
- **`watch_pairing_codes`**:
  - Dropped overly broad `Anyone can read pairing codes` policy.
  - Purged all expired PIN records from the database.
  - Restricted anonymous SELECT to active, unexpired PINs (`expires_at > NOW()`).
  - Restricted UPDATE to authenticated owners claiming the code (`auth.uid() = user_id`) or watch claiming active PIN.
- **`watch_pairings`**: Deprecated legacy unauthenticated policies.

### 2.2 SECURITY DEFINER RPC Hardening
- **`deactivate_paired_watch`**: Enforced authentication check and strict ownership verification (`WHERE id = watch_id AND user_id = auth.uid()`), with explicit `SET search_path = public` to mitigate search-path hijacking attacks.
- **`claim_orbit_pin`**: Added explicit `SET search_path = public`.

### 2.3 Git Hygiene
- Added `supabase/.temp/` and `.supabase/` to `.gitignore` to prevent leaking local CLI state and database references.
- Untracked `supabase/.temp` from git index.

---

## 3. Phase P1: Canonical Contract & Multi-Platform Codegen

### 3.1 Single Source of Truth (`HealthSpec/metric_registry.json`)
Defines all supported biometric and activity metrics, canonical units, accepted aliases, semantics, aggregation rules, and attribution windows:
- Activity: `steps`, `active_energy`, `basal_energy`, `distance`, `floors_climbed`, `walking_speed`, `pai`
- Cardiac: `heart_rate`, `resting_heart_rate`, `hrv_sdnn` (Apple Watch / Oura baseline), `hrv_rmssd` (Health Connect baseline)
- Respiratory: `oxygen_saturation` (normalizes `spo2`, `blood_oxygen`, `bo`), `respiratory_rate`
- Sleep: `sleep_stage_deep`, `sleep_stage_rem`, `sleep_stage_light`, `sleep_stage_awake`, `sleep_duration`
- Nutrition & Body: `weight`, `hydration`, `caffeine`, `stress`

### 3.2 Codegen Tool (`HealthSpec/generate_contracts.js`)
Generates type-safe contracts for all four languages with automated key deduplication and language-specific nuances:
1. **Swift**: `DailyCore/Sources/DailyCore/Models/CanonicalHealthMetrics.swift`
   - Defines `CanonicalHealthMetric` enum with `String`, `Codable`, `Sendable`, `CaseIterable`.
   - Includes `.displayName`, `.canonicalUnit`, and `.from(alias: String)`.
2. **Kotlin (Android)**: `Android/core-model/src/main/java/com/intellidream/daily/model/CanonicalHealthMetrics.kt`
   - Defines `CanonicalHealthMetric` enum with attributes and `fromAlias(raw: String)` companion lookup map.
3. **C# (.NET / WinUI)**: `Models/Health/CanonicalHealthMetrics.cs`
   - Defines `CanonicalHealthMetric` enum and `HealthMetricRegistry` with case-insensitive `StringComparer.OrdinalIgnoreCase` deduplicated alias resolution.
4. **TypeScript (Edge Functions)**: `HealthSpec/canonicalHealthMetrics.ts`
   - Type definitions, `METRIC_REGISTRY`, and `normalizeMetricType(raw: string)` resolver.

### 3.3 Verification & Compiler Validation
- **TypeScript**: Validated via `npx -p typescript tsc --noEmit HealthSpec/canonicalHealthMetrics.ts` (0 errors).
- **Swift**: Built and validated via `swift build --package-path DailyCore` and `swift test` (52 unit tests passed across 7 test suites).
- **Kotlin**: Built via `./gradlew :core-model:compileDebugKotlin` (BUILD SUCCESSFUL, 0 errors).
- **C#**: Built with .NET 10 `dotnet build` (Build succeeded, 0 warnings, 0 errors).

---

## 4. Phase P1: Supabase Schema v2 Migration

Applied via `supabase/migrations/20261005161000_p1_health_schema_v2.sql`:

```
┌────────────────────────────────────────────────────────┐
│                  health_telemetry                      │
├────────────────────────────────────────────────────────┤
│ + external_id (idempotency key)                        │
│ + source_id (FK to health_sources)                     │
│ + semantics (spot, interval_delta, session_stage)      │
│ + tz_offset_min (timezone offset in minutes)           │
│ + local_date (calculated date in user timezone)        │
│ + ingested_at (timestamptz)                            │
└───────────┬────────────────────────────────┬───────────┘
            │ BEFORE INSERT                  │ AFTER INSERT
            ▼                                ▼
┌─────────────────────────┐      ┌───────────────────────┐
│ trigger_normalize_      │      │ trigger_mark_dirty_   │
│ telemetry               │      │ telemetry             │
├─────────────────────────┤      ├───────────────────────┤
│ • Canonical alias map   │      │ • Upserts to          │
│ • Local date calc       │      │   health_day_dirty    │
│ • Silent dedup drop     │      │   (user_id,           │
│   (RETURN NULL)         │      │    local_date)        │
└─────────────────────────┘      └───────────┬───────────┘
                                             │
                                             ▼
                                 ┌───────────────────────┐
                                 │ health_daily_summary  │
                                 ├───────────────────────┤
                                 │ • steps, kcal, rhr    │
                                 │ • sleep_score, stages │
                                 │ • stress_avg, hrv     │
                                 │ • summary JSONB       │
                                 │ • Realtime enabled    │
                                 └───────────────────────┘
```

1. **`health_sources`**: Device registration table with device priority scoring for sleep and activity resolution.
2. **`health_telemetry` Evolution**: Added `external_id`, `source_id`, `semantics`, `tz_offset_min`, `local_date`, and `ingested_at`.
3. **`health_day_dirty`**: Realtime dirty tracker marking dates requiring re-aggregation whenever telemetry arrives.
4. **`health_daily_summary`**: Persisted single source of truth for daily vitals, published to `supabase_realtime`.
5. **Legacy Aggregation Trigger Deactivated**: Removed `trigger_aggregate_health_telemetry` which corrupted metrics by accumulating cumulative steps and aggregating on UTC dates.
6. **Live Database Verification**: Verified with live inserts:
   - Alias normalization (`spo2` $\rightarrow$ `oxygen_saturation`) confirmed.
   - Idempotent deduplication (`RETURN NULL` on duplicate) confirmed.
   - Automatic dirty-day logging confirmed.
