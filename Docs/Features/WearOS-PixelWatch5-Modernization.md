# WearOS Pixel Watch 5 Modernization & Architecture

## Overview
This document details the comprehensive modernization of the **Daily WearOS** application (`DayOne Orbit`), bringing it to the visual, fluid, and ergonomic standards of the **Google Pixel Watch 5** and modern Wear OS (Wear Material 3 & Horologist).

---

## 1. Key Architectural & Ergonomic Upgrades

### A. Horologist 0.6.22 Layout & Physical Crown (Rotary) Snapping
- **Root Scaffolding**: `DailyWearApp` is wrapped in `AppScaffold`, establishing curved time text coordinates and responsive bezel padding.
- **Screen Scaffolding**: Each screen (`BubblesScreen`, `SmokesScreen`, `Bubbles7DaysScreen`, `Smokes7DaysScreen`, `AboutScreen`) is hosted in a `ScreenScaffold(scrollState = columnState)` utilizing `rememberResponsiveColumnState(rotaryMode = ScalingLazyColumnState.RotaryMode.Snap)`.
- **Rotary Crown Integration**: Turning the physical crown snaps smoothly to individual items (`RotaryMode.Snap`) accompanied by crisp haptic detent feedback, matching the native Pixel Watch system launcher fluidity.
- **Curved Bezel Position Indicator**: Dynamic scrollbar precisely hugging the outer edge of circular displays.

### B. Vertical Single-Flow Layout & Centered Hero Rings (132dp)
- **Legacy Problem**: The legacy layout crammed an 86dp ring next to 3 tiny 26dp action pill buttons side-by-side, resulting in clipped borders and accidental mis-taps.
- **Modern Solution**:
  1. **Top**: Curved `TimeText` + Category Title (`💧 Bubbles` / `🔥 Smokes`).
  2. **Navigation**: Modern 34dp pill `TemporalNavHeader` with subtle border and arrow controls (`‹ Today ›`).
  3. **Hero Ring (132dp)**: Centered, high-contrast circular canvas with animated arcs (`animateFloatAsState`), 32sp bold numeric totals, and secondary goal subtitles.
  4. **Touch Target Chips (48dp)**: Full-width Wear Material 3 `QuickAddChip` components conforming to Google's 48dp minimum touch target guideline:
     - `💧 +150 ml Water` (Small)
     - `💧 +300 ml Water` (Large)
     - `☕ +100 ml Coffee`
     - `🔥 +1 Cigarette`
     - `⚡ +1 Heated`
  5. **Breakdown Card**: Rounded card summarizing individual sub-components with tap-to-logs navigation (`💧 X ml • ☕ Y ml ›`).
  6. **In-Flow Logs**: Chronological timeline of logged items with timestamps, icons, and tap-to-delete confirmation dialogs.

### C. 7-Day Analytics Overhaul
- **Chart Card**: Elevated surface card (`Color(0xFF141820)`) featuring:
  - Dashed cyan/red baseline target line (`PathEffect.dashPathEffect`).
  - Stacked rounded bars for composite metrics (e.g. Coffee on top of Water, Heated Tobacco on top of Cigarettes).
  - Highlighted today letter (e.g. bold cyan "T" for Tuesday).
  - Subtle track placeholders for upcoming days.
- **Daily Average & Target Card**: Clean bottom card presenting calculated 7-day daily average alongside current target.

### D. Zero-Latency Memory Caching & Offline Reliability
- **Multi-Day & Multi-Week Cache**: `WatchSessionManager` maintains `ConcurrentHashMap` caches keyed by ISO date string (`bubblesDayCache`, `smokesDayCache`) and week offsets (`bubblesWeekCache`, `smokesWeekCache`).
- **0ms Date Navigation**: Switching between Today, Yesterday, or past weeks updates the UI instantaneously without loading spinners or blank states, while asynchronous Supabase coroutines refresh data in the background.

