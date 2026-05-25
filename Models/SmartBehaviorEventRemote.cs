using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;
using System;

namespace Daily.Models
{
    [Table("behavior_events")]
    public class SmartBehaviorEventRemote : BaseModel
    {
        [PrimaryKey("id")]
        public string Id { get; set; } = string.Empty;

        [Column("user_id")]
        public string UserId { get; set; } = string.Empty;

        [Column("feature")]
        public string Feature { get; set; } = string.Empty;

        [Column("action_type")]
        public string ActionType { get; set; } = string.Empty;

        [Column("metadata")]
        public string Metadata { get; set; } = string.Empty;

        [Column("timestamp")]
        public DateTime Timestamp { get; set; }
    }
}
