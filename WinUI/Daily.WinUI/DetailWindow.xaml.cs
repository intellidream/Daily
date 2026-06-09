using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Daily_WinUI.Services;
using Windows.Graphics;
using System;
using System.Runtime.InteropServices;
using Daily_WinUI.Views;
using Microsoft.UI.Dispatching;

namespace Daily_WinUI;

public sealed partial class DetailWindow : Window
{
    private readonly AppSettings _settings;
    private string? _pageKey;
    private string _currentSectionName = "Detail";

    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr hwnd);

    public DetailWindow()
    {
        InitializeComponent();
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        AppWindow.SetIcon("Assets/AppIcon.ico");

        _settings = SettingsService.Load();

        AppWindow.Changed += AppWindow_Changed;
        this.Closed += DetailWindow_Closed;

        UpdateSectionTitleBar("Detail");

        if (this.Content is UIElement rootContent)
        {
            rootContent.AddHandler(UIElement.PointerPressedEvent, new Microsoft.UI.Xaml.Input.PointerEventHandler(OnPointerPressed), true);
        }
    }

    private void OnPointerPressed(object sender, Microsoft.UI.Xaml.Input.PointerRoutedEventArgs e)
    {
        if (this.Content is UIElement root)
        {
            Daily_WinUI.Helpers.NavigationHelper.HandleMouseNavigation(root, e);
        }
    }

    /// <summary>
    /// Call immediately after construction to restore the saved position for this page type.
    /// </summary>
    public void RestorePosition(string pageKey)
    {
        _pageKey = pageKey;
        UpdateSectionTitleBar(MapSectionNameFromPageKey(pageKey));

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

    private void DetailWindow_Closed(object sender, WindowEventArgs args)
    {
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
        RootFrame.RequestedTheme = theme;
    }

    public void NavigateTo(Type pageType, object parameter = null)
    {
        try
        {
            RootFrame.Navigate(pageType, parameter);
            UpdateSectionTitleBar(MapSectionNameFromPageType(pageType));
        }
        catch (Exception ex)
        {
            System.IO.File.WriteAllText("crash_log.txt", ex.ToString());
            throw;
        }
    }

    private void AppTitleBar_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        var inset = AppWindow.TitleBar?.RightInset ?? 140;
        RightPaddingColumn.Width = new GridLength(Math.Max(140, inset));
    }

    private static string MapSectionNameFromPageKey(string pageKey)
    {
        if (string.IsNullOrWhiteSpace(pageKey)) return "Detail";
        var key = pageKey.ToLowerInvariant();
        if (key.Contains("weather")) return "Weather";
        if (key.Contains("habits")) return "Habits";
        if (key.Contains("health")) return "Health";
        if (key.Contains("finance")) return "Finances";
        if (key.Contains("rss") || key.Contains("news")) return "News";
        if (key.Contains("calendar")) return "Calendar";
        return "Detail";
    }

    private static string MapSectionNameFromPageType(Type pageType)
    {
        if (pageType == typeof(WeatherDetailPage)) return "Weather";
        if (pageType == typeof(HabitsDetailPage)) return "Habits";
        if (pageType == typeof(HealthDetailPage)) return "Health";
        if (pageType == typeof(FinancesDetailPage)) return "Finances";
        if (pageType == typeof(RssFeedDetailPage)) return "News";
        if (pageType == typeof(CalendarDetailPage)) return "Calendar";
        return "Detail";
    }

    private static string GetSectionGlyph(string section)
    {
        // Match each page's top-bar icon exactly
        return section switch
        {
            "Weather" => "\uE753",  // WeatherDetailPage top icon
            "Habits" => "\uED23",   // HabitsDetailPage top icon (Tabler)
            "Health" => "\uE95E",   // HealthDetailPage top icon
            "Finances" => "\uE825", // FinancesDetailPage top icon
            "News" => "\uE736",     // RssFeedDetailPage top icon
            "Calendar" => "\uE787", // CalendarDetailPage top icon
            _ => "\uE706"
        };
    }

    private void UpdateSectionTitleBar(string section)
    {
        _currentSectionName = section;
        DetailTitleBarSectionText.Text = $"DayOne - {section}";
        DetailTitleBarSectionIcon.Glyph = GetSectionGlyph(section);
        DetailTitleBarSectionIcon.FontFamily = section == "Habits"
            ? (Microsoft.UI.Xaml.Media.FontFamily)Application.Current.Resources["TablerIconsFont"]
            : new Microsoft.UI.Xaml.Media.FontFamily("Segoe Fluent Icons");
    }

    private async void DetailTitleBarRefreshButton_Click(object sender, RoutedEventArgs e)
    {
        DetailTitleBarRefreshButton.IsEnabled = false;
        try
        {
            if (RootFrame.Content is WeatherDetailPage weatherPage)
            {
                await weatherPage.RefreshFromTitleBarAsync();
            }
            else if (RootFrame.Content is HabitsDetailPage habitsPage)
            {
                await habitsPage.RefreshFromTitleBarAsync();
            }
            else if (RootFrame.Content is HealthDetailPage healthPage)
            {
                await healthPage.RefreshFromTitleBarAsync();
            }
            else if (RootFrame.Content is FinancesDetailPage financesPage)
            {
                await financesPage.RefreshFromTitleBarAsync();
            }
            else if (RootFrame.Content is RssFeedDetailPage newsPage)
            {
                await newsPage.RefreshFromTitleBarAsync();
            }
            else if (RootFrame.Content is CalendarDetailPage calendarPage)
            {
                await calendarPage.RefreshFromTitleBarAsync();
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[DetailWindow] Refresh failed for {_currentSectionName}: {ex}");
        }
        finally
        {
            DetailTitleBarRefreshButton.IsEnabled = true;
        }
    }
}
