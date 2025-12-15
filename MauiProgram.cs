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
#if WINDOWS
                    events.AddWindows(windows => windows
                        .OnLaunched((window, args) =>
                        {
                            // Placeholder for correct implementation if needed
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
                    // Set the WinUI WebView2 background to transparent
                    handler.PlatformView.DefaultBackgroundColor = Microsoft.UI.Colors.Transparent;

                    // Ensure it persists after CoreWebView2 initialization
                    handler.PlatformView.CoreWebView2Initialized += async (sender, args) =>
                    {
                        if (sender is Microsoft.UI.Xaml.Controls.WebView2 webView2)
                        {
                            webView2.DefaultBackgroundColor = Microsoft.UI.Colors.Transparent;
                            
                            // Inject Initial Theme State to force correct background color immediately
                            // This solves the issue where Transparency fails and reveals the System Dark theme instead of App Light theme.
                            var appTheme = Application.Current?.UserAppTheme ?? AppTheme.Unspecified;
                            if (appTheme == AppTheme.Unspecified) appTheme = Application.Current?.RequestedTheme ?? AppTheme.Light;
                            
                            var themeStr = appTheme == AppTheme.Dark ? "dark" : "light";
                            var script = $"document.documentElement.setAttribute('data-theme', '{themeStr}');";
                            
                            if (webView2.CoreWebView2 != null)
                            {
                                await webView2.CoreWebView2.AddScriptToExecuteOnDocumentCreatedAsync(script);
                            }
                        }
                    };
                }
            });
#elif MACCATALYST
            // Configure Mac Catalyst BlazorWebView to be transparent/opaque-aware
            Microsoft.AspNetCore.Components.WebView.Maui.BlazorWebViewHandler.BlazorWebViewMapper.AppendToMapping("BlazorWebViewMacTransparent", (handler, view) =>
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
            builder.Services.AddSingleton<Daily.Services.IGoogleAuthService, Daily.Services.GoogleAuthService>();
            builder.Services.AddSingleton<Daily.Services.IYouTubeService, Daily.Services.YouTubeService>();
            builder.Services.AddSingleton<Daily.Services.IWindowManagerService, Daily.Services.WindowManagerService>();
            builder.Services.AddSingleton<Daily.Services.IDetailNavigationService, Daily.Services.DetailNavigationService>();
            builder.Services.AddSingleton<Daily.Services.IBackButtonService, Daily.Services.BackButtonService>();
            builder.Services.AddSingleton<Daily.Services.IRssFeedService, Daily.Services.RssFeedService>();
            builder.Services.AddSingleton<IGeolocation>(Geolocation.Default);

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
#endif

            return builder.Build();
        }
    }
}
