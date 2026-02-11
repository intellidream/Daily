using YahooFinanceApi;
using Daily.Models.Finances;
using Microsoft.Extensions.Logging;
using AngleSharp;
using Newtonsoft.Json.Linq;
using System.Collections.Concurrent;

namespace Daily.Services.Finances;

public class YahooFinanceService
{
    private readonly ILogger<YahooFinanceService> _logger;
    private readonly HttpClient _httpClient;
    private readonly System.Threading.SemaphoreSlim _concurrencySemaphore = new(2);

    public YahooFinanceService(ILogger<YahooFinanceService> logger, HttpClient httpClient)
    {
        _logger = logger;
        _httpClient = httpClient;
        // Ensure User-Agent is set to look like a browser
        if (!_httpClient.DefaultRequestHeaders.Contains("User-Agent"))
        {
            _httpClient.DefaultRequestHeaders.Add("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36");
        }
    }

    public async Task<Dictionary<string, StockQuote>> GetMarketDataAsync(IEnumerable<string> symbols)
    {
        var results = new System.Collections.Concurrent.ConcurrentDictionary<string, StockQuote>();
        var symbolList = symbols.Distinct().ToList();

        if (!symbolList.Any())
            return new Dictionary<string, StockQuote>();

        var tasks = symbolList.Select(async symbol => 
        {
            await _concurrencySemaphore.WaitAsync();
            try
            {
                var quote = await FetchQuoteFromHtmlAsync(symbol);
                if (quote != null)
                {
                    // Generate Smart Logo
                    quote.LogoUrl = GetLogoUrl(quote);
                    results.TryAdd(symbol, quote);
                }
            }
            catch (Exception ex) 
            {
                 _logger.LogError(ex, $"Failed to scrape {symbol}");
            }
            finally
            {
                _concurrencySemaphore.Release();
            }
        });

        await Task.WhenAll(tasks);
        return results.ToDictionary(k => k.Key, v => v.Value);
    }

