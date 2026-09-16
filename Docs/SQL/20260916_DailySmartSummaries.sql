-- Migration: Next-Gen Cross-Platform Smart Summaries (iOS, macOS, Android, WinUI)
-- File: Docs/SQL/20260916_DailySmartSummaries.sql

-- 1. Create daily_smart_summaries table
create table if not exists public.daily_smart_summaries (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    time_slot text not null, -- 'morning', 'intraday', 'evening', 'nightly'
    data_hash text not null,
    narrative jsonb not null default '{}'::jsonb,
    metrics jsonb not null default '{}'::jsonb,
    created_at timestamp with time zone default now() not null,
    updated_at timestamp with time zone default now() not null,
    constraint daily_smart_summaries_user_slot_key unique (user_id, time_slot)
);

-- 2. Enable Row Level Security
alter table public.daily_smart_summaries enable row level security;

-- 3. Row Level Security policies
drop policy if exists "Users see own smart summaries" on public.daily_smart_summaries;
create policy "Users see own smart summaries"
    on public.daily_smart_summaries for select
    to authenticated
    using (auth.uid() = user_id);

drop policy if exists "Users insert own smart summaries" on public.daily_smart_summaries;
create policy "Users insert own smart summaries"
    on public.daily_smart_summaries for insert
    to authenticated
    with check (auth.uid() = user_id);

drop policy if exists "Users update own smart summaries" on public.daily_smart_summaries;
create policy "Users update own smart summaries"
    on public.daily_smart_summaries for update
    to authenticated
    using (auth.uid() = user_id);

drop policy if exists "Users delete own smart summaries" on public.daily_smart_summaries;
create policy "Users delete own smart summaries"
    on public.daily_smart_summaries for delete
    to authenticated
    using (auth.uid() = user_id);

-- 4. Indexes for performance
create index if not exists idx_daily_smart_summaries_user_slot on public.daily_smart_summaries(user_id, time_slot);
create index if not exists idx_daily_smart_summaries_updated_at on public.daily_smart_summaries(updated_at desc);
