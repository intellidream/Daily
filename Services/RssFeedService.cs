using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Xml.Linq;
using Daily.Models;

namespace Daily.Services
{
    public class RssFeedService : IRssFeedService
    {
        public List<FeedSource> Feeds { get; } = new()
        {
            new FeedSource { Name = "Republica", Url = "https://republica.ro/rss", Type = FeedType.Rss, IconUrl = "https://www.google.com/s2/favicons?domain=republica.ro&sz=64" },
            new FeedSource { Name = "Zona IT", Url = "https://zonait.ro/wp-json/wp/v2/posts?per_page=20&_embed", Type = FeedType.WpJson, IconUrl = "https://www.google.com/s2/favicons?domain=zonait.ro&sz=64" },
            new FeedSource { Name = "BBC News", Url = "https://feeds.bbci.co.uk/news/rss.xml", Type = FeedType.Rss, IconUrl = "https://www.google.com/s2/favicons?domain=bbc.com&sz=64" },
            new FeedSource { Name = "Google News", Url = "https://news.google.com/rss?hl=en-US&gl=US&ceid=US:en", Type = FeedType.Rss, IconUrl = "https://www.google.com/s2/favicons?domain=news.google.com&sz=64" },
            new FeedSource { Name = "Windows Central", Url = "https://www.windowscentral.com/feeds.xml", Type = FeedType.Rss, IconUrl = "https://www.google.com/s2/favicons?domain=windowscentral.com&sz=64" }
        };

        public FeedSource CurrentFeed { get; private set; }
        public List<RssItem> Items { get; private set; } = new();
        public bool IsLoading { get; private set; }
        public string? Error { get; private set; }

        public event Action? OnFeedChanged;
        public event Action? OnItemsUpdated;

        private readonly HttpClient _httpClient;

        public RssFeedService()
        {
            CurrentFeed = Feeds.First();
            
            var handler = new HttpClientHandler
            {
                AutomaticDecompression = System.Net.DecompressionMethods.GZip | System.Net.DecompressionMethods.Deflate
            };
            _httpClient = new HttpClient(handler);
            _httpClient.Timeout = TimeSpan.FromSeconds(15);
            _httpClient.DefaultRequestHeaders.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36");
            _httpClient.DefaultRequestHeaders.Add("Accept", "application/rss+xml, application/xml, text/xml, */*");
        }

        public void SelectFeed(FeedSource feed)
        {
            if (CurrentFeed != feed)
            {
                CurrentFeed = feed;
                OnFeedChanged?.Invoke();
                _ = LoadFeedAsync(feed);
            }
        }

        public async Task ReloadCurrentFeedAsync()
        {
            if (CurrentFeed != null)
            {
                await LoadFeedAsync(CurrentFeed, true);
            }
        }

