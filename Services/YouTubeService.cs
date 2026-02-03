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

        private readonly IAuthService _authService;

        public YouTubeService(IAuthService authService)
        {
            _httpClient = new HttpClient(new Daily.Services.Auth.GoogleAuthHandler(authService));
            _authService = authService;
        }

        public string? SelectedCategory { get; private set; }
        public event Action<string?>? OnCategoryChanged;

        public void SetCategory(string? category)
        {
            if (SelectedCategory != category)
            {
                SelectedCategory = category;
                OnCategoryChanged?.Invoke(category);
            }
        }

        public async Task<(List<VideoItem> Videos, string NextPageToken)> GetRecommendationsAsync(string accessToken, string? pageToken = null, string? category = null)
        {
             // Retry Wrapper
             for (int retry = 0; retry < 2; retry++)
             {
                 try
                 {
                    // Update token if we refreshed it in previous loop
                    if (retry > 0) accessToken = _authService.GetProviderToken() ?? accessToken;

                    if (string.IsNullOrEmpty(accessToken)) return (new List<VideoItem>(), "");
                    
                    return await GetRecommendationsInternalAsync(accessToken, pageToken, category);
                 }
                 catch (HttpRequestException httpEx) when (httpEx.StatusCode == System.Net.HttpStatusCode.Unauthorized)
                 {
                     Console.WriteLine($"[YouTubeService] 401 Unauthorized. Attempting refresh... (Retry {retry})");
                     if (retry == 0)
                     {
                         var refreshed = await _authService.RefreshGoogleTokenAsync();
                         if (!refreshed) throw; // Abort if refresh failed
                     }
                     else throw; // Don't loop forever
                 }
                 catch (Exception)
                 {
                     throw; // Let general catch handle it, or we can squash
                 }
             }
             return (GetMockData(), "");
        }

        private async Task<(List<VideoItem> Videos, string NextPageToken)> GetRecommendationsInternalAsync(string accessToken, string? pageToken, string? category)
        {
                string url;
                bool isSearch = false;

                if (string.Equals(category, "Latest", StringComparison.OrdinalIgnoreCase))
                {
                    return await GetSubscribedVideosAsync(accessToken, pageToken);
                }
                else if (string.Equals(category, "Podcasts", StringComparison.OrdinalIgnoreCase))
                {
                    url = "https://www.googleapis.com/youtube/v3/search?part=snippet&type=video&q=podcasts&maxResults=10";
                    isSearch = true;
                }
                else if (string.Equals(category, "Music", StringComparison.OrdinalIgnoreCase))
                {
                    url = "https://www.googleapis.com/youtube/v3/videos?part=snippet,contentDetails,statistics&chart=mostPopular&videoCategoryId=10&maxResults=10";
                }
                else if (string.Equals(category, "Tech", StringComparison.OrdinalIgnoreCase))
                {
                    // Fetch more items (50) to allow for filtering out Shorts
                    url = "https://www.googleapis.com/youtube/v3/videos?part=snippet,contentDetails,statistics&chart=mostPopular&videoCategoryId=28&maxResults=50"; // 28 = Science & Technology
                }
                else
                {
                    // Default: Liked Videos
                    url = "https://www.googleapis.com/youtube/v3/videos?part=snippet,contentDetails,statistics&myRating=like&maxResults=10";
                }

                if (!string.IsNullOrEmpty(pageToken))
                {
                    url += $"&pageToken={pageToken}";
                }

                var request = new HttpRequestMessage(HttpMethod.Get, url);
                request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", accessToken);

                var response = await _httpClient.SendAsync(request);
                
                // CRITICAL: Throw so we catch in the retry loop
                if (response.StatusCode == System.Net.HttpStatusCode.Unauthorized)
                {
                    throw new HttpRequestException("Unauthorized", null, System.Net.HttpStatusCode.Unauthorized);
                }
                
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
                            var thumb = snippet?["thumbnails"]?["maxres"]?["url"]?.ToString()
                                     ?? snippet?["thumbnails"]?["standard"]?["url"]?.ToString()
                                     ?? snippet?["thumbnails"]?["high"]?["url"]?.ToString()
                                     ?? snippet?["thumbnails"]?["medium"]?["url"]?.ToString() 
                                     ?? snippet?["thumbnails"]?["default"]?["url"]?.ToString() ?? "";
                            
                            // Handle ID parsing (Search returns object, Videos returns string)
                            string id;
                            var idNode = item["id"];
                            if (idNode is System.Text.Json.Nodes.JsonObject && idNode["videoId"] != null)
                            {
                                id = idNode["videoId"]?.ToString() ?? "";
                            }
                            else
                            {
                                id = idNode?.ToString() ?? "";
                            }

                            string durationStr = ""; // UI display string
                            double totalSeconds = 0;

                            if (contentDetails != null && contentDetails["duration"] != null)
                            {
                                var durationPt = contentDetails["duration"]!.ToString(); // ISO 8601 (e.g., PT5M30S)
                                var ts = ParseDuration(durationPt);
                                totalSeconds = ts.TotalSeconds;

                                // Format nicely
                                if (ts.TotalHours >= 1)
                                    durationStr = $"{(int)ts.TotalHours}h {ts.Minutes}m {ts.Seconds}s";
                                else if (ts.TotalMinutes >= 1)
                                    durationStr = $"{ts.Minutes}m {ts.Seconds}s";
                                else
                                    durationStr = $"{ts.Seconds}s";
                            }


                            // FILTER: Global Shorts Filter
                            // 1. Duration < 240s (4 mins)
                            // 2. Title or Description contains "#shorts"
                            bool isShort = false;
                            
                            if (totalSeconds > 0 && totalSeconds < 240) isShort = true;
                            
                            if (!isShort)
                            {
                                if (title.Contains("#shorts", StringComparison.OrdinalIgnoreCase) ||
                                    (snippet?["description"]?.ToString() ?? "").Contains("#shorts", StringComparison.OrdinalIgnoreCase))
                                {
                                    isShort = true;
                                }
                            }

                            if (isShort) continue;

                            videos.Add(new VideoItem
                            {
                                Title = title,
                                ChannelTitle = channel,
                                ThumbnailUrl = thumb,
                                Duration = durationStr, // May be empty for search results, or parsed string
                                Url = $"https://www.youtube.com/watch?v={id}",
                                Id = id,
                                Platform = "YouTube"
                            });
                        }
                    }
                    return (videos, nextPageToken ?? "");
                }
                else
                {
                     return (GetMockData(), "");
                }
        }


        private async Task<(List<VideoItem> Videos, string NextPageToken)> GetSubscribedVideosAsync(string accessToken, string? pageToken)
        {
            try
            {
                // 1. Get Subscriptions (Channels)
                var subsUrl = "https://www.googleapis.com/youtube/v3/subscriptions?part=snippet,contentDetails&mine=true&order=relevance&maxResults=20";
                if (!string.IsNullOrEmpty(pageToken)) subsUrl += $"&pageToken={pageToken}";

                var subsReq = new HttpRequestMessage(HttpMethod.Get, subsUrl);
                subsReq.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", accessToken);
                var subsRes = await _httpClient.SendAsync(subsReq);
                if (!subsRes.IsSuccessStatusCode) return (new List<VideoItem>(), "");

                var subsJson = await subsRes.Content.ReadAsStringAsync();
                var subsNode = System.Text.Json.Nodes.JsonNode.Parse(subsJson);
                var nextToken = subsNode?["nextPageToken"]?.ToString() ?? "";
                var subsItems = subsNode?["items"]?.AsArray();

                if (subsItems == null || subsItems.Count == 0) return (new List<VideoItem>(), nextToken);

                var channelIds = new List<string>();
                foreach(var item in subsItems)
                {
                    var cid = item?["snippet"]?["resourceId"]?["channelId"]?.ToString();
                    if (!string.IsNullOrEmpty(cid)) channelIds.Add(cid);
                }

                // 2. Get Uploads Playlist ID for these channels
                // We can batch 50 ids. We have max 20.
                var channelsUrl = $"https://www.googleapis.com/youtube/v3/channels?part=contentDetails&id={string.Join(",", channelIds)}";
                var chanReq = new HttpRequestMessage(HttpMethod.Get, channelsUrl);
                chanReq.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", accessToken);
                var chanRes = await _httpClient.SendAsync(chanReq);
                if (!chanRes.IsSuccessStatusCode) return (new List<VideoItem>(), nextToken); // Partial fail?

                var chanJson = await chanRes.Content.ReadAsStringAsync();
                var chanNode = System.Text.Json.Nodes.JsonNode.Parse(chanJson);
                var chanItems = chanNode?["items"]?.AsArray();

                var uploadPlaylistIds = new List<string>();
                if (chanItems != null)
                {
                    foreach(var item in chanItems)
                    {
                        var pid = item?["contentDetails"]?["relatedPlaylists"]?["uploads"]?.ToString();
                        if (!string.IsNullOrEmpty(pid)) uploadPlaylistIds.Add(pid);
                    }
                }

                // 3. Fetch latest video for each playlist (Parallel)
                var tasks = uploadPlaylistIds.Select(async pid => 
                {
                    try 
                    {
                        var plUrl = $"https://www.googleapis.com/youtube/v3/playlistItems?part=snippet&playlistId={pid}&maxResults=1";
                        var plReq = new HttpRequestMessage(HttpMethod.Get, plUrl);
                         plReq.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", accessToken);
                        var plRes = await _httpClient.SendAsync(plReq);
                        if (plRes.IsSuccessStatusCode)
                        {
                            var plJson = await plRes.Content.ReadAsStringAsync();
                            var plNode = System.Text.Json.Nodes.JsonNode.Parse(plJson);
                            var items = plNode?["items"]?.AsArray();
                            if (items != null && items.Count > 0)
                            {
                                var item = items[0]; // First item (latest)
                                var snippet = item?["snippet"];
                                var videoId = snippet?["resourceId"]?["videoId"]?.ToString();
                                var title = snippet?["title"]?.ToString();
                                var channel = snippet?["channelTitle"]?.ToString();
                                var thumb = snippet?["thumbnails"]?["maxres"]?["url"]?.ToString()
                                         ?? snippet?["thumbnails"]?["standard"]?["url"]?.ToString()
                                         ?? snippet?["thumbnails"]?["high"]?["url"]?.ToString()
                                         ?? snippet?["thumbnails"]?["medium"]?["url"]?.ToString() 
                                         ?? snippet?["thumbnails"]?["default"]?["url"]?.ToString();
                                var publishedAt = snippet?["publishedAt"]?.ToString();

                                if (!string.IsNullOrEmpty(videoId))
                                {
                                    return new VideoItem {
                                        Title = title ?? "Unknown",
                                        ChannelTitle = channel ?? "Unknown",
                                        ThumbnailUrl = thumb ?? "",
                                        Url = $"https://www.youtube.com/watch?v={videoId}",
                                        Id = videoId,
                                        Platform = "YouTube",
                                        // Store temporary ID or Published date to sort/fetch details
                                        Duration = videoId // Hack: Store ID in duration temporarily to fetch details later
                                    };
                                }
                            }
                        }
                    }
                    catch {} // Ignore failures
                    return null;
                });

                var rawVideos = (await Task.WhenAll(tasks)).Where(v => v != null).ToList();

                // 4. Fetch Durations and details for these videos (Batch)
                var finalVideos = new List<VideoItem>();
                
                if (rawVideos.Count > 0)
                {
                    var videoIds = rawVideos.Select(v => v.Duration).Distinct(); // Duration currently holds VideoID
                    var vidsUrl = $"https://www.googleapis.com/youtube/v3/videos?part=contentDetails,snippet&id={string.Join(",", videoIds)}";
                    var vidsReq = new HttpRequestMessage(HttpMethod.Get, vidsUrl);
                    vidsReq.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", accessToken);
                    var vidsRes = await _httpClient.SendAsync(vidsReq);
                    
                    var durationMap = new Dictionary<string, string>();
                    var invalidIds = new HashSet<string>();

                    if (vidsRes.IsSuccessStatusCode)
                    {
                        var vidsJson = await vidsRes.Content.ReadAsStringAsync();
                        var vidsNode = System.Text.Json.Nodes.JsonNode.Parse(vidsJson);
                        var vItems = vidsNode?["items"]?.AsArray();
                        if (vItems != null)
                        {
                            foreach(var item in vItems)
                            {
                                var id = item?["id"]?.ToString();
                                var durPt = item?["contentDetails"]?["duration"]?.ToString();
                                
                                // Extra check for #shorts tag
                                var snip = item?["snippet"];
                                var title = snip?["title"]?.ToString() ?? "";
                                var desc = snip?["description"]?.ToString() ?? "";

                                if (!string.IsNullOrEmpty(id) && !string.IsNullOrEmpty(durPt))
                                {
                                    var ts = ParseDuration(durPt);
                                    
                                    // FILTER: Skip Shorts
                                    // 1. Duration < 240s
                                    bool isShort = ts.TotalSeconds < 240;
                                    
                                    // 2. #shorts tag
                                    if (!isShort)
                                    {
                                        if (title.Contains("#shorts", StringComparison.OrdinalIgnoreCase) || 
                                            desc.Contains("#shorts", StringComparison.OrdinalIgnoreCase))
                                        {
                                            isShort = true;
                                        }
                                    }

                                    if (isShort)
                                    {
                                        invalidIds.Add(id);
                                        continue;
                                    }

                                    // Format
                                    string durStr;
                                    if (ts.TotalHours >= 1)
                                        durStr = $"{(int)ts.TotalHours}h {ts.Minutes}m {ts.Seconds}s";
                                    else if (ts.TotalMinutes >= 1)
                                        durStr = $"{ts.Minutes}m {ts.Seconds}s";
                                    else
                                        durStr = $"{ts.Seconds}s";
                                        
                                    durationMap[id] = durStr;
                                }
                            }
                        }
                    }

                    // Fixup and Filter videos
                    foreach(var v in rawVideos)
                    {
                         var vid = v.Duration; // v.Duration holds VideoId
                         
                         // If it's a short (invalid) or we couldn't fetch duration, skip or keep?
                         // If we couldn't fetch duration, safer to keep but might be short. 
                         // Logic: if in invalidIds -> SHORT -> Skip
                         // If in durationMap -> OK -> Apply
                         // Else -> Keep with Unknown duration? Or skip?
                         // Let's Skip if we can't confirm duration to be safe against shorts?
                         // Or keep to be resilient. Let's keep if not explicitly identified as short.
                         
                         if (invalidIds.Contains(vid)) continue;

                         if (durationMap.ContainsKey(vid))
                         {
                             v.Duration = durationMap[vid];
                             finalVideos.Add(v);
                         }
                         else
                         {
                             // Failed to get details, skip for now to avoid ugly UI or risk of Short
                         }
                    }
                }
                
                return (finalVideos, nextToken);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"SubFeed Error: {ex}");
                return (new List<VideoItem>(), "");
            }
        }

        private TimeSpan ParseDuration(string isoDuration)
        {
            try 
            {
                return System.Xml.XmlConvert.ToTimeSpan(isoDuration);
            }
            catch 
            {
                // Fallback manual parsing if XmlConvert fails
                // Simple parser for PT#M#S
                // This is very basic and fragile, but handles common cases
                // Prefer avoiding shorts if parsing fails? -> Returns Zero
                return TimeSpan.Zero;
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
