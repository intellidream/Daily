# Unified Health Canonical Sleep Guidance Deserialization Parity

## Overview
This architectural resolution eliminates a cross-platform deserialization mismatch between the Supabase Edge Function (`health-engine`) and Apple platforms (`DailyCore` on iOS and macOS). The issue prevented macOS and iOS from ingesting the canonical computed daily health summary (`health_daily_summary`), causing them to fall back to provisional segmented sleep telemetry and report partial sleep metrics (e.g. 2h 50m instead of the true 5h 21m) while Android and WinUI successfully displayed the canonical totals.

---

## 1. Problem Diagnosis & Mathematical Breakdown

### The Discrepancy
- **Nocturnal Telemetry**: Total sleep from Pixel Watch 5 on 2026-10-29 spanned 04:15 to 09:44 local time (02:15 to 07:44 UTC) across 20 granular stages.
- **Segment 1 (04:15 - 07:13 local)**: 10,200s (2h 50m) asleep, 10,680s (2h 58m) duration.
- **Segment 2 (07:13 - 09:44 local)**: 9,060s (2h 31m) asleep.
- **Canonical Combined Total**: 19,260s (5h 21m) asleep, sleep score 77.

### Root Cause
1. **Edge Function Contract**: In `supabase/functions/health-engine/engine.ts`, `generateSleepGuidance` constructed `SleepRecoveryVerdict` without an `id` field:
   ```typescript
   const verdict: SleepRecoveryVerdict = {
       status,
       headline,
       narrative,
       readiness_score: readinessScore,
       physical_repair_rating: physicalRepair,
       cognitive_restore_rating: cognitiveRestore,
       sleep_continuity_rating: continuity
   };
   ```
2. **Android Resilience**: In `Android/core-model/HealthDailySummaryModels.kt`, `CanonicalSleepVerdict` intentionally omits `id` and assigns `UUID.randomUUID().toString()` during domain conversion. Android devices (RADAR / Z Fold 8 and Trapper / Pixel 9 Pro) deserialized the Supabase payload cleanly without errors.
3. **WinUI Resilience**: WinUI uses `Newtonsoft.Json`, which ignores absent properties unless explicitly required. WinUI parsed the payload and populated `health_daily_summary_cache` with 5h 21m.
4. **Apple Platform Silent Failure**: In `DailyCore` (`SleepGuidance.swift`), `SleepRecoveryVerdict` declared `public let id: String` with synthesized `Codable`. When decoding `HealthDailySummaryRecord`:
   `DecodingError.keyNotFound: Key 'id' not found in keyed decoding container. Path: [0].summary.sleep.guidance.verdict`
   In `HealthDataService.swift`, this error was caught in `remoteSummaryFetch` and returned `nil`. Consequently, macOS and iOS fell back to provisional calculation from the first nocturnal cluster (2h 50m), locking in the partial duration.

---

## 2. Implemented Architecture Fixes

### A. Resilient Swift Deserialization (`DailyCore`)
In `DailyCore/Sources/DailyCore/Services/SleepGuidance.swift`:
- Implemented custom `init(from decoder: Decoder)` for `SleepRecoveryVerdict` with `decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString`.
- Implemented custom `init(from decoder: Decoder)` for `SleepActionableTip` with fallback identifier synthesis.
- Implemented custom `init(from decoder: Decoder)` for `SleepAIContext` with fallback default empty prompt arrays.

### B. Supabase Backend Parity (`health-engine`)
In `supabase/functions/health-engine/engine.ts` & `types.ts`:
- Added `id?: string;` to `SleepRecoveryVerdict` interface.
- Emitted deterministic canonical identifier `id: 'sleep_verdict_' + targetDateStr` during verdict synthesis.

### C. Regression Test Suite
In `DailyCore/Tests/DailyCoreTests/HealthServiceTests.swift`:
- Added `testCanonicalSleepGuidanceDecodingWithoutId` validating that JSON payloads lacking an `id` field parse into valid `SleepRecoveryVerdict` domain models without throwing.

---

## 3. Verification & Deployment

1. **DailyCore Test Suite**: All 55 tests in 8 test suites passed (`0 failures`).
2. **macOS Native App Build**: Verified build success on macOS 15.0+ arm64 (`xcodebuild build` completed with zero errors).
3. **iOS Simulator Build**: Verified build success on SimulaPhone (`xcodebuild build` completed with zero errors).
4. **Cache Cleared**: Purged stale `health_daily_summary_2026-10-29` and `daily_sleep_widget_snapshot_v1` from macOS App Group defaults to enable immediate consumption of the canonical 5h 21m summary.
