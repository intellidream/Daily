using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Daily_WinUI.Views;
using Daily_WinUI.Services;
using System.Collections.Generic;
using System.Linq;
using Microsoft.Extensions.DependencyInjection;

namespace Daily_WinUI;

public sealed partial class MainPage : Page
{
    private readonly Dictionary<System.Type, DetailWindow> _openWindows = new();
    private readonly WinUIAuthService _authService;

    public MainPage()
    {
        InitializeComponent();
        _authService = App.Current.Services.GetRequiredService<WinUIAuthService>();
        RssFeedWidget.ArticleTapped += RssFeedWidget_ArticleTapped;
        Loaded += MainPage_Loaded;
    }

    private void MainPage_Loaded(object sender, RoutedEventArgs e)
    {
        UpdateUserUI();
    }

    private void UpdateUserUI()
    {
        if (_authService.IsAuthenticated)
        {
            UserEmailText.Text = _authService.CurrentUserEmail ?? "Signed in";
            UserAvatar.DisplayName = _authService.CurrentUserEmail?.Split('@').FirstOrDefault() ?? "U";
            if (!string.IsNullOrEmpty(_authService.CurrentUserAvatarUrl))
            {
                UserAvatar.ProfilePicture = new Microsoft.UI.Xaml.Media.Imaging.BitmapImage(
                    new System.Uri(_authService.CurrentUserAvatarUrl));
            }
            SignOutItem.Text = "Sign Out";
        }
        else
        {
            UserEmailText.Text = "Not signed in";
            UserAvatar.DisplayName = "?";
            SignOutItem.Text = "Sign In";
        }
    }

    private async void SignOut_Click(object sender, RoutedEventArgs e)
    {
        if (_authService.IsAuthenticated)
        {
            await _authService.SignOutAsync();
            // Navigate back to login
            if (Frame != null)
            {
                Frame.Navigate(typeof(LoginPage));
            }
        }
        else
        {
            // Navigate to login
            if (Frame != null)
            {
                Frame.Navigate(typeof(LoginPage));
            }
        }
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
