# Daily App: Supabase Architecture & WinUI Porting Guide (2026)

This document outlines the current state of the Daily App's cloud architecture, specifically focusing on the Supabase integration, local-first synchronization strategy, real-time capabilities, and edge functions. 

It also serves as a comprehensive porting guide for bringing this logic into the native `Daily.WinUI` application.

## 1. High-Level Architecture: Local-First Strategy
The app employs a **Local-First Architecture**. 
* **Source of Truth for the UI:** The local SQLite database (`Daily.db3`). The UI *never* directly reads from Supabase to render lists (Habits, Goals, RSS Feeds, Finances). It only reads from SQLite.
* **Source of Truth for the Cloud:** Supabase PostgreSQL.
* **The Bridge:** `SyncService.cs` acts as the bidirectional bridge between SQLite and Supabase.

When a user performs an action (e.g., logging a habit), the app:
1. Instantly saves the data to the local SQLite database.
2. Marks the record as "dirty" (`SyncedAt = null`).
3. Fires an asynchronous, background call to `SyncService.PushAsync()`.
4. If offline, the data remains dirty in SQLite until the next background sync cycle.

## 2. Authentication & Session Hydration
The authentication flow is critical for maintaining cross-session persistence, especially given issues with default token caches losing custom provider tokens (like YouTube OAuth tokens).

* **Manual Hydration:** Inside `App.xaml.cs`, the app explicitly checks if the Supabase `CurrentSession` is null at startup. If it is, it uses `MauiSessionPersistence.cs` to manually load the `AccessToken`, `RefreshToken`, and (crucially) the `ProviderToken`.
* **The `SetSession` Call:** It calls `await _supabase.Auth.SetSession(...)` to inject the session into the Supabase client.
* **The Event Trigger:** Calling `SetSession` triggers the `AuthStateChanged` event with the `SignedIn` state. This event is what kicks off the startup migrations and data synchronization.

## 3. Data Synchronization (`SyncService.cs`)
The `SyncService` is responsible for keeping the local SQLite DB aligned with Supabase. 

### Push Mechanics (`PushAsync`)
* Queries all local tables for records where `SyncedAt == null`.
* Maps local models (e.g., `LocalHabitLog`) to remote models (`HabitLog`).
* Upserts the records to Supabase.
* On success, updates the local records, setting `SyncedAt = DateTime.UtcNow`.

### Pull Mechanics (`PullAsync`)
* Relies on a `lastPull` timestamp stored in `Preferences`.
* **Important Fix:** If `lastPull` is `DateTime.MinValue` (first sync), it pulls *all* history starting from the year 2000. If `lastPull` exists, it only pulls records created/updated *after* that timestamp. (Note: A safety buffer of 14 days is applied for `habits_logs` to catch offline entries from other platforms that might not have correctly updated timestamps).
* Upserts pulled data into the local SQLite database.

## 4. Supabase Realtime
To provide instantaneous cross-device updates (e.g., logging water on a phone and seeing it immediately on the desktop), the app uses Supabase Realtime WebSockets.

* **Channels:** The app subscribes to `public:habits_logs` and `public:habits_goals`.
* **Filtering:** The real-time events are received for *all* changes, but the app explicitly filters them locally checking if `remoteLog.UserId == CurrentUserId`. Note: RLS (Row Level Security) restricts what the server broadcasts, but the local check is an additional safety measure.
* **Action:** When a real-time event fires, the app saves the new log directly to SQLite and invokes `OnHabitsUpdated`, causing the UI to re-render without a full sync cycle.

## 5. Supabase Edge Functions
To bypass strict CORS requirements, hide API keys, and centralize external data fetching, the app utilizes Supabase Edge Functions.

* **Function:** `fetch-market-quotes`
* **Purpose:** Fetches live financial data (e.g., from Yahoo Finance or Finnhub) and returns a unified JSON payload.
* **Authentication:** The Edge Function requires the user's JWT. `FinancesService.cs` attaches the user's session token to the HTTP request.
* **Benefit:** The API keys for the financial providers are stored securely as secrets inside the Supabase project, not hardcoded in the client app.

---

## 6. Technical Debt: Addressing the RSS Initialization Question
Currently, the RSS Feeds seeding and initialization (`SeedRssFeedsAsync` / `InitializeCustomFeedsAsync`) are located directly inside `HabitsService.cs` (specifically in its `InitializeAsync` method). 

**Why is it there?** 
During rapid migration, `HabitsService` was acting as our *de-facto* "Startup Bootstrapper". It was already instantiated early, guaranteed to run, and hooked into the `AuthStateChanged` listeners. It was simply the most convenient place to attach the RSS initialization logic to guarantee it ran when a user logged in.

**Future Refactoring Needed:** 
This is a violation of separation of concerns. In the future, this logic should be abstracted into a dedicated `AppStartupService` or `MigrationManager`. This manager should orchestrate the initialization of *all* modules (Habits, Finances, RSS, Preferences) independently, without cross-contaminating service domains.

---

## 7. Porting Guide for WinUI (`Daily.WinUI`)

To port this new Supabase-powered logic into the native WinUI application, follow these steps:

### A. Database Initialization Alignment
1. **SQLite Configuration:** Ensure the WinUI `DatabaseService` mirrors the MAUI version. Specifically, the connection *must* use standard `Ticks` for `DateTime` parsing (i.e., do NOT set `storeDateTimeAsTicks: false`).
2. **Table Creation:** Ensure `LocalRssSubscription` (and all other new tables) are explicitly created via `_connection.CreateTableAsync<...>()` during database initialization.

### B. Shared Services Integration
1. **SyncService & SeederService:** The WinUI app needs to instantiate and utilize the exact same `SyncService.cs` and `SeederService.cs`. 
2. **HabitsRepository Fixes:** Ensure the WinUI `HabitsRepository` uses standard `||` operators instead of array `.Contains()` when filtering by User ID to prevent `NotSupportedException` crashes in `sqlite-net-pcl`.

### C. Authentication Flow
1. **Implement Manual Hydration:** Mirror the `App.xaml.cs` manual hydration logic in WinUI's startup (e.g., `App.xaml.cs` or `MainWindow.xaml.cs`). It must manually load the `MauiSessionPersistence` tokens and call `SetSession`.
2. **Startup Trigger:** Ensure that `InitializeCustomFeedsAsync` and `SyncAsync` are explicitly called after the session is established. Do not rely solely on the `AuthStateChanged` event if auto-hydration bypasses it.

### D. Finances Integration (Edge Functions)
1. **Refactor `FinancesService.cs`:** The current WinUI implementation likely makes direct HTTP calls to Yahoo/Finnhub. 
2. **Switch to Supabase Functions:** Update `FinancesService` to use `_supabase.Functions.Invoke("fetch-market-quotes", ...)` instead, passing the necessary body payloads. Ensure the user's JWT token is correctly attached (handled automatically by the Supabase C# Client if authenticated).
