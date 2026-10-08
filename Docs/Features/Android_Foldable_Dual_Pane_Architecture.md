# Android Adaptive Dual-Pane Foldable Architecture

## Overview
This document details the first-class native foldable and dual-pane tablet architecture introduced to **DayOne Android** (`com.intellidream.daily`), specifically engineered and verified for the **Samsung Galaxy Z Fold 8 ("RADAR")** and the **Google Pixel 9 Pro Fold**.

The architecture ensures that when the device is unfolded or used on an expanded display (`screenWidthDp >= 600`), the application transforms into an adaptive dual-pane workspace while retaining 100% normal single-screen smartphone ergonomics on folded cover screens or standard mobile devices.

---

## Architecture Decisions

### 1. Dual-Pane Strategy: Option B (Persistent Master + Companion Pulse)
- **Master Pane (Left, `weight(1.08f)`)**:
  - Houses the full **DashboardView** in `forceSingleColumn` mode.
  - Keeps critical diurnal widgets (Weather radar, Daily Glance, News feed, Health biometrics, Habits, Smart Ledger, Notes) visible at all times.
- **Detail / Secondary Pane (Right, `weight(1f)`)**:
  - When no secondary hub or sheet is explicitly open, it hosts the **`DailyFoldableCompanionPane`**:
    - **Companion Pulse Header**: Real-time heart rate badge and current diurnal date.
    - **Concentric Recovery Rings**: Activity steps ring (Orange), Sleep score ring (Purple), and Hydration progress ring (Cyan).
    - **Procedural Monkey Mascot**: Live autonomic stress representation (`MonkeyMood.fromLevel(stressLevel)`) with animated breathing glow.
    - **Interactive Smart Briefing Launcher**: Diurnal intelligence summary teaser with audio playback shortcut.
    - **Quick Hub Cards**: Direct shortcuts to Health Studio, Smart Ledger, Habits & Routines, and Curated News.
  - When a Hub or Sheet is opened, it seamlessly transitions into that functional view inside the right pane:
    - **Health Studio**: Biometrics, hypnogram, stress curves, and trend charts.
    - **Habits Tracker**: Hydration logging, smoke cessation counters, and daily routines.
    - **Smart Ledger**: Transaction DSL editor, net worth breakdown, and watchlist quotes.
    - **Tagdos & Notes**: Quick memos, mental stream, and task checklists.
    - **Curated News & Reader**: RSS feed browsing and distraction-free reader mode (`widthIn(max = 700.dp)` for optimal reading measure).
    - **Smart Briefing Console**: Full typewriter diurnal narration and TTS voice controls embedded directly without a modal sheet.
    - **Customize Dashboard**: Live reorderable widget list with instant master-pane visual reflection.
    - **Settings & Profile**: Cloud account sync, appearance themes, and biometric preferences.

### 2. Capsule Navigation Placement: Option A (Master-Pane Bottom Anchor)
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

### 3. Crease Separation & Gesture Interception
- A 1dp subtle glass divider (`Color.White.copy(alpha = 0.08f)`) demarcates the left and right viewports.
- **Predictive Back Navigation**:
  - Pressing the system Back button or gesture while in a detail hub immediately collapses the right pane back to the Companion Pulse (`NavigationTab.Dashboard`), keeping the user contextually anchored on the master dashboard without exiting the app.

---

## Key Files & Components

| File | Purpose |
|---|---|
| [`FoldableLayoutState.kt`](file:///Users/mihai/Source/Daily/Android/app/src/main/java/com/intellidream/daily/presentation/foldable/FoldableLayoutState.kt) | Sealed target states (`Companion`, `Hub`, `Settings`, `Customize`, `Briefing`, `NewsArticleDetail`). |
| [`FoldableDetailHeader.kt`](file:///Users/mihai/Source/Daily/Android/app/src/main/java/com/intellidream/daily/presentation/foldable/FoldableDetailHeader.kt) | Liquid Glass top bar with drag handle pill, category glyph, title, subtitle, and dismiss button. |
| [`DailyFoldableCompanionPane.kt`](file:///Users/mihai/Source/Daily/Android/app/src/main/java/com/intellidream/daily/presentation/foldable/DailyFoldableCompanionPane.kt) | Persistent Companion with concentric rings, live BPM/mascot, briefing teaser, and quick cards. |
| [`SmartBriefingFoldablePane.kt`](file:///Users/mihai/Source/Daily/Android/app/src/main/java/com/intellidream/daily/presentation/foldable/SmartBriefingFoldablePane.kt) | Embedded right-pane presentation for Smart Briefing without `ModalBottomSheet` scaffolding. |
| [`DashboardView.kt`](file:///Users/mihai/Source/Daily/Android/app/src/main/java/com/intellidream/daily/presentation/dashboard/DashboardView.kt) | Added `forceSingleColumn` flag to render as a single column in the left master pane on foldables. |
| [`NewsReaderSheet.kt`](file:///Users/mihai/Source/Daily/Android/app/src/main/java/com/intellidream/daily/presentation/news/NewsReaderSheet.kt) | Adaptive width constraint (`widthIn(max = 700.dp)`) preventing excessively wide text lines on large screens. |
| [`MainActivity.kt`](file:///Users/mihai/Source/Daily/Android/app/src/main/java/com/intellidream/daily/MainActivity.kt) | Adaptive layout switch (`screenWidthDp >= 600`) orchestrating dual-pane vs single-pane execution. |
| [`ThemeColors.kt`](file:///Users/mihai/Source/Daily/Android/core-designsystem/src/main/java/com/intellidream/daily/designsystem/ThemeColors.kt) | Added `accentYellow` (`0xFFFFD600`) for cross-platform color parity across Weather and Tagdos hubs. |

---

## Verification & Device Matrix

1. **Pixel 9 Pro Fold Emulator (`emulator-5556`)**:
   - Resolution: `2076x2152` px at 390 dpi (~851 dp width).
   - Verified: Dual-pane master-detail renders correctly with Option B companion pulse; hub transitions (Health, Briefing, etc.) open cleanly in right pane; Back gesture gracefully collapses to Companion.
2. **Standard Phone Emulator (`emulator-5554`)**:
   - Resolution: `1080x2400` px.
   - Verified: Single-pane mobile layout with centered bottom capsule retains 100% normal behavior with zero regression.
3. **Physical Samsung Galaxy Z Fold 8 ("RADAR", `SM-F971B`)**:
   - Deployed over wireless adb (`192.168.3.64:32995`).
   - Verified: Live execution, responsive layout across inner foldable display.
4. **Physical Google Pixel 9 Pro**:
   - Deployed over wireless adb (`192.168.3.8:39221`).
   - Verified: Compact mobile layout functions identically on physical hardware.
