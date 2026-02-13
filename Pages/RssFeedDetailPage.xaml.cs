using Daily.Models;
using Daily.Services;
using Daily.ViewModels;

namespace Daily.Pages;

public partial class RssFeedDetailPage : ContentPage
{
    private readonly RssFeedViewModel? _viewModel;

    public RssFeedDetailPage(RssItem? selectedItem = null)
    {
        InitializeComponent();

        var services = Application.Current?.Handler?.MauiContext?.Services;
        var rssService = services?.GetService<IRssFeedService>();

        if (rssService != null)
        {
            _viewModel = new RssFeedViewModel(rssService);
            BindingContext = _viewModel;

            if (selectedItem != null)
            {
                _ = _viewModel.SelectItemAsync(selectedItem);
            }
        }
    }

    private async void OnItemTapped(object sender, TappedEventArgs e)
    {
        if (_viewModel == null)
        {
            return;
        }

        if (e.Parameter is RssItem item)
        {
            await _viewModel.SelectItemAsync(item);
        }
    }
}
