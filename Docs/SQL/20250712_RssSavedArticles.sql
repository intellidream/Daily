-- RSS Saved Articles (Read Later & Favorites)
-- Stores articles the user saves for later reading or marks as favorite.
-- Synced across all platforms (Win/Mac/iOS/Android) via the app's SyncService.

create table if not exists public.rss_saved_articles (
	id uuid primary key default gen_random_uuid(),
	user_id uuid not null references auth.users(id) on delete cascade,
	article_url text not null,
	title text not null default '',
	image_url text,
	description text,
	author text,
	publication_name text not null default '',
	publication_icon_url text,
	article_type text not null default 'ReadLater' check (article_type in ('ReadLater', 'Favorite')),
	article_date timestamp with time zone not null default now(),
	created_at timestamp with time zone not null default now(),
	updated_at timestamp with time zone,
	is_deleted boolean not null default false
);

alter table public.rss_saved_articles enable row level security;

-- Users can only see their own saved articles
drop policy if exists "Users see own saved articles" on public.rss_saved_articles;
create policy "Users see own saved articles"
	on public.rss_saved_articles for select
	to authenticated
	using (auth.uid() = user_id);

-- Users can insert their own saved articles
drop policy if exists "Users insert own saved articles" on public.rss_saved_articles;
create policy "Users insert own saved articles"
	on public.rss_saved_articles for insert
	to authenticated
	with check (auth.uid() = user_id);

-- Users can update their own saved articles (soft-delete, etc.)
drop policy if exists "Users update own saved articles" on public.rss_saved_articles;
create policy "Users update own saved articles"
	on public.rss_saved_articles for update
	to authenticated
	using (auth.uid() = user_id);

-- Users can delete their own saved articles
drop policy if exists "Users delete own saved articles" on public.rss_saved_articles;
create policy "Users delete own saved articles"
	on public.rss_saved_articles for delete
	to authenticated
	using (auth.uid() = user_id);

-- Indexes for fast lookups
create index if not exists idx_rss_saved_articles_user_id on public.rss_saved_articles(user_id);
create index if not exists idx_rss_saved_articles_user_type on public.rss_saved_articles(user_id, article_type);
create index if not exists idx_rss_saved_articles_user_url on public.rss_saved_articles(user_id, article_url);
