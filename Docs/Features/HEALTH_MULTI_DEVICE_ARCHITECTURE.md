# Generic Multi-Device Health Synchronization Architecture

## 1. Overview & Core Philosophy

The Daily platform provides an autonomous, device-agnostic health synchronization pipeline uniting multiple host smartphones (**iOS**, **Android**) and arbitrary peripheral sensor wearables (**Apple Watch**, **Oura Ring**, **Pixel Watch / WearOS / Fitbit**, **Amazfit Balance**, etc.) into a single, cohesive timeline.

### 1.1 Non-Negotiable Tenets
1. **Generic & Device-Agnostic**: Zero hardcoding of device models, hostnames, or hardware platforms. Any phone running Daily automatically binds its own native host name (`UIDevice.current.name` on iOS, `BluetoothAdapter.getDefaultAdapter()?.name` / `Settings.Global.DEVICE_NAME` on Android).
2. **Compound Device Keys**: Every telemetry record is tagged with a compound key:
   $$\text{CompoundKey} = \text{[Host Phone Name]} \text{ - } \text{[Peripheral / Sensor Name]}$$
   Examples:
   - `Schmitz - Apple Health`
   - `Schmitz - Oura Ring`
   - `TRAPPER - Health Connect`
   - `TRAPPER - Pixel Watch 5 (Fitbit)`
   - `Radar - Health Connect`
3. **Deterministic Color Encoding**: Every compound source receives an auto-assigned color from a deterministic 9-color high-contrast palette based on an FNV-1a hash of the key.
4. **Lean Active Telemetry Retention**: The raw `health_telemetry` table in Supabase retains strictly today's intraday telemetry. Past days are summarized and permanently archived into `health_daily_summary` (Single Source of Truth).
5. **No Pedometer Downgrades**: Local phone pedometers sitting on desks cannot downgrade higher step counts reported by wearables in "All Devices" aggregation mode.
6. **Local Cache First**: On app launch and tab switching, SQLite/Room on Android and UserDefaults/AppGroup on iOS serve cached canonical snapshots in under 50ms, eliminating any UI freeze or spinner stutter.

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
- **Per-Device Chips**: Every available compound source (`● [Host] - [Wearable]`) is presented with its distinct colored dot chip.
- **Filtered Drill-Down**: Selecting a specific compound device isolates the activity rings, step cadence hourly histograms, sleep staging hypnogram, and vitals strictly to that hardware source.

### 2.3 Vital Metric Origin Badging
Each metric card (Resting HR, HRV, SpO2, Respiratory Rate, Active Calories) displays a compact pill badge with the color dot and name of the device that reported the value, e.g.:
$$\text{● } \text{Schmitz - Oura Ring} \quad \text{or} \quad \text{● } \text{TRAPPER - Pixel Watch 5}$$

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
| **Android APK Build** | Gradle 9.6 | Debug APK assemble (`:app:assembleDebug`) | **PASSED (11s)** |
| **Android Emulator** | `Medium_Phone_API_36.1` | Installed, launched, tested Device Selector & colored dots | **VERIFIED (Visual)** |
| **iOS Simulator** | `SimulaPhone` (iOS 26.2) | Installed, launched via `-startTabHealth`, Health Hub verified | **VERIFIED (Visual)** |
| **Physical iPhone** | `Schmitz` (iPhone 16 Pro) | Built, codesigned with Apple Dev profile, deployed via `devicectl` | **DEPLOYED & INSTALLED** |
