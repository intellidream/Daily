using Microsoft.Extensions.Logging;
using MudBlazor.Services;
using H.NotifyIcon;
using CommunityToolkit.Maui;
using Microsoft.Maui.LifecycleEvents;

namespace Daily
{
    public static class MauiProgram
    {
        public static MauiApp CreateMauiApp()
        {

            var builder = MauiApp.CreateBuilder();
            builder
                .UseMauiApp<App>()
                .UseMauiCommunityToolkit()
                .ConfigureFonts(fonts =>
                {
                    fonts.AddFont("OpenSans-Regular.ttf", "OpenSansRegular");
                })
                .ConfigureLifecycleEvents(events =>
                {
#if MACCATALYST
                    events.AddiOS(ios => ios.FinishedLaunching((app, launchOptions) => 
                    {
                         AppDomain.CurrentDomain.UnhandledException += (sender, error) => 
                         {
                             var path = Path.Combine(FileSystem.AppDataDirectory, "crash_log.txt");
                             File.AppendAllText(path, $"[CRASH] {DateTime.Now}: {error.ExceptionObject}\n");
                         };
                         TaskScheduler.UnobservedTaskException += (sender, error) => 
                         {
                             var path = Path.Combine(FileSystem.AppDataDirectory, "crash_log.txt");
                             File.AppendAllText(path, $"[TASK ICON] {DateTime.Now}: {error.Exception}\n");
                         };
                         return true;
                    }));
#endif
#if WINDOWS
                    events.AddWindows(windows => windows
                        .OnLaunched((window, args) =>
                        {
                            // Logic moved to MainPage/WindowHelpers for safety
                        }));
#endif
                });

            builder.Services.AddMauiBlazorWebView();
            builder.Services.AddMudServices();



#if WINDOWS
            builder.UseNotifyIcon();
            Microsoft.AspNetCore.Components.WebView.Maui.BlazorWebViewHandler.BlazorWebViewMapper.AppendToMapping("BlazorWebViewTransparent", (handler, view) =>
            {
                if (view is Microsoft.AspNetCore.Components.WebView.Maui.BlazorWebView)
                {
                    // Detect current App Theme preference
                    var appTheme = Application.Current?.UserAppTheme ?? AppTheme.Unspecified;
                    if (appTheme == AppTheme.Unspecified) appTheme = Application.Current?.RequestedTheme ?? AppTheme.Light;
                    
                    var backgroundColor = appTheme == AppTheme.Dark ? Microsoft.UI.Colors.Black : Microsoft.UI.Colors.White;
                    
                    // Set the WinUI WebView2 background to App Theme Color
                    // This ensures that even if index.html is transparent, we see the correct background
                    handler.PlatformView.DefaultBackgroundColor = backgroundColor;

                    // Ensure it persists after CoreWebView2 initialization
                    handler.PlatformView.CoreWebView2Initialized += (sender, args) =>
                    {
                        if (sender is Microsoft.UI.Xaml.Controls.WebView2 webView2)
                        {
                            webView2.DefaultBackgroundColor = backgroundColor;
                        }
                    };
                }
            });
#elif MACCATALYST || IOS
            // Configure Mac Catalyst and iOS BlazorWebView to be transparent/opaque-aware
            Microsoft.AspNetCore.Components.WebView.Maui.BlazorWebViewHandler.BlazorWebViewMapper.AppendToMapping("BlazorWebViewTransparentMobile", (handler, view) =>
            {
                 if (view is Microsoft.AspNetCore.Components.WebView.Maui.BlazorWebView)
                 {
                     handler.PlatformView.Opaque = false;
                     handler.PlatformView.BackgroundColor = UIKit.UIColor.Clear;
                     // Also ensure the scroll view behind it is clear
                     handler.PlatformView.ScrollView.BackgroundColor = UIKit.UIColor.Clear;
                 }
            });
#endif


            builder.Services.AddSingleton<Daily.Services.IWidgetService, Daily.Services.WidgetService>();
            builder.Services.AddSingleton<Daily.Services.IWeatherService, Daily.Services.WeatherService>();
            builder.Services.AddSingleton<Daily.Services.IRefreshService, Daily.Services.RefreshService>();
            builder.Services.AddSingleton<Daily.Services.ISystemMonitorService, Daily.Services.SystemMonitorService>();
            builder.Services.AddSingleton<Daily.Services.IHabitsService, Daily.Services.HabitsService>();
            builder.Services.AddSingleton<Daily.Services.IDatabaseService, Daily.Services.DatabaseService>();
            builder.Services.AddSingleton<Daily.Services.IRssFeedService, Daily.Services.RssFeedService>();
            
            Console.WriteLine("[MauiProgram] Registering Health Services...");
            // Health Services
//#if IOS && !MACCATALYST
//            Console.WriteLine("[MauiProgram] Registering iOS HealthKitService...");
//            builder.Services.AddSingleton<Daily.Services.Health.INativeHealthStore, Daily.Platforms.iOS.Services.Health.HealthKitService>();
//#else
            // iOS HealthKit (Actual)
#if IOS && !MACCATALYST
            Console.WriteLine("[MauiProgram] Registering iOS HealthKitService...");
            builder.Services.AddSingleton<Daily.Services.Health.INativeHealthStore, Daily.Platforms.iOS.Services.Health.HealthKitService>();
#elif ANDROID
            Console.WriteLine("[MauiProgram] Registering Android HealthConnectService...");
            builder.Services.AddSingleton<Daily.Services.Health.INativeHealthStore, Daily.Platforms.Android.HealthConnectService>();
#else
            Console.WriteLine("[MauiProgram] Registering MockNativeHealthStore (Default)...");
            builder.Services.AddSingleton<Daily.Services.Health.INativeHealthStore, Daily.Services.Health.MockNativeHealthStore>();
#endif
            Console.WriteLine("[MauiProgram] Registering SupabaseHealthService...");
            builder.Services.AddSingleton<Daily.Services.Health.IHealthService, Daily.Services.Health.SupabaseHealthService>();
            builder.Services.AddSingleton<Daily.Services.IHabitsRepository, Daily.Services.HabitsRepository>();
            builder.Services.AddSingleton<Daily.Services.ISyncService, Daily.Services.SyncService>();
            builder.Services.AddSingleton<Daily.Services.ISeederService, Daily.Services.SeederService>();
            Console.WriteLine("[MauiProgram] Health Services Registered.");
            
            builder.Services.AddSingleton<Daily.Services.IYouTubeService, Daily.Services.YouTubeService>();
            
            // Register as Concrete to allow App.xaml.cs to resolve it for PreWarmMacDetail
            builder.Services.AddSingleton<Daily.Services.WindowManagerService>();
            builder.Services.AddSingleton<Daily.Services.IWindowManagerService>(sp => sp.GetRequiredService<Daily.Services.WindowManagerService>());
            
            builder.Services.AddSingleton<Daily.Services.IDetailNavigationService, Daily.Services.DetailNavigationService>();
            builder.Services.AddSingleton<Daily.Services.IBackButtonService, Daily.Services.BackButtonService>();
            builder.Services.AddSingleton<Daily.Services.IRssFeedService, Daily.Services.RssFeedService>();
            // Register Concrete execution to use the SAME instance (prevent split singleton)
            builder.Services.AddSingleton<Daily.Services.RssFeedService>(sp => (Daily.Services.RssFeedService)sp.GetRequiredService<Daily.Services.IRssFeedService>());
            builder.Services.AddSingleton<Daily.Services.ISettingsService, Daily.Services.SettingsService>();
            builder.Services.AddSingleton<Daily.Services.IAuthService, Daily.Services.AuthService>();
            builder.Services.AddSingleton<IGeolocation>(Geolocation.Default);
            builder.Services.AddSingleton<HttpClient>();

#if DEBUG
    		builder.Services.AddBlazorWebViewDeveloperTools();
    		builder.Logging.AddDebug();
#endif

#if WINDOWS
            builder.Services.AddSingleton<Daily.Services.ITrayService, Daily.Platforms.Windows.WindowsTrayService>();
#elif MACCATALYST
            builder.Services.AddSingleton<Daily.Services.ITrayService, Daily.Platforms.MacCatalyst.MacTrayService>();
#else
            builder.Services.AddSingleton<Daily.Services.ITrayService, Daily.Services.StubTrayService>();
            builder.Services.AddSingleton<Daily.Services.ITrayService, Daily.Services.StubTrayService>();
#endif

            builder.Services.AddSingleton<Daily.Services.DebugLogger>();
            
            // Supabase Configuration
            var supabaseUrl = Daily.Configuration.Secrets.SupabaseUrl;
            var supabaseKey = Daily.Configuration.Secrets.SupabaseKey;
            
            // Register Client using Factory to resolve dependencies (DebugLogger)
            builder.Services.AddSingleton(provider => 
            {
                var logger = provider.GetRequiredService<Daily.Services.DebugLogger>();
                var options = new Supabase.SupabaseOptions
                {
                    AutoRefreshToken = true,
                    AutoConnectRealtime = true,
                    SessionHandler = new Daily.Services.Auth.MauiSessionPersistence(logger)
                };
                return new Supabase.Client(supabaseUrl, supabaseKey, options);
            });

            return builder.Build();
        }

#if WINDOWS
        [System.Runtime.InteropServices.DllImport("dwmapi.dll")]
        private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int pvAttribute, int cbAttribute);
#endif
    }
}
