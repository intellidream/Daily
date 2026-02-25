-- Creates a temporary table to securely transfer Supabase tokens across the air gap.
create table public.watch_pairings (
    code text primary key,
    access_token text,
    refresh_token text,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Enable Row Level Security to prevent unauthorized access
alter table public.watch_pairings enable row level security;

-- The Watch App (unauthenticated) generates the code and creates the row
create policy "Allow anon insert watch_pairings" on public.watch_pairings for insert to anon with check (true);

-- The Watch App (unauthenticated) polls this row waiting for the tokens
create policy "Allow anon select watch_pairings" on public.watch_pairings for select to anon using (true);

-- The Watch App (unauthenticated) deletes the row after it securely downloads the tokens
create policy "Allow anon delete watch_pairings" on public.watch_pairings for delete to anon using (true);

-- The iPhone App (authenticated) securely injects your active tokens into the row
create policy "Allow auth update watch_pairings" on public.watch_pairings for update to authenticated using (true);
