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

---

## 5. XAML Compiler Stability & UI Components

A key challenge during the WinUI port was ensuring compile-time and runtime stability for complex layouts.

### Avoiding MSB3073 & Complex Layout Crashes
* **The Problem**: Nesting complex third-party visual controls (like Syncfusion Gauges and Charts) deep within WinUI 3 `DataTemplate` and `FlipView` hierarchies frequently caused `MSB3073` XamlCompiler errors in .NET 10.
* **The Solution**: The UI was systematically refactored to prioritize **Native WinUI Controls** (e.g., `ProgressRing`, `Expander`, `GridView`) for all core layouts. Third-party controls are now strictly isolated within their own lightweight `UserControl` wrappers when necessary, preventing the XamlCompiler from failing during the markup generation phase.

### Two-Way Binding Parse Exceptions
* **The Problem**: WinUI 3's `{Binding}` engine heavily relies on strict type matching. Binding `int` or `double` data models directly to a `TextBox.Text` property using `Mode=TwoWay` without a custom type converter causes a silent `XamlParseException` during `InitializeComponent()`, instantly aborting page navigation.
* **The Solution**: The architecture mandates the use of the native `NumberBox` control (`Microsoft.UI.Xaml.Controls.NumberBox`) for all numeric inputs. Because `NumberBox.Value` explicitly accepts `double` types, it safely handles two-way bindings to numeric models without triggering reflection/parse crashes.

---

## 6. Server-Side RPC Aggregation

To optimize performance and reduce local processing overhead, the application minimizes expensive local SQLite aggregations in favor of Supabase server-side RPCs (Remote Procedure Calls).

### Optimized Financial & Consistency Calculations
* Rather than downloading the entire `habits_logs` dataset to compute multi-month consistency heatmaps or financial savings, the WinUI app leverages optimized Postgres functions (e.g., `get_smokes_financials` and `get_consistency`).
* **Accurate Elapsed Time tracking**: Calculations dynamically calculate the duration (like "Days Since Quit") server-side using Postgres `CURRENT_DATE - p_since_date::date` instead of simply counting the distinct number of logged days. This ensures that financial totals (Money Saved, Cigarettes Avoided) accurately reflect real-world time elapsed regardless of the user's daily logging frequency.
* **Client-Side Caching**: The results of these RPC calls are aggressively cached in-memory on the client to prevent excessive network requests when repeatedly navigating between widget details.

---

## 7. Windows Shell Customization, Docking & Shell State Settings

We implemented a custom, premium windows layout control system to support flexible desktop workspaces.

### 7.1 Adaptive Title Bar & Avatar State
* **Narrow Sizing Collapse (`AppTitleBar_SizeChanged`)**: When the window is resized below `640` logical pixels, space in the custom title bar becomes extremely constrained. The system hooks into `SizeChanged` and collapses the `TitleBarDateText` (the calendar date) and `TitleBarUserEmailText` (the username string next to the avatar), leaving only the account picture visible. They automatically restore to visible when the window is widened.
* **Auth State Profile Hydration**: On launch, authentication session hydration runs asynchronously in the background. To prevent a timing race where the avatar fails to load because the session wasn't active when the page loaded, the `MainPage` registers an auth state changed listener to re-trigger `UpdateUserUI` on the UI thread when hydration completes.
* **Robust Image Resolvers**: Accounts authenticated via Google OAuth store their profile pictures under the JSON property `picture`, while standard Supabase accounts use `avatar_url`. The `WinUIAuthService` parses both keys in the user metadata to ensure the avatar loads correctly.

### 7.2 DPI-Aware Docking & DWM Border Compensations
* **Multi-Mode Docking Dropdown**: A dropdown button (`TitleBarDockButton` with Glyph `\uE952`) was added to the title bar, allowing the user to select between:
  1. **Float Center (Default)**: Horizontal centering at the bottom of the active screen (`1380×790` scaled pixels).
  2. **Dock Left / Right**: Fixed sidebar mode (`480` scaled pixels) stretching to fill the vertical display height.
* **DWM Extended Frame Bounds Compensation**: Windows 10/11 windows have invisible resize borders (typically 7–8 physical pixels on the left, right, and bottom). Directly passing screen coordinates to `AppWindow.MoveAndResize` causes docked windows to offset slightly off-screen (on the right) and overlap the taskbar (at the bottom). We resolved this by querying the window's true visible region using the Win32 API `DwmGetWindowAttribute` with the `DWMWA_EXTENDED_FRAME_BOUNDS` attribute. The system calculates these margins dynamically:
  - `outerX = targetX - margins.left`
  - `outerY = targetY - margins.top`
  - `outerWidth = targetWidth + margins.left + margins.right`
  - `outerHeight = targetHeight + margins.top + margins.bottom`
* **Clamp Enforcement Bypass**: To prevent the OS/SDK window manager from overriding the docking size and pushing the window bounds back over the taskbar, we reduced the minimum window size enforcement in `AppWindow_Changed` from `500` to `400` logical pixels.

### 7.3 Settings Service Caching & Tray Persistence
* **Overwritten State Bug**: Previously, separate window/page instances (e.g. `MainWindow`, `SettingsWindow`, `GeneralSettingsPage`) created their own instances of `AppSettings` on startup. If a user updated a setting in `GeneralSettingsPage` (like turning on "Close to tray"), it was saved to the JSON file. However, when the user subsequently closed `MainWindow`, the `MainWindow`'s local settings instance (which was instantiated at startup and still had the old `false` value) wrote to disk, overwriting the user's change.
* **Singleton State Caching**: We resolved this by implementing a thread-safe, in-memory caching singleton in `SettingsService.cs`. All pages and dialogs load and reference the exact same settings instance. Any changes reflect globally in real-time, preventing state overwrites on window closing.

### 7.4 Standardized Widget Headers
* **Visual Weight Uniformity**: The dashboard widgets utilize native vector `FontIcon` elements. To ensure equal visual weight, header icons were standardized across widgets (Vitals, News, Habits, Finances) to a uniform `FontSize="20"`, correcting the visually smaller footprint of the Finances and Habits glyphs.