    private async Task<StockQuote?> FetchQuoteFromHtmlAsync(string symbol)
    {
        var retryCount = 0;
        var maxRetries = 3;
        var delay = TimeSpan.FromSeconds(1);

        while (retryCount <= maxRetries)
        {
            try
            {
                // Add random jitter to behave like a human
                await Task.Delay(Random.Shared.Next(200, 800));

                var url = $"https://finance.yahoo.com/quote/{symbol}";
                using var request = new HttpRequestMessage(HttpMethod.Get, url);
                
                // Rotate user agents slightly if possible, or just keep the working one
                request.Headers.Add("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36");
                request.Headers.Add("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8");
                request.Headers.Add("Accept-Language", "en-US,en;q=0.5");
                
                using var response = await _httpClient.SendAsync(request);
                
                if (response.StatusCode == System.Net.HttpStatusCode.TooManyRequests)
                {
                    _logger.LogWarning($"[YahooFinanceService] Rate limited for {symbol}. Retrying in {delay.TotalSeconds}s...");
                    await Task.Delay(delay);
                    delay *= 2; // Exponential backoff
                    retryCount++;
                    continue;
                }

                response.EnsureSuccessStatusCode();
                var html = await response.Content.ReadAsStringAsync();
                
                var config = AngleSharp.Configuration.Default;
                var context = AngleSharp.BrowsingContext.New(config);
                var document = await context.OpenAsync(req => req.Content(html));

                // Find the script with quoteResponse
                var scripts = document.Scripts;
                foreach(var script in scripts)
                {
                    if (script.TextContent.Contains("quoteResponse") && script.TextContent.Contains(symbol))
                    {
                        var outerJson = Newtonsoft.Json.Linq.JToken.Parse(script.TextContent);
                        if (outerJson is Newtonsoft.Json.Linq.JObject obj)
                        {
                             var body = obj["body"]?.ToString();
                             if (!string.IsNullOrEmpty(body))
                             {
                                 var innerJson = Newtonsoft.Json.Linq.JObject.Parse(body);
                                 var quoteResponse = innerJson["quoteResponse"];
                                 var result = quoteResponse?["result"]?[0];
                                 
                                 if (result != null)
                                 {
                                     var q = new StockQuote
                                     {
                                         Symbol = result["symbol"]?.ToString() ?? symbol,
                                         CurrentPrice = (decimal?)result["regularMarketPrice"]?["raw"] ?? 0m,
                                         PercentChange = (decimal?)result["regularMarketChangePercent"]?["raw"] ?? 0m,
                                         CompanyName = result["shortName"]?.ToString() ?? result["longName"]?.ToString() ?? symbol,
                                         Currency = result["currency"]?.ToString(),
                                         Exchange = result["fullExchangeName"]?.ToString() ?? result["exchange"]?.ToString(),
                                         
                                         // Rich Data
                                         DayHigh = (decimal?)result["regularMarketDayHigh"]?["raw"],
                                         DayLow = (decimal?)result["regularMarketDayLow"]?["raw"],
                                         Volume = (long?)result["regularMarketVolume"]?["raw"],
                                         MarketCap = (long?)result["marketCap"]?["raw"]
                                     };

                                     // FIX: Crypto Name Sanitization
                                     if (q.Symbol.Contains("-USD"))
                                     {
                                         if (q.CompanyName == "USD" || q.CompanyName == q.Symbol)
                                         {
                                             var ticker = q.Symbol.Replace("-USD", "");
                                             q.CompanyName = ticker switch
                                             {
                                                 "BTC" => "Bitcoin",
                                                 "ETH" => "Ethereum",
                                                 "SOL" => "Solana",
                                                 "BNB" => "Binance Coin",
                                                 "XRP" => "Ripple",
                                                 "DOGE" => "Dogecoin",
                                                 "ADA" => "Cardano",
                                                 "AVAX" => "Avalanche",
                                                 "DOT" => "Polkadot",
                                                 "LINK" => "Chainlink",
                                                 _ => ticker
                                             };
                                         }
                                     }

                                     return q;
                                 }
                             }
                        }
                    }
                }
                
                // If we get here, parsing failed but request succeeded.
                // Could be that Yahoo returned a different structure or captcha page.
                _logger.LogWarning($"[YahooFinanceService] Failed to parse content for {symbol}.");
                return null;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Error scraping Yahoo for {symbol} (Attempt {retryCount + 1})");
                retryCount++;
                await Task.Delay(delay);
                delay *= 2;
            }
        }
        return null;
    }

    public async Task<List<StockQuote>> SearchSymbolsAsync(string query)
    {
        var results = new List<StockQuote>();
        try
        {
             // ... existing search logic ...
            await Task.CompletedTask;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error searching symbols on Yahoo Finance");
        }
        return results;
    }

    private string GetLogoUrl(StockQuote stock)
    {
        var s = stock.Symbol.ToUpper().Trim();

        // 1. Crypto Overrides (Keep SVGs)
        if (s.Contains("BTC-")) return "https://upload.wikimedia.org/wikipedia/commons/4/46/Bitcoin.svg";
        if (s.Contains("ETH-")) return "https://upload.wikimedia.org/wikipedia/commons/6/6f/Ethereum-icon-purple.svg";
        
        // 2. Google Favicon Service (The Golden Standard)
        if (!string.IsNullOrEmpty(stock.CompanyName))
        {
             var name = stock.CompanyName.ToLower();
             var candidates = name.Split(new char[]{' ', ',', '.', '-'}, StringSplitOptions.RemoveEmptyEntries);
             if (candidates.Length > 0)
             {
                 var domain = candidates[0] + ".com";
                 return $"https://www.google.com/s2/favicons?domain={domain}&sz=128";
             }
        }
        
        // Fallback: Try with Symbol
        return $"https://www.google.com/s2/favicons?domain={s.ToLower()}.com&sz=128";
    }
}
