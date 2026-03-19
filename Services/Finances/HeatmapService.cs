using Daily.Models.Finances;

namespace Daily.Services.Finances
{
    public class HeatmapService : IHeatmapService
    {
        private readonly IDatabaseService _databaseService;

        // Curated Q1 2026 data for ~25 major economies
        // Sources: Central bank websites, IMF, Trading Economics
        private static readonly List<CountryEconomicData> _defaultData = new()
        {
            // Americas
            new() { CountryCode = "US", CountryName = "United States",  CurrencyCode = "USD", InterestRate = 4.50m, InflationRate = 2.8m, Region = "Americas" },
            new() { CountryCode = "CA", CountryName = "Canada",         CurrencyCode = "CAD", InterestRate = 3.25m, InflationRate = 2.5m, Region = "Americas" },
            new() { CountryCode = "BR", CountryName = "Brazil",         CurrencyCode = "BRL", InterestRate = 14.25m, InflationRate = 5.1m, Region = "Americas" },
            new() { CountryCode = "MX", CountryName = "Mexico",         CurrencyCode = "MXN", InterestRate = 9.50m, InflationRate = 3.8m, Region = "Americas" },
            new() { CountryCode = "AR", CountryName = "Argentina",      CurrencyCode = "ARS", InterestRate = 29.0m, InflationRate = 67.0m, Region = "Americas" },

            // Europe
            new() { CountryCode = "DE", CountryName = "Germany",        CurrencyCode = "EUR", InterestRate = 2.65m, InflationRate = 2.3m, Region = "Europe" },
            new() { CountryCode = "GB", CountryName = "United Kingdom", CurrencyCode = "GBP", InterestRate = 4.50m, InflationRate = 3.0m, Region = "Europe" },
            new() { CountryCode = "FR", CountryName = "France",         CurrencyCode = "EUR", InterestRate = 2.65m, InflationRate = 1.8m, Region = "Europe" },
            new() { CountryCode = "CH", CountryName = "Switzerland",    CurrencyCode = "CHF", InterestRate = 0.50m, InflationRate = 1.1m, Region = "Europe" },
            new() { CountryCode = "RO", CountryName = "Romania",        CurrencyCode = "RON", InterestRate = 6.50m, InflationRate = 5.0m, Region = "Europe" },
            new() { CountryCode = "PL", CountryName = "Poland",         CurrencyCode = "PLN", InterestRate = 5.75m, InflationRate = 4.7m, Region = "Europe" },
            new() { CountryCode = "TR", CountryName = "Turkey",         CurrencyCode = "TRY", InterestRate = 42.50m, InflationRate = 44.0m, Region = "Europe" },
            new() { CountryCode = "SE", CountryName = "Sweden",         CurrencyCode = "SEK", InterestRate = 2.25m, InflationRate = 1.5m, Region = "Europe" },

            // Asia-Pacific
            new() { CountryCode = "JP", CountryName = "Japan",          CurrencyCode = "JPY", InterestRate = 0.50m, InflationRate = 3.2m, Region = "Asia" },
            new() { CountryCode = "CN", CountryName = "China",          CurrencyCode = "CNY", InterestRate = 3.10m, InflationRate = 0.5m, Region = "Asia" },
            new() { CountryCode = "IN", CountryName = "India",          CurrencyCode = "INR", InterestRate = 6.25m, InflationRate = 4.5m, Region = "Asia" },
            new() { CountryCode = "KR", CountryName = "South Korea",   CurrencyCode = "KRW", InterestRate = 2.75m, InflationRate = 2.0m, Region = "Asia" },
            new() { CountryCode = "AU", CountryName = "Australia",      CurrencyCode = "AUD", InterestRate = 4.10m, InflationRate = 3.4m, Region = "Asia" },
            new() { CountryCode = "ID", CountryName = "Indonesia",      CurrencyCode = "IDR", InterestRate = 5.75m, InflationRate = 3.0m, Region = "Asia" },
            new() { CountryCode = "TH", CountryName = "Thailand",       CurrencyCode = "THB", InterestRate = 2.00m, InflationRate = 1.2m, Region = "Asia" },

            // Middle East & Africa
            new() { CountryCode = "ZA", CountryName = "South Africa",   CurrencyCode = "ZAR", InterestRate = 7.50m, InflationRate = 5.3m, Region = "Africa" },
            new() { CountryCode = "NG", CountryName = "Nigeria",        CurrencyCode = "NGN", InterestRate = 27.50m, InflationRate = 29.0m, Region = "Africa" },
            new() { CountryCode = "SA", CountryName = "Saudi Arabia",   CurrencyCode = "SAR", InterestRate = 5.50m, InflationRate = 1.7m, Region = "Middle East" },
            new() { CountryCode = "AE", CountryName = "UAE",            CurrencyCode = "AED", InterestRate = 4.90m, InflationRate = 2.1m, Region = "Middle East" },
            new() { CountryCode = "EG", CountryName = "Egypt",          CurrencyCode = "EGP", InterestRate = 27.25m, InflationRate = 24.0m, Region = "Africa" },
        };

        public HeatmapService(IDatabaseService databaseService)
        {
            _databaseService = databaseService;
        }

        public async Task<List<CountryEconomicData>> GetGlobalHeatmapDataAsync(bool forceRefresh = false)
        {
            await _databaseService.InitializeAsync();

            // 1. Check cache (24-hour freshness)
            if (!forceRefresh)
            {
                var cached = await GetCachedDataAsync();
                if (cached.Count >= 20)
                {
                    var oldest = cached.Min(c => c.LastUpdatedAt ?? DateTime.MinValue);
                    if (oldest > DateTime.UtcNow.AddHours(-24))
                    {
                        return cached.Select(MapToModel).OrderByDescending(c => c.RealRate).ToList();
                    }
                }
            }

            // 2. Use curated data (future: FRED API integration)
            var results = new List<CountryEconomicData>();
            foreach (var item in _defaultData)
            {
                item.LastUpdatedAt = DateTime.UtcNow;
                results.Add(item);
                await UpsertCacheAsync(item);
            }

            return results.OrderByDescending(c => c.RealRate).ToList();
        }

        private async Task<List<LocalCountryEconomicData>> GetCachedDataAsync()
        {
            try
            {
                return await _databaseService.Connection.Table<LocalCountryEconomicData>().ToListAsync();
            }
            catch
            {
                return new List<LocalCountryEconomicData>();
            }
        }

        private async Task UpsertCacheAsync(CountryEconomicData data)
        {
            try
            {
                var local = new LocalCountryEconomicData
                {
                    CountryCode = data.CountryCode,
                    CountryName = data.CountryName,
                    CurrencyCode = data.CurrencyCode,
                    InterestRate = data.InterestRate,
                    InflationRate = data.InflationRate,
                    Region = data.Region,
                    LastUpdatedAt = DateTime.UtcNow
                };
                await _databaseService.Connection.InsertOrReplaceAsync(local);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[HeatmapService] Cache write failed: {ex.Message}");
            }
        }

        private static CountryEconomicData MapToModel(LocalCountryEconomicData local)
        {
            return new CountryEconomicData
            {
                CountryCode = local.CountryCode,
                CountryName = local.CountryName,
                CurrencyCode = local.CurrencyCode,
                InterestRate = local.InterestRate,
                InflationRate = local.InflationRate,
                Region = local.Region,
                LastUpdatedAt = local.LastUpdatedAt
            };
        }
    }
}
