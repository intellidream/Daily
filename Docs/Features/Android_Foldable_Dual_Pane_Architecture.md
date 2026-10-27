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
    - **Curated News & Reader**: RSS feed browsing and centered distraction-free reader mode (`widthIn(max = 700.dp)` for optimal reading measure).
    - **Centered Modal Intelligence**: Smart Briefing (`SmartBriefingBottomSheet`), News Reader (`NewsReaderSheet`), and Clinical Guidance (`HabitGuidanceSheet`) display as centered modal sheets (`sheetMaxWidth = 700.dp`) over both panes with dimming scrim, preserving the underlying dual-pane layout.
    - **Customize Dashboard**: Live reorderable widget list with instant master-pane visual reflection.
    - **Settings & Profile**: Cloud account sync, appearance themes, and biometric preferences.

### 2. Symmetrical Margins, Full Content Width & Liquid Glass Controls
- **Width Symmetry & Elimination of Double Margin Discrepancy**:
  - Master pane and secondary pane both use `weight(1f)`.
  - Left pane padding: `start = 16.dp, end = 12.dp`.
  - Right pane padding: `start = 12.dp, end = 16.dp`.
  - Previously, detail hubs internally applied `padding(horizontal = 20.dp)` in addition to the container's outer margins, causing hub cards in the right pane to measure narrower (873 px) than the master pane (969 px).
  - All hub views (`HealthMainView`, `HabitsMainView`, `FinancesMainView`, `TagdosNotesHubView`, `NewsFeedView`, `WeatherDetailView`, `SettingsScreen`, `CustomizeDashboardScreen`, `SmartBriefingBottomSheet`) now accept a parameterized `horizontalPadding: Dp = 20.dp` and `applyStatusBarsPadding: Boolean = true`.
  - When hosted inside the foldable secondary pane, `horizontalPadding = 0.dp` and `applyStatusBarsPadding = false` are passed, yielding exact 1:1 card widths of 969 px across both panes.
- **Vertical Alignment Parity (`y = 290 px`)**:
  - The left `HeaderGreetingView` occupies `56.dp` total height (48dp content + 8dp vertical padding), followed by `top = 8.dp` and `spacedBy = 14.dp` inside the dashboard LazyColumn.
  - The right `DailyFoldableCompanionPane` header row is calibrated to identical dimensions (`height(56.dp)`, `padding(top = 4.dp, bottom = 4.dp)`), with redundant date text omitted (as the master header already displays it).
  - The LazyColumn on the right applies `contentPadding = PaddingValues(top = 8.dp, bottom = 90.dp)` with `verticalArrangement = Arrangement.spacedBy(14.dp)`.
  - Both the left Weather card and the right Hero tile (concentric progress rings) begin at the exact identical vertical coordinate `y = 290 px` (`78 dp`).
- **Minimalist Hub Drag Handle (`FoldableDragHandle`)**:
  - Redundant artificial top headers (category icon, title, subtitle, circular X button) above secondary hubs were eliminated to let the hub's own content shine cleanly.
  - Hubs now display only a subtle, elegant horizontal drag handle (`FoldableDragHandle`): a 48x5dp rounded capsule with `detectVerticalDragGestures`, physics-based vertical offset animations, and haptic feedback.
  - Hubs can be dismissed smoothly via drag-down on the handle, back gesture swipe, or the hub's internal back button.
- **Centered Smart Briefing Architecture (Parity with News & Clinical Guidance)**:
  - Rather than being constrained to the secondary pane, Smart Briefing opens as a centered modal sheet overlay (`SmartBriefingBottomSheet` with `sheetMaxWidth = 700.dp`), exactly matching the centered presentation of `NewsReaderSheet` and `HabitGuidanceSheet`.
  - Features Material 3 spring gestures with drag down to dismiss (including the signature 48x5dp liquid glass pill drag handle), rounded top corners (`topStart = 28.dp, topEnd = 28.dp`), dark backdrop dimming scrim over both panes, and generous `20.dp` internal padding.
  - Leaves the secondary pane (Companion or active Hub) completely intact beneath the sheet.

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

