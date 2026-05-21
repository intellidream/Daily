# Supabase Realtime: Threading Pitfalls & Cross-Platform Verification Checklist

*Created: 2026-05-21 — After diagnosing and fixing iOS MAUI app freezes caused by Supabase Realtime threading issues.*

## Overview

After implementing Supabase Realtime channels across the Daily app, the iOS MAUI variant began freezing progressively — the app would launch, work briefly (e.g., log water), then become permanently unresponsive. macOS MAUI and WinUI were unaffected due to more lenient threading environments and larger thread pools.

This document captures **every issue found**, the **root cause**, the **fix applied**, and a **verification checklist** for auditing any app variant that uses Supabase Realtime.

---

## Issue 1: Infinite Watchdog Loops (Thread Pool Saturation)

### What Was Wrong
Three services (`HabitsService`, `SupabaseHealthService`, `SettingsService`) each ran a `while(true)` loop via `Task.Run` that:
- Polled every 2 minutes to check if Realtime channels were still joined
- Called `SetupRealtimeAsync()` (which acquires a `SemaphoreSlim` and awaits `Subscribe()`)
- Never terminated — not on logout, not on app backgrounding, never

### Why It's Dangerous
- Each loop permanently occupies a thread pool thread
- On iOS, the thread pool starts with only ~2-4 threads and grows slowly
- Three permanent threads + WebSocket threads = thread pool starvation
- The watchdog was **redundant** — `AddStateChangedHandler` already triggered reconnection on `SocketState.Open`

### The Fix
- **Removed** all `StartWatchdog()` methods and their calls
- Reconnection is now handled solely by the `AddStateChangedHandler` with debouncing (see Issue 3)

### Verification Checklist
- [ ] Search for `while (true)` or `while(true)` in all service files
- [ ] Search for `Task.Delay` inside infinite loops — if found, verify there's a `CancellationToken`
- [ ] Confirm no service starts a permanent background `Task.Run` from its constructor
- [ ] Verify `AddStateChangedHandler` is already registered for reconnection (making watchdogs redundant)

---

## Issue 2: Platform AppDelegate Creating Multiple App Instances

### What Was Wrong
The iOS `AppDelegate.FinishedLaunching` called `CreateMauiApp()` explicitly to resolve `IWatchConnectivityService` early, then `base.FinishedLaunching()` created a **second** `MauiApp`. This resulted in:
- Two `Supabase.Client` singletons (registered as Singleton)
- Two Realtime WebSocket connections
- Two sets of all services
- The first instance's resources were orphaned but never disposed

### Why It's Dangerous
- Doubles WebSocket connections and thread consumption
- The orphaned Supabase client may still attempt token refresh, calling `SaveSession()` on a disposed service
- Only affects iOS because macOS and Windows don't override `FinishedLaunching` the same way

### The Fix
- Call `base.FinishedLaunching()` first, then resolve services from `IPlatformApplication.Current.Services`

### Verification Checklist
- [ ] **iOS `AppDelegate.cs`**: Verify `CreateMauiApp()` is NOT called explicitly — only `base.FinishedLaunching()` should create the app
- [ ] **macOS `AppDelegate.cs`**: Same check
- [ ] **Android `MainApplication.cs`**: Verify `CreateMauiApp()` is only called once (the framework calls it)
- [ ] **WinUI `App.xaml.cs`**: Verify the Supabase client is only instantiated once
- [ ] Verify the Supabase client is registered as `AddSingleton` (not `AddTransient`) in `MauiProgram.cs`

---

## Issue 3: Reconnection Stampede (No Debouncing)

### What Was Wrong
When the Realtime socket reconnected (`SocketState.Open`), all three services' `AddStateChangedHandler` callbacks fired simultaneously, each calling `Task.Run(async () => await SetupRealtimeAsync())`. This "triple stampede" caused:
- Three concurrent `SemaphoreSlim.WaitAsync()` calls
- Three concurrent channel subscriptions hitting the same WebSocket
- Six thread pool threads consumed (3 running, 3 blocked)

### Why It's Dangerous
- The Supabase Realtime client may not be thread-safe for concurrent channel creation
- On iOS, six simultaneous thread pool threads can cause starvation
- Even on Windows/macOS, concurrent semaphore contention adds latency

### The Fix
- Added `CancellationTokenSource`-based debouncing with a 1-second delay:
```csharp
private CancellationTokenSource? _reconnectCts;

_supabase.Realtime.AddStateChangedHandler((sender, state) =>
{
    if (state == SocketState.Open)
    {
        _reconnectCts?.Cancel();
        _reconnectCts = new CancellationTokenSource();
        var token = _reconnectCts.Token;
        Task.Run(async () =>
        {
            try
            {
                await Task.Delay(1000, token); // Debounce
                if (!token.IsCancellationRequested)
                    await SetupRealtimeAsync();
            }
            catch (TaskCanceledException) { }
        });
    }
});
```

