# WearOS & HarmonyOS Ecosystem Parity: DayOne Orbit

## Overview
This feature implements **1:1 complete parity** for both the **WearOS** (`com.intellidream.daily.wearos`) and **HarmonyOS** (`com.intellidream.daily`) companion apps, bringing them to the exact gold-standard established on **watchOS** and **ZeppOS**.

---

## 1. Parity Matrix: Across All 4 Companion Platforms

| Feature / Dimension | Apple watchOS | Amazfit ZeppOS | Google WearOS | Huawei HarmonyOS |
| :--- | :--- | :--- | :--- | :--- |
| **App Name** | `DayOne Orbit` | `DayOne Orbit` | `DayOne Orbit` | `DayOne Orbit` |
| **App Icon** | 3D Orbit Glowing Logo | 3D Orbit Glowing Logo | 3D Orbit Glowing Logo | 3D Orbit Glowing Logo |
| **Main Layout** | 5-Tab Pager | 5-Page Swiper | 5-Page `HorizontalPager` | 5-Page `Swiper` |
| **Page 0: Bubbles** | Ring + 3 Btns + Breakdown | Ring + 3 Btns + Breakdown | Ring + 3 Btns + Breakdown | Ring + 3 Btns + Breakdown |
| **Page 1: 💧 7 Days**| Mon–Sun Stacked Chart | Mon–Sun Stacked Chart | Mon–Sun Stacked Chart | Mon–Sun Stacked Chart |
| **Page 2: Smokes** | Ring + 2 Btns + Breakdown | Ring + 2 Btns + Breakdown | Ring + 2 Btns + Breakdown | Ring + 2 Btns + Breakdown |
| **Page 3: 🔥 7 Days**| Mon–Sun Stacked Chart | Mon–Sun Stacked Chart | Mon–Sun Stacked Chart | Mon–Sun Stacked Chart |
| **Page 4: About** | Logo + Status + Health + Unpair | Logo + Health + Unpair | Logo + Status + Health + Unpair | Logo + Status + Health + Unpair |
| **Day Navigation** | `◀ Today ▶` (boundary guard)| `◀ Today ▶` (boundary guard)| `◀ Today ▶` (boundary guard)| `◀ Today ▶` (boundary guard)|
| **Week Navigation**| `◀ This Week ▶` (Mon–Sun) | `◀ This Week ▶` (Mon–Sun) | `◀ This Week ▶` (Mon–Sun) | `◀ This Week ▶` (Mon–Sun) |
| **Action Buttons** | `💧 300`, `💧 150`, `☕ 100`<br>`🔥 Cig`, `⚡ Heat` | `💧 300`, `💧 150`, `☕ 100`<br>`🔥 Cig`, `⚡ Heat` | `💧 300`, `💧 150`, `☕ 100`<br>`🔥 Cig`, `⚡ Heat` | `💧 300`, `💧 150`, `☕ 100`<br>`🔥 Cig`, `⚡ Heat` |
| **Breakdown Line** | `💧 ... • ☕ ... ›`<br>`🔥 ... • ⚡ ... ›` | `💧 ... • ☕ ... ›`<br>`🔥 ... • ⚡ ... ›` | `💧 ... • ☕ ... ›`<br>`🔥 ... • ⚡ ... ›` | `💧 ... • ☕ ... ›`<br>`🔥 ... • ⚡ ... ›` |
| **Logs Management**| Dedicated logs view + delete | Dedicated sub-page + delete | Sub-screen overlay + delete | Sub-screen overlay + delete |
| **Soft Delete** | `PATCH { is_deleted: true }` | `PATCH { is_deleted: true }` | `PATCH { is_deleted: true }` | `PATCH { is_deleted: true }` |
| **Pairing PIN** | 6-Digit OTP, green monospace | 6-Digit OTP, green monospace | 6-Digit OTP, green monospace | 6-Digit OTP, green monospace |
| **OS Widgets** | WidgetKit Complications | N/A | Tiles & Complications (`🔥`) | Service Cards (`🔥`) |

---

## 2. 5-Page Horizontal Navigation Architecture

All companion apps now share an identical 5-page horizontal swiper/pager experience:
1. **Page 0 (`💧 Bubbles`)**:
   - Title: `💧 Bubbles`
   - Temporal header: `◀ Today ▶` / `◀ Yesterday ▶` / `◀ EEE, d MMM ▶` (with forward button hidden on today).
   - Dual-arc progress ring: Cyan Water arc + Orange Coffee arc. Center displays `Total / Goal`.
   - Action buttons: `💧 300`, `💧 150`, `☕ 100`.
   - Breakdown text: `💧 X ml  •  ☕ Y ml  ›`.
   - Tapping the center ring or breakdown opens the dedicated **Habit Logs Screen**.
2. **Page 1 (`💧 7 Days`)**:
   - Title: `💧 7 Days`
   - Temporal header: `◀ This Week ▶` / `◀ Last Week ▶` / `◀ d MMM - d MMM ▶` (with forward button hidden on this week).
   - 7-Column Monday–Sunday stacked histogram: Water (Cyan) + Coffee (Orange).
   - Dashed horizontal Goal line at daily target.
   - Metric summary row: `💧 Avg: X ml/d  •  Goal: Y ml`.
