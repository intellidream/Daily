using System;
using System.Linq;
using System.Text.RegularExpressions;
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

    public ObservableCollection<Daily_WinUI.ViewModels.RssItemViewModel> Articles => _articles;
    public ObservableCollection<Daily_WinUI.ViewModels.RssItemViewModel> ReadLaterArticles => _readLaterArticles;
    public ObservableCollection<Daily_WinUI.ViewModels.RssItemViewModel> FavoriteArticles => _favoriteArticles;
    private RssItem? _selectedItem;
    private RssItem? _currentRenderedArticle;
    private bool _isHeaderIconsMode;
    private Task? _webViewInitTask;
    private readonly FeedSource _allNewsFeedSource = new FeedSource
    {
        Name = "All News",
        Url = "all_news",
        IconUrl = ""
    };
    private readonly FeedSource _mediumReadingListSource = new FeedSource
    {
        Name = "Medium Reading List",
        Url = "medium_reading_list",
        IconUrl = ""
    };
    private readonly FeedSource _substackInboxSource = new FeedSource
    {
        Name = "Substack Inbox",
        Url = "substack_inbox",
        IconUrl = "https://substack.com/favicon.ico"
    };
    private FeedSource? _currentLocalFeed;

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

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);

        if (e.Parameter is RssItem preSelectedItem)
        {
            // The user clicked an item from the widget. Store it to open on Loaded.
            _selectedItem = preSelectedItem;
        }
    }

    private async void RssFeedDetailPage_Loaded(object sender, RoutedEventArgs e)
    {
        if (this.Frame != App.Current?.MainWindow?.RootFrame)
        {
            if (BackButton != null) BackButton.Visibility = Visibility.Collapsed;
            if (ListViewBackButton != null) ListViewBackButton.Visibility = Visibility.Collapsed;
            if (ListViewPopOutButton != null) ListViewPopOutButton.Visibility = Visibility.Collapsed;
            if (ReaderPopOutButton != null) ReaderPopOutButton.Visibility = Visibility.Collapsed;
        }

        _rssService.OnFeedChanged += RssService_OnFeedChanged;
        _rssService.OnItemsUpdated += RssService_OnItemsUpdated;
        _articleService.OnItemsChanged += ArticleService_OnItemsChanged;

        PopulateFeedMenu();
        PreFetchAllFeedsInBackground();
        
        // Put current feed items in cache if already loaded
        if (_rssService.CurrentFeed != null && 
            _rssService.CurrentFeed.Url != "all_news" && 
            _rssService.CurrentFeed.Url != "medium_reading_list" &&
            _rssService.Items != null && 
            _rssService.Items.Count > 0)
        {
            lock (_allFeedsCache)
            {
                _allFeedsCache[_rssService.CurrentFeed.Url] = _rssService.Items;
            }
        }

        if (_selectedItem != null)
        {
            var feed = _rssService.Feeds?.FirstOrDefault(f => f.Name == _selectedItem.PublicationName);
            if (feed != null)
            {
                _currentLocalFeed = feed;
                _rssService.SelectFeed(feed);
                UpdateSelectedFeedUI(feed);
            }
            
            // Open Reader View after the page is fully loaded and in the visual tree
            await OpenReaderViewAsync(_selectedItem);
        }
        else
        {
            _currentLocalFeed = _rssService.CurrentFeed;
            UpdateSelectedFeedUI(_currentLocalFeed);
        }
        
        if (_currentLocalFeed != null && _currentLocalFeed.Url == "all_news")
        {
            await LoadAllNewsFeedAsync();
        }
        else
        {
            UpdateArticles();
        }
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
            var feeds = GetFeedsListWithAllNews();
            if (_currentLocalFeed == null || !feeds.Any(f => f.Url == _currentLocalFeed.Url))
            {
                _currentLocalFeed = _rssService.CurrentFeed;
            }
            UpdateSelectedFeedUI(_currentLocalFeed);
        });
    }

    private void RssService_OnItemsUpdated()
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            if (_rssService.CurrentFeed != null && _rssService.Items != null)
            {
                // ONLY cache under the feed URL if we are actually viewing that specific feed in the UI
                // and it's not a custom/special feed like All News or Reading List!
                if (_currentLocalFeed != null && 
                    _currentLocalFeed.Url == _rssService.CurrentFeed.Url &&
                    _currentLocalFeed.Url != "all_news" && 
                    _currentLocalFeed.Url != "medium_reading_list")
                {
                    lock (_allFeedsCache)
                    {
                        _allFeedsCache[_rssService.CurrentFeed.Url] = _rssService.Items;
                    }
                }
            }
            UpdateArticles();
        });
    }

    private void UpdateArticles()
    {
        if (_currentLocalFeed != null && (_currentLocalFeed.Url == "all_news" || _currentLocalFeed.Url == "medium_reading_list"))
        {
            return;
        }

        string query = ArticleSearchBox?.Text ?? string.Empty;
        if (!string.IsNullOrWhiteSpace(query))
        {
            FilterArticles(query);
        }
        else
        {
            _articles.Clear();
            foreach (var item in _rssService.Items)
            {
                _articles.Add(new Daily_WinUI.ViewModels.RssItemViewModel(item));
            }
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
        try
        {
            var syncService = App.Current?.Services?.GetService<Daily.Services.ISyncService>();
            if (syncService != null)
            {
                await syncService.SyncAsync(Daily.Services.SyncScope.SavedArticles | Daily.Services.SyncScope.RssSubscriptions);
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[RssFeedDetailPage] Cloud sync warning: {ex.Message}");
        }

        UpdateSavedLists();

        if (_selectedItem != null)
        {
            await OpenReaderViewAsync(_selectedItem);
            return;
        }

        if (_currentLocalFeed != null)
        {
            if (_currentLocalFeed.Url == "all_news")
            {
                lock (_allFeedsCache)
                {
                    _allFeedsCache.Clear();
                }
                await LoadAllNewsFeedAsync(forceRefresh: true);
            }
            else
            {
                LoadingPanel.Visibility = Visibility.Visible;
                ArticlesListView.Visibility = Visibility.Collapsed;
                await _rssService.LoadFeedAsync(_currentLocalFeed, forceRefresh: true);
            }
        }
    }

    private Task EnsureWebViewInitializedAsync()
    {
        if (_webViewInitTask == null || _webViewInitTask.IsFaulted || _webViewInitTask.IsCanceled)
        {
            _webViewInitTask = InitWebViewInternalAsync();
        }
        return _webViewInitTask;
    }

    private async Task InitWebViewInternalAsync()
    {
        try
        {
            string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string userDataFolder = System.IO.Path.Combine(localAppData, "Daily.WinUI", "WebView2");
            System.IO.Directory.CreateDirectory(userDataFolder);

            var options = new Microsoft.Web.WebView2.Core.CoreWebView2EnvironmentOptions();
            var env = await Microsoft.Web.WebView2.Core.CoreWebView2Environment.CreateWithOptionsAsync(null, userDataFolder, options);
            await ReaderWebView.EnsureCoreWebView2Async(env);
            await BackgroundWebView.EnsureCoreWebView2Async(env);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"WebView2 initialization failed: {ex.Message}");
            throw;
        }
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
            if (_articles.Count == 0 && _currentLocalFeed != null)
            {
                if (_currentLocalFeed.Url == "all_news")
                {
                    _ = LoadAllNewsFeedAsync();
                }
                else
                {
                    _ = _rssService.LoadFeedAsync(_currentLocalFeed);
                }
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
        try
        {
            var behaviorService = App.Current.Services.GetRequiredService<IBehaviorService>();
            string safeTitle = (item.Title ?? "").Replace("\"", "\\\"");
            string safeSource = (item.PublicationName ?? "RSS").Replace("\"", "\\\"");
            string metadata = $"{{\"title\":\"{safeTitle}\",\"source\":\"{safeSource}\"}}";
            _ = behaviorService.TrackEventAsync("News", "ReadArticle", metadata);
        }
        catch { }

        _currentRenderedArticle = null;
        _selectedItem = item;
        UpdateReaderToolbarStates();
        PopulateRecommendations(item);
        ListViewContainer.Visibility = Visibility.Collapsed;
        ReaderViewContainer.Visibility = Visibility.Visible;
        ReaderLoadingPanel.Visibility = Visibility.Visible;
        ReaderProgressRing.IsActive = true;
        ReaderProgressRing.Visibility = Visibility.Visible;
        ReaderLoadingText.Text = "Extracting article...";
        ReaderWebView.Visibility = Visibility.Collapsed;
        ReaderWebView.Opacity = 1;

        bool isDark = this.ActualTheme == ElementTheme.Dark;
        string fallbackText = isDark ? "#E0E0E0" : "#1A1A1A";
        string fallbackLink = isDark ? "#66B2FF" : "#0066CC";
        string fallbackBg = isDark ? "#1A1423" : "#EDE5D9";

        // Step 1: Try the fast HttpClient + SmartReader path
        RssItem? fullArticle = null;
        bool needsWebViewFallback = false;

        bool isMedium = !string.IsNullOrEmpty(item.Link) && 
                         (item.Link.Contains("medium.com", StringComparison.OrdinalIgnoreCase) || 
                          (item.PublicationName != null && item.PublicationName.Contains("Medium", StringComparison.OrdinalIgnoreCase)));

        bool isSubstack = IsItemSubstack(item);

        bool hasSubstantialContent = !string.IsNullOrWhiteSpace(item.Content) && 
                                     item.Content.Length > 250 && 
                                     !IsMediumTeaser(item.Content) &&
                                     !IsSubstackTeaser(item.Content);

        var appSettingsForSubstack = isSubstack ? SettingsService.Load() : null;
        bool shouldUpgradeSubstackBonus = isSubstack &&
                                          hasSubstantialContent &&
                                          HasSubstackBonusPaywall(item.Content) &&
                                          !string.IsNullOrEmpty(appSettingsForSubstack?.SubstackUsername);

        if (isMedium && hasSubstantialContent)
        {
            fullArticle = item;
            needsWebViewFallback = false;
        }
        else if (isSubstack && hasSubstantialContent && !shouldUpgradeSubstackBonus)
        {
            string purified = StripSubstackTrackingAndNoise(item.Content!);
            if (!string.IsNullOrEmpty(item.ImageUrl))
            {
                purified = DeduplicateSubstackFeaturedImage(purified, item.ImageUrl);
            }
            fullArticle = new RssItem
            {
                Title = item.Title,
                Link = item.Link,
                Content = purified,
                Description = item.Description,
                Author = item.Author,
                PublishDate = item.PublishDate,
                PublicationName = item.PublicationName,
                PublicationIconUrl = item.PublicationIconUrl,
                ImageUrl = item.ImageUrl
            };
            needsWebViewFallback = false;
        }
        else if (isSubstack)
        {
            fullArticle = await ExtractSubstackArticleAsync(item);
            if (fullArticle != null && !string.IsNullOrWhiteSpace(fullArticle.Content) && fullArticle.Content.Length > 100)
            {
                needsWebViewFallback = false;
            }
            else
            {
                needsWebViewFallback = true;
            }
        }
        else if (isMedium)
        {
            System.Diagnostics.Debug.WriteLine($"[Reader] Forcing WebView2 fallback for Medium link to preserve cookie authentication: {item.Link}");
            needsWebViewFallback = true;
        }
        else
        {
            try
            {
                fullArticle = await _rssService.FetchFullArticleAsync(item.Link);
                
                // FetchFullArticleAsync never throws — it returns Title="Error fetching article" on failure.
                // Detect that and trigger the WebView2 fallback instead of showing the error.
                if (fullArticle.Title == "Error fetching article" || string.IsNullOrWhiteSpace(fullArticle.Content))
                {
                    if (!string.IsNullOrWhiteSpace(item.Content) && item.Content.Length > 80)
                    {
                        fullArticle = item;
                    }
                    else
                    {
                        needsWebViewFallback = true;
                    }
                }
            }
            catch
            {
                if (!string.IsNullOrWhiteSpace(item.Content) && item.Content.Length > 80)
                {
                    fullArticle = item;
                }
                else
                {
                    needsWebViewFallback = true;
                }
            }
        }

        // Step 2: If the fast path succeeded, render it
        if (!needsWebViewFallback && fullArticle != null)
        {
            try
            {
                // Preserve publication name/icon from the clicked item unless Substack API upgraded generic placeholders
                if (string.IsNullOrEmpty(fullArticle.PublicationName) ||
                    (!string.IsNullOrEmpty(item.PublicationName) && item.PublicationName != "Substack" && item.PublicationName != "Substack Inbox"))
                {
                    fullArticle.PublicationName = item.PublicationName;
                }
                if (string.IsNullOrEmpty(fullArticle.PublicationIconUrl) ||
                    (!string.IsNullOrEmpty(item.PublicationIconUrl) && item.PublicationIconUrl != "https://substack.com/favicon.ico"))
                {
                    fullArticle.PublicationIconUrl = item.PublicationIconUrl;
                }

                if (string.IsNullOrEmpty(fullArticle.ImageUrl) && !string.IsNullOrEmpty(item.ImageUrl))
                {
                    fullArticle.ImageUrl = item.ImageUrl;
                }
                if (string.IsNullOrEmpty(fullArticle.Author) && !string.IsNullOrEmpty(item.Author))
                {
                    fullArticle.Author = item.Author;
                }

                _currentRenderedArticle = fullArticle;
                UpdateReaderToolbarStates();
                string html = GenerateReaderHtml(fullArticle);
                
                // Set visibility to Visible with Opacity 0 to allow WebView2 to initialize
                ReaderWebView.Visibility = Visibility.Visible;
                ReaderWebView.Opacity = 0.0;

                await EnsureWebViewInitializedAsync();
                if (ReaderWebView.CoreWebView2 == null)
                    throw new InvalidOperationException("CoreWebView2 is null after initialization.");

                UpdateWebViewBackground();
                SetupWebViewVirtualHost();
                ReaderWebView.NavigateToString(html);
                ReaderLoadingPanel.Visibility = Visibility.Collapsed;
                ReaderWebView.Opacity = 1.0;
                return;
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[Reader] Fast path rendering failed: {ex.Message}. Falling back to WebView2 navigation...");
                needsWebViewFallback = true;
            }
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
            
            await EnsureWebViewInitializedAsync();
            if (ReaderWebView.CoreWebView2 == null)
                throw new InvalidOperationException("CoreWebView2 failed to initialize in fallback path.");

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

                    // Remove cookie/GDPR overlays that block content, with safety guards so real story content is never stripped
                    var cleanupScript = "(function(){" +
                        "var selectors=['#cmp-app-container','.cookie-banner','#cookie-consent','.gdpr-modal'," +
                        "'[class*=\"cookie\"]','[id*=\"cookie\"]','[class*=\"consent\"]','[class*=\"paywall\"]'," +
                        "'[id*=\"consent\"]','[class*=\"overlay\"]','[id*=\"piano\"]'," +
                        "'.subscription-widget-wrap','.subscribe-widget','.post-footer','.like-button-container','.share-dialog','.comment-widget'];" +
                        "selectors.forEach(function(s){" +
                        "    document.querySelectorAll(s).forEach(function(e){" +
                        "        if(e.tagName==='ARTICLE'||e.tagName==='MAIN'||e.tagName==='SECTION') return;" +
                        "        if(e.querySelectorAll('p').length>=2||(e.innerText||'').length>300) return;" +
                        "        e.remove();" +
                        "    });" +
                        "});" +
                        "var upsells=['.meteredContentUpsell','[data-testid=\"paywall-dialog\"]','[data-testid=\"upgrade-banner\"]','[data-testid=\"postPaywallBanner\"]'];" +
                        "upsells.forEach(function(s){" +
                        "    document.querySelectorAll(s).forEach(function(e){" +
                        "        if(e.querySelectorAll('p').length<2&&(e.innerText||'').length<300) e.remove();" +
                        "    });" +
                        "});" +
                        "document.body.style.overflow='auto';document.documentElement.style.overflow='auto';" +
                        "document.body.style.position='static';" +
                        "var main=document.querySelector('article')||document.querySelector('main')||document.querySelector('[role=\"main\"]');" +
                        "if(main){main.style.display='block';main.style.visibility='visible';main.style.opacity='1';}" +
                        "})()";
                    await ReaderWebView.ExecuteScriptAsync(cleanupScript);

                    // Poll until the page has substantial text content (JS-rendered)
                    string extractedHtml = "";
                    int lastChars = 0;
                    int stableCount = 0;

                    var stateCheckScript = "(function(){" +
                        "var s = window.__APOLLO_STATE__ || {};" +
                        "var rq = s.ROOT_QUERY || {};" +
                        "var hasViewer = Boolean(rq.viewer);" +
                        "var postKey = Object.keys(s).find(function(k){ return k.indexOf('Post:') === 0; });" +
                        "var post = postKey ? s[postKey] : null;" +
                        "var isLocked = post ? Boolean(post.isLocked) : false;" +
                        "var expectedWords = (post && typeof post.wordCount === 'number') ? post.wordCount : 0;" +
                        "var apolloParagraphs = Object.keys(s).filter(function(k){ return k.indexOf('Paragraph:') === 0; }).length;" +
                        "var el = document.querySelector('article') || document.querySelector('main') || document.body;" +
                        "var text = (el && el.innerText) ? el.innerText.trim() : '';" +
                        "var words = text ? text.split(/\\s+/).length : 0;" +
                        "var domBlocks = el ? el.querySelectorAll('p, h1, h2, h3, h4, pre, li, blockquote').length : 0;" +
                        "return JSON.stringify({" +
                        "    hasViewer: hasViewer," +
                        "    isLocked: isLocked," +
                        "    expectedWords: expectedWords," +
                        "    apolloParagraphs: apolloParagraphs," +
                        "    domWords: words," +
                        "    domChars: text.length," +
                        "    domBlocks: domBlocks" +
                        "});" +
                        "})()";

                    var extractArticleScript = "(function(){" +
                        "var selectors='article, main, [itemprop=\"articleBody\"], .article-body, .article-content, .post-content, .entry-content, .layout-article-body';" +
                        "var el=document.querySelector(selectors);" +
                        "if(el && el.innerText && el.innerText.length > 200) {" +
                        "    var clone = el.cloneNode(true);" +
                        "    var junk = clone.querySelectorAll('button, [data-testid*=\"clap\"], [data-testid*=\"response\"], .responsesStream, [data-testid=\"postSidebar\"], [data-testid=\"authorPhoto\"], img[src*=\"resize:fill:48:48\"], img[src*=\"resize:fill:64:64\"], img[src*=\"resize:fill:88:88\"]');" +
                        "    junk.forEach(function(j){ j.remove(); });" +
                        "    clone.querySelectorAll('div, aside, section').forEach(function(box){" +
                        "        if(box.tagName === 'ARTICLE') return;" +
                        "        var txt = (box.innerText || '').trim();" +
                        "        if(txt.length > 0 && txt.length < 360 && box.querySelectorAll('p').length <= 3) {" +
                        "            var lower = txt.toLowerCase();" +
                        "            if(lower.indexOf('stories in your inbox') !== -1 || (lower.indexOf('stories in ') !== -1 && lower.indexOf('inbox') !== -1) || lower.indexOf('get updates from this writer') !== -1) {" +
                        "                box.remove();" +
                        "            }" +
                        "        }" +
                        "    });" +
                        "    var headMeta = Array.from(document.querySelectorAll('title, meta[property^=\"og:\"], meta[name=\"author\"], meta[property*=\"author\"]'))" +
                        "        .map(function(m){ return m.outerHTML; }).join('');" +
                        "    return '<html><head><meta charset=\"utf-8\"/>' + headMeta + '</head><body>' + clone.outerHTML + '</body></html>';" +
                        "}" +
                        "if(document.body && document.body.innerText && document.body.innerText.length > 500) {" +
                        "    return document.documentElement.outerHTML;" +
                        "}" +
                        "return null;" +
                        "})()";

                    for (int i = 0; i < 12; i++)
                    {
                        await Task.Delay(i == 0 ? 500 : 400);

                        bool hasViewer = false;
                        bool isLocked = false;
                        int expectedWords = 0;
                        int apolloParagraphs = 0;
                        int domWords = 0;
                        int domChars = 0;
                        int domBlocks = 0;

                        try
                        {
                            var stateJsonRaw = await ReaderWebView.ExecuteScriptAsync(stateCheckScript);
                            if (!string.IsNullOrWhiteSpace(stateJsonRaw) && stateJsonRaw != "null")
                            {
                                string unescapedState = System.Text.Json.JsonSerializer.Deserialize<string>(stateJsonRaw) ?? stateJsonRaw;
                                using var doc = System.Text.Json.JsonDocument.Parse(unescapedState);
                                var root = doc.RootElement;
                                if (root.TryGetProperty("hasViewer", out var hv)) hasViewer = hv.GetBoolean();
                                if (root.TryGetProperty("isLocked", out var il)) isLocked = il.GetBoolean();
                                if (root.TryGetProperty("expectedWords", out var ew)) expectedWords = ew.GetInt32();
                                if (root.TryGetProperty("apolloParagraphs", out var ap)) apolloParagraphs = ap.GetInt32();
                                if (root.TryGetProperty("domWords", out var dw)) domWords = dw.GetInt32();
                                if (root.TryGetProperty("domChars", out var dc)) domChars = dc.GetInt32();
                                if (root.TryGetProperty("domBlocks", out var db)) domBlocks = db.GetInt32();
                            }
                        }
                        catch { }

                        bool hasFullExpectedWords = expectedWords > 0 && domWords >= (int)(expectedWords * 0.68);
                        bool hasAllUnlockedBlocks = !isLocked && apolloParagraphs > 0 && domBlocks >= (int)(apolloParagraphs * 0.85) && domChars > 350;
                        bool isLockedWithoutViewer = i >= 1 && isLocked && !hasViewer;

                        if (hasFullExpectedWords || hasAllUnlockedBlocks || isLockedWithoutViewer || i >= 10)
                        {
                            await ReaderWebView.ExecuteScriptAsync("window.scrollTo(0, document.body.scrollHeight / 2);");
                            await Task.Delay(100);
                            await ReaderWebView.ExecuteScriptAsync("window.scrollTo(0, document.body.scrollHeight);");
                            await Task.Delay(100);
                            await ReaderWebView.ExecuteScriptAsync("window.scrollTo(0, 0);");
                            await ReaderWebView.ExecuteScriptAsync(cleanupScript);

                            var articleJson = await ReaderWebView.ExecuteScriptAsync(extractArticleScript);
                            if (articleJson != null && articleJson != "null")
                            {
                                try { extractedHtml = System.Text.Json.JsonSerializer.Deserialize<string>(articleJson) ?? ""; }
                                catch { extractedHtml = articleJson; }
                            }
                            if (!string.IsNullOrWhiteSpace(extractedHtml) && extractedHtml.Length > 200)
                                break;
                        }

                        // Hydration scroll triggers on intermediate iterations
                        if (i % 3 == 0)
                        {
                            await ReaderWebView.ExecuteScriptAsync("window.scrollTo(0, document.body.scrollHeight / 2);");
                        }
                        else if (i % 3 == 1)
                        {
                            await ReaderWebView.ExecuteScriptAsync("window.scrollTo(0, document.body.scrollHeight);");
                        }
                        else
                        {
                            await ReaderWebView.ExecuteScriptAsync("window.scrollTo(0, 0);");
                        }

                        if (domChars > 300)
                        {
                            if (domChars == lastChars)
                            {
                                stableCount++;
                            }
                            else
                            {
                                stableCount = 0;
                                lastChars = domChars;
                            }

                            if ((domChars > 3000 && stableCount >= 2) || (i >= 6 && stableCount >= 2))
                            {
                                await ReaderWebView.ExecuteScriptAsync(cleanupScript);
                                var articleJson = await ReaderWebView.ExecuteScriptAsync(extractArticleScript);
                                if (articleJson != null && articleJson != "null")
                                {
                                    try { extractedHtml = System.Text.Json.JsonSerializer.Deserialize<string>(articleJson) ?? ""; }
                                    catch { extractedHtml = articleJson; }
                                }
                                if (!string.IsNullOrWhiteSpace(extractedHtml) && extractedHtml.Length > 200)
                                    break;
                            }
                        }
                    }

                    if (string.IsNullOrWhiteSpace(extractedHtml))
                    {
                        var fullJson = await ReaderWebView.ExecuteScriptAsync("document.documentElement.outerHTML;");
                        if (fullJson != null && fullJson != "null")
                        {
                            try { extractedHtml = System.Text.Json.JsonSerializer.Deserialize<string>(fullJson) ?? ""; }
                            catch { extractedHtml = fullJson; }
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

            // Sanitize cookies and ensure parent domain .medium.com cookies apply across subdomains
            if (!string.IsNullOrEmpty(item.Link) && item.Link.Contains("medium.com"))
            {
                try
                {
                    var cookieManager = ReaderWebView.CoreWebView2.CookieManager;
                    var mediumCookies = await cookieManager.GetCookiesAsync("https://medium.com");
                    bool hasAuthUid = false;
                    foreach (var c in mediumCookies)
                    {
                        if (c.Name == "uid" && !string.IsNullOrEmpty(c.Value) && !c.Value.StartsWith("lo_", StringComparison.OrdinalIgnoreCase))
                        {
                            hasAuthUid = true;
                            break;
                        }
                    }

                    var targetUri = new Uri(item.Link);
                    var targetCookies = await cookieManager.GetCookiesAsync(item.Link);
                    foreach (var c in targetCookies)
                    {
                        // Delete host-only cookies on subdomains that shadow .medium.com per RFC 6265 §5.4
                        if (c.Domain.Equals(targetUri.Host, StringComparison.OrdinalIgnoreCase) && !c.Domain.Equals("medium.com", StringComparison.OrdinalIgnoreCase))
                        {
                            cookieManager.DeleteCookie(c);
                        }
                        else if (c.Name == "uid" && c.Value.StartsWith("lo_", StringComparison.OrdinalIgnoreCase) && hasAuthUid)
                        {
                            cookieManager.DeleteCookie(c);
                        }
                    }

                    // Promote any host-only medium.com auth cookies to .medium.com
                    foreach (var c in mediumCookies)
                    {
                        if ((c.Name == "uid" || c.Name == "sid") && c.Domain == "medium.com")
                        {
                            var wildcard = cookieManager.CreateCookie(c.Name, c.Value, ".medium.com", c.Path);
                            wildcard.IsHttpOnly = c.IsHttpOnly;
                            wildcard.IsSecure = c.IsSecure;
                            cookieManager.AddOrUpdateCookie(wildcard);
                        }
                    }
                }
                catch { }
            }

            ReaderWebView.CoreWebView2.Navigate(item.Link);
            
            // Wait up to 30s for the scraping to complete
            var completedTask = await Task.WhenAny(tcs.Task, Task.Delay(30000));
            string loadedHtml = "";
            if (completedTask == tcs.Task)
            {
                loadedHtml = await tcs.Task;
            }

            if (!string.IsNullOrWhiteSpace(loadedHtml))
            {
                loadedHtml = System.Text.RegularExpressions.Regex.Replace(
                    loadedHtml,
                    @"<img[^>]*medium\.com/_/stat[^>]*>",
                    "",
                    System.Text.RegularExpressions.RegexOptions.IgnoreCase
                );
            }
            
            if (!string.IsNullOrWhiteSpace(loadedHtml) && loadedHtml.Length > 200)
            {
                var reader = new SmartReader.Reader(item.Link, loadedHtml);
                var article = reader.GetArticle();
                
                string? chosenContent = null;
                if (article.IsReadable && !string.IsNullOrWhiteSpace(article.Content) && article.Content.Length > 250)
                {
                    chosenContent = article.Content;
                }
                
                // If SmartReader stripped too much, discarded sections, or wasn't readable,
                // fall back safely to the cleaned article HTML
                if (string.IsNullOrWhiteSpace(chosenContent) || chosenContent.Length < 300)
                {
                    int bodyStart = loadedHtml.IndexOf("<body", StringComparison.OrdinalIgnoreCase);
                    if (bodyStart >= 0)
                    {
                        int tagClose = loadedHtml.IndexOf('>', bodyStart);
                        int bodyEnd = loadedHtml.IndexOf("</body>", StringComparison.OrdinalIgnoreCase);
                        if (tagClose >= 0 && bodyEnd > tagClose)
                        {
                            chosenContent = loadedHtml.Substring(tagClose + 1, bodyEnd - tagClose - 1);
                        }
                    }
                    if (string.IsNullOrWhiteSpace(chosenContent))
                    {
                        chosenContent = loadedHtml;
                    }
                }

                if (!string.IsNullOrWhiteSpace(chosenContent) && chosenContent.Length > 80)
                {
                    var fallbackArticle = new RssItem 
                    {
                        Title = !string.IsNullOrEmpty(article?.Title) ? article.Title : item.Title,
                        Link = item.Link,
                        Content = chosenContent,
                        Description = article?.Excerpt ?? article?.TextContent ?? item.Description,
                        Author = article?.Byline ?? item.Author,
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
            
            if (ReaderWebView.CoreWebView2 != null)
            {
                try
                {
                    UpdateWebViewBackground();
                    ReaderWebView.NavigateToString($"<html><head><style>body {{ font-family: 'Segoe UI', sans-serif; padding: 40px; color: {fallbackText}; background: {fallbackBg}; }}</style></head><body><h2>Error loading article</h2><p>{fallbackEx.Message}</p></body></html>");
                }
                catch { }
            }
            else
            {
                ReaderProgressRing.IsActive = false;
                ReaderProgressRing.Visibility = Visibility.Collapsed;
                ReaderLoadingText.Text = $"Failed to load article: {fallbackEx.Message}";
            }
        }
        finally
        {
            if (ReaderWebView.CoreWebView2 != null)
            {
                ReaderLoadingPanel.Visibility = Visibility.Collapsed;
                ReaderWebView.Visibility = Visibility.Visible;
                ReaderWebView.Opacity = 1.0;
            }
            else
            {
                ReaderLoadingPanel.Visibility = Visibility.Visible;
                ReaderWebView.Visibility = Visibility.Collapsed;
            }
        }
    }

    private void BackButton_Click(object sender, RoutedEventArgs e)
    {
        _selectedItem = null;
        _currentRenderedArticle = null;
        ReaderViewContainer.Visibility = Visibility.Collapsed;
        ListViewContainer.Visibility = Visibility.Visible;
        
        // If we don't have articles loaded (e.g., navigated directly to an article from widget), load the selected feed
        if (_articles.Count == 0 && _currentLocalFeed != null)
        {
            if (_currentLocalFeed.Url == "all_news")
            {
                _ = LoadAllNewsFeedAsync();
            }
            else
            {
                _ = _rssService.LoadFeedAsync(_currentLocalFeed);
            }
        }
    }

    private void ListViewBackButton_Click(object sender, RoutedEventArgs e)
    {
        if (this.Frame?.CanGoBack == true)
        {
            this.Frame.GoBack();
        }
        else
        {
            if (App.Current?.MainWindow is MainWindow mw)
            {
                mw.NavigateToTab(1);
            }
            else
            {
                this.Frame?.Navigate(typeof(MainPage));
            }
        }
    }

    private void PopOutButton_Click(object sender, RoutedEventArgs e)
    {
        if (App.Current?.MainWindow is MainWindow mw)
        {
            mw.OpenDetailWindow(typeof(RssFeedDetailPage), _selectedItem);
            mw.NavigateToTab(1);
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
        .paywall-card {{
            background: {(isDark ? "rgba(255,255,255,0.04)" : "rgba(0,0,0,0.03)")};
            border: 1px solid {(isDark ? "rgba(255,255,255,0.12)" : "rgba(0,0,0,0.12)")};
            border-radius: 16px;
            padding: 24px;
            text-align: center;
            margin: 32px 0;
        }}
        .paywall-icon {{
            font-size: 32px;
            margin-bottom: 12px;
        }}
        .open-browser-btn {{
            display: inline-block;
            margin-top: 16px;
            padding: 10px 20px;
            background: {(isDark ? "rgba(102, 178, 255, 0.15)" : "rgba(0, 102, 204, 0.1)")};
            color: {linkColor} !important;
            border: 1px solid {(isDark ? "rgba(102, 178, 255, 0.3)" : "rgba(0, 102, 204, 0.3)")};
            border-radius: 20px;
            font-weight: 600;
            font-size: 14px;
            text-decoration: none !important;
        }}
        .substack-subtitle {{
            font-size: 1.15em;
            color: {metaColor};
            line-height: 1.45;
            margin: -6px 0 22px 0;
            font-weight: 400;
        }}
        .captioned-image-container, .image2-inset {{
            margin: 22px 0;
            width: 100%;
        }}
        a.image-link {{
            display: block;
            text-decoration: none !important;
        }}
        .image-caption {{
            font-size: 13px;
            color: {metaColor};
            text-align: center;
            margin-top: 8px;
            line-height: 1.4;
        }}
        .image-link-expand,
        button.restack-image,
        button.view-image,
        .subscription-widget-wrap,
        .subscription-widget-wrap-editor,
        .subscription-widget,
        .subscribe-widget,
        .post-ufi,
        .like-button-container,
        .fake-input-wrapper {{
            display: none !important;
        }}
        .pullquote {{
            margin: 28px 0;
            padding: 16px 22px;
            border-left: 4px solid #FF6719;
            background: {(isDark ? "rgba(255, 103, 25, 0.08)" : "rgba(255, 103, 25, 0.06)")};
            border-radius: 0 12px 12px 0;
            font-size: 1.1em;
            font-weight: 500;
            line-height: 1.55;
        }}
        .pullquote p:last-child {{
            margin-bottom: 0;
        }}
        .callout-block {{
            margin: 24px 0;
            padding: 18px 20px;
            background: {(isDark ? "rgba(255,255,255,0.06)" : "rgba(0,0,0,0.04)")};
            border: 1px solid {(isDark ? "rgba(255,255,255,0.12)" : "rgba(0,0,0,0.10)")};
            border-radius: 14px;
        }}
        .callout-block h4 {{
            margin-top: 0;
        }}
        .callout-block p:last-child {{
            margin-bottom: 0;
        }}
        .embedded-post-wrap, .embedded-post {{
            margin: 24px 0;
            padding: 16px 18px;
            background: {(isDark ? "rgba(255,255,255,0.05)" : "rgba(0,0,0,0.03)")};
            border: 1px solid {(isDark ? "rgba(255,255,255,0.12)" : "rgba(0,0,0,0.10)")};
            border-radius: 14px;
        }}
        img.embedded-post-publication-logo {{
            width: 24px;
            height: 24px;
            border-radius: 6px;
            display: inline-block;
            vertical-align: middle;
            margin: 0 8px 0 0;
        }}
        .button-wrapper {{
            text-align: center;
            margin: 24px 0;
        }}
        .button-wrapper a.button {{
            display: inline-block;
            padding: 10px 22px;
            border-radius: 999px;
            background: {(isDark ? "rgba(102, 178, 255, 0.16)" : "rgba(0, 102, 204, 0.10)")};
            border: 1px solid {(isDark ? "rgba(102, 178, 255, 0.35)" : "rgba(0, 102, 204, 0.30)")};
            color: {linkColor} !important;
            font-weight: 600;
            font-size: 0.92em;
            text-decoration: none !important;
        }}
        .footnote-anchor {{
            font-size: 0.75em;
            vertical-align: super;
            padding: 1px 6px;
            border-radius: 6px;
            background: {(isDark ? "rgba(102, 178, 255, 0.15)" : "rgba(0, 102, 204, 0.10)")};
            margin: 0 2px;
            text-decoration: none !important;
        }}
        .footnote {{
            font-size: 0.88em;
            color: {metaColor};
            border-top: 1px solid {(isDark ? "rgba(255,255,255,0.08)" : "rgba(0,0,0,0.08)")};
            padding-top: 12px;
            margin-top: 16px;
        }}
        .substack-paid-card {{
            border-color: rgba(255, 103, 25, 0.35);
            background: {(isDark ? "rgba(255, 103, 25, 0.08)" : "rgba(255, 103, 25, 0.05)")};
        }}
        .substack-paid-card .open-browser-btn {{
            background: rgba(255, 103, 25, 0.18);
            border-color: rgba(255, 103, 25, 0.45);
            color: #FF6719 !important;
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

    private bool IsAlreadySubscribedToFeedUrl(string? feedUrl)
    {
        if (string.IsNullOrWhiteSpace(feedUrl) || _rssService.Feeds == null) return false;
        string targetNorm = Daily.Services.RssFeedService.NormalizeSubscriptionUrl(feedUrl);
        return _rssService.Feeds.Any(f => Daily.Services.RssFeedService.NormalizeSubscriptionUrl(f.Url) == targetNorm);
    }

    private string? ResolveSubscribableFeedUrl(RssItem item, out string resolvedName, out string resolvedCategory)
    {
        resolvedName = item.PublicationName ?? "Feed";
        resolvedCategory = "Tech";

        if (IsItemSubstack(item))
        {
            var (slug, feedUrl) = ExtractSubstackInfo(item.Link, true);
            if (!string.IsNullOrEmpty(feedUrl))
            {
                string pubName = item.PublicationName ?? slug ?? "Substack";
                if (pubName == "Substack Inbox" || pubName == "Substack")
                {
                    pubName = slug ?? "Substack";
                }
                resolvedName = pubName;
                resolvedCategory = "Tech";
                return feedUrl;
            }
            return null;
        }

        if (!string.IsNullOrEmpty(item.Link) && item.Link.Contains("medium.com", StringComparison.OrdinalIgnoreCase))
        {
            try
            {
                var uri = new Uri(item.Link);
                foreach (var segment in uri.Segments)
                {
                    var cleanSegment = segment.Trim('/');
                    if (cleanSegment.StartsWith("@"))
                    {
                        resolvedName = !string.IsNullOrEmpty(item.Author) ? item.Author : cleanSegment;
                        resolvedCategory = "Coding";
                        return $"https://medium.com/feed/{cleanSegment}";
                    }
                }
            }
            catch { }
        }

        return null;
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

        if (ReaderSubscribeButton != null)
        {
            var targetItem = _currentRenderedArticle ?? _selectedItem;
            string? feedUrl = ResolveSubscribableFeedUrl(targetItem, out _, out _);
            if (!string.IsNullOrEmpty(feedUrl))
            {
                bool subscribed = IsAlreadySubscribedToFeedUrl(feedUrl);
                ReaderSubscribeButton.Visibility = Visibility.Visible;
                ReaderSubscribeButton.IsEnabled = !subscribed;
                ReaderSubscribeIcon.Glyph = subscribed ? "\uE73E" : "\uE710";
                ReaderSubscribeText.Text = subscribed ? "Subscribed" : "Subscribe";
            }
            else
            {
                ReaderSubscribeButton.Visibility = Visibility.Collapsed;
            }
        }
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

    private async void ReaderSubscribeButton_Click(object sender, RoutedEventArgs e)
    {
        var targetItem = _currentRenderedArticle ?? _selectedItem;
        if (targetItem == null) return;

        string? feedUrl = ResolveSubscribableFeedUrl(targetItem, out string pubName, out string category);
        if (string.IsNullOrEmpty(feedUrl) || IsAlreadySubscribedToFeedUrl(feedUrl)) return;

        ReaderSubscribeButton.IsEnabled = false;
        try
        {
            string userId = Daily_WinUI.App.SupabaseClient.Auth.CurrentSession?.User?.Id ?? "local_user";
            await _rssService.AddFeedAsync(feedUrl, pubName, category, userId, targetItem.PublicationIconUrl);
            UpdateReaderToolbarStates();
        }
        catch (Exception ex)
        {
            ReaderSubscribeButton.IsEnabled = true;
            var errorDialog = new ContentDialog
            {
                Title = "Subscription Failed",
                Content = $"Failed to subscribe to {pubName}: {ex.Message}",
                CloseButtonText = "OK",
                XamlRoot = this.XamlRoot
            };
            await errorDialog.ShowAsync();
        }
    }

    private async void SubscribeAuthorButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.DataContext is Daily_WinUI.ViewModels.RssItemViewModel vm)
        {
            btn.IsEnabled = false;
            try
            {
                if (vm.IsSubstackItem)
                {
                    var (slug, feedUrl) = ExtractSubstackInfo(vm.Link, true);
                    if (string.IsNullOrEmpty(feedUrl) || string.IsNullOrEmpty(slug))
                    {
                        throw new Exception("Could not resolve Substack publication from article URL.");
                    }

                    string pubName = vm.PublicationName ?? slug;
                    if (pubName == "Substack Inbox" || pubName == "Substack")
                    {
                        pubName = slug;
                    }
                    string userId = Daily_WinUI.App.SupabaseClient.Auth.CurrentSession?.User?.Id ?? "local_user";
                    await _rssService.AddFeedAsync(feedUrl, pubName, "Tech", userId, vm.PublicationIconUrl);
                    UpdateReaderToolbarStates();

                    var successDialog = new ContentDialog
                    {
                        Title = "Subscribed Successfully",
                        Content = $"You have subscribed to {pubName}'s Substack feed.",
                        CloseButtonText = "OK",
                        XamlRoot = this.XamlRoot
                    };
                    await successDialog.ShowAsync();
                    return;
                }

                var url = vm.Link;
                var uri = new Uri(url);
                string username = string.Empty;
                var segments = uri.Segments;
                foreach (var segment in segments)
                {
                    var cleanSegment = segment.Trim('/');
                    if (cleanSegment.StartsWith("@"))
                    {
                        username = cleanSegment;
                        break;
                    }
                }

                if (string.IsNullOrEmpty(username))
                {
                    throw new Exception("Could not resolve Medium username from article URL.");
                }

                string authorFeedUrl = $"https://medium.com/feed/{username}";
                string authorName = vm.Author ?? username;

                string userIdMedium = Daily_WinUI.App.SupabaseClient.Auth.CurrentSession?.User?.Id ?? "local_user";
                await _rssService.AddFeedAsync(authorFeedUrl, authorName, "Coding", userIdMedium);

                var mediumSuccessDialog = new ContentDialog
                {
                    Title = "Subscribed Successfully",
                    Content = $"You have subscribed to {authorName}'s Medium stories feed.",
                    CloseButtonText = "OK",
                    XamlRoot = this.XamlRoot
                };
                await mediumSuccessDialog.ShowAsync();
            }
            catch (Exception ex)
            {
                var errorDialog = new ContentDialog
                {
                    Title = "Subscription Failed",
                    Content = $"Failed to subscribe to author/publication feed: {ex.Message}",
                    CloseButtonText = "OK",
                    XamlRoot = this.XamlRoot
                };
                await errorDialog.ShowAsync();
            }
            finally
            {
                btn.IsEnabled = true;
            }
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

    private List<FeedSource> GetFeedsListWithAllNews()
    {
        var list = new List<FeedSource>();
        if (_rssService.Feeds != null)
        {
            list.AddRange(_rssService.Feeds);
        }

        var settings = SettingsService.Load();
        if (!string.IsNullOrEmpty(settings.MediumUsername))
        {
            list.Add(_mediumReadingListSource);
        }
        if (!string.IsNullOrEmpty(settings.SubstackUsername))
        {
            list.Add(_substackInboxSource);
        }

        list.Add(_allNewsFeedSource);
        return list;
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

            if (string.IsNullOrWhiteSpace(feed.IconUrl))
            {
                menuItem.Icon = new FontIcon 
                { 
                    Glyph = "\uEB19", 
                    FontFamily = (Microsoft.UI.Xaml.Media.FontFamily)Application.Current.Resources["TablerIconsFont"] 
                };
            }
            else
            {
                try
                {
                    var bitmap = new Microsoft.UI.Xaml.Media.Imaging.BitmapImage(new Uri(feed.IconUrl));
                    var icon = new ImageIcon { Source = bitmap };
                    menuItem.Icon = icon;

                    bitmap.ImageFailed += (imgSender, imgArgs) =>
                    {
                        menuItem.Icon = new FontIcon 
                        { 
                            Glyph = "\uEB19", 
                            FontFamily = (Microsoft.UI.Xaml.Media.FontFamily)Application.Current.Resources["TablerIconsFont"] 
                        };
                    };
                }
                catch
                {
                    menuItem.Icon = new FontIcon 
                    { 
                        Glyph = "\uEB19", 
                        FontFamily = (Microsoft.UI.Xaml.Media.FontFamily)Application.Current.Resources["TablerIconsFont"] 
                    };
                }
            }

            menuItem.Click += FeedMenuItem_Click;
            FeedMenuFlyout.Items.Add(menuItem);
        }

        // Add "Medium Reading List" right before "All News" if MediumUsername is configured
        var settings = SettingsService.Load();
        if (!string.IsNullOrEmpty(settings.MediumUsername))
        {
            var mediumMenuItem = new MenuFlyoutItem
            {
                Text = "Medium Reading List",
                DataContext = _mediumReadingListSource,
                Icon = new FontIcon 
                { 
                    Glyph = "\uEC70", // brand-medium
                    FontFamily = (Microsoft.UI.Xaml.Media.FontFamily)Application.Current.Resources["TablerIconsFont"] 
                }
            };
            mediumMenuItem.Click += FeedMenuItem_Click;
            FeedMenuFlyout.Items.Add(mediumMenuItem);
        }

        // Add "Substack Inbox" right before "All News" if SubstackUsername is configured
        if (!string.IsNullOrEmpty(settings.SubstackUsername))
        {
            var substackMenuItem = new MenuFlyoutItem
            {
                Text = "Substack Inbox",
                DataContext = _substackInboxSource,
                Icon = new FontIcon 
                { 
                    Glyph = "\uEB19",
                    FontFamily = (Microsoft.UI.Xaml.Media.FontFamily)Application.Current.Resources["TablerIconsFont"] 
                }
            };
            substackMenuItem.Click += FeedMenuItem_Click;
            FeedMenuFlyout.Items.Add(substackMenuItem);
        }

        // Add "All News" as the LAST entry always
        var allNewsMenuItem = new MenuFlyoutItem
        {
            Text = "All News",
            DataContext = _allNewsFeedSource,
            Icon = new FontIcon 
            { 
                Glyph = "\uEAFD", // brand-news / icon-news
                FontFamily = (Microsoft.UI.Xaml.Media.FontFamily)Application.Current.Resources["TablerIconsFont"] 
            }
        };
        allNewsMenuItem.Click += FeedMenuItem_Click;
        FeedMenuFlyout.Items.Add(allNewsMenuItem);
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
        var feeds = GetFeedsListWithAllNews();
        if (feeds == null || feeds.Count == 0) return;

        int currentIndex = 0;
        if (_currentLocalFeed != null)
        {
            currentIndex = feeds.FindIndex(f => f.Url == _currentLocalFeed.Url);
            if (currentIndex < 0) currentIndex = 0;
        }

        int prevIndex = (currentIndex - 1 + feeds.Count) % feeds.Count;
        var prevFeed = feeds[prevIndex];
        await SelectFeedAsync(prevFeed);
    }

    private async void CycleRightButton_Click(object sender, RoutedEventArgs e)
    {
        var feeds = GetFeedsListWithAllNews();
        if (feeds == null || feeds.Count == 0) return;

        int currentIndex = 0;
        if (_currentLocalFeed != null)
        {
            currentIndex = feeds.FindIndex(f => f.Url == _currentLocalFeed.Url);
            if (currentIndex < 0) currentIndex = 0;
        }

        int nextIndex = (currentIndex + 1) % feeds.Count;
        var nextFeed = feeds[nextIndex];
        await SelectFeedAsync(nextFeed);
    }

    private async Task SelectFeedAsync(FeedSource feed)
    {
        if (feed == null) return;

        if (ArticleSearchBox != null)
        {
            ArticleSearchBox.Text = string.Empty;
        }

        var previousFeed = _currentLocalFeed;
        UpdateSelectedFeedUI(feed);
        _currentLocalFeed = feed;

        if (feed.Url == "all_news")
        {
            await LoadAllNewsFeedAsync();
        }
        else if (feed.Url == "medium_reading_list")
        {
            await LoadMediumReadingListAsync();
        }
        else if (feed.Url == "substack_inbox")
        {
            await LoadSubstackInboxAsync();
        }
        else
        {
            if (previousFeed == null || feed.Url != previousFeed.Url)
            {
                LoadingPanel.Visibility = Visibility.Visible;
                ArticlesListView.Visibility = Visibility.Collapsed;
                _rssService.SelectFeed(feed);
                await _rssService.LoadFeedAsync(feed);
            }
            else
            {
                UpdateArticles();
            }
        }
    }

    private void UpdateSelectedFeedUI(FeedSource? feed)
    {
        if (feed == null)
        {
            SelectedFeedText.Text = "Select Feed";
            if (SelectedFeedIconBorder != null) SelectedFeedIconBorder.Visibility = Visibility.Collapsed;
            if (SelectedFeedFontIcon != null) SelectedFeedFontIcon.Visibility = Visibility.Collapsed;
            return;
        }

        SelectedFeedText.Text = feed.Name;
        if (feed.Url == "all_news")
        {
            if (SelectedFeedIconBorder != null) SelectedFeedIconBorder.Visibility = Visibility.Collapsed;
            if (SelectedFeedFontIcon != null)
            {
                SelectedFeedFontIcon.Glyph = "\uEAFD";
                SelectedFeedFontIcon.FontFamily = (Microsoft.UI.Xaml.Media.FontFamily)Application.Current.Resources["TablerIconsFont"];
                SelectedFeedFontIcon.Visibility = Visibility.Visible;
            }
        }
        else if (feed.Url == "medium_reading_list")
        {
            if (SelectedFeedIconBorder != null) SelectedFeedIconBorder.Visibility = Visibility.Collapsed;
            if (SelectedFeedFontIcon != null)
            {
                SelectedFeedFontIcon.Glyph = "\uEC70";
                SelectedFeedFontIcon.FontFamily = (Microsoft.UI.Xaml.Media.FontFamily)Application.Current.Resources["TablerIconsFont"];
                SelectedFeedFontIcon.Visibility = Visibility.Visible;
            }
        }
        else
        {
            if (string.IsNullOrWhiteSpace(feed.IconUrl))
            {
                if (SelectedFeedIconBorder != null) SelectedFeedIconBorder.Visibility = Visibility.Collapsed;
                if (SelectedFeedFontIcon != null)
                {
                    SelectedFeedFontIcon.Glyph = "\uEB19";
                    SelectedFeedFontIcon.FontFamily = (Microsoft.UI.Xaml.Media.FontFamily)Application.Current.Resources["TablerIconsFont"];
                    SelectedFeedFontIcon.Visibility = Visibility.Visible;
                }
            }
            else
            {
                if (SelectedFeedFontIcon != null) SelectedFeedFontIcon.Visibility = Visibility.Collapsed;
                if (SelectedFeedIconBorder != null) SelectedFeedIconBorder.Visibility = Visibility.Visible;
                try
                {
                    SelectedFeedIcon.Source = new Microsoft.UI.Xaml.Media.Imaging.BitmapImage(new Uri(feed.IconUrl));
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine($"[RssFeedDetailPage] Error loading icon: {ex.Message}");
                    SelectedFeedIcon.Source = null;
                    if (SelectedFeedIconBorder != null) SelectedFeedIconBorder.Visibility = Visibility.Collapsed;
                    if (SelectedFeedFontIcon != null)
                    {
                        SelectedFeedFontIcon.Glyph = "\uEB19";
                        SelectedFeedFontIcon.FontFamily = (Microsoft.UI.Xaml.Media.FontFamily)Application.Current.Resources["TablerIconsFont"];
                        SelectedFeedFontIcon.Visibility = Visibility.Visible;
                    }
                }
            }
        }
    }

    private void SelectedFeedIcon_ImageFailed(object sender, ExceptionRoutedEventArgs e)
    {
        if (SelectedFeedIconBorder != null) SelectedFeedIconBorder.Visibility = Visibility.Collapsed;
        if (SelectedFeedFontIcon != null)
        {
            SelectedFeedFontIcon.Glyph = "\uEB19";
            SelectedFeedFontIcon.FontFamily = (Microsoft.UI.Xaml.Media.FontFamily)Application.Current.Resources["TablerIconsFont"];
            SelectedFeedFontIcon.Visibility = Visibility.Visible;
        }
    }

    private void Page_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        double width = e.NewSize.Width;

        // Hide description text and search box sooner to avoid collision
        if (RssSubtitleTextBlock != null)
        {
            RssSubtitleTextBlock.Visibility = width < 880 ? Visibility.Collapsed : Visibility.Visible;
        }

        if (ArticleSearchBox != null)
        {
            ArticleSearchBox.Visibility = width < 880 ? Visibility.Collapsed : Visibility.Visible;
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

    private static bool IsMediumTeaser(string? content)
    {
        if (string.IsNullOrWhiteSpace(content)) return true;
        if (content.Contains("Continue reading on", StringComparison.OrdinalIgnoreCase) ||
            content.Contains("medium-feed-link", StringComparison.OrdinalIgnoreCase) ||
            content.Contains("medium-feed-item", StringComparison.OrdinalIgnoreCase) ||
            content.Contains("medium-feed-snippet", StringComparison.OrdinalIgnoreCase) ||
            content.Contains("member-only", StringComparison.OrdinalIgnoreCase) ||
            content.Contains("made this story available to Medium members", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }
        return false;
    }

    private static readonly System.Net.Http.HttpClient _substackApiClient = CreateSubstackApiClient();

    private static System.Net.Http.HttpClient CreateSubstackApiClient()
    {
        var client = new System.Net.Http.HttpClient { Timeout = TimeSpan.FromSeconds(10) };
        client.DefaultRequestHeaders.TryAddWithoutValidation("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36");
        client.DefaultRequestHeaders.TryAddWithoutValidation("Accept", "application/json");
        return client;
    }

    public static bool IsItemSubstack(RssItem? item)
    {
        if (item == null) return false;
        if (item.PublicationName != null && item.PublicationName.Contains("Substack", StringComparison.OrdinalIgnoreCase)) return true;
        if (!string.IsNullOrEmpty(item.Link) && item.Link.Contains("substack.com", StringComparison.OrdinalIgnoreCase)) return true;
        if (!string.IsNullOrEmpty(item.ImageUrl) &&
            (item.ImageUrl.Contains("substackcdn.com", StringComparison.OrdinalIgnoreCase) ||
             item.ImageUrl.Contains("substack-post-media", StringComparison.OrdinalIgnoreCase))) return true;
        if (!string.IsNullOrEmpty(item.PublicationIconUrl) &&
            (item.PublicationIconUrl.Contains("substackcdn.com", StringComparison.OrdinalIgnoreCase) ||
             item.PublicationIconUrl.Contains("substack-post-media", StringComparison.OrdinalIgnoreCase) ||
             item.PublicationIconUrl.Contains("substack.com", StringComparison.OrdinalIgnoreCase))) return true;
        if (!string.IsNullOrEmpty(item.Content) &&
            (item.Content.Contains("substackcdn.com", StringComparison.OrdinalIgnoreCase) ||
             item.Content.Contains("substack-post-media", StringComparison.OrdinalIgnoreCase) ||
             item.Content.Contains("captioned-image-container", StringComparison.OrdinalIgnoreCase))) return true;
        return false;
    }

    private static bool IsSubstackTeaser(string? content)
    {
        if (string.IsNullOrWhiteSpace(content)) return true;
        if (content.Contains("class=\"paywall\"", StringComparison.OrdinalIgnoreCase) ||
            content.Contains("data-component-name=\"paywall\"", StringComparison.OrdinalIgnoreCase) ||
            content.Contains("this post is for paid subscribers", StringComparison.OrdinalIgnoreCase) ||
            content.Contains("this post is for subscribers", StringComparison.OrdinalIgnoreCase) ||
            content.Contains("subscribe to continue reading", StringComparison.OrdinalIgnoreCase) ||
            content.Contains("keep reading with a", StringComparison.OrdinalIgnoreCase) ||
            content.Contains("subscribe to unlock", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }
        if (content.Contains("read more", StringComparison.OrdinalIgnoreCase) &&
            (content.Contains("substack.com/p/", StringComparison.OrdinalIgnoreCase) ||
             content.Contains("paywall", StringComparison.OrdinalIgnoreCase) ||
             content.Length < 2500))
        {
            return true;
        }
        return false;
    }

    private static bool HasSubstackBonusPaywall(string? content)
    {
        return !string.IsNullOrEmpty(content) &&
               content.Contains("this post has bonus content for paid subscribers", StringComparison.OrdinalIgnoreCase);
    }

    public static string StripSubstackTrackingAndNoise(string html)
    {
        if (string.IsNullOrEmpty(html)) return html;
        var clean = html;

        // 1. Remove 1x1 Substack email open tracking pixels
        clean = Regex.Replace(clean, @"<img[^>]+(?:substack\.com/o/|eotrx\.substackcdn\.com)[^>]*>", "", RegexOptions.IgnoreCase);

        // 2. Remove Pencraft image action overlay toolbars (Restack / Maximize buttons & SVGs on every image)
        clean = Regex.Replace(clean, @"<div[^>]*class=""[^""]*image-link-expand[^""]*""[^>]*>[\s\S]*?</div>\s*</div>", "", RegexOptions.IgnoreCase);
        clean = Regex.Replace(clean, @"<button[^>]*class=""[^""]*(?:restack-image|view-image|icon-container|buttonBase)[^""]*""[^>]*>[\s\S]*?</button>", "", RegexOptions.IgnoreCase);

        // 3. Unwrap <picture> and strip low-res <source srcset> so crisp <img src> is always used
        clean = Regex.Replace(clean, @"<source[^>]+(?:substackcdn\.com|substack-post-media)[^>]*>", "", RegexOptions.IgnoreCase);
        clean = Regex.Replace(clean, @"</?picture[^>]*>", "", RegexOptions.IgnoreCase);
        clean = Regex.Replace(clean, @"(<img[^>]+(?:substackcdn\.com|substack-post-media)[^>]*?)\s+srcset=""[^""]*""", "$1", RegexOptions.IgnoreCase);

        // 4. Remove nested inline subscription forms & upgrade widgets completely
        clean = Regex.Replace(clean, @"<div[^>]*class=""[^""]*subscription-widget-wrap[^""]*""[^>]*>[\s\S]*?</form>\s*</div>\s*</div>", "", RegexOptions.IgnoreCase);
        clean = Regex.Replace(clean, @"<div[^>]*class=""[^""]*subscription-widget[^""]*""[^>]*>[\s\S]*?</form>\s*</div>", "", RegexOptions.IgnoreCase);
        clean = Regex.Replace(clean, @"<form[^>]*class=""[^""]*subscription-widget[^""]*""[^>]*>[\s\S]*?</form>", "", RegexOptions.IgnoreCase);
        clean = Regex.Replace(clean, @"<div[^>]*class=""[^""]*fake-input-wrapper[^""]*""[^>]*>[\s\S]*?</div>\s*</div>", "", RegexOptions.IgnoreCase);
        clean = Regex.Replace(clean, @"<div[^>]*class=""[^""]*(?:subscription-widget-wrap|subscribe-widget|post-ufi|post-footer|like-button-container|share-dialog|comment-widget)[^""]*""[\s\S]*?</div>", "", RegexOptions.IgnoreCase);

        // 5. Remove inline Subscribe / Share CTA buttons while keeping legitimate external link buttons intact
        clean = Regex.Replace(clean, @"<(?:p|div)[^>]*class=""[^""]*button-wrapper[^""]*""[^>]*>\s*<a[^>]*href=""[^""]*(?:/subscribe|action=share|utm_source=substack)[^""]*""[^>]*>[\s\S]*?</a>\s*</(?:p|div)>", "", RegexOptions.IgnoreCase);

        // 6. Upgrade narrow Substack CDN image widths inside HTML
        clean = Regex.Replace(clean, @"(https://substackcdn\.com/image/fetch/[^""'\s>]*?)w_(?:1\d\d|2\d\d|3\d\d|4\d\d|5\d\d|6\d\d|7\d\d|8\d\d)\b", "$1w_1200", RegexOptions.IgnoreCase);

        return clean;
    }

    private static string NormalizeSubstackAssetKey(string? url)
    {
        if (string.IsNullOrWhiteSpace(url)) return "";
        string decoded = Uri.UnescapeDataString(url);
        if (decoded.Contains("substack-post-media", StringComparison.OrdinalIgnoreCase) ||
            decoded.Contains("substackcdn.com", StringComparison.OrdinalIgnoreCase) ||
            decoded.Contains("bucketeer-", StringComparison.OrdinalIgnoreCase))
        {
            string noQuery = decoded.Split('?')[0];
            string lastSeg = noQuery.TrimEnd('/').Split('/').LastOrDefault() ?? "";
            if (lastSeg.Length > 12) return lastSeg.ToLowerInvariant();
        }
        return System.Net.WebUtility.HtmlDecode(url).Split('?')[0].Trim().ToLowerInvariant();
    }

    public static string DeduplicateSubstackFeaturedImage(string content, string? featuredImage)
    {
        if (string.IsNullOrEmpty(content) || string.IsNullOrEmpty(featuredImage)) return content;
        var imgMatch = Regex.Match(content, @"<img[^>]+src\s*=\s*[""']([^""']+)[""'][^>]*>", RegexOptions.IgnoreCase);
        if (!imgMatch.Success) return content;

        string s1 = NormalizeSubstackAssetKey(imgMatch.Groups[1].Value);
        string s2 = NormalizeSubstackAssetKey(featuredImage);
        if (string.IsNullOrEmpty(s1) || string.IsNullOrEmpty(s2)) return content;

        if (s1.Contains(s2, StringComparison.OrdinalIgnoreCase) || s2.Contains(s1, StringComparison.OrdinalIgnoreCase))
        {
            string modified = content.Remove(imgMatch.Index, imgMatch.Length);
            modified = Regex.Replace(modified, @"<a[^>]*class=[""'][^""']*image-link[^""']*[""'][^>]*>\s*(?:<div[^>]*>\s*</div>\s*)?</a>", "", RegexOptions.IgnoreCase);
            for (int i = 0; i < 2; i++)
            {
                modified = Regex.Replace(modified, @"<(?:figure|div|p)[^>]*>\s*</(?:figure|div|p)>", "", RegexOptions.IgnoreCase);
            }
            return modified.Trim();
        }
        return content;
    }

    public static (string? slug, string? feedUrl) ExtractSubstackInfo(string? urlString, bool isKnownSubstack = false)
    {
        if (string.IsNullOrWhiteSpace(urlString)) return (null, null);
        try
        {
            var uri = new Uri(urlString);
            var host = uri.Host.ToLowerInvariant();
            if (host.StartsWith("www.")) host = host.Substring(4);
            var segments = uri.AbsolutePath.Split('/', StringSplitOptions.RemoveEmptyEntries);

            if (host == "open.substack.com")
            {
                if (segments.Length >= 2 && segments[0].Equals("pub", StringComparison.OrdinalIgnoreCase))
                {
                    var pubSlug = segments[1].ToLowerInvariant();
                    return (pubSlug, $"https://{pubSlug}.substack.com/feed");
                }
                return (null, null);
            }

            if (host.EndsWith(".substack.com", StringComparison.OrdinalIgnoreCase) &&
                host != "substack.com" && host != "substackcdn.com")
            {
                var slug = host.Substring(0, host.Length - ".substack.com".Length);
                if (slug != "api" && slug != "open" && slug != "eotrx")
                {
                    return (slug, $"https://{slug}.substack.com/feed");
                }
                return (null, null);
            }

            if (host == "substack.com")
            {
                if (segments.Length > 0 && segments[0].StartsWith("@"))
                {
                    var handle = segments[0].TrimStart('@').ToLowerInvariant();
                    if (!string.IsNullOrEmpty(handle))
                    {
                        return (handle, $"https://{handle}.substack.com/feed");
                    }
                }
                if (segments.Length >= 2 && segments[0].Equals("profile", StringComparison.OrdinalIgnoreCase))
                {
                    return null == segments[1] ? (null, null) : (null, null); // numeric profile requires API lookup
                }
                // Never return https://substack.com/feed (invalid root feed)
                return (null, null);
            }

            // Custom-domain Substack publication (e.g. newsletter.pragmaticengineer.com/p/...)
            if (isKnownSubstack || (segments.Length >= 2 && segments[0].Equals("p", StringComparison.OrdinalIgnoreCase)))
            {
                if (!host.Contains("medium.com"))
                {
                    return (host, $"https://{host}/feed");
                }
            }
        }
        catch { }
        return (null, null);
    }

    internal static async Task<string> ExecuteAsyncScriptOnWebViewAsync(Microsoft.Web.WebView2.Core.CoreWebView2 core, string asyncFunctionJs, int timeoutMs = 8000)
    {
        string slot = "__dailyAsync_" + Guid.NewGuid().ToString("N");
        string startJs = $"window['{slot}'] = {{ done: false, val: '' }}; ({asyncFunctionJs})().then(function(v) {{ window['{slot}'] = {{ done: true, val: (typeof v === 'string' ? v : JSON.stringify(v || '')) }}; }}).catch(function() {{ window['{slot}'] = {{ done: true, val: '' }}; }}); true;";
        await core.ExecuteScriptAsync(startJs);

        int elapsed = 0;
        while (elapsed < timeoutMs)
        {
            await Task.Delay(140);
            elapsed += 140;
            var pollRaw = await core.ExecuteScriptAsync($"window['{slot}'] ? JSON.stringify(window['{slot}']) : null");
            if (!string.IsNullOrEmpty(pollRaw) && pollRaw != "null")
            {
                string? unescaped = System.Text.Json.JsonSerializer.Deserialize<string>(pollRaw);
                if (!string.IsNullOrEmpty(unescaped))
                {
                    using var doc = System.Text.Json.JsonDocument.Parse(unescaped);
                    if (doc.RootElement.TryGetProperty("done", out var doneProp) && doneProp.GetBoolean())
                    {
                        try { await core.ExecuteScriptAsync($"delete window['{slot}'];"); } catch { }
                        return doc.RootElement.TryGetProperty("val", out var valProp) ? (valProp.GetString() ?? "") : "";
                    }
                }
            }
        }
        try { await core.ExecuteScriptAsync($"delete window['{slot}'];"); } catch { }
        return "";
    }

    private async Task EnsureSubstackOriginOnBackgroundWebViewAsync()
    {
        await EnsureWebViewInitializedAsync();
        if (BackgroundWebView.CoreWebView2 == null) return;

        string currentSrc = BackgroundWebView.CoreWebView2.Source ?? "";
        if (Uri.TryCreate(currentSrc, UriKind.Absolute, out var curUri) &&
            curUri.Host.Equals("substack.com", StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        var navTcs = new TaskCompletionSource<bool>();
        Windows.Foundation.TypedEventHandler<Microsoft.Web.WebView2.Core.CoreWebView2, Microsoft.Web.WebView2.Core.CoreWebView2NavigationCompletedEventArgs>? handler = null;
        handler = (s, e) =>
        {
            BackgroundWebView.CoreWebView2.NavigationCompleted -= handler;
            navTcs.TrySetResult(e.IsSuccess);
        };
        BackgroundWebView.CoreWebView2.NavigationCompleted += handler;
        BackgroundWebView.Source = new Uri("https://substack.com/404");

        var finished = await Task.WhenAny(navTcs.Task, Task.Delay(8000));
        if (finished != navTcs.Task)
        {
            BackgroundWebView.CoreWebView2.NavigationCompleted -= handler;
        }
    }

    private async Task<bool> HasAuthenticatedSubstackCookieAsync()
    {
        try
        {
            await EnsureWebViewInitializedAsync();
            if (BackgroundWebView.CoreWebView2 == null) return false;
            var cookies = await BackgroundWebView.CoreWebView2.CookieManager.GetCookiesAsync("https://substack.com");
            return cookies.Any(c => (c.Name == "substack.sid" || c.Name == "connect.sid") && !string.IsNullOrWhiteSpace(c.Value));
        }
        catch
        {
            return false;
        }
    }

    private static DateTime ParseSubstackDate(string? raw)
    {
        if (!string.IsNullOrWhiteSpace(raw) &&
            DateTimeOffset.TryParse(raw, System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.RoundtripKind, out var dto))
        {
            return dto.LocalDateTime;
        }
        return DateTime.Now;
    }

    private async Task<RssItem?> ExtractSubstackArticleAsync(RssItem baseItem)
    {
        if (string.IsNullOrWhiteSpace(baseItem.Link)) return null;
        string urlStr = baseItem.Link.Trim();
        if (urlStr.StartsWith("http://", StringComparison.OrdinalIgnoreCase))
            urlStr = "https://" + urlStr.Substring(7);
        if (!Uri.TryCreate(urlStr, UriKind.Absolute, out var uri)) return null;

        bool hasAuth = await HasAuthenticatedSubstackCookieAsync();

        string? directPostId = null;
        var pidMatch = Regex.Match(urlStr, @"/p-(\d+)");
        if (pidMatch.Success) directPostId = pidMatch.Groups[1].Value;

        string? apiHost = null;
        string? postSlug = null;
        var pathParts = uri.AbsolutePath.Split('/', StringSplitOptions.RemoveEmptyEntries);
        int pIdx = Array.FindIndex(pathParts, s => s.Equals("p", StringComparison.OrdinalIgnoreCase));
        if (pIdx >= 0 && pIdx + 1 < pathParts.Length)
        {
            postSlug = pathParts[pIdx + 1];
            if (uri.Host.Equals("open.substack.com", StringComparison.OrdinalIgnoreCase) &&
                pathParts.Length >= 2 && pathParts[0].Equals("pub", StringComparison.OrdinalIgnoreCase))
            {
                apiHost = $"{pathParts[1]}.substack.com";
            }
            else
            {
                apiHost = uri.Host;
            }
        }

        (RssItem? article, bool needsUpgrade) BuildFromApiJson(string rawJson)
        {
            var root = System.Text.Json.Nodes.JsonNode.Parse(rawJson);
            if (root == null) return (null, false);
            var post = root["post"] ?? root;
            var pub = root["publication"];
            string? bodyHtml = post["body_html"]?.ToString();
            if (string.IsNullOrEmpty(bodyHtml)) return (null, false);

            string? pid = post["id"]?.ToString();
            if (string.IsNullOrEmpty(directPostId) && !string.IsNullOrEmpty(pid))
            {
                directPostId = pid;
            }

            string audience = post["audience"]?.ToString() ?? "everyone";
            bool isTeaser = IsSubstackTeaser(bodyHtml) || bodyHtml.Length < 250;
            bool needsBonus = HasSubstackBonusPaywall(bodyHtml);
            bool upgrade = hasAuth && (audience == "only_paid" || isTeaser || needsBonus);

            string title = post["title"]?.ToString() ?? baseItem.Title ?? "Substack Post";
            string subtitle = (post["subtitle"]?.ToString() ?? "").Trim();
            string canonicalUrl = post["canonical_url"]?.ToString() ?? baseItem.Link;
            string? rawCover = post["cover_image"]?.ToString() ?? baseItem.ImageUrl;
            string? coverImg = !string.IsNullOrEmpty(rawCover) ? Daily.Services.RssFeedService.OptimizeSubstackImageUrl(rawCover) : null;
            DateTime pubDate = post["post_date"] != null ? ParseSubstackDate(post["post_date"]?.ToString()) : baseItem.PublishDate;

            string? author = baseItem.Author;
            if (post["publishedBylines"] is System.Text.Json.Nodes.JsonArray bylines && bylines.Count > 0)
            {
                var names = bylines.Select(b => b?["name"]?.ToString()).Where(n => !string.IsNullOrWhiteSpace(n)).ToList();
                if (names.Count > 0) author = string.Join(", ", names);
            }

            string? pubName = pub?["name"]?.ToString() ?? baseItem.PublicationName;
            string? pubIcon = pub?["logo_url"]?.ToString() ?? baseItem.PublicationIconUrl;
            if ((string.IsNullOrEmpty(pubName) || pubName == "Substack" || pubName == "Substack Inbox") &&
                post["publishedBylines"] is System.Text.Json.Nodes.JsonArray bylines2 &&
                bylines2.FirstOrDefault()?["publicationUsers"] is System.Text.Json.Nodes.JsonArray pubUsers)
            {
                var firstPub = pubUsers.FirstOrDefault()?["publication"];
                if (firstPub != null)
                {
                    pubName = firstPub["name"]?.ToString() ?? pubName;
                    pubIcon = firstPub["logo_url"]?.ToString() ?? pubIcon;
                }
            }

            bodyHtml = StripSubstackTrackingAndNoise(bodyHtml);
            if (!string.IsNullOrEmpty(coverImg))
            {
                bodyHtml = DeduplicateSubstackFeaturedImage(bodyHtml, coverImg);
            }

            if (!string.IsNullOrEmpty(subtitle) && !bodyHtml.Contains(subtitle, StringComparison.OrdinalIgnoreCase))
            {
                string escapedSub = System.Net.WebUtility.HtmlEncode(subtitle);
                bodyHtml = $"<p class=\"substack-subtitle\">{escapedSub}</p>\n" + bodyHtml;
            }

            if (audience == "only_paid" && (bodyHtml.Length < 700 || IsSubstackTeaser(bodyHtml)))
            {
                string displayPub = System.Net.WebUtility.HtmlEncode(pubName ?? "this publication");
                bodyHtml += $@"
                <div class=""paywall-card substack-paid-card"">
                    <div class=""paywall-icon"">&#x1F512;</div>
                    <h3>Substack Paid Story</h3>
                    <p>This post is exclusive to paid subscribers of {displayPub}.</p>
                    <a href=""{canonicalUrl}"" class=""open-browser-btn"">Unlock on Substack</a>
                </div>";
            }

            return (new RssItem
            {
                Title = System.Net.WebUtility.HtmlDecode(title),
                Link = canonicalUrl,
                Content = bodyHtml,
                Description = !string.IsNullOrEmpty(subtitle) ? subtitle : baseItem.Description,
                Author = author,
                PublishDate = pubDate,
                PublicationName = pubName,
                PublicationIconUrl = pubIcon,
                ImageUrl = coverImg
            }, upgrade);
        }

        // Step 1: Fast public post JSON lookup (/api/v1/posts/{slug})
        RssItem? publicCandidate = null;
        if (string.IsNullOrEmpty(directPostId) && !string.IsNullOrEmpty(apiHost) && !string.IsNullOrEmpty(postSlug))
        {
            try
            {
                var raw = await _substackApiClient.GetStringAsync($"https://{apiHost}/api/v1/posts/{postSlug}");
                var (built, needsUpgrade) = BuildFromApiJson(raw);
                if (built != null)
                {
                    if (!needsUpgrade && !string.IsNullOrEmpty(built.Content) && built.Content.Length > 200)
                    {
                        return built;
                    }
                    publicCandidate = built;
                }
            }
            catch { }
        }

        // Step 2: Same-origin authenticated /api/v1/posts/by-id/{id} via BackgroundWebView on substack.com
        if (!string.IsNullOrEmpty(directPostId))
        {
            if (hasAuth)
            {
                try
                {
                    await EnsureSubstackOriginOnBackgroundWebViewAsync();
                    if (BackgroundWebView.CoreWebView2 != null)
                    {
                        string fetchPostJs = $@"async function() {{
                            try {{
                                const res = await fetch('https://substack.com/api/v1/posts/by-id/{directPostId}', {{
                                    credentials: 'include',
                                    headers: {{ 'Accept': 'application/json' }}
                                }});
                                if (!res.ok) return '';
                                return await res.text();
                            }} catch (e) {{
                                return '';
                            }}
                        }}";
                        string authRaw = await ExecuteAsyncScriptOnWebViewAsync(BackgroundWebView.CoreWebView2, fetchPostJs);
                        if (!string.IsNullOrEmpty(authRaw))
                        {
                            var (built, _) = BuildFromApiJson(authRaw);
                            if (built != null && !string.IsNullOrEmpty(built.Content) && built.Content.Length > 100)
                            {
                                return built;
                            }
                        }
                    }
                }
                catch { }
            }
            else
            {
                try
                {
                    var raw = await _substackApiClient.GetStringAsync($"https://substack.com/api/v1/posts/by-id/{directPostId}");
                    var (built, _) = BuildFromApiJson(raw);
                    if (built != null && !string.IsNullOrEmpty(built.Content) && built.Content.Length > 100)
                    {
                        return built;
                    }
                }
                catch { }
            }
        }

        if (publicCandidate != null && !string.IsNullOrEmpty(publicCandidate.Content) && publicCandidate.Content.Length > 200)
        {
            return publicCandidate;
        }

        // Step 3: Clean DOM fallback targeting ONLY .body.markup / .available-content
        try
        {
            await EnsureWebViewInitializedAsync();
            if (BackgroundWebView.CoreWebView2 != null)
            {
                var navTcs = new TaskCompletionSource<bool>();
                Windows.Foundation.TypedEventHandler<Microsoft.Web.WebView2.Core.CoreWebView2, Microsoft.Web.WebView2.Core.CoreWebView2NavigationCompletedEventArgs>? handler = null;
                handler = (s, e) =>
                {
                    BackgroundWebView.CoreWebView2.NavigationCompleted -= handler;
                    navTcs.TrySetResult(e.IsSuccess);
                };
                BackgroundWebView.CoreWebView2.NavigationCompleted += handler;
                BackgroundWebView.Source = uri;
                var done = await Task.WhenAny(navTcs.Task, Task.Delay(10000));
                if (done != navTcs.Task) BackgroundWebView.CoreWebView2.NavigationCompleted -= handler;
                await Task.Delay(900);

                string domBodyJs = @"(function() {
                    var junk = document.querySelectorAll('.subscription-widget-wrap, .subscription-widget-wrap-editor, .subscribe-widget, .post-ufi, .post-footer, .like-button-container, .share-dialog, .comment-widget, .comments-page, .image-link-expand, button.restack-image, button.view-image');
                    junk.forEach(function(el) { el.remove(); });
                    var bodyMarkup = document.querySelector('.body.markup, .available-content, [data-testid=""post-body""]');
                    if (bodyMarkup && (bodyMarkup.innerText || '').trim().length > 120) {
                        return bodyMarkup.innerHTML;
                    }
                    return null;
                })()";
                var domRaw = await BackgroundWebView.ExecuteScriptAsync(domBodyJs);
                if (!string.IsNullOrEmpty(domRaw) && domRaw != "null")
                {
                    string? htmlBody = System.Text.Json.JsonSerializer.Deserialize<string>(domRaw);
                    if (!string.IsNullOrEmpty(htmlBody) && htmlBody.Length > 120)
                    {
                        htmlBody = StripSubstackTrackingAndNoise(htmlBody);
                        if (!string.IsNullOrEmpty(baseItem.ImageUrl))
                        {
                            htmlBody = DeduplicateSubstackFeaturedImage(htmlBody, baseItem.ImageUrl);
                        }
                        return new RssItem
                        {
                            Title = baseItem.Title,
                            Link = baseItem.Link,
                            Content = htmlBody,
                            Description = baseItem.Description,
                            Author = baseItem.Author,
                            PublishDate = baseItem.PublishDate,
                            PublicationName = baseItem.PublicationName,
                            PublicationIconUrl = baseItem.PublicationIconUrl,
                            ImageUrl = baseItem.ImageUrl
                        };
                    }
                }
            }
        }
        catch { }

        return publicCandidate;
    }

    private static readonly Dictionary<string, List<RssItem>> _allFeedsCache = new();
    private static bool _isPreFetchingAllFeeds = false;

    private void PreFetchAllFeedsInBackground()
    {
        if (_isPreFetchingAllFeeds || _rssService.Feeds == null) return;
        _isPreFetchingAllFeeds = true;

        foreach (var feed in _rssService.Feeds)
        {
            // Skip the current feed since it is already loaded or loading in the main page
            if (_rssService.CurrentFeed != null && feed.Url == _rssService.CurrentFeed.Url)
                continue;

            lock (_allFeedsCache)
            {
                if (_allFeedsCache.ContainsKey(feed.Url))
                    continue;
            }

            _ = Task.Run(async () =>
            {
                try
                {
                    var items = await _rssService.FetchFeedItemsAsync(feed);
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

    private async Task LoadAllNewsFeedAsync(bool forceRefresh = false)
    {
        LoadingPanel.Visibility = Visibility.Visible;
        ArticlesListView.Visibility = Visibility.Collapsed;

        var feeds = _rssService.Feeds;
        if (feeds == null || feeds.Count == 0)
        {
            LoadingPanel.Visibility = Visibility.Collapsed;
            ArticlesListView.Visibility = Visibility.Visible;
            _articles.Clear();
            return;
        }

        try
        {
            var tasks = feeds.Select(async feed =>
            {
                List<RssItem>? items = null;
                if (!forceRefresh)
                {
                    lock (_allFeedsCache)
                    {
                        _allFeedsCache.TryGetValue(feed.Url, out items);
                    }
                }

                if (items == null || items.Count == 0)
                {
                    try
                    {
                        items = await _rssService.FetchFeedItemsAsync(feed);
                        lock (_allFeedsCache)
                        {
                            _allFeedsCache[feed.Url] = items;
                        }
                    }
                    catch (Exception ex)
                    {
                        System.Diagnostics.Debug.WriteLine($"[RssFeedDetailPage] Error fetching {feed.Name}: {ex.Message}");
                        items = new List<RssItem>();
                    }
                }
                return new { Feed = feed, Items = items };
            }).ToList();

            await Task.WhenAll(tasks);

            // Populate from cache in selector order
            var displayItems = new List<RssItem>();
            foreach (var feed in feeds)
            {
                List<RssItem>? items = null;
                lock (_allFeedsCache)
                {
                    _allFeedsCache.TryGetValue(feed.Url, out items);
                }
                if (items != null)
                {
                    var sorted = items.OrderByDescending(i => i.PublishDate).ToList();
                    displayItems.AddRange(sorted.Take(2));
                }
            }

            // Only update UI if we are still on the "All News" feed!
            if (_currentLocalFeed != null && _currentLocalFeed.Url == "all_news")
            {
                string query = ArticleSearchBox.Text.Trim();
                if (string.IsNullOrEmpty(query))
                {
                    _articles.Clear();
                    foreach (var item in displayItems)
                    {
                        _articles.Add(new Daily_WinUI.ViewModels.RssItemViewModel(item));
                    }
                    LoadingPanel.Visibility = Visibility.Collapsed;
                    ArticlesListView.Visibility = Visibility.Visible;
                }
                else
                {
                    FilterArticles(query);
                }
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[RssFeedDetailPage] Error loading All News: {ex.Message}");
        }
        finally
        {
            if (_currentLocalFeed != null && _currentLocalFeed.Url == "all_news")
            {
                LoadingPanel.Visibility = Visibility.Collapsed;
                ArticlesListView.Visibility = Visibility.Visible;
            }
        }
    }

    private void FilterArticles(string query)
    {
        if (string.IsNullOrWhiteSpace(query))
        {
            if (_currentLocalFeed != null && _currentLocalFeed.Url == "all_news")
            {
                var displayItems = new List<RssItem>();
                if (_rssService.Feeds != null)
                {
                    foreach (var feed in _rssService.Feeds)
                    {
                        List<RssItem>? items = null;
                        lock (_allFeedsCache)
                        {
                            _allFeedsCache.TryGetValue(feed.Url, out items);
                        }
                        if (items != null)
                        {
                            var sorted = items.OrderByDescending(i => i.PublishDate).ToList();
                            displayItems.AddRange(sorted.Take(2));
                        }
                    }
                }
                _articles.Clear();
                foreach (var item in displayItems)
                {
                    _articles.Add(new Daily_WinUI.ViewModels.RssItemViewModel(item));
                }
            }
            else
            {
                _articles.Clear();
                foreach (var item in _rssService.Items)
                {
                    _articles.Add(new Daily_WinUI.ViewModels.RssItemViewModel(item));
                }
            }
            return;
        }

        var lowerQuery = query.ToLowerInvariant();
        List<RssItem> filtered;

        if (_currentLocalFeed != null && _currentLocalFeed.Url == "all_news")
        {
            var allItems = new List<RssItem>();
            lock (_allFeedsCache)
            {
                foreach (var list in _allFeedsCache.Values)
                {
                    allItems.AddRange(list);
                }
            }
            filtered = allItems
                .Where(item => (item.Title != null && item.Title.Contains(lowerQuery, StringComparison.OrdinalIgnoreCase)) ||
                               (item.Description != null && item.Description.Contains(lowerQuery, StringComparison.OrdinalIgnoreCase)))
                .OrderByDescending(item => item.PublishDate)
                .ToList();
        }
        else
        {
            filtered = _rssService.Items
                .Where(item => (item.Title != null && item.Title.Contains(lowerQuery, StringComparison.OrdinalIgnoreCase)) ||
                               (item.Description != null && item.Description.Contains(lowerQuery, StringComparison.OrdinalIgnoreCase)))
                .OrderByDescending(item => item.PublishDate)
                .ToList();
        }

        _articles.Clear();
        foreach (var item in filtered)
        {
            _articles.Add(new Daily_WinUI.ViewModels.RssItemViewModel(item));
        }
    }

    private void ArticleSearchBox_TextChanged(AutoSuggestBox sender, AutoSuggestBoxTextChangedEventArgs args)
    {
        if (args.Reason == AutoSuggestionBoxTextChangeReason.UserInput || string.IsNullOrEmpty(sender.Text))
        {
            FilterArticles(sender.Text);
        }
    }

    private void ArticleSearchBox_QuerySubmitted(AutoSuggestBox sender, AutoSuggestBoxQuerySubmittedEventArgs args)
    {
        FilterArticles(sender.Text);
    }

    private async Task LoadMediumReadingListAsync()
    {
        LoadingPanel.Visibility = Visibility.Visible;
        ArticlesListView.Visibility = Visibility.Collapsed;

        var settings = SettingsService.Load();
        var readingListUrl = settings.MediumReadingListUrl;
        if (string.IsNullOrEmpty(readingListUrl))
        {
            if (!string.IsNullOrEmpty(settings.MediumUsername))
            {
                readingListUrl = $"https://medium.com/@{settings.MediumUsername}/list/reading-list";
            }
            else
            {
                LoadingPanel.Visibility = Visibility.Collapsed;
                var dialog = new ContentDialog
                {
                    Title = "Medium Setup Required",
                    Content = "Please link your Medium account in Settings -> Features to view your reading list.",
                    CloseButtonText = "OK",
                    XamlRoot = this.XamlRoot
                };
                await dialog.ShowAsync();
                return;
            }
        }

        try
        {
            await EnsureWebViewInitializedAsync();

            var navigationTcs = new TaskCompletionSource<bool>();
            
            Windows.Foundation.TypedEventHandler<Microsoft.Web.WebView2.Core.CoreWebView2, Microsoft.Web.WebView2.Core.CoreWebView2NavigationCompletedEventArgs>? handler = null;
            handler = (sender, args) =>
            {
                BackgroundWebView.CoreWebView2.NavigationCompleted -= handler;
                if (args.IsSuccess)
                {
                    navigationTcs.TrySetResult(true);
                }
                else
                {
                    navigationTcs.TrySetException(new Exception($"Navigation failed with error status: {args.WebErrorStatus}"));
                }
            };
            BackgroundWebView.CoreWebView2.NavigationCompleted += handler;

            BackgroundWebView.Source = new Uri(readingListUrl);

            var timeoutTask = Task.Delay(15000);
            var completedTask = await Task.WhenAny(navigationTcs.Task, timeoutTask);

            if (completedTask == timeoutTask)
            {
                BackgroundWebView.CoreWebView2.NavigationCompleted -= handler;
                throw new TimeoutException("The request to load Medium Reading List timed out. Please check your connection.");
            }

            await navigationTcs.Task;
            await Task.Delay(1500);

            string javascript = @"
(function() {
    var articles = [];
    var items = document.querySelectorAll('article');
    
    function getStoryUrl(item) {
        var titleEl = item.querySelector('h2');
        if (titleEl) {
            var a = titleEl.querySelector('a') || titleEl.closest('a');
            if (a && a.href) return a.href;
        }
        
        var links = item.querySelectorAll('a');
        for (var i = 0; i < links.length; i++) {
            var href = links[i].href;
            if (!href) continue;
            
            var urlObj;
            try {
                urlObj = new URL(href);
            } catch(e) {
                continue;
            }
            var pathname = urlObj.pathname;
            
            if (pathname.includes('/tag/') || pathname.includes('/tagged/') || pathname.includes('/me') || pathname === '/' || pathname === '') {
                continue;
            }
            
            var parts = pathname.split('/').filter(Boolean);
            if (parts.length === 1 && parts[0].startsWith('@')) {
                continue;
            }
            
            if (pathname.includes('/p/') || parts.length >= 2 || (parts.length === 1 && !parts[0].startsWith('@'))) {
                return href;
            }
        }
        return '';
    }

    function getAuthorInfo(item) {
        var links = item.querySelectorAll('a');
        for (var i = 0; i < links.length; i++) {
            var href = links[i].href;
            if (!href) continue;
            
            try {
                var urlObj = new URL(href);
                if (urlObj.hostname === 'medium.com' && urlObj.pathname.startsWith('/@')) {
                    var parts = urlObj.pathname.split('/').filter(Boolean);
                    if (parts.length === 1) {
                        return {
                            url: href,
                            name: (links[i].innerText || links[i].textContent || '').trim()
                        };
                    }
                }
                if (urlObj.hostname.endsWith('.medium.com') && urlObj.hostname.split('.').length === 3) {
                    var sub = urlObj.hostname.split('.')[0];
                    if (sub !== 'www' && sub !== 'api' && urlObj.pathname === '/') {
                        return {
                            url: href,
                            name: (links[i].innerText || links[i].textContent || '').trim()
                        };
                    }
                }
            } catch(e) {}
        }
        return null;
    }

    items.forEach(function(item) {
        try {
            var titleEl = item.querySelector('h2');
            var title = titleEl ? titleEl.innerText : '';
            
            var storyUrl = getStoryUrl(item);
            var authorInfo = getAuthorInfo(item);
            
            var authorName = authorInfo ? authorInfo.name : '';
            var authorUrl = authorInfo ? authorInfo.url : '';

            if (!authorName) {
                var authorEl = item.querySelector('p');
                if (authorEl) {
                    authorName = authorEl.innerText;
                }
            }
            
            var description = '';
            var h3El = item.querySelector('h3');
            if (h3El) {
                description = h3El.innerText;
            } else {
                var pElements = item.querySelectorAll('p');
                pElements.forEach(function(p) {
                    var txt = p.innerText || '';
                    if (txt.length > 30 && !txt.includes('min read') && !txt.includes('member-only')) {
                        description = txt;
                    }
                });
            }
            
            var img = item.querySelector('img');
            var imageUrl = img ? img.src : '';
            
            title = title.trim();
            authorName = (authorName || '').trim();
            description = (description || '').trim();
            
            if (title && storyUrl) {
                articles.push({
                    title: title,
                    url: storyUrl,
                    author: authorName || 'Unknown Author',
                    authorUrl: authorUrl || '',
                    imageUrl: imageUrl,
                    description: description
                });
            }
        } catch(e) { }
    });
    return JSON.stringify(articles);
})();";

            var jsonResult = await BackgroundWebView.ExecuteScriptAsync(javascript);
            if (!string.IsNullOrEmpty(jsonResult) && jsonResult != "null" && jsonResult != "\"[]\"")
            {
                var json = System.Text.Json.JsonSerializer.Deserialize<string>(jsonResult);
                if (!string.IsNullOrEmpty(json))
                {
                    var scrapedItems = System.Text.Json.JsonSerializer.Deserialize<List<ScrapedMediumArticle>>(json);
                    if (scrapedItems != null && scrapedItems.Count > 0)
                    {
                        _articles.Clear();
                        var itemsList = new List<RssItem>();
                        foreach (var scraped in scrapedItems)
                        {
                            string author = scraped.author;
                            string pubName = "Medium";
                            int inIdx = author.IndexOf(" in ");
                            if (inIdx > 0)
                            {
                                pubName = author.Substring(inIdx + 4).Trim();
                                author = author.Substring(0, inIdx).Trim();
                            }

                            var rssItem = new RssItem
                            {
                                Title = scraped.title,
                                Link = scraped.url,
                                Description = !string.IsNullOrEmpty(scraped.description) 
                                    ? scraped.description 
                                    : $"Author: {author}. Read this story on Medium.",
                                Author = author,
                                PublishDate = DateTime.Now,
                                ImageUrl = Daily.Services.RssFeedService.OptimizeMediumImageUrl(scraped.imageUrl),
                                PublicationName = pubName,
                                PublicationIconUrl = "https://www.google.com/s2/favicons?domain=medium.com&sz=64"
                            };
                            _articles.Add(new Daily_WinUI.ViewModels.RssItemViewModel(rssItem));
                            itemsList.Add(rssItem);
                        }
                        _rssService.SetItemsAndNotify(itemsList);
                    }
                }
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[Medium Reading List] Load Error: {ex.Message}");
            var dialog = new ContentDialog
            {
                Title = "Error Loading Reading List",
                Content = $"Could not load reading list: {ex.Message}",
                CloseButtonText = "OK",
                XamlRoot = this.XamlRoot
            };
            await dialog.ShowAsync();
        }
        finally
        {
            if (_currentLocalFeed != null && _currentLocalFeed.Url == "medium_reading_list")
            {
                LoadingPanel.Visibility = Visibility.Collapsed;
                ArticlesListView.Visibility = Visibility.Visible;
            }
        }
    }

    internal static async Task<List<RssItem>> ScrapeSubstackInboxSharedAsync(WebView2 webView, Daily.Services.IRssFeedService rssService)
    {
        var itemsList = new List<RssItem>();
        if (webView.CoreWebView2 == null) return itemsList;

        // Ensure WebView is on substack.com origin so credentials: 'include' sends .substack.com session cookies
        string currentSrc = webView.CoreWebView2.Source ?? "";
        if (!Uri.TryCreate(currentSrc, UriKind.Absolute, out var curUri) ||
            !curUri.Host.Equals("substack.com", StringComparison.OrdinalIgnoreCase))
        {
            var warmTcs = new TaskCompletionSource<bool>();
            Windows.Foundation.TypedEventHandler<Microsoft.Web.WebView2.Core.CoreWebView2, Microsoft.Web.WebView2.Core.CoreWebView2NavigationCompletedEventArgs>? warmHandler = null;
            warmHandler = (s, e) =>
            {
                webView.CoreWebView2.NavigationCompleted -= warmHandler;
                warmTcs.TrySetResult(e.IsSuccess);
            };
            webView.CoreWebView2.NavigationCompleted += warmHandler;
            webView.Source = new Uri("https://substack.com/404");
            var warmDone = await Task.WhenAny(warmTcs.Task, Task.Delay(8000));
            if (warmDone != warmTcs.Task)
            {
                webView.CoreWebView2.NavigationCompleted -= warmHandler;
            }
        }

        // 1. Primary: Authenticated JSON Reader API (/api/v1/reader/posts?limit=35) joined with /api/v1/subscriptions
        string apiInboxJs = @"async function() {
            try {
                const [postsRes, subsRes] = await Promise.all([
                    fetch('https://substack.com/api/v1/reader/posts?limit=35', {
                        credentials: 'include',
                        headers: { 'Accept': 'application/json' }
                    }),
                    fetch('https://substack.com/api/v1/subscriptions', {
                        credentials: 'include',
                        headers: { 'Accept': 'application/json' }
                    }).catch(() => null)
                ]);
                if (!postsRes.ok) return '';
                const data = await postsRes.json();
                const pubsById = {};
                if (subsRes && subsRes.ok) {
                    const subData = await subsRes.json();
                    if (Array.isArray(subData.publications)) {
                        subData.publications.forEach(p => { if (p && p.id) pubsById[p.id] = p; });
                    }
                    if (Array.isArray(subData.subscriptions)) {
                        subData.subscriptions.forEach(s => {
                            if (s && s.publication && s.publication.id) pubsById[s.publication.id] = s.publication;
                        });
                    }
                }
                if (Array.isArray(data.publications)) {
                    data.publications.forEach(p => { if (p && p.id) pubsById[p.id] = p; });
                } else if (data.publications && typeof data.publications === 'object') {
                    Object.values(data.publications).forEach(p => { if (p && p.id) pubsById[p.id] = p; });
                }
                const rawPosts = Array.isArray(data.posts) ? data.posts : (Array.isArray(data.items) ? data.items : (Array.isArray(data) ? data : []));
                const items = [];
                rawPosts.forEach(p => {
                    const post = p.post || p;
                    if (!post || !post.title) return;
                    let pub = post.publication || p.publication || pubsById[post.publication_id];
                    if (!pub && Array.isArray(post.publishedBylines) && post.publishedBylines.length > 0) {
                        const pu = (post.publishedBylines[0].publicationUsers || []).find(u => u.publication && (!post.publication_id || u.publication.id === post.publication_id)) || (post.publishedBylines[0].publicationUsers || [])[0];
                        if (pu && pu.publication) pub = pu.publication;
                    }
                    let url = post.canonical_url || '';
                    if (!url && pub && post.slug) {
                        const host = (pub.custom_domain && !pub.custom_domain_optional) ? pub.custom_domain : (pub.subdomain ? pub.subdomain + '.substack.com' : '');
                        if (host) url = 'https://' + host + '/p/' + post.slug;
                    }
                    if (!url && post.id) {
                        url = 'https://substack.com/home/post/p-' + post.id;
                    }
                    if (!url) return;
                    let author = '';
                    if (Array.isArray(post.publishedBylines) && post.publishedBylines.length > 0) {
                        author = post.publishedBylines.map(b => b.name).filter(Boolean).join(', ');
                    }
                    items.push({
                        title: post.title || '',
                        url: url,
                        publication: (pub && pub.name) ? pub.name : '',
                        publicationIcon: (pub && pub.logo_url) ? pub.logo_url : '',
                        author: author,
                        imageUrl: post.cover_image || '',
                        description: post.subtitle || post.description || post.truncated_body_text || '',
                        date: post.post_date || null,
                        bodyHtml: post.body_html || null
                    });
                });
                return JSON.stringify(items);
            } catch (e) {
                return '';
            }
        }";

        static List<RssItem> MapScrapedItems(List<ScrapedSubstackArticle> scrapedItems)
        {
            var mapped = new List<RssItem>();
            foreach (var scraped in scrapedItems)
            {
                string pubName = !string.IsNullOrEmpty(scraped.publication) ? scraped.publication : "Substack";
                string pubIcon = !string.IsNullOrEmpty(scraped.publicationIcon)
                    ? Daily.Services.RssFeedService.OptimizeSubstackImageUrl(scraped.publicationIcon)
                    : "https://substack.com/favicon.ico";
                string? cleanBody = null;
                if (!string.IsNullOrEmpty(scraped.bodyHtml) && scraped.bodyHtml.Length > 250)
                {
                    cleanBody = StripSubstackTrackingAndNoise(scraped.bodyHtml);
                }
                mapped.Add(new RssItem
                {
                    Title = scraped.title,
                    Link = scraped.url,
                    Content = cleanBody,
                    Description = !string.IsNullOrEmpty(scraped.description)
                        ? scraped.description
                        : $"Substack post from {pubName}",
                    Author = !string.IsNullOrEmpty(scraped.author) ? scraped.author : pubName,
                    PublishDate = ParseSubstackDate(scraped.date),
                    ImageUrl = Daily.Services.RssFeedService.OptimizeSubstackImageUrl(scraped.imageUrl),
                    PublicationName = pubName,
                    PublicationIconUrl = pubIcon
                });
            }
            return mapped;
        }

        string apiJson = await ExecuteAsyncScriptOnWebViewAsync(webView.CoreWebView2, apiInboxJs, 9000);
        if (!string.IsNullOrWhiteSpace(apiJson))
        {
            try
            {
                var apiScraped = System.Text.Json.JsonSerializer.Deserialize<List<ScrapedSubstackArticle>>(apiJson);
                if (apiScraped != null && apiScraped.Count > 0)
                {
                    return MapScrapedItems(apiScraped);
                }
            }
            catch { }
        }

        // 2. Fallback: DOM scraping on https://substack.com/inbox
        try
        {
            var navigationTcs = new TaskCompletionSource<bool>();
            Windows.Foundation.TypedEventHandler<Microsoft.Web.WebView2.Core.CoreWebView2, Microsoft.Web.WebView2.Core.CoreWebView2NavigationCompletedEventArgs>? handler = null;
            handler = (sender, args) =>
            {
                webView.CoreWebView2.NavigationCompleted -= handler;
                navigationTcs.TrySetResult(args.IsSuccess);
            };
            webView.CoreWebView2.NavigationCompleted += handler;
            webView.Source = new Uri("https://substack.com/inbox");
            var completed = await Task.WhenAny(navigationTcs.Task, Task.Delay(12000));
            if (completed != navigationTcs.Task)
            {
                webView.CoreWebView2.NavigationCompleted -= handler;
            }
            else
            {
                await Task.Delay(1400);
                string domJs = @"(function() {
                    var items = [];
                    var seen = {};
                    var cards = document.querySelectorAll('article, [data-testid*=""post""], div[class*=""reader-post""]');
                    if (cards.length === 0) cards = document.querySelectorAll('a[href*=""/p/""]');
                    cards.forEach(function(card) {
                        var a = card.tagName === 'A' ? card : (card.querySelector('a[href*=""/p/""]') || card.querySelector('a'));
                        if (!a || !a.href) return;
                        var href = a.href;
                        if (seen[href]) return;
                        seen[href] = true;
                        var titleEl = card.querySelector('h1, h2, h3, [class*=""title""]') || a;
                        var title = titleEl ? (titleEl.innerText || '').trim() : '';
                        if (!title) return;
                        var pubEl = card.querySelector('[class*=""publication""], [class*=""pub-name""], a[href*=""substack.com""]:not([href*=""/p/""])');
                        var pubName = pubEl ? (pubEl.innerText || '').trim() : '';
                        var authorEl = card.querySelector('[class*=""byline""], [class*=""author""]');
                        var author = authorEl ? (authorEl.innerText || '').trim() : '';
                        var descEl = card.querySelector('p, [class*=""subtitle""], [class*=""description""]');
                        var desc = descEl ? (descEl.innerText || '').trim() : '';
                        var imgEl = card.querySelector('img');
                        var imgUrl = imgEl ? (imgEl.src || imgEl.getAttribute('data-src') || '') : '';
                        items.push({ title: title, url: href, publication: pubName, author: author, imageUrl: imgUrl, description: desc });
                    });
                    return JSON.stringify(items);
                })();";
                var jsonResult = await webView.ExecuteScriptAsync(domJs);
                if (!string.IsNullOrEmpty(jsonResult) && jsonResult != "null" && jsonResult != "\"[]\"")
                {
                    var json = System.Text.Json.JsonSerializer.Deserialize<string>(jsonResult);
                    if (!string.IsNullOrEmpty(json))
                    {
                        var domScraped = System.Text.Json.JsonSerializer.Deserialize<List<ScrapedSubstackArticle>>(json);
                        if (domScraped != null && domScraped.Count > 0)
                        {
                            return MapScrapedItems(domScraped);
                        }
                    }
                }
            }
        }
        catch { }

        // 3. Final fallback: aggregate subscribed Substack RSS feeds if session cookie expired
        if (rssService.Feeds != null)
        {
            var substackFeeds = rssService.Feeds.Where(f =>
                (f.Url != null && f.Url.Contains("substack.com", StringComparison.OrdinalIgnoreCase)) ||
                (f.IconUrl != null && f.IconUrl.Contains("substack", StringComparison.OrdinalIgnoreCase))).ToList();
            if (substackFeeds.Count > 0)
            {
                var tasks = substackFeeds.Select(async f =>
                {
                    try { return await rssService.FetchFeedItemsAsync(f) ?? new List<RssItem>(); }
                    catch { return new List<RssItem>(); }
                });
                var batches = await Task.WhenAll(tasks);
                itemsList = batches.SelectMany(x => x).OrderByDescending(i => i.PublishDate).Take(40).ToList();
            }
        }

        return itemsList;
    }

    private async Task LoadSubstackInboxAsync()
    {
        LoadingPanel.Visibility = Visibility.Visible;
        ArticlesListView.Visibility = Visibility.Collapsed;

        var settings = SettingsService.Load();
        if (string.IsNullOrEmpty(settings.SubstackUsername))
        {
            LoadingPanel.Visibility = Visibility.Collapsed;
            var dialog = new ContentDialog
            {
                Title = "Substack Setup Required",
                Content = "Please link your Substack account in Settings -> Features to view your inbox.",
                CloseButtonText = "OK",
                XamlRoot = this.XamlRoot
            };
            await dialog.ShowAsync();
            return;
        }

        try
        {
            await EnsureWebViewInitializedAsync();
            var itemsList = await ScrapeSubstackInboxSharedAsync(BackgroundWebView, _rssService);
            _articles.Clear();
            foreach (var rssItem in itemsList)
            {
                _articles.Add(new Daily_WinUI.ViewModels.RssItemViewModel(rssItem));
            }
            _rssService.SetItemsAndNotify(itemsList);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[Substack Inbox] Load Error: {ex.Message}");
            var dialog = new ContentDialog
            {
                Title = "Error Loading Substack Inbox",
                Content = $"Could not load Substack inbox: {ex.Message}",
                CloseButtonText = "OK",
                XamlRoot = this.XamlRoot
            };
            await dialog.ShowAsync();
        }
        finally
        {
            if (_currentLocalFeed != null && _currentLocalFeed.Url == "substack_inbox")
            {
                LoadingPanel.Visibility = Visibility.Collapsed;
                ArticlesListView.Visibility = Visibility.Visible;
            }
        }
    }

    public class ScrapedSubstackArticle
    {
        public string title { get; set; } = string.Empty;
        public string url { get; set; } = string.Empty;
        public string publication { get; set; } = string.Empty;
        public string? publicationIcon { get; set; }
        public string author { get; set; } = string.Empty;
        public string imageUrl { get; set; } = string.Empty;
        public string description { get; set; } = string.Empty;
        public string? date { get; set; }
        public string? bodyHtml { get; set; }
    }

    public class ScrapedMediumArticle
    {
        public string title { get; set; } = string.Empty;
        public string url { get; set; } = string.Empty;
        public string author { get; set; } = string.Empty;
        public string authorUrl { get; set; } = string.Empty;
        public string imageUrl { get; set; } = string.Empty;
        public string description { get; set; } = string.Empty;
    }
}
