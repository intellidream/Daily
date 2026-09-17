# Android Phase 5: Finances & Wealth Studio and SmartLedger DSL Engine

## 1. Overview
Phase 5 introduces native Android parity for the **Finances & Wealth Studio**, replicating 100% of the iOS `DailyCore` Finances domain, `SmartLedgerParser`, Macroeconomic Pulse, Global Real Rate Heatmap, and Securities Watchlist. It features a text-based DSL parser and two-way mutation engine, offline-first Room database cache (`DailyDatabase` v3 with `synced_at` dirty tracking), Yahoo Finance remote API integration via Ktor CIO, modular dashboard widgets across all 4 grid sizes (`1x1 Small`, `2x1 Wide`, `1x2 Tall`, `2x2 Large`), and a dedicated 3-tab Finance Hub (`World`, `Stocks`, `Money`).

---

## 2. Architecture & SmartLedger DSL Engine

### 2.1 Domain Models (`core-model/com.intellidream.daily.model`)
- **`FinanceSubTab`**: `World`, `Stocks`, `Money`.
- **`MarketType`**: `Stock`, `Crypto`, `Forex`.
- **`AccountType`**: `Checking`, `Savings`, `Investment`, `Cash`, `Credit`.
- **`FinanceAccount` & `FinanceTransaction`**: Structured accounts and transactions with category attribution.
- **`StockQuote`**: Ticker symbol, security name, current price, net change, percentage change, day high/low range, and 24h volume.
- **`MacroIndicator`**: Macroeconomic pillar tracking (Crude Oil WTI, Gold, US Dollar Index DXY, Nasdaq 100, Bitcoin, VIX Volatility Index) with numeric price, daily change, and human-friendly contextual `insight` (e.g. *"✨ Energy easing — good for consumers"*, *"✨ Fear rising — investors seeking safety"*).
- **`CountryEconomicData`**: Sovereign economic metrics for 25 countries (Brazil, Mexico, Saudi Arabia, Egypt, UAE, Indonesia, China, South Africa, India, USA, UK, Romania, Poland, France, Thailand, Canada, Sweden, South Korea, Australia, Germany, Switzerland, Turkey, Nigeria, Argentina, Japan) with interest rate, inflation rate, derived `realRate = interestRate - inflationRate`, currency code, and auto-derived national flag emojis.
- **`SmartLedgerItem`**: Single line entry with raw DSL key, parsed category name, raw numeric value, display scaled value in Romanian Lei, optional notes/annotations, destination section, and percentage allocation within its parent section.
- **`SmartLedgerSection`**: Categorized grouping (`Incoming`, `Outgoing`, `Deposit`, etc.) with child items and aggregate sum.
- **`ParsedSmartLedger`**: High-level parsed state containing `totalNetWorth`, `totalDeposits`, `totalLiquid`, `totalIncoming`, `totalOutgoing`, `dentistBudget`, `netSavingsRate`, and categorized sections.
- **`DEFAULT_LEDGER_TEXT`**: Baseline Romanian SmartLedger template seeded on initial launch, matching iOS `SmartLedgerParser.defaultLedgerText`.

### 2.2 SmartLedger DSL Parser & Mutation Engine (`core-model/SmartLedgerParser.kt`)
1:1 Kotlin port of iOS `SmartLedgerParser.swift`:
- **Section Parsing**: Parses Markdown headers (`**Incoming**`, `**Outgoing**`, `**Deposit**`, `**Investments**`, etc.) into structured sections.
- **Shorthand 100x Scaling Heuristic**:
  - Sections appearing before `**Deposit**` (such as `Incoming` and `Outgoing`) use shorthand syntax where 1 unit represents 100 Lei (e.g. `Card = 151` parses to `15.100 Lei`, `Cash = 9` parses to `900 Lei`).
  - Sections from `**Deposit**` onward are unscaled / literal (e.g. `ECO/ME! = 44.000L` parses to `44.000 Lei`, `INT = 53.156,47` parses to `53.156,47 Lei`).
