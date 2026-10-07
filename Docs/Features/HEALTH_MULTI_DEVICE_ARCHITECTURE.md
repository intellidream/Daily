# Generic Multi-Device Health Synchronization Architecture

## 1. Overview & Core Philosophy

The Daily platform provides an autonomous, device-agnostic health synchronization pipeline uniting multiple host smartphones (**iOS**, **Android**) and arbitrary peripheral sensor wearables (**Apple Watch**, **Oura Ring**, **Pixel Watch / WearOS / Fitbit**, **Amazfit Balance**, **Samsung Health**, **Garmin**, **Whoop**, **Polar**, **Withings**, etc.) into a single, cohesive timeline.

### 1.1 Non-Negotiable Tenets
1. **Generic & Device-Agnostic**: Zero hardcoding of device models, hostnames, or hardware platforms. Any phone running Daily automatically binds its own native host name (`UIDevice.current.name` on iOS, `BluetoothAdapter.getDefaultAdapter()?.name` / `Settings.Global.DEVICE_NAME` on Android).
2. **Compound Device Keys**: Every telemetry record is tagged with a compound key:
   $$\text{CompoundKey} = \text{[Host Phone Name]} \text{ - } \text{[Peripheral / Sensor Name]}$$
   Examples:
   - `Schmitz - Apple Health`
   - `Schmitz - Oura Ring`
   - `TRAPPER - Health Connect`
   - `TRAPPER - Fitbit`
   - `RADAR - Health Connect`
3. **Compound Key & Sensor Normalization**:
   - Stripping reverse-domain package names (`com.fitbit.FitbitMobile` $\rightarrow$ `Fitbit`, `com.google.android.apps.fitness` $\rightarrow$ `Google Fit`).
   - Resolving compound strings: `TRAPPER - com.fitbit.FitbitMobile` dynamically normalizes to `TRAPPER - Fitbit`.
   - Bare prefixless filtering: when compound sources (e.g. `TRAPPER - Health Connect` or `Schmitz - Apple Health`) are present, bare un-prefixed duplicates (e.g. `Health Connect`, `Apple Health`) are automatically suppressed from the device selector menu to eliminate duplicate clutter.
4. **Deterministic Cross-Platform Color Encoding**:
   - Both Swift (`DeviceColorPalette`) and Kotlin (`DeviceColorPalette`) use an identical 31-multiplier polynomial UTF-8 hash:
     $$\text{hash} = \sum_{i=0}^{n-1} s[i] \cdot 31^{n-1-i}$$
   - Any device name (`Schmitz - Oura Ring`, `TRAPPER - Fitbit`, etc.) resolves to the exact same color on both platforms across 9 high-contrast neon tints.
5. **Unified Hardware Glyphs**:
   - **Smartwatch** (Apple Watch, Pixel Watch, Galaxy Watch, Fitbit, Garmin, Whoop, Polar, Withings): `applewatch` (iOS), `Icons.Rounded.Watch` (Android).
   - **Smart Ring** (Oura Ring): `circle.circle` (iOS), `Icons.Rounded.Adjust` (Android).
   - **Health Platform** (Apple Health, Health Connect): `heart.text.square.fill` (iOS), `Icons.Rounded.Favorite` (Android).
   - **Handset / Phone** (Phone Pedometer): `iphone` (iOS), `Icons.Rounded.Smartphone` (Android).
   - **Sensor / Generic**: `sensor.fill` (iOS), `Icons.Rounded.Sensors` (Android).
6. **Live Real-Time Heart Rate Priority**:
   - The dashboard card and Health Hub prioritize live `latestBpm` read directly from HealthKit (iOS) and Health Connect (Android), falling back gracefully to the daily average BPM.
7. **120Hz Liquid Glass Navigation Fluidity**:
   - 15-second debounce throttle and warm-cache return in `performLoadDataForSelectedDate` on iOS, eliminating main-thread hitching and stutter when returning from Health Hub to the Dashboard.
8. **Lean Active Telemetry Retention**: The raw `health_telemetry` table in Supabase retains strictly today's intraday telemetry. Past days are summarized and permanently archived into `health_daily_summary` (Single Source of Truth).
9. **Local Cache First**: On app launch and tab switching, SQLite/Room on Android and UserDefaults/AppGroup on iOS serve cached canonical snapshots in under 50ms, eliminating any UI freeze or spinner stutter.

---

## 2. Multi-Device Presentation & UI Parity

### 2.1 Color Palette Contract
Both iOS (`DeviceColorPalette`) and Android (`DeviceColorPalette`) share an identical deterministic 9-color palette:

