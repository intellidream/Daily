# Cosmos 9-DOF Sensor Fusion, Live Sky Auto-Lift & Magnetic Calibration Architecture

**Date:** November 2026  
**Platforms:** iOS / Foldable (`DailyCore` + `CosmosMotionService`), Android / Foldable (`CosmosMotionManager` + `CosmosScreen`), macOS (Graceful Desktop Hide), Windows 11 WinUI 3 (Auto-Detected 2-in-1 / Tablet IMU, Hidden on Desktop/VM)

---

## 1. Architectural Goals & Zero-Regression Guarantees

When pointing a smartphone or foldable device toward the real sky ("Compass / Live Sky" mode, inspired by *Stellarium Mobile*, *SkySafari*, and *Apple Night Sky*), the star map must track the observer's optical line of sight with:
- **Zero Euler Gimbal Lock at Zenith (`+90°`) and Nadir (`-90°`):** Full right-handed orthonormal 3x3 camera basis `(right, up, forward)` in **NWZ** (`+X = True North, +Y = True West, +Z = Zenith`) projected directly from unit quaternions (`customBasisNWZ`).
- **True Geographic North Alignment:** Correcting Magnetic North via local geomagnetic declination from **CoreLocation / `locationd`** + embedded offline **NOAA World Magnetic Model (WMM-2025)** on iOS, and **`android.hardware.GeomagneticField`** on Android, incorporating GPS ellipsoidal/barometric altitude (`LocationManager.lastKnownAltitudeMeters` / `Location.altitude`) for topocentric parallax and horizon accuracy.
- **FOV-Adaptive Optical Image Stabilization (OIS):** Quaternion SLERP velocity damping scales dynamically by $\sqrt{\text{FOV} / 60^\circ}$, suppressing $8\text{–}12\text{ Hz}$ physiological hand micro-tremors when zoomed into `8° 7x50` binoculars or `2°` telescope magnification without introducing slew lag at wide angles (`60°–120°`).
- **Zero Supabase Egress & Zero Background Battery Drain:** 100% on-device hardware sensor + SIMD math (`0 bytes` of network/Supabase traffic). Hardware IMU listeners register strictly while Cosmos is visible onscreen and unregister immediately on navigation away, app backgrounding, screen lock, or explicit manual toggle-off.

---

## 2. Smart "Lift-to-Sky" (`>= +6°`) & Multi-Touch State Machine

1. **`standbyAutoLift` (Default on Every Fresh Entry to Cosmos on Phones & Foldables):**
   - Evaluates **unsmoothed** optical-axis elevation directly from the raw hardware quaternion (`rawQ` / `rawQuat`) *before* adaptive SLERP filtering, eliminating filter convergence delay when lifting from a resting hand pose (`-40°..-60°`).
   - Sustaining unsmoothed optical elevation **`>= +6.0°` above the horizon for `>= 180ms`** automatically snaps `smoothedQuat = rawQuat`, engages **`activeLiveSky`** at 100Hz–120Hz with zero transition lag, synchronizes the simulation clock to real-time (`LIVE`), and triggers haptic confirmation.
   - On Android (`CosmosMotionManager`), `SensorManager.SENSOR_DELAY_GAME` is bound idempotently once on observatory entry (`ensureHardwareSensorsRegistered`) so transitioning from `STANDBY_AUTO_LIFT` to `ACTIVE_LIVE_SKY` never invokes re-entrant `unregisterListener`/`registerListener` inside `SensorEventListener.onSensorChanged`. Every fresh entry into Cosmos resets prior `MANUAL_OFF` state back to `STANDBY_AUTO_LIFT` while keeping `0` active listeners whenever Cosmos is closed or backgrounded.
   - Geometrically suppressed on foldables *only* when genuinely resting flat in **Tabletop Flex Mode** (`HALF_OPENED` horizontal crease with hinge angle `65°..138°` and optical elevation `< +4°`), preventing false tabletop lockouts when holding an unfolded Galaxy Z Fold at `160°..178°` toward the sky.
2. **`activeLiveSky` (100Hz–120Hz Full 9-DOF ProMotion / LTPO Tracking):**
   - **2-Finger Pinch-to-Zoom:** Zooms smoothly along the live optical crosshair *without* cancelling sensor tracking.
   - **1-Finger Deliberate Pan / Drag:** Uses density-scaled touch slop (`>= 14pt` on iOS, `max(touchSlop * 1.25f, 32px)` on Android) so thin/curved bezel palm brushes never accidentally cancel Live Sky or Auto-Lift, while intentional panning disengages immediately (`pausedAfterDrag`), levels horizon roll (`0°`), and surfaces a 1-tap **"Resume Live Sky"** pill (also re-arming automatically after lowering `< -5°` and lifting back `>= +14°`).
3. **`manualOff` (Explicit Top HUD Toggle Off):**
   - Tapping the top HUD Compass button while active turns off all IMU hardware listeners for the remainder of the current observatory visit until tapped back on or until the user re-enters Cosmos.

---

## 2B. 120Hz Zero-Invalidation Rendering Pipeline (iOS ProMotion & Android Compose)

