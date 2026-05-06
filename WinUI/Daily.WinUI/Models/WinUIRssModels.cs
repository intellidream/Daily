using System;

namespace Daily.Models
{
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
        public bool IsRead { get; set; }
        public bool IsSaved { get; set; }
        public bool IsFavorite { get; set; }
    }

    public enum FeedType
    {
        Rss,
        WpJson
    }

    public enum FeedCategory
    {
        Local,
        World,
        Tech,
        Gaming,
        Markets
    }

    public class FeedSource
    {
        public string Name { get; set; } = string.Empty;
        public string Url { get; set; } = string.Empty;
        public FeedType Type { get; set; }
        public FeedCategory Category { get; set; }
        public string? IconUrl { get; set; }
    }
}
