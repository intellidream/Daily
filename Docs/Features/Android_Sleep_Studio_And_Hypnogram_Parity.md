# Android Sleep Studio & Hypnogram Parity (iOS Golden Standard)

## 1. Overview
This release resolves critical data-parsing anomalies and visual design discrepancies in the Android Sleep Studio (`SleepStudioView.kt`, `SleepHypnogramView.kt`), establishing 1:1 behavioral and graphical parity with the iOS golden standard (`SleepStudioView.swift`, `SleepHypnogramView.swift`).

---

## 2. Root Cause Analysis

### 2.1 Fatal Timestamp Ingestion Bug
- **Symptom:** The Sleep Hypnogram on Android displayed all sleep stages (e.g. 71 distinct sleep blocks recorded by Oura Ring / Apple Watch) as a single overlapping 3px vertical sliver at pixel coordinate 0 on the far left edge of the chart. Tapping to inspect sleep blocks had zero effect.
- **Root Cause:** In Supabase PostgREST responses (`health_daily_summary` and `health_sleep_sessions`), stage start and end times are stored as ISO-8601 strings without UTC offset (e.g. `"2026-11-08T00:06:59.000"`). 
  - `TimestampSerializer.parseIsoToEpoch()` attempted `Instant.parse()` and `OffsetDateTime.parse()`, both of which threw `DateTimeParseException` due to the absent timezone specifier.
  - The fallback parser `SimpleDateFormat("yyyy-MM-dd", Locale.US)` matched `"2026-11-08"` and **truncated the timestamp to midnight (`00:00:00.000Z`)**.
  - Consequently, all 71 stages had identical start and end times (`startTime = endTime = midnight`), reducing their elapsed timeline offset `(stage.startTime - session.startTime)` to `0.0` and calculated duration to `0s`.
  - When written to SQLite Room (`health_daily_summary_cache`), this corrupted midnight timestamp was persisted locally, permanently poisoning offline views until cache invalidation.

### 2.2 Missing Left Stage Labels & Guideline Discrepancies
- In iOS `SleepHypnogramView.swift`, the leading 44dp column displays color-coded semantic stage labels:
  - **Awake**: Coral Orange (`#FF7043`)
  - **REM**: Cyan Glow (`#26C6DA`)
  - **Light**: Sky Blue (`#42A5F5`)
  - **Deep**: Indigo Midnight (`#3949AB`)
- In Android `SleepHypnogramView.kt`, the labels were completely omitted from the layout, leaving a blank gap on the leading edge.
- Hourly vertical grid lines were drawn as solid lines on Android, while the iOS golden standard uses dashed stroke lines (`[3, 3]`).

### 2.3 Interactive Tap Hit-Testing Failure
- Android hit-testing checked `targetTime in stage.startTime..stage.endTime`. Because timestamps were collapsed to 0ms intervals, no hit was ever detected.
- Additionally, touch input lacked Y-axis lane awareness, causing ambiguous hits across vertically adjacent stages.

### 2.4 Sleep Studio Visual Inconsistencies
- **Origin Device Badge:** Missing hardware source icon in the `HeroSleepScoreCard` origin chip.
- **Score Progress Ring:** Rendered with a solid cyan stroke instead of the multi-stop angular gradient (`accentCyan` -> `accentBlue` -> `accentPurple`).
- **Sleep Architecture Metrics Grid:** `MetricTile` cards omitted the category icons (`Icons.Rounded.Nightlight`, `AutoAwesome`, `Bed`, `RemoveRedEye`) present in the iOS standard.

---

## 3. Implementation Details

