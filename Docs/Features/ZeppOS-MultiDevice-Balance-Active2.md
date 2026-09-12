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
| **Page Titles (All 4)**| `y: 80, text_size: 24` (`💧 Bubbles`, `💧 7 Days`, `🔥 Smokes`, `🔥 7 Days`) | `y: 50, text_size: 26` (`💧 Bubbles`, `💧 7 Days`, `🔥 Smokes`, `🔥 7 Days`) | Retained at top positions with clean top margins; chart titles simplified to '7 Days'. |
| **Date/Week Nav Row** | `y: 114, left: 35, right: 313, text: 80 (w: 230), size: 16` | `y: 90, left: 75, right: 361, text: 120 (w: 240), size: 17` | Dedicated temporal navigation row flanking date/week labels (`◀ Today ▶` / `◀ This Week ▶`), with `▶` hidden on current date/week. |
| **Progress Arc (P1 & P3)** | `x: 20, y: 150, w: 200, h: 200, line_width: 16` | `x: 30, y: 136, w: 216, h: 216, line_width: 18` | Centered vertically alongside action buttons; thicker stroke on Round. |
| **Arc Center Text** | `text_size: 26` | `text_size: 28` | Better readability on 1.5" screen. |
| **Action Buttons (P1 & P3)**| Dark gray (`0x222222`, press `0x111111`) | Dark gray (`0x222222`, press `0x111111`) | Unified dark aesthetic, letting emojis (💧, ☕, 🔥, ⚡) stand out. |
| **P1 Button Sizes** | `x: 240, w: 130, h: 58, r: 29, y: [145, 217, 289]` | `x: 265, w: 165, h: 62, r: 31, y: [136, 210, 284]` | Centered vertically, ending before breakdown text. |
| **P3 Button Sizes** | `x: 240, w: 130, h: 62, r: 31, y: [180, 258]` | `x: 265, w: 165, h: 68, r: 34, y: [168, 252]` | Vertically centered with arc midpoint. |
| **Breakdown Details Text**| `x: 0, y: 358, w: 390, h: 26` (centered) | `x: 30, y: 366, w: 420, h: 26, text_size: 14` (centered) | Placed below rings & buttons; aligned across the bottom. |
| **7-Day Histograms** | `x: 41, y: 145, w: 340, h: 195, bar: 30, space: 14` | `x: 72, y: 135, w: 360, h: 215, bar: 32, space: 16` | Mathematically centered on screen axis (41px margins on Active 2; 72px margins on Balance). Container width $w$ expanded to prevent right-edge clipping. Solid, generous bar widths without cramped spacing. |
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

## 5. Temporal Navigation & Historical Habit Management

To allow inspecting and recording habits for past dates, as well as browsing historical week trends, all 4 habit screens integrate a unified temporal navigation system:

### 1. Navigation Controls & Balanced Vertical Layout (`navRow`)
- **Visuals & Dimensions**:
  - **Amazfit Active 2 (Square 390x450)**:
    - Title: `y: 66, h: 30` (ends at $y=96$).
    - `navRow`: `y: 112, h: 40`, `btnW: 46`, `btnH: 40, radius: 12`, `leftX: 28, rightX: 316`, `textX: 78, textW: 234, textH: 40`.
    - Main Content (Arc/Buttons/Chart): starts at $y = 168$.
    - Breakdown/Legend: $y = 376..404$.
    - Syncing Indicator: $y = 416..440$.
    - **Vertical Breathing Room**: 16px gap between Title and NavRow, 16px gap between NavRow and Content, completely eliminating the previous top crowding and centering the whole screen.
  - **Amazfit Balance (Round 480x480)**:
    - Title: `y: 52, h: 32` (ends at $y=84$).
    - `navRow`: `y: 102, h: 42`, `btnW: 48`, `btnH: 42, radius: 12`, `leftX: 74, rightX: 358`, `textX: 126, textW: 228, textH: 42`.
    - Main Content (Arc/Buttons/Chart): starts at $y = 160..162$.
    - Breakdown/Legend: $y = 386..415$.
    - Syncing Indicator: $y = 424..448$.
    - **Vertical Breathing Room**: 18px gap between Title and NavRow, 16–18px gap between NavRow and Content, maintaining 30px+ clearance to circular bezel at all edges.
- **Anti-Truncation & Vertical Clearance**:
  - Full-height buttons (`40px` on Active 2, `42px` on Balance) with dedicated `arrow_size: 16-18` guarantee that `◀` and `▶` are never clipped.
- **Color Accent**: Left/right buttons match the screen's theme accent (`0x00aaff` for Bubbles / 💧 7 Days, `0xff5555` for Smokes / 🔥 7 Days).
- **Future Boundary Guard**: The `▶` forward button is automatically hidden when the user is on the current date (`dayOffset === 0`) or current week (`weekOffset === 0`), completely preventing navigation into future dates.

