# Android Jetpack Glance Widget Ecosystem: 1:1 iOS Parity & Android 16/17 Architecture

## Executive Summary
This document outlines the complete implementation of the native Android Widget ecosystem for Daily, built with **Jetpack Glance (Material 3 Expressive & Liquid Glass aesthetics)**. It achieves 100% functional and visual parity with the iOS WidgetKit ecosystem (`DailyWidgets`), while preserving native Android design conventions (resizable layouts, `ColorProvider`, dynamic themes, honest empty states, and deep-link navigation into corresponding application hubs).

---

## 1. Widget Architecture & Design System

Every widget is implemented as a Jetpack Glance AppWidget backed by a Glance Receiver and configured via XML AppWidgetProvider metadata:

| Widget Name | Target Feature Hub | iOS Equivalent | Key Metrics & Glance Visual Elements |
|---|---|---|---|
| **Daily Combined Glance Widget** | Health & Dashboard | `CombinedWidget` | 4-column overview (Steps, Heart Rate, Sleep, Stress Level), status badges, instant hub launch. |
| **Daily Stress Glance Widget** | Health -> Stress Studio | `StressWidget` | Real-time Stress Score (0-100), biometric rating (`Calm`, `Moderate`, `High`), calming breathing CTA, deep-link navigation. |
| **Daily Bubbles Glance Widget** | Habits -> Bubbles | `BubblesWidget` | Daily hydration (ml logged vs goal), `LinearProgressIndicator`, percentage completion pill, drink category breakdown. |
| **Daily Smokes Glance Widget** | Habits -> Smokes | `SmokesWidget` | Smokes logged vs baseline daily max, elapsed time since last smoke, lung recovery dynamic color coding (Green/Amber/Coral). |
| **Daily Sleep Studio Glance Widget** | Health -> Sleep | `SleepWidget` | Overnight sleep score (/100), restorative status pill (`Optimal`, `Great`, `Fair`, `Deficit`), Deep & REM duration breakdown, efficiency %. |
| **Daily Money Glance Widget** | Finances -> SmartLedger | `MoneyWidget` | Net worth in Lei (RON) and EUR conversion, incoming vs outgoing cash flow, top active accounts. |
| **Daily Tagdos Glance Widget** | Tagdos & Notes Hub | `TagdosWidget` | Active task queue count, prioritized execution stream pill tags (`[WRK]`, `[FIT]`, `[FIN]`), next scheduled reminder time. |

---

## 2. Liquid Glass & Material 3 Expressive Aesthetics

The Glance widgets match the dark luxury aesthetic of Daily:
- **Surface Elevation**: Dark curved containers (`#07111E`, `#0C0E1E`, `#0F131C`) with `cornerRadius(22.dp)`.
- **Subtle Badging**: Translucent pill containers with matching theme colors (`alpha = 0.20f`).
- **Typography**: Clean hierarchy with high contrast primary metrics (`26.sp` - `28.sp`, Bold) and muted slate secondary text (`#8E9BAE`).
- **Adaptive Sizing**: `minWidth="140dp"` / `minHeight="110dp"`, `resizeMode="horizontal|vertical"`, and `widgetCategory="home_screen"` to scale seamlessly on phones, tablets, and foldable inner/outer screens.

---

## 3. Deep-Link Navigation Architecture

When a user taps any widget, it triggers a `clickable(actionStartActivity(launchIntent))` directing to `MainActivity` with `singleTask` launch mode:

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

## 4. Verification & Testing

1. **Unit Tests**: Executed `./gradlew testDebugUnitTest` across all modules (`:app`, `:core-model`, `:core-database`, `:core-health`, `:core-network`) with 100% pass rate.
2. **Build**: Executed `./gradlew assembleDebug` with 0 warnings or errors.
3. **Emulator (`Medium_Phone_API_36.1` / API 36)**:
   - Verified installation of `com.intellidream.daily.debug`.
   - Verified registration of all 7 widget providers via `adb shell dumpsys appwidget`.
   - Verified deep-link routing into Habits (Smokes), Health (Sleep), Finances (SmartLedger), and Tagdos (Notes).
4. **Physical Device Deployment**:
   - Deployed and verified live on **Google Pixel 9 Pro** (`caiman` via wireless adb `adb-48231FDAP0011V-Ma9KPE`).
   - Verified all 7 widgets registered in `dumpsys appwidget` on physical Pixel 9 Pro.
   - APK built and ready for physical **Samsung Galaxy Z Fold 7** upon reconnecting wireless debugging.