3. **Page 2 (`🔥 Smokes`)**:
   - Title: `🔥 Smokes`
   - Temporal header: `◀ Today ▶` / `◀ Yesterday ▶` / `◀ EEE, d MMM ▶` (with forward button hidden on today).
   - Progress ring: Green (`< 75%`), Orange (`75-99%`), Red (`≥ 100%`). Center displays `Total / Baseline`.
   - Action buttons: `🔥 Cig`, `⚡ Heat`.
   - Breakdown text: `🔥 X cig  •  ⚡ Y heat  ›`.
   - Tapping the center ring or breakdown opens the dedicated **Habit Logs Screen**.
4. **Page 3 (`🔥 7 Days`)**:
   - Title: `🔥 7 Days`
   - Temporal header: `◀ This Week ▶` / `◀ Last Week ▶` / `◀ d MMM - d MMM ▶` (with forward button hidden on this week).
   - 7-Column Monday–Sunday stacked histogram: Cigarette (Red) + Heated Tobacco (Blue).
   - Dashed horizontal Baseline line.
   - Metric summary row: `🔥 Avg: X/d  •  Base: Y`.
5. **Page 4 (`⚙️ About`)**:
   - Official 3D Orbit logo.
   - App branding: `DayOne Orbit`, `v1.0`.
   - Connection status: `Connected` (green).
   - Health telemetry status: `synced` / `not synced`.
   - `Unpair Watch` destructive button with confirmation dialog.

---

## 3. Dedicated Habit Logs Screen & Soft-Delete

To eliminate cluttered layouts and gesture conflicts inside swiper/pager containers:
- **Navigation Overlay**: Tapping on the breakdown row or the center progress ring opens a clean, full-screen scrollable logs view (`HabitLogsScreen` on WearOS, `LogsView` on HarmonyOS).
- **Entries**: Cards display habit emoji (`💧`, `☕`, `🔥`, `⚡`), exact amount & type (`300 ml Large`, `100 ml Coffee`, `1 Cig`, `1 Heat`), and localized time `HH:mm`.
- **Accidental Deletion Prevention**: Tapping the red delete button triggers an OS-native confirmation dialog (`Delete Log?`).
- **Multi-Device Soft-Delete**: Deletion sends a `PATCH` request setting `{ is_deleted: true }` in the Supabase `habits_logs` table, keeping all connected devices in sync without data loss.

---

## 4. Historical Habit Logging

When the user navigates to a past date (`dayOffset < 0`) and taps an action button (`💧 300`, `☕ 100`, `🔥 Cig`, `⚡ Heat`):
1. The app computes the exact timestamp on that past day (`logged_at`).
2. The log is inserted into Supabase with that historical timestamp.
3. The day's totals, progress arcs, and the corresponding 7-day histogram bar update optimistically.

---

## 5. OS Integration, Complications & Tiles

- **WearOS**:
  - `strings.xml`: Application name set to `DayOne Orbit`.
  - Service metadata: `DailyTileService` (`DayOne Orbit Stats`), `WaterComplicationService` (`DayOne Orbit Water`), `SmokesComplicationService` (`DayOne Orbit Smokes`).
  - Emoji unification: Complications and Tiles updated from `🚬` to `🔥`.
  - Icons: High-resolution 3D Orbit logo generated across all mipmap densities (`mdpi` through `xxxhdpi`) and `res/drawable/orbit_logo.png`.
- **HarmonyOS**:
  - `AppScope/resources/base/element/string.json`: `app_name` set to `DayOne Orbit`.
  - `entry/src/main/resources/base/element/string.json`: `EntryAbility_label` set to `DayOne Orbit`.
  - Icons: `startIcon.png` and `foreground.png` updated with official 3D Orbit logo.
  - Card & complication labels unified with DayOne Orbit branding.

---

## 6. Pairing Handshake Architecture (`watch_pairing_codes`)

Both WearOS and HarmonyOS utilize the exact same handshake channel established by watchOS and ZeppOS:
1. **Watch Generates 6-Digit PIN**: Inserts `{ pin_code: "<6-digit-pin>" }` into `public.watch_pairing_codes` with `'Prefer': 'return=representation'`.
2. **Watch Displays Instruction**: `"Enter this PIN in DayOne to link."` with large monospace green digits.
3. **User Claims PIN in DayOne (Desktop / Mobile)**: The user enters the PIN into the DayOne app (`FeaturesPage` / `Settings`). The app claims the code by updating `claimed = true`, generating a long-lived JWT token, and writing `access_token`.
4. **Watch Polls & Retrieves Session**: Watch polls `watch_pairing_codes?pin_code=eq.<pin>&select=*` every 2.5s. When `claimed == true` and `access_token` is present, it imports the token, deletes the pairing code row, registers the watch in `paired_watches`, and enters the 5-page dashboard.

