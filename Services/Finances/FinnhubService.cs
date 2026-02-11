using Daily.Configuration;
using Daily.Models.Finances;
using Microsoft.Extensions.Logging;
using System.Net.Http.Json;
using System.Text.Json.Serialization;

namespace Daily.Services.Finances;

public class FinnhubService
{
    private readonly HttpClient _httpClient;
    private readonly ILogger<FinnhubService> _logger;
    private readonly string _apiKey;

    public FinnhubService(HttpClient httpClient, ILogger<FinnhubService> logger)
    {
        _httpClient = httpClient;
        _logger = logger;
        _apiKey = Secrets.FinnhubApiKey;
    }

    public async Task<StockQuote?> GetQuoteAsync(string symbol)
    {
        if (string.IsNullOrEmpty(_apiKey)) return null;

        try
        {
            var targetSymbol = MapSymbol(symbol);
            
            var requestUrl = $"https://finnhub.io/api/v1/quote?symbol={targetSymbol}&token={_apiKey}";
            var response = await _httpClient.GetFromJsonAsync<FinnhubQuote>(requestUrl);

            if (response != null && response.CurrentPrice != 0) 
            {
                // Note: Finnhub quote is minimal. We might lack Company Name, etc.
                // We should try to preserve the original symbol/name if possible or infer it.
                return new StockQuote
                {
                    Symbol = symbol, // Return request symbol to match caller expectation
                    CurrentPrice = response.CurrentPrice,
                    Change = response.Change,
                    PercentChange = response.PercentChange,
                    DayHigh = response.High,
                    DayLow = response.Low,
                    // Finnhub doesn't provide Volume/MarketCap in free quote
                };
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, $"Finnhub failed for {symbol}");
        }

        return null;
    }

    private string MapSymbol(string symbol)
    {
        // 1. Crypto Mapping
        if (symbol.EndsWith("-USD"))
        {
            var ticker = symbol.Replace("-USD", "");
            return $"BINANCE:{ticker}USDT"; // Try Binance USDT pair
        }
        
        // 2. Forex Mapping (Yahoo: EURGBP=X -> Finnhub: OANDA:EUR_GBP)
        if (symbol.Contains("=X"))
        {
             // Yahoo: EURGBP=X
             // We need to split into EUR and GBP
             var raw = symbol.Replace("=X", "");
             if (raw.Length == 6)
             {
                 var baseCur = raw.Substring(0, 3);
                 var quoteCur = raw.Substring(3, 3);
                 return $"OANDA:{baseCur}_{quoteCur}";
             }
        }

        return symbol;
    }

    private class FinnhubQuote
    {
        [JsonPropertyName("c")]
        public decimal CurrentPrice { get; set; }

        [JsonPropertyName("d")]
        public decimal Change { get; set; }

        [JsonPropertyName("dp")]
        public decimal PercentChange { get; set; }

        [JsonPropertyName("h")]
        public decimal High { get; set; }

        [JsonPropertyName("l")]
        public decimal Low { get; set; }

        [JsonPropertyName("o")]
        public decimal Open { get; set; }

        [JsonPropertyName("pc")]
        public decimal PreviousClose { get; set; }
    }
}
