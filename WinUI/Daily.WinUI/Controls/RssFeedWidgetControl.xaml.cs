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
            var task = _rssService.LoadFeedAsync(_rssService.CurrentFeed);
            MainPage.Current?.RegisterLoadingTask(task);
            await task;
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
                var task = _rssService.LoadFeedAsync(_rssService.CurrentFeed);
                MainPage.Current?.RegisterLoadingTask(task);
                await task;
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
            System.Diagnostics.Debug.WriteLine($"[RssFeedWidgetControl] Error loading icon: {ex.Message}");
            SelectedFeedIcon.Source = null;
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
            await _rssService.LoadFeedAsync(_rssService.CurrentFeed);
    }

    private async void RefreshButton_Click(object sender, RoutedEventArgs e)
    {
        if (WidgetPivot.SelectedIndex == 0 && _rssService.CurrentFeed != null)
        {
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
}

