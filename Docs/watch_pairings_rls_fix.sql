-- The iPhone app (authenticated) needs permission to SELECT the row before it can UPDATE the row
create policy "Allow auth select watch_pairings" on public.watch_pairings for select to authenticated using (true);
