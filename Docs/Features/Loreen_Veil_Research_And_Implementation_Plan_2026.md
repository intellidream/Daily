# Loreen Veil — Research, Script Specification & Cross-Platform Implementation Plan (2026)

## 1. Executive Summary & Origin Story

**Loreen Veil** is a zero-egress, zero-latency **Visual Privacy Shield** for **Tagdos & Notes** across all Daily platforms (iOS, macOS, Android, Windows 11 / WinUI 3, watchOS, and Wear OS). It renders personal tasks, active memos, and quick notes in **Loreen Script** — a bespoke 26-letter geometric cipher invented by the author in childhood and named after Sandra's 1986 song *"Loreen"* (from the album *Mirrors*).

To activate **Loreen Veil** in Settings, the user completes an interactive, 100% offline **"Loreen Initiation"** handwriting challenge: drawing a word in Loreen (such as `LOREEN` or their own first name) directly on-screen to prove fluency. Once unlocked, Settings also houses the **Feature Documentation** and the **Loreen Codex** (full A–Z visual reference + practice pad).

### Honest Security & Privacy Framing
- **What Loreen Veil IS**: A high-craft **anti-shoulder-surfing visual veil** that protects private notes and Tagdos against casual glances in cafés, offices, public transit, screen-sharing, and screenshots — with zero password friction on every tap.
- **What Loreen Veil IS NOT**: Because Loreen Script is a deterministic 1-to-1 monoalphabetic substitution over the Latin alphabet, it is **visual obfuscation**, not cryptographic encryption.
- **Architectural Benefit**: All underlying text in local caches (`GroupDefaults`, Room, `SharedPreferences`, JSON) and Supabase (`public.tagdos_streams`, `public.tagdos_quick_notes`) remains untouched UTF-8. Search, TagDoS DSL parsing (`/` and `&`), semantic pill classification (`$`, `€`, `!`, digits), AI Smart Briefings, Realtime sync, and widgets continue to function with **zero regressions** and **zero extra Supabase egress**.

---

## 2. Linguistic, Historical & Structural Research

### 2.1 Origin Dataset
- **Initial recalled glyphs (17)**: `A, B, C, D, E, I, J, L, M, N, O, Q, R, U, V, W, X`
- **Newly recalled glyph (+1)**: `F` (inverted triangle bisected by a vertical & horizontal cross), bringing the authentic recalled set to **18 of 26 letters (69.2%)**.
- **Pattern-completed glyphs (8)**: `G, H, K, P, S, T, Y, Z`, derived strictly from the internal geometric rules observed in the original 18 glyphs and refined with the author.

### 2.2 Historical & Archetypal Parallels
Although invented independently in childhood for writing private notes by hand, Loreen Script naturally converges on several classic geometric writing systems and ciphers:
1. **Phoenician / Proto-Sinaitic & Archaic Greek**:
   - **A** (`○`) parallels *Ayin* (`𐤏`).
   - **D** (enclosed 3-rung ladder) parallels *Heth* (`𐤇`) and CJK `目`.
   - **E** (`⊕`, circle + 4-way cross) is identical to *Teth* (`𐤈`) and archaic *Theta* (as well as the astronomical/alchemical symbol for Earth / sun cross).
   - **I** (`†`) parallels *Taw* (`𐤕`).
2. **Tifinagh (Berber Script) & Alchemical/Astronomical Notation**:
   - Shares the same minimal geometric primitives (circles, crosses, 8-ray stars, open arches, bilateral symmetry) designed for rapid, unambiguous hand tracing.
3. **Classic Substitution Ciphers**:
   - Balances high visual disguise against quick 1–3 stroke handwriting ergonomics.

### 2.3 Internal Visual Grammar
Out of the 18 original glyphs, **15 exhibit strict left-right vertical symmetry**, all use uniform monoline strokes inside a vertical rectangular cell (`viewBox="0 0 100 120"`, cap height `y = 22..98`), and they organize into **four structural families**:

1. **Radial & Circle Family** *(primarily vowels + Q)*:
   - `A` (`○` empty circle) → `E` (`⊕` circle + 4-way cross) → `G` (`⊗` circle + diagonal X) → `H` (`∞` two horizontally adjacent touching circles) → `I` (`†` bare Latin cross) → `O` (`✳` bare 8-ray star) → `Q` (`❂` circle enclosing 8-ray star, literally `A + O`).
