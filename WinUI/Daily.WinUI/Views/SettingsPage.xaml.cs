using Microsoft.UI.Xaml.Controls;

namespace Daily_WinUI.Views;

public sealed partial class SettingsPage : Page
{
    // Maps nav item Tag → page type
    private static readonly System.Collections.Generic.Dictionary<string, System.Type> _pageMap = new()
    {
        { "DayOne",        typeof(AboutPage) },
        // Stub placeholders — replace with real pages when built
        { "General",       typeof(GeneralSettingsPage) },
        { "Appearance",    typeof(AppearanceSettingsPage) },
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
        // Select "General" by default
        foreach (var item in NavView.MenuItems)
        {
            if (item is NavigationViewItem navItem && navItem.Tag?.ToString() == "General")
            {
                NavView.SelectedItem = navItem;
                break;
            }
        }
        NavigateTo("General");
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
            try
            {
                ContentFrame.Navigate(pageType);
            }
            catch (System.Exception ex)
            {
                try
                {
                    string dir = System.IO.Path.Combine(System.Environment.GetFolderPath(System.Environment.SpecialFolder.LocalApplicationData), "DailyApp");
                    System.IO.Directory.CreateDirectory(dir);
                    System.IO.File.WriteAllText(System.IO.Path.Combine(dir, "nav_error.txt"), $"Navigation to {tag} ({pageType?.FullName}) failed:\n{ex}");
                }
                catch { }
                System.Diagnostics.Debug.WriteLine($"[SettingsPage] Navigation failed to {tag}: {ex}");
            }
        }
    }
}
