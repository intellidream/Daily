using System;
using System.Linq;
using System.Threading.Tasks;
using Daily.Models;
using Daily_WinUI.Services;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Daily_WinUI.Controls;

public sealed partial class PrismWidgetControl : UserControl
{
    private IPrismService? _prismService;
    private bool _subscribed;

    public PrismWidgetControl()
    {
        InitializeComponent();
        Loaded += PrismWidgetControl_Loaded;
        Unloaded += PrismWidgetControl_Unloaded;
    }

    private async void PrismWidgetControl_Loaded(object sender, RoutedEventArgs e)
    {
        _prismService = App.Current?.Services?.GetService<IPrismService>();
        if (_prismService != null && !_subscribed)
        {
            _prismService.DataChanged += OnPrismDataChanged;
            _subscribed = true;
        }

        var task = RefreshAsync();
        MainPage.Current?.RegisterLoadingTask(task);
        await task;
    }

    private void PrismWidgetControl_Unloaded(object sender, RoutedEventArgs e)
    {
        if (_prismService != null && _subscribed)
        {
            _prismService.DataChanged -= OnPrismDataChanged;
            _subscribed = false;
        }
    }

    private void OnPrismDataChanged(object? sender, EventArgs e)
    {
        DispatcherQueue?.TryEnqueue(() => ApplyStateToUi());
    }

    public async Task RefreshAsync()
    {
        try
        {
            _prismService ??= App.Current?.Services?.GetService<IPrismService>();
            if (_prismService != null)
            {
                await _prismService.EnsureLoadedAsync();
                ApplyStateToUi();
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[PrismWidgetControl] Refresh warning: {ex.Message}");
        }
    }

    private void ApplyStateToUi()
    {
        if (_prismService == null)
        {
            return;
        }

        var clips = _prismService.Clips;
        var pins = _prismService.PinnedSites.Take(6).ToList();

        VaultCountBadgeText.Text = $"{clips.Count} Saved";
        SpeedDialItemsControl.ItemsSource = pins;

        var latest = clips.FirstOrDefault();
        if (latest != null)
        {
            LatestClipIcon.Glyph = latest.TypeGlyph;
            LatestClipTitleText.Text = latest.ClipType == PrismClipType.Quote && !string.IsNullOrWhiteSpace(latest.ContentText)
                ? $"\"{latest.ContentText}\""
                : latest.Title;
            LatestClipDomainText.Text = latest.Domain;
        }
        else
        {
            LatestClipIcon.Glyph = "\uF4A5";
            LatestClipTitleText.Text = "Browse with shared logins, clip quotes & images, and synthesize pages with Co-Pilot.";
            LatestClipDomainText.Text = string.Empty;
        }
    }

    private void SpeedDialButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.Tag is string targetUrl && !string.IsNullOrWhiteSpace(targetUrl))
        {
            var pin = (btn.DataContext as PrismPinnedSite);
            _prismService?.RequestOpenUrlInPrism(targetUrl, pin?.Title);
            if (App.Current?.MainWindow is MainWindow mw)
            {
                mw.NavigateToTab(10);
            }
        }
    }

    private void OpenPrismStudioButton_Click(object sender, RoutedEventArgs e)
    {
        if (App.Current?.MainWindow is MainWindow mw)
        {
            mw.NavigateToTab(10);
        }
    }
}
