-- Create Vitals Table
create table if not exists public.vitals (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references auth.users not null,
  type text not null,
  value double precision not null,
  unit text,
  date date not null,
  source_device text,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null,
  
  -- Unique constraint to ensure one metric per type per day per user
  constraint vitals_user_date_type_key unique (user_id, date, type)
);

-- Enable Row Level Security
alter table public.vitals enable row level security;

-- Policies
drop policy if exists "Users can view own vitals" on public.vitals;
create policy "Users can view own vitals" on public.vitals
  for select using ((select auth.uid()) = user_id);

drop policy if exists "Users can insert own vitals" on public.vitals;
create policy "Users can insert own vitals" on public.vitals
  for insert with check ((select auth.uid()) = user_id);

drop policy if exists "Users can update own vitals" on public.vitals;
create policy "Users can update own vitals" on public.vitals
  for update using ((select auth.uid()) = user_id);

-- Grant access to authenticated users
grant all on public.vitals to authenticated;
grant all on public.vitals to service_role;
