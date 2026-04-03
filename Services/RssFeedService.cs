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
            // 🇷🇴 Local
            new FeedSource { Name = "Republica", Url = "https://republica.ro/rss", Type = FeedType.Rss, Category = FeedCategory.Local, IconUrl = "https://www.google.com/s2/favicons?domain=republica.ro&sz=64" },
            new FeedSource { Name = "Digi24", Url = "https://www.digi24.ro/rss", Type = FeedType.Rss, Category = FeedCategory.Local, IconUrl = "https://www.google.com/s2/favicons?domain=digi24.ro&sz=64" },
            new FeedSource { Name = "Ziarul Financiar", Url = "https://www.zf.ro/rss/", Type = FeedType.Rss, Category = FeedCategory.Local, IconUrl = "https://www.google.com/s2/favicons?domain=zf.ro&sz=64" },
            new FeedSource { Name = "HotNews", Url = "https://www.hotnews.ro/rss", Type = FeedType.Rss, Category = FeedCategory.Local, IconUrl = "https://www.google.com/s2/favicons?domain=hotnews.ro&sz=64" },
            new FeedSource { Name = "Biziday", Url = "https://www.biziday.ro/feed/", Type = FeedType.Rss, Category = FeedCategory.Local, IconUrl = "https://www.google.com/s2/favicons?domain=biziday.ro&sz=64" },
            new FeedSource { Name = "Economica.net", Url = "https://www.economica.net/rss", Type = FeedType.Rss, Category = FeedCategory.Local, IconUrl = "https://www.google.com/s2/favicons?domain=economica.net&sz=64" },

            // 📈 Markets
            new FeedSource { Name = "CNBC", Url = "https://www.cnbc.com/id/100003114/device/rss/rss.html", Type = FeedType.Rss, Category = FeedCategory.Markets, IconUrl = "https://www.google.com/s2/favicons?domain=cnbc.com&sz=64" },
            new FeedSource { Name = "The Economist", Url = "https://www.economist.com/finance-and-economics/rss.xml", Type = FeedType.Rss, Category = FeedCategory.Markets, IconUrl = "https://www.google.com/s2/favicons?domain=economist.com&sz=64" },

            // 🌍 World
            new FeedSource { Name = "BBC News", Url = "https://feeds.bbci.co.uk/news/rss.xml", Type = FeedType.Rss, Category = FeedCategory.World, IconUrl = "https://www.google.com/s2/favicons?domain=bbc.com&sz=64" },
            new FeedSource { Name = "NPR", Url = "https://feeds.npr.org/1001/rss.xml", Type = FeedType.Rss, Category = FeedCategory.World, IconUrl = "https://www.google.com/s2/favicons?domain=npr.org&sz=64" },
            new FeedSource { Name = "Politico Europe", Url = "https://www.politico.eu/feed/", Type = FeedType.Rss, Category = FeedCategory.World, IconUrl = "https://www.google.com/s2/favicons?domain=politico.eu&sz=64" },
            new FeedSource { Name = "Deutsche Welle", Url = "https://rss.dw.com/rdf/rss-en-all", Type = FeedType.Rss, Category = FeedCategory.World, IconUrl = "https://www.google.com/s2/favicons?domain=dw.com&sz=64" },
            new FeedSource { Name = "Google News", Url = "https://news.google.com/rss?hl=en-US&gl=US&ceid=US:en", Type = FeedType.Rss, Category = FeedCategory.World, IconUrl = "https://www.google.com/s2/favicons?domain=news.google.com&sz=64" },

            // 💡 Tech
            new FeedSource { Name = "TechCrunch", Url = "https://techcrunch.com/feed/", Type = FeedType.Rss, Category = FeedCategory.Tech, IconUrl = "https://www.google.com/s2/favicons?domain=techcrunch.com&sz=64" },
            new FeedSource { Name = "The Verge", Url = "https://www.theverge.com/rss/index.xml", Type = FeedType.Rss, Category = FeedCategory.Tech, IconUrl = "https://www.google.com/s2/favicons?domain=theverge.com&sz=64" },
            new FeedSource { Name = "Ars Technica", Url = "https://feeds.arstechnica.com/arstechnica/index", Type = FeedType.Rss, Category = FeedCategory.Tech, IconUrl = "https://www.google.com/s2/favicons?domain=arstechnica.com&sz=64" },
            new FeedSource { Name = "Zona IT", Url = "https://zonait.ro/wp-json/wp/v2/posts?per_page=20&_embed", Type = FeedType.WpJson, Category = FeedCategory.Tech, IconUrl = "https://www.google.com/s2/favicons?domain=zonait.ro&sz=64" },
            new FeedSource { Name = "Windows Central", Url = "https://www.windowscentral.com/feeds.xml", Type = FeedType.Rss, Category = FeedCategory.Tech, IconUrl = "https://www.google.com/s2/favicons?domain=windowscentral.com&sz=64" }
        };

        public FeedSource CurrentFeed { get; private set; }
        public List<RssItem> Items { get; private set; } = new();
        public bool IsLoading { get; private set; }
        public string? Error { get; private set; }

        public event Action? OnFeedChanged;
        public event Action? OnItemsUpdated;

        private readonly HttpClient _httpClient;
        private readonly IRenderedHtmlService? _renderedHtmlService;
        private readonly Guid _instanceId = Guid.NewGuid();

        public RssFeedService(IRenderedHtmlService? renderedHtmlService = null)
        {
            Console.WriteLine($"[RssFeedService] Constructor called. InstanceId: {_instanceId}");
            CurrentFeed = Feeds.First();
            _renderedHtmlService = renderedHtmlService;
            
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

        private async Task LoadRssFeedAsync(FeedSource feed)
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

            // Atomic Swap
            Items = doc.Descendants().Where(e => e.Name.LocalName == "item" || e.Name.LocalName == "entry").Select(item =>
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

                return new RssItem
                {
                    Title = title,
                    Link = link,
                    PublishDate = DateTime.TryParse(pubDateStr, out var date) ? date : DateTime.Now,
                    ImageUrl = imageUrl ?? channelImage,
                    Description = description,
                    Content = contentEncoded,
                    Author = author
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
                // Items = new List<RssItem>(); // Do not clear on error
                return;
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

                // WP JSON Author is usually an ID, requiring a separate lookup or 'embed'
                // For now, check if embedded author is present
                string? author = null;
                var embedded = post["_embedded"];
                
                string? imageUrl = null;
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
                     ImageUrl = imageUrl,
                     Description = excerpt,
                     Content = content,
                     Author = author
                });
            }
            // Atomic Swap
            Items = newList;
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
                            PublishDate = DateTime.Now
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
                        Author = author
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
