using Microsoft.UI.Xaml.Controls;

namespace Daily_WinUI.Views;

public sealed partial class SettingsPage : Page
{
    // Maps nav item Tag → page type
    private static readonly System.Collections.Generic.Dictionary<string, System.Type> _pageMap = new()
    {
        { "DayOne",        typeof(AboutPage) },
        // Stub placeholders — replace with real pages when built
        { "Appearance",    typeof(GeneralSettingsPage) },
        { "Notifications", typeof(AboutPage) },
        { "Account",       typeof(AboutPage) },
        { "Data",          typeof(AboutPage) },
    };

    public SettingsPage()
    {
        InitializeComponent();
        Loaded += SettingsPage_Loaded;
    }

    private void SettingsPage_Loaded(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        // Select "DayOne" by default
        NavView.SelectedItem = NavAbout;
        NavigateTo("DayOne");
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
