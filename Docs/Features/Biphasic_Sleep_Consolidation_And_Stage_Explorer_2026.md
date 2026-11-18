# Device-Agnostic Biphasic / Split-Night Sleep Consolidation & Interactive Stage Explorer (2026)

## Overview

When a user experiences **biphasic or split-night sleep** (for example, sleeping `22:18 -> 03:28`, waking up out of bed for ~2 hours, and returning to sleep `05:31 -> 09:45`), different wearables and OS health stores emit two distinct telemetry topologies:

1. **Single Session Envelope with Uncovered Internal Gap (e.g. Health Connect wearables worn continuously)**:
   - A single `SleepSessionRecord` spans `22:21 -> 09:38`, while granular `stages` cover `22:21 -> 03:18` and `06:07 -> 09:38`, leaving an uncovered wake interval (`03:18 -> 06:07`) inside the same session envelope.
2. **Multiple Nocturnal Episodes with an Untracked Break (e.g. HealthKit / Health Connect wearables splitting episodes)**:
   - Two separate nocturnal episodes (`22:18 -> 03:28` and `05:31 -> 09:45`) are separated by an untracked break (`>= 45 min`) without stage records.

Previously, `SleepClusteringEngine` split clusters whenever `gapMinutes >= 45` and downstream `buildLeanSleepSessionRecords` (`uq_health_sleep_session`: 1 `primary_sleep` row per `(user_id, local_date, session_type, source_device_key)`) kept only the first or longest episode, dropping Stage 2.

---

## Architecture (100% Device-Agnostic)

Zero device-name branching is used. Consolidation, `Time in Bed` math, and stage exploration operate purely on session envelopes and chronological stage intervals across **Oura Ring**, **Apple Watch Ultra 2**, **Google Pixel Watch 5**, **OnePlus Watch 3**, **Samsung Galaxy Watch**, **Amazfit**, **Garmin**, and all HealthKit / Health Connect wearables:

### 1. Health Connect Intra-Envelope Gap Filling (`HealthConnectManager.kt`)
- Sessions whose `endTime` falls inside `(D-1 18:00, D 18:00]` are attributed to morning wake-up date `D` (preventing early Stage 1 sessions ending between `18:00` and `23:59` on `D-1` from being dropped).
- Within a single `SleepSessionRecord` containing granular stages, any uncovered internal interval `>= 60s` inside `[record.startTime, record.endTime]` is emitted as a deterministic `sleep_stage_awake` telemetry record (`${record.metadata.id}_gap_$cursorMs`), matching Google Health session totals 1:1.

### 2. Multi-Episode Nocturnal Consolidation (`SleepClusteringEngine` — Swift, Kotlin, TypeScript)
- **Early-Morning Continuation Reclassification**: If a wearable has a truncated nocturnal episode (`!isNap`, `asleepSeconds < 6h`) and a follow-up episode starting `< 11:00` within `<= 4h` of the prior episode's `endTime`, the continuation is classified as nocturnal (`isNap = false`) rather than a daytime nap. Genuine afternoon naps (`>= 11:00` or after `>= 6h` sleep) remain strictly segregated in `daytimeNaps`.
- **Per-Wearable Nocturnal Consolidation**: Multiple nocturnal episodes (`!isNap`) from the same canonical wearable separated by `<= 8h` are merged into a single consolidated `SleepSession` (`startTime = first.startTime`, `endTime = last.endTime`, chronological `stages`), **without** inventing fake `Awake` stages for untracked out-of-bed breaks.
- **Zero Extra Supabase Egress**: Consolidation writes to the existing single `primary_sleep` row per wearable in `public.health_sleep_sessions`. `SleepUploadFingerprintStore.shouldInvalidateStaleRemoteSleep` self-heals truncated single-stage remote rows automatically once Stage 2 syncs.

### 3. Untracked Break Subtraction in `Time in Bed` (`HealthModels.swift`, `HealthModels.kt`, `SleepSession.cs`, `engine.ts`)
- `computeUntrackedBreakSeconds` sums any uncovered gaps `>= 45 min` (`2700s`) between consecutive sorted stages (and leading/trailing session bounds) and subtracts them from `endTime - startTime` when computing `durationSeconds` (`Time in Bed`).
- Prevents untracked out-of-bed breaks (e.g. `2h 03m`) from inflating `Time in Bed` or artificially depressing `Efficiency %` and `Sleep Score`.
- On WinUI (`SleepSession.cs`), `EffectiveEndTime` preserves `EndTime` whenever granular stages reach `EndTime` so `WakeTimeFormatted` accurately reflects final morning wake-up.

### 4. On-the-Fly Interactive Stage Selector (`Full Night` | `Stage 1` | `Stage 2`)
- `SleepSession.sleepSegments` (`GetSleepSegments()` in C#) derives explorable stages client-side when a nocturnal session contains 2+ sleep segments (`>= 20m` asleep each) separated by either:
  - an untracked gap `>= 45 min`, or
  - a contiguous `Awake` bridge `>= 45 min` flanked by `>= 20m` of real sleep on both sides.
- Rendered in **Sleep Studio** across **iOS**, **macOS**, **Android**, and **WinUI 3** (`Full Night` + `Stage 1` + `Stage 2` Liquid Glass pills), updating the Hero card, Clinical Hypnogram, and Stage Breakdown Grid on selection while remaining completely hidden on normal single-segment nights.

### 5. Standardized Stage Ordering (`REM` First, `Deep` Second)
- Across **iOS**, **macOS**, **Android**, **WinUI 3**, **watchOS**, **Wear OS**, and all **WidgetKit / Jetpack Glance / Windows Desktop Widgets**, horizontal stage breakdowns, proportional bars, and metric cards present **`REM -> Deep -> Light/Core -> Awake`**, while the 4-lane Clinical Hypnogram preserves standard vertical EEG depth (`Awake -> REM -> Core/Light -> Deep`).
