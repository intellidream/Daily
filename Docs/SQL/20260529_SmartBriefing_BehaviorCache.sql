-- Migration: Support Smart Behavior event tracking and Smart Briefing caching
-- File: Docs/SQL/20260529_SmartBriefing_BehaviorCache.sql

-- 1. Create behavior_events table for user telemetry delta sync
create table if not exists public.behavior_events (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    feature text not null,
    action_type text not null,
    metadata jsonb default '{}'::jsonb not null,
    timestamp timestamp with time zone default now() not null
);

alter table public.behavior_events enable row level security;

-- Row Level Security policies for behavior_events
drop policy if exists "Users see own behavior events" on public.behavior_events;
create policy "Users see own behavior events"
    on public.behavior_events for select
    to authenticated
    using (auth.uid() = user_id);

drop policy if exists "Users insert own behavior events" on public.behavior_events;
create policy "Users insert own behavior events"
    on public.behavior_events for insert
    to authenticated
    with check (auth.uid() = user_id);

drop policy if exists "Users update own behavior events" on public.behavior_events;
create policy "Users update own behavior events"
    on public.behavior_events for update
    to authenticated
    using (auth.uid() = user_id);

drop policy if exists "Users delete own behavior events" on public.behavior_events;
create policy "Users delete own behavior events"
    on public.behavior_events for delete
    to authenticated
    using (auth.uid() = user_id);

-- Indexes for behavior_events
create index if not exists idx_behavior_events_user_id on public.behavior_events(user_id);
create index if not exists idx_behavior_events_timestamp on public.behavior_events(timestamp desc);


-- 2. Create smart_briefings table for cross-device briefing cache
create table if not exists public.smart_briefings (
    user_id uuid primary key references auth.users(id) on delete cascade,
    serialized_data text not null,
    timestamp timestamp with time zone default now() not null
);

alter table public.smart_briefings enable row level security;

-- Row Level Security policies for smart_briefings
drop policy if exists "Users see own smart briefing cache" on public.smart_briefings;
create policy "Users see own smart briefing cache"
    on public.smart_briefings for select
    to authenticated
    using (auth.uid() = user_id);

drop policy if exists "Users insert own smart briefing cache" on public.smart_briefings;
create policy "Users insert own smart briefing cache"
    on public.smart_briefings for insert
    to authenticated
    with check (auth.uid() = user_id);

drop policy if exists "Users update own smart briefing cache" on public.smart_briefings;
create policy "Users update own smart briefing cache"
    on public.smart_briefings for update
    to authenticated
    using (auth.uid() = user_id);

drop policy if exists "Users delete own smart briefing cache" on public.smart_briefings;
create policy "Users delete own smart briefing cache"
    on public.smart_briefings for delete
    to authenticated
    using (auth.uid() = user_id);
