using Daily.Models;
using Daily.Services;
using Daily.ViewModels;

namespace Daily.Views;

public partial class RssFeedWidgetView : ContentView
{
    private readonly RssFeedViewModel? _viewModel;

    public event EventHandler<RssItem>? ItemSelected;

    public RssFeedWidgetView()
    {
        InitializeComponent();

        var services = Application.Current?.Handler?.MauiContext?.Services;
        var rssService = services?.GetService<IRssFeedService>();

        if (rssService != null)
        {
            _viewModel = new RssFeedViewModel(rssService, maxItems: 5);
            BindingContext = _viewModel;
        }
    }

    private void OnItemTapped(object sender, TappedEventArgs e)
    {
        if (e.Parameter is RssItem item)
        {
            ItemSelected?.Invoke(this, item);
        }
    }
}