### E. Tactile Waveforms & Soft Auditory Feedback
- **SoundAndHapticFeedback**:
  - Double-pulse waveform vibration (`VibrationEffect.createWaveform`) for log completions and sync events.
  - Gentle 45ms soft chime (`ToneGenerator.TONE_PROP_BEEP2`) respecting silent and Do-Not-Disturb modes.
  - Subtle click haptics (`HapticFeedbackConstants.KEYBOARD_TAP`) for crown navigation and buttons.

### F. Telemetry & Health Sync Title Formatting
- Standardized health telemetry across all platforms:
  - `"Health: Synced at [DateTime]"`
  - `"Health: No New Data"`
  - `"Health: Not Synced"`
- Capitalized words without a trailing period.

---

## 2. Multi-ABI Packaging & Pixel Watch 5 Compatibility
- **Hardware Architecture**: The Google Pixel Watch 5 utilizes an `armeabi-v7a` 32-bit CPU core architecture.
- **Universal Multi-ABI Support**: Configured Gradle `ndk.abiFilters` to package `armeabi-v7a`, `arm64-v8a`, `x86`, and `x86_64` into the universal debug APK, preventing `INSTALL_FAILED_NO_MATCHING_ABIS` deployment errors.

---

## 3. Physical Device Verification
- **Target Device**: Google Pixel Watch 5 (`serial: 67301WRDTW62DP`).
- **Connection**: Wireless ADB via TLS pairing on local subnet (`192.168.3.65`).
- **Verification Results**:
  - App installed via streamed install (`Success`).
  - Native launch of `com.intellidream.daily.wearos/.presentation.MainActivity`.
  - Visual verification confirmed 122dp unclipped hero ring, curved `TimeText`, rounded 48dp quick chips, 7-day stacked bar chart, and fluid rotary crown response.

---

## 4. Fine-Tuning, Ergonomics & Launcher Polish

### A. Progress Ring Clipping Elimination
- **Root Cause**: `drawArc` on Canvas without insets centered the stroke on outer bounds `[0, size]`, causing the outer 5dp of the stroke to clip against the item boundary.
- **Solution**: Set Hero ring container to 122dp and mathematically inset the arc by `strokeWidth / 2f` (`topLeft = Offset(halfStroke, halfStroke)`, `size = Size(width - strokeWidth, height - strokeWidth)`). The circle is 100% contained, perfectly round, and free from any flat clipping.

### B. Consistent Vector Iconography
- Replaced emoji characters on `QuickAddChip` with native material vector icons matching the headers:
  - Cigarette button: `Icons.Filled.LocalFireDepartment` (matches the header icon).
  - Heated tobacco button: `Icons.Filled.Bolt`.
  - Water button: `Icons.Filled.WaterDrop`.
  - Coffee button: `Icons.Filled.LocalCafe`.

### C. Smokes Data Loading & Canonical Contract Fix
- Resolved missing history data on previous days and weeks by querying both `"smokes"` and `"smoke"` (`or { eq("habit_type", "smokes"); eq("habit_type", "smoke") }`), aligning with `DailyCore` and Android.
- New logs are committed with the canonical `"smokes"` key.

### D. Adaptive Launcher Icon (No White Box)
- Created `mipmap-anydpi-v26/ic_launcher.xml` and `ic_launcher_round.xml` with background color `#030609` and foreground artwork.
- Added `android:roundIcon="@mipmap/ic_launcher_round"` in `AndroidManifest.xml`, ensuring edge-to-edge circular presentation in the Pixel Watch launcher.

### E. 14-Day Batched Pre-Fetch & Rotary Scroll Fluidity
- Implemented a 14-day history window pre-fetch on screen active state, grouping records by local date string into the memory cache. Date navigation (`‹ Today ‹ Yesterday ‹ 2 days ago`) is 0ms instantaneous.
- Switched rotary mode to `ScalingLazyColumnState.RotaryMode.Scroll` for 120Hz high-framerate fluid scrolling with tactile ticks.
- Set `beyondViewportPageCount = 0` in `HorizontalPager` to avoid mounting multiple heavy screens simultaneously during page transitions.
