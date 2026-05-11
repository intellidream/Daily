using Microsoft.UI.Xaml;
using Daily.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace Daily_WinUI;

public partial class App : Application
{
    private Window? _window;
    public static Supabase.Client SupabaseClient { get; private set; } = null!;
    public IServiceProvider Services { get; private set; } = null!;
    public static new App Current => (App)Application.Current;

    public App()
    {
        Syncfusion.Licensing.SyncfusionLicenseProvider.RegisterLicense(Secrets.SyncfusionLicenseKey);
        this.InitializeComponent();
    }

    protected override void OnLaunched(Microsoft.UI.Xaml.LaunchActivatedEventArgs args)
    {
        var services = new Microsoft.Extensions.DependencyInjection.ServiceCollection();
        ConfigureServices(services);
        Services = services.BuildServiceProvider();

        _window = new MainWindow();
        _window.Activate();

        _ = InitializeAsync(); // Run startup without blocking UI thread
    }

    private void ConfigureServices(Microsoft.Extensions.DependencyInjection.IServiceCollection services)
    {
        var options = new Supabase.SupabaseOptions
        {
            AutoConnectRealtime = true,
            SessionHandler = new Daily_WinUI.Services.WinUISessionPersistence()
        };
        SupabaseClient = new Supabase.Client(Secrets.SupabaseUrl, Secrets.SupabaseKey, options);
        services.AddSingleton(SupabaseClient);

        // Core Services
        services.AddSingleton<Daily.Services.IDatabaseService, Daily.Services.DatabaseService>();
        services.AddSingleton<Daily.Services.ISyncService, Daily.Services.SyncService>();
        services.AddSingleton<Daily.Services.IRssFeedService, Daily.Services.RssFeedService>();
        services.AddSingleton<Daily.Services.SeederService>();
        
        // Dummy services to satisfy SyncService dependencies
        services.AddSingleton<Daily.Services.Health.IHealthService, Daily_WinUI.Services.MockHealthService>();
    }

    private async Task InitializeAsync()
    {
        await SupabaseClient.InitializeAsync();

        // Manual Hydration
        if (SupabaseClient.Auth.CurrentSession == null)
        {
            var persistence = new Daily_WinUI.Services.WinUISessionPersistence();
            var session = persistence.LoadSession();
            if (session != null && !string.IsNullOrEmpty(session.AccessToken))
            {
                try { await SupabaseClient.Auth.SetSession(session.AccessToken, session.RefreshToken); }
                catch { }
            }
        }

        // Initialize Database & Start Background Sync
        var db = Services.GetRequiredService<Daily.Services.IDatabaseService>();
        await db.InitializeAsync();

        var userId = SupabaseClient.Auth.CurrentSession?.User?.Id ?? "local_user";
        var seeder = Services.GetRequiredService<Daily.Services.SeederService>();
        await seeder.SeedRssFeedsAsync(userId);

        // Re-initialize feeds in memory to reflect the newly seeded database entries
        var rssService = Services.GetRequiredService<Daily.Services.IRssFeedService>();
        await rssService.InitializeCustomFeedsAsync();

        if (SupabaseClient.Auth.CurrentSession != null)
        {
            var syncService = Services.GetRequiredService<Daily.Services.ISyncService>();
            syncService.StartBackgroundSync();
        }
    }
}
