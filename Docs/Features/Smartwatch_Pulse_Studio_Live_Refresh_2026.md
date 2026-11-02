# Smartwatch Pulse Studio — Canonical Live Refresh & TagDoS-Style Sync Indicator (Wear OS & watchOS)

**Date**: November 2, 2026  
**Platforms**: watchOS (`DailyWatch Watch App`) & Wear OS (`com.intellidream.daily.wearos`)  
**Engine Contract**: Canonical `public.health_daily_summary` + `functions/v1/health-engine` Stress Engine `v2.0`

---

## 1. Overview & Motivation

Previously, the smartwatch `Pulse Studio` page (`WatchPulseView.swift` on watchOS and `PulseScreen.kt` on Wear OS) displayed static/circadian placeholder values (`82` sleep score, `7h 8m` duration, circadian-approximated RHR/HRV/Stress, and static equal-width stage bars) instead of consuming the user's real canonical wearable telemetry from Supabase. Furthermore, swiping into `Pulse Studio` on watchOS (`selectedTab == 3`) did not trigger a cloud refresh, and neither watch platform displayed an active sync indicator in the header.

This update brings full canonical `v2.0` live telemetry refresh to **Sleep & Recovery** and **Autonomic Stress** on both **Wear OS** and **watchOS**, adds a compact **`TagDoS`-style refresh spinner right next to `"Pulse Studio"`**, preserves `< 1ms` local-cache glanceability with strict **10-minute (`600s`) network/battery throttling**, and guarantees zero-allocation 60/120Hz rotary scrolling.

---

## 2. Architecture & Data Pipeline

### 2.1 `< 1ms` Local-First Snapshot + Throttled Cloud Sync
- **watchOS (`WatchPulseStore.swift`)**:
  - Singleton `ObservableObject` backed by App Group `UserDefaults("group.com.intellidream.daily")` key `watch_pulse_studio_cache_v2` (and mirrored to `daily_sleep_widget_snapshot_v1` for watch complications).
  - Hydrates `WatchPulseSnapshot` synchronously in `init()` (`< 1ms`, zero network wait on view appearance).
  - Pushes fresh watchOS HealthKit vitals/sleep (`HealthTelemetryManager.shared.syncTelemetry`) before querying `GET /rest/v1/health_daily_summary?user_id=eq.<uid>&date=eq.<yyyy-MM-dd>`.
  - Automatically invokes `POST /functions/v1/health-engine` (`{"date": "<yyyy-MM-dd>"}`) when today's summary row is missing, lacks `stress.engine_version == "v2.0"`, is older than 15 minutes (`updated_at`), received new watchOS HealthKit samples, or when the user manually taps the `"Pulse Studio"` header (`force = true`).
- **Wear OS (`WatchPulseRepository.kt`)**:
  - Singleton repository backed by `SharedPreferences("daily_prefs")` key `watch_pulse_studio_cache_v2`.
  - Exposes `@Immutable @Serializable data class PulseSnapshot` via `StateFlow<PulseSnapshot>` and `isSyncing: StateFlow<Boolean>`.
  - Parses nested JSON safely via `kotlinx.serialization.json.JsonObject` helpers (immune to R8 field stripping and numeric int/float variance in Supabase JSONB).
  - Queries `public.health_daily_summary` via Ktor `CIO` and triggers `POST /functions/v1/health-engine` when stale, missing, pre-`v2.0`, or manually forced.

### 2.2 Battery & Network TTL Policy
- **Automatic Sync TTL**: `10 minutes` (`600s` / `600_000ms`) between automatic cloud checks when swiping onto `Pulse Studio` or waking the wrist (`scenePhase == .active` / `Lifecycle.Event.ON_RESUME`).
- **Morning Sleep Early Retry**: `2 minutes` (`120s`) if `hasSleepData == false` so morning wake-up sleep sync resolves rapidly once Oura Ring, Apple Watch, or Pixel Watch uploads its sleep session.
- **Day Rollover**: Immediate refresh whenever `snapshot.localDate != todayLocalDate`.
- **1-Tap Force Refresh**: Tapping the `"Pulse Studio"` header row plays haptic feedback and runs `fetchPulseData(force: true)` / `syncWithSupabase(force = true)`, bypassing the 10-minute TTL.

