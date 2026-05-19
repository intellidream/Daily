using System;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using Daily.Models;
using Daily_WinUI.Services;
using System.Collections.ObjectModel;
using Microsoft.Extensions.DependencyInjection;

namespace Daily_WinUI.Views;

public sealed partial class RssFeedDetailPage : Page
{
    private readonly Daily.Services.IRssFeedService _rssService;
    private ObservableCollection<RssItem> _articles = new();
    private RssItem? _selectedItem;

    public RssFeedDetailPage()
    {
        InitializeComponent();
        _rssService = App.Current.Services.GetRequiredService<Daily.Services.IRssFeedService>();
        
        ArticlesListView.ItemsSource = _articles;
        Loaded += RssFeedDetailPage_Loaded;
        Unloaded += RssFeedDetailPage_Unloaded;
    }

    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);

        if (e.Parameter is RssItem preSelectedItem)
        {
            // The user clicked an item from the widget. Open Reader View directly.
            _selectedItem = preSelectedItem;
            await OpenReaderViewAsync(_selectedItem);
        }
    }

    private void RssFeedDetailPage_Loaded(object sender, RoutedEventArgs e)
    {
        _rssService.OnFeedChanged += RssService_OnFeedChanged;
        _rssService.OnItemsUpdated += RssService_OnItemsUpdated;

        if (FeedComboBox.ItemsSource == null)
        {
            FeedComboBox.ItemsSource = _rssService.Feeds;
            if (_selectedItem != null)
            {
                // Pre-select the feed that matches the item, if possible
                var feed = _rssService.Feeds.FirstOrDefault(f => f.Name == _selectedItem.PublicationName);
                if (feed != null)
                {
                    FeedComboBox.SelectedItem = feed;
                }
            }
            else if (_rssService.CurrentFeed != null)
            {
                FeedComboBox.SelectedItem = _rssService.CurrentFeed;
            }
            else if (_rssService.Feeds.Any())
            {
                FeedComboBox.SelectedIndex = 0;
            }
        }
        
        UpdateArticles();
        EnsureWebViewCoreInitialized();
    }

    private void RssFeedDetailPage_Unloaded(object sender, RoutedEventArgs e)
    {
        _rssService.OnFeedChanged -= RssService_OnFeedChanged;
        _rssService.OnItemsUpdated -= RssService_OnItemsUpdated;
    }

    private void RssService_OnFeedChanged()
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            if (FeedComboBox.ItemsSource != _rssService.Feeds)
            {
                FeedComboBox.ItemsSource = _rssService.Feeds;
            }
            if (FeedComboBox.SelectedItem != _rssService.CurrentFeed)
            {
                FeedComboBox.SelectedItem = _rssService.CurrentFeed;
            }
        });
    }

    private void RssService_OnItemsUpdated()
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            UpdateArticles();
        });
    }

    private void UpdateArticles()
    {
        _articles.Clear();
        foreach (var item in _rssService.Items)
        {
            _articles.Add(item);
        }

        if (_rssService.IsLoading)
        {
            LoadingPanel.Visibility = Visibility.Visible;
            ArticlesListView.Visibility = Visibility.Collapsed;
        }
        else
        {
            LoadingPanel.Visibility = Visibility.Collapsed;
            ArticlesListView.Visibility = Visibility.Visible;
        }
    }

    public async Task RefreshFromTitleBarAsync()
    {
        if (_selectedItem != null)
        {
            await OpenReaderViewAsync(_selectedItem);
            return;
        }

        if (FeedComboBox.SelectedItem is FeedSource selectedFeed)
        {
            LoadingPanel.Visibility = Visibility.Visible;
            ArticlesListView.Visibility = Visibility.Collapsed;
            _rssService.SelectFeed(selectedFeed);
            await _rssService.LoadFeedAsync(selectedFeed);
        }
        else if (_rssService.CurrentFeed != null)
        {
            LoadingPanel.Visibility = Visibility.Visible;
            ArticlesListView.Visibility = Visibility.Collapsed;
            await _rssService.LoadFeedAsync(_rssService.CurrentFeed);
        }
    }

    private async void EnsureWebViewCoreInitialized()
    {
        await ReaderWebView.EnsureCoreWebView2Async();
    }

    private async void FeedComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (FeedComboBox.SelectedItem is FeedSource selectedFeed && _selectedItem == null)
        {
            if (selectedFeed != _rssService.CurrentFeed)
            {
                LoadingPanel.Visibility = Visibility.Visible;
                ArticlesListView.Visibility = Visibility.Collapsed;
                _rssService.SelectFeed(selectedFeed);
                await _rssService.LoadFeedAsync(selectedFeed);
            }
        }
    }

    private async void ArticlesListView_ItemClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is RssItem item)
        {
            _selectedItem = item;
            await OpenReaderViewAsync(item);
        }
    }

    private async Task OpenReaderViewAsync(RssItem item)
    {
        ListViewContainer.Visibility = Visibility.Collapsed;
        ReaderViewContainer.Visibility = Visibility.Visible;
        ReaderLoadingPanel.Visibility = Visibility.Visible;
        ReaderWebView.Visibility = Visibility.Collapsed;
        ReaderWebView.Opacity = 1;

        // Step 1: Try the fast HttpClient + SmartReader path
        RssItem? fullArticle = null;
        bool needsWebViewFallback = false;
        try
        {
            fullArticle = await _rssService.FetchFullArticleAsync(item.Link);
            
            // FetchFullArticleAsync never throws — it returns Title="Error fetching article" on failure.
            // Detect that and trigger the WebView2 fallback instead of showing the error.
            if (fullArticle.Title == "Error fetching article" || string.IsNullOrWhiteSpace(fullArticle.Content))
            {
                needsWebViewFallback = true;
            }
        }
        catch
        {
            needsWebViewFallback = true;
        }

        // Step 2: If the fast path succeeded, render it
        if (!needsWebViewFallback && fullArticle != null)
        {
            string html = GenerateReaderHtml(fullArticle);
            await ReaderWebView.EnsureCoreWebView2Async();
            // Set to fully transparent (alpha = 0) to let mica effect show through
            ReaderWebView.DefaultBackgroundColor = Windows.UI.Color.FromArgb(0, 0, 0, 0);
            SetupWebViewVirtualHost();
            ReaderWebView.NavigateToString(html);
            ReaderLoadingPanel.Visibility = Visibility.Collapsed;
            ReaderWebView.Visibility = Visibility.Visible;
            return;
        }

        // Step 3: WebView2 fallback — navigate a real browser to the URL,
        // wait for JS to render, then extract + parse with SmartReader.
        System.Diagnostics.Debug.WriteLine($"[Reader] Fast path failed for {item.Link}, using WebView2 fallback...");
        try 
        {
            // WebView2 must be Visible for its Chromium engine to run JS.
            // Hide it visually with Opacity 0 while we scrape.
            ReaderWebView.Visibility = Visibility.Visible;
            ReaderWebView.Opacity = 0.0;
            
            await ReaderWebView.EnsureCoreWebView2Async();
            SetupWebViewVirtualHost();

            // Safety: wait for the engine to fully attach
            if (ReaderWebView.CoreWebView2 == null) 
            {
                await Task.Delay(500);
                if (ReaderWebView.CoreWebView2 == null)
                    throw new Exception("WebView2 engine failed to initialize.");
            }

            // Navigate to the actual article URL
            var tcs = new TaskCompletionSource<string>();
            
            Windows.Foundation.TypedEventHandler<Microsoft.Web.WebView2.Core.CoreWebView2, Microsoft.Web.WebView2.Core.CoreWebView2NavigationCompletedEventArgs>? handler = null;
            handler = async (s, args) => 
            {
                ReaderWebView.CoreWebView2.NavigationCompleted -= handler;
                try 
                {
                    // Give the page a moment to settle after navigation
                    await Task.Delay(2000);

                    // Remove cookie/GDPR overlays that block content
                    var cleanupScript = "(function(){" +
                        "var selectors=['#cmp-app-container','.cookie-banner','#cookie-consent','.gdpr-modal'," +
                        "'[class*=\"cookie\"]','[id*=\"cookie\"]','[class*=\"consent\"]','[class*=\"paywall\"]'," +
                        "'[id*=\"consent\"]','[class*=\"overlay\"]','[id*=\"piano\"]'];" +
                        "selectors.forEach(function(s){document.querySelectorAll(s).forEach(function(e){e.remove();});});" +
                        "document.body.style.overflow='auto';document.documentElement.style.overflow='auto';" +
                        "document.body.style.position='static';" +
                        "var main=document.querySelector('article')||document.querySelector('main')||document.querySelector('[role=\"main\"]');" +
                        "if(main){main.style.display='block';main.style.visibility='visible';main.style.opacity='1';}" +
                        "})()";
                    await ReaderWebView.ExecuteScriptAsync(cleanupScript);

                    // Poll until the page has substantial text content (JS-rendered)
                    string extractedHtml = "";
                    for (int i = 0; i < 20; i++)
                    {
                        await Task.Delay(1000);
                        
                        // Re-run cleanup each iteration in case overlays re-appear
                        if (i % 3 == 0 && i > 0)
                            await ReaderWebView.ExecuteScriptAsync(cleanupScript);

                        // Check text length
                        var lenJson = await ReaderWebView.ExecuteScriptAsync(
                            "document.body && document.body.innerText ? document.body.innerText.length : 0;");
                        if (lenJson != null && int.TryParse(lenJson.Trim('\"'), out int len) && len > 500)
                        {
                            // Also try article-specific selectors for a more targeted extraction
                            var articleJson = await ReaderWebView.ExecuteScriptAsync(
                                "(function(){" +
                                "var selectors='article, main, [itemprop=\"articleBody\"], .article-body, .article-content, .post-content, .entry-content, .layout-article-body';" +
                                "var el=document.querySelector(selectors);" +
                                "if(el && el.innerText && el.innerText.length > 200) return '<html><head><meta charset=\"utf-8\"/></head><body>'+el.outerHTML+'</body></html>';" +
                                "return null;" +
                                "})()");
                            
                            string? articleHtml = null;
                            if (articleJson != null && articleJson != "null")
                            {
                                try { articleHtml = System.Text.Json.JsonSerializer.Deserialize<string>(articleJson); }
                                catch { }
                            }

                            if (!string.IsNullOrWhiteSpace(articleHtml) && articleHtml.Length > 500)
                            {
                                extractedHtml = articleHtml;
                                break;
                            }

                            // Fall back to full page HTML
                            var fullJson = await ReaderWebView.ExecuteScriptAsync("document.documentElement.outerHTML;");
                            if (fullJson != null && fullJson != "null")
                            {
                                try { extractedHtml = System.Text.Json.JsonSerializer.Deserialize<string>(fullJson) ?? ""; }
                                catch { extractedHtml = fullJson; }
                            }
                            
                            if (extractedHtml.Length > 2000)
                                break;
                        }
                    }
                    
                    tcs.TrySetResult(extractedHtml);
                }
                catch (Exception jsEx)
                {
                    tcs.TrySetException(jsEx);
                }
            };
            
            ReaderWebView.CoreWebView2.NavigationCompleted += handler;
            ReaderWebView.CoreWebView2.Navigate(item.Link);
            
            // Wait up to 30s for the scraping to complete
            var completedTask = await Task.WhenAny(tcs.Task, Task.Delay(30000));
            string loadedHtml = "";
            if (completedTask == tcs.Task)
            {
                loadedHtml = await tcs.Task;
            }
            
            if (!string.IsNullOrWhiteSpace(loadedHtml) && loadedHtml.Length > 500)
            {
                var reader = new SmartReader.Reader(item.Link, loadedHtml);
                var article = reader.GetArticle();
                
                if (article.IsReadable)
                {
                    var fallbackArticle = new RssItem 
                    {
                        Title = !string.IsNullOrEmpty(article.Title) ? article.Title : item.Title,
                        Link = item.Link,
                        Content = article.Content,
                        Description = article.Excerpt ?? article.TextContent,
                        Author = article.Byline ?? item.Author,
                        PublishDate = item.PublishDate,
                        PublicationName = item.PublicationName,
                        PublicationIconUrl = item.PublicationIconUrl,
                        ImageUrl = item.ImageUrl
                    };
                    string finalHtml = GenerateReaderHtml(fallbackArticle);
                    ReaderWebView.NavigateToString(finalHtml);
                }
                else
                {
                    // SmartReader couldn't parse it — show the raw page instead
                    ReaderWebView.NavigateToString($"<html><head><style>body {{ font-family: 'Segoe UI', sans-serif; padding: 40px; color: #ccc; background: transparent; }} a {{ color: #4DA6FF; }}</style></head><body><h2>Could not extract article text</h2><p>The content may be behind a paywall. <a href='{item.Link}'>Open in browser</a></p></body></html>");
                }
            }
            else
            {
                ReaderWebView.NavigateToString($"<html><head><style>body {{ font-family: 'Segoe UI', sans-serif; padding: 40px; color: #ccc; background: transparent; }} a {{ color: #4DA6FF; }}</style></head><body><h2>Timed out loading article</h2><p>The page took too long to render. <a href='{item.Link}'>Open in browser</a></p></body></html>");
            }
        }
        catch (Exception fallbackEx)
        {
            System.Diagnostics.Debug.WriteLine($"WebView2 fallback failed: {fallbackEx.Message}");
            await ReaderWebView.EnsureCoreWebView2Async();
            ReaderWebView.NavigateToString($"<html><head><style>body {{ font-family: 'Segoe UI', sans-serif; padding: 40px; color: #ccc; background: transparent; }}</style></head><body><h2>Error loading article</h2><p>{fallbackEx.Message}</p></body></html>");
        }
        finally
        {
            ReaderLoadingPanel.Visibility = Visibility.Collapsed;
            ReaderWebView.Visibility = Visibility.Visible;
            ReaderWebView.Opacity = 1.0;
        }
    }

    private void BackButton_Click(object sender, RoutedEventArgs e)
    {
        _selectedItem = null;
        ReaderViewContainer.Visibility = Visibility.Collapsed;
        ListViewContainer.Visibility = Visibility.Visible;
        
        // If we don't have articles loaded (e.g., navigated directly to an article from widget), load the selected feed
        if (_articles.Count == 0 && FeedComboBox.SelectedItem is FeedSource feed)
        {
            _ = _rssService.LoadFeedAsync(feed);
        }
    }

    private bool _virtualHostMapped = false;

    private void SetupWebViewVirtualHost()
    {
        if (_virtualHostMapped || ReaderWebView.CoreWebView2 == null) return;
        string assetsPath = System.IO.Path.Combine(AppContext.BaseDirectory, "Assets");
        ReaderWebView.CoreWebView2.SetVirtualHostNameToFolderMapping(
            "app-assets.local", assetsPath,
            Microsoft.Web.WebView2.Core.CoreWebView2HostResourceAccessKind.Allow);
        _virtualHostMapped = true;
    }

    private string GenerateReaderHtml(RssItem article)
    {
        bool isDark = this.ActualTheme == ElementTheme.Dark;

        string textColor = isDark ? "#E0E0E0" : "#1A1A1A";
        string linkColor = isDark ? "#66B2FF" : "#0066CC";
        string metaColor = isDark ? "#A0A0A0" : "#666666";

        // Extract gradient colors from SVG top area - these match the backgrounds
        // Dark theme: blue gradient starting with #0F1D35
        // Light theme: warm tan gradient starting with #D9B08D
        string bodyBackground = isDark ? "rgba(15, 29, 53, 0.4)" : "rgba(217, 176, 141, 0.15)";

        string featuredImageHtml = string.IsNullOrEmpty(article.ImageUrl) 
            ? "" 
            : $"<img class='featured-image' src='{article.ImageUrl}' />";

        string metaHtml = $"<div class='meta'>Published: {article.PublishDate:f}";
        if (!string.IsNullOrEmpty(article.Author))
            metaHtml += $" &bull; By {article.Author}";
        metaHtml += "</div>";

        return $@"
<!DOCTYPE html>
<html>
<head>
    <meta charset='utf-8'/>
    <meta name='viewport' content='width=device-width, initial-scale=1.0'/>
    <style>
        html, body {{
            min-height: 100%;
        }}
        html {{
            background: transparent;
        }}
        body {{
            font-family: 'Segoe UI', -apple-system, BlinkMacSystemFont, Roboto, Helvetica, Arial, sans-serif;
            background: {bodyBackground};
            color: {textColor};
            line-height: 1.6;
            margin: 0;
            padding: 0;
            font-size: 18px;
        }}
        .article-wrap {{
            max-width: 800px;
            margin-left: auto;
            margin-right: auto;
            padding: 24px;
        }}
        h1 {{
            font-size: 32px;
            font-weight: 800;
            line-height: 1.2;
            margin-bottom: 12px;
            margin-top: 0;
        }}
        h2, h3, h4 {{
            margin-top: 32px;
            margin-bottom: 16px;
            font-weight: 700;
        }}
        p {{
            margin-bottom: 20px;
        }}
        a {{
            color: {linkColor};
            text-decoration: none;
        }}
        a:hover {{
            text-decoration: underline;
        }}
        img {{
            max-width: 100%;
            height: auto;
            border-radius: 8px;
            margin: 24px 0;
            display: block;
        }}
        .featured-image {{
            margin-top: 24px;
            margin-bottom: 32px;
            border-radius: 12px;
        }}
        .meta {{
            font-size: 14px;
            color: {metaColor};
            margin-bottom: 32px;
            border-bottom: 1px solid {metaColor};
            padding-bottom: 16px;
            opacity: 0.6;
        }}
        figure {{
            margin: 0;
        }}
        figcaption {{
            font-size: 14px;
            color: {metaColor};
            text-align: center;
            margin-top: 8px;
        }}
        blockquote {{
            border-left: 4px solid {linkColor};
            margin: 0;
            padding-left: 16px;
            font-style: italic;
            opacity: 0.9;
        }}
    </style>
</head>
<body>
<div class='article-wrap'>
    <h1>{article.Title}</h1>
    {metaHtml}
    {featuredImageHtml}
    <div class='content'>
        {article.Content ?? article.Description ?? "" }
    </div>
</div>
</body>
</html>";
    }
}
