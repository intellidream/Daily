using Daily.Configuration;
using Daily.Models.Finances;
using Daily.Services;
using System.Text.Json;
using System.Text.Json.Serialization;
using Supabase;
using Supabase.Postgrest;

namespace Daily.Services.Finances
{
    public class FinancesService : IFinancesService
    {
        private readonly YahooFinanceService _yahooService;
        private readonly FinnhubService _finnhubService;
        private readonly Supabase.Client _supabaseClient;
        private readonly IDatabaseService _databaseService;

        public event Action OnViewTypeChanged;
        private string _currentViewType = "Stocks";
        public string CurrentViewType
        {
            get => _currentViewType;
            set
            {
                if (_currentViewType != value)
                {
                    _currentViewType = value;
                    OnViewTypeChanged?.Invoke();
                }
            }
        }

        public FinancesService(YahooFinanceService yahooService, FinnhubService finnhubService, Supabase.Client supabaseClient, IDatabaseService databaseService)
        {
            _yahooService = yahooService;
            _finnhubService = finnhubService;
            _supabaseClient = supabaseClient;
            _databaseService = databaseService;
        }

        public async Task<List<StockQuote>> GetStockQuotesAsync(List<string> symbols)
        {
            var results = new List<StockQuote>();
            var symbolsToFetchFromYahoo = new List<string>();

            if (symbols == null || !symbols.Any()) return results;

            // Ensure DB is initialized
            // Ensure DB is initialized
            await _databaseService.InitializeAsync();

            var cachedSecurities = new List<LocalSecurity>();

            try 
            {
                // 1. Check Local SQLite Cache
                cachedSecurities = await _databaseService.Connection.Table<LocalSecurity>()
                                      .Where(s => symbols.Contains(s.Symbol))
                                      .ToListAsync();

                foreach (var symbol in symbols)
                {
                    var cached = cachedSecurities.FirstOrDefault(s => s.Symbol == symbol);
                    
                    bool isFresh = false;
                    bool isRich = false;

                    if (cached != null)
                    {
                        // Check Freshness (15 mins)
                        if (cached.LastUpdatedAt.HasValue && cached.LastUpdatedAt.Value > DateTime.UtcNow.AddMinutes(-15))
                        {
                            isFresh = true;
                        }

                        // Check Richness (DayHigh/Volume)
                        if (cached.DayHigh.HasValue && cached.Volume.HasValue)
                        {
                            isRich = true;
                        }
                        
                        // FIX: Force update if using old/broken FMP or Clearbit icons
                        if (cached.LogoUrl != null && (cached.LogoUrl.Contains("financialmodelingprep.com") || cached.LogoUrl.Contains("clearbit.com")))
                        {
                            // Invalidate to force Google Favicon logic (via YahooService fetch)
                             isFresh = false; 
                        }

                        // FIX: Force update if Crypto name is generic "USD"
                        // RELAXED: Removed "Name == Symbol" check to prevent loops for valid symbols like "SOL"
                        if (cached.Type == "crypto" && cached.Name == "USD")
                        {
                            isFresh = false;
                        }

                        // Use cached if valid-ish (we can show stale data while fetching)
                        results.Add(MapToQuote(cached));
                    }

                    // Decide if we need to fetch
                    // RELAXED CACHE: If it's fresh, use it. Don't force re-fetch just for "richness" (Volume/DayHigh).
                    // This prevents infinite loops with Finnhub which always returns "light" data.
                    if (!isFresh || cached == null)
                    {
                         if (!symbolsToFetchFromYahoo.Contains(symbol)) symbolsToFetchFromYahoo.Add(symbol);
                    }
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[FinancesService] SQLite Read Error: {ex.Message}");
                symbolsToFetchFromYahoo = symbols.ToList();
            }

            // 2. Fetch Stale/Missing/Rich data from Yahoo
            if (symbolsToFetchFromYahoo.Any())
            {
                // Console.WriteLine($"[FinancesService] Fetching from Yahoo: {string.Join(", ", symbolsToFetchFromYahoo)}");
                var yahooData = await _yahooService.GetMarketDataAsync(symbolsToFetchFromYahoo);

                // Failover Logic: If Yahoo didn't return some symbols, try Finnhub
                var missingSymbols = symbolsToFetchFromYahoo.Where(s => !yahooData.ContainsKey(s)).ToList();
                if (missingSymbols.Any())
                {
                    foreach (var missing in missingSymbols)
                    {
                        var finnhubQuote = await _finnhubService.GetQuoteAsync(missing);
                        if (finnhubQuote != null)
                        {
                            // Finnhub data is "lighter" (no CompanyName usually), so we might need to patch it
                            // Use cached name if available or symbol as fallback
                            var cached = cachedSecurities.FirstOrDefault(s => s.Symbol == missing);
                            if (string.IsNullOrEmpty(finnhubQuote.CompanyName))
                            {
                                finnhubQuote.CompanyName = cached?.Name ?? GetPrettyName(missing, missing);
                            }
                            // Attempt to infer MarketType/Currency/Exchange if missing
                            if (string.IsNullOrEmpty(finnhubQuote.Currency)) finnhubQuote.Currency = "USD"; // Default
                            if (string.IsNullOrEmpty(finnhubQuote.MarketType)) 
                            {
                                if (missing.Contains("-USD")) finnhubQuote.MarketType = "crypto";
                                else if (missing.Contains("=X")) finnhubQuote.MarketType = "forex";
                                else finnhubQuote.MarketType = "stock";
                            }

                            // Add to yahooData so it gets processed downstream
                            if (!yahooData.ContainsKey(missing))
                            {
                                yahooData.Add(missing, finnhubQuote);
                            }
                        }
                    }
                }

                if (yahooData.Any())
                {
                    // Update Results with Fresh Data (Merge with Cached)
                    foreach (var kvp in yahooData)
                    {
                        var freshQuote = kvp.Value;
                        
                        // 2a. Merge with Cached Data to preserve richness (Logo, Volume, MarketCap)
                        // This is crucial because Finnhub quotes are "light" (missing huge chunks of data)
                        // If we just overwrite, we lose the Logos and Charts.
                        var cached = cachedSecurities.FirstOrDefault(s => s.Symbol == freshQuote.Symbol);
                        if (cached != null)
                        {
                            // Preserve Name if fresh is generic/missing
                            if (string.IsNullOrEmpty(freshQuote.CompanyName) || freshQuote.CompanyName == freshQuote.Symbol)
                            {
                                 freshQuote.CompanyName = cached.Name;
                            }

                            // Preserve Logo if fresh is missing
                            // Finnhub returns NULL LogoUrl. We MUST use the cached one if valid.
                            if (string.IsNullOrEmpty(freshQuote.LogoUrl) && !string.IsNullOrEmpty(cached.LogoUrl))
                            {
                                freshQuote.LogoUrl = cached.LogoUrl;
                            }

                            // Preserve Rich Data (Volume/MarketCap) if fresh is missing/zero
                            if (freshQuote.Volume == 0 && cached.Volume.HasValue) freshQuote.Volume = cached.Volume;
                            if (freshQuote.MarketCap == 0 && cached.MarketCap.HasValue) freshQuote.MarketCap = cached.MarketCap;
                            if (freshQuote.DayHigh == 0 && cached.DayHigh.HasValue) freshQuote.DayHigh = cached.DayHigh;
                            if (freshQuote.DayLow == 0 && cached.DayLow.HasValue) freshQuote.DayLow = cached.DayLow;
                        }

                        // 2b. Final Fallback for Logo
                        if (string.IsNullOrEmpty(freshQuote.LogoUrl))
                        {
                             freshQuote.LogoUrl = GetLogoUrl(freshQuote.Symbol, freshQuote.CompanyName, freshQuote.MarketType);
                        }
                        
                        // Remove stale entry if exists
                        var existing = results.FirstOrDefault(r => r.Symbol == freshQuote.Symbol);
                        if (existing != null) results.Remove(existing);
                        
                        results.Add(freshQuote);

                        // 3. Update Local SQLite Cache
                        try
                        {
                            var security = new LocalSecurity
                            {
                                Symbol = freshQuote.Symbol,
                                Name = freshQuote.CompanyName, 
                                LatestPrice = freshQuote.CurrentPrice,
                                LastUpdatedAt = DateTime.UtcNow,
                                Type = MapMarketType(freshQuote.MarketType),
                                Change = freshQuote.Change,
                                PercentChange = freshQuote.PercentChange,
                                
                                // Rich Data
                                DayHigh = freshQuote.DayHigh,
                                DayLow = freshQuote.DayLow,
                                Volume = freshQuote.Volume,
                                MarketCap = freshQuote.MarketCap,
                                Currency = freshQuote.Currency,
                                Exchange = freshQuote.Exchange,
                                LogoUrl = freshQuote.LogoUrl
                            };
                            
                            await _databaseService.Connection.InsertOrReplaceAsync(security);
                        }
                        catch(Exception ex)
                        {
                             Console.WriteLine($"[FinancesService] SQLite Write Error: {ex}");
                        }
                    }
                }
                else
                {
                    Console.WriteLine("[FinancesService] Yahoo fetch returned empty. Keeping cached data if available.");
                }
            }

            return results;
        }

        private StockQuote MapToQuote(LocalSecurity sec)
        {
            return new StockQuote
            {
                Symbol = sec.Symbol,
                CompanyName = sec.Name ?? sec.Symbol,
                CurrentPrice = sec.LatestPrice,
                Change = sec.Change, 
                PercentChange = sec.PercentChange,
                MarketType = sec.Type,
                Currency = sec.Currency,
                Exchange = sec.Exchange,
                // Rich Data from Local Cache
                DayHigh = sec.DayHigh,
                DayLow = sec.DayLow,
                Volume = sec.Volume,
                MarketCap = sec.MarketCap,
                LogoUrl = !string.IsNullOrEmpty(sec.LogoUrl) ? sec.LogoUrl : GetLogoUrl(sec.Symbol, sec.Name, sec.Type)
            };
        }

        private string GetLogoUrl(string symbol, string name, string type)
        {
            var s = symbol.ToUpper().Trim();

            // 1. Bitcoin/Crypto specific
            if (s == "BTC" || s.Contains("BTC-")) return "https://upload.wikimedia.org/wikipedia/commons/4/46/Bitcoin.svg";
            if (s == "ETH" || s.Contains("ETH-")) return "https://upload.wikimedia.org/wikipedia/commons/6/6f/Ethereum-icon-purple.svg";
            if (s == "SOL" || s.Contains("SOL-")) return "https://upload.wikimedia.org/wikipedia/en/b/b9/Solana_logo.png";
            if (s == "BNB" || s.Contains("BNB-")) return "https://upload.wikimedia.org/wikipedia/commons/f/fc/Binance-coin-bnb-logo.png";
            if (s == "XRP" || s.Contains("XRP-")) return "https://upload.wikimedia.org/wikipedia/commons/9/91/XRP_Symbol.png"; // or similar
            if (s == "ADA" || s.Contains("ADA-")) return "https://upload.wikimedia.org/wikipedia/commons/1/1a/Cardano-ada-logo.png";
            if (s == "DOGE" || s.Contains("DOGE-")) return "https://upload.wikimedia.org/wikipedia/en/d/d0/Dogecoin_Logo.png";
            
            // 2. Google Favicon Service
            // We need a domain. 
            // If name contains space, take first word. 
            // "Apple Inc" -> apple.com
            // "Microsoft Corporation" -> microsoft.com
            // "Nvidia" -> nvidia.com

            if (!string.IsNullOrEmpty(name))
            {
                name = GetPrettyName(s, name);
                
                var candidates = name.ToLower().Split(new char[]{' ', ',', '.', '-'}, StringSplitOptions.RemoveEmptyEntries);
                if (candidates.Length > 0)
                {
                    var domain = candidates[0] + ".com";
                    // Google Favicon Service
                    return $"https://www.google.com/s2/favicons?domain={domain}&sz=128";
                }
            }
            
            // Fallback to Google with symbol if name fails
            return $"https://www.google.com/s2/favicons?domain={s.ToLower()}.com&sz=128";
        }

        private string GetPrettyName(string symbol, string name)
        {
            var s = symbol.ToUpper().Trim();
             // SPECIAL MAPPINGS FOR KNOWN CRYPTOS/STOCKS IF NAME IS JUST SYMBOL OR MISSING
            if (string.IsNullOrEmpty(name) || name.ToUpper() == s || name.ToUpper() == s.Replace("-USD", "")) 
            {
                var ticker = s.Replace("-USD", "");
                return ticker switch
                {
                    "SOL" => "Solana",
                    "BNB" => "Binance",
                    "XRP" => "Ripple",
                    "ADA" => "Cardano",
                    "DOGE" => "Dogecoin",
                    "AVAX" => "Avalanche",
                    "DOT" => "Polkadot",
                    "LINK" => "Chainlink",
                    "NVDA" => "Nvidia", 
                    "MSFT" => "Microsoft",
                    "AAPL" => "Apple",
                    "GOOG" => "Google",
                    "AMZN" => "Amazon",
                    "TSLA" => "Tesla",
                    "META" => "Meta",
                    _ => name ?? s
                };
            }
            return name;
        }

        private string MapMarketType(string rawType)
        {
            // Yahoo might return "EQUITY", "CURRENCY", "CRYPTOCURRENCY"
            // Map to our "stock", "forex", "crypto"
            return rawType?.ToUpper() switch
            {
                "EQUITY" => "stock",
                "CURRENCY" => "forex",
                "CRYPTOCURRENCY" => "crypto",
                _ => rawType?.ToLower() ?? "stock"
            };
        }

        public Task<MoneyData> GetMoneyDataAsync()
        {
             return Task.FromResult(new MoneyData
             {
                 BaseCurrency = "USD",
                 TargetCurrency = "EUR",
                 Rate = 0.92m 
             });
        }

        // ==========================================
        // Money Implementation (Local SQLite)
        // ==========================================

        public async Task<List<LocalAccount>> GetAccountsAsync()
        {
            await _databaseService.InitializeAsync();
            return await _databaseService.Connection.Table<LocalAccount>()
                            .Where(a => !a.IsDeleted)
                            .ToListAsync();
        }

        public async Task AddAccountAsync(LocalAccount account)
        {
            await _databaseService.InitializeAsync().ConfigureAwait(false);
            if (string.IsNullOrEmpty(account.Id)) account.Id = Guid.NewGuid().ToString();
            account.CreatedAt = DateTime.UtcNow;
            account.UpdatedAt = DateTime.UtcNow;
            account.SyncedAt = null; 
            
            await _databaseService.Connection.InsertAsync(account).ConfigureAwait(false);
        }

        public async Task<List<LocalTransaction>> GetTransactionsAsync(string accountId)
        {
            await _databaseService.InitializeAsync().ConfigureAwait(false);
            return await _databaseService.Connection.Table<LocalTransaction>()
                            .Where(t => t.AccountId == accountId && !t.IsDeleted)
                            .OrderByDescending(t => t.Date)
                            .ToListAsync().ConfigureAwait(false);
        }

        public async Task AddTransactionAsync(LocalTransaction transaction)
        {
            await _databaseService.InitializeAsync().ConfigureAwait(false);
            if (string.IsNullOrEmpty(transaction.Id)) transaction.Id = Guid.NewGuid().ToString();
            transaction.CreatedAt = DateTime.UtcNow;
            transaction.UpdatedAt = DateTime.UtcNow;
            transaction.SyncedAt = null; 

            await _databaseService.Connection.RunInTransactionAsync(tran => 
            {
                tran.Insert(transaction);
                
                var account = tran.Find<LocalAccount>(transaction.AccountId);
                if (account != null)
                {
                    account.CurrentBalance += transaction.Amount; 
                    account.UpdatedAt = DateTime.UtcNow;
                    account.SyncedAt = null; 
                    tran.Update(account);
                }
            }).ConfigureAwait(false);

        }

        // ==========================================
        // Portfolio Implementation
        // ==========================================

        public async Task<List<StockQuote>> GetHoldingsWithQuotesAsync()
        {
            await _databaseService.InitializeAsync();
            
            // 1. Get Holdings (Local)
            var holdings = await _databaseService.Connection.Table<LocalHolding>().Where(h => !h.IsDeleted).ToListAsync();
            if (!holdings.Any()) return new List<StockQuote>();

            // 2. Get Quotes (Global)
            var symbols = holdings.Select(h => h.SecuritySymbol).Distinct().ToList();
            var quotes = await GetStockQuotesAsync(symbols);
            var quoteMap = quotes.ToDictionary(q => q.Symbol, q => q);

            // 3. Merge
            var result = new List<StockQuote>();
            foreach (var h in holdings)
            {
                if (quoteMap.TryGetValue(h.SecuritySymbol, out var q))
                {
                    result.Add(new PortfolioItem
                    {
                        Symbol = q.Symbol,
                        CompanyName = q.CompanyName,
                        CurrentPrice = q.CurrentPrice,
                        Change = q.Change,
                        PercentChange = q.PercentChange,
                        LogoUrl = q.LogoUrl,
                        Quantity = h.Quantity,
                        CostBasis = h.CostBasis,
                        MarketType = q.MarketType,
                        Currency = q.Currency,
                        Exchange = q.Exchange
                    });
                }
                else
                {
                    result.Add(new PortfolioItem
                    {
                        Symbol = h.SecuritySymbol,
                        Quantity = h.Quantity,
                        CostBasis = h.CostBasis,
                        CurrentPrice = 0
                    });
                }
            }
            
            var aggregated = result.Cast<PortfolioItem>()
                .GroupBy(p => p.Symbol)
                .Select(g => new PortfolioItem
                {
                    Symbol = g.Key,
                    CompanyName = g.First().CompanyName,
                    CurrentPrice = g.First().CurrentPrice,
                    Change = g.First().Change,
                    PercentChange = g.First().PercentChange,
                    LogoUrl = g.First().LogoUrl,
                    Quantity = g.Sum(x => x.Quantity),
                    CostBasis = g.Sum(x => x.CostBasis),
                    MarketType = g.First().MarketType,
                    Currency = g.First().Currency,
                    Exchange = g.First().Exchange
                })
                .OrderByDescending(p => p.TotalValue)
                .Cast<StockQuote>()
                .ToList();

            return aggregated;
        }

        public async Task<decimal> GetNetWorthAsync()
        {
            var accounts = await GetAccountsAsync();
            var cash = accounts.Sum(a => a.CurrentBalance);

            var portfolio = await GetHoldingsWithQuotesAsync();
            var investments = portfolio.OfType<PortfolioItem>().Sum(p => p.TotalValue);

            return cash + investments;
        }
    }
}
