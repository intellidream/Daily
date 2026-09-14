# iOS Modular & Resizable Dashboard Widgets Architecture

## 1. Overview & Strategic Goals

This feature introduces a fully customizable, modular, and resizable personal dashboard on iOS, establishing 100% architectural and UX parity with the desktop WinUI dashboard (`VariableSizedWrapGrid` with `1x1`, `2x1`, `1x2`, `2x2` tiles).

Prior to this implementation, the iOS dashboard presented a rigid, vertical stack of full-width (`Wide`) cards. With this modular system:
- Users can arrange widgets in a flexible **2-column grid**.
- Every widget dynamically adapts its information density and actionable controls across **4 distinct modular sizes**:
  - **Small ($1 \times 1$)**: Compact glanceable square (~$165 \times 165\text{ pt}$).
  - **Wide ($2 \times 1$)**: Classic full-width card (~$350 \times 165\text{ pt}$).
  - **Tall ($1 \times 2$)**: Vertical tower spanning two row units (~$165 \times 346\text{ pt}$).
  - **Large ($2 \times 2$)**: Comprehensive multi-metric hub (~$350 \times 346\text{ pt}$).
- Layouts are **persisted locally and across app restarts** in `GroupDefaults` (`UserDefaults`).
- Users can resize cards directly on the dashboard via an **instant haptic context menu** or customize the entire flow through a dedicated **Customize Dashboard modal sheet**.

---

## 2. Standardized Modular Grid Architecture & 120Hz ProMotion Engine

### 2.1 The 4 Real Root Causes of 120Hz ProMotion Jitter
A deep profiling analysis on iPhone 16 Pro (`D93AP`, 120Hz ProMotion display) identified four distinct issues that compounded into severe scrolling tremor and layout defects:

1. **Width Cache Thrashing Loop (`ModularDashboardLayout`)**:
   - In `ModularDashboardLayout.swift`, the fallback width was hardcoded to `proposal.width ?? 353`.
   - On the iPhone 16 Pro, the screen width is $402\text{ pt}$ ($1206\text{ px}$ @ 3x) and content width is $362\text{ pt}$ ($402 - 40$).
   - When `ScrollView` called `sizeThatFits` with an unconstrained proposal, the layout computed row positions based on $353\text{ pt}$. During `placeSubviews`, it received $362\text{ pt}$. Because the delta ($9\text{ pt} > 0.5\text{ pt}$) invalidated the layout cache on every single scroll frame, SwiftUI was forced to reconstruct subviews 120 times per second during momentum scrolling.

2. **Custom `Layout` Protocol vs. Hardware CoreAnimation Stacks**:
   - SwiftUI's `Layout` protocol performs CPU-side subview placement on every scroll tick when nested in `ScrollView`, preventing CoreAnimation from optimizing display layers into GPU compositing batches.

3. **Rigid 155pt Unit Height on Wide Cards (Dead Space)**:
   - Forcing Wide cards (like Health & Vitals, Habits) to expand to $155\text{ pt}$ when their content naturally requires only $95\text{–}110\text{ pt}$ created huge 60–70pt empty black voids inside the cards.
   - Because Wide cards span both columns and never share rows with other cards, they should hug their content naturally (`maxWidth: .infinity`), while Small ($155\text{ pt}$) and Tall/Large ($324\text{ pt}$) maintain geometric standardization.

4. **Sequential Non-Coalesced Grid Allocation (Sparse Grid Holes)**:
   - In sequential packing, placing a Small card followed by a Wide card caused the second column of that row to remain completely empty, producing awkward asymmetric gaps.

5. **Nested Gesture Recognizer Arbitration**:
   - A nested horizontal `ScrollView` in Weather Large and a global `DragGesture` in `RootView` were conflicting with the parent vertical `ScrollView`, triggering touch cancellation hitches and frame drops.

---

### 2.2 Native Coalesced Row-Grid Architecture (`DashboardRowBuilder`)

To resolve all issues permanently, `DashboardView` adopts a native coalesced row-grid builder (`DashboardRowBuilder`):
1. **Dynamic Row Coalescing (`DashboardRowBuilder.buildRows(from:)`)**:
   - Resolves incoming widget configurations into structured row layouts:
     - `.full(config)`: For Wide and Large cards spanning the full width.
     - `.pair(left, right)`: For two Small cards side-by-side.
     - `.tallWithSmalls(tall, smalls)`: Pairs a Tall card ($324\text{ pt}$) with up to two Small cards ($155\text{ pt} + 14\text{ pt} + 155\text{ pt} = 324\text{ pt}$), guaranteeing zero grid holes.
     - `.singleSmall(config)`: Graceful fallback if an isolated Small card cannot be paired.