2. **Crossbar Progressions**:
   - `U` (`∩`, 0 bars) → `V` (arch + 1 bar) → `W` (arch + 2 bars).
   - `C` (`Ⅱ`, open frame, 0 inner rungs) → `D` (closed frame + 3 inner rungs).
3. **Block / Architectural Cluster**:
   - `J` (vertical spine with opposite top-left & bottom-right rectangular flags).
   - `K` (inverted `L` — wide top block + narrow descending stem).
   - `L` (pedestal / top-hat — wide bottom block + narrow rising stem).
4. **Mirrored, Rotated & Disguised Latin Forms**:
   - `F` (inverted triangle + full cross — recalled by author).
   - `P` (`|◁`) ↔ `R` (`▷|`) horizontal mirror pair.
   - `S` (empty vertical hourglass) ↔ `Z` (90° rotation — empty horizontal bowtie).
   - `I` (`†`) ↔ `T` (Cross of Lorraine `‡`).
   - `U` (`∩`) ↔ `Y` (elevated-stem chalice/trident).
   - `B` (fluid `2`-loop), `M` (crossed inner legs), `N` (opposing `∪` over `∩` meeting at center), `X` (curved vertical vesica with 4 flared ends).

### 2.4 Canonical A–Z Vector Specification (`viewBox="0 0 100 120"`)

All glyphs share cap height `y = 22..98`, center `(50, 60)`, uniform stroke `6.5`, `stroke-linecap="round"`, and `stroke-linejoin="round"`.

| Letter | Origin | Family | Visual Description | Canonical SVG Inner Elements |
| :--- | :--- | :--- | :--- | :--- |
| **A** | Original | Radial (Vowel) | Empty circle | `<circle cx="50" cy="60" r="38" />` |
| **B** | Original | Disguised Latin | Fluid `2`-curve loop | `<path d="M 24 24 L 62 24 C 82 24 84 52 56 58 L 42 62 C 16 68 18 96 38 96 L 78 96" />` |
| **C** | Original | Bars & Rungs | Open twin-pillar frame (0 rungs) | `<path d="M 20 22 H 80 M 20 98 H 80 M 37 22 V 98 M 63 22 V 98" />` |
| **D** | Original | Bars & Rungs | Closed ladder frame (3 rungs) | `<path d="M 24 22 H 76 V 98 H 24 Z M 24 41 H 76 M 24 60 H 76 M 24 79 H 76" />` |
| **E** | Original | Radial (Vowel) | Circle + 4-way cross | `<circle cx="50" cy="60" r="38" /><path d="M 12 60 H 88 M 50 22 V 98" />` |
| **F** | Original | Recalled (PDF) | Inverted triangle + full cross | `<path d="M 18 22 H 82 L 50 96 Z M 50 22 V 98 M 24 58 H 76" />` |
| **G** | Completed | Radial (Var. 1) | Circle + diagonal X cross | `<circle cx="50" cy="60" r="38" /><path d="M 23.1 33.1 L 76.9 86.9 M 76.9 33.1 L 23.1 86.9" />` |
| **H** | Completed | Radial (Refined) | Two adjacent touching circles (`∞`) | `<circle cx="30.5" cy="60" r="19.5" /><circle cx="69.5" cy="60" r="19.5" />` |
| **I** | Original | Radial / Cross | Bare Latin cross | `<path d="M 50 22 V 98 M 28 46 H 72" />` |
| **J** | Original | Architectural | Vertical spine + 2 opposite flags | `<path d="M 20 22 H 50 V 40 H 20 Z M 50 40 V 80 M 50 80 H 80 V 98 H 50 Z" />` |
| **K** | Completed | Architectural | Inverted `L` (wide top block) | `<path d="M 16 22 H 84 V 48 H 16 Z M 40 48 V 98 H 60 V 48" />` |
| **L** | Original | Architectural | Pedestal / top-hat (wide base) | `<path d="M 16 72 H 84 V 98 H 16 Z M 40 72 V 22 H 60 V 72" />` |
| **M** | Original | Disguised Latin | `M` with crossed inner legs | `<path d="M 16 98 L 34 22 L 62 98 M 38 98 L 66 22 L 84 98" />` |
| **N** | Original | Symmetric | Opposing `∪` over `∩` meeting at center | `<path d="M 20 22 C 20 56 36 60 50 60 C 64 60 80 56 80 22 M 20 98 C 20 64 36 60 50 60 C 64 60 80 64 80 98" />` |
| **O** | Original | Radial (Vowel) | Bare 8-ray star | `<path d="M 50 22 V 98 M 12 60 H 88 M 23.1 33.1 L 76.9 86.9 M 76.9 33.1 L 23.1 86.9" />` |
| **P** | Completed | Mirror Pair | Horizontal mirror of `R` (`\|◁`) | `<path d="M 22 22 V 98 M 78 22 V 98 M 78 22 L 22 60 L 78 98" />` |
| **Q** | Original | Radial | Circle enclosing 8-ray star (`A + O`) | `<circle cx="50" cy="60" r="38" /><path d="M 50 22 V 98 M 12 60 H 88 M 23.1 33.1 L 76.9 86.9 M 76.9 33.1 L 23.1 86.9" />` |
| **R** | Original | Mirror Pair | Triangle facing right + bar (`▷\|`) | `<path d="M 22 22 V 98 M 78 22 V 98 M 22 22 L 78 60 L 22 98" />` |
| **S** | Completed | Hourglass | Empty vertical hourglass | `<path d="M 20 22 H 80 L 20 98 H 80 Z" />` |
| **T** | Completed | Crosses | Cross of Lorraine (`‡`) | `<path d="M 50 22 V 98 M 32 42 H 68 M 22 62 H 78" />` |
| **U** | Original | Arch & Bars | Inverted open arch (`∩`, 0 bars) | `<path d="M 20 98 V 52 A 30 30 0 0 1 80 52 V 98" />` |
| **V** | Original | Arch & Bars | Arch + 1 crossbar | `<path d="M 20 98 V 52 A 30 30 0 0 1 80 52 V 98 M 20 60 H 80" />` |
| **W** | Original | Arch & Bars | Arch + 2 crossbars | `<path d="M 20 98 V 52 A 30 30 0 0 1 80 52 V 98 M 20 52 H 80 M 20 72 H 80" />` |
| **X** | Original | Symmetric | Curved vertical vesica, 4 flared ends | `<path d="M 20 22 C 80 34 80 86 20 98 M 80 22 C 20 34 20 86 80 98" />` |
| **Y** | Completed | Arch & Bars (Refined) | Chalice / trident with tall inner stem | `<path d="M 22 22 V 34 A 28 28 0 0 0 78 34 V 22 M 50 30 V 98" />` |
| **Z** | Completed | Hourglass | 90° rotation of `S` (horizontal bowtie) | `<path d="M 16 22 V 98 L 84 22 V 98 Z" />` |

