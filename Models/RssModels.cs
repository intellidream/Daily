using System;
using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

namespace Daily.Models
{
    public enum FeedType
    {
        Rss,
        WpJson
    }

    public enum FeedCategory
    {
        Local,
        Markets,
        World,
        Tech
    }

    public enum RssOverlayMode
    {
        None,
        Publications,
        ReadLater,
        Favorites
    }

    public enum SavedArticleType
    {
        ReadLater,
        Favorite
    }

    [Table("rss_saved_articles")]
    public class SavedArticle : BaseModel
    {
        [PrimaryKey("id")]
        public Guid Id { get; set; }

        [Column("user_id")]
        public Guid UserId { get; set; }

        [Column("article_url")]
        public string ArticleUrl { get; set; } = string.Empty;

        [Column("title")]
        public string Title { get; set; } = string.Empty;

        [Column("image_url")]
        public string? ImageUrl { get; set; }

        [Column("description")]
        public string? Description { get; set; }

        [Column("author")]
        public string? Author { get; set; }

        [Column("publication_name")]
        public string PublicationName { get; set; } = string.Empty;

        [Column("publication_icon_url")]
        public string? PublicationIconUrl { get; set; }

        [Column("article_type")]
        public string ArticleType { get; set; } = "ReadLater"; // "ReadLater" or "Favorite"

        [Column("article_date")]
        public DateTime ArticleDate { get; set; }

        [Column("created_at")]
        public DateTime CreatedAt { get; set; }

        [Column("updated_at")]
        public DateTime? UpdatedAt { get; set; }

        [Column("is_deleted")]
        public bool IsDeleted { get; set; }

        [Newtonsoft.Json.JsonIgnore]
        public DateTime? SyncedAt { get; set; }
    }

    public class FeedSource
    {
        public string Name { get; set; } = string.Empty;
        public string Url { get; set; } = string.Empty;
        public string IconUrl { get; set; } = string.Empty;
        public FeedType Type { get; set; }
        public FeedCategory Category { get; set; }

        public override bool Equals(object? o)
        {
            var other = o as FeedSource;
            return other?.Name == Name;
        }

        public override int GetHashCode() => Name?.GetHashCode() ?? 0;
        public override string ToString() => Name;
    }

    public class RssItem
    {
        public string Title { get; set; } = string.Empty;
        public string Link { get; set; } = string.Empty;
        public DateTime PublishDate { get; set; }
        public string? ImageUrl { get; set; }
        public string? Description { get; set; } // Summary/Excerpt
        public string? Content { get; set; }     // Full Content
        public string? Author { get; set; }

        public string? PublicationName { get; set; }
        public string? PublicationIconUrl { get; set; }
    }
}
