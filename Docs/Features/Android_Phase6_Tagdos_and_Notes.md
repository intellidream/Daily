# Android Phase 6: TagDoS & Notes Studio and Shorthand Stream DSL

## 1. Overview
Phase 6 introduces native Android parity for the **TagDoS & Notes Studio**, replicating 100% of the iOS `DailyCore` TagDoS mental tag pipelines, Shorthand Stream DSL grammar, non-destructive task recycling, token-level semantic classification, offline-first Room database cache (`DailyDatabase` v4 with `synced_at` dirty tracking), modular dashboard card across all 4 grid sizes (`1x1 Small`, `2x1 Wide`, `1x2 Tall`, `2x2 Large`), and dedicated interactive TagDoS Hub (`Streams 1-5`, `Active Memos`, `Quick Notes`).

---

## 2. Architecture & Shorthand Stream DSL Grammar

### 2.1 Domain Models (`core-model/com.intellidream.daily.model`)
- **`TagDoPillType`**:
  - `Standard`: Neon Cyan (`#00E5FF`). Regular operational tasks.
  - `Financial`: Neon Emerald (`#00E676`). Auto-detected when token contains `$` or `€`.
  - `Urgent`: Glowing Ruby Coral (`#FFFF2D55`). Auto-detected when token contains `!`.
  - `TemporalOrMetric`: Neon Amber Yellow (`#FFD600`). Auto-detected when token contains digits/numbers.
  - `Completed`: Muted translucent White (`#59FFFFFF`) with strikethrough decoration.
- **`TagDoPill`**: Atomic tag token containing `id`, `rawText`, `isCompleted`, auto-classified `type`, and optional `customColorHex`.
- **`TagDoCluster`**: Logical grouping delimited by `/` within a stream, containing `id`, list of `pills`, and derived `drivingPill` (the first active non-completed pill in the cluster).
- **`TagDoAttachment`**: Rich reference metadata containing `id`, `name`, `type` (`Link`, `Doc`, `Pdf`, `Credential`), `uri`, and `fileSize`.
- **`TagDoStream`**: Full mental task stream consisting of:
  - `id: String`
  - `orderIndex: Int` (0 to 4 for S1 through S5)
  - `customTitle: String?`
  - `rawText: String`
  - `streamReminder: Long?` (epoch millis checkpoint)
  - `activeMemos: String` (Markdown notes for the stream)
  - `attachments: List<TagDoAttachment>`
  - `clusters: List<TagDoCluster>`
  - `displayTitle`: Defaults to `customTitle` if present, else computes auto-detected title from the driving pill, falling back to `"Stream ${orderIndex + 1}"`.
  - `drivingPill`: The first active pill of the first active cluster, displayed on the stream indicator badge.
- **`TagDoQuickNote`**: Lightweight Markdown memo containing `id`, `title`, `content`, `isPinned`, `createdAt`, and `updatedAt`.
- **`TagDoPillAction`**: Encapsulates selected stream and pill target for bottom sheet actions.

### 2.2 Shorthand Stream DSL Parser & Non-Destructive Mutations (`core-model/TagdosParser.kt`)
1:1 Kotlin port of iOS `TagdosParser.swift`:
- **Grammar**:
  - `Stream` = `Cluster` separated by ` & `
  - `Cluster` = `Pill` separated by `/`
  - Example: `GM/TG/MG & FSH/LDL & C$T/DUB/14 & PL98/PBZ/SPL/CLN/ROT$ & BP/ACTE`
- **Non-Destructive Task Recycling (`recyclePillToBack`)**:
  - Identifies the target pill within its parent cluster.
  - Removes it from its current position and moves it to the back (end) of that cluster while preserving its recurrence state.
  - Instantly recalculates the cluster's driving pill and updates the stream badge.
- **Completion Toggle (`togglePillCompletion`)**:
  - Toggles `isCompleted` without deleting the task, marking it with strikethrough and moving focus to the next available task.