---

## 3. UI, Fluidity & Smartwatch Layout Rules

1. **`TagDoS`-Style Refresh Spinner Next to Title**:
   - **watchOS (`WatchPulseView.swift`)**: Compact `ProgressView().tint(Color(hex: "#FF2D55")).scaleEffect(0.55).frame(width: 12, height: 12)` rendered immediately to the right of `"Pulse Studio"` while `pulseStore.isSyncing == true`.
   - **Wear OS (`PulseScreen.kt`)**: Compact `CircularProgressIndicator(modifier = Modifier.size(10.dp), strokeWidth = 1.5.dp, indicatorColor = Color(0xFFFF2D55))` rendered right next to `"Pulse Studio"` while `isSyncing == true`, matching `TagdosScreen.kt`.
2. **Sleep & Recovery Card**:
   - Displays canonical `sleep.score` ring, formatted `total_asleep_seconds` (`Xh Ym`), `Readiness <score> • <status>`, `guidance.narrative`, `RHR: <bpm>` + `HRV: <ms>`, and a **real proportional 4-stage bar** (`Deep`, `REM`, `Core/Light`, `Awake`) computed from `sleep.primary_session` durations (with clamped minimum visual weights).
3. **Autonomic Stress Card (Engine `v2.0`)**:
   - Displays canonical physiological `stress.current_score` (`<score>/100`), `<current_level> • Avg <daily_average>`, `stress.monkey_mood`, formatted `activity.steps`, `Parasym: <parasympathetic_percent>%`, 2-line `advice_quote`, and a single-line `"Breathe"` capsule (`maxLines = 1, softWrap = false` on Wear OS; `.fixedSize()` on watchOS) that launches the recommended breathing protocol (`recommended_breathing`).
4. **Orbit Hub Macro Pillar Sync**:
   - `WatchOrbitHubView.swift` and `OrbitHubScreen.kt` now read their **Energy** (Sleep Score) and **Mind** (`Calm <100 - stress>%`) macro pillars directly from the local `PulseSnapshot` cache (`0` extra network calls).
5. **Zero-Allocation Rotary Scrolling & Release Delivery**:
   - All display strings and stage fractions/weights are precomputed inside `@Immutable PulseSnapshot` / `WatchPulseSnapshot` at sync time; colors and progress values in `PulseScreen.kt` are memoized via `remember(...)`.
   - Wear OS physical watches receive exclusively R8-minified, resource-shrunk Release builds (`./gradlew assembleRelease` -> `app-release.apk`).

---

## 4. Modified & Created Files

### watchOS (`WatchOS/DailyWatch/DailyWatch Watch App/`)
- `WatchPulseStore.swift` *(new)* — Canonical snapshot model, App Group cache, 10m TTL throttle, REST `health_daily_summary` reader, and `health-engine` v2.0 trigger.
- `HealthTelemetryManager.swift` — `@discardableResult` `syncTelemetry(isDeepSync:force:) -> Bool` and immediate first-of-day watch sleep upload.
- `WatchPulseView.swift` — Live binding to `WatchPulseStore`, `TagDoS`-style header spinner + tap-to-refresh, proportional stage bar, single-line `"Breathe"` chip, and zero-truncation typography.
- `ContentView.swift` — Triggers `WatchPulseStore.shared.fetchPulseData()` on `selectedTab == 3` and foreground `scenePhase == .active`.
- `WatchOrbitHubView.swift` — Reads live cached `Energy` and `Mind` metrics from `WatchPulseStore.shared.snapshot`.

### Wear OS (`WearOS/app/src/main/java/com/intellidream/daily/wearos/`)
- `data/WatchPulseRepository.kt` *(new)* — `@Immutable` `PulseSnapshot`, `SharedPreferences` `< 1ms` cache, 10m TTL, Ktor `CIO` canonical sync, and R8-safe JSONB parsing.
- `presentation/pulse/PulseScreen.kt` — Live binding to `WatchPulseRepository` + `dataRefreshTrigger`, `TagDoS`-style header spinner + clickable manual refresh, memoized rotary scroll state, and single-line `"Breathe"` chip.
- `presentation/orbit/OrbitHubScreen.kt` — Reads live cached `Energy` and `Mind` pillars from `WatchPulseRepository`.
