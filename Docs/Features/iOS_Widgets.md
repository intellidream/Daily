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
    - Stylized watermark drop icon (`drop.fill`, 74pt height, 0.18 opacity) positioned on the right, bleeding ~35% outside widget bounds with `.clipped()`.
    - Progress ring on top-left comfortably inset (`72x72pt`, `lineWidth: 7.0`, `padding(.top, 4).padding(.leading, 4)`) ensuring the stroke is never clipped or pushed outside the widget boundaries.
    - Inside the ring: large bold current volume (`[actual]`) with smaller `/ [total] ml` underneath.
    - Top-right corner: percentage in a compact single-line cyan pill (`.lineLimit(1)`, `.fixedSize`, `padding(.top, 4)`), aligned flush top with the progress ring.
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
  - Header text ("Smokes") removed across all widgets.
  - **Small (1x1)**:
    - Stylized watermark flame icon (`flame.fill`, 74pt height, 0.18 opacity) on the right, bleeding ~35% outside widget bounds with `.clipped()`.
    - Outer progress ring starts from top-left, comfortably inset (`72x72pt`, `lineWidth: 7.0`, `padding(.top, 4).padding(.leading, 4)`) with zero clipping and clean gradient strictly from green to red (`accentGreen` -> `accentAmber` -> `accentOrange` -> `accentRed`).
    - Anatomical lungs removed from the small widget for maximum clarity and numerical readability.
    - Dual-tier numbers inside ring: large bold current count (`[todayTotal]`) with `/ [baseline]` smaller underneath.
    - Top-right corner: elapsed time since last smoke (`formattedTime`, e.g. `2h`, `45m`, `30s`) in a compact single-line frosted capsule pill (`padding(.top, 4)`), aligned flush top with the ring.
    - 2 bottom action buttons: **`Cig`** (red, powered by dedicated parameter-free `LogCigaretteIntent`) and **`Heat`** (blue, powered by dedicated `LogHeatedIntent`).
  - **Medium (2x1)** & **Large (2x2)**:
    - Custom vector anatomical lungs silhouette (`WidgetVectorLungsShape` + `WidgetVectorLungsBronchiShape`) centered within an outer progress ring.
    - Dynamic lung health color transitioning based on logged smokes today (Healthy Pink -> Dusky Rose -> Sickly Ashen Gray -> Dark Charcoal).
    - Total count displayed cleanly under the lungs inside the hero circle.
    - Right section displays `flame.fill` icon, compact daily baseline (e.g. `40 base`), and compact elapsed time.
- **Interactive Quick-Logging**:
  - Zero-app-open instant logging via dedicated App Intents:
    - **Small (1x1)**: **`LogCigaretteIntent`** (guarantees strictly `.cigarette` logging without string matching ambiguity) and **`LogHeatedIntent`** (`.heated`).
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
  - **Small (1x1)**:
    - Stylized watermark wallet icon (`wallet.bifold.fill`, 59pt height, 0.14 opacity, offset x: 16) in `WidgetColors.accentGreen`.
    - Net Worth in Lei positioned on the top-left in bold typography (`16pt`, `.minimumScaleFactor(0.65)`) with zero truncation.
    - Live EUR conversion badge (`25.4K €`) positioned flush in the top-right corner inside a frosted cyan capsule.
    - Compact liquidity breakdown (`Crd 15.1K · Csh 900`).
    - 2 quick adjustment buttons at bottom: **`-50 Crd`** and **`+100 Crd`**.
  - **Medium (2x1)**:
    - Displays three structured columns: Net Worth, Flow In/Out, and Liquid breakdown.
    - 3 quick adjust buttons: **`-50 Crd`**, **`-50 Csh`**, and **`+100 Crd`**.
  - **Large (2x2)**:
    - Full financial executive cockpit with ranked capsules of top outgoing budget allocations and full ledger summary.
- **Interactive Quick Adjustments**:
  - Zero-app-open ledger balance adjustment via `AdjustLedgerIntent`. Adjusts raw SmartLedger syntax in App Group storage, recalculates balances, and broadcasts widget timeline reload.

---

### D. Sleep Studio Widget (Health Hub & Nocturnal Telemetry)
- **Supported Families**:
  - Home Screen: Small (1x1), Medium (2x1), Large (2x2)
  - Lock Screen: Accessory Circular, Accessory Rectangular, Accessory Inline
- **Deep Linking**:
  - Tapping opens the app directly into Health Hub with Sleep Studio selected (`daily://health/sleep`), triggering `HealthDataService.shared.activeSubTab = .sleep`.