### 2.5 Typography & Localization Policy
- **Monocase Mapping**: Both uppercase `A–Z` (`U+0041..U+005A`) and lowercase `a–z` (`U+0061..U+007A`) map to the same 26 Loreen glyph indices inside `Loreen-Regular.ttf`.
- **Romanian Diacritics**: Mapped directly in the font's `cmap` table so native text requires zero runtime string transformation:
  - `Ă` / `ă` (`U+0102`, `U+0103`) & `Â` / `â` (`U+00C2`, `U+00E2`) → **A**
  - `Î` / `î` (`U+00CE`, `U+00EE`) → **I**
  - `Ș` / `ș` (`U+0218`, `U+0219`) & `Ş` / `ş` (`U+015E`, `U+015F`) → **S**
  - `Ț` / `ț` (`U+021A`, `U+021B`) & `Ţ` / `ţ` (`U+0162`, `U+0163`) → **T**
- **DSL Punctuation & Numerals**: Clean geometric monoline glyphs for `0–9` and TagDoS syntax characters (`/`, `&`, `$`, `€`, `!`, `?`, `.`, `,`, `:`, `;`, `-`, `—`, `(`, `)`) are included in `Loreen-Regular.ttf` so semantic pills (`C$T`, `RUN/5K`, `EXP!`) retain visual structure and spacing without font fallback jitter.

---

## 3. Zero-Egress, Zero-Latency, Zero-Regression Architecture

