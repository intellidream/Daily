-- 1. Create the table
create table public.habits_daily_summaries (
  id uuid not null primary key,
  user_id uuid references auth.users not null default auth.uid(), -- Added default for convenience
  habit_type text not null,
  date timestamp with time zone not null,
  total_value double precision not null default 0,
  log_count integer not null default 0,
  metadata text,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone
);

-- 2. Enable RLS
alter table public.habits_daily_summaries enable row level security;

-- 3. Create Policies
-- Note: Using (select auth.uid()) wrapping as requested to suppress warnings

create policy "Users can view their own summaries"
on public.habits_daily_summaries for select
using ( (select auth.uid()) = user_id );

create policy "Users can insert their own summaries"
on public.habits_daily_summaries for insert
with check ( (select auth.uid()) = user_id );

create policy "Users can update their own summaries"
on public.habits_daily_summaries for update
using ( (select auth.uid()) = user_id );

create policy "Users can delete their own summaries"
on public.habits_daily_summaries for delete
using ( (select auth.uid()) = user_id );

-- 4. Create Index
create index idx_summaries_user_date on public.habits_daily_summaries(user_id, date);
