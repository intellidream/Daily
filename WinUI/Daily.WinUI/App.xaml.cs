using Microsoft.UI.Xaml;
using Daily.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace Daily_WinUI;

public partial class App : Application
{
    private Window? _window;
    public MainWindow? MainWindow => _window as MainWindow;
    public static Supabase.Client SupabaseClient { get; private set; } = null!;
    public IServiceProvider Services { get; private set; } = null!;
    public static new App Current => (App)Application.Current;

    /// <summary>
    /// Custom entry point. Runs BEFORE the WinUI Application is created.
    ///  1. Registers the protocol for the current unpackaged exe.
    ///  2. Single-instance gate – a second process redirects and returns immediately.
    ///  3. Subscribes to Activated so the running instance receives the callback.
    /// </summary>
    [System.STAThreadAttribute]
    static void Main(string[] args)
    {
        WinRT.ComWrappersSupport.InitializeComWrappers();

        // ── Register protocol for the unpackaged exe ──
        // Writes HKCU\Software\Classes\com.intellidream.daily\shell\open\command
        // pointing at the CURRENT executable. Idempotent.
        Microsoft.Windows.AppLifecycle.ActivationRegistrationManager
            .RegisterForProtocolActivation(
                "com.intellidream.daily.desktop",
                "",
                "Daily Dashboard (Desktop)",
                System.Environment.ProcessPath ?? "");

        // ── Single-Instance gate ──
        var mainInstance =
            Microsoft.Windows.AppLifecycle.AppInstance.FindOrRegisterForKey("DailyWinUIMainInstance");

        if (!mainInstance.IsCurrent)
        {
            // Another instance owns the key – redirect the activation and exit.
            var activationArgs =
                Microsoft.Windows.AppLifecycle.AppInstance.GetCurrent().GetActivatedEventArgs();
            mainInstance.RedirectActivationToAsync(activationArgs).AsTask().Wait();
            return;
        }

        // ── Wire Activated BEFORE Application.Start so no redirects are lost ──
        mainInstance.Activated += OnAppInstanceActivated;

        // ── Main instance – start normally ──
        Microsoft.UI.Xaml.Application.Start((p) =>
        {
            var context = new Microsoft.UI.Dispatching.DispatcherQueueSynchronizationContext(
                Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread());
            System.Threading.SynchronizationContext.SetSynchronizationContext(context);
            new App();
        });
    }

    public App() { this.UnhandledException += (s, e) => { Console.WriteLine("UNHANDLED XAML EXCEPTION: " + e.Exception); e.Handled = true; }; AppDomain.CurrentDomain.UnhandledException += (s, e) => { Console.WriteLine("UNHANDLED APPDOMAIN EXCEPTION: " + e.ExceptionObject); };
        Syncfusion.Licensing.SyncfusionLicenseProvider.RegisterLicense(Secrets.SyncfusionLicenseKey);
        this.InitializeComponent();
    }

    protected override void OnLaunched(Microsoft.UI.Xaml.LaunchActivatedEventArgs args)
    {
        var services = new Microsoft.Extensions.DependencyInjection.ServiceCollection();
        ConfigureServices(services);
        Services = services.BuildServiceProvider();

        // Start initialization FIRST so the task is available to be awaited
        InitializationTask = InitializeAsync();

        _window = new MainWindow();
        _window.Activate();

        // Handle initial launch activation (covers cold-start via protocol click)
        var appActivatedArgs = Microsoft.Windows.AppLifecycle.AppInstance.GetCurrent().GetActivatedEventArgs();
        HandleActivation(appActivatedArgs);
    }

    public Task InitializationTask { get; private set; } = Task.CompletedTask;

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
        services.AddSingleton<Daily.Services.ISeederService, Daily.Services.SeederService>();
        services.AddSingleton<Daily.Services.ISettingsService, Daily.Services.SettingsService>();
        services.AddSingleton<Daily_WinUI.Services.WinUIAuthService>();
        services.AddSingleton<Daily_WinUI.Services.WinUIWidgetService>();
        services.AddSingleton<Daily.Services.IHabitsRepository, Daily.Services.HabitsRepository>();
        services.AddSingleton<Daily.Services.IHabitsService, Daily.Services.HabitsService>();
        services.AddSingleton<Daily.Services.IRefreshService, Daily.Services.RefreshService>();
        
