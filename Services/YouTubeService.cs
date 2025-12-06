using Daily.Models;
using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Threading.Tasks;

namespace Daily.Services
{
    public class YouTubeService : IYouTubeService
    {
        private readonly HttpClient _httpClient;

        public YouTubeService()
        {
            _httpClient = new HttpClient();
        }

        public async Task<(List<VideoItem> Videos, string NextPageToken)> GetRecommendationsAsync(string accessToken, string? pageToken = null)
        {
            if (string.IsNullOrEmpty(accessToken))
            {
               return (new List<VideoItem>(), null);
            }

            try
            {
                var url = "https://www.googleapis.com/youtube/v3/videos?part=snippet,contentDetails,statistics&myRating=like&maxResults=10";
                if (!string.IsNullOrEmpty(pageToken))
                {
                    url += $"&pageToken={pageToken}";
                }

                var request = new HttpRequestMessage(HttpMethod.Get, url);
                request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", accessToken);

                var response = await _httpClient.SendAsync(request);
                if (response.IsSuccessStatusCode)
                {
                    var json = await response.Content.ReadAsStringAsync();
                    var node = System.Text.Json.Nodes.JsonNode.Parse(json);
                    
                    var nextPageToken = node?["nextPageToken"]?.ToString();
                    var items = node?["items"]?.AsArray();

                    var videos = new List<VideoItem>();

                    if (items != null)
                    {
                        foreach (var item in items)
                        {
                            var snippet = item["snippet"];
                            var contentDetails = item["contentDetails"];

                            var title = snippet?["title"]?.ToString() ?? "Unknown";
                            var channel = snippet?["channelTitle"]?.ToString() ?? "Unknown";
                            var thumb = snippet?["thumbnails"]?["medium"]?["url"]?.ToString() 
                                     ?? snippet?["thumbnails"]?["default"]?["url"]?.ToString() ?? "";
                            var id = item["id"]?.ToString() ?? "";
                            var durationPt = contentDetails?["duration"]?.ToString() ?? "";

                            string duration = durationPt.Replace("PT", "").Replace("H", "h ").Replace("M", "m ").Replace("S", "s");

                            videos.Add(new VideoItem
                            {
                                Title = title,
                                ChannelTitle = channel,
                                ThumbnailUrl = thumb,
                                Duration = duration.ToLower(),
                                Url = $"https://www.youtube.com/watch?v={id}",
                                Platform = "YouTube"
                            });
                        }
                    }
                    return (videos, nextPageToken);
                }
                else
                {
                    Console.WriteLine($"YouTube API Error: {response.StatusCode}");
                    // Fallback to mock if API fails (e.g. quota, permissions)
                    return (GetMockData(), null); 
                }
            }
            catch (Exception ex)
            {
                 Console.WriteLine($"YouTube Exception: {ex}");
                 return (GetMockData(), null);
            }
        }

        private List<VideoItem> GetMockData()
        {
             return new List<VideoItem>
                {
                    new VideoItem { Title = "Understanding .NET MAUI Bindings", ChannelTitle = "Microsoft Developer", ThumbnailUrl = "https://img.youtube.com/vi/dQw4w9WgXcQ/mqdefault.jpg", Duration = "12:34", Url = "https://www.youtube.com/watch?v=dQw4w9WgXcQ" },
                    new VideoItem { Title = "Blazor Hybrid vs Web Assembly", ChannelTitle = "dotnet", ThumbnailUrl = "https://img.youtube.com/vi/dQw4w9WgXcQ/mqdefault.jpg", Duration = "08:15", Url = "https://www.youtube.com/watch?v=dQw4w9WgXcQ" },
                    // ...
                };
        }
    }
}