- **Visuals**:
  - **Small (1x1)**:
    - Radial Sleep Score ring on top-left (`72x72pt`, `lineWidth: 7.0`, `padding(.top, 4).padding(.leading, 4)`): cyan-blue-purple angular gradient with bold score (`71 / 100`).
    - Sleep duration pill (`4h 28m`) in top-right corner aligned flush top with the progress ring in `WidgetColors.accentPurple`.
    - Stylized watermark moon/stars icon (`moon.stars.fill`, 59pt height, 0.14 opacity, offset x: 16) in `WidgetColors.accentPurple`.
    - 2 bottom capsules: Bedtime-Wake schedule (`04:46-09:38`) and Efficiency (`92% Eff`).
  - **Medium (2x1)**:
    - Radial score hero on left (`78x78pt`) with total asleep duration (`4h 28m`) and score pill (`71 pts`).
    - Schedule and efficiency pill (`04:46 ➔ 09:38`, `92% Eff · 31% Rest`).
    - Multi-stage proportional color bar (Deep `#6366F1`, REM `#8B5CF6`, Light `#00E5FF`, Awake `#EF4444`).
    - 4 mini stage pills (`D 39m`, `R 43m`, `L 3h 6m`, `A 12m`) and device footer (`4h 52m in bed • Zepp OS Watch`).
  - **Large (2x2)**:
    - Header with `SLEEP STUDIO`, source device chip, and quality rating pill (`Fair`/`Optimal`).
    - Left radial gauge (`82x82pt`) with score and `SCORE` caption.
    - Right summary: total asleep duration (`4h 28m`), time in bed, bedtime and wake time.
    - Full-width proportional stage bar and 4-column breakdown grid with duration and percentage.
    - Nocturnal vitals cards: Resting Heart Rate (`81 bpm`), HRV SDNN, and Restorative ratio (`31%`).
  - **Lock Screen Accessories**:
    - Accessory Circular: Radial score ring with score.
    - Accessory Rectangular: Sleep duration, score, efficiency %, and bedtime/wake schedule.
    - Accessory Inline: `Sleep: 4h 28m (71)`.

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
8. **Sleep Studio Native Widgets & Zero-Mock Empty States**: A dedicated native widget suite `SleepWidget` provides sleep score ring, hypnogram architecture (Deep, REM, Light, Awake), restorative sleep metrics, resting heart rate, HRV, and bedtime schedule. Deep-links directly to `daily://health/sleep`. When no sleep session is recorded for the current day, all 3 sizes (Small, Medium, Large) dynamically switch to high-fidelity, dark liquid glass "No Data" variants (`No Sleep Tracked`, prompt to wear Apple Watch or log in Health, and quick "Open Studio" button) with zero invented or mock data.
9. **Small Money Widget Layout Polish**:
   - **Net Worth**: Compact Lei value displayed top-left with `"NET WORTH"` subtitle positioned neatly directly underneath.
   - **EUR Badge**: Cyan conversion badge (`25.4K €`) positioned in the top-right corner.
   - **Centered Liquidity Stack**: `Card [value]` and `Cash [value]` stacked vertically one below the other, vertically centered between the Net Worth section and the bottom action buttons (`-100 Crd` & `+100 Crd`).
10. **In-App Finances Large Card Navigation**: Standardized the header navigation link in the Large 2x2 modular dashboard card to `"Open Hub"` with chevron, aligning with the wide and habits cards.
11. **Real-Currency Nominal Widget Adjustments & DSL Scaling Fix**:
   - **Root Cause**: The Smart Ledger DSL scales sections like `**Incoming**` and `**Outgoing**` by 100 ($1\text{ unit} = 100\text{ Lei}$). Previously, passing raw deltas (`deltaRaw: -50` / `+100`) adjusted the DSL value by 50/100 units, inadvertently modifying accounts by 5,000 and 10,000 Lei.
   - **Fix**: `AdjustLedgerIntent` and `WidgetDataCoordinator.adjustLedgerAmount` now accept real currency amounts (`deltaReal: Double`). In scaled sections (`item.isScaled == true`), `deltaRaw = deltaReal / 100.0` (so $-100\text{ Lei} \to -1.0$ DSL unit, $+100\text{ Lei} \to +1.0$ DSL unit). In unscaled sections, it applies `deltaReal` directly.
   - **Updated Buttons**: All widget sizes (Small `-100 Crd` / `+100 Crd`; Medium `-100 Crd`, `-100 Csh`, `+100 Crd`; Large `-100 Card`, `-100 Cash`, `+100 Card`) adjust exact nominal amounts written on the buttons in real currency (Lei).
12. **Monthly Flow Metric Definition**:
   - The `Flow` / `Monthly Flow` readout in the Medium widget and in-app dashboard card computes `Total Incoming / Total Outgoing` in Lei.
   - **Incoming (In)** represents the calculated sum of all accounts and income lines in `**Incoming**` (e.g. Card + Cash balances).
   - **Outgoing (Out)** represents the calculated sum of all planned and budgeted expense allocations in `**Outgoing**`.

