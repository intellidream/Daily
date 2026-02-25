using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;
using System;

namespace Daily.Models
{
    [Table("watch_pairings")]
    public class WatchPairing : BaseModel
    {
        [PrimaryKey("code")]
        public string Code { get; set; }
        
        [Column("access_token")]
        public string AccessToken { get; set; }
        
        [Column("refresh_token")]
        public string RefreshToken { get; set; }
        
        [Column("created_at", ignoreOnInsert: true, ignoreOnUpdate: true)]
        public DateTime? CreatedAt { get; set; }
    }
}