- **Move to Front (`movePillToFront`)**:
  - Elevates an urgent pill to become the immediate driving pill of its cluster.
- **Safe Deletion (`removePill`)**:
  - Removes a one-off task from the stream text cleanly, pruning empty clusters if all child pills are deleted.
- **Add Pill (`addPill`)**:
  - Safely injects a new token into a target cluster.

---

## 3. Offline-First Room SQLite Cache & State Management (`core-database`)

### 3.1 Room Entities & Schema Version 4
- **`TagdoStreamEntity`**:
  - `id: String` (Primary Key, e.g. `"stream_1"`)
  - `order_index: Int`
  - `custom_title: String?`
  - `raw_text: String`
  - `stream_reminder: Long?`
  - `active_memos: String`
  - `attachments_json: String`
  - `updated_at: Long`
  - `synced_at: Long?` (Dirty tracking: `null` marks local mutation awaiting remote sync)
- **`TagdoQuickNoteEntity`**:
  - `id: String` (Primary Key UUID)
  - `title: String`
  - `content: String`
  - `is_pinned: Boolean`
  - `created_at: Long`
  - `updated_at: Long`
  - `synced_at: Long?`
- **`DailyDatabase.kt`**: Bumped to version 4, registering `TagdoStreamEntity`, `TagdoQuickNoteEntity`, and `tagdosDao()`.

### 3.2 Reactive Repository (`TagdosRepository.kt`)
- Hot reactive StateFlows:
  - `streams: StateFlow<List<TagDoStream>>`
  - `quickNotes: StateFlow<List<TagDoQuickNote>>`
  - `isSyncing: StateFlow<Boolean>`
- Automatic initial seeding of 5 default streams on first run:
  1. `Stream 1 (Daily Ops)`: `MG/GM/TG & FSH/LDL & C$T/DUB/14 & PL98/PBZ/SPL/CLN/ROT$ & BP/ACTE & VER/CLD/DIV$/CNTR/!MP$/FCT$/STK/BON$ & BIA/€CO & SSD/ELVS/MEIZ & GORN/PICI/CRNA/IOA & CDO/SRN/NLU/NIN/SVS & ITP/CRRvg/Park/Ghis`
  2. `Stream 2 (Work & Code)`: `WRK/PRJ/REV & MET/ZOOM/CALL & DOC/RFC/PLAN & ARCH/DATA/ENG & FIX/LINT/CI`
  3. `Stream 3 (Fitness & Health)`: `RUN/5K/HRV & GYM/LEGS/CORE & HYD/2L/3L & SLP/8H/REST & MED/MINDFUL`
  4. `Stream 4 (Finances & Tax)`: `INV/ETF/STK & DIV$/PAY/TAX & ACC/BAL/SAVE & AUDIT/EXP/REC & REBAL/PORT`
  5. `Stream 5 (Home & Errands)`: `HOM/ORD/CLN & BUY/MKT/GROC & FAM/CALL/VIS & MAINT/CAR/INSP & RELAX/READ`
- Automatic initial seeding of starter Quick Notes (`DUBaFest bilete` pinned, `Benzina 98`).
- All mutations immediately write through to SQLite Room and mark `synced_at = null` for background WorkManager dirty sync.

---

## 4. UI & Presentation Components (`app/presentation`)

### 4.1 Modular Dashboard Widget (`TagdosNotesDashboardCard.kt`)
Supports all 4 sizes of the modular liquid grid:
1. **`1x1 Small`**: Compact stream driving pill badge (`S1 MG`), total active tags counter, and quick-tap to open hub.
2. **`2x1 Wide`**: Header with active tag count and `Open Hub >`, two primary stream previews (`Stream 1` and `Stream 2`) with horizontal chip clusters (`GM`, `TG`, `MG`, `C$T`, `+35`), and active reminder indicators.
3. **`1x2 Tall`**: Vertical pipeline showing Streams 1, 2, and 3 with full driving pill badges, cluster pills, and recent quick notes preview.
4. **`2x2 Large`**: Master cockpit displaying all 5 streams with driving tags, cluster flows, reminder timestamps, and pinned quick notes list.

