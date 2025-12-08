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
#if WINDOWS
            // Force WebView2 to be transparent
            Environment.SetEnvironmentVariable("WEBVIEW2_DEFAULT_BACKGROUND_COLOR", "0");
#endif
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
            Microsoft.AspNetCore.Components.WebView.Maui.BlazorWebViewHandler.BlazorWebViewMapper.AppendToMapping("BlazorWebViewTransparent", (handler, view) =>
            {
                if (view is Microsoft.AspNetCore.Components.WebView.Maui.BlazorWebView)
                {
                    // Set the WinUI WebView2 background to transparent
                    handler.PlatformView.DefaultBackgroundColor = Microsoft.UI.Colors.Transparent;

                    // Ensure it persists after CoreWebView2 initialization
                    handler.PlatformView.CoreWebView2Initialized += (sender, args) =>
                    {
                        if (sender is Microsoft.UI.Xaml.Controls.WebView2 webView2)
                        {
                            webView2.DefaultBackgroundColor = Microsoft.UI.Colors.Transparent;
                        }
                    };
                }
            });
            builder.UseNotifyIcon();
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
#else
            builder.Services.AddSingleton<Daily.Services.ITrayService, Daily.Services.StubTrayService>();
#endif

            return builder.Build();
        }
    }
}