### 5. Unified Hub Header Button Architecture (Health Hub Golden Standard)
To achieve complete visual harmony across all hubs opened in the right pane on foldables (as well as single-screen phones), all header navigation and action buttons adhere strictly to the **Health Hub golden standard**:
- **Button Geometry & Shape**:
  - Outer bounding box: Exactly `36.dp` diameter (`size(36.dp)`), shaped with `CircleShape`.
  - Icon dimensions: Centered `18.dp` icon (`size(18.dp)`), providing optimal touch target semantics (`minimumInteractiveComponentSize` via `Box`) without excess Material padding.
  - Navigation Icon: Standardized on `Icons.AutoMirrored.Rounded.KeyboardArrowLeft` with `Color.White` tint for consistent chevron visual weight.
- **Glassmorphic Material Styling**:
  - Rest/Normal background: `Color.White.copy(alpha = 0.08f)`.
  - Rest/Normal border: `1.dp` solid with `Color.White.copy(alpha = 0.12f)` and `CircleShape`.
  - Active/Highlighted states: Dynamic accent tinting (`accentColor.copy(alpha = 0.18f..0.20f)` fill, `accentColor.copy(alpha = 0.40f..0.60f)` border).
- **Header Row Alignment & Vertical Center Parity**:
  - Row vertical padding is unified across all hubs to `vertical = 12.dp`.
  - Inner navigation arrows (e.g. Day navigator in Habits and Health) standardized to `26.dp` circular buttons with `14.dp` icons inside a `10.dp horizontal / 5.dp vertical` glass capsule.
  - Sub-tab switchers (e.g. Finances Money/Stocks/World) standardized to `height(36.dp)` with `3.dp` padding, keeping all leading, center, and trailing controls on the exact same vertical center coordinate (`y = 266 px`).
- **Standardized Surfaces**:
  - **Health Studio** (`HealthMainView.kt`): Serves as the golden reference.
  - **Habits Tracker** (`HabitsMainView.kt`): Replaced Material `IconButton` with `36.dp` circular glass Box for back and guidance buttons; unified day navigation capsule to 26dp circular controls.
  - **Smart Ledger** (`FinancesMainView.kt`): Replaced `38.dp` back button with `36.dp` circular glass Box; aligned 36dp sub-tab switcher.
  - **Tagdos & Notes** (`TagdosNotesHubView.kt`): Replaced irregular text toggle pill and cyan back arrow with `36.dp` circular glass Box (`18.dp` GridView/TextFields icon), matching Health's trailing action pattern; centered title inside a glass capsule.
  - **Curated News** (`NewsFeedView.kt` & `NewsReaderSheet.kt`): Standardized back, manage feeds, category selector, and reader action buttons to `36.dp` circular glass buttons with `18.dp` icons and `1.dp` borders.
  - **Weather Detail** (`WeatherDetailView.kt`): Standardized `38.dp` back, reset location, and search location buttons to `36.dp` with `18.dp` icons.
  - **Customize Dashboard** (`CustomizeDashboardScreen.kt`): Replaced square 12dp-radius `GlassButton` with `36.dp` circular glass Box with `KeyboardArrowLeft`.
  - **Settings & Profile** (`SettingsScreen.kt`): Standardized back button to `36.dp` circular glass Box with `KeyboardArrowLeft`.
  - **Smart Briefing** (`SmartBriefingBottomSheet.kt`): Replaced `34.dp` close and audio buttons with `36.dp` circular glass buttons with `18.dp` icons.
  - **Clinical Guidance** (`HabitGuidanceSheet.kt`): Standardized close button from `32.dp` `IconButton` to `36.dp` circular glass Box with `Close` (`18.dp`).
  - **Foldable Detail Container** (`FoldableDetailHeader.kt`): Standardized close button to `36.dp` circular glass Box.

---

## Key Files & Components

