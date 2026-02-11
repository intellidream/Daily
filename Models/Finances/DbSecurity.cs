using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;
using System;
using Newtonsoft.Json;

namespace Daily.Models.Finances
{
    [Table("securities")]
    public class DbSecurity : BaseModel
    {
        [PrimaryKey("symbol")]
        public string Symbol { get; set; }

        [Column("name")]
        public string Name { get; set; }

        [Column("type")]
        public string Type { get; set; } // stock, forex, crypto, bond

        [Column("currency")]
        public string Currency { get; set; }

        [Column("exchange")]
        public string Exchange { get; set; }

        [Column("last_price")]
        public decimal? LastPrice { get; set; }

        [Column("last_updated_at")]
        public DateTime? LastUpdatedAt { get; set; }

        // Local Cache Fields (Not in Supabase/Postgres yet)
        // These will be saved to SQLite but ignored by Supabase Sync (due to missing [Column] and JsonIgnore)
        [JsonIgnore]
        public decimal? DayHigh { get; set; }
        [JsonIgnore]
        public decimal? DayLow { get; set; }
        [JsonIgnore]
        public long? Volume { get; set; }
        [JsonIgnore]
        public long? MarketCap { get; set; }
    }
}
