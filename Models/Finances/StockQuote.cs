
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
    
    public class PortfolioItem : StockQuote
    {
        public decimal Quantity { get; set; }
        public decimal CostBasis { get; set; } // Total Cost Logic
        public decimal TotalValue => CurrentPrice * Quantity;
        public decimal TotalGainLoss => TotalValue - CostBasis;
        public decimal TotalGainLossPercent => CostBasis != 0 ? (TotalGainLoss / CostBasis) * 100 : 0;
    }

    public class MoneyData
    {
        // Placeholder for future currency data
        public string BaseCurrency { get; set; } = "USD";
        public string TargetCurrency { get; set; } = "EUR";
        public decimal Rate { get; set; }
    }
}
