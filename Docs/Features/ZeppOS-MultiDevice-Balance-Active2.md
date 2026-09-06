# Zepp OS Multi-Device UI Adaptation: Amazfit Balance & Active 2

## Context & Overview
The DayOne Orbit Zepp OS companion app was originally designed specifically for the rectangular/square display of the **Amazfit Active 2** (390x450). With the addition of the **Amazfit Balance** (480x480 round circular display), the app required multi-device UI adaptation to:
1. Ensure the UI fits naturally on a circular AMOLED display without bezel clipping or corner occlusion.
2. Scale up visual elements (progress rings, histograms, buttons, typography) on the larger 1.5" circular screen.
3. Guarantee **zero regressions** for the Amazfit Active 2 (maintaining 1:1 pixel parity with the original square layout).

---

## 1. Network & Hardware Communication (Amazfit Balance Wi-Fi)

### Architectural Constraints:
- **No Direct Socket / Fetch on Device**: Although Amazfit Balance has physical 2.4GHz Wi-Fi hardware, Zepp OS reserves Wi-Fi strictly for system-level operations (OTA firmware downloads, offline OSM map files, music transfer). Third-party mini programs (`BasePage`) cannot open direct Wi-Fi TCP/HTTP sockets.
- **Side Service Proxy**: Network requests (`fetch`) run exclusively inside `app-side/index.js` (`BaseSideService`), hosted in the Zepp app on the paired smartphone. Communication between watch and phone uses Bluetooth LE via `@zeppos/zml`.
- **Performance**: Enabling Wi-Fi on the Balance does **not** alter or accelerate mini-program data sync speeds; data still passes through the phone BLE bridge. No network code changes were needed or applicable.

---

## 2. Dynamic Device Detection Architecture

The application checks hardware specifications at runtime using `@zos/device`:

```javascript
import { getDeviceInfo, SCREEN_SHAPE_ROUND } from '@zos/device'

let isRound = false
let screenW = 390
let screenH = 450

try {
  const devInfo = getDeviceInfo()
  if (devInfo) {
    screenW = devInfo.width || 390
    screenH = devInfo.height || 450
    isRound = devInfo.screenShape === SCREEN_SHAPE_ROUND || screenW === 480 || (devInfo.width === devInfo.height && devInfo.width >= 454)
  }
} catch (e) {
  logger.error('getDeviceInfo error', e)
}

const cfg = isRound ? ROUND_CONFIG : SQUARE_CONFIG
```

### Permissions:
`ZeppOS/app.json` requires `"data:os.device.info"` to allow querying device hardware information via `getDeviceInfo()`.

---

## 3. Layout Specifications Matrix

