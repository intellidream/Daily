# Smart Ledger iOS Feature

## Overview
The **Smart Ledger iOS** feature provides text-based financial planning and personal net worth management within the Daily iOS app, directly integrated into the **Finances** -> **Money** sub-tab.

It mirrors the Double-Entry DSL architecture established in WinUI (`Daily.Services.Finances.SmartLedgerParser`) while implementing user-aligned ergonomics:
1. **Dynamic Scaling (`100x Multiplier`)**: Values between `**Incoming**` up to `**Deposit**` represent hundreds of Lei (`151` = `15.100 Lei`, `49` = `4.900 Lei`, `10` = `1.000 Lei`).
2. **Deposit & Post-Deposit Direct Values**: Values within `**Deposit**` and following sections are treated as exact/full amounts (`44.000L` = `44.000 Lei`, `53.156,47` = `53.156,47 Lei`).
3. **Parentheses as Pure Metadata**: All content inside parentheses `(...)` is purely informative/annotative and completely excluded from numeric mathematical evaluation.
4. **Custom Net Worth Formula**:
   $$\text{Net Worth} = \text{Deposits Total} + \text{Balance Total}$$
   In zero-based budgeting, where all monthly income is budgeted (`Balance = 0`), Net Worth reflects current bank deposits (`127.156,47 Lei`). Any monthly surplus automatically expands Net Worth.
5. **Interactive UI Pills**: Prominently display full Lei values with subtle badges for the shorthand notations and informative notes.

---

## Architecture

### 1. Core Data Models (`DailyCore/Models/SmartLedgerModels.swift`)
- `SmartLedgerItem`:
  - `id: UUID`: Unique identifier for SwiftUI rendering.
  - `key: String`: Account or category name (e.g. `Card`, `Rata/Rds/Gaz...`, `ECO/ME!`).
  - `rawAmount: Double`: Unscaled shorthand value (e.g. `151.0`, `49.0`, `44000.0`).
  - `calculatedAmount: Double`: Evaluated full value in Lei (e.g. `15100.0`, `4900.0`, `44000.0`).
  - `isScaled: Bool`: Flag indicating whether the item belongs to pre-Deposit sections.
  - `notes: [String]`: Extracted annotations from round parentheses.
  - `percentageOfSection: Double`: Calculated relative weight in the section.
  - Formatting helpers: `formattedCalculatedAmount`, `formattedRawAmount`.
- `SmartLedgerSection`:
  - `name: String`: Section header name (`Incoming`, `Outgoing`, `Balance`, `Dentist`, `Deposit`).
  - `items: [SmartLedgerItem]`: Section items.
  - `totalCalculated: Double`: Sum of calculated item amounts or explicit section total.
  - `totalRaw: Double`: Sum of raw amounts.
  - `isScaled: Bool`: Section scale indicator.
- `ParsedSmartLedger`:
  - Aggregated totals: `incomingTotal`, `outgoingTotal`, `balanceTotal`, `dentistTotal`, `depositTotal`.
  - Computed Net Worth in RON (`netWorth`) and EUR (`netWorthEUR`).
  - Formatted helpers with compact badge support (`formattedBadge(_:)`).

### 2. Parsing Engine (`DailyCore/Services/SmartLedgerParser.swift`)
- **AST Line Parser**:
  - Detects Markdown section delimiters (`**Incoming**`, `**Outgoing**`, etc.).
  - Filters empty lines and Markdown horizontal rules (`---`).
  - Pre-processes parenthesized expressions (`(...)`) across the line to extract metadata notes, then strips them before numeric tokenization.
  - **Key Cleaning (`cleanKeyName`)**:
    - Preserves intentional double-slashes `//` within category keys (e.g., `Itp/Rvg/4.27//Ghs/Prk/Csc/Rca/1.27`).
    - Strips embedded parenthesized notes from category names (e.g., `Serviciu/(0/*100)/Outs/(0*200)` -> `Serviciu//Outs`) and aggregates extracted note tokens (`["0/*100", "0*200"]`).
    - Strips trailing slashes left when a trailing parenthesized note is removed.
    - Preserves pure note lines (`isPureNote`) verbatim without stripping outer parentheses.
  - Converts European/Romanian number formats (thousands dot `44.000`, decimal comma `53.156,47`).
  - Applies 100x multiplier conditionally based on section position relative to `**Deposit**`.
  - Handles explicit `Total = ...` and `(Total = ...)` expressions.

