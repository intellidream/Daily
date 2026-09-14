# iOS Native Widgets (WidgetKit & AppIntents)

## 1. Overview
Daily provides native iOS Home Screen and Lock Screen widgets powered by Apple's **WidgetKit** framework and iOS 17+ interactive **App Intents**. The widgets deliver an ultra-dense, visual aesthetic inspired by modern health telemetry dashboards like StressWatch, while preserving Daily's dark Liquid Glass styling.

## 2. Widgets Included

### A. Bubbles Widget (Hydration & Drinks)
- **Supported Families**:
  - Home Screen: Small (1x1), Medium (2x1), Large (2x2)
  - Lock Screen: Accessory Circular, Accessory Inline
- **Deep Linking**:
  - Tapping opens the app directly into Habits Hub with Bubbles selected (`daily://habits/bubbles`).
- **Visuals**:
  - Header text ("Bubbles") removed; sleek icon-centric presentation.
  - **Small (1x1)**:
    - Top-right header: percentage on the left with Bubbles icon (`drop.fill`) to its right.
    - Large progress circle maximized with minimal spacing, displaying `[actual/total] ml` inside.
    - 3 bottom action buttons in order: **`100`** (Coffee amber), **`150`** (Water cyan), **`300`** (Water cyan).
  - **Medium (2x1)**:
    - Multi-liquid circular arc gauge (`BubblesMultiDrinkArcRing`) on the left spanning vertically top-to-bottom.
    - Colored breakdown list by drink type without repetitive icons.
    - 2x2 grid of 4 buttons: **`300`**, **`150`**, **`100`**, **`200`** (tea).
- **Interactive Quick-Logging**:
  - Zero-app-open instant logging via `LogWaterIntent`:
    - **Small (1x1)**: **`100`** (Coffee), **`150`** (Water), **`300`** (Water).
    - **Medium (2x1)**: **`300`**, **`150`**, **`100`**, **`200`** (tea).
  - Updates local App Group aggregates in 0ms and triggers timeline reload via `WidgetCenter`.

---

### B. Smokes Widget (Tobacco & Cessation Tracking)
- **Supported Families**:
  - Home Screen: Small (1x1), Medium (2x1), Large (2x2)
  - Lock Screen: Accessory Circular, Accessory Inline
- **Deep Linking**:
  - Tapping opens the app directly into Habits Hub with Smokes selected (`daily://habits/smokes`).
- **Visuals**:
  - Header text ("Smokes") removed.
  - Custom vector anatomical lungs silhouette (`WidgetVectorLungsShape` + `WidgetVectorLungsBronchiShape`) centered within an outer progress ring.
  - Dynamic lung health color transitioning based on logged smokes today:
    - **Healthy Pink (`#FF6B8B`)**: 0 smokes.
    - **Dusky Rose (`#D45D79`)**: 1–5 smokes.
    - **Sickly Ashen Gray (`#8A7D7D`)**: 6–10 smokes.
    - **Dark Charcoal (`#3A3A3C`)**: 11+ smokes.
  - Total count displayed cleanly under the lungs inside the hero circle.
  - Right section displays `flame.fill` icon, compact daily baseline (e.g. `40 base`), and compact elapsed time (`XXs`/`YYm`/`ZZh`).
- **Interactive Quick-Logging**:
  - Zero-app-open instant logging via `LogSmokeIntent`:
    - **Small (1x1)**: 2 compact buttons: **`Cig`** (red) and **`Heat`** (blue).
    - **Medium (2x1)**: 2x2 grid of 4 buttons: **`Cgr`** (purple), **`Rol`** (orange), **`Cig`** (red), **`Heat`** (blue).
  - *Abstinence logging is explicitly excluded to keep tracking focused, streamlined, and friction-free.*

---

### C. Money Widget (SmartLedger & Personal Finances)
- **Supported Families**:
  - Home Screen: Small (1x1), Medium (2x1), Large (2x2)
  - Lock Screen: Accessory Rectangular
- **Deep Linking**:
  - Tapping opens the app directly into Finances Hub with Money selected (`daily://finances/money`).
- **Visuals**:
  - Top header: **`NET WORTH`** caption in upper left, green wallet icon in upper right.
  - Prominent Net Worth in Lei in large white typography with live EUR conversion badge below (synced with BNR rates).
  - Compact liquidity breakdown (`Crd 15.1K · Csh 900`).
  - Medium widget displays three structured columns: Net Worth, Flow In/Out, and Liquid breakdown.
  - Large widget includes ranked capsules of the top outgoing budget allocations and full ledger summary.
- **Interactive Quick Adjustments**:
  - Zero-app-open ledger balance adjustment via `AdjustLedgerIntent`:
    - **Small (1x1)**: **`-50 Crd`** and **`+100 Crd`**.
    - **Medium (2x1)**: **`-50 Crd`**, **`-50 Csh`**, and **`+100 Crd`**.
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
7. **Cross-Device Tombstone Synchronization**: When records are deleted on another device or instance (marked `is_deleted: true` in Supabase), other instances query the day's habit logs including soft-deleted items to detect remotely deleted UUIDs. These UUIDs are automatically merged into the local `deleted_habit_log_ids` tombstone set, purged from the local `offlineLogQueue`, and excluded from local logs and widget calculations. Furthermore, only pending logs in `offlineLogQueue` (not arbitrary stale logs from cache) are merged with remote data, preventing zombie records from persisting across devices.
