using System;
using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

namespace Daily.Models
{
    [Table("calendar_accounts")]
    public class CalendarAccount : BaseModel
    {
        [PrimaryKey("id")]
        public Guid Id { get; set; }

        [Column("user_id")]
        public Guid UserId { get; set; }

        [Column("account_type")]
        public string AccountType { get; set; } = string.Empty; // "Google", "MicrosoftPersonal", "MicrosoftWork", "Yahoo"

        [Column("email")]
        public string Email { get; set; } = string.Empty;

        [Column("access_token")]
        public string AccessToken { get; set; } = string.Empty; // Will be stored encrypted

        [Column("refresh_token")]
        public string RefreshToken { get; set; } = string.Empty; // Will be stored encrypted

        [Column("token_expires_at")]
        public DateTime TokenExpiresAt { get; set; }

        [Column("color")]
        public string Color { get; set; } = "#FF594AE2";

        [Column("custom_name")]
        public string CustomName { get; set; } = string.Empty;

        [Column("identified_name")]
        public string IdentifiedName { get; set; } = string.Empty;

        [Column("display_order")]
        public int DisplayOrder { get; set; }

        [Column("is_active")]
        public bool IsActive { get; set; }

        [Column("created_at")]
        public DateTime CreatedAt { get; set; }

        [Column("updated_at")]
        public DateTime? UpdatedAt { get; set; }

        [Newtonsoft.Json.JsonIgnore]
        public DateTime? SyncedAt { get; set; }
    }
}
