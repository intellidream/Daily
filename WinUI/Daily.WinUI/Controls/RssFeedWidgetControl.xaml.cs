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

namespace Daily_WinUI.Controls;

public sealed partial class RssFeedWidgetControl : UserControl
{
    private readonly RssClient _rssClient = new();
    private CancellationTokenSource? _cancellationTokenSource;
    private ObservableCollection<RssItem> _articles = new();

    public event EventHandler<RssItem>? ArticleTapped;
    public event EventHandler? WidgetTapped;

    public RssFeedWidgetControl()
    {
        InitializeComponent();
        Loaded += RssFeedWidgetControl_Loaded;
        Unloaded += RssFeedWidgetControl_Unloaded;
        ArticlesListView.ItemsSource = _articles;
    }

    private async void RssFeedWidgetControl_Loaded(object sender, RoutedEventArgs e)
    {
        FeedComboBox.ItemsSource = _rssClient.Feeds;
        if (_rssClient.Feeds.Any())
        {
            FeedComboBox.SelectedIndex = 0; // Triggers FeedComboBox_SelectionChanged
        }
    }

    private void RssFeedWidgetControl_Unloaded(object sender, RoutedEventArgs e)
    {
        _cancellationTokenSource?.Cancel();
    }

    private async void FeedComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (FeedComboBox.SelectedItem is FeedSource selectedFeed)
        {
            await LoadFeedAsync(selectedFeed);
        }
    }

    private async Task LoadFeedAsync(FeedSource feed)
    {
        _cancellationTokenSource?.Cancel();
        _cancellationTokenSource = new CancellationTokenSource();

        LoadingPanel.Visibility = Visibility.Visible;
        ArticlesListView.Visibility = Visibility.Collapsed;

        try
        {
            var items = await _rssClient.FetchFeedAsync(feed, _cancellationTokenSource.Token);
            
            _articles.Clear();
            foreach (var item in items.Take(3)) // Show top 3 in widget
            {
                _articles.Add(item);
            }

            LoadingPanel.Visibility = Visibility.Collapsed;
            ArticlesListView.Visibility = Visibility.Visible;
        }
        catch (TaskCanceledException)
        {
            // Ignore cancellation
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Error loading feed: {ex.Message}");
            LoadingPanel.Visibility = Visibility.Collapsed;
        }
    }

    private void ArticlesListView_ItemClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is RssItem item)
        {
            ArticleTapped?.Invoke(this, item);
        }
    }

    private void WidgetBorder_Tapped(object sender, TappedRoutedEventArgs e)
    {
        WidgetTapped?.Invoke(this, EventArgs.Empty);
    }
}
