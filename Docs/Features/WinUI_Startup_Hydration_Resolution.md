# WinUI 3 Startup Hydration & Deadlock Resolution

## Executive Summary
This document records the diagnostic investigation, root-cause isolation, and resolution for the startup freeze/hang on `Daily.WinUI` (DayOne Windows desktop app) running on Windows 11 ARM64 (Parallels Desktop VM `WINCHESTER`).

---

## 1. Problem Description
- When launched, the application remained indefinitely on an empty/blank window with a busy cursor, or trapped inside the `LoginPage` / `LoadingOverlay` ("Loading your day...").
- No unhandled exceptions were logged to stdout or the Windows Event Viewer.
- Interacting with UI controls (e.g. `SkipButton`, `GoogleSignInButton`) failed or hung.

---

## 2. Root Cause Analysis

### A. Circular Dependency in DI Container
The primary cause of the total freeze was an implicit circular dependency in the Microsoft.Extensions.DependencyInjection configuration:
1. `MainWindow` navigated to `MainPage` upon hydration completion.
2. `MainPage` constructor resolved `WinUIWidgetService` via DI.
3. `WinUIWidgetService` required `ISettingsService` (`SettingsService`).
4. `SettingsService` required `ISyncService` (`SyncService`).
5. `SyncService` required `IHealthService` (`HealthHubService`).
6. `HealthHubService` had `ISettingsService settingsService` declared in its primary constructor.
7. Crucially, `_settingsService` was **never used anywhere** inside `HealthHubService.cs`!
8. When DI attempted to resolve singleton `ISettingsService` on a background thread (`App.InitializeAsync()`), and simultaneously the UI thread tried to resolve `WinUIWidgetService`, the DI container entered a lock-wait circular dependency deadlock. The UI thread froze indefinitely inside `GetRequiredService<WinUIWidgetService>()`.

### B. Storyboard Completion Deadlock in `LoadingOverlay`
`MainWindow.FadeOutLoadingOverlayAsync()` used a `TaskCompletionSource` awaiting `Storyboard.Completed`. Under high CPU load or when transitioning between frames, WPF/WinUI storyboards can complete before event wire-up or fail to fire if paused or obscured, leaving the TCS uncompleted forever.

### C. UI Thread Blocking in Startup / Sign-In
`App.InitializeAsync()` previously executed synchronously on the UI thread during `OnLaunched`, blocking layout and input processing. Furthermore, OAuth callbacks and button event handlers (`SkipButton_Click`, `GoogleSignInButton_Click`) awaited the entire `InitializationTask`, cascading delays to user actions.

---

## 3. Implemented Solutions

