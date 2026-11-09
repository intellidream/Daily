# Windows 11 Desktop Widgets Real Biometrics and Astronomy Parity 2026

## 1. Context and Problem Statement
When running the independent micro-process `Daily.WidgetsHost.exe` for Windows 11 desktop widgets, several metrics in the dedicated views and Executive Combined Brief view were displaying fallback values:
1. **Sleep & Recovery**: Scores and durations showed static fallbacks (e.g. `85` and `7h 40m` / `7h 45m`) instead of the user's real sleep sessions and scores.
2. **Stress & Vitals**: Showed hardcoded fallbacks (e.g. `22 Low`, `HRV 64 ms`, `62 bpm`) instead of real tracked stress, HRV, and resting heart rate.
3. **Cosmos & Astronomy**: Stargazing index displayed a hardcoded `84/100`, visible planets showed static `"🪐 Jupiter & Saturn"`, satellite pass displayed hardcoded `"🛰️ 21:42 (Mag -2.8)"`, and moon times showed static `"Moonrise: 17:15 · Moonset: 05:40"`.

---

## 2. Root Cause Analysis

### Health & Sleep Data Architecture
1. **JSON Deserialization Mismatch**:
   - In SQLite `Daily.db3`, the table `health_daily_summary_cache` stores offline summaries where the column `SummaryJson` contains a serialized `DailyHealthSummaryPayload` (version 2.0/2.1 health schema).
   - `WidgetsHostHealthService.cs` was attempting to deserialize `entity.SummaryJson` as `HealthDailySummaryRecord`:
     ```csharp
     rec = JsonSerializer.Deserialize<HealthDailySummaryRecord>(entity.SummaryJson, HealthJsonSerializer.DefaultOptions);
     ```
   - Because `DailyHealthSummaryPayload`'s root keys (`sleep`, `activity`, `cardiovascular`, `stress`) do not match `HealthDailySummaryRecord`'s flat properties (`sleep_score`, `sleep_asleep_s`, `stress_avg`, `rhr`), deserialization either threw an exception or populated an object with all `null` properties.
   - Consequently, `DesktopSleepWidgetView`, `DesktopStressWidgetView`, and `DesktopCombinedWidgetView` fell back to hardcoded defaults (85 score, 460 mins, 22 stress, 64 HRV).

2. **Sleep Session Extraction**:
   - `WidgetsHostHealthService.GetSleepSessionsAsync` was generating a synthetic primary sleep session with proportional deep/rem/light percentages instead of parsing `summary.Summary.Sleep.PrimarySession` and its granular stages hypnogram from Oura Ring / smartwatches.

3. **Date Boundary Transition**:
   - If the user awakens early in the morning or opens the host before today's sleep session completes syncing to `Daily.db3`, today's summary (`2026-11-09`) may contain 0 sleep seconds while yesterday's (`2026-11-08`) holds the completed sleep session. No multi-day lookback fallback existed.

### Cosmos & Astronomy Data Architecture
1. **Hardcoded Ephemeris**:
   - `DesktopCosmosWidgetView.xaml.cs` and `DesktopCombinedWidgetView.xaml.cs` hardcoded celestial strings without querying the linked `AstronomyService.Shared` and `AstronomyEngine`.
2. **Missing Satellite Propagator**:
   - `SGP4Propagator.cs` was not linked in `Daily.WidgetsHost.csproj`, preventing native NORAD / Vallado orbital pass solving.

---

## 3. Implementation Details

### A. SQLite & Schema Parsing Parity (`WidgetsHostServices.cs`)
- **Proper Payload Deserialization**:
  Deserializes `entity.SummaryJson` into `DailyHealthSummaryPayload` and maps:
  - `SleepScore`: `entity.SleepScore ?? payload?.Sleep?.PrimarySession?.SleepScore ?? payload?.Sleep?.Guidance?.Verdict?.ReadinessScore`
  - `SleepAsleepS`: `entity.SleepAsleepS ?? payload?.Sleep?.PrimarySession?.AsleepSeconds ?? payload?.Sleep?.PrimarySession?.DurationSeconds`
  - `StressAvg`: `entity.StressAvg ?? payload?.Stress?.DailyAverageScore ?? payload?.Stress?.CurrentScore`
  - `Rhr`: `entity.Rhr ?? payload?.Cardiovascular?.RestingHeartRateBpm`
  - `HrvRmssd`: `entity.HrvRmssd ?? payload?.Stress?.BiometricDrivers?.CurrentHrvMs ?? payload?.Stress?.BiometricDrivers?.BaselineHrvMs`
  - `Steps`: `entity.Steps ?? payload?.Activity?.TotalSteps`
  - `ActiveKcal`: `entity.ActiveKcal ?? payload?.Activity?.ActiveCaloriesKcal`