### 4.2 Dedicated TagDoS & Notes Hub (`TagdosNotesHubView.kt`)
- Circular back button `<` returning seamlessly to Dashboard.
- Sync status pill indicator with animated icon.
- Dual Mode switcher: **Canvas Mode** vs **Raw Text Mode**.
- Horizontally scrollable stream selector bar:
  - Circular stream pills `S1`..`S5` displaying driving pill badges (e.g. `S1 GM 🔔`).
  - `Notes` capsule tab with note count badge.
- Interactive Canvas Mode:
  - Editable Stream title with pencil rename action.
  - Active tags count & clusters counter.
  - Reminder chip showing checkpoint time or `+ Reminder`.
  - Flow of clusters connected by stylized `&` DSL symbols.
  - Interactive pills colored by semantic type with `★` driving indicator.
  - `+ Tag` button per cluster.
- Raw Text Editor Mode:
  - Monospace syntax editor with grammar help tooltip.
  - "Save & Parse" instant parser compile button.
- Per-Stream Collapsible Active Memos (`TagdosActiveMemoView.kt`):
  - Expandable card with memo preview and attachment counter.
  - Markdown note editing and file/link attachments.
- Quick Notes Studio (`TagdosQuickNotesView.kt`):
  - Search field with clear button.
  - `+ New` button opening note editor sheet.
  - Pinned Notes section and All Notes section with last modified timestamps.
  - Long-press context menu to pin/unpin or delete.

### 4.3 Interactive Bottom Sheets
- **`TagdosPillActionSheet.kt`**: 1:1 Romanian action items matching iOS:
  - `Recycle to Back (Mută la coadă • Recurent)`
  - `Mark Done (Bifează pe loc)`
  - `Prioritizează la început de șir`
  - `Șterge definitiv (One-Off Task)`
- **`TagdosAddTagSheet.kt`**: Fast entry modal for new shorthand tags.
- **`TagdosRenameStreamSheet.kt`**: Custom stream title naming with fallback to auto-detected title.
- **`TagdosReminderSheet.kt`**: Rapid checkpoint selector presets (`08:30`, `10:00`, `14:00`, `17:30`, `19:00`, `21:00`, and clear).
- **`MarkdownNoteEditorSheet.kt`**: Full-screen Markdown note editor with title, preview toggle, and pin toggle.

---

## 5. Verification & Testing

### 5.1 Android Emulator (`Medium_Phone_API_36.1` / `emulator-5558`)
- **Compilation**: `assembleDebug` completed with 0 errors.
- **Dashboard Card**: Verified in `Wide (2x1)` and `Large (2x2)` sizes with dynamic token coloring and live badge counts.
- **Bottom Dock**: Verified `TagDoS` tab selection and persistent capsule navigation.
- **Recycling Engine**: Verified `recyclePillToBack` dynamically moves target pill to end of cluster, recomputes cluster driving pill, and updates top stream pill badge `S1 GM`.
- **Reminder Engine**: Verified selecting `08:30` updates stream reminder timestamp and displays `🔔 08:30` on both Hub and Dashboard card.
- **Raw Text Mode**: Verified real-time two-way synchronization between DSL text and Canvas clusters.
- **Active Memos**: Verified expanding/collapsing per-stream active memos.
- **Quick Notes**: Verified searching notes, viewing pinned items, and editing notes in `MarkdownNoteEditorSheet`.

### 5.2 Physical Devices Delivery
- **Google Pixel 9 Pro (`caiman`)**: Streamed install successful (`com.intellidream.daily.debug`), app launched and verified live via ADB.
- **Samsung Galaxy S25 Edge (`SM_S937B`)**: Streamed install successful (`com.intellidream.daily.debug`), app launched and verified live via ADB.
