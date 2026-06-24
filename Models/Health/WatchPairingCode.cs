using System;
using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

namespace Daily.Models.Health
{
    [Table("watch_pairing_codes")]
    public class WatchPairingCode : BaseModel
    {
        [PrimaryKey("pin_code", false)] // pin_code is the primary key
        public string PinCode { get; set; } = string.Empty;

        [Column("user_id")]
        public Guid UserId { get; set; }

        [Column("created_at")]
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        [Column("expires_at")]
        public DateTime ExpiresAt { get; set; }

        [Column("claimed")]
        public bool Claimed { get; set; }
    }
}
