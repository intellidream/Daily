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
- **Service Integration**: The chat relies on `ISmartIntelligenceService`, which abstracts the underlying inference engines (Phi-3, Llama) and properly formats the system prompts with ChatML (`<|user|>`, `<|assistant|>`) to prevent infinite generation loops and hallucination.
- **Natural Language Parsing**: The AI is instructed to reply with a natural language confirmation followed by a strict JSON object (`LedgerCommand` with `action`, `source`, `target`, `amount`).
- **Robust JSON Extraction**: The UI code uses a regex (`@"\{[^{}]*\}"`) to extract the first complete flat JSON object, ignoring any conversational text. The JSON is then executed mathematically against the AST, while the natural language portion is isolated and displayed cleanly in the Chat UI.
- **Auto-Logging**: All interactions are natively captured by `LlmDebugLogger` and visible in `DebugSettingsPage.xaml` under the "AI Debug Diagnostics" panel.

### UI/UX Details
- **Dynamic Layout Stretching**: The Money tab replaces generic scrolling stack panels with nested `Grid` rows (`Height="*"`), allowing the raw text editor and the chat bubble ScrollViewer to stretch fluidly and consume the full available window height without infinitely expanding off-screen.
- **Differentiated Chat Bubbles**: Follows the `SmartBriefing` UI pattern—blue gradient borders for user input and glassy dark styling for the AI response.

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
