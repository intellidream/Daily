using Daily.Models.Finances;
using Daily.Services;
using Newtonsoft.Json.Linq;

namespace Daily.Services.Finances
{
    public class MacroService : IMacroService
    {
        private readonly HttpClient _httpClient;
        private readonly IDatabaseService _databaseService;

        // The 6 Core Pillars mapped to Yahoo Finance symbols
        private static readonly List<(string Symbol, string Name, string Pillar, string Emoji)> Pillars = new()
        {
            ("CL=F",      "Crude Oil (WTI)",  "Energy",      "🛢️"),
            ("GC=F",      "Gold",             "Safe Haven",  "🟡"),
            ("DX-Y.NYB",  "US Dollar Index",  "The King",    "💵"),
            ("^NDX",      "Nasdaq 100",       "Tech/Growth", "💻"),
            ("BTC-USD",   "Bitcoin",          "Risk/Future",  "₿"),
            ("^VIX",      "VIX Index",        "Stress",      "📊"),
        };

        public MacroService(HttpClient httpClient, IDatabaseService databaseService)
        {
            _httpClient = httpClient;
            _databaseService = databaseService;
        }

        public async Task<List<MacroIndicator>> GetMacroIndicatorsAsync(bool forceRefresh = false)
        {
            await _databaseService.InitializeAsync();

            // 1. Check cache first (1-hour freshness)
            if (!forceRefresh)
            {
                var cached = await GetCachedIndicatorsAsync();
                if (cached.Count == Pillars.Count)
                {
                    var oldest = cached.Min(c => c.LastUpdatedAt ?? DateTime.MinValue);
                    if (oldest > DateTime.UtcNow.AddHours(-1))
                    {
                        Console.WriteLine($"[MacroService] Serving {cached.Count} cached indicators");
                        return cached.Select(MapToIndicator).ToList();
                    }
                }
            }

            // 2. Fetch fresh data from Yahoo v8 Chart API (direct JSON, no HTML scraping)
            var results = new List<MacroIndicator>();
            foreach (var pillar in Pillars)
            {
                try
                {
                    var indicator = await FetchFromChartApiAsync(pillar);
                    if (indicator != null)
                    {
                        results.Add(indicator);
                        await UpsertCacheAsync(indicator);
                    }
                    else
                    {
                        // Fallback to cache for this symbol
                        var stale = await GetCachedIndicatorAsync(pillar.Symbol);
                        if (stale != null) results.Add(MapToIndicator(stale));
                        else Console.WriteLine($"[MacroService] No data for {pillar.Symbol}");
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[MacroService] Error fetching {pillar.Symbol}: {ex.Message}");
                    var stale = await GetCachedIndicatorAsync(pillar.Symbol);
                    if (stale != null) results.Add(MapToIndicator(stale));
                }

                // Small delay between requests to be respectful
                await Task.Delay(Random.Shared.Next(100, 300));
            }

            Console.WriteLine($"[MacroService] Fetched {results.Count}/{Pillars.Count} indicators");
            return results;
        }

        /// <summary>
        /// Fetches data from Yahoo Finance v8 Chart API (JSON endpoint, no HTML scraping).
        /// URL: https://query1.finance.yahoo.com/v8/finance/chart/{symbol}?interval=1d&range=1d
        /// </summary>
        private async Task<MacroIndicator?> FetchFromChartApiAsync(
            (string Symbol, string Name, string Pillar, string Emoji) pillar)
        {
            var url = $"https://query1.finance.yahoo.com/v8/finance/chart/{Uri.EscapeDataString(pillar.Symbol)}?interval=1d&range=1d";

            using var request = new HttpRequestMessage(HttpMethod.Get, url);
            request.Headers.Add("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36");
            request.Headers.Add("Accept", "application/json");

            using var response = await _httpClient.SendAsync(request);

            if (!response.IsSuccessStatusCode)
            {
                Console.WriteLine($"[MacroService] HTTP {response.StatusCode} for {pillar.Symbol}");
                return null;
            }

            var json = await response.Content.ReadAsStringAsync();
            var root = JObject.Parse(json);

            var meta = root["chart"]?["result"]?[0]?["meta"];
            if (meta == null)
            {
                Console.WriteLine($"[MacroService] No chart meta for {pillar.Symbol}");
                return null;
            }

            var currentPrice = (decimal?)meta["regularMarketPrice"] ?? 0m;
            var previousClose = (decimal?)meta["chartPreviousClose"] ?? 0m;
            var dayHigh = (decimal?)meta["regularMarketDayHigh"];
            var dayLow = (decimal?)meta["regularMarketDayLow"];
            var volume = (long?)meta["regularMarketVolume"];
            var currency = meta["currency"]?.ToString() ?? "USD";

            var change = currentPrice - previousClose;
            var percentChange = previousClose != 0 ? (change / previousClose) * 100 : 0;

            return new MacroIndicator
            {
                Symbol = pillar.Symbol,
                Name = pillar.Name,
                Pillar = pillar.Pillar,
                Emoji = pillar.Emoji,
                CurrentPrice = currentPrice,
                Change = change,
                PercentChange = percentChange,
                Currency = currency,
                DayHigh = dayHigh,
                DayLow = dayLow,
                Volume = volume,
                LastUpdatedAt = DateTime.UtcNow
            };
        }

        private async Task<List<LocalMacroIndicator>> GetCachedIndicatorsAsync()
        {
            try
            {
                return await _databaseService.Connection.Table<LocalMacroIndicator>().ToListAsync();
            }
            catch
            {
                return new List<LocalMacroIndicator>();
            }
        }

        private async Task<LocalMacroIndicator?> GetCachedIndicatorAsync(string symbol)
        {
            try
            {
                return await _databaseService.Connection.Table<LocalMacroIndicator>()
                    .Where(m => m.Symbol == symbol)
                    .FirstOrDefaultAsync();
            }
            catch
            {
                return null;
            }
        }

        private async Task UpsertCacheAsync(MacroIndicator indicator)
        {
            try
            {
                var local = new LocalMacroIndicator
                {
                    Symbol = indicator.Symbol,
                    Name = indicator.Name,
                    Pillar = indicator.Pillar,
                    Emoji = indicator.Emoji,
                    CurrentPrice = indicator.CurrentPrice,
                    Change = indicator.Change,
                    PercentChange = indicator.PercentChange,
                    Currency = indicator.Currency,
                    DayHigh = indicator.DayHigh,
                    DayLow = indicator.DayLow,
                    Volume = indicator.Volume,
                    LastUpdatedAt = DateTime.UtcNow
                };
                await _databaseService.Connection.InsertOrReplaceAsync(local);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[MacroService] Cache write failed: {ex.Message}");
            }
        }

        private static MacroIndicator MapToIndicator(LocalMacroIndicator local)
        {
            return new MacroIndicator
            {
                Symbol = local.Symbol,
                Name = local.Name,
                Pillar = local.Pillar,
                Emoji = local.Emoji,
                CurrentPrice = local.CurrentPrice,
                Change = local.Change,
                PercentChange = local.PercentChange,
                Currency = local.Currency,
                DayHigh = local.DayHigh,
                DayLow = local.DayLow,
                Volume = local.Volume,
                LastUpdatedAt = local.LastUpdatedAt
            };
        }
    }
}
