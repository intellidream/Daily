# Health Engine PostgREST Telemetry Range Pagination & Smartwatch Sleep Parity

## 1. Context & Issue Summary
- **Incidents Reported**:
  - Sleep duration for 2026-10-30 dropped from the true **7h 8m** (recorded by Oura Ring + Apple Watch) down to **13 minutes** on iOS ("Schmitz") and macOS.
  - On smartwatches (Apple Watch Ultra 2 & Pixel Watch 5), Pulse Studio displayed a static placeholder value of **7h 42m** / score **88**, divergent from canonical health metrics.
- **Affected Systems**:
  - Supabase Edge Function `health-engine` (`index.ts` & `engine.ts`)
  - Swift Core Domain `HealthDataService.swift`
  - watchOS Pulse Studio (`WatchPulseView.swift`)
  - Wear OS Pulse Studio (`PulseScreen.kt`)

---

## 2. Root Cause Analysis

### A. PostgREST Default Max Rows (`PGRST_MAX_ROWS = 1000`)
The Supabase PostgREST layer enforces an immutable server-side row limit (default: 1,000 records per response). In `supabase/functions/health-engine/index.ts`:
```typescript
// Buggy implementation:
const { data: telemetry, error: telemetryError } = await supabase
  .from('health_telemetry')
  .select('*')
  .eq('user_id', user.id)
  .gte('recorded_at', nocturnalWindowStart.toISOString())
  .lte('recorded_at', nocturnalWindowEnd.toISOString())
  .limit(25000);
```
Even though `.limit(25000)` was requested, PostgREST silently truncated the returned array at exactly **1,000 rows**.

On 2026-10-30, the nocturnal window contained **6,519 telemetry rows** across multiple devices (Oura Ring, Apple Watch, Pixel Watch). The 1,000-row cutoff truncated data at **00:12:00 UTC**.
- Oura Ring nocturnal sleep stages spanned from 00:04:30 to 07:42:30 UTC (69 sleep stages).
- Only the first 2 stages (00:04:30 Awake 390s, 00:11:00 Light 750s) were within the first 1,000 rows; the remaining 67 stages were dropped.
- Because Oura had highest source priority (rank 100) and `hasGranularHypnogram = true`, the engine chose Oura's truncated session of exactly **750 seconds asleep (12.5 minutes, rounded to 13 minutes)**.
- `health_daily_summary` was overwritten with 13 minutes, synchronizing to iOS and macOS clients.

### B. Smartwatch Pulse Studio Hardcoded Fallback
Commit `5a772deb` introduced circadian metrics in Pulse Studio, but left temporary hardcoded literals (`"7h 42m"`, `sleepScore = 88`) in:
- `WatchPulseView.swift`
- `PulseScreen.kt`

---

## 3. Architecture & Implementation Fixes

### A. PostgREST Chunked Range Pagination Loop
Implemented range-based pagination (`.range(from, to)`) in both the Supabase Edge Function and Swift client to safely ingest arbitrarily large telemetry volumes:

**Edge Function (`supabase/functions/health-engine/index.ts`)**:
```typescript
let allTelemetry: any[] = [];
let from = 0;
const pageSize = 1000;
const maxRecords = 30000;

while (from < maxRecords) {
  const to = from + pageSize - 1;
  const { data: page, error: pageError } = await supabase
    .from('health_telemetry')
    .select('*')
    .eq('user_id', user.id)
    .gte('recorded_at', nocturnalWindowStart.toISOString())
    .lte('recorded_at', nocturnalWindowEnd.toISOString())
    .order('recorded_at', { ascending: true })
    .range(from, to);

  if (pageError) throw pageError;
  if (!page || page.length === 0) break;
  allTelemetry.push(...page);
  if (page.length < pageSize) break;
  from += pageSize;
}
```

**DailyCore (`HealthDataService.swift`)**:
```swift
var allTelemetry: [HealthTelemetryPayload] = []
var from = 0
let pageSize = 1000
let maxRecords = 20000

while from < maxRecords {
    let to = from + pageSize - 1
    let page: [HealthTelemetryPayload] = try await client
        .from("health_telemetry")
        .select()
        .eq("user_id", value: userId)
        .gte("recorded_at", value: startString)
        .lte("recorded_at", value: endString)
        .order("recorded_at", ascending: true)
        .range(from: from, to: to)
        .execute()
        .value

    allTelemetry.append(contentsOf: page)
    if page.count < pageSize { break }
    from += pageSize
}
```

### B. Dynamic Smartwatch Snapshot Hydration
Updated `WatchPulseView.swift` to read directly from the shared App Group snapshot (`daily_sleep_widget_snapshot_v1`) with zero latency, falling back to canonical health summary metrics rather than hardcoded literals.
Updated `PulseScreen.kt` with synchronized defaults and reactive Room observation.

---

## 4. Verification & Delivery

1. **Golden Fixtures Regression Test**:
   - `node --experimental-strip-types HealthSpec/generate_and_test_fixtures.ts`:
   - All 8 Golden Fixtures passed with 0 errors.
2. **DailyCore Unit & Integration Tests**:
   - `swift test --package-path DailyCore`:
   - 56 tests across 8 suites passed with 0 failures.
3. **Database Summary Recomputation**:
   - Ingested all 6,519 telemetry rows for 2026-10-30.
   - Verified restored canonical values in Supabase `health_daily_summary`:
     - `asleep_seconds`: 25,680 (**7h 8m**)
     - `sleep_score`: 82
     - `steps`: 6,672
     - `status`: Great
4. **Target Deployments**:
   - macOS: Built and verified natively.
   - iOS Simulator (SimulaDuo): Built and launched cleanly (PID 94456).
   - Physical iPhone 16 Pro (Schmitz): Built, deployed via `devicectl`, verified 7h 8m sleep view.
   - watchOS Simulator: Built, installed, and launched cleanly (PID 96018).
   - Wear OS (Pixel Watch 5): Assembled and deployed via adb.
