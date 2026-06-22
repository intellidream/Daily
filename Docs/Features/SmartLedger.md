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
- **Fully Responsive Architecture**: Implemented a rock-solid `VisualStateManager` anchored to the Page root. In wide view (≥850px width), the editor takes the full left column while the Totals and AI Chat securely dock to the right. When narrowed (<850px), the UI morphs into a vertically stacked, mobile-friendly view (Totals -> Editor -> Chat). In this mobile view, the editor is given a strict `500px` minimum height, and the outer layout seamlessly enables vertical window scrolling to ensure no content is crushed.
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

## Logic

> [!NOTE]
> The Smart Ledger uses a strict Double-Entry accounting logic based on a unique Domain Specific Language (DSL).

### The DSL Syntax
The AI and the AST parser adhere to a strict rule separating the **Mathematics** from the **Metadata**:
``text
CategoryName = Value // Aliases, Tags, and Comments
``
- **Math Part**: Everything to the left of // is mathematical. The parser looks here to run additions/subtractions.
- **Metadata Part**: Everything to the right of // is completely ignored by the math parser. It is used as a safe space for human annotations and for the AI to find alias names.

### Example Ledger
``text
# Calcule
**Incoming**
Card = 107 // Rz: 97, Ig: 10, Rv: 0. [Mom: 9, !!!!: 9]
Cash = 0 // [SG-1/A/3M], [MOM/250!]

Total = 107

**Outgoing**
CarTaxes = 0 // Itp, Rvg (4.27). Ghs, Prk, Csc, Rca (1.27)
Subs = 2 // V, N, Y, O, AI, M, W, E, I, Ap, Am, Sy, Ad, Sp
Household = 35 // Prop, Rds, Gaz, �nt, Hid (est 30). Mom (5)
Groceries = 0 // Cora, Mega, Bringo, Fresh. [Edn: 6]
Tigari = 6 // [25/45 packs]
Car = 5 // Benzina, Honda. [1/4 fill-ups] [CER/SPL!]
Serviciu = 0 // Outs. [0/100, 0/200]
Acasa = 10 // Tuns, Cadouri. [M&T=5, !!!!!=5]
Vacante = 49 // Noi, Iesiri, Other. [MOM/250!]

AnnualSubs = 0 // (APL 21.01 $5) (RED 14.03 $1) (CSP 29.05 $5)

Total = 107

**Balance**
Total = 0

**Dentist**
Total = 53 // Dental track

**Deposit**
ECO = 0 // Current account
EUR = 0 // Euro current
ERO = 0 // Euro economies (5-7%)
DEP = 0 // RON economies (2-3%)
BIA = 30000 // GF emergency savings
INT = 139604 // (~27.300E) [-IMP-VER]
``

### AI Prompting Strategy
To prevent AI hallucinations (especially with Small Language Models like Phi):
1. The AI is fed few-shot examples via its System Prompt dictating exactly how to output its Markdown JSON structure.
2. The AI is strictly told not to mutate values to the right of //. 
3. If a user says "I spent 5 on Mega", the AI searches the // comments for "Mega" and outputs {"target": "Mega"}.
4. The C# parser locates the Groceries row because the string "Mega" exists in its metadata, splits the row at //, calculates the math, and re-attaches the comment seamlessly.
