using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Daily_WinUI.Services;
using Windows.Graphics;
using System;
using System.Runtime.InteropServices;

namespace Daily_WinUI;

public sealed partial class SettingsWindow : Window
{
    private readonly AppSettings _settings;

    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr hwnd);

    public SettingsWindow()
    {
        InitializeComponent();
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        AppWindow.SetIcon("Assets/AppIcon.ico");

        _settings = SettingsService.Load();

        AppWindow.Changed += AppWindow_Changed;
        this.Closed += SettingsWindow_Closed;

        RestorePosition();
        NavigateTo(typeof(Views.SettingsPage));
    }

    private void RestorePosition()
    {
        const string key = "SettingsWindow";
        if (_settings.DetailWindowPositions.TryGetValue(key, out var pos)
            && pos.Width > 0 && pos.Height > 0)
        {
            AppWindow.MoveAndResize(new RectInt32(pos.X, pos.Y, pos.Width, pos.Height));
        }
        else
        {
            var displayArea = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary);
            var workArea = displayArea.WorkArea;
            var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
            double scale = GetDpiForWindow(hwnd) / 96.0;
            int w = Math.Min((int)(900 * scale), workArea.Width);
            int h = Math.Min((int)(640 * scale), workArea.Height);
            int x = workArea.X + (workArea.Width  - w) / 2;
            int y = workArea.Y + (workArea.Height - h) / 2;
            AppWindow.MoveAndResize(new RectInt32(x, y, w, h));
        }
    }

    private void AppWindow_Changed(AppWindow sender, AppWindowChangedEventArgs args)
    {
        if (!args.DidPositionChange && !args.DidSizeChange) return;

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

        const string key = "SettingsWindow";
        var pos = sender.Position;
        _settings.DetailWindowPositions[key] = new DetailWindowPosition
        {
            X = pos.X, Y = pos.Y,
            Width = size.Width, Height = size.Height
        };
        SettingsService.Save(_settings);
    }

    private void SettingsWindow_Closed(object sender, WindowEventArgs args)
    {
        AppWindow.Changed -= AppWindow_Changed;
        this.Closed -= SettingsWindow_Closed;
        ExtendsContentIntoTitleBar = false;
        SetTitleBar(null);
        Content = null;
    }

    public void ApplyTheme(ElementTheme theme)
    {
        if (Content is FrameworkElement root)
            root.RequestedTheme = theme;
    }

    public void NavigateTo(Type pageType, object? parameter = null)
    {
        RootFrame.Navigate(pageType, parameter);
    }
}
