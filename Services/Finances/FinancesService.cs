using Daily.Configuration;
using Daily.Models.Finances;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Daily.Services.Finances
{
    public class FinancesService : IFinancesService
    {
        private readonly HttpClient _httpClient;
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

        public FinancesService(HttpClient httpClient)
        {
            _httpClient = httpClient;
            _apiKey = Secrets.FinnhubApiKey;
            _useMockData = string.IsNullOrEmpty(_apiKey) || _apiKey == ""; // Fallback to mock if key is empty
        }

        public async Task<List<StockQuote>> GetStockQuotesAsync(List<string> symbols)
        {
            if (_useMockData)
            {
                return GetMockData(symbols);
            }

            var results = new List<StockQuote>();

            foreach (var symbol in symbols)
            {
                try
                {
                    // Rate Limit: Free tier is 60 req/min. 
                    // Simple throttling: 1 req per second if we were looping fast, but for 3-5 items it's usually fine.
                    // We can add a small delay if needed.

                    var response = await _httpClient.GetAsync($"{BaseUrl}/quote?symbol={symbol}&token={_apiKey}");
                    if (response.IsSuccessStatusCode)
                    {
                        var json = await response.Content.ReadAsStringAsync();
                        var data = JsonSerializer.Deserialize<FinnhubQuote>(json);

                        if (data != null && data.CurrentPrice != 0) // Basic validation
                        {
                            results.Add(new StockQuote
                            {
                                Symbol = symbol,
                                CurrentPrice = data.CurrentPrice,
                                Change = data.Change,
                                PercentChange = data.PercentChange,
                                CompanyName = symbol // Finnhub quote doesn't return name, would need Profile2 endpoint. Using Symbol for now.
                            });
                        }
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[FinancesService] Error fetching {symbol}: {ex.Message}");
                    // On error, maybe fallback to mock or just skip? 
                    // For now, let's add a "Error" state mock so user sees something failed visually if they care
                }
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
                    CompanyName = sym // Mock name
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
}
