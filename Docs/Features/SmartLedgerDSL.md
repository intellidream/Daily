# Smart Ledger DSL

The Smart Ledger Domain-Specific Language (DSL) allows for generic financial planning and asset tracking within a plain-text document. The parser automatically tracks assets, values, goals, and streams live data between the UI and local persistence.

## Core Syntax

### 1. Variables and Assignment
Assign values to tags simply using the equals sign (`=`).
```text
Groceries = 50
Entertainment = 100
```

### 2. Goals and Financial Planning
To specify a financial target or a yield (APY%), use the target arrow `=>` or slash `/`. The parser treats the left side as the core value.
```text
EmergencyFund = 5000 => 10000 (+4.5%)
Vacation = 1500 / 2000
```

### 3. Asset Tracking (Quantity @ Price)
For investments or other assets, specify the quantity, the `@` symbol, and the price. The parser automatically multiplies the quantity by the price to calculate the net worth value.
```text
TechStocks = 10 @ 415.50
Gold = 2.5 oz @ 2100
```

### 4. Tagging
Append comments starting with `//` to the end of any line to add metadata tags (`#`).
```text
TechStocks = 10 @ 415.50 // #ticker:MSFT
EmergencyFund = 5000 => 10000 // #goal
```

## How It Works Under The Hood
- **Regex Parsing:** `Daily.Services.Finances.SmartLedgerParser` reads line-by-line and extracts values.
- **`ParseValue` pipeline:** Automatically identifies whether a value is an Asset (`10 @ 415.50`) or a Goal (`5000 => 10000`) and evaluates to the correct numerical decimal.
- **Suffix Preservation:** When an AI transaction occurs (e.g. `{"action": "buy", "target": "TechStocks", "amount": 2}`), the parser correctly adds the quantity (`10 + 2 = 12`) and dynamically reconstructs the suffix (`= 12 @ 415.50 // #ticker:MSFT`) without deleting your custom notes.

## Sections
The ledger requires specific section headers to calculate Net Worth properly:
- `**Incoming**`: Liquid assets (Cash, Checking).
- `**Deposit**` or `**Investments**`: Illiquid assets or brokers.
- `**Outgoing**`: Liabilities, credit cards.

## Flow Notation
Double-entry transactions are intrinsically supported by the application via the local SQLite `LedgerTransactions` table. Every natural-language interaction logged into the UI resolves to a transaction:
`Source -> Target : Amount`

This ensures that the ledger text maintains a clean "state snapshot" while still preserving a robust immutable transaction history.
