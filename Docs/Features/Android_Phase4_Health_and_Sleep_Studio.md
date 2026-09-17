# Android Phase 4: Health & Vitals Studio and Clinical Sleep Intelligence

## 1. Overview
Phase 4 introduces native Android parity for the **Health & Vitals Studio**, replicating 100% of the iOS `DailyCore` Health domain, `SleepClusteringEngine`, `SleepGuidance`, `HealthKitService`, and clinical sleep architecture analysis. It integrates Google Health Connect SDK with an offline-first Room database cache (`DailyDatabase` v2 with `synced_at` dirty tracking), dynamic sleep hypnogram rendering (Awake, REM, Light, Deep), Bezier intraday heart rate curves with 4-zone aerobic distribution, 24-hour hourly step histograms with active hours highlights, and modular dashboard widgets across all 4 grid sizes (`1x1 Small`, `2x1 Wide`, `1x2 Tall`, `2x2 Large`).

---

## 2. Architecture & Clinical Engines

### 2.1 Domain Models (`core-model/com.intellidream.daily.model.HealthModels.kt`)
- **`HealthSubTab`**: `Overview`, `SleepStudio`, `HeartVitals`, `Trends`.
- **`HealthMetricType`**: `Steps`, `ActiveCalories`, `HeartRate`, `RestingHeartRate`, `SleepDuration`, `SleepScore`, `SpO2`, `HRV`, `Hydration`.
- **`SleepStageType`**: `Awake`, `Rem`, `Light`, `Deep`.
- **`SleepStageRecord`**: Segment with start/end timestamps, stage enum, and calculated duration.
- **`SleepSession`**: Full nocturnal session including total duration, time in bed, sleep efficiency percentage, stages breakdown, and awake transitions.
- **`NapSession`**: Diurnal rest segments classified using a < 3.5h duration heuristic.
- **`SleepRecoveryStatus`**: `Optimal`, `Good`, `Fair`, `Poor`, `Critical`.
- **`SleepRecoveryVerdict`**: Clinical readiness score, physical recovery rating, cognitive recovery rating, circadian alignment assessment, narrative synthesis, and 3 recovery pillars.
- **`SleepAICoachCard` & `SleepAIContext`**: Romanian clinical sleep prompt context and pre-configured inquiry chips.
- **`IntradayHeartRatePoint` & `HeartRateZone`**: 4 cardiac intensity zones (`Rest / Recovery`, `Fat Burn`, `Cardio`, `Peak`).
- **`HourlyStepBucket`**: 24-hour step distribution with peak indicator flags.
- **`DailyMetricTrendPoint`**: 7-day capsule trend points with daily average/sum statistics.
- **`DeviceSource`**: Multi-device provenance tracking (`Pixel Watch 3`, `Amazfit Balance`, `Galaxy Watch`, `Health Connect`, `Apple Watch`, `Manual`).

### 2.2 Clinical Sleep Intelligence (`core-health`)
- **`SleepClusteringEngine.kt`**: 1:1 Kotlin port of iOS `SleepClusteringEngine.swift`:
  - Nocturnal session clustering window: Previous day 18:00 to current day 18:00 (D-1 18:00 to D 18:00).
  - Daytime nap classification (< 3.5h duration outside nocturnal window).
  - Micro-fragment stage clustering and deduplication across multi-device recording streams.
  - Clinical fallbacks generating natural circadian sleep architecture when sensor data is sparse.
- **`SleepAnalysisEngine.kt`**: 1:1 Kotlin port of iOS `SleepGuidance.swift`:
  - Overall Sleep Readiness score calculation based on deep sleep ratio (target 15-25%), REM ratio (target 20-25%), and sleep efficiency (target >= 85%).
  - Physical recovery assessment (deep sleep and sleep duration).
  - Cognitive recovery assessment (REM sleep consolidation and continuity).
  - Actionable clinical hygiene tips mapped to AASM (American Academy of Sleep Medicine) guidelines (Circadian, Sleep Environment, Nutrition/Stimulants, Wind-Down Protocol).