- **Dynamic Stress from HRV**:
  If stress score is not explicitly in summary, estimates autonomic arousal dynamically from HRV RMSSD:
  - $\text{RMSSD} \ge 70\text{ ms} \implies 18\text{ (Low / Calm)}$
  - $\text{RMSSD} \ge 55\text{ ms} \implies 26\text{ (Low / Relaxed)}$
  - $\text{RMSSD} \ge 40\text{ ms} \implies 38\text{ (Balanced)}$
  - $\text{RMSSD} \ge 25\text{ ms} \implies 58\text{ (Elevated)}$
  - $\text{RMSSD} < 25\text{ ms} \implies 76\text{ (High Strain)}$
- **Sleep Session Extraction with Granular Hypnogram**:
  Extracts the real `StartTime`, `EndTime`, `DeepSeconds`, `RemSeconds`, `LightSeconds`, `AwakeSeconds`, and stages telemetry from `primary.Stages` (e.g. Oura Ring / Wearable Hub).
- **Multi-Day Lookback**:
  If today's date has no sleep session or 0 sleep score, queries `date.AddDays(-1)` and the most recent valid summary.

### B. Cosmos Ephemeris & Stargazing Parity (`DesktopCosmosWidgetView.xaml.cs`)
- **Real Observer Coordinates**:
  Queries `Daily_WinUI.Services.SettingsService.Load()` for `LastLatitude` and `LastLongitude` (defaulting to Bucharest 44.4323, 26.1063 if unconfigured).
- **Real Moon Phase & Rise/Set**:
  Calculates real moon phase, illumination fraction, moon glyph, and rise/set times via `_astronomyService.GetRiseTransitSet(CelestialBody.Moon, now, lat, lon)`.
- **Real Twilight / Golden Hour**:
  Calculates sunset and golden hour window using `_astronomyService.GetSunTimes(now, lat, lon)`.
- **Real Visible Planets**:
  Queries `_astronomyService.GetAllVisibleBodies(now, lat, lon)`. If daytime, queries tonight's astronomical dusk window to identify planets above the horizon (Venus, Mars, Jupiter, Saturn, Mercury).
- **Real Stargazing Quality Score**:
  Queries `WeatherClient.GetCachedSnapshot().Clouds` and executes `_astronomyService.EvaluateStargazingConditions(lat, lon, now, cloudCoverTotal, bortleClass: 4)`.
- **Real ISS Satellite Passes**:
  Links `SGP4Propagator.cs` in `Daily.WidgetsHost.csproj`. When `iss_omm.json` is cached, executes `SGP4Propagator.PredictVisiblePasses(omm, lat, lon, ...)` to find the next visible pass with start time, compass direction, and peak magnitude.

### C. Executive Combined Brief Parity (`DesktopCombinedWidgetView.xaml.cs`)
- Connected real sleep score and duration with multi-day lookback.
- Connected real stress score and pulse.
- Replaced static `"84 Sky"` with dynamic calculated `{skyScore} Sky`.

---

## 4. Verification and Cross-Platform Stability

1. **Compilation Matrix**:
   - `Daily.WidgetsHost.csproj` (ARM64 & x64): **0 Error(s)**, 0 Warning(s) on new code.
   - `Daily.WinUI.csproj` (ARM64 & x64): **0 Error(s)**, 0 Warning(s) on new code.
2. **Process Integrity**:
   - Terminated existing instances and launched `Daily.WidgetsHost.exe` (PID 4708) and `Daily.WinUI.exe` (PID 12216) in interactive Console Session 1 via Task Scheduler.
   - Sent IPC `refresh` command via named pipe `Daily_WidgetsHost_IpcPipe` and verified execution in `daily_widgetshost_debug.log`.
3. **Target Scope Adherence**:
   - Strictly modified files within `WinUI/` and `Docs/Features/`.
   - Never modified iOS, macOS, watchOS, Android, or Wear OS codebases.