### 3. Persistent Store (`DailyCore/Services/SmartLedgerStore.swift`)
- `@MainActor ObservableObject` providing single-source-of-truth.
- Persists raw text in `UserDefaults` (`daily_smart_ledger_raw_text_v1`).
- Falls back to baseline starter template on clean installs.
- Publishes reactive updates upon saving or resetting.

### 4. Two-Way DSL Mutation Engine (`DailyCore/Services/SmartLedgerParser.swift` & `SmartLedgerStore.swift`)
- **Deterministic Line Tracking**: `SmartLedgerItem` retains `sectionName`, `lineIndex`, and `rawLine` from AST tokenization.
- **`adjustItemAmount(in:lineIndex:deltaRaw:)`**: Increments/decrements numeric tokens while preserving keys, parentheses notes, and comments.
- **`setItemAmount(in:lineIndex:newRaw:)`**: Sets exact numeric values preserving number formatting, currency suffixes (`€`, `L`, `$`), and trailing notes.
- **`addItem(to:sectionName:key:rawAmount:note:)`**: Injects new category lines before section total markers.
- **`deleteItem(from:lineIndex:)`**: Prunes line entries cleanly and cleans consecutive empty lines.
- **`recalculateTotalsInLines(_:)`**: Automatically balances section `Total = ...` expressions and updates `**Balance**` `Total = Incoming - Outgoing`.

### 5. SwiftUI Presentation Layer (`iOS/Daily/Views/Finances`)
- **Navigation Architecture**:
  - `FloatingGlassCapsule`: Anchored bottom capsule configured with `[Dashboard, Money, Health, Habits]`, displaying the `wallet.bifold.fill` icon for Money.
  - `FinancesMainView`: Sub-tab order updated to `[Money | Stocks | World]`, opening `Money` by default.
- **Interactive Pill Steppers**:
  - Each non-note item row features inline Liquid Glass `[ − ]` and `[ + ]` steppers with spring haptics.
  - Pre-Deposit scaled items step by 1 unit (= 100 Lei).
  - Unscaled items step by 100 Lei.
- **Horizontally Scrollable Category Titles**:
  - Main list rows wrap category names in `ScrollView(.horizontal, showsIndicators: false)` so users can drag long keys (like `Itp/Rvg/4.27//Ghs/Prk/Csc/Rca/1.27` or `V/N/Y/O/AI/M/W/E/I/Ap/Am/Sy/Ad/Sp`) left and right.
  - Dedicated slider indicator button (`slider.horizontal.3`) pinned next to the title clearly indicates quick-adjust access.
- **Auto-Scrolling Title Component (`AutoScrollingText.swift`)**:
  - Used in `SmartLedgerQuickAdjustSheet.swift` in both the top navigation bar (`ToolbarItem(placement: .principal)`) and the hero card.
  - Synchronously computes text intrinsic width using `UIFont`.
  - If text exceeds container bounds, smoothly animates horizontal marquee scrolling (start -> pause -> end -> pause -> start) and supports manual touch dragging with auto-resume.
- **Quick Adjust Sheet (`SmartLedgerQuickAdjustSheet.swift`)**:
  - Tapping any category pill or note chip opens the quick adjustment modal.
  - Preset delta chips:
    - Scaled: `-500L (-5)`, `-200L (-2)`, `-100L (-1)`, `+100L (+1)`, `+200L (+2)`, `+500L (+5)`, `+1.000L (+10)`.
    - Unscaled: `-1.000`, `-500`, `+500`, `+1.000`, `+5.000`.
    - Real-time conversion preview, exact amount input, note editor, and category deletion with confirmation.
- **Add Category Modal (`AddLedgerItemSheet.swift`)**:
  - "+ Adaugă" button on section headers to create new items on the fly.
  - Live preview of scaled amounts into full Lei.
- **Backup Raw Editor (`SmartLedgerEditorSheet.swift`)**:
  - Retained as a robust fallback editor for directly modifying the raw DSL code.

---

## Verification & Testing
- **Unit Tests**: `DailyCoreTests/SmartLedgerParserTests.swift` passes 10/10 tests (including preserving `//` in keys, stripping embedded parenthesized notes, positive balance, increment adjustment with total balancing, comment/note preservation, category addition, and deletion). All 57 test cases across `DailyCore` passing cleanly.
- **Simulator Inspection (SimulaPhone)**: Verified interactive `[ - ]` and `[ + ]` steppers, subtab ordering, floating capsule order `[Dashboard, Money, Health, Habits]`, horizontal title dragging in list, and auto-scrolling titles in detail sheets.
- **Physical Device Deployment**: Built, signed, installed, and launched on iPhone 16 Pro ("Schmitz").
