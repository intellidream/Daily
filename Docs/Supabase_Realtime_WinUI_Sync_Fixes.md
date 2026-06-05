# Supabase Realtime WinUI 3 Sync Fixes (June 2026)

This document details the investigation, proposals, and final implemented changes to fix the Supabase Realtime synchronization issues in the WinUI 3 desktop application.

---

## 1. Problem Statement

The WinUI 3 desktop variant of the Daily app would lose Supabase Realtime connection and subscription functionality (such as Health updates and Habits updates) after running in the background for a while. However:
1. The MAUI application (sharing the same code base) did not lose sync.
2. Clicking the **DayOne/Refresh** button in the WinUI title bar temporarily restored data flow.

---

## 2. Root Cause Analysis

We identified three distinct root causes that caused the connection to drop out silently:

### A. Garbage Collection of Weakly Referenced Event Listeners
The Supabase C# SDK (`gotrue-csharp` and `realtime-csharp`) stores authentication state listeners and Realtime socket state handlers as weak references (`WeakReference<T>`).
In the shared services (`HabitsService.cs`, `SupabaseHealthService.cs`, and `SettingsService.cs`), the event listeners were registered using anonymous inline lambda expressions:

```csharp
_supabase.Auth.AddStateChangedListener((sender, state) => { ... });
```

Since the application did not hold any strong references to these delegate instances, the .NET Garbage Collector reclaimed them during the next GC cycle. Once collected, the services stopped receiving `TokenRefreshed` and `SocketState.Open` events, leaving the connection in an unauthenticated or disconnected state.

### B. Missing Central Auth Token Propagation in WinUI
Unlike the MAUI project (which registers a central listener in `MauiProgram.cs` to instantly propagate refreshed access tokens to the Realtime client), the WinUI application had no central mechanism to propagate token updates. When service-level listeners were garbage collected, the Realtime client continued using the expired token, resulting in the server dropping the connection after 1 hour.

### C. Missing Network Connectivity and Sleep/Resume Handlers
In the MAUI version, the network change handler (`ConnectivityChanged`) and lifecycle hooks automatically reconnect the socket on network changes or app wake up. In the WinUI codebase, these were compiled out via `#if !WINUI_NATIVE` with no Windows-native replacement. When the PC went to sleep or changed networks, the socket stayed disconnected permanently.

### D. Why the Title Bar Refresh Healed It
Clicking the refresh button invoked `SyncService.SyncAsync()`, which evaluates token expiration via `auth.CurrentSession.Expired()` and calls `await auth.RefreshSession()`. This proactively obtained a fresh token and fetched data over HTTPS REST. It also triggered a new GoTrue token refresh cycle, temporarily re-authorizing the connection.

---

## 3. Implemented Fixes

The following architectural and service changes were implemented:

### 1. Central Auth and Network Listeners in WinUI App
* **File**: [App.xaml.cs](file:///c:/Users/mihai/source/repos/Daily/WinUI/Daily.WinUI/App.xaml.cs)
* **Changes**:
  * Added a private `_centralAuthListener` delegate field to prevent GC.
  * Registered it in `ConfigureServices` to immediately push refreshed access tokens to the Realtime client:
    ```csharp
    _centralAuthListener = (sender, state) =>
    {
        if (state == Supabase.Gotrue.Constants.AuthState.SignedIn || 
            state == Supabase.Gotrue.Constants.AuthState.TokenRefreshed)
        {
            var session = SupabaseClient.Auth.CurrentSession;
            if (session != null && !string.IsNullOrEmpty(session.AccessToken))
            {
                SupabaseClient.Realtime.SetAuth(session.AccessToken);
            }
        }
    };
    ```
  * Subscribed to the native Windows `NetworkInformation.NetworkStatusChanged` event inside `OnLaunched`. When internet connection is restored, it verifies the session expiration, reconnects the Realtime client, and triggers background sync pulls.

### 2. Delegate Reference Preservation (GC Protection)
* **Files**: [SettingsService.cs](file:///c:/Users/mihai/source/repos/Daily/Services/SettingsService.cs), [HabitsService.cs](file:///c:/Users/mihai/source/repos/Daily/Services/HabitsService.cs), [SupabaseHealthService.cs](file:///c:/Users/mihai/source/repos/Daily/Services/Health/SupabaseHealthService.cs)
* **Changes**:
  * Added private delegate fields in all three services to store the handlers:
    ```csharp
    private Supabase.Gotrue.Interfaces.IGotrueClient<Supabase.Gotrue.User, Supabase.Gotrue.Session>.AuthEventHandler? _authStateChangedHandler;
    private Supabase.Realtime.Interfaces.IRealtimeClient<Supabase.Realtime.RealtimeSocket, Supabase.Realtime.RealtimeChannel>.SocketStateEventHandler? _realtimeStateChangedHandler;
    ```
  * Assigned the lambda delegates to these fields in the constructor prior to registering them with `AddStateChangedListener` / `AddStateChangedHandler`. This holds a strong reference to the delegates, protecting them from garbage collection.

### 3. Redundant Channel Re-creation Avoidance
* **Files**: [HabitsService.cs](file:///c:/Users/mihai/source/repos/Daily/Services/HabitsService.cs), [SupabaseHealthService.cs](file:///c:/Users/mihai/source/repos/Daily/Services/Health/SupabaseHealthService.cs)
* **Changes**:
  * Optimized `InitializeAsync` and constructor auth handlers to ignore the `TokenRefreshed` event.
  * Since the central auth listener propagates the fresh token automatically on the existing open connection, the services no longer need to unsubscribe and recreate the channels on token rotation, preventing race conditions and resource overhead.
  * Ensured `SetupRealtimeAsync` is called when not authenticated in `HabitsService` to cleanly unsubscribe and nullify channels.

---

## 4. Verification

We verified the changes by:
1. **Compilation**: Built the `Daily.WinUI` project using `dotnet build WinUI\Daily.WinUI\Daily.WinUI.csproj` to guarantee all generic delegates compile correctly without errors.
2. **Behavioral Integrity**: Ensured the shared service changes did not break MAUI app compilation.