| File | Purpose |
|---|---|
| [`FoldableLayoutState.kt`](file:///Users/mihai/Source/Daily/Android/app/src/main/java/com/intellidream/daily/presentation/foldable/FoldableLayoutState.kt) | Sealed target states (`Companion`, `Hub`, `Settings`, `Customize`, `Briefing`, `NewsArticleDetail`). |
| [`FoldableDetailHeader.kt`](file:///Users/mihai/Source/Daily/Android/app/src/main/java/com/intellidream/daily/presentation/foldable/FoldableDetailHeader.kt) | Contains `FoldableDragHandle`, a minimalist liquid glass drag pill (48x5dp) with vertical swipe gestures, offset animation, and haptic feedback. |
| [`DailyFoldableCompanionPane.kt`](file:///Users/mihai/Source/Daily/Android/app/src/main/java/com/intellidream/daily/presentation/foldable/DailyFoldableCompanionPane.kt) | Persistent Companion with diurnal wish header, concentric rings, live BPM/mascot, briefing teaser, and rich Executive Multi-Hub Digest cards. |
| [`SmartBriefingFoldablePane.kt`](file:///Users/mihai/Source/Daily/Android/app/src/main/java/com/intellidream/daily/presentation/foldable/SmartBriefingFoldablePane.kt) | Embedded right-pane presentation for Smart Briefing with unified header, TTS toggle, and drag-down dismiss. |
| [`SmartBriefingBottomSheet.kt`](file:///Users/mihai/Source/Daily/Android/app/src/main/java/com/intellidream/daily/presentation/briefing/SmartBriefingBottomSheet.kt) | Added `showHeader: Boolean = true` parameter to `SmartBriefingContent` to suppress duplicate navigation rows on foldables. |
| [`DashboardView.kt`](file:///Users/mihai/Source/Daily/Android/app/src/main/java/com/intellidream/daily/presentation/dashboard/DashboardView.kt) | Added `forceSingleColumn` flag to render as a single column in the left master pane on foldables. |
| [`NewsReaderSheet.kt`](file:///Users/mihai/Source/Daily/Android/app/src/main/java/com/intellidream/daily/presentation/news/NewsReaderSheet.kt) | Adaptive width constraint (`widthIn(max = 700.dp)`) preventing excessively wide text lines on large screens. |
| [`MainActivity.kt`](file:///Users/mihai/Source/Daily/Android/app/src/main/java/com/intellidream/daily/MainActivity.kt) | Adaptive layout switch (`screenWidthDp >= 600`) orchestrating dual-pane vs single-pane execution with symmetrical `weight(1f)` margins. |
| [`ThemeColors.kt`](file:///Users/mihai/Source/Daily/Android/core-designsystem/src/main/java/com/intellidream/daily/designsystem/ThemeColors.kt) | Added `accentYellow` (`0xFFFFD600`) for cross-platform color parity across Weather and Tagdos hubs. |

---

## Verification & Device Matrix

1. **Pixel 9 Pro Fold Emulator (`emulator-5554` / `emulator-5556`)**:
   - Resolution: `2076x2152` px at 390 dpi (~851 dp width).
   - Verified: Dual-pane master-detail renders with 1:1 symmetrical card widths (969px each); diurnal wish header displays accurately; executive summary cards display live data.
   - Header Buttons: Verified via `uiautomator` bounds inspection that all hubs opened in the right pane (Health, Habits, Finances, Tagdos/Notes, News, Weather) feature identical `36.dp` (`44x44` px) circular glass buttons (`CircleShape`, `18.dp` icon, `Color.White.copy(0.08f)` fill, `Color.White.copy(0.12f)` border), perfectly aligned on the vertical center axis (`y = 266 px`).
   - Gestures & Navigation: Verified dismissal back to Companion pane via header back button, drag handle swipe-down, and system back gesture.
2. **Standard Phone Emulator & Compact Layout**:
   - Verified: Single-pane mobile layout with centered bottom capsule retains 100% normal behavior with zero regression.
3. **Physical Samsung Galaxy Z Fold 8 ("RADAR", `SM-F971B`)**:
   - Deployed over wireless adb (`adb-R3GL70B1LGP-HLPtmw._adb-tls-connect._tcp`).
   - Verified: Native build deployed and launched cleanly; 120Hz smooth scrolling; pixel-perfect header button styling and fluid responsive transitions across folded cover display and inner foldable workspace.
4. **Physical Google Pixel 9 Pro ("Trapper")**:
   - Deployed over wireless adb (`adb-48231FDAP0011V-Ma9KPE._adb-tls-connect._tcp`).
   - Verified: Native build deployed and launched cleanly; compact mobile layout and header buttons function identically on physical phone hardware.