### 3.1 Single Compiled TrueType Font (`Loreen-Regular.ttf`)
- Built reproducibly from a canonical single source of truth: `Art/Loreen/loreen_glyphs.json` via `Scripts/build_loreen_font.py` (using `fontTools` + `skia-pathops` / `bezier` stroke expansion in an isolated build venv).
- Expected binary footprint: **~15–25 KB** per platform bundle.
- **Zero runtime text mutation**: Switching Loreen Veil on/off or holding to peek only toggles the UI text style's `Font` / `FontFamily` (`Loreen-Regular` vs system UI font). The GPU glyph atlas renders every letter at **60/120Hz** with zero string allocations, zero regex passes, and zero layout thrashing.
- **Zero-Allocation Watch & Scroll Rule**:
  - **Wear OS**: `val LoreenFontFamily = FontFamily(Font(R.font.loreen_regular))` declared as a top-level immutable singleton — never instantiated inside `@Composable` bodies or `ScalingLazyColumn` items.
  - **watchOS / iOS / macOS**: Static cached `Font.custom("Loreen", size: ...)` helper; no per-cell string parsing during scroll.
  - **WinUI 3**: Static `FontFamily("ms-appx:///Assets/Fonts/Loreen-Regular.ttf#Loreen")` resource in `App.xaml`.

### 3.2 Zero Supabase Egress Guarantee
- **Zero SQL migrations**: No columns added to `tagdos_streams`, `tagdos_quick_notes`, or `profiles`.
- **Zero extra Supabase REST/RPC calls or Realtime channels**.
- **Local-only preference storage** (piggybacking on existing local settings stores):
  - **Apple (`DailyCore`)**: `AppSettings.swift` via `GroupDefaults` (`group.com.intellidream.daily` on iOS/watchOS; `7LZ9ZT2Z5B.group.com.intellidream.daily` on macOS — instant App + Widget sharing, zero Keychain prompts).
  - **Android**: Existing `SharedPreferences` / DataStore used by `SettingsScreen.kt` (shared with Glance widgets via existing widget update trigger).
  - **WinUI 3**: `AppSettings` JSON persisted by `WinUI/Daily.WinUI/Services/SettingsService.cs`.
  - **Wear OS**: Local `SharedPreferences` (optionally mirrored from Android phone over local Wearable Data Layer / Bluetooth with zero cloud calls).

### 3.3 Settings Data Contract
All platforms implement backward-compatible defaults so existing persisted settings decode cleanly:
```text
loreenVeilUnlocked: Bool              = false   // Set true only after passing Loreen Initiation
loreenVeilEnabled: Bool               = false   // Master Veil toggle
loreenVeilApplyToTagdos: Bool         = true    // Apply to Tagdos Streams & Pills
loreenVeilApplyToNotes: Bool          = true    // Apply to Active Memos & Quick Notes
loreenVeilApplyToWidgets: Bool        = false   // Opt-in for OS Home/Lock/Desktop Widgets
loreenVeilRequireBiometricsForPeek: Bool = false // Optional Face ID / Touch ID / Windows Hello gate
```

---

## 4. The "Loreen Initiation" Handwriting Challenge & Settings UX

### 4.1 Why Standard OS OCR Cannot Be Used — and the `$P` Solution
Standard platform OCR engines (Apple Vision `VNRecognizeTextRequest`, Google ML Kit Digital Ink, Windows Ink OCR) only recognize Unicode scripts (Latin, Cyrillic, CJK, etc.) and cannot classify a custom invented alphabet.

Instead, Daily will run a **100% offline, deterministic `$P` Point-Cloud Multistroke Recognizer** (Vatavu, Anthony & Wobbrock, 2012) implemented identically in ~250 lines of pure math in Swift (`DailyCore`), Kotlin (`Android`), and C# (`WinUI`):
- **Stroke-order & stroke-direction invariant**: Drawing a circle clockwise or counter-clockwise, or adding crossbars left-to-right vs right-to-left, scores identically.
- **Zero ML model weight / < 1 ms per recognition**: Templates are resampled directly from the 26 canonical SVG paths (`N = 32` normalized points per glyph; ~8 KB static template table).
- **Pipeline per drawing tile**:
  1. Collect `(x, y, strokeId)` points from touch, Apple Pencil, mouse, or stylus.
  2. Resample entire point cloud to `N = 32` equidistant points, scale uniformly preserving aspect ratio to `[0, 1]`, translate centroid to `(0.5, 0.5)`.
  3. Compute bidirectional point-cloud Euclidean distance against all 26 templates + **geometric disambiguation guards** for structurally close pairs:
     - `I` vs `T`: horizontal stroke count (`1` vs `2`).
     - `U` vs `V` vs `W`: horizontal crossbar count inside arch (`0` vs `1` vs `2`).
     - `A` vs `E` vs `G` vs `Q` vs `H`: outer closed loop count (`1` vs `2` for `H`) + inner stroke count/orientation (`0` vs `2` orthogonal vs `2` diagonal vs `4`).
     - `P` vs `R`: triangle apex horizontal bias (`x < 0.45` for `P` vs `x > 0.55` for `R`).
     - `K` vs `L`: bounding-box vertical center of mass (`y < 0.48` for `K` vs `y > 0.52` for `L`).
     - `S` vs `Z`: top/bottom horizontal segments (`S`) vs left/right vertical segments (`Z`).
  4. Accept if top match equals the tile's target letter (or within top-2 if confidence margin is close on noisy mouse input, configurable per input device).