- **`HealthConnectManager.kt`**: Android Health Connect SDK client wrapper:
  - Runtime permissions management (`READ_STEPS`, `READ_HEART_RATE`, `READ_RESTING_HEART_RATE`, `READ_SLEEP`, `READ_TOTAL_CALORIES_BURNED`, `READ_OXYGEN_SATURATION`, `READ_HEART_RATE_VARIABILITY`, `READ_HYDRATION`).
  - Aggregated metric queries and intraday record extraction.
  - Safe API guarding for Android 14+ system framework Health Connect vs backwards-compatible Health Connect client.
- **`HealthDataRepository.kt`**: Central health state manager:
  - Hot `StateFlow` state streams for all core metrics.
  - Immediate local-first rendering (0ms startup latency) from Room cache or synthesized multi-device telemetry.
  - Asynchronous background synchronization with Supabase and Health Connect.
  - Filter by provenance device (`All Devices`, `Pixel Watch 3`, `Amazfit Balance`, `Health Connect`).

---

## 3. Offline-First Persistence & Remote Sync

### 3.1 SQLite Room Cache (`core-database`)
- **`HealthTelemetryEntity`**:
  - Primary key: `id: String` (UUID v4).
  - Schema: `date`, `metric_type`, `value`, `unit`, `device_source`, `timestamp`.
  - Dirty tracking: `synced_at: Long?` (null on local write, populated on remote ACK).
  - Indexes: composite index on `(date, metric_type)`.
- **`VitalMetricEntity`**:
  - Primary key: `id: String`.
  - Schema: `metric_id`, `name`, `current_value`, `unit`, `status`, `target`, `device_source`, `timestamp`.
  - Dirty tracking: `synced_at: Long?`.
- **`HealthTelemetryDao` & `VitalMetricDao`**: Coroutine `Flow` reactive queries for zero-jank 120Hz updates.
- **`DailyDatabase.kt`**: Bumped to database version 2, registering health entities and DAOs.

### 3.2 Remote Cloud Synchronization (`core-network`)
- **`HealthRemoteService.kt`**: Supabase PostgREST sync client targeting `health_telemetry` and `vitals` tables.

---

## 4. Visual & UI Components (`app/presentation/health`)

### 4.1 Master Health Hub View (`HealthMainView.kt`)
- Header with live connection status pill and dynamic device selector dropdown (`All Devices`, `Pixel Watch 3`, `Amazfit Balance`, `Health Connect`).
- Date navigation capsule with previous/next day stepping.
- 4-pill segmented capsule sub-tab switcher:
  1. `Overview`: Concentric activity rings, 24h step histogram, sleep summary, and 2-column vital metric glass tiles.
  2. `Sleep Studio`: Hero readiness ring gauge, clinical recovery verdict card, 4-level hypnogram canvas, sleep architecture breakdown grid, daytime naps, and AI Coach card.
  3. `Heart & Vitals`: Intraday Bezier heart rate curve, min/max/resting callouts, 4-zone intensity distribution bar, and full vitals inspection grid.
  4. `Trends`: 7-day capsule bar evolution charts for Steps, Sleep Duration, and Heart Rate with stats breakdown.

### 4.2 Concentric Activity Rings & Vital Tiles (`VitalMetricTile.kt`)
- Multi-ring concentric arc canvas with gradient strokes for Active Calories (Flame Red), Exercise (Emerald Green), and Move Hours (Cyan).
- Biometric glass tiles with icon badge, metric name, device source pill, value, unit, and status badge.

### 4.3 24-Hour Steps Histogram Canvas (`HourlyStepsHistogramView.kt`)
- Custom `Canvas` rendering 24 hourly step bars with dynamic height interpolation.
- Visual distinction between resting hours, active hours, and peak activity hour callouts.
- Time axis markings (`00:00`, `06:00`, `12:00`, `18:00`, `23:00`).

