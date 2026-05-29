using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;
using System;

namespace Daily.Models
{
    [Table("smart_briefings")]
    public class SmartBriefingRemote : BaseModel
    {
        [PrimaryKey("user_id")]
        public string UserId { get; set; } = string.Empty;

        [Column("serialized_data")]
        public string SerializedData { get; set; } = string.Empty;

        [Column("timestamp")]
        public DateTime Timestamp { get; set; }
    }
}
