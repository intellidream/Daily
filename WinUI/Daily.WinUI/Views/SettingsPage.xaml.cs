using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media.Imaging;

namespace Daily_WinUI.Views;

public sealed partial class SettingsPage : Page
{
    // Maps nav item Tag → page type
    private static readonly System.Collections.Generic.Dictionary<string, System.Type> _pageMap = new()
    {
        { "DayOne",        typeof(AboutPage) },
        // Stub placeholders — replace with real pages when built
        { "Appearance",    typeof(AboutPage) },
        { "Notifications", typeof(AboutPage) },
        { "Account",       typeof(AboutPage) },
        { "Data",          typeof(AboutPage) },
    };

    public SettingsPage()
    {
        InitializeComponent();
        Loaded += SettingsPage_Loaded;
        ActualThemeChanged += SettingsPage_ThemeChanged;
    }

    private void SettingsPage_Loaded(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        // Select "DayOne" by default
        NavView.SelectedItem = NavAbout;
        NavigateTo("DayOne");

        // Set theme-aware icon
        UpdateDayOneIcon();
    }

    private void SettingsPage_ThemeChanged(FrameworkElement sender, object args)
    {
        UpdateDayOneIcon();
    }

    private void UpdateDayOneIcon()
    {
        var isDark = ActualTheme == ElementTheme.Dark;
        var iconPath = isDark
            ? "ms-appx:///Assets/appicon.theme-dark.svg"
            : "ms-appx:///Assets/appicon.theme-light.svg";
        DayOneIconSource.UriSource = new System.Uri(iconPath);
    }

    private void NavView_ItemInvoked(NavigationView sender, NavigationViewItemInvokedEventArgs args)
    {
        if (args.InvokedItemContainer is NavigationViewItem item && item.Tag is string tag)
            NavigateTo(tag);
    }

    private void NavigateTo(string tag)
    {
        if (_pageMap.TryGetValue(tag, out var pageType) &&
            ContentFrame.CurrentSourcePageType != pageType)
        {
            ContentFrame.Navigate(pageType);
        }
    }
}
