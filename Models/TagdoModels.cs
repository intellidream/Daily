using System;
using System.Collections.Generic;
using SQLite;

namespace Daily.Models
{
    public enum TagDoPillType
    {
        Standard,
        Financial,
        Urgent,
        TemporalOrMetric,
        Completed
    }

    public class TagDoPill
    {
        public string Id { get; set; } = Guid.NewGuid().ToString();
        public string Text { get; set; } = string.Empty;
        public TagDoPillType Type { get; set; } = TagDoPillType.Standard;
        public bool IsCompleted { get; set; } = false;

        public TagDoPill() { }

        public TagDoPill(string text, TagDoPillType type, bool isCompleted = false)
        {
            Id = Guid.NewGuid().ToString();
            Text = text;
            Type = type;
            IsCompleted = isCompleted;
        }
    }

    public class TagDoCluster
    {
        public string Id { get; set; } = Guid.NewGuid().ToString();
        public List<TagDoPill> Pills { get; set; } = new();
    }

    public class TagDoStream
    {
        public string Id { get; set; } = Guid.NewGuid().ToString();
        public int OrderIndex { get; set; }
        public string Title { get; set; } = string.Empty;
        public string? CustomTitle { get; set; }
        public string RawText { get; set; } = string.Empty;
        public DateTime? StreamReminder { get; set; }
        public string ActiveMemos { get; set; } = string.Empty;
        public string AttachmentsJson { get; set; } = "[]";
        public List<TagDoCluster> Clusters { get; set; } = new();

        public string DisplayTitle => !string.IsNullOrWhiteSpace(CustomTitle) ? CustomTitle : Title;

        public TagDoPill? DrivingPill => Clusters.Count > 0 && Clusters[0].Pills.Count > 0 ? Clusters[0].Pills[0] : null;

        public IEnumerable<TagDoPill> AllPills
        {
            get
            {
                foreach (var cluster in Clusters)
                {
                    foreach (var pill in cluster.Pills)
                    {
                        yield return pill;
                    }
                }
            }
        }
    }

    public class TagDoQuickNote
    {
        public string Id { get; set; } = Guid.NewGuid().ToString();
        public string? UserId { get; set; }
        public string Title { get; set; } = string.Empty;
        public string Content { get; set; } = string.Empty;
        public bool IsPinned { get; set; }
        public List<string> Tags { get; set; } = new();
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
        public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    }

    // ── Local SQLite Entities ──────────────────────────────────────────────

    [Table("tagdos_streams")]
    public class LocalTagdoStream
    {
        [PrimaryKey]
        public string Id { get; set; } = Guid.NewGuid().ToString();

        [Indexed]
        public int OrderIndex { get; set; }

        public string Title { get; set; } = string.Empty;
        public string? CustomTitle { get; set; }
        public string RawText { get; set; } = string.Empty;
        public long? StreamReminderTicks { get; set; }
        public string ActiveMemos { get; set; } = string.Empty;
        public string AttachmentsJson { get; set; } = "[]";
        public long UpdatedAtTicks { get; set; } = DateTime.UtcNow.Ticks;
        public long? SyncedAtTicks { get; set; }
    }

    [Table("tagdos_quick_notes")]
    public class LocalTagdoQuickNote
    {
        [PrimaryKey]
        public string Id { get; set; } = Guid.NewGuid().ToString();

        public string? UserId { get; set; }
        public string Title { get; set; } = string.Empty;
        public string Content { get; set; } = string.Empty;
        public bool IsPinned { get; set; }
        public string TagsJson { get; set; } = "[]";
        public long CreatedAtTicks { get; set; } = DateTime.UtcNow.Ticks;
        public long UpdatedAtTicks { get; set; } = DateTime.UtcNow.Ticks;
        public long? SyncedAtTicks { get; set; }
    }

    // ── Supabase Postgrest Entities ─────────────────────────────────────────

    [Supabase.Postgrest.Attributes.Table("tagdos_streams")]
    public class RemoteTagdoStream : Supabase.Postgrest.Models.BaseModel
    {
        [Supabase.Postgrest.Attributes.PrimaryKey("id")]
        [Supabase.Postgrest.Attributes.Column("id")]
        public string Id { get; set; } = string.Empty;

        [Supabase.Postgrest.Attributes.Column("user_id")]
        public string? UserId { get; set; }

        [Supabase.Postgrest.Attributes.Column("order_index")]
        public int OrderIndex { get; set; }

        [Supabase.Postgrest.Attributes.Column("title")]
        public string Title { get; set; } = string.Empty;

        [Supabase.Postgrest.Attributes.Column("raw_text")]
        public string RawText { get; set; } = string.Empty;

        [Supabase.Postgrest.Attributes.Column("stream_reminder")]
        public DateTime? StreamReminder { get; set; }

        [Supabase.Postgrest.Attributes.Column("active_memos")]
        public string? ActiveMemos { get; set; }

        [Supabase.Postgrest.Attributes.Column("updated_at")]
        public DateTime UpdatedAt { get; set; }
    }

    [Supabase.Postgrest.Attributes.Table("tagdos_quick_notes")]
    public class RemoteTagdoQuickNote : Supabase.Postgrest.Models.BaseModel
    {
        [Supabase.Postgrest.Attributes.PrimaryKey("id")]
        [Supabase.Postgrest.Attributes.Column("id")]
        public string Id { get; set; } = string.Empty;

        [Supabase.Postgrest.Attributes.Column("user_id")]
        public string? UserId { get; set; }

        [Supabase.Postgrest.Attributes.Column("title")]
        public string Title { get; set; } = string.Empty;

        [Supabase.Postgrest.Attributes.Column("content")]
        public string Content { get; set; } = string.Empty;

        [Supabase.Postgrest.Attributes.Column("is_pinned")]
        public bool IsPinned { get; set; }

        [Supabase.Postgrest.Attributes.Column("created_at")]
        public DateTime CreatedAt { get; set; }

        [Supabase.Postgrest.Attributes.Column("updated_at")]
        public DateTime UpdatedAt { get; set; }
    }
}