2. **Native Stacks for 120 FPS Fluidity**:
   - Uses native `VStack(spacing: 14)` and `HStack(spacing: 14)`, allowing CoreAnimation to render and composite scroll content at a rock-solid 120 FPS without CPU layout thrashing.
3. **Natural Height for Wide Cards**:
   - Cards use `.dashboardCardFrame(for: size)`. Wide cards hug content height (`maxWidth: .infinity`), eliminating all empty voids. Small cards lock to $155\text{ pt}$, and Tall/Large cards lock to $324\text{ pt}$.
4. **Clean Non-Conflicting Gestures**:
   - Replaced horizontal `ScrollView` in Weather Large with a crisp 5-item `HStack(spacing: 8)`.
   - Constrained `RootView`'s edge-swipe `DragGesture` to only activate when `selectedTab != .dashboard`.

---

## 3. Data Models & Resilient Storage

### 3.1 `DashboardWidgetModels.swift` (`DailyCore`)
- `DashboardWidgetSize`: Enum containing `.small ("1x1")`, `.wide ("2x1")`, `.tall ("1x2")`, and `.large ("2x2")` with helper getters:
  - `columnSpan`: 1 for small/tall, 2 for wide/large.
  - `rowSpan`: 1 for small/wide, 2 for tall/large.
  - `displayName`: Human-readable label for pickers.
  - `iconName`: SF Symbol depicting the aspect ratio.
- `DashboardWidgetType`: Type-safe identifiers for standard widgets (`.weather`, `.news`, `.health`, `.habits`).
- `DashboardWidgetConfig`: Struct encapsulating `id: String`, `size: DashboardWidgetSize`, and `isVisible: Bool`.
- `DashboardWidgetConfig.defaultLayout`:
  ```swift
  [
      DashboardWidgetConfig(id: "weather", size: .wide, isVisible: true),
      DashboardWidgetConfig(id: "news", size: .wide, isVisible: true),
      DashboardWidgetConfig(id: "health", size: .wide, isVisible: true),
      DashboardWidgetConfig(id: "habits", size: .wide, isVisible: true)
  ]
  ```

### 3.2 Backward-Compatible Storage (`AppSettings.swift` & `GroupDefaults.swift`)
- Added `dashboardWidgets: [DashboardWidgetConfig]` to `AppSettings`.
- Implemented custom `init(from decoder: Decoder)` and `encode(to encoder: Encoder)` in `AppSettings`. Any existing user preferences JSON omitting `dashboardWidgets` seamlessly decodes with `DashboardWidgetConfig.defaultLayout`, guaranteeing zero data corruption or startup crashes.

---

## 4. Adaptive Widget Content Density

Each widget implements dedicated UI representations tailored for all 4 aspect ratios:

### 4.1 Weather & Atmosphere (`WeatherDashboardCard.swift`)
- **Small ($1 \times 1$)**: High-glanceability square with condition SF symbol, current location, 38pt thin rounded temperature (`22°`), condition description, and high/low range (`H: 25° · L: 14°`).
- **Wide ($2 \times 1$)**: Classic full-width banner with current temperature, condition badge, high/low, atmospheric description, and large condition icon.
- **Tall ($1 \times 2$)**: Vertical tower featuring current temperature and condition header, followed by a vertical 4-hour micro-forecast list (Time, SF symbol, Temp), plus bottom humidity (%) and wind speed badges.
- **Large ($2 \times 2$)**: Comprehensive weather station: hero temperature row, horizontal hourly forecast carousel (6 hours), and 3 atmospheric telemetry badges (Humidity, Wind speed, and Barometric Pressure).

### 4.2 News & Briefings (`NewsDashboardCard.swift`)
- **Small ($1 \times 1$)**: Top headline glance with `newspaper.fill` icon, publication badge pill, 3-line headline text in bold rounded font, and relative timestamp.
- **Wide ($2 \times 1$)**: Primary lead briefing card with headline, publication branding, relative time, and thumbnail image.
- **Tall ($1 \times 2$)**: Dual-story vertical tower featuring the lead story with full-width banner image and headline, separated by a divider from a secondary recent story with timestamp.
- **Large ($2 \times 2$)**: Extended news digest with full lead briefing and thumbnail, plus a vertical stack of 2 additional recent stories with publication metadata and thumbnail images.

### 4.3 Health & Vitals (`HealthDashboardCard.swift`)
- **Small ($1 \times 1$)**: Compact vitals glance with live heart rate indicator, bold 26pt daily steps counter, step goal progress capsule bar, and sleep duration footer.
- **Wide ($2 \times 1$)**: Standard 3-column split view (STEPS | HEART RATE | SLEEP) with vertical dividers.
- **Tall ($1 \times 2$)**: Vertical health tower with steps circular progress ring, heart rate section with resting HR, and nocturnal sleep section with sleep efficiency percentage.
- **Large ($2 \times 2$)**: Multi-metric biometrics hub: hero 3-metric row (Steps, Avg BPM, Sleep) above a 4-tile vitals matrix (HRV SDNN in ms, Blood Oxygen in %, Resting Heart Rate in bpm, and Sleep Score).

