using System;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using Daily.Models;
using Daily_WinUI.Services;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;

namespace Daily_WinUI.Views;

public sealed partial class RssFeedDetailPage : Page
{
    private readonly Daily.Services.IRssFeedService _rssService;
    private readonly Daily.Services.IRssArticleService _articleService;
    private ObservableCollection<Daily_WinUI.ViewModels.RssItemViewModel> _articles = new();
    private ObservableCollection<Daily_WinUI.ViewModels.RssItemViewModel> _readLaterArticles = new();
    private ObservableCollection<Daily_WinUI.ViewModels.RssItemViewModel> _favoriteArticles = new();
    private RssItem? _selectedItem;
    private RssItem? _currentRenderedArticle;
    private bool _isHeaderIconsMode;

    public RssFeedDetailPage()
    {
        InitializeComponent();
        _rssService = App.Current.Services.GetRequiredService<Daily.Services.IRssFeedService>();
        _articleService = App.Current.Services.GetRequiredService<Daily.Services.IRssArticleService>();
        
        ArticlesListView.ItemsSource = _articles;
        ReadLaterListView.ItemsSource = _readLaterArticles;
        FavoritesListView.ItemsSource = _favoriteArticles;

        Loaded += RssFeedDetailPage_Loaded;
        Unloaded += RssFeedDetailPage_Unloaded;
        ActualThemeChanged += RssFeedDetailPage_ActualThemeChanged;
        
        UpdateWebViewBackground();
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
        _articleService.OnItemsChanged += ArticleService_OnItemsChanged;

        PopulateFeedMenu();
        PreFetchAllFeedsInBackground();
        if (_selectedItem != null)
        {
            var feed = _rssService.Feeds?.FirstOrDefault(f => f.Name == _selectedItem.PublicationName);
            if (feed != null)
            {
                _rssService.SelectFeed(feed);
                UpdateSelectedFeedUI(feed);
            }
        }
        else
        {
            UpdateSelectedFeedUI(_rssService.CurrentFeed);
        }
        
        UpdateArticles();
        EnsureWebViewCoreInitialized();
        RecommendationsScrollViewer.LayoutUpdated += RecommendationsScrollViewer_LayoutUpdated;
    }

    private void RssFeedDetailPage_Unloaded(object sender, RoutedEventArgs e)
    {
        _rssService.OnFeedChanged -= RssService_OnFeedChanged;
        _rssService.OnItemsUpdated -= RssService_OnItemsUpdated;
        _articleService.OnItemsChanged -= ArticleService_OnItemsChanged;
        ActualThemeChanged -= RssFeedDetailPage_ActualThemeChanged;
        RecommendationsScrollViewer.LayoutUpdated -= RecommendationsScrollViewer_LayoutUpdated;
    }

    private void RssFeedDetailPage_ActualThemeChanged(FrameworkElement sender, object args)
    {
        UpdateWebViewBackground();
        if (_currentRenderedArticle != null && ReaderViewContainer.Visibility == Visibility.Visible)
        {
            string html = GenerateReaderHtml(_currentRenderedArticle);
            ReaderWebView.NavigateToString(html);
        }
    }

    private void RssService_OnFeedChanged()
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            PopulateFeedMenu();
            UpdateSelectedFeedUI(_rssService.CurrentFeed);
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
            _articles.Add(new Daily_WinUI.ViewModels.RssItemViewModel(item));
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

