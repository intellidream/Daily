create table if not exists public.smart_ledgers (
    id uuid primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    ledger_text text not null,
    created_at timestamp with time zone default now() not null,
    updated_at timestamp with time zone default now() not null
);

-- RLS
alter table public.smart_ledgers enable row level security;
create policy "Users can view own smart ledgers" on public.smart_ledgers for select using (auth.uid() = user_id);
create policy "Users can insert own smart ledgers" on public.smart_ledgers for insert with check (auth.uid() = user_id);
create policy "Users can update own smart ledgers" on public.smart_ledgers for update using (auth.uid() = user_id);
create policy "Users can delete own smart ledgers" on public.smart_ledgers for delete using (auth.uid() = user_id);
