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
        public event Action? OnQuotesUpdated;
        private readonly System.Collections.Concurrent.ConcurrentDictionary<string, bool> _fetchingSymbols = new();
        private string _currentViewType = "World";
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
            var symbolsToFetch = new List<string>();

            if (symbols == null || !symbols.Any()) return results;

            // Deduplicate incoming symbols case-insensitively
            symbols = symbols.Distinct(StringComparer.OrdinalIgnoreCase).ToList();

            // Ensure DB is initialized
            await _databaseService.InitializeAsync();

            var cachedSecurities = new List<LocalSecurity>();

            try 
            {
                // 1. Check Local SQLite Cache
                cachedSecurities = await _databaseService.Connection.Table<LocalSecurity>()
                                      .Where(s => symbols.Contains(s.Symbol))
                                      .ToListAsync();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[FinancesService] SQLite Read Error: {ex.Message}");
            }

            foreach (var symbol in symbols)
            {
                var cached = cachedSecurities.FirstOrDefault(s => string.Equals(s.Symbol, symbol, StringComparison.OrdinalIgnoreCase));
                
                bool isFresh = false;

                if (cached != null)
                {
                    cached.Type = MapMarketType(cached.Type, symbol);
                    // Check Freshness (1 hour)
                    if (cached.LastUpdatedAt.HasValue && cached.LastUpdatedAt.Value > DateTime.UtcNow.AddHours(-1))
                    {
                        isFresh = true;
                    }

                    // Use cached if valid-ish (we can show stale data while fetching)
                    results.Add(MapToQuote(cached));
                }
                else
                {
                    // Return placeholder quote immediately
                    results.Add(new StockQuote
                    {
                        Symbol = symbol,
                        CompanyName = symbol,
                        CurrentPrice = 0,
                        Change = 0,
                        PercentChange = 0,
                        MarketType = MapMarketType("", symbol),
                        LogoUrl = GetLogoUrl(symbol, symbol, MapMarketType("", symbol))
                    });
                }

                // Decide if we need to fetch
                if (!isFresh || cached == null)
                {
                     // Check if not already being fetched
                     if (!_fetchingSymbols.ContainsKey(symbol))
                     {
                         symbolsToFetch.Add(symbol);
                     }
                }
            }

            // 2. Fetch Stale/Missing data asynchronously in the background
            if (symbolsToFetch.Any())
            {
                foreach (var sym in symbolsToFetch)
                {
                    _fetchingSymbols.TryAdd(sym, true);
                }

                _ = Task.Run(async () =>
                {
                    try
                    {
                        Console.WriteLine($"[FinancesService] Background Fetching: {string.Join(", ", symbolsToFetch)}");
                        
                        var yahooData = await _yahooService.GetMarketDataAsync(symbolsToFetch);
                        
                        var missingSymbols = symbolsToFetch.Where(s => yahooData == null || !yahooData.ContainsKey(s)).ToList();
                        if (missingSymbols.Any())
                        {
                            yahooData ??= new Dictionary<string, StockQuote>();
                            var tasks = missingSymbols.Select(async missing =>
                            {
                                try {
                                    var finnhubQuote = await _finnhubService.GetQuoteAsync(missing);
                                    if (finnhubQuote != null)
                                    {
                                        lock (yahooData) { yahooData[missing] = finnhubQuote; }
                                    }
                                } catch { }
                            });
                            await Task.WhenAll(tasks);
                        }

                        // Store failed/unresolved symbols as placeholders to prevent infinite request loops
                        var unresolvedSymbols = symbolsToFetch.Where(s => yahooData == null || !yahooData.ContainsKey(s)).ToList();
                        if (unresolvedSymbols.Any())
                        {
                            Console.WriteLine($"[FinancesService] Saving placeholder entries for unresolved symbols: {string.Join(", ", unresolvedSymbols)}");
                            foreach (var symbol in unresolvedSymbols)
                            {
                                try
                                {
                                    var existing = cachedSecurities.FirstOrDefault(s => string.Equals(s.Symbol, symbol, StringComparison.OrdinalIgnoreCase));
                                    var security = new LocalSecurity
                                    {
                                        Symbol = symbol,
                                        Name = existing?.Name ?? symbol,
                                        LatestPrice = existing?.LatestPrice ?? 0,
                                        LastUpdatedAt = DateTime.UtcNow,
                                        Type = MapMarketType(existing?.Type ?? "", symbol),
                                        Change = existing?.Change ?? 0,
                                        PercentChange = existing?.PercentChange ?? 0,
                                        DayHigh = existing?.DayHigh ?? 0,
                                        DayLow = existing?.DayLow ?? 0,
                                        Volume = existing?.Volume ?? 0,
                                        MarketCap = existing?.MarketCap ?? 0,
                                        Currency = existing?.Currency,
                                        Exchange = existing?.Exchange,
                                        LogoUrl = existing?.LogoUrl ?? GetLogoUrl(symbol, symbol, MapMarketType("", symbol))
                                    };
                                    await _databaseService.Connection.InsertOrReplaceAsync(security);
                                }
                                catch (Exception ex)
                                {
                                    Console.WriteLine($"[FinancesService] SQLite Write Placeholder Error for {symbol}: {ex}");
                                }
                            }
                        }

                        if (yahooData != null && yahooData.Any())
                        {
                            foreach (var kvp in yahooData)
                            {
                                var freshQuote = kvp.Value;
                                var symbol = kvp.Key;

                                // Fallback logic for Name/Logo
                                var cached = cachedSecurities.FirstOrDefault(s => string.Equals(s.Symbol, symbol, StringComparison.OrdinalIgnoreCase));
                                var finalName = string.IsNullOrEmpty(freshQuote.CompanyName) || freshQuote.CompanyName == symbol ? (cached?.Name ?? symbol) : freshQuote.CompanyName;
                                
                                // Normalize Market Type here!
                                freshQuote.MarketType = MapMarketType(freshQuote.MarketType, symbol);
                                
                                var finalLogoUrl = cached?.LogoUrl ?? GetLogoUrl(symbol, finalName, freshQuote.MarketType);

                                freshQuote.CompanyName = finalName;
                                freshQuote.LogoUrl = finalLogoUrl;

                                // Update Local SQLite Cache
                                try
                                {
                                    var security = new LocalSecurity
                                    {
                                        Symbol = freshQuote.Symbol,
                                        Name = freshQuote.CompanyName, 
                                        LatestPrice = freshQuote.CurrentPrice,
                                        LastUpdatedAt = DateTime.UtcNow,
                                        Type = MapMarketType(freshQuote.MarketType, symbol),
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
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"[FinancesService] Background Fetch Error: {ex}");
                    }
                    finally
                    {
                        foreach (var sym in symbolsToFetch)
                        {
                            _fetchingSymbols.TryRemove(sym, out _);
                        }
                        // Notify that quotes have been updated
                        OnQuotesUpdated?.Invoke();
                    }
                });
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

        private string MapMarketType(string rawType, string symbol = "")
        {
            if (!string.IsNullOrEmpty(symbol))
            {
                if (symbol.EndsWith("-USD") || symbol.EndsWith("USDT")) return "crypto";
                if (symbol.Contains("=X")) return "forex";
            }
            string mapped = rawType?.ToUpper() switch
            {
                "EQUITY" => "stock",
                "CURRENCY" => "forex",
                "CRYPTOCURRENCY" => "crypto",
                _ => rawType?.ToLower() ?? "stock"
            };
            if (mapped != "crypto" && mapped != "forex" && mapped != "stock") return "stock";
            return mapped;
        }

        public async Task<List<string>> GetWatchlistSymbolsAsync()
        {
            await _databaseService.InitializeAsync();

            var userId = _supabaseClient.Auth.CurrentUser?.Id;
            if (string.IsNullOrEmpty(userId))
            {
                return new List<string>();
            }

            List<LocalWatchlist> cached = new();
            try
            {
                cached = await _databaseService.Connection.Table<LocalWatchlist>()
                    .Where(w => w.UserId == userId)
                    .OrderBy(w => w.DisplayOrder)
                    .ToListAsync();

                if (cached.Any())
                {
                    var oldest = cached.Min(w => w.LastUpdatedAt ?? DateTime.MinValue);
                    if (oldest > DateTime.UtcNow.AddHours(-1))
                    {
                        Console.WriteLine($"[FinancesService] Serving {cached.Count} cached watchlist symbols");
                        return cached.Select(w => w.Symbol).ToList();
                    }
                }

                var response = await _supabaseClient
                    .From<Daily.Models.Finances.UserWatchlist>()
                    .Filter("user_id", Supabase.Postgrest.Constants.Operator.Equals, userId)
                    .Order("display_order", Supabase.Postgrest.Constants.Ordering.Ascending)
                    .Get();

                if (response.Models != null && response.Models.Any())
                {
                    var now = DateTime.UtcNow;
                    var freshLocal = response.Models
                        .OrderBy(m => m.DisplayOrder)
                        .Select(m => new LocalWatchlist
                        {
                            Id = m.Id,
                            UserId = m.UserId,
                            Symbol = m.Symbol,
                            DisplayOrder = m.DisplayOrder,
                            CreatedAt = m.CreatedAt,
                            LastUpdatedAt = now
                        })
                        .ToList();

                    await _databaseService.Connection.ExecuteAsync("DELETE FROM watchlists WHERE UserId = ?", userId);
                    await _databaseService.Connection.InsertAllAsync(freshLocal);

                    return freshLocal.Select(w => w.Symbol).ToList();
                }

                // No remote rows: keep using stale cache if we have one.
                return cached.Select(w => w.Symbol).ToList();
            }
            catch (Exception ex)
            {
                Console.WriteLine("[FinancesService] Failed to load watchlist symbols: " + ex.Message);
                return cached.Select(w => w.Symbol).ToList();
            }
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
            var quoteMap = quotes.ToDictionary(q => q.Symbol, q => q, StringComparer.OrdinalIgnoreCase);

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

        // ==========================================
        // SMART LEDGER
        // ==========================================

        public async Task<LocalSmartLedger?> GetSmartLedgerAsync()
        {
            var user = _supabaseClient.Auth.CurrentUser;
            if (user == null) return null;

            return await _databaseService.Connection.Table<LocalSmartLedger>()
                .Where(l => l.UserId == user.Id)
                .FirstOrDefaultAsync();
        }

        public async Task SaveSmartLedgerAsync(string ledgerText)
        {
            var user = _supabaseClient.Auth.CurrentUser;
            if (user == null) return;

            var existing = await GetSmartLedgerAsync();
            if (existing == null)
            {
                var newLedger = new LocalSmartLedger
                {
                    Id = Guid.NewGuid().ToString(),
                    UserId = user.Id,
                    LedgerText = ledgerText,
                    CreatedAt = DateTime.UtcNow,
                    UpdatedAt = DateTime.UtcNow
                };
                await _databaseService.Connection.InsertAsync(newLedger);
            }
            else
            {
                existing.LedgerText = ledgerText;
                existing.UpdatedAt = DateTime.UtcNow;
                await _databaseService.Connection.UpdateAsync(existing);
            }
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
