# iOS Native Widgets (WidgetKit & AppIntents)

## 1. Overview
Daily provides native iOS Home Screen and Lock Screen widgets powered by Apple's **WidgetKit** framework and iOS 17+ interactive **App Intents**. The widgets deliver an ultra-dense, visual aesthetic inspired by modern health telemetry dashboards like StressWatch, while preserving Daily's dark Liquid Glass styling.

## 2. Widgets Included

### A. Bubbles Widget (Hydration & Drinks)
- **Supported Families**:
  - Home Screen: Small (1x1), Medium (2x1), Large (2x2)
  - Lock Screen: Accessory Circular, Accessory Inline
- **Visuals**:
  - Gradient ring gauge (`#00E5FF` Cyan to `#00E676` Green) tracking daily ml intake against the user's custom daily water goal.
  - Telemetry breakdown showing total water volume (`ml`) and coffee volume (`ml ☕`).
- **Interactive Quick-Logging**:
  - Zero-app-open instant logging via `LogWaterIntent`:
    - **`+150 ml`** (Water)
    - **`+300 ml`** (Water)
    - **`+100 ml`** (Coffee ☕)
  - Updates local App Group aggregates in 0ms and triggers timeline reload via `WidgetCenter`.

---

### B. Smokes Widget (Tobacco & Cessation Tracking)
- **Supported Families**:
  - Home Screen: Small (1x1), Medium (2x1), Large (2x2)
  - Lock Screen: Accessory Circular, Accessory Inline
- **Visuals**:
  - Custom vector anatomical lungs silhouette (`WidgetLungsShape`) centered within a dynamic color ring.
  - Adaptive color states:
    - **Clean Green (`#00E676`)**: 0 smokes logged today.
    - **Progress Cyan (`#00E5FF`)**: Smokes logged below daily baseline cap.
    - **Warning Pink (`#FF2D55`)**: Smokes logged exceeding baseline limit.
  - Telemetry: Current count, time elapsed since last logged smoke (e.g. `2h 15m ago`), daily financial expenditure estimation in Lei, and cigarettes vs. heated tobacco breakdown.
- **Interactive Quick-Logging**:
  - Zero-app-open instant logging via `LogSmokeIntent`:
    - **`+1 Cig 🚬`** (Cigarette)
    - **`+1 Heat 💨`** (Heated Tobacco)
  - *Abstinence logging is explicitly excluded to keep tracking focused, streamlined, and friction-free.*

---

### C. Money Widget (SmartLedger & Personal Finances)
- **Supported Families**:
  - Home Screen: Small (1x1), Medium (2x1), Large (2x2)
  - Lock Screen: Accessory Rectangular
- **Visuals**:
  - Prominent Net Worth in Lei with currency conversion badge in EUR (live sync with BNR rates).
  - Three-column financial overview:
    - **Net Worth**: Total accumulated wealth.
    - **Flow**: Monthly Incoming vs Outgoing totals.
    - **Liquid**: Available card and cash liquidity breakdown (`Crd` & `Csh`).
  - Large widget includes ranked capsules of the top outgoing budget allocations.
- **Interactive Quick Adjustments**:
  - Zero-app-open ledger balance adjustment via `AdjustLedgerIntent`:
    - **`-50 Crd`** (Quick -50 on Card balance)
    - **`-50 Csh`** (Quick -50 on Cash balance)
    - **`+100 Crd`** (Quick +100 on Card balance)
  - Adjusts raw SmartLedger syntax in App Group storage, recalculates balances, and broadcasts widget timeline reload.

---

## 3. Architecture & Data Flow

```
┌────────────────────────────────────────────────────────┐
│                   App Group Storage                    │
│             group.com.intellidream.daily               │
└─────────────────────────┬──────────────────────────────┘
                          │
         ┌────────────────┴────────────────┐
         ▼                                 ▼
┌──────────────────┐              ┌──────────────────┐
│    Daily App     │              │  DailyWidgets    │
│   (Main Target)  │              │ (WidgetKit Ext)  │
└────────┬─────────┘              └────────┬─────────┘
         │                                 │
         │ Updates habits & ledger         │ Reads snapshots
         ▼                                 ▼
┌────────────────────────────────────────────────────────┐
│               WidgetDataCoordinator                    │
│ • fetchBubblesSnapshot()                               │
│ • fetchSmokesSnapshot()                                │
│ • fetchMoneySnapshot()                                 │
│ • logWater(amountMl:drinkType:)                        │
│ • logSmoke(smokeType:)                                 │
│ • adjustLedgerAmount(accountName:delta:)               │
│ • WidgetCenter.shared.reloadAllTimelines()             │
└────────────────────────────────────────────────────────┘
```

1. **Shared Container**: Both `Daily.app` and `DailyWidgetsExtension.appex` share the App Group `group.com.intellidream.daily`.
2. **`WidgetDataCoordinator`**: Central engine located in `DailyCore` that produces instantaneous, synchronous snapshots (`BubblesWidgetSnapshot`, `SmokesWidgetSnapshot`, `MoneyWidgetSnapshot`) from App Group defaults with zero async delays.
3. **Interactive `AppIntent` & Offline Resilience**: Each interactive button runs in the widget extension process, executing mutations via `WidgetDataCoordinator` and notifying `WidgetCenter.shared.reloadAllTimelines()`. Queued changes are persisted in `offline_habits_queue` with the authenticated `user_id` cached from the main app.
4. **Foreground Sync & Non-Destructive Merge**: When the main app enters the foreground (`scenePhase == .active` or `willEnterForegroundNotification`), `HabitsService` immediately reloads the local storage queue, pushes pending widget logs to Supabase, and merges local un-synced logs with remote records by UUID. This guarantees widget values are never overwritten or reverted when the app refreshes remote data.
5. **Small Widget Auto-Scaling**: In `MoneyWidget` small size, the header `"Money"` label is prioritized with `.fixedSize()` and `.layoutPriority(1)`, while the EUR conversion badge formats amounts compactly (e.g. `25.4K €`), preventing any truncation on compact widget grids.
6. **Persistent Tombstones & Zombie Resurrection Prevention**: When a habit record is deleted in the app, its UUID is permanently stored in `deleted_habit_log_ids` within App Group storage, purged immediately from `offline_habits_queue`, `local_smokes_logs`, and `local_water_logs`. Both `WidgetDataCoordinator` and `HabitsService` filter all entries against these tombstones. This strictly prevents the offline queue or local cache from resurrecting deleted entries as "new un-synced offline records" upon app backgrounding, pull-to-refresh, or widget timeline reloads.
