using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;
using Daily_WinUI.Services;
using Windows.Graphics;

// To learn more about WinUI, the WinUI project structure,
// and more about our project templates, see: http://aka.ms/winui-project-info.

namespace Daily_WinUI;

public sealed partial class MainWindow : Window
{
    private readonly AppSettings _settings;
    private DispatcherTimer? _dateTimer;

    public MainWindow()
    {
        InitializeComponent();
        _settings = SettingsService.Load();

        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);

        AppWindow.SetIcon("Assets/AppIcon.ico");
        AppWindow.Title = "DayOne";
        ConfigureStartupWindow();

        StartDateClock();

        _ = NavigateAfterHydrationAsync();

        AppWindow.Changed += AppWindow_Changed;
        Closed += MainWindow_Closed;
    }

    // ── Title bar user state ──────────────────────────────────────────────────

    /// <summary>Called by MainPage after auth state changes to update title bar profile.</summary>
    public void UpdateTitleBarUser(string email, string displayName, string? avatarUrl, bool isAuthenticated)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            if (AppTitleBar.RightHeader is StackPanel outer)
            {
                // Account button is the second child of the outer StackPanel
                var accountBtn = outer.Children.Count > 1 ? outer.Children[1] as Button : null;
                if (accountBtn?.Content is StackPanel sp)
                {
                    if (sp.Children[0] is PersonPicture avatar)
                    {
                        avatar.DisplayName = isAuthenticated ? (displayName ?? "U") : "?";
                        avatar.ProfilePicture = null;
                        if (isAuthenticated && !string.IsNullOrEmpty(avatarUrl))
                            avatar.ProfilePicture = new BitmapImage(new System.Uri(avatarUrl));
                    }
                    if (sp.Children[1] is TextBlock emailText)
                        emailText.Text = isAuthenticated ? (email ?? "Signed in") : "Not signed in";
                }
                if (accountBtn?.Flyout is MenuFlyout flyout &&
                    flyout.Items.Count > 0 &&
                    flyout.Items[0] is MenuFlyoutItem item)
                    item.Text = isAuthenticated ? "Sign Out" : "Sign In";
            }
        });
    }

    /// <summary>Called by MainPage after a theme toggle to sync the title bar button icon/text.</summary>
    public void UpdateThemeIcon(bool isDark)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            if (AppTitleBar.RightHeader is StackPanel outer &&
                outer.Children.Count > 0 &&
                outer.Children[0] is Button themeBtn &&
                themeBtn.Content is StackPanel sp)
            {
                if (sp.Children[0] is FontIcon icon)
                    icon.Glyph = isDark ? "\uE708" : "\uE706"; // moon : sun
                if (sp.Children[1] is TextBlock text)
                    text.Text = isDark ? "Light" : "Dark";
            }
        });
    }

    // ── Date clock ────────────────────────────────────────────────────────────

    private void StartDateClock()
    {
        UpdateDateText();
        _dateTimer = new DispatcherTimer { Interval = TimeSpan.FromMinutes(1) };
        _dateTimer.Tick += (_, _) => UpdateDateText();
        _dateTimer.Start();
    }

    private void UpdateDateText()
    {
        if (AppTitleBar.Content is TextBlock tb)
            tb.Text = DateTime.Now.ToString("dddd, MMMM d");
    }

    // ── Theme toggle handler ──────────────────────────────────────────────────

    private void TitleBarTheme_Click(object sender, RoutedEventArgs e)
    {
        if (RootFrame.Content is MainPage mainPage)
            mainPage.ApplyThemeToggle();
    }

    // ── Sign-out flyout handler ───────────────────────────────────────────────

    private async void TitleBarSignOut_Click(object sender, RoutedEventArgs e)
    {
        // Delegate to the currently active MainPage if present
        if (RootFrame.Content is MainPage mainPage)
            await mainPage.HandleSignOutAsync();
    }

    // ── Navigation after auth hydration ──────────────────────────────────────

    private async Task NavigateAfterHydrationAsync()
    {
        await App.Current.InitializationTask;

        var authService = Microsoft.Extensions.DependencyInjection.ServiceProviderServiceExtensions
            .GetRequiredService<WinUIAuthService>(App.Current.Services);

        DispatcherQueue.TryEnqueue(() =>
        {
            if (authService.IsAuthenticated)
                RootFrame.Navigate(typeof(MainPage));
            else
                RootFrame.Navigate(typeof(Views.LoginPage));
        });
    }

    // ── Window management ─────────────────────────────────────────────────────

    private void ConfigureStartupWindow()
    {
        if (AppWindow.Presenter is OverlappedPresenter overlappedPresenter)
        {
            overlappedPresenter.IsResizable = true;
            overlappedPresenter.IsMaximizable = true;
            overlappedPresenter.IsMinimizable = true;
        }

        if (_settings.HasWindowPosition && _settings.WindowWidth > 0 && _settings.WindowHeight > 0)
        {
            AppWindow.MoveAndResize(new RectInt32(_settings.WindowX, _settings.WindowY, _settings.WindowWidth, _settings.WindowHeight));
            return;
        }

        var displayArea = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary);
        var workArea = displayArea.WorkArea;

        var width = Math.Min(600, workArea.Width);
        var height = Math.Min(800, workArea.Height);
        var x = workArea.X + (workArea.Width - width) / 2;
        var y = workArea.Y + (workArea.Height - height) / 2;

        AppWindow.MoveAndResize(new RectInt32(x, y, width, height));
    }

    private void AppWindow_Changed(AppWindow sender, AppWindowChangedEventArgs args)
    {
        if (!args.DidPositionChange && !args.DidSizeChange) return;

        var bounds = sender.Position;
        var size = sender.Size;
        _settings.WindowX = bounds.X;
        _settings.WindowY = bounds.Y;
        _settings.WindowWidth = size.Width;
        _settings.WindowHeight = size.Height;
        _settings.HasWindowPosition = true;
    }

    private void MainWindow_Closed(object sender, WindowEventArgs args)
    {
        _dateTimer?.Stop();
        SettingsService.Save(_settings);
    }
}
