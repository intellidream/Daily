# Android 16/17 Parity, Biometric Integrity, and Foldable Optimization

## Overview
This document outlines the architectural enhancements and parity updates delivered to the native Android app (`com.intellidream.daily`), bringing it to 1:1 functional and visual alignment with the iOS gold standard while adhering to modern Android 16/17 standards and foldable responsiveness (specifically optimized for Google Pixel 9 Pro and Samsung Galaxy Z Fold 8 "RADAR").

---

## 1. Biometric Integrity & Stress Engine Nullability (1:1 with iOS)

### The Problem
Previously, when biometric telemetry (HRV, heart rate, sleep) was absent (such as fresh installs, guest mode, or unmeasured days), the Android stress calculation engine and dashboard cards defaulted to arbitrary values (`32` / `Calm` or `0` / `Calm`). Furthermore, virtual engines like `"StressWatch"` or `"Daily Biometric Engine"` could leak into the device picker and vitals telemetry.

### The Solution
1. **Device Source Filtering (`core-model`)**:
   - Added `DeviceSource.Oura` and updated `DeviceSource.from()`.
   - Implemented `DeviceSource.isVirtualEngine`:
     ```kotlin
     val isVirtualEngine: Boolean
         get() = when (this) {
             StressWatch, DailyBiometricEngine, Unknown -> true
             else -> false
         }
     ```
   - All source selection menus and vitals telemetry now strictly filter `!src.isVirtualEngine`.

2. **Nullable Stress Calculation (`core-health`)**:
   - Updated `StressAnalysisEngine.calculateStress(...)` return type to `Pair<StressAnalysisResult, List<IntradayStressPoint>>?`.
   - Enforced hard prerequisite:
     ```kotlin
     if (hrvMs == null && hrTelemetry.isEmpty()) {
         return null
     }
     ```
   - Only hours containing actual biometric telemetry points generate intraday stress points; unmeasured hours are no longer populated with simulated data.

3. **Repository State & Vitals Coordination (`HealthDataRepository`)**:
   - Added `latestBpm: StateFlow<Double?>` for live current heart rate tracking.
   - When biometrics are absent:
     - `_stressAnalysis.value = null`
     - `_intradayStress.value = emptyList()`
     - `vitalsMap.remove(HealthMetricType.STRESS)`
   - When biometrics are present:
     - Dynamically resolves honest hardware source device (`AppleWatch`, `PixelWatch`, `GalaxyWatch`, `Garmin`, `Whoop`, `Oura`, `HealthConnect`).

4. **Unit Test Coverage (`core-health/src/test`)**:
   - Added comprehensive suite in `StressAnalysisEngineTest.kt` verifying:
     - Missing biometrics returns `null`
     - Sigmoid stress scoring thresholds
     - Sedentary heart rate elevation
     - Peak recovery Zen state
     - Virtual engine filtering

---

## 2. Dashboard & Studio Honest Empty States

1. **Dashboard Health Cards (`HealthDashboardCard.kt` & `StressDashboardCard.kt`)**:
   - Small, Wide, Tall, and Large variants updated.
   - When stress is unmeasured:
     - Renders `🐵 --` and `No Data` with a muted indicator dot.
     - Gauge displays empty track without fake indicator.
     - Guidance displays "Wear watch or sync biometrics".
     - Eliminates misleading `0 Calm` displays.

2. **Stress Studio (`StressStudioView.kt`)**:
   - Introduced `EmptyStressCard`:
     - Displays glowing monkey avatar with `-- / 100 STRESS` and `NO TELEMETRY RECORDED` badge.
     - Educational Autonomic Tone card explaining HRV and sedentary HR correlation.
     - Guided Autonomic Breathwork (Stanford Huberman Physiological Sigh, 4-7-8, Box Breathing) remains fully accessible and playable without needing prior biometric telemetry.
   - Forwarded `sourceDevice` parameter to `HeroStressCard` for stacked hardware attribution pill.

3. **Activity Hero Dual Concentric Rings (`HealthMainView.kt`)**:
   - Updated `ActivityHeroCard` and `OverviewSection` to accept `latestBpm: Double?`.
   - "Current BPM" prioritizes live `latestBpm` with fallback to `averageBpm`, rendering `--` when no heart rate is available.

4. **Glance App Widgets (`DailyCombinedGlanceWidget` & `DailyStressGlanceWidget`)**:
   - Made stress score and level nullable.
   - Combined widget displays `--` when unmeasured instead of forced `32`.
   - Stress widget displays `NO DATA`, `--`, and "Sync biometrics to measure stress".

---

## 3. Modern Android 16/17 Standards & Foldable Responsiveness

1. **Predictive Back System Integration**:
   - Added `android:enableOnBackInvokedCallback="true"` to `<application>` in `AndroidManifest.xml`.
   - Native compose `BackHandler` hooks seamlessly into Android 14/15/16 predictive back gesture transitions.

2. **Foldable & Tablet Responsiveness (Samsung Galaxy Z Fold 8 "RADAR")**:
   - In `MainActivity.kt`, the root tab container (`DailyRootScreen`) wraps all main screen views with:
     ```kotlin
     Box(
         modifier = Modifier
             .fillMaxSize()
             .statusBarsPadding(),
         contentAlignment = Alignment.TopCenter
     ) {
         Box(
             modifier = Modifier
                 .fillMaxSize()
                 .widthIn(max = 760.dp)
         ) { ... }
     }
     ```
   - On standard phones (e.g., Pixel 9 Pro ~412dp), content spans 100% width naturally.
   - On unfolded foldables (Galaxy Z Fold 8 ~800dp) and tablets, the interface remains centered, preventing excessive horizontal stretch and maintaining optimal typography and card proportions.
   - Floating Glass Capsule navigation remains centered at `Alignment.BottomCenter` with `wrapContentWidth()`.

---

## 4. Verification & Deployment Matrix

| Target | Platform / Spec | Result |
| :--- | :--- | :--- |
| **Gradle Unit Tests** | `core-health:test`, `core-model:test` | **PASS** (100%) |
| **Android Emulator** | `Medium_Phone_API_36.1` (Android 16 API 36) | **PASS** (Verified visually, screenshots captured) |
| **Google Pixel 9 Pro** | Physical Device (`caiman` / wireless adb) | **PASS** (Installed `app-debug.apk` & launched live) |
| **Samsung Galaxy Z Fold 8 ("RADAR")** | Physical Device (`SM-F971B` / wireless adb) | **PASS** (Installed `app-debug.apk` & launched live) |
| **iOS Core & App** | Gold Standard (`iOS/`, `DailyCore/`, `DailyWidgets/`) | **0 bytes touched** (Zero regressions) |
