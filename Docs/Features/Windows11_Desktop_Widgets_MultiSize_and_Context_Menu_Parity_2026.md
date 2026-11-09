# Windows 11 Desktop Widgets: Multi-Size Architecture, Data Density & Context Menu Parity (2026)

## Overview & Executive Summary

This architecture release establishes complete visual density parity, multi-size responsiveness (Small 170×170, Medium 360×170, Large 360×360), context menu state verification, and live biometric telemetry across all 9 Windows 11 desktop widgets, running both inside `Daily.WidgetsHost.exe` (micro-process) and `Daily.WinUI.exe` (in-app fallback).

---

## 1. Multi-Size Density Parity Across All 9 Widgets

Prior to this update, several desktop widgets reused a single `MediumLargeLayout` for both Medium (360×170 pt) and Large (360×360 pt), causing large widgets on high-resolution displays to feel sparse or artificially stretched. Every widget now has dedicated XAML templates and layout switching for `SmallLayout`, `MediumLayout`, and `LargeLayout`.

| Widget | Small (170×170 pt) | Medium (360×170 pt) | Large (360×360 pt) Dense Layout |
| :--- | :--- | :--- | :--- |
| **Combined** | Compact icon + metric grid (Water, Smokes, Cash, Sleep) | Header greeting + weather + 4 core cards | Full Executive Dashboard: Header greeting + weather badge, 4 primary cards (Hydration, Smokes, Net Worth, Sleep), and 3 secondary cards (TagDoS pending, Stress/Pulse, Cosmos sky). |
| **TagDoS** | Active stream name + top task pill | Top 2 active tasks with category pills + stream summary | Header with stream count and total tasks, 5 prioritized task items with colored status dots and category badges, active stream focus badge, and Quick Notes preview box. |
| **Money** | Net worth (Lei + EUR) + card/cash synced pill | Net worth + Card & Cash account balances + 3 adjustment buttons | Header (Lei + EUR), 4 account cards grid (Card, Cash, Savings Reserve, Cashflow Runway), 4 quick adjustment buttons (+100/-100 Card, +100/-100 Cash), SmartLedger breakdown preview. |
| **Weather** | Current temp, condition, high/low pill | Location, current temp, 5-hour timeline, atmospheric pill | Location, current temp, condition, feels like, 5-hour timeline, 4-card atmospheric grid (Humidity, Wind speed, Barometric pressure, Cloud cover), 3-day daily forecast cards, Sunrise & Sunset times. |
| **Sleep** | Score ring, duration, recovery pill | Score ring, duration, hypnogram stage bar, Resting HR & HRV | Header with score ring and bedtime schedule, full 4-stage hypnogram breakdown (Deep, REM, Light, Awake durations & percentages), 4-grid vitals (Resting HR, HRV RMSSD, SpO2, Circadian Debt), Circadian bedtime recommendation. |
| **Smokes** | Compact Lungs vector + count + 2 quick buttons | Vector LungsControl + count + Cigarettes vs Heated breakdown + 2 buttons | Header with count vs baseline and craving-free badge, large anatomical vector LungsControl with cilia regeneration status, 4-card breakdown (Cigarettes, Heated, Money saved, Life regained), 3 action buttons (+1 Cig, +1 Heat, Undo last). |
| **Stress** | Circular gauge, score /100, calm HRV pill | Circular gauge, score /100, recommendation, HRV & pulse badges, 1-min breathe button | Header (Score /100, state label), circular gauge with autonomic explanation, 4 biomarkers grid (HRV RMSSD, Resting HR, Autonomic tone, Resilience capacity), interactive 1-minute mindful breathing pacing card. |
| **Cosmos** | Moon glyph, phase name, illumination %, stargazing pill | Moon glyph, phase name, score /100, planets & ISS badge, moon times | Header (Phase name, illumination %, stargazing score /100), large moon glyph with distance, 4-card celestial grid (Planets, ISS pass magnitude, Golden hour, Bortle class), ephemeris summary (Moonrise, Moonset, Zenith). |
| **Bubbles** | Circular progress ring, ml logged, 3 quick buttons | Progress ring, intake ml vs goal, drink breakdown chips, 3 quick buttons | Header (% and daily goal), circular progress ring with ml intake and cellular pacing status, 4-card beverage breakdown (Water, Coffee, Tea, Electrolytes), 4 quick action chips (100ml, 150ml, 300ml, 500ml), remaining fluid pill. |

