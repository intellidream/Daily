# Android Adaptive Dual-Pane Foldable Architecture

## Overview
This document details the first-class native foldable and dual-pane tablet architecture in **DayOne Android** (`com.intellidream.daily`), specifically engineered and verified for the **Samsung Galaxy Z Fold 8 ("RADAR")** and the **Google Pixel 9 Pro Fold**.

The architecture ensures that when the device is unfolded or used on an expanded display (`screenWidthDp >= 600`), the application transforms into an adaptive dual-pane workspace while retaining 100% normal single-screen smartphone ergonomics on folded cover screens or standard mobile devices.

---

## Architecture Decisions & Polish

### 1. Dual-Pane Strategy: Master + Adaptive Secondary Workspace
- **Master Pane (Left, `weight(1f)`)**:
  - Houses the full **DashboardView** in `forceSingleColumn` mode.
  - Keeps critical diurnal widgets (Weather radar, Daily Glance, News feed, Health biometrics, Habits, Smart Ledger, Notes) visible at all times.
  - Balanced padding: `padding(start = 16.dp, end = 12.dp, top = 4.dp)` ensuring exact symmetrical spacing with the detail pane.
- **Detail / Secondary Pane (Right, `weight(1f)`)**:
  - Balanced padding: `padding(start = 12.dp, end = 16.dp, top = 4.dp)`.
  - When no secondary hub or sheet is explicitly open, it hosts the **`DailyFoldableCompanionPane`**:
    - **Adaptive Diurnal Wish Header**: Replaces static titles with the diurnal wish adapted to the time of day, identical to the bottom action button of Smart Briefing (e.g., *"Have a productive day!"*, *"Enjoy a restful evening!"*, *"Sleep tight & rest well!"*), accompanied by a diurnal badge (e.g., "EVENING REVIEW", "MORNING PULSE") and formatted date.
    - **Concentric Recovery Rings**: Activity steps ring (Orange), Sleep score ring (Purple), and Hydration progress ring (Cyan).
    - **Procedural Monkey Mascot**: Live autonomic stress representation (`MonkeyMood.fromLevel(stressLevel)`) with animated breathing glow.
    - **Interactive Smart Briefing Launcher**: Diurnal intelligence summary teaser with audio playback shortcut.
    - **Executive Multi-Hub Digest**: Replaced redundant buttons with rich live intelligence summary cards displaying real-time telemetry:
      - *Health & Vitals*: Heart rate (BPM), recovery score, daily steps, and active calories.
      - *Habits & Routines*: Water intake progress bar (`0 / 2000 ml`), completion percentage, and smoke-free clean streak badge.
      - *Smart Ledger*: Net worth summary, monthly savings rate, active expense counts, and transaction previews.
      - *Tagdos & Notes*: Active pending tasks count and latest mental stream preview.
      - *News & Briefings*: Top curated headline preview with publication badge and relative timestamp.
  - When a Hub or Sheet is opened, it seamlessly transitions into that functional view inside the right pane:
    - **Health Studio**: Biometrics, hypnogram, stress curves, and trend charts.
    - **Habits Tracker**: Hydration logging, smoke cessation counters, and daily routines.
    - **Smart Ledger**: Transaction DSL editor, net worth breakdown, and watchlist quotes.
    - **Tagdos & Notes**: Quick memos, mental stream, and task checklists.
    - **Curated News & Reader**: RSS feed browsing and distraction-free reader mode (`widthIn(max = 700.dp)` for optimal reading measure).
    - **Smart Briefing Console**: Full typewriter diurnal narration and TTS voice controls embedded directly without a modal sheet.
    - **Customize Dashboard**: Live reorderable widget list with instant master-pane visual reflection.
    - **Settings & Profile**: Cloud account sync, appearance themes, and biometric preferences.

### 2. Symmetrical Margins & Liquid Glass Controls
- **Width Symmetry**:
  - Master pane and secondary pane both use `weight(1f)`.
  - Left pane padding: `start = 16.dp, end = 12.dp`.
  - Right pane padding: `start = 12.dp, end = 16.dp`.
  - Both panes share identical 969px card content widths on typical foldable viewports, eliminating previous width discrepancies.
- **40dp Circular Liquid Glass Controls**:
  - All close buttons and secondary action buttons across the right pane (`FoldableDetailHeader`) use 40dp circular shapes (`CircleShape`) with subtle translucent glass backgrounds (`Color(0xFF080F1E).copy(alpha = 0.72f)`) and white gradient borders, matching the master pane header buttons 1:1.
- **Swipe-Down Dismiss Ergonomics**:
  - The top header bar and pill handle in `FoldableDetailHeader` attach `detectVerticalDragGestures` with physics-based offset animations and haptic feedback. Dragging down smoothly collapses the active hub back to the Companion workspace, restoring bottom-sheet-like ergonomics without modal disruption.
- **Smart Briefing Foldable Polish**:
  - `SmartBriefingContent(showHeader = false)` suppresses the internal redundant navigation bar in foldable mode.
  - The single unified `FoldableDetailHeader` incorporates the TTS Speaker toggle in its `trailingContent`, eliminating duplicate headers and duplicate close buttons.

