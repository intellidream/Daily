using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Daily_WinUI.Views;
using System.Collections.Generic;
using System.Linq;

namespace Daily_WinUI;

public sealed partial class MainPage : Page
{
    private readonly Dictionary<System.Type, DetailWindow> _openWindows = new();

    public MainPage()
    {
        InitializeComponent();
        RssFeedWidget.ArticleTapped += RssFeedWidget_ArticleTapped;
    }

    private void WeatherWidget_Tapped(object sender, TappedRoutedEventArgs e)
    {
        OpenDetailWindow(typeof(WeatherDetailPage));
    }

    private void FinancesWidget_Tapped(object sender, TappedRoutedEventArgs e)
    {
        // OpenDetailWindow(typeof(FinancesDetailPage)); // To be implemented
    }

    private void HabitsWidget_Tapped(object sender, TappedRoutedEventArgs e)
    {
        // OpenDetailWindow(typeof(HabitsDetailPage)); // To be implemented
    }

    private void RssFeedWidget_Tapped(object sender, TappedRoutedEventArgs e)
    {
        // OpenDetailWindow(typeof(RssFeedDetailPage));
    }

    private void RssFeedWidget_ArticleTapped(object? sender, Daily.Models.RssItem article)
    {
        OpenDetailWindow(typeof(Views.RssFeedDetailPage), article);
    }

    private void HealthWidget_Tapped(object sender, TappedRoutedEventArgs e)
    {
        // OpenDetailWindow(typeof(HealthDetailPage)); // To be implemented
    }

    private void OpenDetailWindow(System.Type pageType, object parameter = null)
    {
        if (_openWindows.TryGetValue(pageType, out var existingWindow))
        {
            if (parameter != null)
            {
                // If window is already open, we might want to navigate it to the new item
                existingWindow.NavigateTo(pageType, parameter);
            }
            existingWindow.Activate();
            return;
        }

        var window = new DetailWindow();
        
        window.Closed += (s, ev) => 
        {
            _openWindows.Remove(pageType);
        };
        
        _openWindows[pageType] = window;
        
        window.NavigateTo(pageType, parameter);
        window.Activate();
    }
}
