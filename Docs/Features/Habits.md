# Feature: Habits Tracker (Water Logging & Tobacco Management)

The Habits Tracker is designed to help users log their daily habits, track historical consistency, and manage specific health goals. It supports two core habits: **Water Intake** (for hydration logging) and **Smokes** (for tobacco reduction management and financial savings metrics).

---

## 1. Functional Specification

### 1.1 Water Intake Tracker (Hydration)
- **Goal Definition**: Users can define a daily target water intake volume (e.g., 2000 ml or 80 oz).
- **Quick Logging Presets**: Allows logging quick volumes: "Small Water" (150 ml, styled with empty bubble icon `\xea97`) and "Large Water" (300 ml, styled with droplets icon `\xfc12`), as well as presets for coffee, tea, beer, and wine.
- **Dynamic Wave Progress**: Visually reflects the current percentage of the goal achieved using a liquid wave animation representing water levels.

### 1.2 Smokes Tracker (Tobacco Reduction)
- **Tobacco Intake Management**: Unlike quit-smoking clones, this feature helps users gradually lower and manage their tobacco intake relative to a baseline.
- **Personalized Configuration**: Saves baseline settings per user:
  - *Quit Start Date*: The day the user begins tracking/limiting intake.
  - *Baseline (Cigs/Day)*: Historical smoking count.
  - *Cigs in Pack*: Quantity per pack (to determine individual cigarette cost).
  - *Cost per Pack*: Monetary price.
  - *Currency*: User's currency symbol.
- **Financial & Health Statistics**: Compares current consumption to the baseline to show:
  - *Money Saved*: Calculated by multiplying cost-per-cigarette by cigarettes avoided relative to the baseline.
  - *Cigarettes Avoided*: Baseline count minus logged smokes.
  - *Days Tracked*: Number of active tracking days since the Quit Start date.
- **Logging Timeline**: Users tap a button to record each cigarette smoked, stamping the date and time.

---

## 2. Technical Architecture & Data Model

### 2.1 Services & Dependency Injection
- `IHabitsService` / `HabitsService`: The primary controller for logging habits, retrieving historical consistency, and calculating smokes statistics.
- `IHabitsRepository` / `HabitsRepository`: Coordinates local SQLite data access.
- `ISyncService` / `SyncService`: Performs background sync operations between SQLite and the Supabase database.

### 2.2 Data Models & Schema
The SQLite database stores logs locally and synchronizes them with Supabase when online.

#### SQLite Local Tables (`Models/LocalModels.cs`)
- **`LocalHabitGoal`** (Mapped to Supabase `habits_goals` table):
  - `Id` (String Primary Key)
  - `UserId` (String)
  - `HabitType` (String: `"water"` or `"smokes"`)
  - `TargetValue` (Double)
  - `Unit` (String)
  - `CreatedAt` / `UpdatedAt` / `SyncedAt` (DateTime)
  - `IsDeleted` (Boolean)
- **`LocalHabitLog`** (Mapped to Supabase `habits_logs` table):
  - `Id` (String Primary Key)
  - `UserId` (String)
  - `HabitType` (String)
  - `Value` (Double)
  - `Unit` (String)
  - `LoggedAt` (DateTime)
  - `Metadata` (String: JSON object containing contextual logs)
  - `CreatedAt` / `UpdatedAt` / `SyncedAt` (DateTime)
  - `IsDeleted` (Boolean)

#### Server-Side Aggregation Functions (Supabase RPCs)
- **`GetConsistencyAsync(habitType, startDate, endDate)`**: Queries the server for daily aggregated totals over a date range. It falls back to local SQLite grouping queries if offline.
- **`GetSmokesFinancialsAsync(sinceDate)`**: Executes a database RPC function to calculate total smokes and days tracked since the tracking date. Falls back to local counting queries if offline.

### 2.3 Daily Breakdown Metadata Parsing
To present a segmented radial gauge and detailed lists of logged habits, the application parses the JSON stored in `Metadata` using `JsonDocument.Parse`:
- **Safe Extraction**: If `log.Metadata` is valid JSON, the service reads the `"drink"` key (for water view) or the `"type"` key (for smokes view) to dynamically retrieve the specific item type.
- **Normalization**: Extracted keys are normalized to lowercase (e.g., `"small water"` becomes `"small"`, and `"large water"` becomes `"large"`) for consistent aggregation and color/icon mapping.

### 2.4 Background Sync, Session Recovery & Realtime Update
- **Automatic Sync Cycle**: The application initiates background synchronization of local habit logs to Supabase every 15 minutes.
- **Proactive Token Refresh & Realtime Re-auth**: Prior to pushing or pulling logs in `SyncService`, the service verifies the session validity using `Expired()`. If the lease has expired, it proactively refreshes the JWT token using `RefreshSession()`. The service listens to the `TokenRefreshed` auth state to update the Realtime client authentication and force-recreate its channels (`habits_logs` and `habits_goals`), keeping database subscription listeners alive overnight.
- **Graceful Refresh Exception Handlers**: Dashboard refresh clicks run full pushes and pulls. The refresh tasks capture any sync exceptions to ensure the UI successfully updates using the latest local database values even if the backend is temporarily unreachable. App window restoration (`ShowAndActivate()`) automatically initiates background sync catch-ups.

