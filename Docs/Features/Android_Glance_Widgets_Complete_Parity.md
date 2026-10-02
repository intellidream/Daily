# Android Jetpack Glance Widget Ecosystem: 1:1 iOS Parity & Android 16/17 Architecture

## Executive Summary
This document outlines the complete implementation of the native Android Widget ecosystem for Daily, built with **Jetpack Glance (Material 3 Expressive & Liquid Glass aesthetics)**. It achieves 100% functional, structural, and aesthetic parity with the iOS WidgetKit ecosystem (`iOS/DailyWidgets/`), while preserving native Android design conventions (resizable layouts, `ColorProvider`, dynamic themes, honest Room database offline cache, and reactive deep-link navigation into corresponding application hubs).

---

## 1. Widget Architecture & Design System

Every widget is implemented as a Jetpack Glance AppWidget backed by a Glance Receiver and configured via XML AppWidgetProvider metadata:

| Widget Name | Target Feature Hub | iOS Equivalent | Key Metrics & Glance Visual Elements |
|---|---|---|---|
| **Daily Combined Glance Widget** | Health & Executive Hub | `CombinedWidget` | Left hero column (Sleep score gauge + net worth pill + stress mascot pill), right column with 3 metric tiles (Water, Smokes, Tagdos) with color-coded status badges and instant hub launch. |
| **Daily Stress Glance Widget** | Health -> Stress Studio | `StressWidget` | Real-time Stress Score (0-100) circular gauge, Autonomic Balance bar (Parasympathetic Rest vs Sympathetic Active dual gradient capsule), mascot emoji chip, biometric rating pills (HRV, BPM), monkey wisdom card, and studio link. |
| **Daily Bubbles Glance Widget** | Habits -> Bubbles | `BubblesWidget` | Segmented multi-drink arc hero ring on left with intake/goal inside, percentage pill + drop icon on top right, color-coded drink breakdown pills (Water, Coffee, Tea), and 2x2 interactive quick-log buttons (`300`, `150`, `100`, `200`). |
| **Daily Smokes Glance Widget** | Habits -> Smokes | `SmokesWidget` | Anatomical vector lungs circular hero on left with count inside, baseline, elapsed time ago, flame badge, and 2x2 interactive quick-log buttons (`Cgr`, `Rol`, `Cig`, `Heat`). |
| **Daily Sleep Studio Glance Widget** | Health -> Sleep | `SleepWidget` | Radial sleep score gradient ring on left with duration and `${score} pts` capsule, bedtime/wake schedule, multi-stage proportional hypnogram bar (Deep, REM, Light, Awake), 4 mini stage pills, and device badge. |
| **Daily Money Glance Widget** | Finances -> SmartLedger | `MoneyWidget` | 3-column architecture (`NET WORTH`, `FLOW IN/OUT`, `LIQUID`) with dividers and quick adjust action buttons (`-100 Crd`, `-100 Csh`, `+100 Crd`). |
| **Daily Tagdos Glance Widget** | Tagdos & Notes Hub | `TagdosWidget` | `TAGDOS` header, `FOCUS TAG` hero card with starred driving pill and stream title, reminder badge, and Stream 1 / Stream 2 queued tags chains (`➔`). |

---

## 2. Canvas Graphics Engine (`WidgetVisualGraphics.kt`)

Because Jetpack Glance lacks native `Canvas` drawing composables, Daily implements a dedicated high-DPI anti-aliased bitmap graphics rendering engine (`com.intellidream.daily.glance.WidgetVisualGraphics`):

1. **`createMultiDrinkArcBitmap`**: Renders segmented circular arc rings with start/sweep angles corresponding to Water (`#38BDF8`), Coffee (`#D97706`), and Tea (`#10B981`) intake proportions against the daily target.
2. **`createSmokesGaugeBitmap`**: Renders a circular recovery ring combined with true anatomical vector lungs and bronchial tree (exact cubic bezier curves ported directly from iOS `WidgetVectorLungsShape` and `WidgetVectorLungsBronchiShape`).
3. **`createSleepScoreRingBitmap`**: Renders an angular gradient circular arc (Violet `#8B5CF6` to Indigo `#6366F1`) reflecting restorative sleep score percentages.
4. **`createSleepHypnogramBarBitmap`**: Renders a proportional multi-stage hypnogram bar with rounded capsule corners, allocating widths to Deep sleep (`#8B5CF6`), REM (`#38BDF8`), Light (`#60A5FA`), and Awake (`#F59E0B`).
5. **`createStressGaugeBitmap`**: Renders a circular stress score gauge arc with dynamic color shifting (Emerald `#10B981` -> Amber `#F59E0B` -> Rose `#EF4444`).
6. **`createAutonomicBalanceBarBitmap`**: Renders a dual gradient capsule representing Parasympathetic Rest (Teal `#14B8A6`) versus Sympathetic Active (Amber `#F59E0B`) tone.
7. **`createMiniMetricGaugeBitmap`**: Renders mini circular gauges with background track and progress stroke for high-density combined widgets.

