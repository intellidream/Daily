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
  - Pre-processes parenthesized expressions (`(...)`) to extract metadata notes, then strips them before numeric tokenization.
  - Strips inline comments (`//`).
  - Converts European/Romanian number formats (thousands dot `44.000`, decimal comma `53.156,47`).
  - Applies 100x multiplier conditionally based on section position relative to `**Deposit**`.
  - Handles explicit `Total = ...` and `(Total = ...)` expressions.

### 3. Persistent Store (`DailyCore/Services/SmartLedgerStore.swift`)
- `@MainActor ObservableObject` providing single-source-of-truth.
- Persists raw text in `UserDefaults` (`daily_smart_ledger_raw_text_v1`).
- Falls back to baseline starter template on clean installs.
- Publishes reactive updates upon saving or resetting.

### 4. SwiftUI Presentation Layer (`iOS/Daily/Views/Finances`)
- **`FinancesMainView.swift` (Money Sub-tab)**:
  - Header: Integrated capsule switcher (`World | Stocks | Money`).
  - `netWorthHeroCard`:
    - Large Net Worth in Lei (`127.156,47 Lei`) and EUR (`~25.431 €`).
    - Metric badges: `DEPOZITE`, `SOLD`, `INCOMING`, `DENTIST`.
    - "Edit Ledger" button.
  - Categorized Section Cards:
    - `Incoming` (Venituri & Card/Cash breakdown with purple progress bars).
    - `Outgoing` (Cheltuieli with category weights & progress bars).
    - `Balance` (Zero-Based Budget status caption).
    - `Dentist` (Tracked liability caption & total).
    - `Deposits & Savings` (Bank deposit cards with EUR estimates and note pills).
- **`SmartLedgerEditorSheet.swift`**:
  - Live preview header showing recalculated Net Worth and totals in real-time.
  - "Paste from Clipboard" one-tap paste action.
  - "Reset Default" template restoration.
  - Monospaced dark `TextEditor` with line counter.

---

## Verification & Testing
- **Unit Tests**: `DailyCoreTests/SmartLedgerParserTests.swift` passes 100% (4/4 tests: totals, breakdown, percentage, positive balance).
- **Simulator Inspection (SimulaPhone)**: Verified visual layout, colors, badges, and editor sheet.
- **Physical Device Deployment**: Installed on iPhone 16 Pro ("Schmitz").
