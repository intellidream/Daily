using System;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Daily.Models;
using Daily_WinUI.Services;
using System.Collections.ObjectModel;
using Microsoft.Extensions.DependencyInjection;

namespace Daily_WinUI.Controls;

public sealed partial class RssFeedWidgetControl : UserControl
{
    private readonly Daily.Services.IRssFeedService _rssService;
    private readonly Daily.Services.IRssArticleService _articleService;
    private ObservableCollection<RssItem> _widgetArticles = new();
    private ObservableCollection<RssItem> _readLaterArticles = new();
    private ObservableCollection<RssItem> _favoriteArticles = new();

    private readonly FeedSource _mediumReadingListSource = new FeedSource
    {
        Name = "Medium Reading List",
        Url = "medium_reading_list",
        Category = FeedCategory.Coding,
        IconUrl = "https://www.google.com/s2/favicons?domain=medium.com&sz=64"
    };

    private readonly FeedSource _allNewsFeedSource = new FeedSource
    {
        Name = "All News",
        Url = "all_news",
        Category = FeedCategory.Other,
        IconUrl = "https://www.google.com/s2/favicons?domain=rss.com&sz=64"
    };

    private Task? _webViewInitTask;
    private bool _isWidgetLoadingCustomFeed = false;

    public event EventHandler<RssItem>? ArticleTapped;
    public event EventHandler? WidgetTapped;

    public RssFeedWidgetControl()
    {
        InitializeComponent();
        _rssService = App.Current.Services.GetRequiredService<Daily.Services.IRssFeedService>();
        _articleService = App.Current.Services.GetRequiredService<Daily.Services.IRssArticleService>();
        
        Loaded += RssFeedWidgetControl_Loaded;
        Unloaded += RssFeedWidgetControl_Unloaded;
        SizeChanged += OnSizeChanged;
        ArticlesListView.ItemsSource = _widgetArticles;
        ReadLaterListView.ItemsSource = _readLaterArticles;
        FavoritesListView.ItemsSource = _favoriteArticles;
    }


    private async void RssFeedWidgetControl_Loaded(object sender, RoutedEventArgs e)
    {
        PopulateFeedMenu();
        UpdateSelectedFeedUI(_rssService.CurrentFeed);
        UpdateAdaptiveLayout(ActualWidth);

        
        _rssService.OnFeedChanged += RssService_OnFeedChanged;
        _rssService.OnItemsUpdated += RssService_OnItemsUpdated;
        _articleService.OnItemsChanged += ArticleService_OnItemsChanged;
        
        UpdateWidgetArticles();
        UpdateReadLaterArticles();
        UpdateFavoriteArticles();
        
        // Auto-load articles if a feed is selected but items haven't been fetched yet.
        if (_rssService.CurrentFeed != null && !_rssService.Items.Any() && !_rssService.IsLoading)
        {
            LoadingPanel.Visibility = Visibility.Visible;
            ArticlesListView.Visibility = Visibility.Collapsed;
            if (_rssService.CurrentFeed.Url == "medium_reading_list")
            {
                await LoadMediumReadingListAsync();
            }
            else if (_rssService.CurrentFeed.Url == "all_news")
            {
                await LoadAllNewsFeedAsync();
            }
            else
            {
                var task = _rssService.LoadFeedAsync(_rssService.CurrentFeed);
                MainPage.Current?.RegisterLoadingTask(task);
                await task;
            }
        }
    }

    private void RssFeedWidgetControl_Unloaded(object sender, RoutedEventArgs e)
    {
        _rssService.OnFeedChanged -= RssService_OnFeedChanged;
        _rssService.OnItemsUpdated -= RssService_OnItemsUpdated;
        _articleService.OnItemsChanged -= ArticleService_OnItemsChanged;
    }