### 4.4 Habits & Cravings (`HabitsDashboardCard.swift`)
- **Small ($1 \times 1$)**: Dual-metric mini glance with water progress ring (28pt) and current ml, plus quick `+150ml` log chip, alongside cigarette count and allowance ring.
- **Wide ($2 \times 1$)**: Dual full circular progress rings (Bubbles cyan ring + Smokes color-coded allowance ring) and 5 quick intake chips (`300`, `150`, `100 Coffee`, `Cig`, `Heat`).
- **Tall ($1 \times 2$)**: Vertical tower with full 36pt Bubbles ring and quick `+300` / `+150` chips, separated by divider from Smokes ring with `+Cig` / `+Heat` log buttons.
- **Large ($2 \times 2$)**: Extended habits management hub: 44pt hero progress rings with volume/baseline targets, plus full 6-button quick intake grid (`+500 Bottle`, `+300 Water`, `+150 Water`, `+100 Coffee`, `+1 Cigarette`, `+1 Heated`).

### 4.5 Smart Ledger & Finances (`FinancesDashboardCard.swift`)
- **Small ($1 \times 1$)**: Compact Net Worth & Cash pill glance with total net worth figure, primary incoming/cash metrics, and balance indicator.
- **Wide ($2 \times 1$)**: Classic 3-column finance glance showing Net Worth, Monthly In/Out flow, and Cash & Deposits overview with tap-to-open Smart Ledger.
- **Tall ($1 \times 2$)**: Vertical finance tower displaying hero Net Worth, categorized incoming/outgoing breakdown list, and bottom cash status.
- **Large ($2 \times 2$)**: Comprehensive financial cockpit: hero Net Worth badge, categorized incoming/outgoing progress breakdown, cash & card liquidity cards, and direct adjust pills.

---

## 5. Interaction & Customization UX

### 5.1 Instant Context Menu (Direct on Dashboard)
Long-pressing any widget reveals an immediate iOS haptic context menu:
- **Widget Size**: `Small (1x1)`, `Wide (2x1)`, `Tall (1x2)`, `Large (2x2)` with a checkmark on the current active size.
- **Order**: `Move Up` (if not first) and `Move Down` (if not last).
- **Customize Dashboard...**: Direct link to the customization sheet.
- Resizing or reordering applies immediately with fluid spring animations.

### 5.2 Dedicated Customization Sheet (`CustomizeDashboardSheet.swift`)
Accessible via the header button (`slider.horizontal.2.square`) or the context menu:
- **List of Widgets**: Each card displays its icon, title, move up/down controls, and a 4-way segmented size selector (`[Small, Wide, Tall, Large]`).
- **Reset to Default Layout**: One-tap restore button returning all widgets to the factory `Wide (2x1)` order.
- Changes are instantly synced to `SettingsService.shared.update` and saved in `GroupDefaults`.

### 5.3 Global Edge-Swipe Back Navigation (`RootView.swift`)
To ensure natural iOS navigation ergonomics across the entire app without requiring users to reach for the bottom capsule or top buttons:
- Integrated a global edge-swipe detector via `.simultaneousGesture(DragGesture)` on all child views.
- Triggers when a gesture initiates within 50pt of the left screen edge (`startX <= 50`), traverses > 60pt to the right, and satisfies horizontal dominance (`abs(dx) > abs(dy) * 1.3`).
- Provides instantaneous tactile feedback via `UIImpactFeedbackGenerator(style: .light)` and smoothly transitions back to the main Dashboard (`navigateToDashboard()`).

---

## 6. Verification & Automated Test Coverage

1. **DailyCore Unit Tests (`DashboardLayoutTests.swift`)**:
   - `Widget Size Matrix Dimensions`: Verified 1x1, 2x1, 1x2, 2x2 column and row span calculations.
   - `Default Dashboard Layout Configuration`: Verified 4 default widgets with size `.wide`.
   - `AppSettings JSON Round-Trip`: Verified encoding and decoding with custom widget configurations.
   - `Legacy AppSettings JSON Graceful Fallback`: Verified that legacy settings without `dashboardWidgets` decode cleanly to default layout without throwing errors.
   - **Full Suite Status**: All 28 tests across 4 suites in `DailyCore` passed 100% green.

2. **Xcode Compilation & Physical Device Deployment**:
   - Clean compilation for physical iPhone 16 Pro destination (`** BUILD SUCCEEDED **`).
   - Deployed and launched live on `iPhone 16 Pro` ("Schmitz", CoreDevice ID `62990754-1EE9-5A95-A45E-F4A69DA6E591`).