        // Dummy services to satisfy SyncService dependencies
        services.AddSingleton<Daily.Services.Health.INativeHealthStore, Daily.Services.Health.MockNativeHealthStore>();
        services.AddSingleton<Microsoft.Extensions.Logging.ILogger<Daily.Services.Health.SupabaseHealthService>>(Microsoft.Extensions.Logging.Abstractions.NullLogger<Daily.Services.Health.SupabaseHealthService>.Instance);
        services.AddSingleton<Daily.Services.Health.IHealthService, Daily.Services.Health.SupabaseHealthService>();
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

        // CRITICAL: Guarantee SettingsService is fully hydrated BEFORE the UI loads and asks for widgets!
        // This solves the race condition where the dashboard falls back to default sizes/positions on startup.
        var settingsService = Services.GetRequiredService<Daily.Services.ISettingsService>();
        await settingsService.InitializeAsync();

        var userId = SupabaseClient.Auth.CurrentSession?.User?.Id ?? "local_user";
        var seeder = Services.GetRequiredService<Daily.Services.ISeederService>();
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

    /// <summary>
    /// Fires on a background thread when a second process redirects its activation here.
    /// </summary>
    private static void OnAppInstanceActivated(object? sender, Microsoft.Windows.AppLifecycle.AppActivationArguments e)
    {
        HandleActivation(e);
    }

    /// <summary>
    /// Parses the protocol URI for the OAuth code and sets the TCS on WinUIAuthService.
    /// </summary>
    internal static void HandleActivation(Microsoft.Windows.AppLifecycle.AppActivationArguments args)
    {
        if (args.Kind == Microsoft.Windows.AppLifecycle.ExtendedActivationKind.Protocol)
        {
            var protocolArgs = args.Data as Windows.ApplicationModel.Activation.IProtocolActivatedEventArgs;
            if (protocolArgs != null)
            {
                System.Diagnostics.Debug.WriteLine($"[WinUIAuth] Protocol Activated: {protocolArgs.Uri}");
                var uri = protocolArgs.Uri;

                var code = "";
                string queryToParse = "";

                if (!string.IsNullOrEmpty(uri.Query)) queryToParse = uri.Query.TrimStart('?');
                else if (!string.IsNullOrEmpty(uri.Fragment)) queryToParse = uri.Fragment.TrimStart('#');

                System.Diagnostics.Debug.WriteLine($"[WinUIAuth] Query to parse: {queryToParse}");

                if (!string.IsNullOrEmpty(queryToParse))
                {
                    var parts = queryToParse.Split('&');
                    foreach (var part in parts)
                    {
                        var kv = part.Split('=');
                        if (kv.Length == 2 && kv[0] == "code")
                        {
                            code = System.Net.WebUtility.UrlDecode(kv[1]);
                            System.Diagnostics.Debug.WriteLine("[WinUIAuth] Code found!");
                            break;
                        }
                    }
                }

                if (!string.IsNullOrEmpty(code))
                {
                    var tcs = Daily_WinUI.Services.WinUIAuthService.GoogleAuthTcs;
                    if (tcs != null && !tcs.Task.IsCompleted)
                    {
                        System.Diagnostics.Debug.WriteLine("[WinUIAuth] Setting TCS Result...");
                        tcs.TrySetResult(code);
                    }
                    else
                    {
                        System.Diagnostics.Debug.WriteLine($"[WinUIAuth] TCS is null or already completed! (tcs null: {tcs == null})");
                    }
                }
                else
                {
                    System.Diagnostics.Debug.WriteLine("[WinUIAuth] No code found in URI.");
                }

                // Bring window to front
                var handle = System.Diagnostics.Process.GetCurrentProcess().MainWindowHandle;
                if (handle != IntPtr.Zero)
                {
                    ShowWindow(handle, 9); // SW_RESTORE
                    SetForegroundWindow(handle);
                }
            }
        }
    }

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    [return: System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.Bool)]
    static extern bool SetForegroundWindow(IntPtr hWnd);

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}


