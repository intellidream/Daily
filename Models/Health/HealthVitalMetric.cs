using System;
using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

namespace Daily.Models.Health
{
    [Table("health_vitals")]
    public class HealthVitalMetric : BaseModel
    {
        [PrimaryKey("id")]
        public Guid Id { get; set; } = Guid.NewGuid();

        [Column("user_id")]
        public Guid UserId { get; set; }

        [Column("type")]
        public string TypeString { get; set; }

        [Column("value")]
        public double Value { get; set; }

        [Column("unit")]
        public string Unit { get; set; }

        [Column("date")]
        public DateTime Date { get; set; }

        [Column("source_device")]
        public string SourceDevice { get; set; }

        [Column("created_at")]
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        [Column("updated_at")]
        public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

        public VitalMetric ToVitalMetric()
        {
            return new VitalMetric
            {
                Id = this.Id,
                UserId = this.UserId,
                TypeString = this.TypeString,
                Value = this.Value,
                Unit = this.Unit,
                Date = this.Date,
                SourceDevice = this.SourceDevice,
                CreatedAt = this.CreatedAt,
                UpdatedAt = this.UpdatedAt
            };
        }
    }
}
