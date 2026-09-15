-- Migration: 20260915_tagdos_notes.sql
-- Description: Create tagdos_streams and tagdos_quick_notes tables, RLS policies, Realtime publication, and storage bucket.

-- 1. Create tagdos_streams table
create table if not exists public.tagdos_streams (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    stream_number integer not null,
    title text not null default '',
    raw_syntax text not null default '',
    reminder_time text,
    active_memos text default '',
    attachments jsonb default '[]'::jsonb,
    created_at timestamptz default now() not null,
    updated_at timestamptz default now() not null,
    constraint tagdos_streams_user_stream_unique unique (user_id, stream_number)
);

-- Index for rapid lookup by user
create index if not exists idx_tagdos_streams_user_id on public.tagdos_streams(user_id);

-- 2. Create tagdos_quick_notes table
create table if not exists public.tagdos_quick_notes (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    title text not null default '',
    content text not null default '',
    is_pinned boolean default false not null,
    tags text[] default '{}'::text[],
    created_at timestamptz default now() not null,
    updated_at timestamptz default now() not null
);

-- Index for rapid lookup by user and updated_at
create index if not exists idx_tagdos_quick_notes_user_id on public.tagdos_quick_notes(user_id);
create index if not exists idx_tagdos_quick_notes_updated_at on public.tagdos_quick_notes(updated_at desc);

-- 3. Row Level Security (RLS)
alter table public.tagdos_streams enable row level security;
alter table public.tagdos_quick_notes enable row level security;

-- Policies for tagdos_streams
drop policy if exists "Users can select own tagdos_streams" on public.tagdos_streams;
create policy "Users can select own tagdos_streams" on public.tagdos_streams
    for select using (auth.uid() = user_id);

drop policy if exists "Users can insert own tagdos_streams" on public.tagdos_streams;
create policy "Users can insert own tagdos_streams" on public.tagdos_streams
    for insert with check (auth.uid() = user_id);

drop policy if exists "Users can update own tagdos_streams" on public.tagdos_streams;
create policy "Users can update own tagdos_streams" on public.tagdos_streams
    for update using (auth.uid() = user_id);

drop policy if exists "Users can delete own tagdos_streams" on public.tagdos_streams;
create policy "Users can delete own tagdos_streams" on public.tagdos_streams
    for delete using (auth.uid() = user_id);

-- Policies for tagdos_quick_notes
drop policy if exists "Users can select own tagdos_quick_notes" on public.tagdos_quick_notes;
create policy "Users can select own tagdos_quick_notes" on public.tagdos_quick_notes
    for select using (auth.uid() = user_id);

drop policy if exists "Users can insert own tagdos_quick_notes" on public.tagdos_quick_notes;
create policy "Users can insert own tagdos_quick_notes" on public.tagdos_quick_notes
    for insert with check (auth.uid() = user_id);

drop policy if exists "Users can update own tagdos_quick_notes" on public.tagdos_quick_notes;
create policy "Users can update own tagdos_quick_notes" on public.tagdos_quick_notes
    for update using (auth.uid() = user_id);

drop policy if exists "Users can delete own tagdos_quick_notes" on public.tagdos_quick_notes;
create policy "Users can delete own tagdos_quick_notes" on public.tagdos_quick_notes
    for delete using (auth.uid() = user_id);

-- 4. Enable Supabase Realtime for instant multi-device sync
alter publication supabase_realtime add table public.tagdos_streams;
alter publication supabase_realtime add table public.tagdos_quick_notes;

-- 5. Storage Bucket for per-stream file/photo attachments
insert into storage.buckets (id, name, public)
values ('tagdos-attachments', 'tagdos-attachments', false)
on conflict (id) do nothing;

-- Storage RLS policies for tagdos-attachments
create policy "Users can upload own tagdos attachments"
on storage.objects for insert
with check (
    bucket_id = 'tagdos-attachments' and
    auth.uid()::text = (storage.foldername(name))[1]
);

create policy "Users can view own tagdos attachments"
on storage.objects for select
using (
    bucket_id = 'tagdos-attachments' and
    auth.uid()::text = (storage.foldername(name))[1]
);

create policy "Users can update own tagdos attachments"
on storage.objects for update
using (
    bucket_id = 'tagdos-attachments' and
    auth.uid()::text = (storage.foldername(name))[1]
);

create policy "Users can delete own tagdos attachments"
on storage.objects for delete
using (
    bucket_id = 'tagdos-attachments' and
    auth.uid()::text = (storage.foldername(name))[1]
);
