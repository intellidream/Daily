-- Update platform check constraint to include zeppos
alter table public.paired_watches drop constraint if exists paired_watches_platform_check;
alter table public.paired_watches add constraint paired_watches_platform_check
    check (platform in ('watchos', 'wearos', 'harmonyos', 'zeppos'));
