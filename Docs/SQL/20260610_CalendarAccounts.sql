-- Create calendar_accounts table for cloud synchronization
create table if not exists public.calendar_accounts (
    id uuid primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    account_type text not null,                       -- 'Google', 'MicrosoftPersonal', 'MicrosoftWork', 'Yahoo'
    email text not null,
    access_token text not null,                       -- Stored AES-GCM encrypted
    refresh_token text,                               -- Stored AES-GCM encrypted
    token_expires_at timestamp with time zone not null,
    color text not null default '#FF594AE2',
    is_active boolean not null default true,
    created_at timestamp with time zone default now() not null,
    updated_at timestamp with time zone default now() not null
);

-- Enable Row Level Security
alter table public.calendar_accounts enable row level security;

-- Index for fast user synchronization queries
create index if not exists idx_calendar_accounts_user_id on public.calendar_accounts(user_id);

-- Policies
-- 1. Users can view their own calendar accounts
drop policy if exists "Users can view own calendar accounts" on public.calendar_accounts;
create policy "Users can view own calendar accounts"
    on public.calendar_accounts for select
    to authenticated
    using (auth.uid() = user_id);

-- 2. Users can insert their own calendar accounts
drop policy if exists "Users can insert own calendar accounts" on public.calendar_accounts;
create policy "Users can insert own calendar accounts"
    on public.calendar_accounts for insert
    to authenticated
    with check (auth.uid() = user_id);

-- 3. Users can update their own calendar accounts
drop policy if exists "Users can update own calendar accounts" on public.calendar_accounts;
create policy "Users can update own calendar accounts"
    on public.calendar_accounts for update
    to authenticated
    using (auth.uid() = user_id);

-- 4. Users can delete their own calendar accounts
drop policy if exists "Users can delete own calendar accounts" on public.calendar_accounts;
create policy "Users can delete own calendar accounts"
    on public.calendar_accounts for delete
    to authenticated
    using (auth.uid() = user_id);

-- Add to Realtime replication publication (for instant sync across clients)
alter publication supabase_realtime add table public.calendar_accounts;
