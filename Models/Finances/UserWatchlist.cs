using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;
using System;

namespace Daily.Models.Finances
{
    [Table("watchlists")]
    public class UserWatchlist : BaseModel
    {
        [PrimaryKey("id", false)]
        public string Id { get; set; }

        [Column("user_id")]
        public string UserId { get; set; }

        [Column("symbol")]
        public string Symbol { get; set; }

        [Column("display_order")]
        public int DisplayOrder { get; set; }

        [Column("created_at")]
        public DateTime CreatedAt { get; set; }

        // Join to get details
        [Reference(typeof(DbSecurity))]
        public DbSecurity Security { get; set; }
    }
}