### 3. Capsule Navigation Placement: Option A (Master-Pane Bottom Anchor)
- Rather than stretching or centering the floating navigation capsule across the crease (which strains thumb ergonomics and can be obstructed by physical hinges), the capsule is anchored at:
  ```kotlin
  FloatingGlassCapsule(
      selectedTab = selectedTab,
      onTabSelected = { tab -> ... },
      modifier = Modifier
          .align(Alignment.BottomCenter)
          .navigationBarsPadding()
          .padding(bottom = 16.dp)
  )
  ```
- This allows fluid one-handed thumb navigation without reaching across the display hinge.

### 4. Crease Separation & Gesture Interception
- A 1dp subtle glass divider (`Color.White.copy(alpha = 0.08f)`) demarcates the left and right viewports.
- **Predictive Back Navigation**:
  - Pressing the system Back button or gesture while in a detail hub immediately collapses the right pane back to the Companion (`NavigationTab.Dashboard`), keeping the user contextually anchored on the master dashboard without exiting the app.

---

## Key Files & Components

| File | Purpose |
|---|---|
| [`FoldableLayoutState.kt`](file:///Users/mihai/Source/Daily/Android/app/src/main/java/com/intellidream/daily/presentation/foldable/FoldableLayoutState.kt) | Sealed target states (`Companion`, `Hub`, `Settings`, `Customize`, `Briefing`, `NewsArticleDetail`). |
| [`FoldableDetailHeader.kt`](file:///Users/mihai/Source/Daily/Android/app/src/main/java/com/intellidream/daily/presentation/foldable/FoldableDetailHeader.kt) | Liquid Glass top bar with drag handle pill, swipe-down dismiss gestures, category glyph, title, subtitle, and 40dp circular close button. |
| [`DailyFoldableCompanionPane.kt`](file:///Users/mihai/Source/Daily/Android/app/src/main/java/com/intellidream/daily/presentation/foldable/DailyFoldableCompanionPane.kt) | Persistent Companion with diurnal wish header, concentric rings, live BPM/mascot, briefing teaser, and rich Executive Multi-Hub Digest cards. |
| [`SmartBriefingFoldablePane.kt`](file:///Users/mihai/Source/Daily/Android/app/src/main/java/com/intellidream/daily/presentation/foldable/SmartBriefingFoldablePane.kt) | Embedded right-pane presentation for Smart Briefing with unified header, TTS toggle, and drag-down dismiss. |
| [`SmartBriefingBottomSheet.kt`](file:///Users/mihai/Source/Daily/Android/app/src/main/java/com/intellidream/daily/presentation/briefing/SmartBriefingBottomSheet.kt) | Added `showHeader: Boolean = true` parameter to `SmartBriefingContent` to suppress duplicate navigation rows on foldables. |
| [`DashboardView.kt`](file:///Users/mihai/Source/Daily/Android/app/src/main/java/com/intellidream/daily/presentation/dashboard/DashboardView.kt) | Added `forceSingleColumn` flag to render as a single column in the left master pane on foldables. |
| [`NewsReaderSheet.kt`](file:///Users/mihai/Source/Daily/Android/app/src/main/java/com/intellidream/daily/presentation/news/NewsReaderSheet.kt) | Adaptive width constraint (`widthIn(max = 700.dp)`) preventing excessively wide text lines on large screens. |
| [`MainActivity.kt`](file:///Users/mihai/Source/Daily/Android/app/src/main/java/com/intellidream/daily/MainActivity.kt) | Adaptive layout switch (`screenWidthDp >= 600`) orchestrating dual-pane vs single-pane execution with symmetrical `weight(1f)` margins. |
| [`ThemeColors.kt`](file:///Users/mihai/Source/Daily/Android/core-designsystem/src/main/java/com/intellidream/daily/designsystem/ThemeColors.kt) | Added `accentYellow` (`0xFFFFD600`) for cross-platform color parity across Weather and Tagdos hubs. |

---

## Verification & Device Matrix

1. **Pixel 9 Pro Fold Emulator (`emulator-5556`)**:
   - Resolution: `2076x2152` px at 390 dpi (~851 dp width).
   - Verified: Dual-pane master-detail renders with 1:1 symmetrical card widths (969px each); diurnal wish header displays accurately; executive summary cards display live data; circular 40dp close buttons match master pane; swipe-down gesture dismisses detail pane; Smart Briefing contains single header and single close button.
2. **Standard Phone Emulator (`emulator-5554`) & Compact Layout**:
   - Verified: Single-pane mobile layout with centered bottom capsule retains 100% normal behavior with zero regression.
3. **Physical Samsung Galaxy Z Fold 8 ("RADAR", `SM-F971B`)**:
   - Deployed over wireless adb (`192.168.3.64:32995`).
   - Verified: Live execution, responsive layout, fluid 120Hz scrolling, and seamless transitions on physical hardware.
4. **Physical Google Pixel 9 Pro**:
   - Deployed over wireless adb (`192.168.3.8:39221`).
   - Verified: Compact mobile layout functions identically on physical hardware.