### 3.1 Robust Universal ISO Timestamp Normalization
`TimestampSerializer.parseIsoToEpoch()` in `HabitModels.kt`, `FlexibleTimestampSerializer`, and `NullableTimestampSerializer` in `HealthModels.kt` were overhauled with comprehensive ISO normalization:
1. **Long/Epoch Millis & Seconds Detection:** Direct parsing for numeric timestamps.
2. **Standard Instant/OffsetDateTime:** Parses standard UTC (`Z`) and offset strings (`+02:00`, `-05:00`).
3. **LocalDateTime Parsing:** Uses `LocalDateTime.parse(normalized).toInstant(ZoneOffset.UTC)` for ISO strings lacking timezone indicators (`"2026-11-08T00:06:59.000"` or space-separated `"2026-11-08 00:06:59"`).
4. **Normalized 'Z' Fallback & LocalDate:** Gracefully falls back to start-of-day UTC for pure date strings (`"2026-11-08"`).

### 3.2 SleepStageType Tolerant Deserializer
Added `SleepStageTypeSerializer` to `SleepStageType` supporting case-insensitive deserialization and alias mapping (`"awake"`, `"wake"`, `"out_of_bed"`, `"rem"`, `"light"`, `"core"`, `"deep"`).

### 3.3 Complete Hypnogram Canvas Re-architecture
`SleepHypnogramView.kt` now mirrors iOS 1:1:
- **Left Stage Labels:** 44dp column displaying "Awake", "REM", "Light", "Deep" with exact hex tints (`0.85f` alpha) and horizontal lane guidelines.
- **Dashed Hourly Grid Lines:** Rendered with `PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 3.dp.toPx()), 0f)`.
- **Vertical Gradient Blocks:** Each stage block is rendered with `Brush.verticalGradient` (top `0.85f` alpha to bottom `0.60f` alpha, or `1.0f` to `0.80f` when selected), 4dp rounded corners, and dynamic border (`1.5dp` white when selected, `0.5dp` subtle white when unselected).
- **Dual-Axis Hit-Testing:** Detects both the tapped time along the X axis and the tapped lane along the Y axis, with fallback to any stage spanning that moment.
- **Inspection Pill Tooltip:** Animated capsule displaying stage color indicator, name, time range (`HH:mm - HH:mm`), and duration in minutes.

### 3.4 Sleep Studio Tab Polish (`SleepStudioView.kt`)
- **Device Origin Chip:** Added hardware icon via `DeviceSource.from(session.sourceDevice).iconType` (e.g. `Icons.Rounded.Adjust` for Oura Ring, `Icons.Rounded.Watch` for smartwatches, `Icons.Rounded.Smartphone` for phones).
- **Angular Gradient Radial Ring:** Replaced flat indicator with `Brush.sweepGradient` matching iOS (`accentCyan`, `0xFF2979FF`, `accentPurple`, `accentCyan`).
- **Architecture Metric Tiles:** Added category icons in the card header row (`Nightlight`, `AutoAwesome`, `Bed`, `RemoveRedEye`).
- **Granular Hypnogram Guard:** Uses `session.hasGranularHypnogram || session.stages.isNotEmpty()` to guarantee the hypnogram displays whenever stages exist.

### 3.5 Automated Cache Migration
- Bumped `CURRENT_SUMMARY_CACHE_VERSION` from `2` to `3` in `HealthDataRepository.kt`.
- Room database maintenance automatically executes:
  ```sql
  DELETE FROM health_daily_summary_cache WHERE summary_version < 3;
  ```
- Existing devices purge corrupted zero-length stage cache and seamlessly ingest corrected minute-accurate telemetry from Supabase.

---

## 4. Verification & Testing

### 4.1 Unit Testing
- Added `SleepModelsTest.kt` in `core-model`:
  - Verified ISO parsing with and without 'Z', space-separated dates, and epoch timestamps.
  - Verified `SleepStageRecord` deserialization and duration accuracy.
  - Verified `SleepStageType` case-insensitivity.
- Executed `./Android/gradlew -p Android testDebugUnitTest` — all unit test suites passed.

### 4.2 Physical Device Deployment
- Successfully built `app-debug.apk` and installed via `adb` (transport over TLS):
  - **Samsung Galaxy Z Fold 8 ("RADAR")**: Verified package installation and successful cache eviction of version 2 records.
  - **Google Pixel 9 Pro ("Trapper")**: Verified package installation.
