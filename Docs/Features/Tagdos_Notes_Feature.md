# Tagdos & Notes Feature Specification

## 1. Overview & Conceptual Architecture

**Tagdos & Notes** is a high-density, mnemonic productivity and quick-capture system designed for DayOne. Inspired by high-velocity executive note-taking and cognitive shorthand, it compresses daily operations, routines, reminders, and financial checkpoints into dense, obfuscated lines of mental tags.

Instead of heavy database rows and complex forms, Tagdos structures work into **Streams** (1 to 5) represented as single-line syntax strings that can be scanned at a glance, prioritized on the fly, and reflected seamlessly across Dashboard cards, interactive Hub views, and iOS System Widgets.

---

## 2. Syntax & Serialization Specification

### 2.1 Stream Grammar
```text
Stream       := Cluster (" & " Cluster)*
Cluster      := TagDo ("/" TagDo)*
TagDo        := [PRIORITY_MODIFIER] IDENTIFIER [METRIC_OR_TIME] [STATUS_MODIFIER]
```

- **Cluster Separator (`&`)**: Groups related tasks into logical execution batches (e.g. Morning Routine `&` Blood Panel `&` Credit Card Payments).
- **TagDo Separator (`/`)**: Separates sequential pills within a cluster (e.g. `MG/GM/TG`).
- **Pill Text**: 2–6 character mnemonic code representing a task, habit, entity, or action.

### 2.2 Semantic Pill Types & Automatic Token Detection
The deterministic tokenizer inspects each pill string and assigns semantic styling:

| Pill Type | Detection Rule | Visual Treatment | Examples |
| :--- | :--- | :--- | :--- |
| **Financial** | Contains `$` or `€` | Emerald Green border & glowing fill | `C$T`, `€100`, `PAY$` |
| **Urgent** | Ends with or contains `!` | Crimson / Coral Red glowing border | `EXP!`, `CALL!`, `TAX!` |
| **Metric / Time** | Contains digits or `h`/`m`/`k` | Amber / Golden Yellow tint | `22`, `14:00`, `45m`, `10K` |
| **Primary Action** | Alphabetic mnemonic | Electric Cyan / Indigo / Violet | `MG`, `GM`, `TG`, `FSH`, `LDL` |

### 2.3 Recycling & Lifecycle Semantics
A core requirement of Tagdos is **task reusability**:
- **Non-destructive Completion**: Tasks do not vanish into an archive when checked off unless explicitly requested.
- **Recycle to Back**: Checking off a recurring task (e.g. morning vitamins, gym routine, periodic billing) shifts the pill from the front of the cluster to the end of the queue.
- **Prioritize to Front**: Urgent items can be bumped immediately to index 0.
- **In-place Done**: Crosses out the pill with a strikethrough without shifting position.
- **Delete / Remove**: Removes one-off tasks entirely.

---

## 3. Data Architecture (`DailyCore`)

### 3.1 Models (`TagdoModels.swift`)
- `TagDoPill`: Represents an individual atomic item (`id`, `text`, `type`, `isCompleted`).
- `TagDoCluster`: Represents a group of sequential pills joined by `/`.
- `TagDoStream`: Represents an entire stream pipeline (`id`, `streamNumber`, `title`, `rawSyntax`, `reminderTime`, `clusters`, `drivingPillText`).
- `TagdosWidgetSnapshot`: Codable snapshot shared across App and WidgetKit targets via App Group shared storage.

### 3.2 Parser (`TagdosParser.swift`)
- `parseStream(raw:title:reminderTime:) -> TagDoStream`: Deterministic parser from raw string into cluster and pill hierarchy.
- `serializeStream(_ stream: TagDoStream) -> String`: Serializes modified clusters back into standard shorthand notation.
- `recyclePillToBack(pillId:in:) -> TagDoStream`: Moves completed pill to end of stream.
- `togglePillCompletion(pillId:in:) -> TagDoStream`: Toggles completion status.
- `movePillToFront(pillId:in:) -> TagDoStream`: Bumps pill to top priority.