All bitmaps are rendered at 2.5x density scale with `Paint.ANTI_ALIAS_FLAG`, ensuring crisp rendering on high-DPI displays (including Google Pixel 9 Pro 120Hz LTPO and Samsung Galaxy Z Fold 7 inner/outer displays).

---

## 3. Interactive Quick Actions (`WidgetActionCallbacks.kt`)

Android Glance widgets feature 1-tap direct logging without needing to open the app:

- **`LogWaterActionCallback`**: Reads amount (`amount_ml`) and drink type (`drink_type`) from action parameters, logs directly into Room DB via `HabitsRepository.logWater()`, and re-triggers `DailyBubblesGlanceWidget().updateAll(context)` and `DailyCombinedGlanceWidget().updateAll(context)`.
- **`LogSmokeActionCallback`**: Reads smoke type (`smoke_type`) from action parameters, logs directly into Room DB via `HabitsRepository.logSmoke()`, and re-triggers `DailySmokesGlanceWidget().updateAll(context)` and `DailyCombinedGlanceWidget().updateAll(context)`.
- **`AdjustLedgerActionCallback`**: Reads adjustment amount and account type (`card` or `cash`), adjusts the balance via `SmartLedgerRepository`, and re-triggers `DailyMoneyGlanceWidget().updateAll(context)`.

---

## 4. Liquid Glass & Material 3 Expressive Aesthetics

The Glance widgets match the dark luxury aesthetic of Daily:
- **Surface Elevation**: Dark curved containers (`#07111E`, `#0C0E1E`, `#0F131C`) with `cornerRadius(22.dp)`.
- **Subtle Badging**: Translucent pill containers with matching theme colors (`alpha = 0.20f`).
- **Typography**: Clean hierarchy with high contrast primary metrics (`26.sp` - `28.sp`, Bold) and muted slate secondary text (`#8E9BAE`).
- **Adaptive Sizing**: `minWidth="140dp"` / `minHeight="110dp"`, `resizeMode="horizontal|vertical"`, and `widgetCategory="home_screen"` to scale seamlessly on phones, tablets, and foldable inner/outer screens.

---

## 5. Deep-Link Navigation Architecture

When a user taps anywhere outside the quick-action buttons, it triggers a `clickable(actionStartActivity(launchIntent))` directing to `MainActivity` with `singleTask` launch mode:

```kotlin
val launchIntent = Intent(context, MainActivity::class.java).apply {
    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
    putExtra(MainActivity.EXTRA_TARGET_TAB, MainActivity.TAB_HABITS)
    putExtra(MainActivity.EXTRA_HABIT_SUBTAB, "smokes")
}
```

### Destination Routing Table
- `MainActivity.EXTRA_TARGET_TAB`:
  - `TAB_HEALTH` -> `NavigationTab.Health`
    - `EXTRA_HEALTH_SUBTAB = "stress"` -> `HealthSubTab.STRESS`
    - `EXTRA_HEALTH_SUBTAB = "sleep"` -> `HealthSubTab.SLEEP`
    - `EXTRA_HEALTH_SUBTAB = "vitals"` -> `HealthSubTab.VITALS`
    - `EXTRA_HEALTH_SUBTAB = "trends"` -> `HealthSubTab.TRENDS`
  - `TAB_HABITS` -> `NavigationTab.Habits`
    - `EXTRA_HABIT_SUBTAB = "smokes"` -> switches to `HabitType.SMOKES`
    - `EXTRA_HABIT_SUBTAB = "water"` -> switches to `HabitType.WATER`
  - `TAB_FINANCES` -> `NavigationTab.Finances`
  - `TAB_TAGDOS` -> `NavigationTab.Tagdos`
  - `TAB_WEATHER` -> `NavigationTab.Weather`
  - `TAB_NEWS` -> `NavigationTab.News`

---

## 6. Verification & Testing

1. **Unit Tests**: Executed `./gradlew testDebugUnitTest` across all modules (`:app`, `:core-model`, `:core-database`, `:core-health`, `:core-network`) with 100% pass rate (0 failures).
2. **Build**: Executed `./gradlew assembleDebug` with 0 errors.
3. **Emulator (`Medium_Phone_API_36.1` / API 36)**:
   - Verified installation of `com.intellidream.daily.debug`.
   - Verified registration of all 7 widget providers via `adb shell dumpsys appwidget`.
   - Verified deep-link routing into Habits (Smokes & Bubbles), Health (Sleep & Stress), Finances (SmartLedger), and Tagdos (Notes).
4. **Physical Device Deployment**:
   - Deployed and verified live on **Google Pixel 9 Pro** (`caiman` via wireless adb `adb-48231FDAP0011V-Ma9KPE`).
   - Verified all 7 widgets registered in `dumpsys appwidget` on physical Pixel 9 Pro.
   - APK built and ready for physical **Samsung Galaxy Z Fold 7**.
