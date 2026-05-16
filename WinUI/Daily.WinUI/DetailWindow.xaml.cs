using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Daily_WinUI.Services;
using Windows.Graphics;
using System;

namespace Daily_WinUI;

public sealed partial class DetailWindow : Window
{
    public DetailWindow()
    {
        InitializeComponent();
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        AppWindow.SetIcon("Assets/AppIcon.ico");

        // Subscribe for future updates, then replay the last known condition immediately
        WeatherBannerService.WeatherConditionChanged += OnWeatherConditionChanged;
        if (WeatherBannerService.LastIconCode is { } code)
            OnWeatherConditionChanged(code);
        this.Closed += DetailWindow_Closed;
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
