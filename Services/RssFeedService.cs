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
        public List<FeedSource> Feeds { get; private set; } = new();

        public FeedSource CurrentFeed { get; private set; }
        public List<RssItem> Items { get; private set; } = new();
        public bool IsLoading { get; private set; }
        public string? Error { get; private set; }

        public event Action? OnFeedChanged;
        public event Action? OnItemsUpdated;

        private readonly HttpClient _httpClient;
        private readonly IRenderedHtmlService? _renderedHtmlService;
        private readonly IDatabaseService? _databaseService;
        private readonly ISyncService? _syncService;
        private readonly Guid _instanceId = Guid.NewGuid();

        public RssFeedService(IRenderedHtmlService? renderedHtmlService = null, IDatabaseService? databaseService = null, ISyncService? syncService = null)
        {
            Console.WriteLine($"[RssFeedService] Constructor called. InstanceId: {_instanceId}");
            _renderedHtmlService = renderedHtmlService;
            _databaseService = databaseService;
            _syncService = syncService;
            
            _ = InitializeCustomFeedsAsync();

            if (_syncService != null)
            {
                _syncService.OnRssSubscriptionsPulled += () =>
                {
                    Console.WriteLine("[RssFeedService] SyncService pulled RSS Subscriptions. Reloading feeds...");
                    _ = InitializeCustomFeedsAsync();
                };
            }
            
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
            // If already loading and not forcing, skip
            if (IsLoading && !forceRefresh) return;
            
            try
            {
                IsLoading = true;
                Error = null;
                // ATOMIC UPDATE: Do NOT clear items here. Wait for fetch to complete.
                // if (!forceRefresh) Items = new List<RssItem>(); 
                
                Console.WriteLine($"[RssFeedService] LoadFeedAsync called for {feed.Name}. Force: {forceRefresh}. Instance: {_instanceId}");
                OnItemsUpdated?.Invoke(); // Notify loading state

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
                // Items = new List<RssItem>(); // GUARD: Keep stale items to prevent Widget Loop
            }
            finally
            {
                IsLoading = false;
                OnItemsUpdated?.Invoke();
            }
        }

        public async Task InitializeCustomFeedsAsync()
        {
            if (_databaseService == null) return;
            try 
            {
                await _databaseService.InitializeAsync();
                var customFeeds = await _databaseService.Connection.Table<LocalRssSubscription>()
                                    .Where(x => !x.IsDeleted)
                                    .OrderBy(x => x.DisplayOrder)
                                    .ThenBy(x => x.CreatedAt)
                                    .ToListAsync();
                
                var distinctFeeds = customFeeds.GroupBy(f => f.Url).Select(g => g.First()).ToList();

                var combined = new List<FeedSource>();
                foreach(var c in distinctFeeds)
                {
                    combined.Add(new FeedSource {
                        Name = c.Name,
                        Url = c.Url,
                        IconUrl = c.IconUrl,
                        Category = Enum.TryParse<FeedCategory>(c.Category, true, out var cat) ? cat : FeedCategory.Tech,
                        Type = c.Url.Contains("wp-json") ? FeedType.WpJson : FeedType.Rss
                    });
                }
                Feeds = combined;
                
                if (CurrentFeed == null && Feeds.Any())
                {
                    CurrentFeed = Feeds.First();
                }
                
                OnFeedChanged?.Invoke();
            }
            catch(Exception ex)
            {
                Console.WriteLine($"[RssFeedService] Init Custom Feeds Error: {ex}");
            }
        }

        public async Task AddFeedAsync(string url, string name, string category, string userId)
        {
            if (_databaseService == null) return;
            
            await _databaseService.InitializeAsync();
            
            // Get next display order
            var maxOrderSub = await _databaseService.Connection.Table<LocalRssSubscription>()
                                .OrderByDescending(x => x.DisplayOrder)
                                .FirstOrDefaultAsync();
            int nextOrder = (maxOrderSub != null) ? maxOrderSub.DisplayOrder + 1 : 0;
            
            // Check if we already have this URL for the user
            var existing = await _databaseService.Connection.Table<LocalRssSubscription>()
                            .Where(x => x.Url == url && x.UserId == userId)
                            .FirstOrDefaultAsync();

            if (existing != null)
            {
                existing.Name = name;
                existing.Category = category;
                existing.IsDeleted = false;
                existing.SyncedAt = null;
                existing.UpdatedAt = DateTime.UtcNow;
                existing.DisplayOrder = nextOrder;
                await _databaseService.Connection.UpdateAsync(existing);
            }
            else
            {
                var newSub = new LocalRssSubscription
                {
                    Id = Guid.NewGuid().ToString(),
                    UserId = userId,
                    Name = name,
                    Url = url,
                    Category = category,
                    IconUrl = $"https://www.google.com/s2/favicons?domain={new Uri(url).Host}&sz=64",
                    CreatedAt = DateTime.UtcNow,
                    SyncedAt = null,
                    DisplayOrder = nextOrder
                };
                await _databaseService.Connection.InsertOrReplaceAsync(newSub);
            }
            
            await InitializeCustomFeedsAsync();
            TriggerSync();
        }

        public async Task<List<LocalRssSubscription>> GetSubscriptionsAsync()
        {
            if (_databaseService == null) return new List<LocalRssSubscription>();
            await _databaseService.InitializeAsync();
            return await _databaseService.Connection.Table<LocalRssSubscription>()
                .Where(x => !x.IsDeleted)
                .OrderBy(x => x.DisplayOrder)
                .ThenBy(x => x.CreatedAt)
                .ToListAsync();
        }

        public async Task SaveSubscriptionAsync(LocalRssSubscription subscription)
        {
            if (_databaseService == null) return;
            await _databaseService.InitializeAsync();
            subscription.UpdatedAt = DateTime.UtcNow;
            subscription.SyncedAt = null; // Mark dirty
            await _databaseService.Connection.InsertOrReplaceAsync(subscription);
            await InitializeCustomFeedsAsync();
            TriggerSync();
        }

        public async Task DeleteSubscriptionAsync(string id)
        {
            if (_databaseService == null) return;
            await _databaseService.InitializeAsync();
            var sub = await _databaseService.Connection.Table<LocalRssSubscription>().Where(x => x.Id == id).FirstOrDefaultAsync();
            if (sub != null)
            {
                sub.IsDeleted = true;
                sub.SyncedAt = null; // Mark dirty
                sub.UpdatedAt = DateTime.UtcNow;
                await _databaseService.Connection.UpdateAsync(sub);
                await InitializeCustomFeedsAsync();
                TriggerSync();
            }
        }

        public async Task ReorderSubscriptionsAsync(List<LocalRssSubscription> subscriptions)
        {
            if (_databaseService == null) return;
            await _databaseService.InitializeAsync();
            
            // Assign display orders sequentially
            for (int i = 0; i < subscriptions.Count; i++)
            {
                var sub = subscriptions[i];
                sub.DisplayOrder = i;
                sub.SyncedAt = null; // Mark dirty
                sub.UpdatedAt = DateTime.UtcNow;
            }

            await _databaseService.Connection.RunInTransactionAsync(tran =>
            {
                foreach (var sub in subscriptions)
                {
                    tran.Update(sub);
                }
            });

            await InitializeCustomFeedsAsync();
            TriggerSync();
        }

        public async Task<List<FeedSearchResult>> DiscoverFeedsAsync(string query)
        {
            var results = new List<FeedSearchResult>();
            if (string.IsNullOrWhiteSpace(query)) return results;

            // 1. Check if the query is a direct URL
            string targetUrl = query.Trim();
            if (targetUrl.StartsWith("http://", StringComparison.OrdinalIgnoreCase) || 
                targetUrl.StartsWith("https://", StringComparison.OrdinalIgnoreCase) ||
                Regex.IsMatch(targetUrl, @"^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,6}(/.*)?$"))
            {
                if (!targetUrl.StartsWith("http://", StringComparison.OrdinalIgnoreCase) && 
                    !targetUrl.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
                {
                    targetUrl = "https://" + targetUrl;
                }

                try
                {
                    var sniffedFeeds = await SniffFeedsFromUrlAsync(targetUrl);
                    if (sniffedFeeds.Any())
                    {
                        return sniffedFeeds;
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[RssFeedService] Error sniffing URL: {ex.Message}");
                }
            }

            // 2. Query Feedly search API
            try
            {
                string encodedQuery = Uri.EscapeDataString(query);
                string apiUrl = $"https://cloud.feedly.com/v3/search/feeds?query={encodedQuery}";
                var responseStr = await _httpClient.GetStringAsync(apiUrl);
                var node = JsonNode.Parse(responseStr);
                if (node != null && node["results"] is JsonArray jsonArray)
                {
                    foreach (var item in jsonArray)
                    {
                        if (item == null) continue;
                        
                        string feedId = item["feedId"]?.ToString() ?? item["id"]?.ToString() ?? "";
                        if (string.IsNullOrEmpty(feedId)) continue;
                        
                        string feedUrl = feedId;
                        if (feedId.StartsWith("feed/", StringComparison.OrdinalIgnoreCase))
                        {
                            feedUrl = feedId.Substring(5);
                        }

                        string name = item["title"]?.ToString() ?? "";
                        string iconUrl = item["iconUrl"]?.ToString() ?? item["visualUrl"]?.ToString() ?? "";
                        string website = item["website"]?.ToString() ?? "";

                        if (string.IsNullOrEmpty(iconUrl))
                        {
                            try
                            {
                                var uri = new Uri(feedUrl);
                                iconUrl = $"https://www.google.com/s2/favicons?domain={uri.Host}&sz=64";
                            }
                            catch
                            {
                                iconUrl = "";
                            }
                        }

                        results.Add(new FeedSearchResult
                        {
                            Name = name,
                            Url = feedUrl,
                            IconUrl = iconUrl,
                            Website = website
                        });
                    }
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[RssFeedService] Feedly search error: {ex.Message}");
            }

            return results;
        }

        private async Task<List<FeedSearchResult>> SniffFeedsFromUrlAsync(string url)
        {
            var results = new List<FeedSearchResult>();
            var html = await _httpClient.GetStringAsync(url);
            
            // Find alternate link tags
            var linkMatches = Regex.Matches(html, @"<link[^>]+(?:type=[""'](application/rss\+xml|application/atom\+xml|application/json)[""']|rel=[""']alternate[""'])[^>]*>", RegexOptions.IgnoreCase);
            
            foreach (Match match in linkMatches)
            {
                var tag = match.Value;
                var typeMatch = Regex.Match(tag, @"type=[""']([^""']+)[""']", RegexOptions.IgnoreCase);
                var hrefMatch = Regex.Match(tag, @"href=[""']([^""']+)[""']", RegexOptions.IgnoreCase);
                var titleMatch = Regex.Match(tag, @"title=[""']([^""']+)[""']", RegexOptions.IgnoreCase);

                if (hrefMatch.Success)
                {
                    // Clean href value by extracting the string inside quotes
                    var hrefValueMatch = Regex.Match(hrefMatch.Value, @"href=[""']([^""']+)[""']", RegexOptions.IgnoreCase);
                    string href = hrefValueMatch.Groups[1].Value;

                    if (!href.StartsWith("http://", StringComparison.OrdinalIgnoreCase) && 
                        !href.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
                    {
                        var baseUri = new Uri(url);
                        var absoluteUri = new Uri(baseUri, href);
                        href = absoluteUri.ToString();
                    }

                    string title = "Discovered Feed";
                    if (titleMatch.Success)
                    {
                        var titleValueMatch = Regex.Match(titleMatch.Value, @"title=[""']([^""']+)[""']", RegexOptions.IgnoreCase);
                        title = titleValueMatch.Groups[1].Value;
                    }

                    string iconUrl = $"https://www.google.com/s2/favicons?domain={new Uri(url).Host}&sz=64";

                    results.Add(new FeedSearchResult
                    {
                        Name = title,
                        Url = href,
                        IconUrl = iconUrl,
                        Website = url
                    });
                }
            }

            // Fallback: If no alternate tags, try common paths
            if (!results.Any())
            {
                string[] commonPaths = { "/feed", "/rss", "/rss.xml", "/feed.xml", "/wp-json/wp/v2/posts" };
                var baseUri = new Uri(url);
                foreach (var path in commonPaths)
                {
                    try
                    {
                        var testUri = new Uri(baseUri, path);
                        var response = await _httpClient.SendAsync(new HttpRequestMessage(HttpMethod.Head, testUri));
                        if (response.IsSuccessStatusCode)
                        {
                            results.Add(new FeedSearchResult
                            {
                                Name = $"{baseUri.Host} Feed ({path.TrimStart('/')})",
                                Url = testUri.ToString(),
                                IconUrl = $"https://www.google.com/s2/favicons?domain={baseUri.Host}&sz=64",
                                Website = url
                            });
                            break;
                        }
                    }
                    catch { }
                }
            }

            return results;
        }

        private void TriggerSync()
        {
            if (_syncService != null)
            {
                _ = Task.Run(async () =>
                {
                    try
                    {
                        await _syncService.SyncAsync(SyncScope.RssSubscriptions);
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"[RssFeedService] TriggerSync failed: {ex.Message}");
                    }
                });
            }
        }

        private async Task LoadRssFeedAsync(FeedSource feed)
        {
            Items = await FetchFeedItemsAsync(feed);
        }

        private async Task LoadWpJsonFeedAsync(FeedSource feed)
        {
            Items = await FetchFeedItemsAsync(feed);
        }

        public async Task<List<RssItem>> FetchFeedItemsAsync(FeedSource feed)
        {
            if (feed.Type == FeedType.Rss)
            {
                var xml = await _httpClient.GetStringAsync(feed.Url);
                var doc = XDocument.Parse(xml);
                XNamespace media = "http://search.yahoo.com/mrss/";
                XNamespace contentNs = "http://purl.org/rss/1.0/modules/content/";
                XNamespace dc = "http://purl.org/dc/elements/1.1/";

                var channelImage = doc.Descendants().FirstOrDefault(e => e.Name.LocalName == "channel" || e.Name.LocalName == "feed")
                    ?.Elements().FirstOrDefault(e => e.Name.LocalName == "image" || e.Name.LocalName == "logo" || e.Name.LocalName == "icon")
                    ?.Elements().FirstOrDefault(e => e.Name.LocalName == "url")?.Value
                    ?? doc.Descendants().FirstOrDefault(e => e.Name.LocalName == "logo" || e.Name.LocalName == "icon")?.Value;

                return doc.Descendants().Where(e => e.Name.LocalName == "item" || e.Name.LocalName == "entry").Select(item =>
                {
                    var title = item.Elements().FirstOrDefault(e => e.Name.LocalName == "title")?.Value ?? "No Title";

                    var linkEl = item.Elements().FirstOrDefault(e => e.Name.LocalName == "link");
                    var link = linkEl?.Attribute("href")?.Value;
                    if (string.IsNullOrEmpty(link)) link = linkEl?.Value ?? "";

                    var description = item.Elements().FirstOrDefault(e => e.Name.LocalName == "description" || e.Name.LocalName == "summary")?.Value;
                    var pubDateStr = item.Elements().FirstOrDefault(e => e.Name.LocalName == "pubDate" || e.Name.LocalName == "published" || e.Name.LocalName == "updated" || e.Name == dc + "date")?.Value;
                    var contentEncoded = item.Elements().FirstOrDefault(e => e.Name == contentNs + "encoded" || e.Name.LocalName == "content")?.Value;

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

                    // 3. Enclosure or Atom Rel=Enclosure
                    if (string.IsNullOrEmpty(imageUrl))
                    {
                        var enclosure = item.Elements().FirstOrDefault(e => e.Name.LocalName == "enclosure" || (e.Name.LocalName == "link" && e.Attribute("rel")?.Value == "enclosure"));
                        if (enclosure != null)
                        {
                            var type = enclosure.Attribute("type")?.Value;
                            if (string.IsNullOrEmpty(type) || type.StartsWith("image/"))
                            {
                                imageUrl = enclosure.Attribute("url")?.Value ?? enclosure.Attribute("href")?.Value;
                            }
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

                    // 6. Author Extraction
                    var author = item.Elements().FirstOrDefault(e => e.Name == dc + "creator")?.Value;
                    if (string.IsNullOrEmpty(author))
                    {
                        var authorEl = item.Elements().FirstOrDefault(e => e.Name.LocalName == "author");
                        author = authorEl?.Elements().FirstOrDefault(e => e.Name.LocalName == "name")?.Value ?? authorEl?.Value;
                    }

                    // Format Author and Publication (split "Author in Publication" if present)
                    string authorName = author ?? string.Empty;
                    string pubName = feed.Name;
                    int inIdx = authorName.IndexOf(" in ");
                    if (inIdx > 0)
                    {
                        pubName = authorName.Substring(inIdx + 4).Trim();
                        authorName = authorName.Substring(0, inIdx).Trim();
                    }

                    // Clean description of HTML tags and fall back to content snippet if needed
                    string cleanDescription = StripHtmlTags(description ?? string.Empty);
                    if (string.IsNullOrWhiteSpace(cleanDescription) && !string.IsNullOrEmpty(contentEncoded))
                    {
                        var contentClean = StripHtmlTags(contentEncoded);
                        if (contentClean.Length > 250)
                            cleanDescription = contentClean.Substring(0, 250) + "...";
                        else
                            cleanDescription = contentClean;
                    }

                    return new RssItem
                    {
                        Title = title,
                        Link = link,
                        PublishDate = DateTime.TryParse(pubDateStr, out var date) ? date : DateTime.Now,
                        ImageUrl = OptimizeMediumImageUrl(imageUrl ?? channelImage ?? feed.IconUrl),
                        Description = cleanDescription,
                        Content = contentEncoded,
                        Author = authorName,
                        PublicationName = pubName,
                        PublicationIconUrl = feed.IconUrl
                    };
                }).ToList();
            }
            else if (feed.Type == FeedType.WpJson)
            {
                var json = await _httpClient.GetStringAsync(feed.Url);
                var node = JsonNode.Parse(json);
                var posts = node?.AsArray();

                if (posts == null) 
                {
                    return new List<RssItem>();
                }

                var newList = new List<RssItem>();

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
                    string cleanDescription = StripHtmlTags(excerpt ?? string.Empty);
                    if (string.IsNullOrWhiteSpace(cleanDescription) && !string.IsNullOrEmpty(content))
                    {
                        var contentClean = StripHtmlTags(content);
                        if (contentClean.Length > 250)
                            cleanDescription = contentClean.Substring(0, 250) + "...";
                        else
                            cleanDescription = contentClean;
                    }

                    string? author = null;
                    var embedded = post["_embedded"];
                    
                    string? imageUrl = null;
                    if (embedded != null)
                    {
                        var media = embedded["wp:featuredmedia"]?.AsArray()?.FirstOrDefault();
                        if (media != null)
                        {
                            imageUrl = media["source_url"]?.ToString();
                             if (media["media_details"]?["sizes"]?["medium"]?["source_url"] != null)
                            {
                                imageUrl = media["media_details"]?["sizes"]?["medium"]?["source_url"]?.ToString();
                            }
                        }
                        
                        var authorObj = embedded["author"]?.AsArray()?.FirstOrDefault();
                        if (authorObj != null)
                        {
                            author = authorObj["name"]?.ToString();
                        }
                    }
                    
                    newList.Add(new RssItem
                    {
                         Title = title ?? "No Title",
                         Link = link,
                         PublishDate = date,
                         ImageUrl = imageUrl ?? feed.IconUrl,
                         Description = cleanDescription,
                         Content = content,
                         Author = author,
                         PublicationName = feed.Name,
                         PublicationIconUrl = feed.IconUrl
                    });
                }
                return newList;
            }
            return new List<RssItem>();
        }
        public async Task<RssItem> FetchFullArticleAsync(string url)
        {
            try
            {

                if (_renderedHtmlService != null)
                {
                    var renderedArticle = await _renderedHtmlService.GetRenderedArticleAsync(url);
                    if (renderedArticle != null && !string.IsNullOrWhiteSpace(renderedArticle.Content))
                    {
                        return new RssItem
                        {
                            Title = renderedArticle.Title ?? "",
                            Link = url,
                            Content = renderedArticle.Content,
                            Description = renderedArticle.Excerpt ?? renderedArticle.TextContent,
                            Author = renderedArticle.Byline,
                            PublishDate = DateTime.Now,
                            PublicationName = CurrentFeed?.Name,
                            PublicationIconUrl = CurrentFeed?.IconUrl
                        };
                    }
                }

                // OPTIMIZATION: Use shared HttpClient for fetching to ensure Handler/DNS reuse and speed
                var html = await _httpClient.GetStringAsync(url);
                var reader = new SmartReader.Reader(url, html);
                var article = reader.GetArticle(); // Synchronous parse of provided content

                if (article.IsReadable)
                {
                    var content = article.Content;
                    var featImg = article.FeaturedImage;

                    // Deduplicate Featured Image from Content Body (Aggressive)
                    if (!string.IsNullOrEmpty(content) && !string.IsNullOrEmpty(featImg))
                    {
                        try 
                        {
                            // 1. Find the FIRST image tag (simple, robust regex)
                            var imgMatch = Regex.Match(content, @"<img[^>]+src\s*=\s*[""']([^""']+)[""'][^>]*>", RegexOptions.IgnoreCase);
                            
                            if (imgMatch.Success)
                            {
                                var foundSrc = imgMatch.Groups[1].Value;
                                
                                // 2. Normalize URLs for Loose Comparison
                                // (Handle query params, encoded entities, http/s differences)
                                string s1 = System.Net.WebUtility.HtmlDecode(foundSrc ?? "").Split('?')[0].Trim();
                                string s2 = System.Net.WebUtility.HtmlDecode(featImg ?? "").Split('?')[0].Trim();
                                
                                bool shouldRemove = false;
                                
                                if (!string.IsNullOrEmpty(s1) && !string.IsNullOrEmpty(s2))
                                {
                                    // A. Check for exact containment (one is substring of other)
                                    // Helps if one is relative or CDN resized
                                    if (s1.IndexOf(s2, StringComparison.OrdinalIgnoreCase) >= 0 || 
                                        s2.IndexOf(s1, StringComparison.OrdinalIgnoreCase) >= 0)
                                    {
                                        shouldRemove = true;
                                    }
                                    // B. Check Filename match (if long enough to avoid "image.jpg" false positives)
                                    else if (s1.Length > 15 && s2.Length > 15)
                                    {
                                        var f1 = s1.TrimEnd('/').Split('/').Last();
                                        var f2 = s2.TrimEnd('/').Split('/').Last();
                                        if (string.Equals(f1, f2, StringComparison.OrdinalIgnoreCase))
                                        {
                                            shouldRemove = true;
                                        }
                                    }
                                }

                                // 3. Execute Removal
                                if (shouldRemove)
                                {
                                    // Remove the <img> tag
                                    content = content.Remove(imgMatch.Index, imgMatch.Length);
                                    
                                    // 4. Cleanup Empty Wrappers (Figure/Div/P) surrounding that spot
                                    // We look at the text around the removal point to see if we left an empty wrapper
                                    // This regex finds empty tags <tag></tag> or <tag>  </tag>
                                    string cleanPattern = @"<((figure|div|p))[^>]*>\s*</\1>";
                                    content = Regex.Replace(content, cleanPattern, "", RegexOptions.IgnoreCase);
                                    
                                    // Final trim
                                    content = content.Trim();
                                }
                            }
                        }
                        catch 
                        { 
                             // Safety net
                        }
                    }

                    var author = article.Byline;
                    if (!string.IsNullOrEmpty(author))
                    {
                        // 1. Remove "junk" phrases
                        author = author.Replace("Social Links", "", StringComparison.OrdinalIgnoreCase)
                                       .Replace("NavigationContributor", "", StringComparison.OrdinalIgnoreCase) // Specific combo
                                       .Replace("Navigation", "", StringComparison.OrdinalIgnoreCase)
                                       .Replace("See all articles", "", StringComparison.OrdinalIgnoreCase);

                        // 2. Fix Concatenated or Unseparated Titles (e.g. "NameSenior" or "Name Senior")
                        // Ensure comma separator. Order of titles matters (Longer first to capture full title).
                        author = Regex.Replace(author, @"(?<=[a-z])\s*(?<!,\s)(Senior Editor|Executive Editor|Deals Editor|Managing Editor|Editor|Contributor|Freelance Writer|Freelance|Staff Writer|Staff|Writer|Journalist)", ", $1", RegexOptions.IgnoreCase);

                        // 3. Trim around punctuation
                        author = author.Trim();
                        author = author.TrimEnd(',', '.', '-', '|');
                        
                        // 4. Fix "Space before Comma" (e.g. "Name , Title" -> "Name, Title")
                        author = Regex.Replace(author, @"\s+,", ",");
                        
                        // Final trim
                        author = author.Trim();
                    }

                    return new RssItem
                    {
                        Title = article.Title,
                        Link = url,
                        Content = content, // Aggressively De-duplicated
                        Description = article.Excerpt,
                        ImageUrl = featImg,
                        PublishDate = article.PublicationDate ?? DateTime.Now,
                        Author = author,
                        PublicationName = CurrentFeed?.Name,
                        PublicationIconUrl = CurrentFeed?.IconUrl
                    };
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error fetching article: {ex.Message}");
            }

            // Actually, let's return a basic item
            return new RssItem { Link = url, Title = "Error fetching article" };
        }

        public void SetItemsAndNotify(List<RssItem> items)
        {
            Items.Clear();
            Items.AddRange(items);
            OnItemsUpdated?.Invoke();
        }

        public static string StripHtmlTags(string html)
        {
            if (string.IsNullOrEmpty(html)) return string.Empty;
            var clean = html;
            
            // Remove style and script blocks
            clean = Regex.Replace(clean, @"<style[^>]*>[\s\S]*?</style>", string.Empty, RegexOptions.IgnoreCase);
            clean = Regex.Replace(clean, @"<script[^>]*>[\s\S]*?</script>", string.Empty, RegexOptions.IgnoreCase);
            
            // Replace common block tags with spaces/newlines
            clean = Regex.Replace(clean, @"<br\s*/?>", " ", RegexOptions.IgnoreCase);
            clean = Regex.Replace(clean, @"</p>", " ", RegexOptions.IgnoreCase);
            clean = Regex.Replace(clean, @"</div>", " ", RegexOptions.IgnoreCase);
            clean = Regex.Replace(clean, @"</td>", " ", RegexOptions.IgnoreCase);
            clean = Regex.Replace(clean, @"</th>", " ", RegexOptions.IgnoreCase);
            clean = Regex.Replace(clean, @"</tr>", " ", RegexOptions.IgnoreCase);
            clean = Regex.Replace(clean, @"</li>", " ", RegexOptions.IgnoreCase);
            
            // Remove all other HTML tags
            clean = Regex.Replace(clean, @"<[^>]*>", string.Empty);
            
            // Decode HTML entities
            clean = System.Net.WebUtility.HtmlDecode(clean);
            
            // Clean up multiple spaces/newlines
            clean = Regex.Replace(clean, @"\s+", " ");
            return clean.Trim();
        }

        public static string OptimizeMediumImageUrl(string url)
        {
            if (string.IsNullOrEmpty(url)) return url;
            if (url.Contains("miro.medium.com"))
            {
                var pattern = @"v2/resize:[^/]+(/format:[^/]+)?";
                var result = Regex.Replace(url, pattern, "v2/resize:fit:800");
                return result;
            }
            return url;
        }
    }
}