- **Parenthetical Annotation Stripping**: Strips sub-account details inside parentheses `(...)` during numeric extraction so that text like `Card = 151 (Rz/141/Ing/10/Rev/0/Mom/9/!!!!/9)` evaluates strictly to `151`.
- **Romanian Currency Formatting**: Standard European/Romanian number conventions: dot `.` as thousand grouping separator and comma `,` as decimal separator (e.g. `127.156,47 Lei`).
- **Two-Way Mutation Engine**:
  - `adjustItemAmount(rawText, sectionTitle, itemName, delta)`: Dynamically finds and updates an item's numeric amount by adding or subtracting `delta`.
  - `setItemAmount(rawText, sectionTitle, itemName, newAmount)`: Replaces an item's numeric value in place.
  - `addItem(rawText, sectionTitle, itemName, amount, notes)`: Appends a new item under the targeted section header before dividers or totals.
  - `deleteItem(rawText, sectionTitle, itemName)`: Safely removes an item line from the DSL text.
  - `recalculateTotalsInLines(lines)`: Automatically recomputes and replaces `Total = ...` lines for each section.

---

## 3. Offline-First Persistence & Remote Sync

### 3.1 SQLite Room Cache (`core-database`)
- **`SmartLedgerEntity`**:
  - Primary key: `id: String = "primary"`.
  - Schema: `raw_text: String`, `updated_at: Long`, `synced_at: Long?`.
  - Dirty tracking: `synced_at` is set to `null` on local mutation, populated when Supabase ACKs write.
- **`SmartLedgerDao`**:
  - `getSmartLedger(): Flow<SmartLedgerEntity?>`: Hot reactive flow for 120Hz Compose updates.
  - `getUnsyncedLedgers(): List<SmartLedgerEntity>`: Dirty tracking query for background workers.
  - `markSynced(id: String, syncedAt: Long)`: Transitions entity from dirty to synced.
- **`DailyDatabase.kt`**: Bumped to database version 3, registering `SmartLedgerEntity` and `smartLedgerDao()`.
- **`SmartLedgerRepository.kt`**: Central state repository maintaining reactive `rawText: StateFlow<String>` and `parsedLedger: StateFlow<ParsedSmartLedger>`. Seeds `DEFAULT_LEDGER_TEXT` if empty, and commits all mutations through Room.
- **`FinanceDataRepository.kt`**: Manages `activeSubTab: StateFlow<FinanceSubTab>`, 6 Macro Indicators, 25-Country Real Rate Heatmap (sorted descending by `realRate`), and curated multi-asset watchlist.

### 3.2 Remote Cloud Synchronization (`core-network`)
- **`FinanceRemoteService.kt`**:
  - **Yahoo Finance v8 API**: Queries `https://query1.finance.yahoo.com/v8/finance/chart/{symbol}` using Ktor CIO client with timeout and graceful fallback to cached quotes.
  - **Supabase Remote Sync**: Upserts raw ledger text and timestamps to the `smart_ledgers` table.

---

## 4. Visual & UI Components (`app/presentation/finances`)

### 4.1 Master Finance Hub (`FinancesMainView.kt`)
- Top bar with `<` back button and 3-tab capsule switcher: `World`, `Stocks`, `Money` with tactile spring animation and glowing active pill.
- Swipe-to-refresh integration.
- Modal bottom sheets management (`SmartLedgerEditorSheet`, `SmartLedgerQuickAdjustSheet`, `AddLedgerItemSheet`).

### 4.2 Money Tab (`MoneySectionView.kt`)
- **Net Worth Hero Card**: Displays total net worth in Romanian Lei (e.g. `127.156,47 Lei`) with EUR conversion estimate (`~25.431 €`) and `Edit Ledger` pencil button.
- **4 Breakdown Capsules**: `DEPOZITE`, `SOLD`, `INCOMING`, `DENTIST` with distinct color accents.
- **Categorized Sections**: Dynamic cards for `Incoming`, `Outgoing`, `Deposit`, etc. with:
  - Down/Up flow indicator icons.
  - Section total pills.
  - `+ Adaugă` button to append new entries.
  - Item cards displaying category title, notes, percentage progress bar, and formatted Lei amounts.
  - Click-to-adjust interaction opening `SmartLedgerQuickAdjustSheet`.