### 2. Temporal Modes & Labels:
- **Day Screens (💧 Bubbles & 🔥 Smokes)**:
  - `offset = 0` $\rightarrow$ `Today`
  - `offset = -1` $\rightarrow$ `Yesterday`
  - `offset < -1` $\rightarrow$ `Sun, 6 Sep` (Day of week, Date, Month)
  - Fetches habit totals for the exact 24-hour midnight window via `GET_HABITS_TODAY` with `day_offset`.
- **7-Day Chart Screens (💧 7 Days & 🔥 7 Days)**:
  - Titles simplified from previous verbose labels to `💧 7 Days` and `🔥 7 Days`.
  - `offset = 0` $\rightarrow$ `This Week`
  - `offset = -1` $\rightarrow$ `Last Week`
  - `offset < -1` $\rightarrow$ `24 Aug - 30 Aug` (7-day date window range)
  - Fetches the 7 daily buckets for that specific week via `GET_HABITS_WEEK` with `week_offset`.

### 3. Historical Habit Logging:
- When a user logs a habit (`💧 300`, `☕ 100`, `🔥 Cig`, `⚡ Heat`) while viewing a past day (`dayOffset < 0`), the companion app computes the target timestamp `logged_at` for that past date.
- `app-side/index.js` receives `logged_at` and stores it into Supabase `habits_logs` with the historical timestamp rather than `now()`.
- If the logged date falls within the current 7-day chart window, the corresponding histogram bar updates optimistically.

### 4. Haptic Feedback on Navigation:
- Every tap on `◀` or `▶` triggers `triggerHaptic('nav')`, invoking `VIBRATOR_SCENE_DURATION` (600ms solid pulse, mode 28) to provide instantaneous, satisfying physical confirmation across both ERM (Active 2) and LRA (Balance) motors.

---

## 6. Verification & Build
The multi-target build is compiled using the Zeus CLI:
```bash
npm run build
```
Outputs: `dist/20001-DayOne_Orbit-1.0.0-<timestamp>.zab` containing binaries for all defined platforms (`platforms.common.r` 480 and `platforms.common.s` 390).

---

## 7. Dynamic Histogram Re-rendering & WatchOS Parity Polish

### 1. Instant Histogram Re-rendering on Week Navigation
- **Root Cause Identified**: In `@zos/ui`, the `prop.UPDATE_DATA` property is only supported by `widget.SCROLL_LIST`. When applied to `widget.HISTOGRAM`, `.setProperty(prop.UPDATE_DATA, ...)` was a silent no-op. The histogram would only update if the user swiped to another screen and returned (triggering a redraw in the swiper buffer).
- **Architecture Solution**:
  - Implemented `renderWaterHistogram()` and `renderSmokeHistogram()` using `deleteWidget()` from `@zos/ui` to destroy the previous histogram instances followed by immediate `createWidget(widget.HISTOGRAM, ...)` instantiation with updated week bucket data.
  - Layer ordering is preserved: primary bar histogram created first (with background track `0x333333`), followed by secondary stacked histogram (transparent background `0x00000000`).
  - **Flicker-Free Cache Invalidation**: Used `renderedWaterKey` and `renderedSmokeKey` (`${offset}_${maxVal}_${weekArray}_${subArray}`). Histograms are only re-created when the week data or offset actually changes. This prevents unnecessary widget destruction/creation during the background 2-second stale texture workaround timer.

### 2. Target & Average Summary Row Under Charts (Pages 2 & 4)
- Replaced the static color description text with watchOS-style metric summaries:
  - **Page 2 (💧 7 Days)**: `💧 Avg: ${waterAvg} ml/d  •  Goal: ${waterGoal} ml`
  - **Page 4 (🔥 7 Days)**: `🔥 Avg: ${smokeAvg}/d  •  Base: ${smokeBaseline}`
- **Centered Layout & Vertical Clearance**:
  - Rendered using full-screen width `widget.TEXT` (`x: 0, w: cfg.screenW`) with `align_h: align.CENTER_H` and `align_v: align.CENTER_V`.
  - Scaled typography: `text_size: 15` (`h: 36`) at `y: 384` on Active 2, and `text_size: 16` (`h: 38`) at `y: 396` on Balance.
  - Leaves ample vertical clearance below the histogram bars and generous bottom margin without clipping.

