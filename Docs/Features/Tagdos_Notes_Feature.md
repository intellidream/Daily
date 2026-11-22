# Tagdos & Notes Feature Specification

## 1. Overview & Conceptual Architecture

**Tagdos & Notes** is a high-density, mnemonic productivity and quick-capture system designed for DayOne. Inspired by high-velocity executive note-taking and cognitive shorthand, it compresses daily operations, routines, reminders, and financial checkpoints into dense, obfuscated lines of mental tags.

Instead of heavy database rows and complex forms, Tagdos structures work into **Dynamic Streams** (`1..N`, seeded with 5 defaults and expandable via `+`) represented as single-line syntax strings that can be scanned at a glance, prioritized on the fly, and reflected seamlessly across Dashboard cards, interactive Hub views, iOS System Widgets, macOS, Android, and Windows (WinUI 3).

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
- `updatePillText(in:pillId:newText:) -> TagDoStream`: Edits an existing pill's text inline, re-evaluates its semantic pill type (`financial`, `urgent`, `metric`, `action`), and re-serializes `rawSyntax`.
- `isAlreadyTagdosDsl(_:)`: Detects whether an external task title is already written in TagDoS DSL shorthand (`/` clusters, uppercase mnemonics, `$`/`€`/`!`/metric tokens).
- `prepareImportItem(title:notes:isHighImportance:)`: Preserves valid TagDoS DSL titles verbatim (appending only notes if present), or converts natural-language titles into an editable mnemonic proposal plus formatted `• [TAG] Title — Notes` memo entry.
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

---

## 4. Supabase Cloud Sync & Cross-Device Reflection

### 4.1 Schema & Realtime Tables
- **`public.tagdos_streams`**:
  - `id UUID PRIMARY KEY DEFAULT gen_random_uuid()`
  - `user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE`
  - `order_index INT NOT NULL`
  - `title TEXT NOT NULL`
  - `raw_text TEXT NOT NULL`
  - `stream_reminder TIMESTAMPTZ`
  - `active_memos JSONB DEFAULT '[]'::jsonb`
  - `attachments JSONB DEFAULT '[]'::jsonb`
  - `updated_at TIMESTAMPTZ DEFAULT now()`
  - Unique constraint on `(user_id, order_index)`.
- **`public.tagdos_quick_notes`**:
  - `id UUID PRIMARY KEY DEFAULT gen_random_uuid()`
  - `user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE`
  - `title TEXT NOT NULL`
  - `content TEXT NOT NULL`
  - `is_pinned BOOLEAN DEFAULT false`
  - `created_at TIMESTAMPTZ DEFAULT now()`
  - `updated_at TIMESTAMPTZ DEFAULT now()`
- **Supabase Realtime Channel**:
  - `TagdosStore` subscribes to `channel.postgresChange` for `tagdos_streams` and `tagdos_quick_notes` filtered by `user_id`.
  - Immediate reflection across devices logged in with the same account (e.g. SimulaPhone and physical iPhone Schmitz).
  - Debounced push mechanism (0.5s) to coalesce rapid user edits.

### 4.2 Storage & Attachments Architecture (`tagdos-attachments`)
- Dedicated storage bucket `tagdos-attachments` with authenticated user RLS policies.
- **On-demand Download**: Attachment metadata and image thumbnails are synced; raw file data downloads on tap when opened from a secondary device (matching Microsoft To Do behavior).
- **Local Disk Cache**: Managed by `TagdosAttachmentManager.shared` in `Caches/TagdosAttachments/` with cache eviction and offline fallback.

---

## 5. UI Architecture & Components

### 5.1 In-App Modular Dashboard Card (`TagdosNotesDashboardCard.swift`)
Adheres to DayOne's Liquid Glass design language with Title Case headers:
- **Small (1x1)**: Focus Tag Hero with glowing border, reminder capsule, next queue pill preview, and active tag count.
- **Wide (2x1)**: Left Focus Hero with reminder + Right scrollable pipeline preview showing upcoming tags.
- **Tall (1x2)**: Vertical stream progression showing active driving pills, reminder stamps, and Quick Notes preview.
- **Large (2x2)**: Comprehensive multi-stream view displaying Stream 1 through Stream 4 with colored pill badges and Quick Notes preview strip.

### 5.2 Dedicated Tagdos Hub (`TagdosNotesHubView.swift`)
Accessible via Dashboard tap or `daily://tagdos` deep link:
- **Navigation & Dismissal**:
  - Replaced legacy text back button with a clean, circular Liquid Glass back button (`chevron.left` in 32x32 circle, no "Dashboard" label).
  - Integrated interactive edge swipe-to-dismiss gesture (`startX <= 75 && translationX > 50`) for seamless natural navigation.