- **Zero `@Published` / `ObservableObject` Thrash on iOS:** `CosmosMotionService` streams 100Hz `(azimuth, altitude, roll, BasisNWZ)` samples directly into `@Observable CosmosCameraController` via `onAttitudeSample` (with integer-quantized `displayAzimuthDeg` / `displayAltitudeDeg` for the top HUD readout and `0.5s` / `1.0 µT` throttling on diagnostic magnetic UI badges), eliminating full-screen SwiftUI `CosmosDetailView` body rebuilds during sensor motion.
- **Direct GPU `Canvas(opaque: true)` VSync Evaluation:** `CosmosDetailView` evaluates `vm.projectSkyScene(...)` strictly inside the `Canvas` render closure under unthrottled ProMotion `TimelineView(.animation)` while keeping gesture recognizers static outside `TimelineView`.
- **1Hz Ephemeris & SGP4 Caching + Zero-Allocation Flat Star Indexing:** `CosmosViewModel` pre-bakes flat star index pairs for all 88 IAU constellations and 14 asterisms (zero per-frame `Dictionary` hashing) and caches VSOP87/ELP2000 planetary coordinates, Saturn ring tilt, Galilean moons, and the 31-point SGP4 ISS orbital arc at 1Hz (`ensureSceneEphemerisFresh`), keeping 120Hz frame projection purely matrix-bound (`< 0.8ms` per frame on A-series/M-series silicon).

---

## 3. Magnetic Interference Detection (`µT`), Figure-8 Calibration & Balcony Tools

Real-world urban stargazing frequently suffers from hard-iron and soft-iron magnetic distortions (MagSafe cases/chargers, car mounts, speakers, reinforced-concrete balconies, and steel railings):
1. **Real-Time Flux Density Anomaly Detector (`µT`):**
   - Compares measured ambient magnetic vector norm $\|\mathbf{B}\| = \sqrt{B_x^2 + B_y^2 + B_z^2}$ ($\mu\text{T}$) against the local WMM expected geomagnetic intensity ($\sim 48\text{–}50\,\mu\text{T}$ in Central/Eastern Europe; global range $22\text{–}67\,\mu\text{T}$).
   - Flags `hasMagneticInterference` immediately when $\|\mathbf{B}\| > \max(72\,\mu\text{T}, 1.48 \times B_{\text{expected}})$ or $\|\mathbf{B}\| < \min(18\,\mu\text{T}, 0.42 \times B_{\text{expected}})$, surfacing an interactive warning pill (`Mag Interference · Tap to Fix`).
2. **Interactive Sensor & Figure-8 (`∞`) Calibration Sheet:**
   - Displays live $\mu\text{T}$ flux vs WMM expected baseline, local magnetic declination, 3-axis Figure-8 (`∞`) calibration instructions, and **Gyro-Stabilized Balcony Lock (Ignore Magnetometer)** (`TYPE_GAME_ROTATION_VECTOR` on Android / `.xArbitraryZVertical` on iOS anchored to true azimuth).
3. **1-Tap Celestial "Align Compass" on Any Target:**
   - When Live Sky is active and any celestial object (e.g., **Moon**, **Venus**, **Jupiter**, **Saturn**, or **Sirius**) is selected in the Target Inspector, tapping **"Align Compass" / "Align"** computes $\Delta\text{Az} = \text{Az}_{\text{ephemeris}} - \text{Az}_{\text{sensor}}$ (automatically engaging Gyro-Stabilized Lock if magnetic interference is present), locking the celestial sphere to sub-degree accuracy even on a steel balcony.
4. **3-Tier Hardware Fallback on Android:**
   - Tier 1: `Sensor.TYPE_ROTATION_VECTOR` (Gyroscope + Accelerometer + Magnetometer).
   - Tier 2: `Sensor.TYPE_GAME_ROTATION_VECTOR` (Gyroscope + Accelerometer — Balcony Gyro-Lock).
   - Tier 3: `Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR` or `TYPE_ACCELEROMETER + TYPE_MAGNETIC_FIELD` (`SensorManager.getRotationMatrix`) with enhanced tremor filtering ($\alpha_{\min} = 0.04, \alpha_{\max} = 0.24$) for gyroscope-less Android devices.

---

## 4. 360° Roll-Invariant Sky, Horizon & Planetary Rendering

- **Unified Clockwise `cameraRollDegrees` Convention:** Standardized across `DailyCore` (Swift), `core-model` (Kotlin), and `Daily.WinUI` (C#) so positive `cameraRollDegrees` represents clockwise device tilt around the optical axis (`rx = cr * r0x - sr * u0x`, `ux = sr * r0x + cr * u0x`), matching direct quaternion `customBasisNWZ` to machine precision ($<10^{-9}$).
- **360° Horizon & Ground Polygon:** Replaces monotonic `screenX` filtering with continuous forward-hemisphere azimuth sampling closed along the projected Earth Nadir screen vector `(-rz, +uz)`, preventing horizon tearing or ground inversion at steep roll angles ($\pm 90^\circ, 180^\circ$).
- **Cohesive Celestial Roll:** Rayleigh twilight atmosphere gradients, Moon bright-limb terminators, Saturn ring planes, Jupiter's 4 Galilean moons, and Messier/Caldwell galaxy position angles all rotate cohesively with device roll on both iOS and Android.
