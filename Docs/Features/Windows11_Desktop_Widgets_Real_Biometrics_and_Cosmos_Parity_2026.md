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
- **Sleep Session Extraction with Granular Hypnogram & Real Asleep Time**:
  Extracts the real `StartTime`, `EndTime`, `DeepSeconds`, `RemSeconds`, `LightSeconds`, `AwakeSeconds`, and stages telemetry from `primary.Stages` (e.g. Oura Ring / Wearable Hub).
  - Inside the Progress Ring (`SmallDurationText`, `MediumCenterDurationText`), the widget strictly displays the **actual asleep time** (`asleepMins`), e.g. `7h 28m`, matching the Health Hub and Executive Combined Brief.
  - In the subtitle under the title (`MediumScheduleSubtitle`, `LargeScheduleSubtitle`), the total time in bed is displayed in parentheses alongside the bedtime/wakeup schedule: `00:04 → 08:11 (8h 06m in bed)`.
- **Multi-Day Lookback**:
  If today's date has no sleep session or 0 sleep score, queries `date.AddDays(-1)` and the most recent valid summary.

### B. Cosmos Ephemeris, Live Atmospheric Seeing & ISS Passes (`DesktopCosmosWidgetView.xaml.cs`)
- **Real Observer Coordinates & Bortle Class**:
  Queries `Daily_WinUI.Services.SettingsService.Load()` for `LastLatitude` and `LastLongitude` (defaulting to Bucharest 44.4323, 26.1063 if unconfigured), and `BortleClass` (defaulting to 5).
- **Live Atmospheric Seeing & Multi-Layer Clouds**:
  Integrated `CosmosLiveService.Shared.FetchLiveBundleAsync(lat, lon)` which asynchronously fetches:
  - Open-Meteo UTC forecast with multi-layer cloud cover (`cloud_cover`, `cloud_cover_low`, `cloud_cover_mid`, `cloud_cover_high`), visibility, temperature, and dew point.
  - 7Timer astronomical seeing (`seeingArcsec` e.g. 1.4", transparency label e.g. "Crystal (<0.4 mag)").
  - Evaluates live deterministic stargazing score using `_astronomyService.EvaluateStargazingConditions(...)` with live cloud layers and seeing instead of mocked/fallback values.
- **Real Moon Phase & Rise/Set**:
  Calculates real moon phase, illumination fraction, moon glyph, and rise/set times via `_astronomyService.GetRiseTransitSet(CelestialBody.Moon, now, lat, lon)`.
- **Real Twilight / Golden Hour**:
  Calculates sunset and golden hour window using `_astronomyService.GetSunTimes(now, lat, lon)`.
- **Real Visible Planets**:
  Queries `_astronomyService.GetAllVisibleBodies(now, lat, lon)`. If daytime, queries tonight's astronomical dusk window to identify planets above the horizon (Venus, Mars, Jupiter, Saturn, Mercury).
- **Live ISS Satellite Passes**:
  `CosmosLiveService` queries and caches CelesTrak OMM records for ISS (NORAD 25544) in `%LOCALAPPDATA%\Daily\CosmosCache\iss_omm.json`. Executes `SGP4Propagator.PredictVisiblePasses(omm, lat, lon, ...)` to find the next visible pass with start time, compass direction, max altitude, and peak magnitude.

### C. Executive Combined Brief Parity (`DesktopCombinedWidgetView.xaml.cs`)
- Connected real sleep score and duration (`summary.SleepAsleepS` = `7h 28m`) with multi-day lookback.
- Connected real stress score and pulse.
- Replaced static `"84 Sky"` with dynamic calculated `{skyScore} Sky` powered by `CosmosLiveService.Shared.FetchLiveBundleAsync(lat, lon)`.

---

## 4. Desktop Widgets Auto-Refresh Architecture

The Windows 11 desktop widgets employ a multi-tiered refresh strategy designed for maximum responsiveness with near-zero idle CPU and power consumption:

1. **Periodic Background Maintenance Timer (15 Minutes)**:
   - In `Daily.WidgetsHost/App.xaml.cs`, a `DispatcherTimer` set to `TimeSpan.FromMinutes(15)` periodically triggers `DesktopWidgetManager.Instance.RefreshAllWidgets()`.
   - This ensures ephemeris, weather forecasts, and background data remain fresh even if the main application is closed.

2. **Instant Event-Driven Named Pipe IPC (`Daily_WidgetsHost_IpcPipe`)**:
   - Whenever the main app (`Daily.WinUI.exe`) syncs with Supabase, completes a cloud pull, or registers user changes (habits logged, TagDoS pills edited, smart ledger entries added), it sends the command `"refresh"` through the named pipe `Daily_WidgetsHost_IpcPipe`.
   - `Daily.WidgetsHost.exe` listens asynchronously on a dedicated thread. When `"refresh"` arrives, it instantly dispatches `RefreshAllWidgets()` on the UI thread without any polling delay.

3. **Window Initialization & Startup**:
   - Each widget window triggers `RefreshData()` upon its XAML `Loaded` event.
   - When `Daily.WidgetsHost.exe` is started on boot or user login, all widgets instantly render the latest cached telemetry.

4. **System Resume & Wake from Sleep (`SessionGuardian`)**:
   - `SessionGuardian` in `Daily.WinUI` monitors system time jumps. When the machine wakes from sleep or standby, it automatically triggers a Supabase synchronization and sends an IPC `"refresh"` to the widget host.

5. **User Manual Refresh**:
   - Right-clicking any widget brings up the context menu where clicking "Refresh Data" immediately triggers `RefreshData()` for all widgets.
   - Clicking Refresh in the Windows System Tray companion or Glance popover also dispatches an IPC refresh.

---

## 5. Verification and Cross-Platform Stability

1. **Compilation Matrix**:
   - `Daily.WidgetsHost.csproj` (ARM64 & x64): **0 Error(s)**, 0 Warning(s) on new code.
   - `Daily.WinUI.csproj` (ARM64 & x64): **0 Error(s)**, 0 Warning(s) on new code.
2. **Process Integrity**:
   - Terminated existing instances and launched `Daily.WidgetsHost.exe` (PID 13056) and `Daily.WinUI.exe` (PID 17096) in interactive Console Session 1 via Task Scheduler.
   - Verified that `sky_weather.json` and `iss_omm.json` in `%LOCALAPPDATA%\Daily\CosmosCache` are populated with live Open-Meteo UTC cloud layers and CelesTrak orbital records.
   - Sent IPC `refresh` command via named pipe `Daily_WidgetsHost_IpcPipe` and verified execution in `daily_widgetshost_debug.log`.
3. **Target Scope Adherence**:
   - Strictly modified files within `WinUI/` and `Docs/Features/`.
   - Never modified iOS, macOS, watchOS, Android, or Wear OS codebases.
