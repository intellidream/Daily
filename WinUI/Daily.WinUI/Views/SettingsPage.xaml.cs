using Microsoft.UI.Xaml.Controls;

namespace Daily_WinUI.Views;

public sealed partial class SettingsPage : Page
{
    // Maps nav item Tag → page type
    private static readonly System.Collections.Generic.Dictionary<string, System.Type> _pageMap = new()
    {
        { "DayOne",        typeof(AboutPage) },
        // Stub placeholders — replace with real pages when built
        { "Features",      typeof(FeaturesPage) },
        { "Appearance",    typeof(AppearanceSettingsPage) },
        { "Notifications", typeof(AboutPage) },
        { "Cosmos",        typeof(CosmosSettingsPage) },
        { "Account",       typeof(AboutPage) },
        { "Data",          typeof(DataSyncSettingsPage) },
        { "Debug",         typeof(DebugSettingsPage) },
    };

    private string _initialTag = "Features";

    public SettingsPage()
    {
        InitializeComponent();
        Loaded += SettingsPage_Loaded;
    }

    protected override void OnNavigatedTo(Microsoft.UI.Xaml.Navigation.NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        if (e.Parameter is string requestedTag && _pageMap.ContainsKey(requestedTag))
        {
            _initialTag = requestedTag;
        }
    }

    private void SettingsPage_Loaded(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        foreach (var item in NavView.MenuItems)
        {
            if (item is NavigationViewItem navItem && navItem.Tag?.ToString() == _initialTag)
            {
                NavView.SelectedItem = navItem;
                break;
            }
        }
        NavigateTo(_initialTag);
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