- **Stream Switcher Bar**:
  - Dynamic stream tabs (`S1` to `SN`) showing `customTitle` on tab pills when set (falling back to the driving tag), a `+` button to create additional streams beyond 5, a **Reorder** button (`S1..SN`), and a dedicated `Notes` tab.
  - `S1`–`SN` are rendered inside distinct mini circular badges (`Circle()` with Purple glass accent) to stand out clearly beside the stream title/driving tag.
  - Clean `Notes` tab label (`Image(systemName: "note.text")` + `Text("Notes")`), removing redundant trailing emojis.
- **Clean Cluster Canvas & Inline Pill Editing**:
  - Standalone visual `&` separator rows between cluster cards are omitted in Canvas view on all platforms (maximizing vertical density) while keeping `&` intact inside the serialized DSL and Raw Text editor.
  - Tapping/right-clicking any pill opens inline **Edit Tag** controls (re-classifying semantic color/type on save) alongside Prioritize to Front, Mark Done, Recycle to Back, and Delete.
- **Dynamic & Custom Stream Naming, Safe Rename & Deletion Protection**:
  - Intelligent auto-detection of domain keywords (e.g. Work & Code, Health & Fitness, Finances & Bills, Home & Life, Daily Ops, or Driving Tag focus).
  - Interactive stream rename sheet/dialog allowing custom naming, **Reset to Auto** (clear custom title), **Move Left / Move Right**, and **2-step Delete Stream confirmation** (`Keep Stream` / `Confirm Delete`) so streams are never deleted by accident.
  - **Dirty-State & Canonical Slot UUID Sync Protection**: Local renames, edits, reorders, and attachment changes persist a `dirty` set locally across restarts; remote Supabase pulls never prune dirty/unpushed streams and reuse canonical remote slot UUIDs for `(user_id, stream_number)` upserts.
  - Re-detection fallback: if the user deletes or clears the custom name, the system automatically falls back to the auto-detected domain title.
- **Stream Reordering & Cross-Device Persistence**:
  - Users can reorder streams via quick **Move Left / Move Right** actions (stream tab context menu / long-press / Rename dialog) or the dedicated **Reorder Streams** UI (drag-and-drop on iOS/macOS/WinUI 3 + explicit Up/Down arrows on all 4 platforms) while preserving the active selected stream.
  - Reordered `orderIndex = 0..N-1` persists locally and in OS widgets immediately, and syncs to Supabase `stream_number = 1..N`.
- **100% English UI Standardization**: All TagDoS views, dialogs, action sheets, and fallback quick notes across iOS, macOS, Android, and WinUI 3 are standardized in English.
- **Collapsible Per-Stream Active Memos (`TagdosActiveMemoView.swift`)**:
  - Compact collapsible header showing memo and attachment count badges, preserving vertical screen space for the cluster canvas.
  - Smooth spring animation toggle to expand full Markdown editor, file carousel, and media previews.
- **Dedicated Quick Notes Stream (`TagdosQuickNotesView.swift`)**:
  - Pinned notes and chronological notes listing with live search filtering.
  - Full-featured Markdown editor sheet (`MarkdownNoteEditorSheet`) with live preview toggle (Edit / Preview modes), formatting toolbar, and note pinning.
- **Sync Status**: Real-time cloud icon in navigation bar (`icloud.fill` when synced, spinning indicator during upload/download).

---

## 6. iOS System OS Widgets (`TagdosWidget.swift`)

Registered in `DailyWidgetsBundle` under `com.intellidream.daily.TagdosWidget`:
- Updated all widget titles and headers to Title Case (`Tagdos & Notes`, `Tagdos`).
- **Dynamic Stream Titles**: Widget snapshot automatically reflects custom or auto-detected stream titles via `displayTitle`.
- **Small**: Displays the driving focus pill, reminder time, upcoming pipeline queue, and total active count.
- **Medium**: Two-column layout with left focus hero and right top-2 stream pipeline rows with colored pill badges.
- **Large**: 5-stream overview showing all active clusters and count badges in dark glass aesthetic.
- **Lock Screen Accessories**:
  - `accessoryCircular`: Circular focus badge with total counter.
  - `accessoryRectangular`: Focus tag + upcoming pipeline queue.
  - `accessoryInline`: Text line with focus pill and next action.

---

