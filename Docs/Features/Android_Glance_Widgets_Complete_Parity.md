# Android Jetpack Glance Widget Ecosystem: 1:1 iOS Parity & Android 16/17 Architecture

## Executive Summary
This document outlines the complete implementation of the native Android Widget ecosystem for Daily, built with **Jetpack Glance (Material 3 Expressive & Liquid Glass aesthetics)**. It achieves 100% functional, structural, and aesthetic parity with the iOS WidgetKit ecosystem (`iOS/DailyWidgets/`), while preserving native Android design conventions (resizable layouts, `ColorProvider`, dynamic themes, honest Room database offline cache, and reactive deep-link navigation into corresponding application hubs).

---

## 1. Widget Architecture & Design System

Every widget is implemented as a Jetpack Glance AppWidget backed by a Glance Receiver and configured via XML AppWidgetProvider metadata with **`SizeMode.Responsive`** supporting distinct Small, Medium, and Large views:

| Widget Name | Target Feature Hub | iOS Equivalent | Key Metrics & Glance Visual Elements |
|---|---|---|---|
| **Daily Combined Glance Widget** | Health & Executive Hub | `CombinedWidget` | **Small**: Hero sleep ring + vital metrics. **Medium**: Hero metrics column + 3 dual-tile cards (Water, Smokes, Finances/Tagdos). **Large**: Full 4-quadrant executive dashboard matching iOS `.systemLarge`. |
| **Daily Stress Glance Widget** | Health -> Stress Studio | `StressWidget` | **Small**: Stress gauge ring (0-100), autonomic balance score, mascot mood badge. **Medium**: Radial gauge + autonomic tone bar + biometric rating pills (HRV, BPM) + mascot quote card. |
| **Daily Bubbles Glance Widget** | Habits -> Bubbles | `BubblesWidget` | **Small**: Multi-drink segmented arc + intake / goal + percentage pill. **Medium**: Segmented ring + Water/Coffee/Tea pills + 2x2 quick-log buttons. **Large**: Detailed breakdown chart + progress analytics + hydration schedule. |
| **Daily Smokes Glance Widget** | Habits -> Smokes | `SmokesWidget` | **Small**: Vector lungs hero + count/baseline + flame icon. **Medium**: Vector lungs + time ago + cost breakdown + 2x2 quick-log buttons (`Cgr`, `Rol`, `Cig`, `Heat`). **Large**: Complete smoking timeline + cessation financial tracker. |
| **Daily Sleep Studio Glance Widget** | Health -> Sleep | `SleepWidget` | **Small**: Radial sleep score gradient ring + duration + sleep quality rating. **Medium**: Sleep score + schedule + proportional hypnogram bar (Deep, REM, Light, Awake). **Large**: Deep architecture analysis + restorative ratio + resting HR/HRV telemetry. |
| **Daily Money Glance Widget** | Finances -> SmartLedger | `MoneyWidget` | **Small**: Net worth (Lei + EUR) + card/cash badges. **Medium**: 3-column architecture (`NET WORTH`, `FLOW IN/OUT`, `LIQUID`) with quick adjustments (`-100 Crd`, `+100 Crd`). **Large**: Full ledger category breakdown + top outgoings list. |
| **Daily Tagdos Glance Widget** | Tagdos & Notes Hub | `TagdosWidget` | **Small**: Driving priority tag pill + active count + reminder pill. **Medium**: Stream 1 & Stream 2 queued tags chains (`➔`) with priority color badges. **Large**: Multi-stream queue view with active memo snippets. |

---

## 2. Canvas Graphics & Vector Iconography Engine (`WidgetVisualGraphics.kt`)

Because Jetpack Glance does not support arbitrary custom canvas composables in standard layout declarations, Daily implements a dedicated high-DPI anti-aliased bitmap vector graphics engine (`com.intellidream.daily.glance.WidgetVisualGraphics`):

1. **Native SF-Symbol Port Vector Icons (`WidgetIconType`)**:
   - `FLAME`: Multi-tier flame glyph with inner spark core.
   - `DROP`: Slender fluid water drop with specular highlight.
   - `MOON`, `MOON_STARS`, `MOON_ZZZ`: Celestial crescent with sleep zzz indicators.
   - `WALLET`, `CREDIT_CARD`: Financial leather wallet with metallic clasp and payment card with security chip and magnetic stripe.
   - `CHECKLIST`, `BELL`, `SPARKLES`, `HEART`, `ECG`, `APPLE_WATCH`, `CHEVRON_RIGHT`, `ARROW_RIGHT`: Crisp anti-aliased native Canvas paths.
2. **`createVectorLungsBitmap`**: Isolated anatomical lungs + bronchial tree using exact cubic bezier curves matching iOS `WidgetVectorLungsShape` and `WidgetVectorLungsBronchiShape`.
3. **`createMultiDrinkArcBitmap`**: Segmented circular arc rings with start/sweep angles corresponding to Water (`#00E5FF`), Coffee (`#F59E0B`), and Tea (`#84CC16`) intake proportions against the daily target.
4. **`createSleepScoreRingBitmap`**: Angular gradient circular arc (Cyan `#00E5FF` to Emerald `#10B981`) reflecting restorative sleep score percentages.
5. **`createSleepHypnogramBarBitmap`**: Proportional multi-stage hypnogram bar with rounded capsule corners, allocating widths to Deep sleep (`#8B5CF6`), REM (`#3B82F6`), Light (`#00E5FF`), and Awake (`#EF4444`).
6. **`createStressGaugeBitmap`**: Circular stress score gauge arc with dynamic color shifting (Emerald `#10B981` -> Amber `#FFB800` -> Rose `#EF4444`).
7. **`createAutonomicBalanceBarBitmap`**: Dual gradient capsule representing Parasympathetic Rest (Teal `#00E5FF` -> Green `#00FFB2`) versus Sympathetic Active tone.
8. **`createLinearProgressBarBitmap`**: High-performance anti-aliased linear bar for progress telemetry.
9. **`createMiniMetricGaugeBitmap`**: Mini circular gauges with background track and progress stroke for high-density combined widgets.

