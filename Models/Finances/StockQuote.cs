
using System;

namespace Daily.Models.Finances
{
    public class StockQuote
    {
        public string Symbol { get; set; } = string.Empty;
        public decimal CurrentPrice { get; set; }
        public decimal Change { get; set; }
        public decimal PercentChange { get; set; }
        public string CompanyName { get; set; } = string.Empty;
        public string LogoUrl { get; set; } = string.Empty;
        
        // Optional: High/Low/Open can be added later if needed
    }
    
    public class MoneyData
    {
        // Placeholder for future currency data
        public string BaseCurrency { get; set; } = "USD";
        public string TargetCurrency { get; set; } = "EUR";
        public decimal Rate { get; set; }
    }
}
