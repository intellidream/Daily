namespace Daily.Models.Finances
{
    /// <summary>
    /// Economic data for a single country, used in the Global Heatmap.
    /// Real Rate = Interest Rate - Inflation Rate.
    /// Money flows toward higher real rates.
    /// </summary>
    public class CountryEconomicData
    {
        public string CountryCode { get; set; } = string.Empty;  // ISO 3166-1 alpha-2 (US, RO, DE, etc.)
        public string CountryName { get; set; } = string.Empty;
        public string CurrencyCode { get; set; } = string.Empty;
        public decimal InterestRate { get; set; }
        public decimal InflationRate { get; set; }
        public decimal RealRate => InterestRate - InflationRate;
        public string Region { get; set; } = string.Empty; // Americas, Europe, Asia, etc.
        public DateTime? LastUpdatedAt { get; set; }
    }

    [SQLite.Table("country_economic_data")]
    public class LocalCountryEconomicData
    {
        [SQLite.PrimaryKey]
        public string CountryCode { get; set; } = string.Empty;
        public string CountryName { get; set; } = string.Empty;
        public string CurrencyCode { get; set; } = string.Empty;
        public decimal InterestRate { get; set; }
        public decimal InflationRate { get; set; }
        public string Region { get; set; } = string.Empty;
        public DateTime? LastUpdatedAt { get; set; }
    }
}