        public async Task LoadFeedAsync(FeedSource feed, bool forceRefresh = false)
        {
            // If already loading and not forcing, skip
            if (IsLoading && !forceRefresh) return;
            // If we have items for this feed (checked by reference or some cache key if we want) 
            // and not forcing, theoretically we could skip, but simpler to just load.
            
            IsLoading = true;
            Error = null;
            if (!forceRefresh)
            {
                Items = new List<RssItem>();
            }
            OnItemsUpdated?.Invoke(); // Notify loading state

            try
            {
                if (feed.Type == FeedType.Rss)
                {
                    await LoadRssFeedAsync(feed);
                }
                else if (feed.Type == FeedType.WpJson)
                {
                    await LoadWpJsonFeedAsync(feed);
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error loading feed: {ex.Message}");
                Error = $"Error loading feed: {ex.Message}";
                Items = new List<RssItem>();
            }
            finally
            {
                IsLoading = false;
                OnItemsUpdated?.Invoke();
            }
        }

        private async Task LoadRssFeedAsync(FeedSource feed)
        {
            var xml = await _httpClient.GetStringAsync(feed.Url);
            var doc = XDocument.Parse(xml);
            XNamespace media = "http://search.yahoo.com/mrss/";
            XNamespace contentNs = "http://purl.org/rss/1.0/modules/content/";

            var channelImage = doc.Descendants("channel").Elements().FirstOrDefault(e => e.Name.LocalName == "image")?.Elements().FirstOrDefault(e => e.Name.LocalName == "url")?.Value;

            Items = doc.Descendants("item").Select(item =>
            {
                var title = item.Element("title")?.Value ?? "No Title";
                var link = item.Element("link")?.Value ?? "";
                var description = item.Element("description")?.Value;
                var pubDateStr = item.Element("pubDate")?.Value;
                var contentEncoded = item.Element(contentNs + "encoded")?.Value;

                string? imageUrl = null;

                // 1. Media Content
                var mediaContent = item.Descendants().FirstOrDefault(e => e.Name.LocalName == "content" && e.Name.Namespace == media);
                if (mediaContent != null)
                {
                    imageUrl = mediaContent.Attribute("url")?.Value;
                }

                // 2. Media Thumbnail
                if (string.IsNullOrEmpty(imageUrl))
                {
                    var mediaThumbnail = item.Descendants().FirstOrDefault(e => e.Name.LocalName == "thumbnail");
                    imageUrl = mediaThumbnail?.Attribute("url")?.Value;
                }

                // 3. Enclosure
                if (string.IsNullOrEmpty(imageUrl))
                {
                    var enclosure = item.Element("enclosure");
                    if (enclosure != null && enclosure.Attribute("type")?.Value?.StartsWith("image/") == true)
                    {
                        imageUrl = enclosure.Attribute("url")?.Value;
                    }
                }

                // 4. Regex in Description
                if (string.IsNullOrEmpty(imageUrl) && !string.IsNullOrEmpty(description))
                {
                    var match = Regex.Match(description, @"<img.+?src=[""']([^""']+)[""']");
                    if (match.Success)
                    {
                        imageUrl = match.Groups[1].Value;
                    }
                }
                
                // 5. Regex in Content Encoded
                if (string.IsNullOrEmpty(imageUrl) && !string.IsNullOrEmpty(contentEncoded))
                {
                    var match = Regex.Match(contentEncoded, @"<img.+?src=[""']([^""']+)[""']");
                    if (match.Success)
                    {
                        imageUrl = match.Groups[1].Value;
                    }
                }

                return new RssItem
                {
                    Title = title,
                    Link = link,
                    PublishDate = DateTime.TryParse(pubDateStr, out var date) ? date : DateTime.Now,
                    ImageUrl = imageUrl ?? channelImage,
                    Description = description,
                    Content = contentEncoded
                };
            }).ToList();
        }

        private async Task LoadWpJsonFeedAsync(FeedSource feed)
        {
            var json = await _httpClient.GetStringAsync(feed.Url);
            var node = JsonNode.Parse(json);
            var posts = node?.AsArray();

            if (posts == null) 
            {
                Items = new List<RssItem>();
                return;
            }

            Items = new List<RssItem>();

            foreach (var post in posts)
            {
                var title = post["title"]?["rendered"]?.ToString();
                if (!string.IsNullOrEmpty(title))
                {
                    title = System.Net.WebUtility.HtmlDecode(title);
                }
                
                var link = post["link"]?.ToString() ?? "";
                var dateStr = post["date"]?.ToString();
                var date = DateTime.TryParse(dateStr, out var d) ? d : DateTime.Now;
                var content = post["content"]?["rendered"]?.ToString();
                var excerpt = post["excerpt"]?["rendered"]?.ToString();

                string? imageUrl = null;
                var embedded = post["_embedded"];
                if (embedded != null)
                {
                    var media = embedded["wp:featuredmedia"]?.AsArray()?.FirstOrDefault();
                    if (media != null)
                    {
                        imageUrl = media["source_url"]?.ToString();
                        // Try medium size if available
                         if (media["media_details"]?["sizes"]?["medium"]?["source_url"] != null)
                        {
                            imageUrl = media["media_details"]?["sizes"]?["medium"]?["source_url"]?.ToString();
                        }
                    }
                }
                
                Items.Add(new RssItem
                {
                     Title = title ?? "No Title",
                     Link = link,
                     PublishDate = date,
                     ImageUrl = imageUrl,
                     Description = excerpt,
                     Content = content
                });
            }
        }
        public async Task<RssItem> FetchFullArticleAsync(string url)
        {
            try
            {
                var reader = new SmartReader.Reader(url);
                var article = await reader.GetArticleAsync();

                if (article.IsReadable)
                {
                    return new RssItem
                    {
                        Title = article.Title,
                        Link = url,
                        Content = article.Content, // Full HTML
                        Description = article.Excerpt,
                        ImageUrl = article.FeaturedImage,
                        PublishDate = article.PublicationDate ?? DateTime.Now
                    };
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error fetching article: {ex.Message}");
            }

            // Fallback: Return empty item or throw, but here we'll return null-like
            // to indicate fetching failed, caller should handle it.
            // Actually, let's return a basic item
            return new RssItem { Link = url, Title = "Error fetching article" };
        }
    }
}
