# Smartwatch Fluidity, Craving Pacing Parity & Release Performance (WearOS & watchOS)

## 1. Overview & Issues Addressed
This engineering cycle resolves smartwatch regressions reported on **WearOS** (Google Pixel Watch 5) and solidifies parity with **watchOS** (Apple Watch Ultra 2):
1. **WearOS Fluidity & Performance Degradation**:
   - Rotary crown scrolling and horizontal swipe between pages exhibited stuttering, dropped frames, and input latency.
   - Root Causes:
     - **Accidental Debug Build Deployment**: An unoptimized `assembleDebug` APK (74 MB) was deployed. Debug builds disable R8 inlining, lack dead-code elimination, keep unneeded classes, and inject debug instrumentation on every composable.
     - **Recomposition Overhead & Heap Allocations on Scroll**: `OrbitHubScreen.kt` and `PulseScreen.kt` performed trigonometric calculations, diurnal temperature simulations, synodic moon phase calculations, string formatting, and stream/log list filtering directly inside the composable body on every scroll frame without memoization.
2. **Craving-Free Timer Discrepancy on WearOS**:
   - `WatchSessionManager.kt` computed time elapsed strictly from a local SharedPreferences key `KEY_LAST_SMOKE_TIMESTAMP`. This key was only updated upon local smoke insertion and was disconnected from Supabase multi-device logs. If a smoke was logged on iOS, macOS, Android, or WinUI, or if the watch restarted, the key remained stale or empty, giving inaccurate craving-free intervals.
   - On watchOS, `WatchHabitStore.swift` derived craving-free time directly from `todaySmokesLogs.first`.
3. **Breathe Action Chip Layout Compression on WearOS**:
   - In `CravingPacingCard.kt`, `Row(horizontalArrangement = Arrangement.SpaceBetween)` allowed the craving-free text row to expand unconstrained, squeezing the "Breathe" action chip and causing its label to wrap onto two lines.

---

## 2. Architectural Fixes & Optimizations

### A. Dynamic Habit Log Craving Pacing (100% watchOS Parity)
- Added `HabitDateParser.parseToEpochMs(raw: String?): Long?` supporting ISO8601 UTC formats, OffsetDateTime, and PostgreSQL timestamps.
- Updated `WatchSessionManager.kt`:
  ```kotlin
  val lastSmokeTimestamp: Long?
      get() {
          val logs = cachedSmokesLogs
          if (logs.isNullOrEmpty()) return null
          val latest = logs.maxByOrNull {
              HabitDateParser.parseToEpochMs(it.logged_at) ?: 0L
          } ?: return null
          return HabitDateParser.parseToEpochMs(latest.logged_at)
      }
  ```
- If `lastSmokeTimestamp` is null (no smokes logged today), both platforms consistently display `"Smoke-Free Today! 🌟"`. Otherwise, they calculate the exact elapsed duration and format as `"{h}h {m}m craving-free"` or `"{m}m craving-free"`.

### B. Action Chip Fixed Layout & Text Multi-Line Wrapping
- In `CravingPacingCard.kt` (WearOS):
  - Left row assigned `Modifier.weight(1f).padding(end = 6.dp)`.
  - Craving status text configured with `maxLines = 2`, `lineHeight = 13.sp`.
  - Breathe action chip enforced with `Text(text = "Breathe", maxLines = 1, softWrap = false)`.
  - Recomposition throttled with a 30-second ticking `LaunchedEffect` and `remember` block.
- In `CravingPacingBadge.swift` (watchOS):
  - Added `.lineLimit(2)` and `.minimumScaleFactor(0.85)` to the status text.
  - Added `.fixedSize()` and `.lineLimit(1)` to the "Breathe" button.

### C. Zero-Allocation Compose Scroll Performance
- In `OrbitHubScreen.kt`:
  - Created `@Immutable` data models `WeatherData` and `CosmosData`.
  - Memoized Briefing text (`remember(streams, waterGoal, refreshTrigger)`).
  - Memoized Weather simulations and diurnal curve calculations (`remember(hour)`).
  - Memoized Cosmos solar/moon phase calculations (`remember(hour)`).
  - Memoized Macro Pillars breakdown (`remember(streams, refreshTrigger)`).
- In `PulseScreen.kt`:
  - Memoized dynamic circadian vitals and stress scores (`remember(hour)` and `remember(stressScore)`).

### D. Enforced R8 Minification & Mandatory Release Workflow in AGENTS.md
- Updated `.agents/AGENTS.md` with explicit rules mandating `./gradlew assembleRelease` for all WearOS wearable deployments, forbidding debug builds on physical smartwatches, and codifying zero-allocation scroll practices.

---

## 3. Verification & Deployment Results

| Platform / Target | Build Configuration | Artifact Size | Result |
| :--- | :--- | :---: | :--- |
| **Google Pixel Watch 5** | Release (R8 Minified) | ~8.8 MB | Installed & Launched via `adb` |
| **Apple Watch Ultra 2** | Release (Native watchOS) | Native Bundle | Verified & Launched via `devicectl` |