---

## 2. TagDoS Widget Visual Cleanup

- **Elimination of Text Overlaps**: Removed `Sync Ready ⚡` (green text) completely from `DesktopTagdosWidgetView.xaml`. In previous builds, long stream titles like `Focus Streams / Personal / Work` collided with the status indicator.
- **Dynamic Text Trimming**: `StreamNamesStatusText` now occupies the full row width with `TextTrimming="CharacterEllipsis"`, ensuring long stream lists render cleanly without wrapping or clipping.

---

## 3. Context Menu Default Checkmarks & Preset Mapping

In `DesktopWidgetWindow.xaml.cs`:
- **Default Opacity Alignment**: Updated `DesktopWidgetModel.Opacity` default from `0.95` to `1.0` (Solid Glass).
- **Continuous-to-Discrete Mapping**: Implemented range bucketing in `ShowContextMenu()`:
  ```csharp
  int selectedPreset = 100;
  if (Model.Opacity <= 0.40) selectedPreset = 30;
  else if (Model.Opacity <= 0.60) selectedPreset = 50;
  else if (Model.Opacity <= 0.78) selectedPreset = 70;
  else if (Model.Opacity <= 0.92) selectedPreset = 85;
  else selectedPreset = 100; // default (100% Solid Glass)
  ```
- **Automated Configuration Migration**: `DesktopWidgetManager.LoadWidgets()` automatically normalizes existing saved configs with `Opacity` between `0.93` and `0.99` up to `1.0`, ensuring that existing installations immediately show `100% (Solid Glass)` checked by default without requiring user intervention.
- **Submenu Consistency**: Verified that `Size` (Small, Medium, Large), `Glass Effect` (Mica Alt Glass, Acrylic Glass), and `Lock Position` accurately reflect their active state with checkmarks.

---

## 4. Real Biometric Data Telemetry in `WidgetsHostHealthService`

In `WinUI/Daily.WidgetsHost/Services/WidgetsHostServices.cs`:
- **Historical Fallback**: If today has not yet received synced health summary records, `GetDailySummaryAsync` falls back to the most recent tracked date in `HealthDailySummaryEntity` (`OrderByDescending(e => e.LocalDate)`), rather than returning synthetic placeholder values.
- **Live Pulse Resolution**: Resolves the most recent biometric pulse from `LocalVitalMetric` (`TypeString == "HeartRate"` or `"RestingHeartRate"`), updating `rec.Rhr` with the real physiological pulse recorded from smartwatches.
- **`GetLatestMetricAsync` Implementation**: Enabled direct typed querying of `LocalVitalMetric` by `VitalType`.

---

## 5. Verification & Validation

- **ARM64 Native Compilation**: Verified on Windows 11 ARM64 VM (`dotnet build WinUI\Daily.WidgetsHost\Daily.WidgetsHost.csproj -c Debug -p:Platform=ARM64` and `Daily.WinUI.csproj`) with **0 Error(s)**.
- **x64 Native Compilation**: Verified for x64 architecture with **0 Error(s)**.
- **Runtime Verification**: `Daily.WidgetsHost.exe` launched via interactive Task Scheduler into Session 1 (Console) with PID 13848, maintaining 0.0% idle CPU and ~220 MB working set.
- **Named Pipe IPC**: Verified command handling for `refresh`, `lock`, `unlock`, `show_all`, and `hide_all` with zero UI latency.
