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
        FeedComboBox.ItemsSource = _rssService.Feeds;
        
        _rssService.OnFeedChanged += RssService_OnFeedChanged;
        _rssService.OnItemsUpdated += RssService_OnItemsUpdated;
        
        if (_rssService.CurrentFeed != null)
        {
            FeedComboBox.SelectedItem = _rssService.CurrentFeed;
        }
        UpdateWidgetArticles();
        
        // Auto-load articles if a feed is selected but items haven't been fetched yet.
        // InitializeCustomFeedsAsync sets CurrentFeed but never calls LoadFeedAsync,
        // and SelectionChanged skips because the feed is already the current one.
        if (_rssService.CurrentFeed != null && !_rssService.Items.Any() && !_rssService.IsLoading)
        {
            LoadingPanel.Visibility = Visibility.Visible;
            ArticlesListView.Visibility = Visibility.Collapsed;
            await _rssService.LoadFeedAsync(_rssService.CurrentFeed);
        }
    }

    private void RssFeedWidgetControl_Unloaded(object sender, RoutedEventArgs e)
    {
        _rssService.OnFeedChanged -= RssService_OnFeedChanged;
        _rssService.OnItemsUpdated -= RssService_OnItemsUpdated;
    }

    private async void RssService_OnFeedChanged()
    {
        DispatcherQueue.TryEnqueue(async () =>
        {
            if (FeedComboBox.ItemsSource != _rssService.Feeds)
            {
                FeedComboBox.ItemsSource = _rssService.Feeds;
            }
            if (FeedComboBox.SelectedItem != _rssService.CurrentFeed)
            {
                FeedComboBox.SelectedItem = _rssService.CurrentFeed;
            }
            
            // Auto-load: InitializeAsync seeds feeds AFTER the widget is already loaded,
            // so this is the first moment we know CurrentFeed is set. Load articles now.
            if (_rssService.CurrentFeed != null && !_rssService.Items.Any() && !_rssService.IsLoading)
            {
                LoadingPanel.Visibility = Visibility.Visible;
                ArticlesListView.Visibility = Visibility.Collapsed;
                await _rssService.LoadFeedAsync(_rssService.CurrentFeed);
            }
        });
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

    private async void FeedComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (FeedComboBox.SelectedItem is FeedSource selectedFeed)
        {
            // Only trigger a new load if the feed actually changed (compare by Url to avoid object reference false positives)
            if (_rssService.CurrentFeed == null || selectedFeed.Url != _rssService.CurrentFeed.Url)
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
            ArticleTapped?.Invoke(this, item);
        }
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