### 4.2 Settings UI Flow
1. **Locked State (`loreenVeilUnlocked == false`)**:
   - Inside Settings (`Privacy & Security` / `Features`), the **Loreen Veil** card displays a locked badge and brief intro.
   - Tapping **"Unlock via Loreen Initiation"** opens the Initiation Sheet:
     - Challenge selector: **`LOREEN`** (default, 6 tiles) or **`My Name`** (user's first name from profile/auth metadata, normalized A–Z, clamped 3–10 characters; falls back to `LOREEN` if unavailable).
     - Row of Liquid Glass square drawing tiles — one per letter of the target word, with subtle Latin letter label beneath each tile.
     - Optional **"Peek Hint"** toggle for learning (disabled/collapsed by default so the challenge feels rewarding, or unlocks cleanly once completed).
     - After pen-up + 450 ms multistroke debounce, the tile evaluates automatically: verified letters glow emerald with haptic feedback; mismatches pulse subtly with a one-tap clear button.
     - Completing all tiles plays a celebratory unlock state and sets `loreenVeilUnlocked = true`.
2. **Unlocked State (`loreenVeilUnlocked == true`)**:
   - Master **Loreen Veil** switch + granular toggles (Tagdos, Notes, OS Widgets, Biometric Peek).
   - **In-App Feature Documentation Card**: Clear explanation of Visual Veil vs. storage encryption, Hold-to-Peek, automatic readable Latin while editing, and desktop shortcuts (`⌘⇧L` / `Ctrl+Shift+L`).
   - **Loreen Codex (Full A–Z Reference & Freehand Practice Pad)**: Searchable/interactive 26-letter specimen grid grouped by family (`Original` vs `Pattern-Completed`) plus a live scratchpad where users can draw any glyph and see the recognizer identify it. Includes an optional **"Re-lock Loreen Veil"** reset action.

---

## 5. Veil & Peek Interaction Design in Tagdos & Notes

- **Tagdos Streams & Pills**: Pill text switches to `Loreen-Regular` while preserving semantic capsule colors (Financial emerald, Urgent crimson, Metric amber, Primary cyan), counts, and driving-pill layout.
- **Active Memos & Quick Notes**: Titles, preview snippets, and Markdown read view render in `Loreen-Regular`.
- **Editing Safety (Auto-Reveal)**: Opening the Inline Pill Editor, Raw DSL Editor, or Markdown Note Editor (Edit tab) automatically renders in readable Latin so the user never edits blind; saving or closing immediately re-applies Loreen Veil.
- **Hold-to-Peek**:
  - **Mobile / Touch**: Press-and-hold the Eye/Shield pill in the Hub header (or long-press a Quick Note card) to reveal readable Latin with a smooth crossfade; releasing re-veils instantly.
  - **Desktop (macOS & Windows 11)**: Toolbar Hold-to-Peek button + global quick toggle shortcut (`⌘⇧L` on macOS, `Ctrl+Shift+L` on WinUI 3).
  - **Optional Biometric Gate**: When `loreenVeilRequireBiometricsForPeek == true`, tapping Reveal triggers Face ID / Touch ID / BiometricPrompt / Windows Hello before lifting the veil for a short session window.

---

## 6. Phased Multi-Platform Implementation Roadmap

### Phase 0 — Canonical Assets & Font Build Pipeline
- **Create**:
  - `Art/Loreen/loreen_glyphs.json` (single source of truth for all 26 letters, digits, DSL punctuation, metadata, and normalized `$P` templates).
  - `Scripts/build_loreen_font.py` (converts canonical SVG paths into closed TrueType glyph outlines, builds `cmap` with monocase + Romanian diacritics, outputs `Loreen-Regular.ttf` + `loreen_templates.json`).
  - `Art/Loreen/Loreen-Regular.ttf` (canonical built binary copied/linked into platform bundles).
- **Verify**: Automated Python check verifying `cmap` coverage (`A-Z`, `a-z`, `ĂăÂâÎîȘșŞşȚțŢţ`, `0-9`, `/&$€!?:;-.`), valid non-overlapping contours, and QuickLook/CoreText specimen render.

### Phase 1 — `DailyCore` + iOS (Golden Standard)
- **Shared Core (`DailyCore`)**:
  - Extend `DailyCore/Sources/DailyCore/Models/AppSettings.swift` with the 6 `loreenVeil*` fields and backward-compatible `CodingKeys` / `init(from:)`.
  - Add `DailyCore/Sources/DailyCore/Models/LoreenGlyphCatalog.swift` (26-glyph metadata + `$P` point-cloud templates).
  - Add `DailyCore/Sources/DailyCore/Services/LoreenStrokeRecognizer.swift` (`$P` recognizer + geometric disambiguation).
  - Add unit tests in `DailyCore/Tests/DailyCoreTests/LoreenRecognizerTests.swift` (all 26 canonical glyphs, reversed stroke order, noisy inputs, Romanian diacritic normalization).
- **iOS (`iOS/Daily` & `iOS/DailyWidgets`)**:
  - Bundle `Loreen-Regular.ttf` and register in `Info.plist` (`UIAppFonts`).
  - Add `iOS/Daily/Views/Settings/LoreenVeilSettingsView.swift`, `LoreenInitiationSheet.swift`, `LoreenCodexView.swift`; link from `SettingsView.swift` / `FeaturesSettingsSection.swift`.
  - Integrate Veil + Hold-to-Peek + Auto-Reveal on edit into `TagdosNotesHubView.swift`, `TagdosActiveMemoView.swift`, `TagdosQuickNotesView.swift`, Dashboard card, and `iOS/DailyWidgets/TagdosWidget.swift`.
- **Verify**: `swift test` in `DailyCore` → iOS Simulator (`SimulaPhone` & `SimulaDuo`) → Physical iPhone (`Schmitz`).

### Phase 2 — macOS Native
- Mirror the verified iOS architecture inside `MacOS/` without modifying `iOS/` files:
  - Bundle `Loreen-Regular.ttf` (`ATSApplicationFontsPath` / `UIAppFonts` in `MacOS/Daily` & `MacOS/DailyWidgets`).
  - Add `MacOS/Daily/Views/Settings/LoreenVeilSettingsView.swift`, `LoreenInitiationSheet.swift` (mouse/trackpad `DragGesture` canvas), and `LoreenCodexView.swift`; link from `MacOS/Daily/Views/Settings/SettingsView.swift`.
  - Add Veil + Hold-to-Peek + `⌘⇧L` shortcut in `MacOS/Daily/Views/Tagdos/TagdosNotesHubView.swift`, `TagdosActiveMemoView.swift`, `TagdosQuickNotesView.swift`, `MenuBarExtra` popover, and `MacOS/DailyWidgets/TagdosWidget.swift`.
- **Verify**: Native signed build via `xcodebuild -project MacOS/Daily.xcodeproj -scheme Daily -configuration Debug -destination 'platform=macOS' build` + live window/MenuBarExtra/shortcut verification on host Mac.

### Phase 3 — Android Native
- Add `Android/app/src/main/res/font/loreen_regular.ttf` and static `LoreenFontFamily` singleton.
- Extend local settings persistence used by `Android/app/src/main/java/com/intellidream/daily/presentation/SettingsScreen.kt`.
- Add Kotlin `$P` engine `LoreenStrokeRecognizer.kt` + unit tests, plus Jetpack Compose `LoreenInitiationSheet.kt` and `LoreenCodexSheet.kt`.
- Integrate Veil + Hold-to-Peek + Auto-Reveal on edit into:
  - `Android/app/src/main/java/com/intellidream/daily/presentation/tagdos/TagdosNotesHubView.kt`
  - `Android/app/src/main/java/com/intellidream/daily/presentation/tagdos/TagdosActiveMemoView.kt`
  - `Android/app/src/main/java/com/intellidream/daily/presentation/tagdos/TagdosQuickNotesView.kt`
  - `Android/app/src/main/java/com/intellidream/daily/presentation/dashboard/TagdosNotesDashboardCard.kt`
  - Android Glance Tagdos Widget.
- **Verify**: `./gradlew assembleDebug` + Android Emulator (`Medium_Phone_API_36.1`) → Physical Pixel 9 Pro (`Trapper`) & Galaxy Z Fold 8 (`RADAR`).

### Phase 4 — Windows 11 (WinUI 3)
- Add `WinUI/Daily.WinUI/Assets/Fonts/Loreen-Regular.ttf` (`Content` build action) and static `FontFamily` resource.
- Extend `AppSettings` in `WinUI/Daily.WinUI/Services/SettingsService.cs`.
- Add C# `$P` engine `LoreenStrokeRecognizer.cs` + Ink/Pointer canvas in `WinUI/Daily.WinUI/Views/SettingsPage.xaml` (Initiation + Codex + Feature Docs).
- Integrate Veil + Hold-to-Peek + `Ctrl+Shift+L` shortcut into `WinUI/Daily.WinUI/Views/TagdosNotesDetailPage.xaml`, `WinUI/Daily.WinUI/Controls/TagdosWidgetControl.xaml`, Taskbar Flyout, and Desktop Widgets.
- **Verify**: Commit & push on Mac → `git pull` on Parallels Windows 11 VM (`prlctl exec "Windows 11"`) → `dotnet build -c Debug -p:Platform=ARM64` + live UI test.

### Phase 5 — Smartwatches (watchOS & Wear OS — Zero-Allocation Consumer Mode)
- **watchOS**: Bundle `Loreen-Regular.ttf` in `WatchOS/DailyWatch`, read `AppSettings.loreenVeil*` from App Group in `WatchTagdosView.swift`, add quick tap-to-peek toggle (no handwriting initiation needed on tiny watch screens; unlocked on companion or optional watch mirror). Verify on watchOS Simulator → physical Apple Watch Ultra 2.
- **Wear OS**: Add `WearOS/app/src/main/res/font/loreen_regular.ttf` with top-level cached `LoreenFontFamily`, integrate cleanly in `WearOS/app/src/main/java/com/intellidream/daily/wearos/presentation/tagdos/TagdosScreen.kt` (zero per-frame allocations in `ScalingLazyColumn`), store preference locally. Verify on Wear OS emulator → mandatory Release build (`./gradlew assembleRelease`) on physical Pixel Watch 5 / OnePlus Watch 3.

### Phase 6 — Cross-Platform Verification & Documentation Sync
- Update `Docs/Features/Tagdos_Notes_Feature.md` with a dedicated **Loreen Veil** section.
- Record verification outcomes across all 6 platforms in this document as each phase completes.

---

## 7. Verification Matrix

| Platform | `$P` Recognizer | Initiation Flow | Veil + Hold-to-Peek | Zero Egress Verified | Build / Device Verified |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `DailyCore` | Done (`5/5` tests pass) | N/A | N/A | Done (`AppSettings` local only) | `swift test --filter Loreen` (pass) |
| iOS (`SimulaDuo` / `Schmitz`) | Done (shared `DailyCore`) | Done (`LoreenInitiationSheet`, `LoreenCodexView`) | Done (`TagdosNotesHubView`, `ActiveMemo`, `QuickNotes`, Dashboard Card, `TagdosWidget`) | Done (no Supabase queries/migrations) | Simulator `SimulaDuo` & physical iPhone `Schmitz` |
| macOS (Native + MenuBarExtra) | Done (shared `DailyCore`) | Done (`LoreenInitiationSheet`, `LoreenCodexView`, mouse/trackpad) | Done (`TagdosNotesHubView`, `ActiveMemo`, `QuickNotes`, Dashboard Card, `MenuBarCompanionView` toggle, `⌘⇧L`, `TagdosWidget`) | Done (`GroupDefaults` `7LZ9ZT2Z5B.group...`, no cloud calls) | Native `xcodebuild` signed + launched on host Mac |
| Android (Emulator / `Trapper` / `RADAR`) | Planned | Planned | Planned | Planned | Planned |
| Windows 11 (WinUI 3 ARM64) | Planned | Planned | Planned | Planned | Planned |
| watchOS (Sim / Ultra 2) | N/A (Consumer) | N/A | Planned | Planned | Planned |
| Wear OS (Emu / Release APK) | N/A (Consumer) | N/A | Planned | Planned | Planned |