### Verification Checklist
- [ ] Every `AddStateChangedHandler` callback that calls `SetupRealtimeAsync()` must use debouncing
- [ ] Verify the debounce uses `CancellationTokenSource` (not just `Task.Delay`)
- [ ] In WinUI: check if Realtime state handlers exist and apply the same pattern
- [ ] Ensure `TaskCanceledException` is caught in the debounce handler

---

## Issue 4: AutoConnectRealtime and Connection/Subscription Sequence

### What Was Wrong
The app initially suffered from a "reconnection stampede" during startup because `AutoConnectRealtime = true` connected the socket immediately, causing multiple services' `SocketState.Open` event handlers to fire concurrently. In trying to fix this, setting `AutoConnectRealtime = false` and calling manual `ConnectAsync()` introduced two critical errors:
1. **403 Forbidden Error**: A manual `ConnectAsync()` call during early initialization connected the WebSocket without the proper user session authentication context, leading to standard 403 authorization failures on connection.
2. **Socket must exist exception**: Attempting to call `_supabase.Realtime.Channel()` or `Subscribe()` inside the services' `InitializeAsync()` (which executes before the manual `ConnectAsync()`) threw an exception because the underlying socket instance was not yet initialized.

### Why It's Dangerous
- Setting `AutoConnectRealtime = false` completely breaks all Realtime sync/update channels (they never connect or join).
- Attempting to bypass the SDK's internal connection lifecycle management leads to race conditions with token hydration.

### The Fix
- **Keep `AutoConnectRealtime = true`** in `MauiProgram.cs` (and WinUI) so that the Supabase client correctly creates the WebSocket and binds it to the authentication session.
- **Rely on Debouncing**: Since each service now has a debounced handler for `SocketState.Open` using `CancellationTokenSource`, the reconnection stampede is fully mitigated and no longer causes hangs/resource exhaustion on startup.
- **Remove manual `ConnectAsync()` calls** from `App.xaml.cs`.

### Verification Checklist
- [x] **`MauiProgram.cs`**: Verify `AutoConnectRealtime = true`
- [x] **`App.xaml.cs`**: Verify no manual `ConnectAsync()` calls are present in the startup flow
- [x] **WinUI equivalent**: Verify `AutoConnectRealtime = true` in WinUI
- [x] Verify that all services' `AddStateChangedHandler` callbacks use debouncing to prevent simultaneous connection stampedes.

---

## Issue 5: Session Persistence Blocking the WebSocket Thread

### What Was Wrong
`MauiSessionPersistence.cs` implements `IGotrueSessionPersistence<Session>`, which is a **synchronous** interface. The `SaveSession()` and `LoadSession()` methods used:
```csharp
Task.Run(async () => await SecureStorage.SetAsync(key, json)).GetAwaiter().GetResult();
```

Worse, `SaveSession()` called `LoadSession()` recursively to preserve provider tokens — meaning **every token refresh did TWO synchronous blocking Keychain/credential operations**.

### Why It's Dangerous
- Supabase's `AutoRefreshToken` triggers `SaveSession()` from the Realtime WebSocket's receive loop thread
- Blocking that thread stalls the entire Realtime system — no messages are received until the block releases
- On iOS, Keychain (`SecureStorage`) operations are slow and sensitive to threading
- The recursive `SaveSession→LoadSession` doubles the blocking time
- If `SecureStorage` hangs (iOS Keychain under contention), the deadlock is permanent

### The Fix
1. **In-memory session cache** eliminates the recursive `LoadSession()` call:
   ```csharp
   private Session? _cachedSession;
   // SaveSession now reads from _cachedSession instead of calling LoadSession()
   ```
2. **5-second timeout** prevents permanent blocking:
   ```csharp
   Task.Run(async () => await SecureStorage.SetAsync(key, json))
       .WaitAsync(TimeSpan.FromSeconds(5))
       .GetAwaiter().GetResult();
   ```

### Verification Checklist
- [ ] Search for `.GetAwaiter().GetResult()` across all projects
- [ ] Search for `.Result` and `.Wait()` — these are equally dangerous
- [ ] Verify `SaveSession()` does NOT call `LoadSession()` (uses cache instead)
- [ ] Verify all blocking async calls have a timeout via `.WaitAsync(TimeSpan.FromSeconds(N))`
- [ ] **WinUI**: Check if the WinUI app has its own session persistence implementation — apply the same fixes
- [ ] **Android**: Keychain equivalent (`SharedPreferences`) is faster, but the blocking pattern is still risky

---

## Issue 6: ContinueWith Without TaskScheduler

### What Was Wrong
Realtime callbacks used `.ContinueWith()` without specifying `TaskScheduler.Default`:
```csharp
_repository.SaveLocalLogAsync(localLog).ContinueWith(_ => OnHabitsUpdated?.Invoke());
```