## 7. Verification & Delivery
- **SimulaPhone Simulator**:
  - Verified compilation and in-app dashboard layout at top position (`simulaphone_app_tagdos.png`).
  - Verified interactive Hub view with circular back button, `S1`..`S5` circular badges, clean `Notes` tab, and auto-detected stream names (`simulaphone_hub_verified.png`).
  - Verified Small, Medium, and Large widgets placed on Home Screen pages (`simulaphone_current_homescreen.png`).
  - Verified 5-pill floating dock with active TagDoS pill (`simulaphone_5pills_dock.png`, `simulaphone_tagdos_tab.png`).
- **Physical Device ("Schmitz")**:
  - Built arm64 debug package for iPhone 16 Pro ("Schmitz", ID `00008140-000E2C863EFB001C`).
  - Successfully installed via `xcrun devicectl device install app` and launched live.

---

## 8. Floating Navigation Dock Integration (5-Pill Dock)
- **Positioning**: TagDoS is elevated to a first-class primary tab inside `FloatingGlassCapsule`: `[Dashboard, Money, TagDoS, Health, Habits]`.
- **Dock Scrubbing & Flick Gestures**: The dynamic segment calculation seamlessly splits the floating capsule into 5 equal touch areas, preserving both instant single-tap switching and continuous horizontal scrubbing with tactile haptics.
- **Root-Level Navigation**: Directly integrated into `RootView` with `onNavigateBack` fallback to Dashboard via top-left back button or edge swipe right.

---

## 9. External Task Import (Microsoft To Do & Google Tasks)

TagDoS supports one-way, on-demand task import from **Microsoft To Do** and **Google Tasks** across **iOS**, **macOS**, **Android**, and **Windows (WinUI 3)**:

### 9.1 Zero Background Egress & On-Demand Authentication
- External task fetching and `public.calendar_accounts` lookups execute **exclusively when the user opens the Import UI** or explicitly taps Refresh/Connect — there are zero launch queries, background timers, or polling loops.
- **Account Reuse & Re-Authentication**: Reads existing connected accounts from `calendar_accounts` (supporting 1-layer and WinUI 2-layer AES-GCM PBKDF2-SHA256 token decryption) and local OAuth cache. If unauthenticated or missing required scopes (`Tasks.Read` for Microsoft Graph, `https://www.googleapis.com/auth/tasks.readonly` for Google Tasks), the Import UI launches PKCE S256 OAuth directly (via `ASWebAuthenticationSession` on Apple platforms, system browser custom-scheme deep link callback on Android, and WinUI Calendar/OAuth flows on Windows).
- OAuth client IDs/secrets are kept outside Git in ignored configuration files (`Secrets.swift` on Apple, `Android/local.properties` -> `BuildConfig` on Android, `Configuration/Secrets.cs` on Windows).

### 9.2 DSL-Aware Conversion & Plain-Memo Notes
- **Already TagDoS DSL**: Recognizes single tags, `&` clusters, and `/` pipelines including multi-word tokens with internal spaces (e.g., `CRR vg/PL 98 & DOC sign`) while guarding against URLs (`http://`, `https://`, `www.`) and natural-language phrases with dates.
  - Its exact DSL expression is parsed directly into pills/clusters with **no** mnemonic renaming and **no** title duplication in `active_memos`.
  - Any optional task `Notes` body goes into `active_memos` strictly as **clean plain text** (HTML tags/entities decoded and stripped, with **no** `[DSL]` prefix).
- **Natural-Language Tasks**: Proposes an editable uppercase mnemonic (`$` / `€` / `!` inferred from keywords and high-importance flags) and appends `• [TAG] Original Title` (or `• [TAG] Original Title — Notes`) to `active_memos`.

### 9.3 Per-Task Multi-Stream Batch Import (Cross-List & Cross-Account)
- **Independent Row Targets**: Each task row provides its own destination selector (**Replace `S1..SN`**, **Append `S1..SN`**, or **+ New Stream** with optional custom title) plus a **"Default target / Apply to checked"** helper for fast triage.
- **Single-Step Combination**: Multiple tasks mapped to the same `Replace` or `Append` stream combine seamlessly (`/` for single tags, `&` for multi-cluster expressions, and newline-separated `active_memos`) in one batch transaction. Unnamed `+ New Stream` rows each create distinct new auto-titled streams.
- **Persistent Staging Across Lists & Providers**: Checked tasks, edited DSL tags, and chosen destinations remain staged across list, account, and Microsoft To Do ↔ Google Tasks switches within the import session so users can review everything in the Batch Summary and import once (`Import (N)`).
- **Pure Local Ownership (Zero Back-Links)**: Once imported, tasks live exclusively as native TagDoS streams and memos with zero external task IDs or write-back sync to Microsoft/Google.


