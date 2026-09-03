using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;
using System;

namespace Daily.Models
{
    [Table("habits_goals")]
    public class HabitGoal : BaseModel
    {
        [PrimaryKey("id")]
        public Guid Id { get; set; }

        [Column("user_id")]
        public Guid UserId { get; set; }

        [Column("habit_type")]
        public string HabitType { get; set; }

        [Column("target_value")]
        public double TargetValue { get; set; }

        [Column("unit")]
        public string Unit { get; set; }

        [Column("updated_at")]
        public DateTime? UpdatedAt { get; set; }

        [Column("created_at")]
        public DateTime CreatedAt { get; set; }

        [Newtonsoft.Json.JsonIgnore]
        public DateTime? SyncedAt { get; set; }

        [Column("is_deleted")]
        public bool IsDeleted { get; set; }
    }

    [Table("habits_logs")]
    public class HabitLog : BaseModel
    {
        [PrimaryKey("id")]
        public Guid Id { get; set; }

        [Column("user_id")]
        public Guid UserId { get; set; }

        [Column("habit_type")]
        public string HabitType { get; set; }

        [Column("value")]
        public double Value { get; set; }

        [Column("unit")]
        public string Unit { get; set; }

        [Column("logged_at")]
        public DateTime LoggedAt { get; set; }

        [Column("metadata")]
        [Newtonsoft.Json.JsonConverter(typeof(StringOrObjectJsonConverter))]
        public string? Metadata { get; set; }

        [Column("created_at")]
        public DateTime CreatedAt { get; set; }

        [Column("updated_at")]
        public DateTime? UpdatedAt { get; set; }

        // Local-only properties (not mapped to Supabase 'Column' unless consistent)
        // If we want to prevent these from sending to Supabase, we rely on Supabase client ignoring non-Column props?
        // Or we use [JsonIgnore] if using System.Text.Json, or explicit Ignore.
        // For now, let's assume simple POCO properties won't be sent if not decorating with Column? 
        // Actually Supabase client usually respects Column attribute. 
        // We will add them as properties.

        [Newtonsoft.Json.JsonIgnore]
        public DateTime? SyncedAt { get; set; }

        [Column("is_deleted")]
        public bool IsDeleted { get; set; }
    }

    [Table("habits_daily_summaries")]
    public class DailySummary : BaseModel
    {
        [PrimaryKey("id")]
        public Guid Id { get; set; }

        [Column("user_id")]
        public Guid UserId { get; set; }

        [Column("habit_type")]
        public string HabitType { get; set; }

        [Column("date")]
        public DateTime Date { get; set; }

        [Column("total_value")]
        public double TotalValue { get; set; }

        [Column("log_count")]
        public int LogCount { get; set; }

        [Column("metadata")]
        public string? Metadata { get; set; }

        [Column("created_at")]
        public DateTime CreatedAt { get; set; }

        [Column("updated_at")]
        public DateTime? UpdatedAt { get; set; }
    }

    public class StringOrObjectJsonConverter : Newtonsoft.Json.JsonConverter
    {
        public override bool CanConvert(Type objectType) => objectType == typeof(string);

        public override object? ReadJson(Newtonsoft.Json.JsonReader reader, Type objectType, object? existingValue, Newtonsoft.Json.JsonSerializer serializer)
        {
            if (reader.TokenType == Newtonsoft.Json.JsonToken.String)
                return reader.Value;

            if (reader.TokenType == Newtonsoft.Json.JsonToken.StartObject || reader.TokenType == Newtonsoft.Json.JsonToken.StartArray)
            {
                var token = Newtonsoft.Json.Linq.JToken.Load(reader);
                return token.ToString(Newtonsoft.Json.Formatting.None);
            }

            return null;
        }

        public override void WriteJson(Newtonsoft.Json.JsonWriter writer, object? value, Newtonsoft.Json.JsonSerializer serializer)
        {
            if (value == null)
            {
                writer.WriteNull();
                return;
            }
            writer.WriteValue(value.ToString());
        }
    }
}
