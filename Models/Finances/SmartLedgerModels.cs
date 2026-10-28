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

    // ==========================================
    // ACCOUNT BALANCE (For Visualizations)
    // ==========================================
    public class AccountBalance
    {
        public string Category { get; set; } = string.Empty;
        public string AccountName { get; set; } = string.Empty;
        public decimal Balance { get; set; }
    }

    // ==========================================
    // RECURRING TRANSACTIONS (Supabase)
    // ==========================================

    [Supabase.Postgrest.Attributes.Table("recurring_transactions")]
    public class RecurringTransaction : Supabase.Postgrest.Models.BaseModel
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

        [Supabase.Postgrest.Attributes.Column("frequency")]
        public string Frequency { get; set; } = string.Empty;

        [Supabase.Postgrest.Attributes.Column("next_run_at")]
        public DateTime NextRunAt { get; set; }

        [Supabase.Postgrest.Attributes.Column("created_at")]
        public DateTime CreatedAt { get; set; }
    }

    // ==========================================
    // LOCAL RECURRING TRANSACTIONS (SQLite)
    // ==========================================

    [Table("local_recurring_transactions")]
    public class LocalRecurringTransaction
    {
        [PrimaryKey]
        public string Id { get; set; } = string.Empty; // UUID string

        [Indexed]
        public string UserId { get; set; } = string.Empty; // Supabase user ID

        public string Source { get; set; } = string.Empty;
        public string Target { get; set; } = string.Empty;
        public decimal Amount { get; set; }
        public string ActionType { get; set; } = string.Empty;
        public string Frequency { get; set; } = string.Empty;
        public DateTime NextRunAt { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? SyncedAt { get; set; }
        public bool IsDeleted { get; set; }
    }

    // ==========================================
    // SMART LEDGER AST / PARSED DOMAIN MODELS
    // ==========================================

    public class SmartLedgerItem
    {
        public string Id { get; set; } = Guid.NewGuid().ToString();
        public string SectionName { get; set; } = string.Empty;
        public int LineIndex { get; set; } = -1;
        public string RawLine { get; set; } = string.Empty;
        public string Key { get; set; } = string.Empty;
        public decimal RawAmount { get; set; }
        public decimal CalculatedAmount { get; set; }
        public string Currency { get; set; } = "Lei";
        public bool IsScaled { get; set; } = true;
        public List<string> Notes { get; set; } = new();
        public bool IsPureNote { get; set; }
        public decimal PercentageOfSection { get; set; }

        public string DisplayName
        {
            get
            {
                if (IsPureNote) return Key;
                var clean = System.Text.RegularExpressions.Regex.Replace(Key, @"\(.*?\)", "").Trim();
                clean = clean.TrimEnd('/');
                return string.IsNullOrWhiteSpace(clean) ? Key : clean;
            }
        }

        public string FormattedCalculatedAmount
        {
            get
            {
                if (Currency == "EUR")
                {
                    return RawAmount % 1 == 0 
                        ? $"{RawAmount:N0} €" 
                        : $"{RawAmount:N2} €";
                }
                return CalculatedAmount % 1 == 0 
                    ? $"{CalculatedAmount:N0} Lei" 
                    : $"{CalculatedAmount:N2} Lei";
            }
        }

        public string FormattedRawAmount
        {
            get
            {
                return RawAmount % 1 == 0
                    ? $"{RawAmount:F0}"
                    : $"{RawAmount:G}";
            }
        }
    }

    public class SmartLedgerSection
    {
        public string Name { get; set; } = string.Empty;
        public List<SmartLedgerItem> Items { get; set; } = new();
        public decimal TotalCalculated { get; set; }
        public decimal TotalRaw { get; set; }
        public bool IsScaled { get; set; } = true;

        public string FormattedTotal => TotalCalculated % 1 == 0 
            ? $"{TotalCalculated:N0} Lei" 
            : $"{TotalCalculated:N2} Lei";
    }

    public class ParsedSmartLedger
    {
        public List<SmartLedgerSection> Sections { get; set; } = new();
        public decimal IncomingTotal { get; set; }
        public decimal OutgoingTotal { get; set; }
        public decimal BalanceTotal { get; set; }
        public decimal DentistTotal { get; set; }
        public decimal DepositTotal { get; set; }
        public decimal NetWorth { get; set; }
        public decimal NetWorthEUR { get; set; }
        public string RawText { get; set; } = string.Empty;

        public string FormattedNetWorth => $"{NetWorth:N0} Lei";
        public string FormattedIncoming => $"{IncomingTotal:N0} Lei";
        public string FormattedOutgoing => $"{OutgoingTotal:N0} Lei";
        public string FormattedBalance => $"{BalanceTotal:N0} Lei";
    }
}
