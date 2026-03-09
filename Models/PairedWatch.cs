using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;
using System;

namespace Daily.Models
{
    [Table("paired_watches")]
    public class PairedWatch : BaseModel
    {
        [PrimaryKey("id", false)]
        [Column("id")]
        public string Id { get; set; }

        [Column("user_id")]
        public string UserId { get; set; }

        [Column("platform")]
        public string Platform { get; set; }

        [Column("device_name")]
        public string? DeviceName { get; set; }

        [Column("paired_at")]
        public DateTime? PairedAt { get; set; }

        [Column("last_token_push")]
        public DateTime? LastTokenPush { get; set; }

        [Column("pending_access_token")]
        public string? PendingAccessToken { get; set; }

        [Column("pending_refresh_token")]
        public string? PendingRefreshToken { get; set; }

        [Column("is_active")]
        public bool IsActive { get; set; } = true;
    }
}