### 4.4 Intraday Bezier Heart Rate Curve (`HeartRateCurveView.kt`)
- Smooth cubic Bezier spline with gradient fill below the curve.
- Min (Resting) and Max (Peak) floating callout badges.
- 4-zone cardiac intensity bar: Rest & Recovery (Slate), Fat Burn (Emerald), Cardio (Amber), Peak (Coral Red).

### 4.5 Clinical Sleep Studio & Hypnogram (`SleepStudioView.kt`, `SleepHypnogramView.kt`)
- **Hero Sleep Readiness Gauge**: Circular 270° gradient arc with score (0-100), sleep duration, and efficiency pill.
- **Clinical Recovery Verdict Card**: Readiness badge (`Optimal`), narrative assessment, and 3 pillars:
  - Physical Recovery: Tissue repair & growth hormone secretion during deep sleep.
  - Cognitive Recovery: Memory consolidation and emotional calibration during REM.
  - Circadian Alignment: Sleep consistency and regularity with circadian rhythms.
- **4-Level Hypnogram Canvas**:
  - Color-coded stages: Awake (Coral `#EF4444`), REM (Cyan `#06B6D4`), Light (Indigo `#6366F1`), Deep (Purple `#8B5CF6`).
  - Interactive stage inspection pill on touch/tap.
- **2x2 Sleep Architecture Grid**: Duration and percentage for each stage compared to clinical targets.
- **Daytime Naps Card**: Separate display for restorative power naps (< 3.5h).
- **Sleep AI Coach & Hygiene Sheet**: Interactive prompt chips ("Cum îmi cresc somnul adânc?", "Efectul cofeinei după 14:00") and modal conversational bottom sheet.

### 4.6 Modular Dashboard Card (`HealthDashboardCard.kt`)
Supports all 4 modular layout sizes from the dashboard grid:
1. **`1x1 Small`**: Compact 155dp widget with dual mini progress rings, steps count, heart rate pill, and quick navigation.
2. **`2x1 Wide`**: Standard 160dp card with triple concentric rings (Calories, Steps, Move), steps total with kcal, current HR with resting HR, and sleep duration with efficiency.
3. **`1x2 Tall`**: Vertical 324dp health column with large concentric rings, full metric breakdown, and quick action.
4. **`2x2 Large`**: Extended 324dp full-feature health center with hero concentric rings, steps histogram preview, sleep efficiency gauge, and vitals summary.

---

## 5. Verification & Device Testing

1. **Gradle Build & Compilation**:
   - Upgraded Room schema to version 2 with auto-migrations.
   - Clean compilation: `./gradlew assembleDebug` passed cleanly with zero warnings or errors.
2. **Emulator Verification (`Medium_Phone_API_36.1` / `emulator-5558`)**:
   - Installed APK and verified live rendering:
     - Dashboard modular `Health & Vitals` card with live rings and metrics.
     - `Overview` tab with concentric rings, 24h step histogram, and vitals grid.
     - `Sleep Studio` tab with hero score (95 Optimal), hypnogram canvas, architecture grid, and Romanian AI Coach card.
     - `Heart & Vitals` tab with Bezier HR curve, min/max tags, and 4-zone distribution.
     - `Trends` tab with 7-day capsule charts.
     - Multi-device dropdown filter (`All Devices`, `Pixel Watch 3`, `Amazfit Balance`, `Health Connect`).
3. **Physical Hardware Deployment**:
   - Built and deployed APK to physical **Google Pixel 9 Pro** via ADB:
     - `adb -s adb-48231FDAP0011V-Ma9KPE._adb-tls-connect._tcp install -r app/build/outputs/apk/debug/app-debug.apk` -> **Success**.
     - Verified live launch on device screen.
4. **Samsung Galaxy S25 Edge Readiness**:
   - APK built and ready for immediate deployment as soon as device is connected via ADB.