### Why It's Dangerous
- Without specifying a scheduler, `ContinueWith` uses the current `SynchronizationContext`
- On iOS, if the Realtime callback runs on a thread with a sync context, the continuation could try to marshal back to it
- Can cause subtle thread affinity issues and UI hangs

### Recommendation
Replace with `await`:
```csharp
await _repository.SaveLocalLogAsync(localLog);
OnHabitsUpdated?.Invoke();
```
Or specify the scheduler:
```csharp
.ContinueWith(_ => OnHabitsUpdated?.Invoke(), TaskScheduler.Default);
```

### Verification Checklist
- [ ] Search for `.ContinueWith(` across all projects
- [ ] Verify each usage either specifies `TaskScheduler.Default` or is replaced with `await`
- [ ] Pay special attention to `ContinueWith` in Realtime callback handlers

---

## Issue 7: No App Lifecycle Management for Realtime

### What Was Wrong
There were no `OnSleep`/`OnResume` overrides in `App.xaml.cs`, and no background modes declared in `Entitlements.plist`. This means:
- When iOS backgrounds the app, the WebSocket is killed (~30s) but no cleanup occurs
- When the app returns to foreground, no explicit reconnection runs
- The app relied on watchdog loops (now removed) for eventual reconnection

### Why It's Dangerous
- On iOS, app suspension freezes all threads — `Task.Delay` loops don't fire
- On resume, any surviving watchdogs would all fire simultaneously (stampede)
- Without lifecycle hooks, the Realtime state may be inconsistent on resume

### Recommendation (Future Enhancement)
Add lifecycle handlers:
```csharp
protected override void OnSleep()
{
    // Disconnect Realtime cleanly
    _ = _supabase.Realtime.DisconnectAsync();
}

protected override void OnResume()
{
    // Reconnect after foregrounding
    _ = Task.Run(async () =>
    {
        await Task.Delay(500); // Brief delay for UI to settle
        await _supabase.Realtime.ConnectAsync();
    });
}
```

### Verification Checklist
- [ ] **iOS/macOS MAUI**: Check for `OnSleep`/`OnResume` in `App.xaml.cs`
- [ ] **WinUI**: Check for window activation/deactivation handlers
- [ ] **Android**: Check for `OnPause`/`OnResume` lifecycle handling
- [ ] Verify Realtime is disconnected on background and reconnected on foreground

---

## Quick Audit Commands

Run these from the project root to quickly scan for common issues:

```bash
# Find infinite loops
grep -rn "while (true)" --include="*.cs" Services/

# Find blocking async patterns
grep -rn "\.GetAwaiter()\.GetResult()" --include="*.cs" .
grep -rn "\.Result" --include="*.cs" Services/
grep -rn "\.Wait()" --include="*.cs" Services/

# Find ContinueWith without TaskScheduler
grep -rn "\.ContinueWith(" --include="*.cs" Services/

# Find watchdog/polling patterns
grep -rn "StartWatchdog\|Task\.Delay.*FromMinutes" --include="*.cs" Services/

# Check AutoConnectRealtime setting
grep -rn "AutoConnectRealtime" --include="*.cs" .

# Find fire-and-forget Task.Run in constructors
grep -rn "Task\.Run" --include="*.cs" Services/
```

---

## Platform-Specific Thread Pool Characteristics

Understanding why iOS is more susceptible:

| Aspect | iOS | macOS (Catalyst) | Windows (WinUI) | Android |
|--------|-----|------------------|-----------------|---------|
| Thread Pool Initial Size | ~2-4 | ~8+ | ~8+ | ~4-8 |
| Thread Pool Growth Rate | Slow (conservative) | Fast | Fast | Moderate |
| SynchronizationContext | Strict single-thread | More lenient | Single-thread (DispatcherQueue) | Single-thread (Looper) |
| WebSocket Implementation | Managed (`ClientWebSocket`) | Managed | Managed | Managed |
| Background Execution | Suspended after ~30s | Unlimited | Unlimited | Limited |
| Keychain/Credential Speed | Slow (secure enclave) | Fast | Fast (DPAPI) | Fast (EncryptedSharedPrefs) |

**Key takeaway**: iOS is always the canary — if it works on iOS, it will work everywhere. If it freezes on iOS, the same bugs exist on other platforms but are masked by larger thread pools and faster scheduling.

---

## Files Modified in the iOS Fix (May 2026)

| File | Change |
|------|--------|
| `Services/HabitsService.cs` | Removed watchdog, added debounced reconnection |
| `Services/Health/SupabaseHealthService.cs` | Same |
| `Services/SettingsService.cs` | Same |
| `MauiProgram.cs` | `AutoConnectRealtime = false` |
| `App.xaml.cs` | Explicit `ConnectAsync()` after service init |
| `Platforms/iOS/AppDelegate.cs` | Fixed double `MauiApp` creation |
| `Services/Auth/MauiSessionPersistence.cs` | In-memory cache, 5s timeout |