### 3.3 State Management & Synchronization (`TagdosStore.swift`)
- `@MainActor` singleton `TagdosStore.shared`.
- Persists to `UserDefaults(suiteName: "group.com.intellidream.daily")`.
- Default seeded data includes:
  - **Stream 1**: `MG/GM/TG & FSH/LDL & C$T/INV & 22/HAB & MED/CHK & REV/DEP & WRK/PRJ` (Driving pill: `MG`, Reminder: 08:30)
  - **Stream 2**: `WRK/PRJ/REV & MET/ZOOM & CALL/CLI & BUG/FIX` (Driving pill: `WRK`, Reminder: 10:00)
  - **Stream 3**: `FIT/GYM & RUN/5K & PROT/SHK & CREAT/5G & SLP/REC` (Driving pill: `FIT`, Reminder: 17:30)
  - **Stream 4**: `FIN/CARD & CASH/EUR & INV/STK & CRYP/BTC` (Driving pill: `FIN`, Reminder: 19:00)
  - **Stream 5**: `HOM/ORD & CLN/KIT & BUY/MKT & GROC/VEG` (Driving pill: `HOM`, Reminder: 21:00)
- Triggers `WidgetCenter.shared.reloadTimelines(ofKind: "com.intellidream.daily.TagdosWidget")` on any data mutation.

---

## 4. UI Implementation

### 4.1 In-App Modular Dashboard Card (`TagdosNotesDashboardCard.swift`)
Adheres to DayOne's Liquid Glass design language with four responsive sizes:
- **Small (1x1)**: Focus Tag Hero with glowing border, reminder capsule, next queue pill preview, and active tag count.
- **Wide (2x1)**: Left Focus Hero with reminder + Right scrollable pipeline preview showing upcoming tags.
- **Tall (1x2)**: Vertical stream progression showing active driving pills and reminder stamps.
- **Large (2x2)**: Comprehensive multi-stream view displaying Stream 1 through Stream 3 with colored pill badges and deep link navigation.

### 4.2 Dedicated Tagdos Hub (`TagdosNotesHubView.swift`)
Accessible via Dashboard tap or `daily://tagdos` deep link:
- **Stream Switcher**: Segmented tabs for Streams 1–5 with active pill counters and driving pill badges.
- **Pipeline Visualizer**: Displays clusters linked by `&` connectors, wrapping pills via dynamic `FlowLayout`.
- **Pill Context Action Sheet**:
  - 🔄 *Recycle to Back* (for recurring items)
  - ✅ *Mark as Done / Toggle*
  - ⭐ *Prioritize to Front*
  - 🗑️ *Delete Tag*
- **Dual-Mode Raw Editor**: Toggle between interactive visual cards and raw shorthand text editor for rapid bulk editing.
- **Reminder Time Configuration**: Native time picker per stream to control alert schedule.
- **Quick Notes / Memos**: Scratchpad area below streams for unparsed scratch thoughts.

---

## 5. iOS System OS Widgets (`TagdosWidget.swift`)

Registered in `DailyWidgetsBundle` under `com.intellidream.daily.TagdosWidget`:
- **Small**: Displays the driving focus pill, reminder time, upcoming pipeline queue, and total active count.
- **Medium**: Two-column layout with left focus hero and right top-2 stream pipeline rows with colored pill badges.
- **Large**: 5-stream overview showing all active clusters and count badges in dark glass aesthetic.
- **Lock Screen Accessories**:
  - `accessoryCircular`: Circular focus badge with total counter.
  - `accessoryRectangular`: Focus tag + upcoming pipeline queue.
  - `accessoryInline`: Text line with focus pill and next action.

---

## 6. Verification & Delivery
- **SimulaPhone Simulator**:
  - Tested in-app dashboard layout at top position (`simulaphone_tagdos_top.png`).
  - Tested interactive Hub sheet (`simulaphone_tagdos_hub.png`).
  - Verified Small, Medium, and Large widgets placed on Home Screen pages (`simulaphone_tagdos_widgets_page0_v4.png`, `simulaphone_tagdos_large.png`).
- **Physical Device**:
  - Built arm64 debug package for iPhone 16 Pro ("Schmitz").
  - Successfully installed via `devicectl device install app`.
