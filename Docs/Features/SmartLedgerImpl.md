# Smart Ledger Implementation Details

This document covers the low-level architectural and technical details of the Smart Ledger feature. It is intended for developers who need to extend the parser, debug synchronization issues, or improve the AI agent integration.

## 1. Data Models & Database

### Local SQLite Database
- **Model**: `LocalSmartLedger` (`Models/Finances/SmartLedgerModels.cs`).
- **Table**: `local_smart_ledgers`.
- **Fields**:
  - `Id` (String Primary Key) - A regular GUID mapped to string.
  - `UserId` (String)
  - `LedgerText` (String) - The raw plain-text DSL.
  - `CreatedAt`, `UpdatedAt`, `SyncedAt` (DateTime)
  - `IsDeleted` (Boolean) - Required for soft deletes during synchronization.

### Supabase Remote Database
- **Model**: `SmartLedger` (Supabase Model).
- **Table**: `smart_ledgers`.
- **Sync Logic**: `SyncService.cs` implements `PushSmartLedgerAsync` and `PullSmartLedgerInternalAsync`.
  - Only the newest `UpdatedAt` timestamp wins.
  - Because it is a text-based document, there is no field-level conflict resolution. The user is assumed to be editing from one primary device at a time, or the last write wins.

## 2. Smart Ledger Parser (AST & Regex)

The core logic that turns the raw text into mathematical totals lives in `Services/Finances/SmartLedgerParser.cs`.

### The DSL Rules
1. **Assignments**: A category and its value are defined with an equals sign. Example: `Card = 108`.
2. **Breakdowns**: Parentheses contain breakdown details and are ignored mathematically by the sum, but they are preserved in the text. Example: `(Rfz/98/Ing/10)`.
3. **Sections**: The parser uses markdown headers to separate sections.
   - `**Incoming**` or `# Incoming`
   - `**Outgoing**` or `# Outgoing`
4. **Calculations**:
   - `Total = X`: Sum of all parsed values in the current section.
   - `Balance = X`: The `Incoming Total` minus the `Outgoing Total`.

### Parsing Pipeline (`RecalculateTotals` method)
1. Reads the text line by line.
2. Identifies the current section based on markdown headers.
3. Uses the Regex `^(.*?)\s*=\s*([\d\.,]+)(.*)$` to find category assignments.
   - Group 1: Name (e.g. `Card`)
   - Group 2: Value (e.g. `108`)
   - Group 3: Remainder (e.g. ` (Rfz/98)`)
4. Accumulates values into `incomingSum` or `outgoingSum`.
5. When encountering a line starting with `Total =`, it overwrites the line with the newly calculated `incomingSum` or `outgoingSum`.
6. When encountering a line starting with `Balance =`, it overwrites it with `incomingSum - outgoingSum`.
7. Returns the newly formulated string.

## 3. UI Integration (`FinancesDetailPage.xaml`)

### Components
- **Editor**: A two-way bound `TextBox` that binds to the `SmartLedgerText` property.
- **Chat**: A `ListView` for message history and a `TextBox` for natural language input.
- **Headers**: A series of text blocks at the top of the UI that bind to properties like `NetWorth`, `CashBalance`, and `InvestmentBalance`. These are extracted using `SmartLedgerParser.ExtractValue(text, "Total")`.

### Lifecycle
1. The UI loads `LocalSmartLedger` via `_financesService.GetSmartLedgerAsync()`.
2. When the user types into the editor, the `TextChanged` event triggers `RecalculateTotals` through a debouncer.
3. The recalculated text is set back to the editor, and `_financesService.SaveSmartLedgerAsync()` saves the text locally.
4. Sync happens in the background.

## 4. AI Engine Integration

The feature uses the SLM (Small Language Model) pipeline `ISmartBriefingEngine` to parse natural language instructions into concrete mathematical edits.

### Prompting Strategy
When the user types an instruction (e.g., "I spent 15 on food from Cash"), the code injects a hidden system prompt to the AI:
```json
// The AI is strictly instructed to return a JSON object:
{
  "action": "transfer",
  "source": "Cash",
  "target": "Food",
  "amount": 15
}
```

### Execution (`ProcessLedgerCommand`)
Once the JSON is successfully parsed from the AI's response:
1. The system identifies the `source` line in the text and subtracts the `amount`.
2. It identifies the `target` line and adds the `amount`.
3. It calls `SmartLedgerParser.RecalculateTotals()` to update the `Total` and `Balance` lines.
4. It refreshes the `TextBox` with the new text.

## 5. Continuing Development on Another Machine

To pick up development on another machine:
1. Ensure the SQLite schema includes the `local_smart_ledgers` table. If not, the automatic EF Core / SQLite init should create it based on `FinanceModels.cs`.
2. Ensure the Supabase database has the `smart_ledgers` table with identical columns (`id`, `user_id`, `ledger_text`, `created_at`, `updated_at`, `synced_at`, `is_deleted`). RLS policies must allow authenticated select/insert/update.
3. Open `Daily.WinUI.csproj` and ensure `Services\Finances\SmartLedgerParser.cs` is properly referenced as a linked compile target.
4. If testing the AI, ensure the `ISmartBriefingEngine` (like `LLamaUniversalEngine`) is loaded and has access to the local weights. If weights are missing, the AI chat will throw a missing service or model error.

## 6. Future Architectural Considerations
- **Version History**: We currently overwrite the single text entry. Implementing a text history or diff log could prevent accidental data loss.
- **Language Independence**: The regex is currently hardcoded to look for `Total` and `Balance`. For full i18n, these keywords might need to be customizable or dynamic.
- **Complex AI Math**: If the user asks the AI "I spent half my cash", the SLM needs to be fed the *current* cash value in the prompt context so it can compute `amount`, or the `ProcessLedgerCommand` needs to handle fractional instructions.
