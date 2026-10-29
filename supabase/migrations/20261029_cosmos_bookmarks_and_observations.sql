-- Migration: 20261029_cosmos_bookmarks_and_observations.sql
-- Description: Create cosmos_bookmarks and cosmos_observations tables with RLS policies and Realtime sync
-- for cross-platform Night Sky Observatory bookmarks and logged sky sightings (iOS, macOS, Android, WinUI).

begin;

-- 1. Create cosmos_bookmarks table
create table if not exists public.cosmos_bookmarks (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    object_id text not null,
    object_name text not null,
    category text not null default 'star',
    ra_hours double precision,
    dec_deg double precision,
    magnitude double precision,
    constellation text,
    notes text default '' not null,
    created_at timestamptz default now() not null,
    updated_at timestamptz default now() not null,
    constraint cosmos_bookmarks_user_object_unique unique (user_id, object_id)
);

create index if not exists idx_cosmos_bookmarks_user_id on public.cosmos_bookmarks(user_id);
create index if not exists idx_cosmos_bookmarks_updated_at on public.cosmos_bookmarks(updated_at desc);

-- 2. Create cosmos_observations table
create table if not exists public.cosmos_observations (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    object_id text not null,
    object_name text not null,
    category text not null default 'star',
    observed_at timestamptz default now() not null,
    latitude double precision not null,
    longitude double precision not null,
    location_name text default '' not null,
    azimuth_deg double precision,
    altitude_deg double precision,
    bortle_class smallint check (bortle_class between 1 and 9),
    stargazing_score smallint check (stargazing_score between 0 and 100),
    optics text default 'Naked Eye' not null,
    notes text default '' not null,
    tagdos_note_id uuid references public.tagdos_quick_notes(id) on delete set null,
    created_at timestamptz default now() not null,
    updated_at timestamptz default now() not null
);

create index if not exists idx_cosmos_observations_user_id on public.cosmos_observations(user_id);
create index if not exists idx_cosmos_observations_observed_at on public.cosmos_observations(observed_at desc);

-- 3. Enable Row Level Security (RLS)
alter table public.cosmos_bookmarks enable row level security;
alter table public.cosmos_observations enable row level security;

-- RLS policies for cosmos_bookmarks
drop policy if exists "Users can select own cosmos_bookmarks" on public.cosmos_bookmarks;
create policy "Users can select own cosmos_bookmarks"
    on public.cosmos_bookmarks for select
    to authenticated
    using ((select auth.uid()) = user_id);

drop policy if exists "Users can insert own cosmos_bookmarks" on public.cosmos_bookmarks;
create policy "Users can insert own cosmos_bookmarks"
    on public.cosmos_bookmarks for insert
    to authenticated
    with check ((select auth.uid()) = user_id);

drop policy if exists "Users can update own cosmos_bookmarks" on public.cosmos_bookmarks;
create policy "Users can update own cosmos_bookmarks"
    on public.cosmos_bookmarks for update
    to authenticated
    using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);

drop policy if exists "Users can delete own cosmos_bookmarks" on public.cosmos_bookmarks;
create policy "Users can delete own cosmos_bookmarks"
    on public.cosmos_bookmarks for delete
    to authenticated
    using ((select auth.uid()) = user_id);

-- RLS policies for cosmos_observations
drop policy if exists "Users can select own cosmos_observations" on public.cosmos_observations;
create policy "Users can select own cosmos_observations"
    on public.cosmos_observations for select
    to authenticated
    using ((select auth.uid()) = user_id);

drop policy if exists "Users can insert own cosmos_observations" on public.cosmos_observations;
create policy "Users can insert own cosmos_observations"
    on public.cosmos_observations for insert
    to authenticated
    with check ((select auth.uid()) = user_id);

drop policy if exists "Users can update own cosmos_observations" on public.cosmos_observations;
create policy "Users can update own cosmos_observations"
    on public.cosmos_observations for update
    to authenticated
    using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);

drop policy if exists "Users can delete own cosmos_observations" on public.cosmos_observations;
create policy "Users can delete own cosmos_observations"
    on public.cosmos_observations for delete
    to authenticated
    using ((select auth.uid()) = user_id);

-- 4. Enable Supabase Realtime publication safely
do $$
begin
    if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'cosmos_bookmarks'
    ) then
        alter publication supabase_realtime add table public.cosmos_bookmarks;
    end if;

    if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'cosmos_observations'
    ) then
        alter publication supabase_realtime add table public.cosmos_observations;
    end if;
end $$;

commit;