All bitmaps are rendered with `Paint.ANTI_ALIAS_FLAG` at device-scaled pixel densities, ensuring crisp rendering on high-DPI displays (including Google Pixel 9 Pro 120Hz LTPO and Samsung Galaxy Z Fold 7 inner/outer displays).

---

## 3. Responsive Multi-Size Support (`SizeMode.Responsive`)

All 7 widgets implement `SizeMode.Responsive` targeting:
- `SMALL_BOX` (120.dp x 100.dp): Compact 2x2 grid cell with high-contrast focal metrics.
- `MEDIUM_BOX` (240.dp x 100.dp): Standard 4x2 widget row balancing hero gauges with structured metadata pills and interactive buttons.
- `LARGE_BOX` (240.dp x 200.dp): Comprehensive 4x4 card displaying extended hypnograms, itemized lists, and multi-stream queues.

Each widget dynamically selects its layout based on `LocalSize.current.width` and `LocalSize.current.height`.

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
   - Verified live visual rendering on home screen across 4 home screen pages:
     - `DailyCombinedGlanceWidget` (Daily Executive with hero sleep ring, vital telemetry, water/smokes/stress pills).
     - `DailySmokesGlanceWidget` (Vector lung health gauge, breakdown indicators, quick-action logging buttons).
     - `DailyBubblesGlanceWidget` (Hydration progress ring, volume breakdown, quick-log buttons).
     - `DailySleepGlanceWidget` (Sleep score ring, sleep architecture hypnogram bar, timing telemetry).
     - `DailyStressGlanceWidget` (Circular stress score ring, autonomic balance tone, HRV telemetry).
     - `DailyMoneyGlanceWidget` (Net worth in Lei and EUR, deposits, liquid cash/card breakdown, outgoing allocations).
     - `DailyTagdosGlanceWidget` (Active stream tags, priority badges, scheduled reminders).
   - Verified deep-link routing into Habits (Smokes & Bubbles), Health (Sleep & Stress), Finances (SmartLedger), and Tagdos (Notes).
4. **Physical Device Deployment**:
   - Deployed and verified live on **Google Pixel 9 Pro** (`caiman` via wireless adb `adb-48231FDAP0011V-Ma9KPE`).
   - Verified all 7 widgets registered and actively rendering RemoteViews in `dumpsys appwidget` on physical Pixel 9 Pro.
   - APK built and ready for physical **Samsung Galaxy S25 Edge / Z Fold 7**.

---

## 7. Troubleshooting & RemoteViews Inflation Hardening

### "Can't load widget" Root Cause Analysis
During initial deployment, the Android Launcher reported **"Can't load widget"** when trying to inflate widgets. Logcat revealed the following fatal exception in `RemoteViews`:
```text
Caused by: android.content.res.Resources$NotFoundException: Can't find ColorStateList from drawable resource ID #0x7f060035
    at android.content.res.ResourcesImpl.loadColorStateList(ResourcesImpl.java:1284)
    at android.content.res.Resources.getColor(Resources.java:1098)
    at android.content.Context.getColor(Context.java:1227)
    at android.widget.RemoteViews$ResourceReflectionAction.getParameterValue(RemoteViews.java:3666)
```

**Why it happened**:
In Jetpack Glance, `GlanceModifier.background(resId: Int)` is annotated with `@ColorRes`. When passing `R.drawable.widget_background` as a raw integer, Kotlin resolved the `@ColorRes` overload. Jetpack Glance translated this into `RemoteViewsCompat.setViewBackgroundColorResource()`, which instructed the launcher to call `context.getColor(resId)`. Because `widget_background.xml` is a `<shape>` drawable rather than a `<color>`, Android threw `Resources$NotFoundException`, failing inflation.

### Solution Applied Across All 7 Widgets:
1. **Explicit `ImageProvider`**: Wrapped the drawable in `ImageProvider(R.drawable.widget_background)`. This instructs Jetpack Glance to invoke `RemoteViewsCompat.setViewBackgroundResource()`, safely dispatching `view.setBackgroundResource(R.drawable.widget_background)` to Android's View system.
2. **`appWidgetBackground()` Modifier**: Added `GlanceModifier.appWidgetBackground()` to the root container of all 7 widgets (`DailyCombined`, `DailySmokes`, `DailyBubbles`, `DailySleep`, `DailyStress`, `DailyMoney`, `DailyTagdos`). This marks the background element for system outline clipping and smooth transitions on Android 12+.
3. **`WidgetUpdateHelper`**: Implemented `WidgetUpdateHelper.updateAllWidgets(context)` called during application startup (`DailyApp.onCreate`) and `MainActivity.onResume` to keep all placed widgets synchronized with the Room database.
4. **Programmatic Pinning Support (`EXTRA_PIN_WIDGET`)**: Added direct support in `MainActivity` for pinning any widget to the home screen via `AppWidgetManager.requestPinAppWidget()`.
