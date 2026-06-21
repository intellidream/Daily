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
}