| Component / Screen | Amazfit Active 2 (Square 390x450) | Amazfit Balance (Round 480x480) | Design Rationale |
| :--- | :--- | :--- | :--- |
| **Viewport & Swiper** | `w: 390, h: 450, pageH: 450` | `w: 480, h: 480, pageH: 480` | Native screen resolution matching. |
| **Page Titles (All 4)**| `y: 80, text_size: 24` | `y: 50, text_size: 26` | Retained at top positions with clean top margins. |
| **Progress Arc (P1 & P3)** | `x: 20, y: 150, w: 200, h: 200, line_width: 16` | `x: 30, y: 136, w: 216, h: 216, line_width: 18` | Centered vertically alongside action buttons; thicker stroke on Round. |
| **Arc Center Text** | `text_size: 26` | `text_size: 28` | Better readability on 1.5" screen. |
| **Action Buttons (P1 & P3)**| Dark gray (`0x222222`, press `0x111111`) | Dark gray (`0x222222`, press `0x111111`) | Unified dark aesthetic, letting emojis (💧, ☕, 🔥, ⚡) stand out. |
| **P1 Button Sizes** | `x: 240, w: 130, h: 58, r: 29, y: [145, 217, 289]` | `x: 265, w: 165, h: 62, r: 31, y: [136, 210, 284]` | Centered vertically, ending before breakdown text. |
| **P3 Button Sizes** | `x: 240, w: 130, h: 62, r: 31, y: [180, 258]` | `x: 265, w: 165, h: 68, r: 34, y: [168, 252]` | Vertically centered with arc midpoint. |
| **Breakdown Details Text**| `x: 0, y: 358, w: 390, h: 26` (centered) | `x: 30, y: 366, w: 420, h: 26, text_size: 14` (centered) | Placed below rings & buttons; aligned across the bottom. |
| **7-Day Histograms** | `x: 45, y: 145, w: 300, h: 195, bar: 30, space: 15` | `x: 80, y: 135, w: 320, h: 215, bar: 32, space: 16` | Mathematically centered horizontally on screen center axis (45px margins on Active 2, 80px margins on Balance). |
| **Chart Color Legends** | `y: 358, h: 30, text_size: 15` (centered) | `y: 366, h: 30, text_size: 15` (centered) | Positioned below histogram, aligning with breakdown texts baseline. |
| **Smokes Chart Color** | `item_color: 0xff3b30` (Apple watchOS Red) | `item_color: 0xff3b30` (Apple watchOS Red) | Restored vibrant red matching watchOS (`Color.red`). |
| **About Page Icon** | `icon.png` (124x124) at `x: 133, y: 40` | `logo.png` (110x110) at `x: 185, y: 35` | Perfectly centered `(480-110)/2 = 185`, eliminating overlap with text. |
| **Unpair Button (P5)** | `x: 45, y: 340, w: 300, h: 60, r: 30` | `x: 70, y: 325, w: 340, h: 60, r: 30` | Centered with safe margins (`dy=145, dx_max=191`). |
| **Pairing PIN** | `x: 0, y: 180, w: 390, h: 100, text_size: 48` | `x: 0, y: 175, w: 480, h: 100, text_size: 54` | Prominent 54pt green OTP PIN. |
| **Syncing Indicator** | `icon: (141, 406, 20x20)`, `text: (169, 404, 15pt)` | `icon: (186, 418, 20x20)`, `text: (214, 416, 15pt)` | Dedicated 20x20 crisp PNG sync icon paired with 15pt text, centered with 22-26px gap below breakdown text. |

---

## 4. Haptic Feedback Integration (`@zos/sensor.Vibrator`)

Both Amazfit Balance and Amazfit Active 2 support tactile feedback through their integrated vibration hardware without requiring special permissions in `app.json`:

1. **Sensor & Constants Initialization (`@zos/sensor`)**:
   - Imports official constants: `Vibrator`, `VIBRATOR_SCENE_SHORT_STRONG` (mode 25), `VIBRATOR_SCENE_DURATION` (mode 28), `VIBRATOR_SCENE_NOTIFICATION` (mode 0).
   - Instantiates `vibratorInstance = new Vibrator()` lazily / in `onInit()`.
2. **Motor Mechanics & Scene Selection**:
   - **Habit Logging (Bubbles & Smokes)**: Uses `VIBRATOR_SCENE_DURATION` (600ms solid pulse, mode 28). On ERM (eccentric rotating mass) motors like in Amazfit Active 2, ultra-short 20ms pulses lack the mechanical time for the motor coil to spin up the rotor weight; 600ms provides palpable, satisfying tactile confirmation on both Active 2 and Balance.
   - **Sync Completion**: Uses `VIBRATOR_SCENE_NOTIFICATION` (mode 0, two short continuous pulses) triggered when `setSyncing` transitions from `true` to `false`.
3. **Multi-Signature Invocation Strategy**:
   - Executes `v.setMode({ mode })` per Zepp OS 3.0 TypeScript specification, with fallback to `v.setMode(mode)`.
   - Fires `v.start({ mode })` and `v.start()`.
   - Never calls `v.stop()` immediately before `v.start()` (which previously interrupted the motor queue). Instead, a delayed `v.stop()` is scheduled 700ms post-trigger to cleanly reset the motor channel for subsequent calls.
   - Includes fallback to legacy `hmSensor.createSensor(hmSensor.id.VIBRATE)` for backward compatibility.
4. **Lifecycle**:
   - Sensor reference created in `onInit()`.
   - Any active motor vibration cleanly stopped in `onDestroy()`.

---

## 5. Verification & Build
The multi-target build is compiled using the Zeus CLI:
```bash
npm run build
```
Outputs: `dist/20001-DayOne_Orbit-1.0.0-<timestamp>.zab` containing binaries for all defined platforms (`platforms.common.r` 480 and `platforms.common.s` 390).
