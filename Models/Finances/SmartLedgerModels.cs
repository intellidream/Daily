using System;
using SQLite;

namespace Daily.Models.Finances
{
    // ==========================================
    // REMOTE MODELS (Supabase)
    // ==========================================

    [Supabase.Postgrest.Attributes.Table("smart_ledgers")]
    public class SmartLedger : Supabase.Postgrest.Models.BaseModel
    {
        [Supabase.Postgrest.Attributes.PrimaryKey("id")]
        public Guid Id { get; set; }

        [Supabase.Postgrest.Attributes.Column("user_id")]
        public Guid UserId { get; set; }

        [Supabase.Postgrest.Attributes.Column("ledger_text")]
        public string LedgerText { get; set; } = string.Empty;

        [Supabase.Postgrest.Attributes.Column("created_at")]
        public DateTime CreatedAt { get; set; }

        [Supabase.Postgrest.Attributes.Column("updated_at")]
        public DateTime UpdatedAt { get; set; }
    }

    // ==========================================
    // LOCAL MODELS (SQLite)
    // ==========================================

    [Table("local_smart_ledgers")]
    public class LocalSmartLedger
    {
        [PrimaryKey]
        public string Id { get; set; } = string.Empty; // UUID string

        [Indexed]
        public string UserId { get; set; } = string.Empty; // Supabase user ID

        public string LedgerText { get; set; } = string.Empty;

        public DateTime CreatedAt { get; set; }
        public DateTime UpdatedAt { get; set; }
        public DateTime? SyncedAt { get; set; }
    }

    // ==========================================
    // LEDGER TRANSACTIONS (Supabase)
    // ==========================================

    [Supabase.Postgrest.Attributes.Table("ledger_transactions")]
    public class LedgerTransaction : Supabase.Postgrest.Models.BaseModel
    {
        [Supabase.Postgrest.Attributes.PrimaryKey("id")]
        public Guid Id { get; set; }

        [Supabase.Postgrest.Attributes.Column("user_id")]
        public Guid UserId { get; set; }

        [Supabase.Postgrest.Attributes.Column("source")]
        public string Source { get; set; } = string.Empty;

        [Supabase.Postgrest.Attributes.Column("target")]
        public string Target { get; set; } = string.Empty;

        [Supabase.Postgrest.Attributes.Column("amount")]
        public decimal Amount { get; set; }

        [Supabase.Postgrest.Attributes.Column("action_type")]
        public string ActionType { get; set; } = string.Empty;

        [Supabase.Postgrest.Attributes.Column("created_at")]
        public DateTime CreatedAt { get; set; }
    }

    // ==========================================
    // LOCAL LEDGER TRANSACTIONS (SQLite)
    // ==========================================

    [Table("local_ledger_transactions")]
    public class LocalLedgerTransaction
    {
        [PrimaryKey]
        public string Id { get; set; } = string.Empty; // UUID string

        [Indexed]
        public string UserId { get; set; } = string.Empty; // Supabase user ID

        public string Source { get; set; } = string.Empty;
        public string Target { get; set; } = string.Empty;
        public decimal Amount { get; set; }
        public string ActionType { get; set; } = string.Empty;

        public DateTime CreatedAt { get; set; }
        public DateTime? SyncedAt { get; set; }
        public bool IsDeleted { get; set; }
    }
}
