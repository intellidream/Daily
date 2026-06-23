# Smart Ledger Transactions

## Overview
The Smart Ledger now tracks transactions to create an immutable audit trail of changes. Every time a chat command triggers a transfer or modification (e.g., "spent 5 at Mega"), the system records a transaction representing the action. This ensures historical traceability.

## Data Models
- **Remote Model**: `LedgerTransaction` (Supabase `ledger_transactions` table)
- **Local Model**: `LocalLedgerTransaction` (SQLite `local_ledger_transactions` table)

## Key Components
- **ActionType**: The type of operation performed (e.g., "transfer", "expense").
- **Source**: The account or category where the money originated (e.g., "Cash").
- **Target**: The account or category where the money went (e.g., "Mega").
- **Amount**: The monetary value of the transaction.
- **CreatedAt**: The UTC timestamp of the transaction.

## Sync Mechanism
The transactions are synced incrementally using `PushLedgerTransactionsAsync` and `PullLedgerTransactionsInternalAsync` within the `SyncService`. They rely on the `UpdatedAt/CreatedAt` and `SyncedAt` fields to sync differential changes since the last pull.

## User Interface
A new "History" list has been added to the Finances detail page below the chat input. It displays the recent ledger transactions with:
- Timestamp of the action
- Source and Target text
- The Action Type
- Formatted numerical amount.

An "Analytics" panel has been added on the bottom left. It uses a swipeable FlipView to show multiple Doughnut charts:
- Balances by Account
- Asset Classes (Cash vs Investments)

## Next Steps
In the future, the target limits logic (budgets) could be evaluated historically using this transaction history to show limit adherence over time.

## Database Setup
To set up the remote tracking, execute the following in your Supabase SQL Editor:

```sql
CREATE TABLE public.ledger_transactions (
    id uuid NOT NULL PRIMARY KEY,
    user_id uuid NOT NULL,
    source text NOT NULL DEFAULT '',
    target text NOT NULL DEFAULT '',
    amount numeric NOT NULL DEFAULT 0,
    action_type text NOT NULL DEFAULT '',
    created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now())
);

ALTER TABLE public.ledger_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage their own ledger transactions"
    ON public.ledger_transactions
    FOR ALL
    USING (auth.uid() = user_id);
```

## Recurring Transactions

In addition to regular transactions, the system supports recurring transactions (e.g. daily, weekly, monthly transfers or expenses). 

- **Remote Model**: `RecurringTransaction` (Supabase `recurring_transactions` table)
- **Local Model**: `LocalRecurringTransaction` (SQLite `local_recurring_transactions` table)

When an AI command returns `{"action": "schedule", "frequency": "monthly"}`, the transaction is saved into the recurring table instead of the regular ledger log.

### Processing Engine
The `ProcessRecurringTransactionsAsync` method in `FinancesService` runs on application launch. It checks the `NextRunAt` timestamp of each recurring transaction. If a transaction is due (or overdue), it:
1. Records a standard `LocalLedgerTransaction` for historical traceability.
2. Adjusts the underlying Smart Ledger text using `SmartLedgerParser`.
3. Updates the `NextRunAt` field according to the frequency.
4. Saves the updated ledger.

### Database Setup
To set up the recurring tracking, execute the following in your Supabase SQL Editor:

```sql
CREATE TABLE public.recurring_transactions (
    id uuid NOT NULL PRIMARY KEY,
    user_id uuid NOT NULL,
    source text NOT NULL DEFAULT '',
    target text NOT NULL DEFAULT '',
    amount numeric NOT NULL DEFAULT 0,
    action_type text NOT NULL DEFAULT '',
    frequency text NOT NULL DEFAULT 'monthly',
    next_run_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
    created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
    is_deleted boolean NOT NULL DEFAULT false
);

ALTER TABLE public.recurring_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage their own recurring transactions"
    ON public.recurring_transactions
    FOR ALL
    USING (auth.uid() = user_id);
```
