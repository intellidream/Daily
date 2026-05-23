# Feature: Finances (Accounts, Transactions & Portfolio)

The Finances feature provides an integrated ledger system for tracking bank accounts, transaction logs, stock portfolios, security watchlists, and global market heatmaps.

---

## 1. Functional Specification

### 1.1 Ledger Accounts & Transactions
- **Multiple Account Types**: Supports checking, savings, credit card, and investment accounts. Each account is assigned a user currency and maintains a rolling balance.
- **Transaction Entry**: Users can log transactions (income or expenses) by entering the date, amount, category, and description. Adding or removing a transaction automatically triggers database updates to recalculate the parent account's balance.

### 1.2 Portfolio Holdings & Watchlist
- **Security Holdings**: Tracks investment assets by storing the symbol, quantity, and cost basis. It combines security records with real-time stock prices to calculate current value and unrealized gains/losses.
- **Asset Net Worth**: Calculates the user's total net worth by aggregating checking/savings balances, subtracting credit card liabilities, and adding the current market value of security holdings.
- **Watchlist**: Users can pin stock ticker symbols (e.g. `AAPL`, `MSFT`) to a watchlist, which pulls real-time quotes (price, change, and percentage change).

### 1.3 Market Quotes API Integration
- **Real-Time Data**: Integrates with financial data APIs (via Yahoo Finance and Finnhub clients) to download active market prices, daily highs/lows, trading volume, and market caps.
- **Logo Acquisition**: The system automatically generates company logos for watchlisted securities using a symbol/name-to-logo lookup helper.

---

## 2. Technical Architecture & Data Model

### 2.1 Services & Dependency Injection
- `IFinancesService` / `FinancesService`: Coordinates account details, transaction lists, and portfolio calculations.
- `YahooFinanceService` / `FinnhubService`: HttpClients that fetch real-time financial market quotes.
- `MacroService` / `HeatmapService`: Provides economic indicator summaries and stock asset weight heatmaps.
- `ISyncService`: Handles background synchronization between local SQLite tables and Supabase.

### 2.2 Data Models & Schema
Finances data utilizes separate SQLite local structures and Supabase remote databases.

#### SQLite Local Tables (`Models/Finances/FinanceModels.cs`)
- **`LocalAccount`** (Mapped to Supabase `accounts` table):
  - `Id` (String Primary Key)
  - `UserId` (String)
  - `Name` (String)
  - `Type` (String: `'checking'`, `'savings'`, `'credit'`, `'investment'`)
  - `Currency` (String)
  - `CurrentBalance` (Decimal)
  - `CreatedAt` / `UpdatedAt` / `SyncedAt` (DateTime)
  - `IsDeleted` (Boolean)
- **`LocalTransaction`** (Mapped to Supabase `transactions` table):
  - `Id` (String Primary Key)
  - `AccountId` (String Foreign Key)
  - `Date` (DateTime)
  - `Amount` (Decimal)
  - `Category` (String)
  - `Description` (String)
  - `CreatedAt` / `UpdatedAt` / `SyncedAt` (DateTime)
  - `IsDeleted` (Boolean)
- **`LocalSecurity`** (Mapped to Supabase `securities` table):
  - `Symbol` (String Primary Key)
  - `Name` (String)
  - `Type` (String)
  - `LatestPrice` (Decimal)
  - `Change` / `PercentChange` (Decimal)
  - `LastUpdatedAt` (DateTime)
  - `LogoUrl` / `Currency` / `Exchange` (String)
- **`LocalHolding`** (Mapped to Supabase `holdings` table):
  - `Id` (String Primary Key)
  - `AccountId` (String)
  - `SecuritySymbol` (String)
  - `Quantity` / `CostBasis` (Decimal)
  - `CreatedAt` / `UpdatedAt` / `SyncedAt` (DateTime)
- **`LocalWatchlist`** (Mapped to Supabase `watchlists` table):
  - `Id` (String Primary Key)
  - `UserId` (String)
  - `Symbol` (String)
  - `DisplayOrder` (Integer)

---

## 3. UI/UX & Layout

### 3.1 Account Grids & Portfolio Details
- **Balance Cards**: Styled cards that display account name, type, and current balance.
- **Transaction Ledger**: A searchable grid table that filters transactions by category, account, or date ranges.
- **World Map Visuals**: In WinUI, a custom `WorldMapControl.xaml` displays global market locations and indicators.

---

## 4. Platform Implementation Differences (WinUI vs. MAUI / Blazor Hybrid)

| Characteristic | WinUI Implementation | MAUI / Blazor Hybrid Implementation |
| :--- | :--- | :--- |
| **UI Technology** | Native XAML Controls (`FinancesWidgetControl.xaml` & `FinancesDetailPage.xaml`) | Blazor Hybrid Razor components (`FinancesWidget.razor` & `FinancesDetail.razor`) |
| **Data Binding** | `ObservableCollection<LocalAccount>` and XAML DataTemplates | Blazor model list bindings with standard C# loops (`@foreach`) |
| **World Map Control** | Custom map layout using WinUI XAML shapes (`WorldMapControl.xaml`) | Simplified statistics indicators or Blazor visual maps |
| **Ledger Management** | Master-Detail Grid displays using WinUI stack panels | MudBlazor tables (`MudTable`) with inline row templates |
| **Add Transaction Dialog** | Uses custom `ContentDialog` panels defined in WinUI code-behind | Uses MudBlazor dialog service overlay components |