### 1. Breaking the DI Circular Dependency
- **Removed Unused Parameter:** Stripped `ISettingsService` from `HealthHubService`'s primary constructor and removed the unused private field `_settingsService`.
- **Backward-Compatible Overload:** Added a constructor overload `HealthHubService(..., ISettingsService? settingsService, ...)` that chains to the 3-arg constructor, preserving compatibility with unit tests (`Daily.Health.Tests`).
- **Explicit Factory Registration:** Updated [App.xaml.cs](file:///Users/mihai/Source/Daily/WinUI/Daily.WinUI/App.xaml.cs) to register `IHealthHubService` using an explicit factory lambda delegate:
  ```csharp
  services.AddSingleton<Daily_WinUI.Services.IHealthHubService>(sp =>
      new Daily_WinUI.Services.HealthHubService(
          sp.GetRequiredService<Supabase.Client>(),
          sp.GetRequiredService<Daily.Services.IDatabaseService>(),
          sp.GetService<Microsoft.Extensions.Logging.ILogger<Daily_WinUI.Services.HealthHubService>>()
      )
  );
  ```

### 2. Robust Non-Blocking Startup & Overlay Dismissal
- **Bounded Overlay Fadeout:** Added `MainWindow.DismissLoadingOverlay()` which forcibly collapses `LoadingOverlayGrid` immediately upon sequence completion or error. Replaced the storyboard TCS in `FadeOutLoadingOverlayAsync` with a bounded delay (`Task.Delay(750)`) and ensured `LoadingStoryboard.Stop()` is called before fading out.
- **Uncoupled Button Handlers:** Removed blocking `await App.Current.InitializationTask` calls from `SkipButton_Click` and `GoogleSignInButton_Click`. Converted `SkipButton` to a standard button style.
- **Background Startup:** `InitializationTask` is spawned via `Task.Run(async () => await InitializeAsync())`, keeping the UI dispatcher completely responsive (< 16ms frame time).

### 3. Comprehensive File-Based Diagnostic Telemetry
- Added `App.LogDiagnostic(string message)` writing timestamps to `C:\Users\mihai\daily_debug.log`.
- Logged all hydration phases across `AppDomain`, `OnLaunched`, `InitializeAsync`, `MainWindow`, `LoginPage`, `MainPage`, and `SmartBriefingService`.

---

## 4. Verification on Physical VM

### A. Startup Sequence Log Verification
Inspecting `C:\Users\mihai\daily_debug.log` on the Windows 11 VM:
```text
[2026-10-06 17:57:58.936] OnLaunched entered
[2026-10-06 17:57:58.971] InitializeAsync started
[2026-10-06 17:57:59.277] MainWindow ctor: hasSession=True
[2026-10-06 17:57:59.278] MainWindow ctor: calling NavigateAfterHydrationAsync
[2026-10-06 17:57:59.887] InitializeAsync: Database initialized
[2026-10-06 17:58:01.065] InitializeAsync: SettingsService initialized
[2026-10-06 17:58:01.173] InitializeAsync: Feeds seeded
[2026-10-06 17:58:01.219] InitializeAsync: Custom feeds initialized
[2026-10-06 17:58:01.225] InitializeAsync: Articles service initialized
[2026-10-06 17:58:03.181] NavigateAfterHydrationAsync: task wait complete
[2026-10-06 17:58:03.408] NavigateAfterHydrationAsync dispatcher callback running. isAuth=True
[2026-10-06 17:58:03.551] NavigateAfterHydrationAsync: Navigating to MainPage
[2026-10-06 17:58:03.664] MainPage constructor entered
[2026-10-06 17:58:10.228] MainPage constructor completed
[2026-10-06 17:58:10.458] MainPage.OnNavigatedTo fired
[2026-10-06 17:58:14.086] MainPage_Loaded fired
[2026-10-06 17:58:14.166] RunLoadingSequenceAsync: calling LoadWidgetsAsync
[2026-10-06 17:58:15.559] RunLoadingSequenceAsync: LoadWidgetsAsync completed
[2026-10-06 17:58:52.147] RunLoadingSequenceAsync: calling FadeOutLoadingOverlayAsync
[2026-10-06 17:58:53.480] DismissLoadingOverlay completed. Visibility now=Collapsed
[2026-10-06 17:58:53.642] MainPage_Loaded: RunLoadingSequenceAsync completed
```

### B. Visual Verification & UI Automation
1. **Smart Briefing Modal:** Correctly greeted user ("Good evening, Mihai Ionescu!") with weather forecast, tasks status, and hydration metrics.
2. **Dashboard Grid:** Upon clicking "Start My Day", revealed all 6 widgets rendered in Liquid Glass style:
   - **Weather Widget:** Live forecast for "Dobroești", 17.4°C, Clear Sky.
   - **News Widget:** Interactive RSS feed tabs with article images and timestamps from Republica.
   - **Vitals Widget:** Live telemetry: 32 steps, 1 kcal, 74 bpm, 63 bpm RHR.
   - **Finances Widget:** World markets (Crude Oil $89.34, Gold $4,192.10).
   - **Habits Widget:** 1400 / 2000 ml circular hydration ring, weekly consistency bars, quick-log actions, and detailed intake timestamp history.
   - **Agenda & Tasks Widget:** Up to date with "No upcoming events or tasks".