---

## 3. UI/UX & Layout

### 3.1 Custom Progress Painting & Gauge Segments
- **Water Level Wave Animation**: In WinUI, the `WaterLevelControl.cs` is a custom control that overrides rendering methods. It uses clipping masks, path geometries, and composition animations to draw a moving wave that rises as the user adds water logs.
- **Segmented Radial Arc**: Displays different drink/smoke type contributions as colored segments on a single Syncfusion radial axis. A background range (grey, 10% opacity) is drawn from `0` to the target goal, and custom ranges are appended sequentially (`currentStart` to `currentStart + value`) based on the daily breakdown.
- **Habit Grid & Logs**: Shows a historical timeline list of logs for the current day, allowing users to remove accidental inputs.

### 3.2 Dynamic Visual Layout States (WinUI)
The `HabitsWidgetControl` uses a custom `SizeChanged` and `DataContext` listener to switch visual states dynamically:
- **`SmallState` (1x1)**:
  - Scaled down radial gauge (150x150 width/height).
  - Compact text list using `DetailedListCompactTemplate` displaying only amounts and icons.
  - Dynamically scaled internal margins (from 8px on narrow screens up to 16px).
  - Collapses external history charts and statistics.
- **`TallState` (1x2)**:
  - Radial gauge scaled to 220x220.
  - Layout is rearranged vertically to stack the gauge and action panels.
- **`NormalState` (Wide, 2x1)**:
  - Radial gauge scaled to 150x150.
  - Displays the history chart and logs side-by-side on the right of the gauge.
  - **Dynamic Interpolation**: If width $\ge 660\text{px}$, it dynamically increases internal padding, margins, and column sizes using linear interpolation, while showing the logs list. If width $< 660\text{px}$, it hides the logs list to prevent overlapping.
- **`LargeState` (2x2)**:
  - Radial gauge scaled to 220x220.
  - Side-by-side grid columns: left column holds the gauge and quick actions vertically, right column shows the history chart, stats, and logs list.

### 3.3 Scroll-Wheel Navigation & Custom Controls
- **Cycle Swipe via Scroll Wheel**: The widget listens to the `PointerWheelChanged` event. Scrolling the mouse wheel over the widget area cycles the view between "Bubbles" (Water) and "Smokes" views automatically with wrap-around index logic. It flags the event as handled (`e.Handled = true`) to prevent nested layout scroll interference.
- **Hidden System Navigation**: To preserve a premium glass aesthetic, the default system FlipView navigation buttons (e.g. `PreviousButtonHorizontal`) are hidden dynamically during initialization by traversing the visual tree using a helper function `FindVisualChildByName`. Custom header navigation buttons are used instead.

---

## 4. Platform Implementation Differences (WinUI vs. MAUI / Blazor Hybrid)

| Characteristic | WinUI Implementation | MAUI / Blazor Hybrid Implementation |
| :--- | :--- | :--- |
| **UI Technology** | Native XAML Controls (`HabitsWidgetControl.xaml` & `HabitsDetailPage.xaml`) with standardized `FontSize="20"` header icons for dashboard weight consistency | Blazor Hybrid Razor components (`HabitsWidget.razor` & `HabitsDetail.razor`) |
| **Progress Graphic** | Custom drawing class `WaterLevelControl.cs` using Composition/Path geometries, and segmented radial `GaugeRange` arcs | MudBlazor progress gauges, circular progress bars, and CSS transitions |
| **Navigation** | Cycles through views via FlipView, custom header arrows, or scroll-wheel events. Detail page uses pivot selectors. | Updates `CurrentViewType` inside `DetailPane` to dynamically swap components |
| **Quick Actions & Presets** | Small Water (empty bubble icon `\xea97`), Large Water (droplets `\xfc12`), Coffee (`\xef0e`), Tea (`\xf552`), Beer (`\xefa1`), Wine (`\xeab7`). Smokes: Cigarette (`\xecc4`), Heated (`\xec2c`), Rolled (`\xec2b`), Cigarillo (`\xeed2`). | MudBlazor preset logging buttons |

---

## 5. Smart Briefing Integration & Cache Invalidation

Habit tracking telemetry is integrated directly into the **Local Smart Briefing** narrative. To optimize system resource usage and NPU/CPU cycles, the briefing is cached locally. However, updates in habit logs trigger an automatic cache invalidation and regeneration under the following conditions:

* **Habit Completion Status Change**: If the total count of completed habits (`HabitsCompleted`) changes (e.g. crossing your daily water target or exceeding your daily smokes baseline limit).
* **Significant Progress Delta (10% Threshold)**: Even if the completion status doesn't change, the briefing cache will be invalidated if:
  * **Water Intake (Bubbles)**: Progress *increases* by **10% or more** of the target goal relative to the last cached value (e.g. going from $400\text{ ml}$ to $\ge 600\text{ ml}$ under a $2000\text{ ml}$ goal).
  * **Smokes (Tobacco)**: Progress *increases* by **10% or more** of the daily baseline limit relative to the last cached value (e.g. going from $11$ smokes to $\ge 15$ smokes under a $40$ daily baseline).