| Index | Name | Hex Code | Purpose |
|:---:|:---|:---:|:---|
| 0 | Electric Sky Blue | `#3897F0` | Default iOS / HealthKit primary |
| 1 | Mint Emerald | `#00D287` | Health Connect / Wearables |
| 2 | Sunset Orange | `#FF8C42` | Smart rings / Oura |
| 3 | Amethyst Violet | `#9D65FF` | Sleep sensors / Hypnograms |
| 4 | Coral Rose | `#FF5C77` | Cardiovascular / Heart sensors |
| 5 | Cyber Yellow | `#FFC837` | Activity / Calorie burn |
| 6 | Deep Teal | `#00B4D8` | Respiratory / SpO2 |
| 7 | Hot Pink | `#F72585` | Specialized accessories |
| 8 | Electric Lime | `#70E000` | Autonomous engines |

### 2.2 Device Selector (`DeviceSelectorMenu`)
Located at the top-right of both the iOS and Android Health Hubs:
- **"All Devices"**: Unified composite view displaying the freshest, most accurate biometric across all reporting devices. Badged with an active device tint.
- **Per-Device Chips**: Every available compound source (`● [Host] - [Wearable]`) is presented with its distinct colored dot chip and hardware icon.
- **Custom Liquid Glass Dropdown**: On iOS, replaced UIKit `Menu` with an ultra-fluid custom Liquid Glass overlay (`deviceDropdownOverlay`) preserving exact color tints, SF Symbols, and glowing dot shadows in Dark Mode.
- **Filtered Drill-Down**: Selecting a specific compound device isolates the activity rings, step cadence hourly histograms, sleep staging hypnogram, and vitals strictly to that hardware source.

### 2.3 Vital Metric Origin Badging (`DeviceOriginBadge`)
Reusable component deployed across both platforms:
- **iOS**: `DeviceOriginBadge.swift`
- **Android**: `DeviceOriginBadge.kt`

Rendered consistently in:
- Activity Hero card (`ActivityHeroCard`)
- Step Cadence hourly histogram (`HourlyStepsHistogramView`)
- Sleep Overview card (`SleepOverviewPreviewCard`)
- Stress Overview card (`StressOverviewPreviewCard`)
- All Vital Metric tiles (`VitalMetricTile`: Resting HR, HRV, SpO2, Respiratory Rate, Blood Pressure, etc.)

---

## 3. Data Synchronization & Delta Watermark

### 3.1 5-Minute Active Sync Loop
When Daily is open and active in the foreground:
- A periodic loop triggers synchronization every 5 minutes (`startActiveSyncLoop()`).
- On app resume (`scenePhase == .active` on iOS, `ON_RESUME` on Android), `refreshIfStale()` immediately triggers a sync if more than 300 seconds have elapsed.

### 3.2 Delta Upload Watermarking
To prevent uploading duplicate rows:
- Both clients maintain `lastPushedTelemetryEpochMs`.
- Only records with `startTime >= watermark` or `endTime >= watermark` are pushed to Supabase.
- An additional `in("external_id", batch)` probe drops any existing IDs prior to insertion.
- The `health-engine` Edge Function is invoked with a 3-minute throttle per date, preventing rate-limit exhaustion.

---

## 4. Verification & Testing Matrix

| Target | Platform / Environment | Scope | Status |
|:---|:---|:---|:---:|
| **DailyCore Swift Tests** | macOS Darwin ARM64 | 8 test suites, 55 unit tests (`swift test`) | **PASSED (55/55)** |
| **Android Health Tests** | JVM Debug | Unit tests (`:core-health:testDebugUnitTest`) | **PASSED** |
| **Android APK Build** | Gradle 9.6 | Debug APK assemble (`:app:assembleDebug`) | **PASSED** |
| **Android Emulator** | `Medium_Phone_API_36.1` | Installed, launched, tested Device Selector & colored dots | **VERIFIED (Visual)** |
| **iOS Simulator** | `SimulaPhone` (iOS 26.2) | Installed, launched via `-startTabHealth`, Health Hub verified | **VERIFIED (Visual)** |
| **Physical iPhone** | `Schmitz` (iPhone 16 Pro) | Built, codesigned with Apple Dev profile, deployed via `devicectl` | **DEPLOYED & VERIFIED** |
| **Physical Android (TRAPPER)** | Google Pixel 9 Pro (`caiman`, wireless adb `192.168.3.8:39221`) | Streamed install `app-debug.apk`, launched PID 16104 | **DEPLOYED & VERIFIED LIVE** |
| **Physical Android (RADAR)** | Samsung Galaxy Z Fold 8 (`SM-F971B`, wireless adb `192.168.3.64:32995`) | Streamed install `app-debug.apk`, launched PID 30513 | **DEPLOYED & VERIFIED LIVE** |
