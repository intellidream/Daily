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

namespace Daily_WinUI.Views;

public sealed partial class RssFeedDetailPage : Page
{
    private readonly RssClient _rssClient = new();
    private CancellationTokenSource? _cancellationTokenSource;
    private ObservableCollection<RssItem> _articles = new();
    private RssItem? _selectedItem;

    public RssFeedDetailPage()
    {
        InitializeComponent();
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
        if (FeedComboBox.ItemsSource == null)
        {
            FeedComboBox.ItemsSource = _rssClient.Feeds;
            if (_selectedItem != null)
            {
                // Pre-select the feed that matches the item, if possible
                var feed = _rssClient.Feeds.FirstOrDefault(f => f.Name == _selectedItem.PublicationName);
                if (feed != null)
                {
                    FeedComboBox.SelectedItem = feed;
                }
            }
            else if (_rssClient.Feeds.Any())
            {
                FeedComboBox.SelectedIndex = 0;
            }
        }
        
        EnsureWebViewCoreInitialized();
    }

    private void RssFeedDetailPage_Unloaded(object sender, RoutedEventArgs e)
    {
        _cancellationTokenSource?.Cancel();
    }

    private async void EnsureWebViewCoreInitialized()
    {
        await ReaderWebView.EnsureCoreWebView2Async();
    }

    private async void FeedComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (FeedComboBox.SelectedItem is FeedSource selectedFeed && _selectedItem == null)
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
            foreach (var item in items)
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

        try
        {
            var fullArticle = await _rssClient.FetchFullArticleAsync(item.Link);
            
            // Generate HTML
            string html = GenerateReaderHtml(fullArticle);
            
            await ReaderWebView.EnsureCoreWebView2Async();
            ReaderWebView.NavigateToString(html);

            ReaderLoadingPanel.Visibility = Visibility.Collapsed;
            ReaderWebView.Visibility = Visibility.Visible;
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Error loading reader view: {ex.Message}");
            ReaderLoadingPanel.Visibility = Visibility.Collapsed;
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
            _ = LoadFeedAsync(feed);
        }
    }

    private string GenerateReaderHtml(RssItem article)
    {
        bool isDark = App.Current.RequestedTheme == ApplicationTheme.Dark;
        
        string bgColor = isDark ? "#1C1C1C" : "#FAF9F6"; // Match ApplicationPageBackgroundThemeBrush closely
        string textColor = isDark ? "#E0E0E0" : "#1A1A1A";
        string linkColor = isDark ? "#66B2FF" : "#0066CC";
        string metaColor = isDark ? "#A0A0A0" : "#666666";

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
        body {{
            font-family: 'Segoe UI', -apple-system, BlinkMacSystemFont, Roboto, Helvetica, Arial, sans-serif;
            background-color: {bgColor};
            color: {textColor};
            line-height: 1.6;
            margin: 0;
            padding: 24px;
            max-width: 800px;
            margin-left: auto;
            margin-right: auto;
            font-size: 18px;
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
    <h1>{article.Title}</h1>
    {metaHtml}
    {featuredImageHtml}
    <div class='content'>
        {article.Content ?? article.Description ?? "" }
    </div>
</body>
</html>";
    }
}
