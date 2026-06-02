# Feature: Habits Tracker (Water Logging & Tobacco Management)

The Habits Tracker is designed to help users log their daily habits, track historical consistency, and manage specific health goals. It supports two core habits: **Water Intake** (for hydration logging) and **Smokes** (for tobacco reduction management and financial savings metrics).

---

## 1. Functional Specification

### 1.1 Water Intake Tracker (Hydration)
- **Goal Definition**: Users can define a daily target water intake volume (e.g., 2000 ml or 80 oz).
- **Quick Logging Presets**: Allows logging quick volumes (e.g. 250ml glass, 500ml bottle) with a single click.
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

### 2.3 Background Sync & Session Recovery
- **Automatic Sync Cycle**: The application initiates background synchronization of local habit logs to Supabase every 15 minutes.
- **Proactive Token Refresh**: Prior to pushing or pulling logs in `SyncService`, the service verifies the session validity using `Expired()`. If the lease has expired, it proactively refreshes the JWT token using `RefreshSession()`, allowing the client to self-heal and successfully sync habits data even after long overnight idle periods.

---

## 3. UI/UX & Layout

### 3.1 Custom Progress Painting
- **Water Level Wave Animation**: In WinUI, the `WaterLevelControl.cs` is a custom control that overrides rendering methods. It uses clipping masks, path geometries, and composition animations to draw a moving wave that rises as the user adds water logs.
- **Habit Grid & Logs**: Shows a historical timeline list of logs for the current day, allowing users to remove accidental inputs.

---

## 4. Platform Implementation Differences (WinUI vs. MAUI / Blazor Hybrid)

| Characteristic | WinUI Implementation | MAUI / Blazor Hybrid Implementation |
| :--- | :--- | :--- |
| **UI Technology** | Native XAML Controls (`HabitsWidgetControl.xaml` & `HabitsDetailPage.xaml`) with standardized `FontSize="20"` header icons for dashboard weight consistency | Blazor Hybrid Razor components (`HabitsWidget.razor` & `HabitsDetail.razor`) |
| **Progress Graphic** | Custom drawing class `WaterLevelControl.cs` using Composition/Path geometries | MudBlazor progress gauges, circular progress bars, and CSS transitions |
| **Navigation** | Swaps between "water" and "smokes" views via Pivot menus or buttons | Updates `CurrentViewType` inside `DetailPane` to dynamically swap components |

---

## 5. Smart Briefing Integration & Cache Invalidation

Habit tracking telemetry is integrated directly into the **Local Smart Briefing** narrative. To optimize system resource usage and NPU/CPU cycles, the briefing is cached locally. However, updates in habit logs trigger an automatic cache invalidation and regeneration under the following conditions:

* **Habit Completion Status Change**: If the total count of completed habits (`HabitsCompleted`) changes (e.g. crossing your daily water target or exceeding your daily smokes baseline limit).
* **Significant Progress Delta (10% Threshold)**: Even if the completion status doesn't change, the briefing cache will be invalidated if:
  * **Water Intake (Bubbles)**: Progress *increases* by **10% or more** of the target goal relative to the last cached value (e.g. going from $400\text{ ml}$ to $\ge 600\text{ ml}$ under a $2000\text{ ml}$ goal).
  * **Smokes (Tobacco)**: Progress *increases* by **10% or more** of the daily baseline limit relative to the last cached value (e.g. going from $11$ smokes to $\ge 15$ smokes under a $40$ daily baseline).
