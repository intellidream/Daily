using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Extensions.DependencyInjection;
using Daily_WinUI.Services;

namespace Daily_WinUI.Views;

public sealed partial class LoginPage : Page
{
    private readonly WinUIAuthService _authService;

    public LoginPage()
    {
        InitializeComponent();
        _authService = App.Current.Services.GetRequiredService<WinUIAuthService>();
    }

    private async void GoogleSignInButton_Click(object sender, RoutedEventArgs e)
    {
        GoogleSignInButton.IsEnabled = false;
        SkipButton.IsEnabled = false;
        LoadingPanel.Visibility = Visibility.Visible;
        ErrorText.Visibility = Visibility.Collapsed;
        StatusText.Text = "Opening browser...";

        try
        {
            // Bounded wait on InitializationTask so background service hydration never hangs user interaction
            await Task.WhenAny(App.Current.InitializationTask, Task.Delay(1500));
            StatusText.Text = "Waiting for Google sign-in...";
            var success = await _authService.SignInWithGoogleAsync();

            if (success)
            {
                StatusText.Text = "Success! Loading dashboard...";
                await Task.Delay(500); // Brief pause so user sees success

                // Navigate to the main dashboard
                if (Frame != null)
                {
                    Frame.Navigate(typeof(MainPage));
                }
                else if (App.Current.MainWindow is MainWindow mw)
                {
                    mw.RootFrame.Navigate(typeof(MainPage));
                }
            }
            else
            {
                ErrorText.Text = "Sign-in was cancelled or failed. Please try again.";
                ErrorText.Visibility = Visibility.Visible;
                LoadingPanel.Visibility = Visibility.Collapsed;
                GoogleSignInButton.IsEnabled = true;
                SkipButton.IsEnabled = true;
            }
        }
        catch (Exception ex)
        {
            ErrorText.Text = $"Error: {ex.Message}";
            ErrorText.Visibility = Visibility.Visible;
            LoadingPanel.Visibility = Visibility.Collapsed;
            GoogleSignInButton.IsEnabled = true;
            SkipButton.IsEnabled = true;
        }
    }

    private async void SkipButton_Click(object sender, RoutedEventArgs e)
    {
        GoogleSignInButton.IsEnabled = false;
        SkipButton.IsEnabled = false;

        try
        {
            // Bounded wait on InitializationTask so guest skip is instantaneous
            await Task.WhenAny(App.Current.InitializationTask, Task.Delay(1000));

            // Navigate directly to the dashboard without signing in
            if (Frame != null)
            {
                Frame.Navigate(typeof(MainPage));
            }
            else if (App.Current.MainWindow is MainWindow mw)
            {
                mw.RootFrame.Navigate(typeof(MainPage));
            }
        }
        catch (System.Exception ex)
        {
            ErrorText.Text = $"Initialization failed: {ex.Message}";
            ErrorText.Visibility = Visibility.Visible;
            GoogleSignInButton.IsEnabled = true;
            SkipButton.IsEnabled = true;
        }
    }
}
