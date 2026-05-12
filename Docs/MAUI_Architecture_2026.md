# Daily MAUI App Architecture (2026)

This document provides an exhaustive overview of the architectural patterns, UI constructs, cloud integrations, and cross-platform specific implementations in the Daily MAUI (Multi-platform App UI) application.

## 1. User Interface (UI) Architecture: The Hybrid Approach

The Daily MAUI app employs a strategic **Hybrid Architecture**, combining native MAUI performance with Blazor Web technology for highly complex data visualizations.

### Native MAUI Dashboard
* **Main Window & Widgets**: The core dashboard (Home screen) is built entirely with native MAUI XAML (`MainPage.xaml`). This ensures 60fps scrolling, immediate touch response, and native gesture handling.
* **Component-Based Widgets**: Widgets like `WeatherWidget`, `RssFeedWidget`, and `HabitsWidget` are native MAUI `ContentView`s. They utilize native layouts (`Grid`, `StackLayout`) and native controls to maintain a strict platform-native feel (e.g., using `HorizontalStackLayout` for quick add buttons).

### Blazor Hybrid Detailed Views
* **Complex Data Visualization**: Pages that require advanced charting, heatmaps, or intricate data grids (like the Habits Detail view) are implemented as Blazor Web Components (`HabitsDetail.razor`) hosted inside a native `BlazorWebView`.
* **Why Blazor?**: This allows the application to leverage mature, sophisticated JavaScript and CSS libraries (such as D3.js or ApexCharts for consistency heatmaps) which lack stable, highly customizable native MAUI equivalents.
* **Seamless Interop**: The Blazor components share the exact same C# Dependency Injection container as the native MAUI app. A Blazor component can inject `IHabitsService` and read directly from the local SQLite database without any HTTP overhead.

---

## 2. Shared Domain & Data Persistence

The MAUI application acts as the foundational blueprint for the shared data model, which is 100% interoperable with the WinUI port.

### Offline-First SQLite
* **The Single Source of Truth**: The UI *never* directly queries the cloud. All data bound to the UI (Habit Logs, Widgets, RSS Feeds, Finances) comes exclusively from a local SQLite database (`Daily.db3`).
* **Performance Benefit**: This ensures the app operates instantly, even in airplane mode or under poor network conditions (crucial for a mobile experience).

### Custom Serialization & Platform Separation
* Because a mobile phone requires a vertical, single-column widget layout and a desktop requires a multi-column span, the MAUI app serializes its widget arrangement strictly into the `dashboard_widgets` column of the `UserPreferences` table, leaving `winui_dashboard_widgets` untouched.
* The app forces `Newtonsoft.Json` (camelCase) to serialize `WidgetModel` instances to ensure compatibility with Supabase's REST endpoints, which silently reject PascalCase JSON payloads for JSONB columns.

---

## 3. Cloud Synchronization & Supabase

The MAUI application synchronizes its local state with the Supabase PostgreSQL backend using a dedicated background synchronization engine.

### Bidirectional Sync (`SyncService`)
* **Push**: Every time a user interacts with the app (e.g., taps "Add Water"), the record is saved locally and marked as "dirty" (`SyncedAt = null`). A background task (`PushAsync`) then sweeps the database and upserts these records to Supabase.
* **Pull**: The app uses a `lastPull` timestamp (stored in Preferences) to only download records modified *after* the last successful sync, drastically reducing bandwidth overhead.

### Supabase Realtime via WebSockets
* The MAUI app subscribes to PostgreSQL change streams (`public:habits_logs`, `public:habits_goals`) using Supabase Realtime.
* If the user adds a log on their Windows PC, the Supabase server instantly broadcasts the payload. The MAUI app's active WebSocket connection receives it, commits the change to the local SQLite DB, and triggers a UI re-render event without initiating a full sync cycle.

### Supabase Server-Side RPC
* **Optimized Data Fetching**: Instead of downloading months of raw `habits_logs` data to calculate multi-month consistency or financial savings, the MAUI app relies on Postgres RPC functions (`get_consistency`, `get_smokes_financials`).
* **Execution**: These functions aggregate data directly on the database tier, returning a lightweight JSON payload. This is highly beneficial for mobile devices with constrained CPU and battery resources.

---

## 4. Platform-Specific Nuances (Android)

MAUI requires platform-specific workarounds to maintain stability and comply with OS-level restrictions.

### Background Execution & Foreground Services
* **The Problem**: Android aggressively kills background tasks. The `SystemMonitorService` and `RssFeedService` require continuous execution to update widgets and system status.
* **The Solution**: The app utilizes an Android `ForegroundService` tied to a persistent notification. This elevates the app's priority, preventing the Android OS from terminating the background sync and monitoring loops.

### JNI & Bitmap Lifecycle Management
* **The Problem**: The app previously suffered from `JNI ERROR: Bitmap.compress` crashes after Google Authenticator logins. Android widgets and custom platform image handlers often mismanage the memory lifecycle of native `Bitmap` objects, throwing fatal JNI exceptions when trying to recycle or compress images.
* **The Solution**: Extensive memory protection was implemented. Images used in Android-specific contexts (like system notifications or homescreen widgets) are explicitly cached, and their native `Bitmap` lifecycle is carefully tracked to avoid recycling objects that the Android OS still maintains references to.

---

## 5. Authentication Architecture

### Edge Cases in OAuth
* The app uses `postgrest-csharp` and standard OAuth flows (e.g., Google login).
* **Manual Hydration Override**: Default MAUI secure storage sometimes loses the `ProviderToken` (necessary for downstream Google API calls) when relying solely on the built-in Supabase session restore.
* **The Fix**: The app implements `MauiSessionPersistence.cs` to manually trap the `ProviderToken` during login, explicitly injecting it back into the session via `_supabase.Auth.SetSession(...)` during the `App.xaml.cs` boot sequence. This guarantees that background services (like YouTube API syncs) always have a valid token upon app restart.
