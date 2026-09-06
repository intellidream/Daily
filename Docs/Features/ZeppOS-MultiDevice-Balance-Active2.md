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
| **Page Title** | `y: 80, text_size: 24` | `y: 50, text_size: 26` | Lifted upward to avoid crowding circular center. |
| **Progress Arc (P1 & P3)** | `x: 20, y: 160, w: 200, h: 200, line_width: 16` | `x: 30, y: 125, w: 216, h: 216, line_width: 18` | Larger ring, thicker arc stroke. |
| **Arc Center Text** | `text_size: 26` | `text_size: 28` | Better readability on 1.5" screen. |
| **Action Buttons (P1 & P3)**| Dark gray (`0x222222`, press `0x111111`) | Dark gray (`0x222222`, press `0x111111`) | Unified dark aesthetic, letting emojis (💧, ☕, 🔥, ⚡) stand out. |
| **P1 Button Sizes** | `x: 240, w: 130, h: 60, r: 30, y: [150, 230, 310]` | `x: 265, w: 165, h: 62, r: 31, y: [120, 195, 270]` | Wider touch targets (165px) within circle safe zone. |
| **P3 Button Sizes** | `x: 240, w: 130, h: 60, r: 30, y: [185, 275]` | `x: 265, w: 165, h: 68, r: 34, y: [150, 240]` | Larger button height (68px) and font (24). |
| **Breakdown Details Text**| `x: 10, y: 370, w: 220, h: 40` (left aligned) | `x: 30, y: 350, w: 420, h: 30, text_size: 14` (centered) | Prevents bottom-left bezel clipping and leaves clear gap above sync. |
| **7-Day Histograms** | `x: 20, y: 180, w: 350, h: 180, bar: 30, space: 15` | `x: 70, y: 135, w: 340, h: 210, bar: 28, space: 14` | Centered 280px bar spread inside 340px container, eliminating right truncation. |
| **Smokes Chart Color** | `item_color: 0xff3b30` (Apple watchOS Red) | `item_color: 0xff3b30` (Apple watchOS Red) | Restored vibrant red matching watchOS (`Color.red`). |
| **About Page Icon** | `icon.png` (124x124) at `x: 133, y: 40` | `logo.png` (110x110) at `x: 185, y: 35` | Perfectly centered `(480-110)/2 = 185`, eliminating overlap with text. |
| **Unpair Button (P5)** | `x: 45, y: 340, w: 300, h: 60, r: 30` | `x: 70, y: 325, w: 340, h: 60, r: 30` | Centered with safe margins (`dy=145, dx_max=191`). |
| **Pairing PIN** | `x: 0, y: 180, w: 390, h: 100, text_size: 48` | `x: 0, y: 175, w: 480, h: 100, text_size: 54` | Prominent 54pt green OTP PIN. |
| **Syncing Indicator** | `x: 0, y: 410, w: 390, h: 30` | `x: 0, y: 412, w: 480, h: 24, text_size: 13` | Centered, positioned comfortably without truncation. |

---

## 4. Verification & Build
The multi-target build is compiled using the Zeus CLI:
```bash
npm run build
```
Outputs: `dist/20001-DayOne_Orbit-1.0.0-<timestamp>.zab` containing binaries for all defined platforms (`platforms.common.r` 480 and `platforms.common.s` 390).
