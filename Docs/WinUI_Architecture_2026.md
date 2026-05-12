# Daily WinUI 3 App Architecture (2026)

This document outlines the architectural patterns, UI constructs, and data synchronization mechanisms implemented in the Daily WinUI 3 application. It specifically details how the WinUI desktop experience interfaces with the existing cross-platform MAUI codebase, local SQLite databases, and the Supabase cloud backend.

## 1. User Interface (UI) Architecture

The WinUI dashboard has been transitioned from a static grid layout into a fully dynamic, user-customizable workspace.

### Dynamic Dashboard Grid
* **`DashboardGridView`**: We built a custom subclass of the native `GridView` to explicitly manage container realization. Because the WinUI `VariableSizedWrapGrid` is notoriously buggy and often drops attached span properties during layout passes and drag-and-drop virtualization, the custom `DashboardGridView` injects the `ColumnSpan` and `RowSpan` directly into the `GridViewItem` container. To mathematically guarantee the layout persists, we hook into the container's `Loaded` event to forcibly re-apply these bounds after the visual tree is finalized.
* **VariableSizedWrapGrid**: Acts as the `ItemsPanel` for the dashboard. To achieve a pixel-perfect, edge-to-edge 2-column layout without trailing margins, the grid automatically calculates its cell size using `Math.Floor(WidgetGridView.ActualWidth / 2)` in the `SizeChanged` event.
* **Custom Drag-and-Drop**: Native `GridView` reordering is disabled because it conflicts with custom column spanning. Instead, we manually handle `DragItemsStarting`, `DragOver`, and `Drop`. The target drop location is determined using physical bounds hit-testing. The layout updates by explicitly removing and inserting the `WidgetModel` instances within the `ObservableCollection`, which triggers the UI to visually displace other widgets.

### Widget Interactivity
* **Nested Control Conflicts**: A common WinUI issue occurs when a `GridView` has `CanDragItems="True"`, as the outer container captures pointer events, suppressing inner list behaviors (like `ItemClick` in the RSS Feed widget).
* **Bypass Strategy**: We solved this by removing native `ItemClick` dependencies entirely. Instead, a direct `Tapped` event handler is placed on the inner `DataTemplate` (e.g., the Article card). By explicitly setting `e.Handled = true` in the code-behind, the click is intercepted and executed before the draggable parent container can swallow it.

---

## 2. Shared Domain & Data Persistence

The WinUI application shares a significant portion of its core business logic, domain models, and database services with the original MAUI application.

### `WidgetModel` & Layout Separation
* Both MAUI and WinUI use the same `WidgetModel` class to define their dashboard items (`Title`, `ComponentType`, `ColumnSpan`, `RowSpan`, `Parameters`).
* **Platform Segregation**: Because a desktop layout (WinUI) requires fundamentally different widget spans and ordering than a mobile screen (MAUI), the `UserPreferences` schema has two distinct columns: `dashboard_widgets` (MAUI) and `winui_dashboard_widgets` (WinUI). 

### Serialization Consistency
* Supabase's REST API (`postgrest-csharp`) uses `Newtonsoft.Json` under the hood, which defaults to converting property names into `camelCase`.
* We enforce the use of `Newtonsoft.Json` in the `WinUIWidgetService` to serialize and deserialize the layout strings. This prevents silent failures where `System.Text.Json` (which expects PascalCase) would ignore `columnSpan` and `rowSpan` properties pulled from the database, preventing widgets from resetting to a default 1x1 size upon app restart.

---

## 3. Boot Sequence & Race Conditions

A critical architectural change was made to the boot sequence in `App.xaml.cs` to prevent silent data overwrites.

### Synchronous Hydration
* **The Problem**: Previously, `SettingsService` initialized the SQLite database in a background thread. Because the UI boots instantly, the `MainPage` would request the widget layout before the database finished loading, receiving `null`. The UI would then render the default widget layout. If the user interacted with a widget, the app would save this default layout back to the database, erasing all their saved customizations.
* **The Solution**: The WinUI `App.xaml.cs` explicitly `awaits` the `SettingsService.InitializeAsync()` pipeline. The main window is physically blocked from requesting the widget layout until the SQLite preferences are 100% hydrated into memory.

---

## 4. Supabase Sync Engine & Conflict Resolution

The application relies on an offline-first SQLite database that syncs in the background to Supabase. This provides instantaneous UI interactions without waiting for network requests.

### Clock Skew Tolerance
* **The Problem**: When pushing local changes to Supabase, the Supabase PostgreSQL triggers stamp the row with the exact `updated_at` time of the cloud server. If the user's local Windows PC clock is drifting even a few seconds behind the server's time, the local PC would stamp the next save with an "older" time than the server's previous save. The `SyncService` conflict resolver would mistakenly think the local edit was outdated, reject the push, and pull down the old layout.
* **The Solution**: The `SyncService.PushPreferencesAsync` conflict resolver includes a generous 60-second clock skew tolerance (`localTime.AddSeconds(60)`). This ensures that rapid local UI saves are correctly prioritized over slightly misaligned server timestamps.

### Supabase Realtime
* The application leverages Supabase Realtime via the `_supabase.Auth.AddStateChangedListener` and specific Postgres change listeners in `SettingsService`.
* When an update occurs on another device (e.g., another WinUI desktop), Supabase broadcasts the row change.
* `SettingsService.OnPreferencesReceived` intercepts this payload, writes it to the local SQLite database, and silently updates `_currentSettings`. While the UI does not aggressively redraw automatically (to prevent disrupting the user), the new layout is securely cached and will be applied on the next app launch or page refresh.
