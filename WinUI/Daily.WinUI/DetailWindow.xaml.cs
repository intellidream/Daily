using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Daily_WinUI.Services;
using Windows.Graphics;
using System;
using System.Runtime.InteropServices;

namespace Daily_WinUI;

public sealed partial class DetailWindow : Window
{
    private readonly AppSettings _settings;
    private string? _pageKey;

    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr hwnd);

    public DetailWindow()
    {
        InitializeComponent();
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        AppWindow.SetIcon("Assets/AppIcon.ico");

        _settings = SettingsService.Load();

        WeatherBannerService.WeatherConditionChanged += OnWeatherConditionChanged;
        if (WeatherBannerService.LastIconCode is { } code)
            OnWeatherConditionChanged(code);

        AppWindow.Changed += AppWindow_Changed;
        this.Closed += DetailWindow_Closed;
    }

    /// <summary>
    /// Call immediately after construction to restore the saved position for this page type.
    /// </summary>
    public void RestorePosition(string pageKey)
    {
        _pageKey = pageKey;

        if (_settings.DetailWindowPositions.TryGetValue(pageKey, out var pos)
            && pos.Width > 0 && pos.Height > 0)
        {
            AppWindow.MoveAndResize(new RectInt32(pos.X, pos.Y, pos.Width, pos.Height));
        }
        else
        {
            // Default: same footprint as the main window (1380×790 logical px), fully centred
            var displayArea = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary);
            var workArea = displayArea.WorkArea;
            var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
            double scale = GetDpiForWindow(hwnd) / 96.0;
            int w = Math.Min((int)(1380 * scale), workArea.Width);
            int h = Math.Min((int)(790  * scale), workArea.Height);
            int x = workArea.X + (workArea.Width  - w) / 2;
            int y = workArea.Y + (workArea.Height - h) / 2;
            AppWindow.MoveAndResize(new RectInt32(x, y, w, h));
        }
    }

    private void AppWindow_Changed(AppWindow sender, AppWindowChangedEventArgs args)
    {
        if (!args.DidPositionChange && !args.DidSizeChange) return;

        // Enforce minimum size
        double scale = this.Content?.XamlRoot?.RasterizationScale ?? 1.0;
        int minPx = (int)(500 * scale);
        var size = sender.Size;
        if (size.Width < minPx || size.Height < minPx)
        {
            sender.ResizeClient(new SizeInt32(
                Math.Max(size.Width,  minPx),
                Math.Max(size.Height, minPx)));
            return;
        }

        // Persist position for this page type
        if (_pageKey is not null)
        {
            var pos = sender.Position;
            _settings.DetailWindowPositions[_pageKey] = new DetailWindowPosition
            {
                X = pos.X, Y = pos.Y,
                Width = size.Width, Height = size.Height
            };
            SettingsService.Save(_settings);
        }
    }

    private void OnWeatherConditionChanged(string iconCode)
    {
        DispatcherQueue.TryEnqueue(Microsoft.UI.Dispatching.DispatcherQueuePriority.Normal, () =>
        {
            TopBarBanner.SetCondition(iconCode);
        });
    }

    private void DetailWindow_Closed(object sender, WindowEventArgs args)
    {
        WeatherBannerService.WeatherConditionChanged -= OnWeatherConditionChanged;
        AppWindow.Changed -= AppWindow_Changed;
        this.Closed -= DetailWindow_Closed;
        ExtendsContentIntoTitleBar = false;
        SetTitleBar(null);
        Content = null;
    }

    public void ApplyTheme(ElementTheme theme)
    {
        if (Content is FrameworkElement root)
            root.RequestedTheme = theme;
    }

    public void NavigateTo(Type pageType, object parameter = null)
    {
        try
        {
            RootFrame.Navigate(pageType, parameter);
        }
        catch (Exception ex)
        {
            System.IO.File.WriteAllText("crash_log.txt", ex.ToString());
            throw;
        }
    }
}
