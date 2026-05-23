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
    private ObservableCollection<RssItem> _widgetArticles = new();

    public event EventHandler<RssItem>? ArticleTapped;
    public event EventHandler? WidgetTapped;

    public RssFeedWidgetControl()
    {
        InitializeComponent();
        _rssService = App.Current.Services.GetRequiredService<Daily.Services.IRssFeedService>();
        
        Loaded += RssFeedWidgetControl_Loaded;
        Unloaded += RssFeedWidgetControl_Unloaded;
        ArticlesListView.ItemsSource = _widgetArticles;
    }

    private async void RssFeedWidgetControl_Loaded(object sender, RoutedEventArgs e)
    {
        PopulateFeedMenu();
        UpdateSelectedFeedUI(_rssService.CurrentFeed);
        
        _rssService.OnFeedChanged += RssService_OnFeedChanged;
        _rssService.OnItemsUpdated += RssService_OnItemsUpdated;
        UpdateWidgetArticles();
        
        // Auto-load articles if a feed is selected but items haven't been fetched yet.
        // InitializeCustomFeedsAsync sets CurrentFeed but never calls LoadFeedAsync,
        // and SelectionChanged skips because the feed is already the current one.
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

            // Auto-load: InitializeAsync seeds feeds AFTER the widget is already loaded,
            // so this is the first moment we know CurrentFeed is set. Load articles now.
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

    /// <summary>Called by the dashboard refresh button to reload the current feed in-place.</summary>
    public async Task RefreshAsync()
    {
        if (_rssService.CurrentFeed != null)
            await _rssService.LoadFeedAsync(_rssService.CurrentFeed);
    }

    private async void RefreshButton_Click(object sender, RoutedEventArgs e)
    {
        if (_rssService.CurrentFeed != null)
        {
            await _rssService.LoadFeedAsync(_rssService.CurrentFeed);
        }
    }

    private void WidgetBorder_Tapped(object sender, TappedRoutedEventArgs e)
    {
        WidgetTapped?.Invoke(this, EventArgs.Empty);
    }
}
