using Daily.Configuration;
using Daily.Models.Finances;
using Daily.Services;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Daily.Services.Finances
{
    public class FinancesService : IFinancesService
    {
        private readonly HttpClient _httpClient;
        private readonly IDatabaseService _databaseService;
        private readonly string _apiKey;
        private readonly bool _useMockData;

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

        // Constants
        private const string BaseUrl = "https://finnhub.io/api/v1";

        public FinancesService(HttpClient httpClient, IDatabaseService databaseService)
        {
            _httpClient = httpClient;
            _databaseService = databaseService;
            _apiKey = Secrets.FinnhubApiKey;
            _useMockData = string.IsNullOrEmpty(_apiKey) || _apiKey == ""; 
            
            if (_useMockData)
            {
                Console.WriteLine("[FinancesService] !!! USING MOCK DATA (No API Key) !!!");
            }
            else
            {
                 Console.WriteLine($"[FinancesService] USING REAL DATA (Key Length: {_apiKey.Length})");
            }
        }

        public async Task<List<StockQuote>> GetStockQuotesAsync(List<string> symbols)
        {
            if (_useMockData)
            {
                return GetMockData(symbols);
            }

            var results = new List<StockQuote>();
            
            // Ensure DB is ready
            await _databaseService.InitializeAsync();

            foreach (var symbol in symbols)
            {
                StockQuote? quote = null;
                bool needsFetch = true;
                
                // Determine Market Type based on symbol format
                // Convention: "BINANCE:BTCUSDT" -> Crypto, "OANDA:EUR_USD" -> Forex, "AAPL" -> Equity
                string marketType = "Equity";
                if (symbol.Contains(":") && (symbol.Contains("BINANCE") || symbol.Contains("COINBASE") || symbol.Contains("KRAKEN"))) marketType = "Crypto";
                else if (symbol.Contains(":") && (symbol.Contains("OANDA") || symbol.Contains("FX"))) marketType = "Forex";

                // 1. Try Cache
                try 
                {
                    var cached = await _databaseService.Connection.Table<LocalSecurity>()
                                    .Where(s => s.Symbol == symbol)
                                    .FirstOrDefaultAsync();
                                    
                    if (cached != null)
                    {
                        // Check freshness (15 mins)
                        if (cached.LastUpdatedAt.HasValue && cached.LastUpdatedAt.Value > DateTime.UtcNow.AddMinutes(-15))
                        {
                            quote = new StockQuote
                            {
                                Symbol = cached.Symbol,
                                CurrentPrice = cached.LatestPrice,
                                Change = cached.Change,
                                PercentChange = cached.PercentChange,
                                CompanyName = cached.Name ?? cached.Symbol,
                                MarketType = cached.Type ?? marketType,
                                LogoUrl = marketType == "Equity" && !symbol.Contains(":") 
                                    ? $"https://financialmodelingprep.com/image-stock/{cached.Symbol.ToUpper()}.png"
                                    : ""
                            };
                            
                            // Simple Logo Logic for major crypto
                            if (marketType == "Crypto")
                            {
                                if (symbol.Contains("BTC")) quote.LogoUrl = "https://cryptologos.cc/logos/bitcoin-btc-logo.png?v=025";
                                if (symbol.Contains("ETH")) quote.LogoUrl = "https://cryptologos.cc/logos/ethereum-eth-logo.png?v=025";
                                if (symbol.Contains("SOL")) quote.LogoUrl = "https://cryptologos.cc/logos/solana-sol-logo.png?v=025";
                                if (symbol.Contains("DOGE")) quote.LogoUrl = "https://cryptologos.cc/logos/dogecoin-doge-logo.png?v=025";
                            }
                            
                            Console.WriteLine($"[FinancesService] Cache HIT for {symbol}");
                            needsFetch = false;
                        }
                    }
                }
                catch (Exception ex) { Console.WriteLine($"[FinancesService] Cache Read Error: {ex.Message}"); }

                if (needsFetch)
                {
                    try
                    {
                        // 2. Fetch API
                        string fetchSymbol = symbol;

                        // Strict Forex Handling (OANDA:EUR_USD)
                        if (marketType == "Forex")
                        {
                            string pair = symbol.Replace("/", "_").Replace(":", "");
                            if (pair.Contains("OANDA")) pair = pair.Replace("OANDA", "");
                            if (pair.Contains("FXCM")) pair = pair.Replace("FXCM", "");
                            fetchSymbol = $"OANDA:{pair}"; 
                        }

                        // 1. Try Primary Fetch
                        var response = await _httpClient.GetAsync($"{BaseUrl}/quote?symbol={fetchSymbol}&token={_apiKey}");
                        FinnhubQuote data = null;

                        if (response.IsSuccessStatusCode)
                        {
                            var json = await response.Content.ReadAsStringAsync();
                            try { data = JsonSerializer.Deserialize<FinnhubQuote>(json); } catch { }
                        }

                        // 2. Failover: If Primary failed OR returned 0 price, try FXCM (for Forex)
                        if (marketType == "Forex" && (data == null || data.CurrentPrice == 0))
                        {
                             Console.WriteLine($"[FinancesService] OANDA failed/zero for {fetchSymbol}, trying FXCM...");
                             // Switch to FXCM
                             string pair = symbol.Replace("/", "_").Replace(":", "");
                             if (pair.Contains("OANDA")) pair = pair.Replace("OANDA", "");
                             if (pair.Contains("FXCM")) pair = pair.Replace("FXCM", "");
                             fetchSymbol = $"FXCM:{pair}";

                             response = await _httpClient.GetAsync($"{BaseUrl}/quote?symbol={fetchSymbol}&token={_apiKey}");
                             if (response.IsSuccessStatusCode)
                             {
                                 var json = await response.Content.ReadAsStringAsync();
                                 try { data = JsonSerializer.Deserialize<FinnhubQuote>(json); } catch { }
                             }
                        }
                        
                        // 3. Process Result (if any valid data found)
                        if (data != null && data.CurrentPrice != 0)
                        {
                            quote = new StockQuote
                            {
                                Symbol = symbol, // Keep original simplified symbol for display
                                CurrentPrice = data.CurrentPrice,
                                Change = data.Change,
                                PercentChange = data.PercentChange,
                                MarketType = marketType,
                                CompanyName = symbol 
                            };

                                string companyName = symbol;
                                string logoUrl = "";
                                
                                // Clean up Company Name
                                if (marketType == "Crypto")
                                {
                                    if (symbol.Contains("BTC")) { companyName = "Bitcoin"; logoUrl = "https://cryptologos.cc/logos/bitcoin-btc-logo.png?v=025"; }
                                    else if (symbol.Contains("ETH")) { companyName = "Ethereum"; logoUrl = "https://cryptologos.cc/logos/ethereum-eth-logo.png?v=025"; }
                                    else if (symbol.Contains("SOL")) { companyName = "Solana"; logoUrl = "https://cryptologos.cc/logos/solana-sol-logo.png?v=025"; }
                                    else if (symbol.Contains("DOGE")) { companyName = "Dogecoin"; logoUrl = "https://cryptologos.cc/logos/dogecoin-doge-logo.png?v=025"; }
                                    else companyName = symbol.Split(':')[1].Replace("USDT", "");
                                }
                                else if (marketType == "Forex")
                                {
                                    companyName = symbol.Replace("_", "/").Replace("OANDA:", "").Replace("FXCM:", "");
                                    // Make sure we just show "EUR/USD" etc
                                    if (companyName.Contains(":")) companyName = companyName.Split(':')[1];
                                }
                                else // Equity
                                {
                                    try 
                                    {
                                        var profileResp = await _httpClient.GetAsync($"{BaseUrl}/stock/profile2?symbol={symbol}&token={_apiKey}");
                                        if (profileResp.IsSuccessStatusCode)
                                        {
                                             var pJson = await profileResp.Content.ReadAsStringAsync();
                                             var profile = JsonSerializer.Deserialize<FinnhubProfile>(pJson);
                                             
                                             if (profile != null && !string.IsNullOrEmpty(profile.Name))
                                             {
                                                quote.CompanyName = profile.Name;
                                                companyName = profile.Name;
                                             } 
                                        }
                                    }
                                    catch { /* Ignore profile errors */ }
                                    logoUrl = $"https://financialmodelingprep.com/image-stock/{symbol.ToUpper()}.png";
                                }

                                quote.CompanyName = companyName;
                                quote.LogoUrl = logoUrl;
                                
                                // 3. Update Cache
                                try
                                {
                                    var cachedSec = new LocalSecurity
                                    {
                                        Symbol = symbol,
                                        Name = companyName,
                                        Type = marketType, 
                                        LatestPrice = data.CurrentPrice,
                                        Change = data.Change,
                                        PercentChange = data.PercentChange,
                                        LastUpdatedAt = DateTime.UtcNow
                                    };
                                    await _databaseService.Connection.InsertOrReplaceAsync(cachedSec);
                                }
                                catch (Exception ex) { Console.WriteLine($"[FinancesService] Cache Write Error: {ex.Message}"); }
                            }
                        }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"[FinancesService] Error fetching {symbol}: {ex.Message}");
                    }
                }

                if (quote != null) results.Add(quote);
            }

            return results;
        }

        public Task<MoneyData> GetMoneyDataAsync()
        {
            // Placeholder Mock
            return Task.FromResult(new MoneyData
            {
                BaseCurrency = "USD",
                TargetCurrency = "EUR",
                Rate = 0.92m // Static mock rate
            });
        }

        private List<StockQuote> GetMockData(List<string> symbols)
        {
            // Return realistic looking data for the requested symbols
            var mocks = new List<StockQuote>();
            var rnd = new Random();

            foreach (var sym in symbols)
            {
                decimal basePrice = 100m;
                if (sym == "AAPL") basePrice = 220m;
                if (sym == "MSFT") basePrice = 415m;
                if (sym == "GOOGL") basePrice = 175m;
                if (sym == "TSLA") basePrice = 240m;
                if (sym == "NVDA") basePrice = 120m;

                var change = (decimal)(rnd.NextDouble() * 10 - 4); // -4 to +6 range roughly
                
                mocks.Add(new StockQuote
                {
                    Symbol = sym,
                    CurrentPrice = basePrice + change,
                    Change = change,
                    PercentChange = Math.Round((change / basePrice) * 100, 2),
                    CompanyName = sym, // Mock name
                    LogoUrl = $"https://financialmodelingprep.com/image-stock/{sym.ToUpper()}.png"
                });
            }

            return mocks;
        }

        // Finnhub Response Model for /quote
        private class FinnhubQuote
        {
            [JsonPropertyName("c")]
            public decimal CurrentPrice { get; set; }

            [JsonPropertyName("d")]
            public decimal Change { get; set; }

            [JsonPropertyName("dp")]
            public decimal PercentChange { get; set; }
        }

        // Finnhub Response Model for /stock/profile2
        private class FinnhubProfile
        {
            [JsonPropertyName("logo")]
            public string Logo { get; set; }
            
            [JsonPropertyName("name")]
            public string Name { get; set; }

            [JsonPropertyName("weburl")]
            public string WebUrl { get; set; }
        }

        // ==========================================
        // Money Implementation
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
             // Ensure ID 
            if (string.IsNullOrEmpty(account.Id)) account.Id = Guid.NewGuid().ToString();
            account.CreatedAt = DateTime.UtcNow;
            account.UpdatedAt = DateTime.UtcNow;
            account.SyncedAt = null; // Dirty
            
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
            transaction.SyncedAt = null; // Dirty

            // ACID: Transaction should update Account Balance
            await _databaseService.Connection.RunInTransactionAsync(tran => 
            {
                tran.Insert(transaction);
                
                var account = tran.Find<LocalAccount>(transaction.AccountId);
                if (account != null)
                {
                    account.CurrentBalance += transaction.Amount; // Amount is signed (+/-, e.g. -50 for expense)
                    account.UpdatedAt = DateTime.UtcNow;
                    account.SyncedAt = null; // Dirty
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
            
            // 1. Get Holdings
            var holdings = await _databaseService.Connection.Table<LocalHolding>().Where(h => !h.IsDeleted).ToListAsync();
            if (!holdings.Any()) return new List<StockQuote>();

            // 2. Get Quotes
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
                        CostBasis = h.CostBasis
                    });
                }
                else
                {
                    // Fallback if quote missing (shouldn't happen if GetStockQuotes works)
                    result.Add(new PortfolioItem
                    {
                        Symbol = h.SecuritySymbol,
                        Quantity = h.Quantity,
                        CostBasis = h.CostBasis,
                        CurrentPrice = 0
                    });
                }
            }
            
            // Aggregate if multiple holdings of same symbol?
            // Usually Portfolio shows one line per symbol. 
            // If user has multiple lots, we should aggregate.
            // Let's aggregate by Symbol.
            
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
                    CostBasis = g.Sum(x => x.CostBasis)
                })
                .OrderByDescending(p => p.TotalValue)
                .Cast<StockQuote>()
                .ToList();

            return aggregated;
        }

        public async Task<decimal> GetNetWorthAsync()
        {
            // 1. Accounts (Cash)
            var accounts = await GetAccountsAsync();
            var cash = accounts.Sum(a => a.CurrentBalance);

            // 2. Investments
            var portfolio = await GetHoldingsWithQuotesAsync();
            var investments = portfolio.OfType<PortfolioItem>().Sum(p => p.TotalValue);

            return cash + investments;
        }
        private async Task<decimal> PeekPrice(HttpResponseMessage response)
        {
             try
             {
                 // Simple check: if content length is tiny, might be empty json
                 if (response.Content.Headers.ContentLength < 5) return 0;
                 return 1; // Assume valid
             }
             catch { return 0; }
        }
    }
}
