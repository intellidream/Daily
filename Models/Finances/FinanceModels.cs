using System;

namespace Daily.Models.Finances
{
    // ==========================================
    // REMOTE MODELS (Supabase)
    // ==========================================

    [Supabase.Postgrest.Attributes.Table("accounts")]
    public class Account : Supabase.Postgrest.Models.BaseModel
    {
        [Supabase.Postgrest.Attributes.PrimaryKey("id")]
        public Guid Id { get; set; }

        [Supabase.Postgrest.Attributes.Column("user_id")]
        public Guid UserId { get; set; }

        [Supabase.Postgrest.Attributes.Column("name")]
        public string Name { get; set; }

        [Supabase.Postgrest.Attributes.Column("type")]
        public string Type { get; set; } // 'checking', 'savings', 'credit', 'investment'

        [Supabase.Postgrest.Attributes.Column("currency")]
        public string Currency { get; set; }

        [Supabase.Postgrest.Attributes.Column("current_balance")]
        public decimal CurrentBalance { get; set; }

        [Supabase.Postgrest.Attributes.Column("created_at")]
        public DateTime CreatedAt { get; set; }

        [Supabase.Postgrest.Attributes.Column("updated_at")]
        public DateTime? UpdatedAt { get; set; }
    }

    [Supabase.Postgrest.Attributes.Table("transactions")]
    public class Transaction : Supabase.Postgrest.Models.BaseModel
    {
        [Supabase.Postgrest.Attributes.PrimaryKey("id")]
        public Guid Id { get; set; }

        [Supabase.Postgrest.Attributes.Column("account_id")]
        public Guid AccountId { get; set; }

        [Supabase.Postgrest.Attributes.Column("date")]
        public DateTime Date { get; set; }

        [Supabase.Postgrest.Attributes.Column("amount")]
        public decimal Amount { get; set; }

        [Supabase.Postgrest.Attributes.Column("category")]
        public string? Category { get; set; }

        [Supabase.Postgrest.Attributes.Column("description")]
        public string? Description { get; set; }

        [Supabase.Postgrest.Attributes.Column("created_at")]
        public DateTime CreatedAt { get; set; }

        [Supabase.Postgrest.Attributes.Column("updated_at")]
        public DateTime? UpdatedAt { get; set; }
    }

    [Supabase.Postgrest.Attributes.Table("securities")]
    public class Security : Supabase.Postgrest.Models.BaseModel
    {
        [Supabase.Postgrest.Attributes.PrimaryKey("symbol")]
        public string Symbol { get; set; } // PK is text

        [Supabase.Postgrest.Attributes.Column("name")]
        public string? Name { get; set; }

        [Supabase.Postgrest.Attributes.Column("type")]
        public string? Type { get; set; }

        [Supabase.Postgrest.Attributes.Column("latest_price")]
        public decimal LatestPrice { get; set; }

        [Supabase.Postgrest.Attributes.Column("last_updated_at")]
        public DateTime? LastUpdatedAt { get; set; }
    }

    [Supabase.Postgrest.Attributes.Table("holdings")]
    public class Holding : Supabase.Postgrest.Models.BaseModel
    {
        [Supabase.Postgrest.Attributes.PrimaryKey("id")]
        public Guid Id { get; set; }

        [Supabase.Postgrest.Attributes.Column("account_id")]
        public Guid AccountId { get; set; }

        [Supabase.Postgrest.Attributes.Column("security_symbol")]
        public string SecuritySymbol { get; set; }

        [Supabase.Postgrest.Attributes.Column("quantity")]
        public decimal Quantity { get; set; }

        [Supabase.Postgrest.Attributes.Column("cost_basis")]
        public decimal CostBasis { get; set; }

        [Supabase.Postgrest.Attributes.Column("created_at")]
        public DateTime CreatedAt { get; set; }

        [Supabase.Postgrest.Attributes.Column("updated_at")]
        public DateTime? UpdatedAt { get; set; }
    }

    // ==========================================
    // LOCAL MODELS (SQLite)
    // ==========================================

    [SQLite.Table("accounts")]
    public class LocalAccount
    {
        [SQLite.PrimaryKey]
        public string Id { get; set; }

        [SQLite.Indexed]
        public string UserId { get; set; }

        public string Name { get; set; }
        public string Type { get; set; }
        public string Currency { get; set; }
        public decimal CurrentBalance { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }

        [SQLite.Indexed]
        public DateTime? SyncedAt { get; set; }
        public bool IsDeleted { get; set; }
    }

    [SQLite.Table("transactions")]
    public class LocalTransaction
    {
        [SQLite.PrimaryKey]
        public string Id { get; set; }

        [SQLite.Indexed]
        public string AccountId { get; set; }

        public DateTime Date { get; set; }
        public decimal Amount { get; set; }
        public string? Category { get; set; }
        public string? Description { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }

        [SQLite.Indexed]
        public DateTime? SyncedAt { get; set; }
        public bool IsDeleted { get; set; }
    }

    [SQLite.Table("securities")]
    public class LocalSecurity
    {
        [SQLite.PrimaryKey]
        public string Symbol { get; set; }

        public string? Name { get; set; }
        public string? Type { get; set; }
        public decimal LatestPrice { get; set; }
        public decimal Change { get; set; }
        public decimal PercentChange { get; set; }
        public DateTime? LastUpdatedAt { get; set; }
    }

    [SQLite.Table("holdings")]
    public class LocalHolding
    {
        [SQLite.PrimaryKey]
        public string Id { get; set; }

        [SQLite.Indexed]
        public string AccountId { get; set; }

        [SQLite.Indexed]
        public string SecuritySymbol { get; set; }

        public decimal Quantity { get; set; }
        public decimal CostBasis { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }

        [SQLite.Indexed]
        public DateTime? SyncedAt { get; set; }
        public bool IsDeleted { get; set; }
    }
}