        UpdateSavedLists();
    }

    public async Task RefreshFromTitleBarAsync()
    {
        if (_selectedItem != null)
        {
            await OpenReaderViewAsync(_selectedItem);
            return;
        }

        if (_rssService.CurrentFeed != null)
        {
            LoadingPanel.Visibility = Visibility.Visible;
            ArticlesListView.Visibility = Visibility.Collapsed;
            await _rssService.LoadFeedAsync(_rssService.CurrentFeed);
        }
    }

    private async void EnsureWebViewCoreInitialized()
    {
        await ReaderWebView.EnsureCoreWebView2Async();
        UpdateWebViewBackground();
    }

    internal bool TryGoBack()
    {
        if (ReaderViewContainer.Visibility == Visibility.Visible)
        {
            _selectedItem = null;
            _currentRenderedArticle = null;
            ReaderViewContainer.Visibility = Visibility.Collapsed;
            ListViewContainer.Visibility = Visibility.Visible;
            
            // If we don't have articles loaded (e.g., navigated directly to an article from widget), load the selected feed
            if (_articles.Count == 0 && _rssService.CurrentFeed != null)
            {
                _ = _rssService.LoadFeedAsync(_rssService.CurrentFeed);
            }
            return true;
        }
        return false;
    }

    private async void ArticlesListView_ItemClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is Daily_WinUI.ViewModels.RssItemViewModel vm)
        {
            _selectedItem = vm.Item;
            await OpenReaderViewAsync(vm.Item);
        }
    }

    private async Task OpenReaderViewAsync(RssItem item)
    {
        _currentRenderedArticle = null;
        _selectedItem = item;
        UpdateReaderToolbarStates();
        PopulateRecommendations(item);
        ListViewContainer.Visibility = Visibility.Collapsed;
        ReaderViewContainer.Visibility = Visibility.Visible;
        ReaderLoadingPanel.Visibility = Visibility.Visible;
        ReaderWebView.Visibility = Visibility.Collapsed;
        ReaderWebView.Opacity = 1;

        bool isDark = this.ActualTheme == ElementTheme.Dark;
        string fallbackText = isDark ? "#E0E0E0" : "#1A1A1A";
        string fallbackLink = isDark ? "#66B2FF" : "#0066CC";
        string fallbackBg = isDark ? "#1A1423" : "#EDE5D9";

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
            _currentRenderedArticle = fullArticle;
            string html = GenerateReaderHtml(fullArticle);
            await ReaderWebView.EnsureCoreWebView2Async();
            UpdateWebViewBackground();
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
            UpdateWebViewBackground();
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
                    _currentRenderedArticle = fallbackArticle;
                    string finalHtml = GenerateReaderHtml(fallbackArticle);
                    ReaderWebView.NavigateToString(finalHtml);
                }
                else
                {
                    // SmartReader couldn't parse it — show the raw page instead
                    ReaderWebView.NavigateToString($"<html><head><style>body {{ font-family: 'Segoe UI', sans-serif; padding: 40px; color: {fallbackText}; background: {fallbackBg}; }} a {{ color: {fallbackLink}; }}</style></head><body><h2>Could not extract article text</h2><p>The content may be behind a paywall. <a href='{item.Link}'>Open in browser</a></p></body></html>");
                }
            }
            else
            {
                ReaderWebView.NavigateToString($"<html><head><style>body {{ font-family: 'Segoe UI', sans-serif; padding: 40px; color: {fallbackText}; background: {fallbackBg}; }} a {{ color: {fallbackLink}; }}</style></head><body><h2>Timed out loading article</h2><p>The page took too long to render. <a href='{item.Link}'>Open in browser</a></p></body></html>");
            }
        }
        catch (Exception fallbackEx)
        {
            System.Diagnostics.Debug.WriteLine($"WebView2 fallback failed: {fallbackEx.Message}");
            await ReaderWebView.EnsureCoreWebView2Async();
            UpdateWebViewBackground();
            ReaderWebView.NavigateToString($"<html><head><style>body {{ font-family: 'Segoe UI', sans-serif; padding: 40px; color: {fallbackText}; background: {fallbackBg}; }}</style></head><body><h2>Error loading article</h2><p>{fallbackEx.Message}</p></body></html>");
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
        _currentRenderedArticle = null;
        ReaderViewContainer.Visibility = Visibility.Collapsed;
        ListViewContainer.Visibility = Visibility.Visible;
        
        // If we don't have articles loaded (e.g., navigated directly to an article from widget), load the selected feed
        if (_articles.Count == 0 && _rssService.CurrentFeed != null)
        {
            _ = _rssService.LoadFeedAsync(_rssService.CurrentFeed);
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
        // Dark theme: purple tone sampled from the dark gradient's top region
        // Light theme: warm tan gradient starting with #D9B08D
        string bodyBackground = isDark ? "#1A1423" : "#EDE5D9";

        string featuredImageHtml = string.IsNullOrEmpty(article.ImageUrl) 
            ? "" 
            : $"<img class='featured-image' src='{article.ImageUrl}' />";

        string metaHtml = $"<div class='meta'>Published: {article.PublishDate:f}";
        if (!string.IsNullOrEmpty(article.Author))
            metaHtml += $" &bull; By {article.Author}";
        metaHtml += "</div>";

        string publicationHeaderHtml = "";
        if (!string.IsNullOrEmpty(article.PublicationName))
        {
            publicationHeaderHtml = $@"
                <div class='publication-header'>
                    <img class='publication-logo' src='{article.PublicationIconUrl}' />
                    <span class='publication-name'>{article.PublicationName}</span>
                </div>";
        }

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
        .publication-header {{
            display: flex;
            align-items: center;
            margin-bottom: 16px;
            opacity: 0.85;
        }}
        .publication-logo {{
            width: 24px;
            height: 24px;
            border-radius: 50%;
            margin: 0 10px 0 0 !important;
            background: white;
            padding: 2px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }}
        .publication-name {{
            font-size: 15px;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            color: {metaColor};
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
    {publicationHeaderHtml}
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

    private void UpdateWebViewBackground()
    {
        bool isDark = this.ActualTheme == ElementTheme.Dark;
        if (isDark)
        {
            ReaderWebView.DefaultBackgroundColor = Windows.UI.Color.FromArgb(255, 0x1A, 0x14, 0x23);
        }
        else
        {
            ReaderWebView.DefaultBackgroundColor = Windows.UI.Color.FromArgb(255, 0xED, 0xE5, 0xD9);
        }
    }

    private void UpdateSavedLists()
    {
        // Update Read Later
        _readLaterArticles.Clear();
        foreach (var saved in _articleService.ReadLaterItems)
        {
            _readLaterArticles.Add(new Daily_WinUI.ViewModels.RssItemViewModel(saved));
        }
        NoReadLaterTextBlock.Visibility = _readLaterArticles.Count == 0 ? Visibility.Visible : Visibility.Collapsed;

        // Update Favorites
        _favoriteArticles.Clear();
        foreach (var saved in _articleService.FavoriteItems)
        {
            _favoriteArticles.Add(new Daily_WinUI.ViewModels.RssItemViewModel(saved));
        }
        NoFavoritesTextBlock.Visibility = _favoriteArticles.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private void ArticleService_OnItemsChanged()
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            // Refresh states of live feed items
            foreach (var vm in _articles)
            {
                vm.RefreshState();
            }
            
            // Reload the saved lists (Favorites / Read Later)
            UpdateSavedLists();
            
            // If we are currently viewing an article, update the top bar icons!
            if (_selectedItem != null)
            {
                UpdateReaderToolbarStates();
            }
        });
    }

    private static readonly Microsoft.UI.Xaml.Media.Brush FavoriteActiveBrush = new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(255, 0xF2, 0x99, 0x4A));
    private static readonly Microsoft.UI.Xaml.Media.Brush ReadLaterActiveBrush = new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(255, 0xFF, 0x52, 0x52));
    
    private Microsoft.UI.Xaml.Media.Brush GetMutedBrush()
    {
        if (Application.Current.Resources.TryGetValue("AppFgMutedColorBrush", out var brushObj) && brushObj is Microsoft.UI.Xaml.Media.Brush brush)
        {
            return brush;
        }
        return new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(255, 0x80, 0x80, 0x80));
    }

    private void UpdateReaderToolbarStates()
    {
        if (_selectedItem == null) return;
        
        bool isFavorite = _articleService.IsSaved(_selectedItem.Link, SavedArticleType.Favorite);
        bool isReadLater = _articleService.IsSaved(_selectedItem.Link, SavedArticleType.ReadLater);

        ReaderFavoriteIcon.Glyph = isFavorite ? "\uE735" : "\uE734";
        ReaderReadLaterIcon.Glyph = isReadLater ? "\uE8A5" : "\uE8A4";

        ReaderFavoriteIcon.Foreground = isFavorite ? FavoriteActiveBrush : GetMutedBrush();
        ReaderReadLaterIcon.Foreground = isReadLater ? ReadLaterActiveBrush : GetMutedBrush();
    }

    private async void FavoriteButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.DataContext is Daily_WinUI.ViewModels.RssItemViewModel vm)
        {
            await _articleService.ToggleArticleAsync(vm.Item, vm.PublicationName ?? "RSS", vm.PublicationIconUrl, SavedArticleType.Favorite);
        }
    }

    private async void ReadLaterButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.DataContext is Daily_WinUI.ViewModels.RssItemViewModel vm)
        {
            await _articleService.ToggleArticleAsync(vm.Item, vm.PublicationName ?? "RSS", vm.PublicationIconUrl, SavedArticleType.ReadLater);
        }
    }

    private async void ReaderFavoriteButton_Click(object sender, RoutedEventArgs e)
    {
        if (_selectedItem != null)
        {
            await _articleService.ToggleArticleAsync(_selectedItem, _selectedItem.PublicationName ?? "RSS", _selectedItem.PublicationIconUrl, SavedArticleType.Favorite);
        }
    }

    private async void ReaderReadLaterButton_Click(object sender, RoutedEventArgs e)
    {
        if (_selectedItem != null)
        {
            await _articleService.ToggleArticleAsync(_selectedItem, _selectedItem.PublicationName ?? "RSS", _selectedItem.PublicationIconUrl, SavedArticleType.ReadLater);
        }
    }

    private void RssPivot_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (RssPivot == null || FeedSelectorContainer == null || RssSubtitleTextBlock == null) return;

        int index = RssPivot.SelectedIndex;
        if (index == 0)
        {
            FeedSelectorContainer.Visibility = Visibility.Visible;
            RssSubtitleTextBlock.Text = "Latest articles from your selected feed";
        }
        else if (index == 1)
        {
            FeedSelectorContainer.Visibility = Visibility.Collapsed;
            RssSubtitleTextBlock.Text = "Articles saved for reading later";
            UpdateSavedLists();
        }
        else if (index == 2)
        {
            FeedSelectorContainer.Visibility = Visibility.Collapsed;
            RssSubtitleTextBlock.Text = "Your starred favorite articles";
            UpdateSavedLists();
        }
    }

    private void PopulateFeedMenu()
    {
        FeedMenuFlyout.Items.Clear();
        if (_rssService.Feeds == null) return;

        foreach (var feed in _rssService.Feeds)
        {
            var menuItem = new MenuFlyoutItem
            {
                Text = feed.Name,
                DataContext = feed
            };

            try
            {
                var icon = new ImageIcon
                {
                    Source = new Microsoft.UI.Xaml.Media.Imaging.BitmapImage(new Uri(feed.IconUrl))
                };
                menuItem.Icon = icon;
            }
            catch { }

            menuItem.Click += FeedMenuItem_Click;
            FeedMenuFlyout.Items.Add(menuItem);
        }
    }

    private async void FeedMenuItem_Click(object sender, RoutedEventArgs e)
    {
        if (sender is MenuFlyoutItem menuItem && menuItem.DataContext is FeedSource selectedFeed)
        {
            await SelectFeedAsync(selectedFeed);
        }
    }

    private async void CycleLeftButton_Click(object sender, RoutedEventArgs e)
    {
        var feeds = _rssService.Feeds;
        if (feeds == null || feeds.Count == 0) return;

        int currentIndex = 0;
        if (_rssService.CurrentFeed != null)
        {
            currentIndex = feeds.FindIndex(f => f.Url == _rssService.CurrentFeed.Url);
            if (currentIndex < 0) currentIndex = 0;
        }

        int prevIndex = (currentIndex - 1 + feeds.Count) % feeds.Count;
        var prevFeed = feeds[prevIndex];
        await SelectFeedAsync(prevFeed);
    }

    private async void CycleRightButton_Click(object sender, RoutedEventArgs e)
    {
        var feeds = _rssService.Feeds;
        if (feeds == null || feeds.Count == 0) return;

        int currentIndex = 0;
        if (_rssService.CurrentFeed != null)
        {
            currentIndex = feeds.FindIndex(f => f.Url == _rssService.CurrentFeed.Url);
            if (currentIndex < 0) currentIndex = 0;
        }

        int nextIndex = (currentIndex + 1) % feeds.Count;
        var nextFeed = feeds[nextIndex];
        await SelectFeedAsync(nextFeed);
    }

    private async Task SelectFeedAsync(FeedSource feed)
    {
        if (feed == null) return;

        UpdateSelectedFeedUI(feed);

        if (_rssService.CurrentFeed == null || feed.Url != _rssService.CurrentFeed.Url)
        {
            LoadingPanel.Visibility = Visibility.Visible;
            ArticlesListView.Visibility = Visibility.Collapsed;
            _rssService.SelectFeed(feed);
            await _rssService.LoadFeedAsync(feed);
        }
    }

    private void UpdateSelectedFeedUI(FeedSource? feed)
    {
        if (feed == null)
        {
            SelectedFeedText.Text = "Select Feed";
            SelectedFeedIcon.Source = null;
            return;
        }

        SelectedFeedText.Text = feed.Name;
        try
        {
            SelectedFeedIcon.Source = new Microsoft.UI.Xaml.Media.Imaging.BitmapImage(new Uri(feed.IconUrl));
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[RssFeedDetailPage] Error loading icon: {ex.Message}");
            SelectedFeedIcon.Source = null;
        }
    }

    private void Page_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        double width = e.NewSize.Width;

        // Hide description text sooner to avoid collision
        if (RssSubtitleTextBlock != null)
        {
            RssSubtitleTextBlock.Visibility = width < 880 ? Visibility.Collapsed : Visibility.Visible;
        }

        // Switch Pivot headers to icons later
        UpdatePivotHeaders(width < 580);
    }

    private void UpdatePivotHeaders(bool isSmall)
    {
        if (RssPivot == null || _isHeaderIconsMode == isSmall) return;
        _isHeaderIconsMode = isSmall;

        if (RssPivot.Items.Count >= 3)
        {
            var item1 = RssPivot.Items[0] as PivotItem;
            var item2 = RssPivot.Items[1] as PivotItem;
            var item3 = RssPivot.Items[2] as PivotItem;

            if (item1 != null && item2 != null && item3 != null)
            {
                if (isSmall)
                {
                    item1.Header = CreateHeaderIcon("\uE736"); // Live Feed icon
                    item2.Header = CreateHeaderIcon("\uE8A4"); // Read Later icon
                    item3.Header = CreateHeaderIcon("\uE734"); // Favorites icon
                }
                else
                {
                    item1.Header = "Live Feed";
                    item2.Header = "Read Later";
                    item3.Header = "Favorites";
                }
            }
        }
    }

    private object CreateHeaderIcon(string glyph)
    {
        var fontIcon = new FontIcon
        {
            Glyph = glyph,
            FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Segoe Fluent Icons"),
            FontSize = 16
        };
        
        string toolTipText = glyph switch
        {
            "\uE736" => "Live Feed",
            "\uE8A4" => "Read Later",
            "\uE734" => "Favorites",
            _ => ""
        };

        ToolTipService.SetToolTip(fontIcon, toolTipText);
        return fontIcon;
    }

    private static readonly Dictionary<string, List<RssItem>> _allFeedsCache = new();
    private static bool _isPreFetchingAllFeeds = false;

    private async void PreFetchAllFeedsInBackground()
    {
        if (_isPreFetchingAllFeeds || _rssService.Feeds == null) return;
        _isPreFetchingAllFeeds = true;

        var httpClient = new System.Net.Http.HttpClient();
        httpClient.DefaultRequestHeaders.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36");

        foreach (var feed in _rssService.Feeds)
        {
            // Skip the current feed since it is already loaded or loading in the main page
            if (_rssService.CurrentFeed != null && feed.Url == _rssService.CurrentFeed.Url)
                continue;

            if (_allFeedsCache.ContainsKey(feed.Url))
                continue;

            _ = Task.Run(async () =>
            {
                try
                {
                    var xml = await httpClient.GetStringAsync(feed.Url);
                    var doc = System.Xml.Linq.XDocument.Parse(xml);
                    System.Xml.Linq.XNamespace dc = "http://purl.org/dc/elements/1.1/";
                    
                    var items = doc.Descendants().Where(e => e.Name.LocalName == "item" || e.Name.LocalName == "entry").Select(item =>
                    {
                        var title = item.Elements().FirstOrDefault(e => e.Name.LocalName == "title")?.Value ?? "No Title";
                        var linkEl = item.Elements().FirstOrDefault(e => e.Name.LocalName == "link");
                        var link = linkEl?.Attribute("href")?.Value;
                        if (string.IsNullOrEmpty(link)) link = linkEl?.Value ?? "";

                        var description = item.Elements().FirstOrDefault(e => e.Name.LocalName == "description" || e.Name.LocalName == "summary")?.Value;
                        var pubDateStr = item.Elements().FirstOrDefault(e => e.Name.LocalName == "pubDate" || e.Name.LocalName == "published" || e.Name.LocalName == "updated" || e.Name == dc + "date")?.Value;
                        
                        DateTime pubDate = DateTime.Now;
                        if (DateTime.TryParse(pubDateStr, out var parsedDate)) pubDate = parsedDate;

                        string? imageUrl = null;
                        var enclosure = item.Elements().FirstOrDefault(e => e.Name.LocalName == "enclosure" || (e.Name.LocalName == "link" && e.Attribute("rel")?.Value == "enclosure"));
                        if (enclosure != null)
                        {
                            imageUrl = enclosure.Attribute("url")?.Value ?? enclosure.Attribute("href")?.Value;
                        }

                        return new RssItem
                        {
                            Title = title,
                            Link = link,
                            PublishDate = pubDate,
                            ImageUrl = imageUrl,
                            Description = description,
                            PublicationName = feed.Name,
                            PublicationIconUrl = feed.IconUrl
                        };
                    }).ToList();

                    lock (_allFeedsCache)
                    {
                        _allFeedsCache[feed.Url] = items;
                    }

                    // Refresh recommendations once loaded
                    DispatcherQueue.TryEnqueue(() =>
                    {
                        if (_selectedItem != null) PopulateRecommendations(_selectedItem);
                    });
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine($"[Reader] Background pre-fetch failed for {feed.Name}: {ex.Message}");
                }
            });
        }
    }

    private void RecommendationsScrollViewer_LayoutUpdated(object? sender, object e)
    {
        UpdateButtonsOpacity();
    }

    private void RecommendationsScrollViewer_ViewChanged(object sender, ScrollViewerViewChangedEventArgs e)
    {
        UpdateButtonsOpacity();
    }

    private void UpdateButtonsOpacity()
    {
        if (RecommendationsScrollViewer == null || RecommendationsItemsControl == null) return;

        double viewportWidth = RecommendationsScrollViewer.ActualWidth;
        if (viewportWidth <= 0) return;

        double fadeZone = 36.0; // width of the fade zone at each end

        for (int i = 0; i < RecommendationsItemsControl.Items.Count; i++)
        {
            var container = RecommendationsItemsControl.ContainerFromIndex(i) as FrameworkElement;
            if (container == null) continue;

            double width = container.ActualWidth;
            if (width <= 0) continue;

            try
            {
                var transform = container.TransformToVisual(RecommendationsScrollViewer);
                var position = transform.TransformPoint(new Windows.Foundation.Point(0, 0));
                double left = position.X;
                double right = left + width;

                double opacity = 1.0;

                // Fade at the left edge
                if (left < fadeZone)
                {
                    double minLeft = -width;
                    if (left <= minLeft)
                    {
                        opacity = 0.0;
                    }
                    else
                    {
                        opacity = Math.Clamp((left - minLeft) / (fadeZone - minLeft), 0.0, 1.0);
                    }
                }

                // Fade at the right edge
                if (right > viewportWidth - fadeZone)
                {
                    double maxRight = viewportWidth + width;
                    if (right >= maxRight)
                    {
                        opacity = 0.0;
                    }
                    else
                    {
                        double rightOpacity = Math.Clamp((maxRight - right) / (maxRight - (viewportWidth - fadeZone)), 0.0, 1.0);
                        opacity = Math.Min(opacity, rightOpacity);
                    }
                }

                // Optimization: only set opacity if the change is significant (prevents layout loops or redraw overhead)
                if (Math.Abs(container.Opacity - opacity) > 0.01)
                {
                    container.Opacity = opacity;
                }
            }
            catch (Exception)
            {
                // In case transform fails during rapid UI updates
            }
        }
    }

    private void PopulateRecommendations(RssItem currentItem)
    {
        if (RecommendationsItemsControl == null) return;
        
        var recommendations = GetSmartRecommendations(currentItem, 20);
        RecommendationsItemsControl.ItemsSource = recommendations;

        // Update button opacities immediately after populating
        RecommendationsScrollViewer.UpdateLayout();
        UpdateButtonsOpacity();
    }

    private async void RecommendationButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.DataContext is RssItem item)
        {
            try
            {
                await OpenReaderViewAsync(item);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[Reader] Failed to load recommendation: {ex.Message}");
            }
        }
    }

    private List<RssItem> GetSmartRecommendations(RssItem currentItem, int count = 20)
    {
        var recommendations = new List<RssItem>();
        if (currentItem == null) return recommendations;

        // 1. Clean and tokenize Title
        var titleWords = currentItem.Title
            .Split(new[] { ' ', ',', '.', ';', ':', '-', '—', '?', '!', '"', '\'', '(', ')' }, StringSplitOptions.RemoveEmptyEntries)
            .Select(w => w.ToLowerInvariant())
            .Where(w => w.Length > 4)
            .ToList();

        // 2. Clean and tokenize Description (HTML-stripped)
        var cleanDescription = System.Text.RegularExpressions.Regex.Replace(currentItem.Description ?? "", "<.*?>", string.Empty);
        var descWords = cleanDescription
            .Split(new[] { ' ', ',', '.', ';', ':', '-', '—', '?', '!', '"', '\'', '(', ')' }, StringSplitOptions.RemoveEmptyEntries)
            .Select(w => w.ToLowerInvariant())
            .Where(w => w.Length > 4)
            .ToList();

        // Stop words set
        var stopWords = new HashSet<string>
        {
            "about", "above", "after", "again", "against", "along", "around", "before", "behind", "below", "beneath", 
            "between", "beyond", "during", "under", "within", "without", "should", "would", "could", "their", "there", 
            "these", "those", "first", "second", "three", "years", "before", "being", "other", "people", "which", "where",
            "about", "first", "since", "while", "where", "after", "before", "still", "often", "their", "there", "these",
            "those", "world", "local", "markets", "tech", "today", "yesterday", "tomorrow", "daily", "news", "articles",
            "report", "latest", "update", "updates", "reporting", "source", "views", "breaking", "exclusive", "inside"
        };

        // Filter out stop words
        var titleKeywords = titleWords.Where(w => !stopWords.Contains(w)).ToList();
        var descKeywords = descWords.Where(w => !stopWords.Contains(w)).ToList();

        // Count frequencies of words in title and description to find the most important keywords
        var wordFreq = new Dictionary<string, double>();
        foreach (var w in titleKeywords)
        {
            wordFreq[w] = wordFreq.GetValueOrDefault(w, 0) + 5.0; // Higher weight for title words
        }
        foreach (var w in descKeywords)
        {
            wordFreq[w] = wordFreq.GetValueOrDefault(w, 0) + 1.0;
        }

        // Keep the top 15 most important keywords
        var topKeywords = wordFreq.OrderByDescending(kvp => kvp.Value)
            .Take(15)
            .Select(kvp => kvp.Key)
            .ToList();

        // Find current feed source and category
        var currentFeedSource = _rssService.Feeds?.FirstOrDefault(f => f.Name == currentItem.PublicationName);
        var currentCategory = currentFeedSource?.Category;

        // Assemble candidates list
        var candidates = new List<RssItem>();

        if (_rssService.Items != null)
        {
            candidates.AddRange(_rssService.Items);
        }

        lock (_allFeedsCache)
        {
            foreach (var cachedItems in _allFeedsCache.Values)
            {
                candidates.AddRange(cachedItems);
            }
        }

        if (_articleService.ReadLaterItems != null)
        {
            candidates.AddRange(_articleService.ReadLaterItems.Select(saved => new RssItem
            {
                Title = saved.Title,
                Link = saved.ArticleUrl,
                PublishDate = saved.ArticleDate,
                ImageUrl = saved.ImageUrl,
                Description = saved.Description,
                Author = saved.Author,
                PublicationName = saved.PublicationName,
                PublicationIconUrl = saved.PublicationIconUrl
            }));
        }

        if (_articleService.FavoriteItems != null)
        {
            candidates.AddRange(_articleService.FavoriteItems.Select(saved => new RssItem
            {
                Title = saved.Title,
                Link = saved.ArticleUrl,
                PublishDate = saved.ArticleDate,
                ImageUrl = saved.ImageUrl,
                Description = saved.Description,
                Author = saved.Author,
                PublicationName = saved.PublicationName,
                PublicationIconUrl = saved.PublicationIconUrl
            }));
        }

        // Remove duplicates and the current item
        var uniqueCandidates = candidates
            .Where(c => c.Link != currentItem.Link && !string.Equals(c.Title, currentItem.Title, StringComparison.OrdinalIgnoreCase))
            .GroupBy(c => c.Link)
            .Select(g => g.First())
            .ToList();

        var scoredCandidates = uniqueCandidates.Select(c =>
        {
            double score = 0;

            // 1. Keyword overlap scoring
            if (topKeywords.Count > 0)
            {
                var titleLower = c.Title.ToLowerInvariant();
                var descLower = System.Text.RegularExpressions.Regex.Replace(c.Description ?? "", "<.*?>", string.Empty).ToLowerInvariant();

                foreach (var kw in topKeywords)
                {
                    if (titleLower.Contains(kw)) score += 10.0;
                    if (descLower.Contains(kw)) score += 2.0;
                }
            }

            // 2. Category matching bonus
            if (currentCategory != null && _rssService.Feeds != null)
            {
                var candidateFeedSource = _rssService.Feeds.FirstOrDefault(f => f.Name == c.PublicationName);
                if (candidateFeedSource != null && candidateFeedSource.Category == currentCategory.Value)
                {
                    score += 20.0; // Significant bonus for same-category feeds (e.g. both are tech or politics)
                }
            }

            return new { Item = c, Score = score };
        })
        .ToList();

        // Separate matching and fallback candidates
        var matchingCandidates = scoredCandidates
            .Where(sc => sc.Score > 0)
            .OrderByDescending(sc => sc.Score)
            .ThenByDescending(sc => sc.Item.PublishDate)
            .Select(sc => sc.Item)
            .ToList();

        var fallbackCandidates = scoredCandidates
            .Where(sc => sc.Score == 0)
            .OrderByDescending(sc => sc.Item.PublishDate)
            .Select(sc => sc.Item)
            .ToList();

        // Round-robin selection helper
        List<RssItem> selected = new List<RssItem>();

        // 1. Round-robin select matching articles
        if (matchingCandidates.Count > 0)
        {
            var matchingGroups = matchingCandidates
                .GroupBy(c => c.PublicationName ?? "Unknown")
                .ToDictionary(g => g.Key, g => new Queue<RssItem>(g));

            bool addedAnyInRound = true;
            while (selected.Count < count && addedAnyInRound)
            {
                addedAnyInRound = false;
                foreach (var key in matchingGroups.Keys.ToList())
                {
                    if (selected.Count >= count) break;
                    var queue = matchingGroups[key];
                    if (queue.Count > 0)
                    {
                        selected.Add(queue.Dequeue());
                        addedAnyInRound = true;
                    }
                }
            }
        }

        // 2. Round-robin select fallback articles if count not reached
        if (selected.Count < count && fallbackCandidates.Count > 0)
        {
            var fallbackGroups = fallbackCandidates
                .GroupBy(c => c.PublicationName ?? "Unknown")
                .ToDictionary(g => g.Key, g => new Queue<RssItem>(g));

            bool addedAnyInRound = true;
            while (selected.Count < count && addedAnyInRound)
            {
                addedAnyInRound = false;
                foreach (var key in fallbackGroups.Keys.ToList())
                {
                    if (selected.Count >= count) break;
                    var queue = fallbackGroups[key];
                    if (queue.Count > 0)
                    {
                        selected.Add(queue.Dequeue());
                        addedAnyInRound = true;
                    }
                }
            }
        }

        return selected;
    }
}