### 3. Dynamic Centering & Proportional Typography for Habit Breakdowns (Pages 1 & 3)
- **Elimination of Multi-Widget Layout Asymmetry**:
  - In Zepp OS `@zos/ui`, there is no automatic flexbox/flow layout or string measurement. Splitting an inline line (`💧 0 ml • ☕ 0 ml`) across 5 separate fixed-coordinate widgets created visible horizontal off-centering and uneven gaps whenever numbers changed in length (e.g. `0 ml` vs `1500 ml`).
  - Replaced with a unified, centered `widget.TEXT` across the full display width (`x: 0, w: cfg.screenW`, `align.CENTER_H`, `align.CENTER_V`), guaranteeing flawless symmetry regardless of character count:
    - **Page 1 (💧 Bubbles)**: `💧 ${waterVal} ml  •  ☕ ${coffeeVal} ml`
    - **Page 3 (🔥 Smokes)**: `🔥 ${cigVal} cig  •  ⚡ ${heatVal} heat`
- **Typography & Proportions**:
  - Scaled up text to `text_size: 15` (Amazfit Active 2) and `text_size: 16` (Amazfit Balance).
  - Increased widget height to `h: 36` (Active 2) and `h: 38` (Balance) positioned at `y: 384` / `y: 396`, providing ample line-height so emoji glyphs and text render crisply with generous clearance below the progress rings.

### 4. About Screen Logo Parity
- Updated `SQUARE_CONFIG` (Amazfit Active 2) from `icon.png` to `logo.png` (110x110) with centered `iconX: 140` (`(390 - 110) / 2 = 140`), creating complete visual unity with Amazfit Balance (`iconX: 185`) and Apple watchOS.

---

## 8. Dedicated Habit Logs Screen & Deletion (watchOS Parity)

### 1. Architectural Design & Zero-Regression Navigation
- **The Challenge**: Zepp OS relies on a 5-page vertical swiper (`SCROLL_MODE_SWIPER`) for main screen navigation (Bubbles $\rightarrow$ 7 Days $\rightarrow$ Smokes $\rightarrow$ 7 Days $\rightarrow$ About). Embedded vertical scroll lists inside a swiper conflict with page snapping gestures.
- **The Solution**: Implemented a dedicated sub-page (`page/logs.js`) accessed via `@zos/router.push`. This preserves the existing 5-page swiper layout with **zero regressions**.
- **Touch Target & Visual Indicator**:
  - The habit breakdown row displays a subtle navigation chevron: `💧 ${waterVal} ml  •  ☕ ${coffeeVal} ml  ›` and `🔥 ${cigVal} cig  •  ⚡ ${heatVal} heat  ›`.
  - Registered direct event listeners (`addEventListener(event.CLICK_UP, ...)`) on both the center ring text (`waterCenterText`, `smokeCenterText`) and the breakdown rows (`waterBreakdownText`, `smokeBreakdownText`).
  - **Zero Overlay / Full Visibility**: Avoids overlaying dummy button widgets (which in Zepp OS render solid opaque black rectangles). All progress arcs and texts remain 100% visible and natively interactive.

### 2. Full-Screen Free Scrolling (`SCROLL_MODE_FREE`)
- `page/logs.js` sets `setScrollMode({ mode: SCROLL_MODE_FREE })`, allowing unlimited log entries to be browsed smoothly with touch or digital crown.
- Responsive layout for both Amazfit Active 2 (Square 390x450) and Amazfit Balance (Round 480x480):
  - **Header**: Back button (`◀`), habit title (`💧 Water Logs` or `🔥 Smoke Logs`), and date/count subtitle (`X entries • Today`).
  - **Cards**: Dark gray cards (`0x1c1c1e`, `radius: 14`) displaying habit icon (`💧`, `☕`, `🔥`, `⚡`), amount & type (`300 ml Large`, `100 ml Coffee`, `1 Cig`, `1 Heat`), and formatted timestamp (`HH:mm`).
  - **Empty State**: Friendly `No logs recorded for this day.` message when no logs exist.

### 3. Log Deletion & Multi-Device Soft-Delete
- Each card includes a dedicated delete button (`🗑️` in red `0xff3b30`).
- Tapping triggers a confirmation modal (`Delete Log?` with details) to prevent accidental deletions.
- Confirmation sends a `DELETE_HABIT_LOG` request via `app-side/index.js` which executes a `PATCH` request setting `{ is_deleted: true }` on Supabase, adhering strictly to the Daily ecosystem's multi-device soft-delete architecture.
- Tactile feedback: `VIBRATOR_SCENE_SHORT_STRONG` on navigation/cancellation, and `VIBRATOR_SCENE_DURATION` on deletion confirmation.
- **Instant Dashboard Synchronization**: `page/index.js` registers `onResume()`. When returning to the dashboard via back gesture or button, the day's totals, progress arcs, and breakdown strings immediately re-fetch and refresh.

---

## 9. Deployment & Delivery Guide

For complete instructions on installing the app on physical Amazfit devices (Balance, Active 2), fresh machine setup, Developer Mode activation, and `npx zeus preview` procedures, refer to:
- [ZeppOS-Amazfit-Deployment-Guide.md](file:///Users/mihai/Source/Daily/Docs/Features/ZeppOS-Amazfit-Deployment-Guide.md)