    private async void RssService_OnFeedChanged()
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            _ = HandleFeedChangedSafeAsync();
        });
    }

    private async Task HandleFeedChangedSafeAsync()
    {
        try
        {
            PopulateFeedMenu();
            UpdateSelectedFeedUI(_rssService.CurrentFeed);

            if (_rssService.CurrentFeed != null && !_rssService.Items.Any() && !_rssService.IsLoading)
            {
                LoadingPanel.Visibility = Visibility.Visible;
                ArticlesListView.Visibility = Visibility.Collapsed;
                if (_rssService.CurrentFeed.Url == "medium_reading_list")
                {
                    await LoadMediumReadingListAsync();
                }
                else if (_rssService.CurrentFeed.Url == "all_news")
                {
                    await LoadAllNewsFeedAsync();
                }
                else
                {
                    var task = _rssService.LoadFeedAsync(_rssService.CurrentFeed);
                    MainPage.Current?.RegisterLoadingTask(task);
                    await task;
                }
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[RssFeedWidgetControl] Feed change handling failed: {ex}");
        }
    }

    private void RssService_OnItemsUpdated()
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            UpdateWidgetArticles();
        });
    }

    private void ArticleService_OnItemsChanged()
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            UpdateReadLaterArticles();
            UpdateFavoriteArticles();
        });
    }

    private void UpdateWidgetArticles()
    {
        _widgetArticles.Clear();
        foreach (var item in _rssService.Items.Take(5))
        {
            _widgetArticles.Add(item);
        }
        
        if (_rssService.IsLoading || _isWidgetLoadingCustomFeed)
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

    private void UpdateReadLaterArticles()
    {
        _readLaterArticles.Clear();
        foreach (var saved in _articleService.ReadLaterItems.Take(5))
        {
            _readLaterArticles.Add(MapToRssItem(saved));
        }
        NoReadLaterTextBlock.Visibility = _readLaterArticles.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private void UpdateFavoriteArticles()
    {
        _favoriteArticles.Clear();
        foreach (var saved in _articleService.FavoriteItems.Take(5))
        {
            _favoriteArticles.Add(MapToRssItem(saved));
        }
        NoFavoritesTextBlock.Visibility = _favoriteArticles.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private RssItem MapToRssItem(LocalSavedArticle saved)
    {
        return new RssItem
        {
            Title = saved.Title,
            Link = saved.ArticleUrl,
            PublishDate = saved.ArticleDate,
            ImageUrl = saved.ImageUrl,
            Description = saved.Description,
            Author = saved.Author,
            PublicationName = saved.PublicationName,
            PublicationIconUrl = saved.PublicationIconUrl
        };
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

        // Add "Medium Reading List" if configured
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

    private List<FeedSource> GetWidgetFeedsList()
    {
        var list = new List<FeedSource>();
        if (_rssService.Feeds != null)
            list.AddRange(_rssService.Feeds);

        var settings = SettingsService.Load();
        if (!string.IsNullOrEmpty(settings.MediumUsername))
            list.Add(_mediumReadingListSource);

        list.Add(_allNewsFeedSource);
        return list;
    }

    private async void CycleLeftButton_Click(object sender, RoutedEventArgs e)
    {
        var feeds = GetWidgetFeedsList();
        if (feeds == null || feeds.Count == 0) return;

        int currentIndex = 0;
        if (_rssService.CurrentFeed != null)
        {
            currentIndex = feeds.FindIndex(f => f.Url == _rssService.CurrentFeed.Url);
            if (currentIndex < 0) currentIndex = 0;
        }

        int nextIndex = (currentIndex - 1 + feeds.Count) % feeds.Count;
        var nextFeed = feeds[nextIndex];
        await SelectFeedAsync(nextFeed);
    }

    private async void CycleRightButton_Click(object sender, RoutedEventArgs e)
    {
        var feeds = GetWidgetFeedsList();
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
            if (feed.Url == "medium_reading_list")
            {
                await LoadMediumReadingListAsync();
            }
            else if (feed.Url == "all_news")
            {
                await LoadAllNewsFeedAsync();
            }
            else
            {
                await _rssService.LoadFeedAsync(feed);
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
                SelectedFeedFontIcon.Glyph = "\uEAFD"; // icon-news
                SelectedFeedFontIcon.FontFamily = (Microsoft.UI.Xaml.Media.FontFamily)Application.Current.Resources["TablerIconsFont"];
                SelectedFeedFontIcon.Visibility = Visibility.Visible;
            }
        }
        else if (feed.Url == "medium_reading_list")
        {
            if (SelectedFeedIconBorder != null) SelectedFeedIconBorder.Visibility = Visibility.Collapsed;
            if (SelectedFeedFontIcon != null)
            {
                SelectedFeedFontIcon.Glyph = "\uEC70"; // brand-medium
                SelectedFeedFontIcon.FontFamily = (Microsoft.UI.Xaml.Media.FontFamily)Application.Current.Resources["TablerIconsFont"];
                SelectedFeedFontIcon.Visibility = Visibility.Visible;
            }
        }
        else if (string.IsNullOrWhiteSpace(feed.IconUrl))
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
                System.Diagnostics.Debug.WriteLine($"[RssFeedWidgetControl] Error loading icon: {ex.Message}");
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

    private void ArticlesListView_ItemClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is RssItem item)
        {
            ArticleTapped?.Invoke(this, item);
        }
    }

    private void WidgetPivot_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (WidgetPivot == null || FeedSelectorContainer == null) return;

        int index = WidgetPivot.SelectedIndex;
        if (index == 0)
        {
            FeedSelectorContainer.Visibility = Visibility.Visible;
            UpdateWidgetArticles();
        }
        else if (index == 1)
        {
            FeedSelectorContainer.Visibility = Visibility.Collapsed;
            UpdateReadLaterArticles();
        }
        else if (index == 2)
        {
            FeedSelectorContainer.Visibility = Visibility.Collapsed;
            UpdateFavoriteArticles();
        }
    }

    /// <summary>Called by the dashboard refresh button to reload the current feed in-place.</summary>
    public async Task RefreshAsync()
    {
        if (WidgetPivot.SelectedIndex == 0 && _rssService.CurrentFeed != null)
        {
            if (_rssService.CurrentFeed.Url == "medium_reading_list")
                await LoadMediumReadingListAsync();
            else if (_rssService.CurrentFeed.Url == "all_news")
                await LoadAllNewsFeedAsync();
            else
                await _rssService.LoadFeedAsync(_rssService.CurrentFeed);
        }
    }

    private async void RefreshButton_Click(object sender, RoutedEventArgs e)
    {
        if (WidgetPivot.SelectedIndex == 0 && _rssService.CurrentFeed != null)
        {
            if (_rssService.CurrentFeed.Url == "medium_reading_list")
                await LoadMediumReadingListAsync();
            else if (_rssService.CurrentFeed.Url == "all_news")
                await LoadAllNewsFeedAsync();
            else
                await _rssService.LoadFeedAsync(_rssService.CurrentFeed);
        }
    }

    private void WidgetPivot_Tapped(object sender, TappedRoutedEventArgs e)
    {
        // Intercept tapped events originating from the Pivot's header/tabs area or controls,
        // and prevent them from bubbling up to the MainPage widget border, which would trigger
        // opening the detail window.
        DependencyObject current = e.OriginalSource as DependencyObject;
        while (current != null && current != WidgetPivot)
        {
            string typeName = current.GetType().Name;
            if (typeName.Contains("PivotHeader") || typeName.Contains("PivotHeaderItem"))
            {
                e.Handled = true;
                return;
            }
            current = Microsoft.UI.Xaml.Media.VisualTreeHelper.GetParent(current);
        }
    }

    private void WidgetBorder_Tapped(object sender, TappedRoutedEventArgs e)
    {
        WidgetTapped?.Invoke(this, EventArgs.Empty);
    }

    private void OnSizeChanged(object sender, SizeChangedEventArgs e)
    {
        UpdateAdaptiveLayout(e.NewSize.Width);
    }

    private void UpdateAdaptiveLayout(double width)
    {
        if (width <= 0 || SelectedFeedText == null) return;

        // Calculate available text width: widget width minus tabs (approx 140) and right-header buttons/spacing (approx 134)
        double available = width - 280; // Safety margin
        double newMaxWidth = Math.Max(55, Math.Min(120, available));

        SelectedFeedText.MaxWidth = newMaxWidth;
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
            await BackgroundWebView.EnsureCoreWebView2Async(env);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"WebView2 initialization failed in Widget: {ex.Message}");
            throw;
        }
    }

    private async Task LoadMediumReadingListAsync()
    {
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
                return;
            }
        }

        _isWidgetLoadingCustomFeed = true;
        UpdateWidgetArticles();

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
                throw new TimeoutException("The request to load Medium Reading List timed out.");
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
                            itemsList.Add(rssItem);
                        }
                        _rssService.SetItemsAndNotify(itemsList);
                    }
                }
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[Medium Reading List Widget] Load Error: {ex.Message}");
        }
        finally
        {
            _isWidgetLoadingCustomFeed = false;
            UpdateWidgetArticles();
        }
    }

    private async Task LoadAllNewsFeedAsync()
    {
        var feeds = _rssService.Feeds;
        if (feeds == null || feeds.Count == 0)
        {
            _rssService.SetItemsAndNotify(new List<RssItem>());
            return;
        }

        _isWidgetLoadingCustomFeed = true;
        UpdateWidgetArticles();

        try
        {
            var tasks = feeds.Select(async feed =>
            {
                try
                {
                    var items = await _rssService.FetchFeedItemsAsync(feed);
                    return items ?? new List<RssItem>();
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine($"[Widget All News] Error fetching {feed.Name}: {ex.Message}");
                    return new List<RssItem>();
                }
            }).ToList();

            var results = await Task.WhenAll(tasks);
            var displayItems = new List<RssItem>();

            // Round-robin selection: take 1st item from each feed, then 2nd from each, etc.
            int maxItemsPerFeed = results.Any() ? results.Max(r => r.Count) : 0;
            for (int i = 0; i < maxItemsPerFeed; i++)
            {
                foreach (var items in results)
                {
                    if (i < items.Count)
                    {
                        displayItems.Add(items[i]);
                    }
                }
                if (displayItems.Count >= 15) // Stop early to avoid taking too many
                    break;
            }

            var sortedItems = displayItems.OrderByDescending(i => i.PublishDate).Take(5).ToList();
            _rssService.SetItemsAndNotify(sortedItems);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[Widget All News] Load Error: {ex.Message}");
        }
        finally
        {
            _isWidgetLoadingCustomFeed = false;
            UpdateWidgetArticles();
        }
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