### 4.3 World Tab (`WorldSectionView.kt`)
- **6 Core Macro Pillars**: Cards for Crude Oil (WTI), Gold, US Dollar Index, Nasdaq 100, Bitcoin, and VIX Volatility with live prices, percentage changes (green/red), and contextual human insights.
- **25-Country Real Rate Heatmap**:
  - Explanatory header with color scale bar (`Negative` crimson to `High Yield` emerald).
  - Clean table with national flag emoji, country name, currency code, Central Bank policy interest rate, inflation rate, and real rate pill badge (`+9.15%` Brazil down to `-1.50%` Nigeria/Turkey).

### 4.4 Stocks & Securities Tab (`StocksSectionView.kt`)
- Market category filter chips: `All`, `Stocks`, `Crypto`, `Forex`.
- Interactive watchlist cards with asset icons, ticker symbols, company names, current price, daily percentage delta pill, 24h Day Range progress bar, and trading volume.

### 4.5 Modal Bottom Sheets
- **`SmartLedgerEditorSheet.kt`**: Full-screen raw DSL editor with live computed net worth preview, line counter badge, `Paste from Clipboard`, `Reset to Baseline`, and `Save & Apply`.
- **`SmartLedgerQuickAdjustSheet.kt`**: Quick adjustment sheet with rapid delta chips (`-10`, `-5`, `-1`, `+1`, `+5`, `+10`), raw DSL value editor, item notes field, and delete confirmation button.
- **`AddLedgerItemSheet.kt`**: New item creator with section picker (`Incoming`, `Outgoing`, `Deposit`), category name, raw DSL amount with live formatted Lei preview, optional notes, and validation.

### 4.6 Modular Dashboard Widget (`FinancesDashboardCard.kt`)
Supports all 4 dashboard sizes:
1. **`1x1 Small`**: Compact Net Worth hero, currency symbol, EUR estimate, and monthly inflow/outflow delta.
2. **`2x1 Wide`**: Net Worth hero, EUR estimate, Monthly Flow (`In 16K Lei · Out 16K Lei`), Deposits breakdown, and `Open Hub >` link.
3. **`1x2 Tall`**: Vertical card featuring Net Worth hero, full Monthly Flow breakdown, Liquid vs Deposit allocation, and key outgoing budget items.
4. **`2x2 Large`**: Master financial command center showing Net Worth hero, Monthly Flow comparison, full breakdown pills, top 3 outgoing expenses, and 3 global macro pillar snapshot pills.

---

## 5. Verification & Physical Device Delivery

### 5.1 Emulator Verification (`Medium_Phone_API_36.1` / `emulator-5558`)
- Tested and visually verified:
  - `FinancesDashboardCard` rendering on main dashboard with live data.
  - Seamless navigation to `FinancesMainView` via bottom capsule ("Money") and dashboard card ("Open Hub >").
  - `World` tab: 6 Macro Pillars with insight badges and 25-Country Real Rate Heatmap table.
  - `Stocks` tab: Filter chips and asset cards with day ranges and trading volume.
  - `Money` tab: Hero Net Worth card, 4 breakdown badges, and categorized item lists.
  - `SmartLedgerEditorSheet`: Live net worth calculation and DSL editing.
  - `SmartLedgerQuickAdjustSheet`: Delta chips and raw input adjustments.
  - `CustomizeDashboardScreen`: Aspect ratio customization (`1x1 Small`, `2x1 Wide`, `1x2 Tall`, `2x2 Large`) and reordering.

### 5.2 Physical Device Verification
- **Google Pixel 9 Pro** (`caiman` / `192.168.3.8:46285`): Installed debug APK (`Success`), launched `com.intellidream.daily.debug/com.intellidream.daily.MainActivity`, verified smooth 120Hz scrolling and Liquid Glass rendering.
- **Samsung Galaxy S25 Edge** (`SM_S937B` / `192.168.3.9:33079`): Installed debug APK (`Performing Streamed Install -> Success`), launched `MainActivity`.
- **iOS Codebase Integrity**: Exactly 0 files in `DailyCore/` or `iOS/` were modified.
