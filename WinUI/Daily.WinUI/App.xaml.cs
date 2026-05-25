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

        // ── Single-Instance gate via named Mutex + named pipe for URI forwarding ──
        const string MutexName   = "DailyWinUI_SingleInstance_Mutex";
        const string PipeName    = "DailyWinUI_ProtocolPipe";

        bool createdNew;
        var mutex = new System.Threading.Mutex(true, MutexName, out createdNew);

        if (!createdNew)
        {
            // Another instance is running. If we were launched by a protocol URL,
            // forward it via named pipe so the running instance can handle it.
            var activationArgs = Microsoft.Windows.AppLifecycle.AppInstance
                .GetCurrent().GetActivatedEventArgs();

            string? uriToForward = null;
            if (activationArgs.Kind == Microsoft.Windows.AppLifecycle.ExtendedActivationKind.Protocol)
            {
                var proto = activationArgs.Data as Windows.ApplicationModel.Activation.IProtocolActivatedEventArgs;
                uriToForward = proto?.Uri?.ToString();
            }

            string message = !string.IsNullOrEmpty(uriToForward) ? uriToForward : "show";
            try
            {
                using var client = new System.IO.Pipes.NamedPipeClientStream(".", PipeName,
                    System.IO.Pipes.PipeDirection.Out);
                client.Connect(2000); // 2 second timeout
                using var writer = new System.IO.StreamWriter(client);
                writer.WriteLine(message);
                writer.Flush();
            }
            catch
            {
                // Bring the running window to front
                var existing = System.Diagnostics.Process.GetProcessesByName(
                    System.IO.Path.GetFileNameWithoutExtension(System.Environment.ProcessPath ?? "Daily.WinUI"));
                foreach (var p in existing)
                {
                    if (p.Id != System.Diagnostics.Process.GetCurrentProcess().Id && p.MainWindowHandle != IntPtr.Zero)
                    {
                        ShowWindow(p.MainWindowHandle, 9); // SW_RESTORE
                        SetForegroundWindow(p.MainWindowHandle);
                        break;
                    }
                }
            }
            return;
        }

        // We are the main instance — keep mutex alive
        GC.KeepAlive(mutex);

        // ── Register protocol handler pointing to this exe ──
        RegisterProtocolDirectly("com.intellidream.daily.desktop", "DayOne");

        // ── Start listening for protocol URIs forwarded from second instances ──
        System.Threading.Tasks.Task.Run(() =>
        {
            while (true)
            {
                try
                {
                    using var server = new System.IO.Pipes.NamedPipeServerStream(PipeName,
                        System.IO.Pipes.PipeDirection.In,
                        1,
                        System.IO.Pipes.PipeTransmissionMode.Message,
                        System.IO.Pipes.PipeOptions.Asynchronous);
                    server.WaitForConnection();
                    using var reader = new System.IO.StreamReader(server);
                    var line = reader.ReadLine();
                    if (!string.IsNullOrEmpty(line))
                    {
                        if (line.Equals("show", StringComparison.OrdinalIgnoreCase))
                        {
                            System.Diagnostics.Debug.WriteLine("[Pipe] Received show command");
                            var app = App.Current;
                            if (app?.MainWindow != null)
                            {
                                app.MainWindow.DispatcherQueue.TryEnqueue(() =>
                                {
                                    app.MainWindow.ShowAndActivate();
                                });
                            }
                        }
                        else if (Uri.TryCreate(line, UriKind.Absolute, out var uri))
                        {
                            System.Diagnostics.Debug.WriteLine($"[Pipe] Received URI: {uri}");
                            HandleProtocolUri(uri);
                        }
                    }
                }
                catch { /* pipe error — restart listener */ }
            }
        });

        // ── Start the app normally ──
        Microsoft.UI.Xaml.Application.Start((p) =>
        {
            var context = new Microsoft.UI.Dispatching.DispatcherQueueSynchronizationContext(
                Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread());
            System.Threading.SynchronizationContext.SetSynchronizationContext(context);
            new App();
        });
    }

    public App()
    {
        this.UnhandledException += (s, e) =>
        {
            Console.WriteLine("UNHANDLED XAML EXCEPTION: " + e.Exception);
            e.Handled = true;
        };

        AppDomain.CurrentDomain.UnhandledException += (s, e) =>
        {
            Console.WriteLine("UNHANDLED APPDOMAIN EXCEPTION: " + e.ExceptionObject);
        };

        TaskScheduler.UnobservedTaskException += (s, e) =>
        {
            Console.WriteLine("UNOBSERVED TASK EXCEPTION: " + e.Exception);
            e.SetObserved();
        };

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
        services.AddSingleton<Daily.Services.IRssArticleService, Daily.Services.RssArticleService>();
        services.AddSingleton<Daily.Services.ISeederService, Daily.Services.SeederService>();
        services.AddSingleton<Daily.Services.ISettingsService, Daily.Services.SettingsService>();
        services.AddSingleton<Daily_WinUI.Services.WinUIAuthService>();
        services.AddSingleton<Daily_WinUI.Services.WinUIWidgetService>();
        services.AddSingleton<Daily_WinUI.Services.SmartBriefingService>();
        services.AddSingleton<Daily_WinUI.Services.IBehaviorService, Daily_WinUI.Services.BehaviorService>();
        services.AddSingleton<Daily.Services.IHabitsRepository, Daily.Services.HabitsRepository>();
        services.AddSingleton<Daily.Services.IHabitsService, Daily.Services.HabitsService>();
        services.AddSingleton<Daily.Services.IRefreshService, Daily.Services.RefreshService>();
        
        // Finances Services
        services.AddHttpClient<Daily.Services.Finances.YahooFinanceService>();
        services.AddHttpClient<Daily.Services.Finances.FinnhubService>();
        services.AddHttpClient<Daily.Services.Finances.MacroService>();
        services.AddSingleton<Daily.Services.Finances.IFinancesService, Daily.Services.Finances.FinancesService>();
        services.AddTransient<Daily.Services.Finances.IMacroService>(sp => sp.GetRequiredService<Daily.Services.Finances.MacroService>());
        services.AddSingleton<Daily.Services.Finances.IHeatmapService, Daily.Services.Finances.HeatmapService>();
        
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

        // Initialize RSS articles service (for bookmarks and favorites)
        var articleService = Services.GetRequiredService<Daily.Services.IRssArticleService>();
        await articleService.InitializeAsync();

        // Initialize Habits and Health services (sets up Realtime subscriptions)
        var habitsService = Services.GetRequiredService<Daily.Services.IHabitsService>();
        await habitsService.InitializeAsync();

        var healthService = Services.GetRequiredService<Daily.Services.Health.IHealthService>();
        await healthService.InitializeAsync();

        if (SupabaseClient.Auth.CurrentSession != null)
        {
            var syncService = Services.GetRequiredService<Daily.Services.ISyncService>();
            syncService.StartBackgroundSync();
        }
    }

    /// <summary>
    /// Called from the named pipe listener with the forwarded URI from the OAuth callback.
    /// </summary>
    internal static void HandleProtocolUri(Uri uri)
    {
        System.Diagnostics.Debug.WriteLine($"[WinUIAuth] Protocol URI received: {uri}");

        var code = "";
        string queryToParse = "";

        if (!string.IsNullOrEmpty(uri.Query)) queryToParse = uri.Query.TrimStart('?');
        else if (!string.IsNullOrEmpty(uri.Fragment)) queryToParse = uri.Fragment.TrimStart('#');

        if (!string.IsNullOrEmpty(queryToParse))
        {
            foreach (var part in queryToParse.Split('&'))
            {
                var kv = part.Split('=');
                if (kv.Length == 2 && kv[0] == "code")
                {
                    code = System.Net.WebUtility.UrlDecode(kv[1]);
                    System.Diagnostics.Debug.WriteLine("[WinUIAuth] Code found via pipe!");
                    break;
                }
            }
        }

        if (!string.IsNullOrEmpty(code))
        {
            var tcs = Daily_WinUI.Services.WinUIAuthService.GoogleAuthTcs;
            if (tcs != null && !tcs.Task.IsCompleted)
            {
                System.Diagnostics.Debug.WriteLine("[WinUIAuth] Setting TCS Result from pipe...");
                tcs.TrySetResult(code);
            }
            else
            {
                System.Diagnostics.Debug.WriteLine($"[WinUIAuth] TCS null or done (null: {tcs == null})");
            }
        }

        // Bring main window to front
        var app = App.Current;
        if (app?.MainWindow != null)
        {
            app.MainWindow.DispatcherQueue.TryEnqueue(() =>
            {
                app.MainWindow.ShowAndActivate();
            });
        }
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
                var app = App.Current;
                if (app?.MainWindow != null)
                {
                    app.MainWindow.DispatcherQueue.TryEnqueue(() =>
                    {
                        app.MainWindow.ShowAndActivate();
                    });
                }
            }
        }
    }

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    [return: System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.Bool)]
    static extern bool SetForegroundWindow(IntPtr hWnd);

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    /// <summary>
    /// Writes the full HKCU protocol handler directly to the registry.
    /// More reliable than RegisterForProtocolActivation for unpackaged apps.
    /// </summary>
    private static void RegisterProtocolDirectly(string scheme, string appName)
    {
        var exePath = System.Environment.ProcessPath ?? System.Reflection.Assembly.GetExecutingAssembly().Location;
        var command = $"\"{exePath}\" \"----ms-protocol:%1\"";

        using var key = Microsoft.Win32.Registry.CurrentUser.CreateSubKey($@"Software\Classes\{scheme}");
        key.SetValue("", $"URL:{scheme}");
        key.SetValue("URL Protocol", "");

        using var appKey = key.CreateSubKey("Application");
        appKey.SetValue("ApplicationName", appName);

        using var cmdKey = key.CreateSubKey(@"shell\open\command");
        cmdKey.SetValue("", command);

        System.Diagnostics.Debug.WriteLine($"[Protocol] Registered {scheme} -> {exePath}");
    }
}


