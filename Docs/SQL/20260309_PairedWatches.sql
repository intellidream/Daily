-- Persistent record of paired watches so the main app can:
--   • show which watches are currently paired
--   • unpair (soft-delete) a watch
--   • push fresh tokens to a specific watch ("repair")
--
-- The existing watch_pairings table remains as the SHORT-LIVED handshake channel.
-- This new table is the LONG-LIVED pairing registry.

create table if not exists public.paired_watches (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    platform text not null check (platform in ('watchos', 'wearos', 'harmonyos')),
    device_name text,                               -- e.g. "Apple Watch Series 9", "Pixel Watch 2", "HarmonyOS Watch"
    paired_at timestamp with time zone default now() not null,
    last_token_push timestamp with time zone default now(),
    -- When the main app pushes fresh tokens for "repair", it writes them here.
    -- The watch polls this row (just like watch_pairings) and picks them up.
    pending_access_token text,
    pending_refresh_token text,
    is_active boolean default true not null
);

alter table public.paired_watches enable row level security;

-- Update platform check constraint to include harmonyos (idempotent)
alter table public.paired_watches drop constraint if exists paired_watches_platform_check;
alter table public.paired_watches add constraint paired_watches_platform_check
    check (platform in ('watchos', 'wearos', 'harmonyos'));

-- Users can only see their own paired watches
drop policy if exists "Users see own paired watches" on public.paired_watches;
create policy "Users see own paired watches"
    on public.paired_watches for select
    to authenticated
    using (auth.uid() = user_id);

-- Users can insert their own pairings
drop policy if exists "Users insert own paired watches" on public.paired_watches;
create policy "Users insert own paired watches"
    on public.paired_watches for insert
    to authenticated
    with check (auth.uid() = user_id);

-- Users can update their own pairings (unpair, push tokens)
drop policy if exists "Users update own paired watches" on public.paired_watches;
create policy "Users update own paired watches"
    on public.paired_watches for update
    to authenticated
    using (auth.uid() = user_id);

-- Users can delete their own pairings
drop policy if exists "Users delete own paired watches" on public.paired_watches;
create policy "Users delete own paired watches"
    on public.paired_watches for delete
    to authenticated
    using (auth.uid() = user_id);

-- Watch apps (anon) can read pending tokens for their own device by id
-- They need this to pick up fresh tokens on "repair"
drop policy if exists "Anon select paired watches by id" on public.paired_watches;
create policy "Anon select paired watches by id"
    on public.paired_watches for select
    to anon
    using (true);

-- Watch apps (anon) can clear the pending tokens after consuming them
drop policy if exists "Anon update paired watches clear tokens" on public.paired_watches;
create policy "Anon update paired watches clear tokens"
    on public.paired_watches for update
    to anon
    using (true);

-- Index for fast lookups by user
create index if not exists idx_paired_watches_user_id on public.paired_watches(user_id);

-- RPC functions for watch apps that lack HTTP PATCH support (HarmonyOS).
-- These are callable via POST to /rest/v1/rpc/<name>.

-- Deactivate a paired watch record (used by watch logout)
create or replace function public.deactivate_paired_watch(watch_id uuid)
returns void
language sql
security definer
as $$
  update public.paired_watches
  set is_active = false
  where id = watch_id;
$$;

-- Clear pending repair tokens after the watch has consumed them
create or replace function public.clear_repair_tokens(watch_id uuid)
returns void
language sql
security definer
as $$
  update public.paired_watches
  set pending_access_token = null,
      pending_refresh_token = null
  where id = watch_id;
$$;
