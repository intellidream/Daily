-- 1. SECURITIES (Safe Migration - Preserves Dependencies)
-- Create table if it doesn't exist
CREATE TABLE IF NOT EXISTS securities (
    symbol text primary key
);

-- Idempotently add/update columns
ALTER TABLE securities ADD COLUMN IF NOT EXISTS name text;
ALTER TABLE securities ADD COLUMN IF NOT EXISTS type text;
ALTER TABLE securities ADD COLUMN IF NOT EXISTS currency text;
ALTER TABLE securities ADD COLUMN IF NOT EXISTS exchange text;
ALTER TABLE securities ADD COLUMN IF NOT EXISTS last_price numeric;
ALTER TABLE securities ADD COLUMN IF NOT EXISTS last_updated_at timestamptz;

-- 2. POLICIES (Optimized for Performance)
ALTER TABLE securities ENABLE ROW LEVEL SECURITY;

-- Select auth.role() allows caching the result for the transaction
DROP POLICY IF EXISTS "Authenticated users can read securities" ON securities; -- Remove legacy redundant policy
DROP POLICY IF EXISTS "Everyone can read securities" ON securities;
CREATE POLICY "Everyone can read securities" ON securities FOR SELECT USING (true);

DROP POLICY IF EXISTS "Users can insert new securities" ON securities;
CREATE POLICY "Users can insert new securities" ON securities FOR INSERT WITH CHECK ((select auth.role()) = 'authenticated');

DROP POLICY IF EXISTS "Users can update securities" ON securities;
CREATE POLICY "Users can update securities" ON securities FOR UPDATE USING ((select auth.role()) = 'authenticated');


-- 3. WATCHLISTS (User Specific)
CREATE TABLE IF NOT EXISTS watchlists (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references auth.users(id) not null,
  symbol text references securities(symbol) not null,
  display_order int default 0,
  created_at timestamptz default now(),
  unique(user_id, symbol)
);

-- Indexes for Performance (Fixes "Unindexed foreign keys" warning)
CREATE INDEX IF NOT EXISTS watchlists_user_id_idx ON watchlists(user_id);
CREATE INDEX IF NOT EXISTS watchlists_symbol_idx ON watchlists(symbol);

-- Optimized RLS
ALTER TABLE watchlists ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own watchlist" ON watchlists;
CREATE POLICY "Users manage own watchlist" ON watchlists
  USING ((select auth.uid()) = user_id)
  WITH CHECK ((select auth.uid()) = user_id);


-- 4. PRE-POPULATION (Curated List)
INSERT INTO securities (symbol, name, type, currency, exchange, last_updated_at)
VALUES 
  -- 🇷🇴 ROMANIA (BVB - Bucharest Stock Exchange)
  ('TLV.RO', 'Banca Transilvania', 'stock', 'RON', 'BVB', now()),
  ('H2O.RO', 'Hidroelectrica', 'stock', 'RON', 'BVB', now()),
  ('SNG.RO', 'Romgaz', 'stock', 'RON', 'BVB', now()),
  ('SNP.RO', 'OMV Petrom', 'stock', 'RON', 'BVB', now()),
  ('ONE.RO', 'One United Properties', 'stock', 'RON', 'BVB', now()),
  ('BET.RO', 'BET Index (Romania)', 'index', 'RON', 'BVB', now()),

  -- 🇺🇸 USA (Tech & Major Indices)
  ('AAPL', 'Apple Inc.', 'stock', 'USD', 'NASDAQ', now()),
  ('MSFT', 'Microsoft Corp.', 'stock', 'USD', 'NASDAQ', now()),
  ('GOOG', 'Alphabet Inc.', 'stock', 'USD', 'NASDAQ', now()),
  ('AMZN', 'Amazon.com Inc.', 'stock', 'USD', 'NASDAQ', now()),
  ('TSLA', 'Tesla Inc.', 'stock', 'USD', 'NASDAQ', now()),
  ('NVDA', 'NVIDIA Corp.', 'stock', 'USD', 'NASDAQ', now()),
  ('PATH', 'UiPath Inc.', 'stock', 'USD', 'NYSE', now()),
  ('^GSPC', 'S&P 500', 'index', 'USD', 'US', now()),
  ('^DJI', 'Dow Jones Industrial Average', 'index', 'USD', 'US', now()),
  ('^IXIC', 'NASDAQ Composite', 'index', 'USD', 'US', now()),

  -- 🇪🇺 EUROPE (Indices)
  ('^STOXX50E', 'Euro Stoxx 50', 'index', 'EUR', 'EU', now()),
  ('^GDAXI', 'DAX Performance Index (Germany)', 'index', 'EUR', 'DE', now()),
  ('^FCHI', 'CAC 40 (France)', 'index', 'EUR', 'FR', now()),

  -- 💱 FOREX
  ('EURRON=X', 'EUR/RON', 'forex', 'RON', 'CCY', now()),
  ('USDRON=X', 'USD/RON', 'forex', 'RON', 'CCY', now()),
  ('EURUSD=X', 'EUR/USD', 'forex', 'USD', 'CCY', now()),
  ('GBPUSD=X', 'GBP/USD', 'forex', 'USD', 'CCY', now()),

  -- ₿ CRYPTO
  ('BTC-USD', 'Bitcoin', 'crypto', 'USD', 'CCY', now()),
  ('ETH-USD', 'Ethereum', 'crypto', 'USD', 'CCY', now()),
  ('EGLD-USD', 'MultiversX', 'crypto', 'USD', 'CCY', now())

ON CONFLICT (symbol) DO NOTHING;
