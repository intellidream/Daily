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
        // OpenDetailWindow(typeof(RssFeedDetailPage)); // To be implemented
    }

    private void HealthWidget_Tapped(object sender, TappedRoutedEventArgs e)
    {
        // OpenDetailWindow(typeof(HealthDetailPage)); // To be implemented
    }

    private void OpenDetailWindow(System.Type pageType)
    {
        if (_openWindows.TryGetValue(pageType, out var existingWindow))
        {
            existingWindow.Activate();
            return;
        }

        var window = new DetailWindow();
        
        window.Closed += (s, e) => 
        {
            _openWindows.Remove(pageType);
        };
        
        _openWindows[pageType] = window;
        
        window.NavigateTo(pageType);
        window.Activate();
    }
}
