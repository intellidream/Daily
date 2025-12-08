using System;

namespace Daily.Models
{
    public enum FeedType
    {
        Rss,
        WpJson
    }

    public class FeedSource
    {
        public string Name { get; set; } = string.Empty;
        public string Url { get; set; } = string.Empty;
        public string IconUrl { get; set; } = string.Empty;
        public FeedType Type { get; set; }

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
    }
}
