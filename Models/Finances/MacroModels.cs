using System;
using System.Collections.Generic;

namespace Daily.Models.Finances
{
    /// <summary>
    /// Represents a single macro economic indicator (e.g., Oil, Gold, DXY, Nasdaq, BTC, VIX).
    /// </summary>
    public class MacroIndicator
    {
        public string Symbol { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string Pillar { get; set; } = string.Empty; // Energy, Safe Haven, The King, Tech/Growth, Risk/Future, Stress
        public string Emoji { get; set; } = string.Empty;   // 🛢️, 🟡, 💵, 💻, ₿, 📊
        public decimal CurrentPrice { get; set; }
        public decimal Change { get; set; }
        public decimal PercentChange { get; set; }
        public string Currency { get; set; } = "USD";
        public decimal? DayHigh { get; set; }
        public decimal? DayLow { get; set; }
        public long? Volume { get; set; }
        public DateTime? LastUpdatedAt { get; set; }

        public bool IsPositive => Change >= 0;

        public string CurrencySymbol => Currency switch
        {
            "USD" => "$",
            "EUR" => "€",
            "GBP" => "£",
            "JPY" => "¥",
            _ => Currency
        };

        /// <summary>
        /// Interpretation for the "normal person" — what this indicator's movement means.
        /// </summary>
        public string Insight => Pillar switch
        {
            "Energy" => IsPositive ? "Energy costs rising — inflation pressure" : "Energy easing — good for consumers",
            "Safe Haven" => IsPositive ? "Fear rising — investors seeking safety" : "Confidence returning — risk-on",
            "The King" => IsPositive ? "Dollar strong — pressure on emerging markets" : "Dollar weakening — relief for EM",
            "Tech/Growth" => IsPositive ? "Tech optimism — growth mode" : "Tech pullback — caution in markets",
            "Risk/Future" => IsPositive ? "Risk appetite high — speculative mood" : "Risk-off — caution prevails",
            "Stress" => CurrentPrice > 30 ? "⚠️ Markets panicking (VIX > 30)" : (CurrentPrice > 20 ? "Elevated concern" : "Markets calm"),
            _ => ""
        };
    }

    // Local SQLite cache for macro indicators
    [SQLite.Table("macro_indicators")]
    public class LocalMacroIndicator
    {
        [SQLite.PrimaryKey]
        public string Symbol { get; set; } = string.Empty;

        public string Name { get; set; } = string.Empty;
        public string Pillar { get; set; } = string.Empty;
        public string Emoji { get; set; } = string.Empty;
        public decimal CurrentPrice { get; set; }
        public decimal Change { get; set; }
        public decimal PercentChange { get; set; }
        public string Currency { get; set; } = "USD";
        public decimal? DayHigh { get; set; }
        public decimal? DayLow { get; set; }
        public long? Volume { get; set; }
        public DateTime? LastUpdatedAt { get; set; }
    }
}
