namespace Daily.Models
{
    public class VideoItem
    {
        public string Title { get; set; } = "";
        public string ChannelTitle { get; set; } = "";
        public string ThumbnailUrl { get; set; } = "";
        public string Duration { get; set; } = "";
        public string Url { get; set; } = "";
        public string Platform { get; set; } = "YouTube"; // For future Spotify expansion
    }
}
