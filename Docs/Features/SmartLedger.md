# Smart Ledger Feature

## Overview
The Smart Ledger is a text-based, unorthodox way to manage personal finances in the Daily app. It replaces the traditional tabular accounts and investments views in the Finances tab with a simple text editor and an integrated AI chat.

The user maintains a ledger text document containing categories, abbreviations, and numeric values. The app parses this text, automatically recalculates totals, and syncs the text via SQLite and Supabase.

## Architecture

### Data Layer
- **Local Model**: `LocalSmartLedger` in SQLite (`local_smart_ledgers` table). Contains `LedgerText`, `CreatedAt`, `UpdatedAt`, `SyncedAt`.
- **Remote Model**: `SmartLedger` in Supabase (`smart_ledgers` table).
- **Syncing**: Managed via `SyncService` which pushes/pulls changes automatically.

### Parsing Engine
- `SmartLedgerParser` (C# AST): Parses the text document to extract headers (Net Worth, Cash, Investments).
- Recognizes structural blocks like `**Incoming**` and `**Outgoing**`.
- Automatically recalculates section sums and balances using Regex.

### AI Integration & Chat
- `ISmartBriefingEngine` evaluates natural language inputs (e.g. "I spent 5 at Mega").
- Output is strictly formatted as JSON (`LedgerCommand` with `action`, `source`, `target`, `amount`).
- The parser interprets the JSON, finds the text lines for `source` and `target`, applies the `amount` mathematically, and replaces the string values dynamically.
- Auto-calculation runs immediately after to ensure `Total` and `Balance` lines are updated.

## Usage Guide
1. Open the **Daily app** and navigate to the **Finances** -> **Money** pivot.
2. Ensure you have the structural text in place. The AI needs a baseline to work with:
   ```text
   # Calcule
   **Incoming**
   Card = 100
   Cash = 50
   Total = 150

   **Outgoing**
   Food = 0
   Total = 0

   Balance = 150
   ```
3. You can either:
   - Edit the text directly and watch the Totals recalculate.
   - Use the chat box at the bottom to say "I bought Food for 20 using Cash". The AI will subtract 20 from Cash, add 20 to Food, update Totals, and update the Balance.

> [!NOTE]
> For highly specific developer documentation regarding AST parsing and SQLite database sync logic, see [SmartLedgerImpl.md](SmartLedgerImpl.md).
