using Microsoft.UI.Xaml;
using Daily.Configuration;

namespace Daily_WinUI;

public partial class App : Application
{
    private Window? _window;
    public static Supabase.Client SupabaseClient { get; private set; } = null!;

    public App()
    {
        Syncfusion.Licensing.SyncfusionLicenseProvider.RegisterLicense(Secrets.SyncfusionLicenseKey);
        this.InitializeComponent();
    }

    protected override void OnLaunched(Microsoft.UI.Xaml.LaunchActivatedEventArgs args)
    {
        InitializeSupabaseAsync();
        _window = new MainWindow();
        _window.Activate();
    }

    private async void InitializeSupabaseAsync()
    {
        var options = new Supabase.SupabaseOptions
        {
            AutoConnectRealtime = true
        };
        SupabaseClient = new Supabase.Client(Secrets.SupabaseUrl, Secrets.SupabaseKey, options);
        await SupabaseClient.InitializeAsync();
    }
}
