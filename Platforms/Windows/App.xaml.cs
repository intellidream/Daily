using Microsoft.UI.Xaml;

// To learn more about WinUI, the WinUI project structure,
// and more about our project templates, see: http://aka.ms/winui-project-info.

namespace Daily.WinUI
{
    /// <summary>
    /// Provides application-specific behavior to supplement the default Application class.
    /// </summary>
    public partial class App : MauiWinUIApplication
    {
        /// <summary>
        /// Initializes the singleton application object.  This is the first line of authored code
        /// executed, and as such is the logical equivalent of main() or WinMain().
        /// </summary>
        public App()
        {
            // Force WebView2 to be transparent (Critical for Light Mode spinner fix)
            System.Environment.SetEnvironmentVariable("WEBVIEW2_DEFAULT_BACKGROUND_COLOR", "0");
            
            this.InitializeComponent();

            // Single Instance Logic
            var mainInstance = Microsoft.Windows.AppLifecycle.AppInstance.FindOrRegisterForKey("DailyMainInstance");
            if (!mainInstance.IsCurrent)
            {
                // Redirect activation to the main instance
                var activationArgs = Microsoft.Windows.AppLifecycle.AppInstance.GetCurrent().GetActivatedEventArgs();
                var task = mainInstance.RedirectActivationToAsync(activationArgs).AsTask();
                task.Wait(); // Synchronous wait to ensure redirection finishes before exit
                System.Diagnostics.Process.GetCurrentProcess().Kill();
                return;
            }

            // Register for future activations (e.g., Protocol redirect while running)
            mainInstance.Activated += OnAppInstanceActivated;
        }

        private static void OnAppInstanceActivated(object? sender, Microsoft.Windows.AppLifecycle.AppActivationArguments e)
        {
            // Must run on UI thread
            Microsoft.Maui.Controls.Application.Current.Dispatcher.Dispatch(() =>
            {
                HandleActivation(e);
            });
        }

        protected override MauiApp CreateMauiApp() => MauiProgram.CreateMauiApp();

        protected override void OnLaunched(LaunchActivatedEventArgs args)
        {
            base.OnLaunched(args);

            // Apply Window Styling (Square Corners, No Chrome) safely after creation
            var mauiWindow = Microsoft.Maui.Controls.Application.Current?.Windows.FirstOrDefault();
            if (mauiWindow?.Handler?.PlatformView is Microsoft.UI.Xaml.Window nativeWindow)
            {
                nativeWindow.ExtendsContentIntoTitleBar = true;
                if (Microsoft.UI.Composition.SystemBackdrops.MicaController.IsSupported())
                {
                    nativeWindow.SystemBackdrop = new Microsoft.UI.Xaml.Media.MicaBackdrop();
                }
                Daily.Platforms.Windows.WindowHelpers.ApplyRoundedCorners(nativeWindow);
                Daily.Platforms.Windows.WindowHelpers.ApplySystemBorderColor(nativeWindow);
                // Explicitly set window size to 450x900 effective pixels (Compact Sidebar)
                // This matches the "Compact" density setting
                Daily.Platforms.Windows.WindowHelpers.ResizeAndDockRight(nativeWindow, 400, 900);
            }

            // Handle initial launch activation
            var appActivatedArgs = Microsoft.Windows.AppLifecycle.AppInstance.GetCurrent().GetActivatedEventArgs();
            HandleActivation(appActivatedArgs);
        }

        private static void HandleActivation(Microsoft.Windows.AppLifecycle.AppActivationArguments args)
        {
            if (args.Kind == Microsoft.Windows.AppLifecycle.ExtendedActivationKind.Protocol)
            {
                var protocolArgs = args.Data as Windows.ApplicationModel.Activation.ProtocolActivatedEventArgs;
                if (protocolArgs != null)
                {
                    Daily.WinUI.AuthDebug.Log($"Protocol Activated: {protocolArgs.Uri}");
                    var uri = protocolArgs.Uri;
                    
                    // Manual Query Parsing (Safer than System.Web.HttpUtility)
                    var code = "";
                    string queryToParse = "";

                    if (!string.IsNullOrEmpty(uri.Query)) queryToParse = uri.Query.TrimStart('?');
                    else if (!string.IsNullOrEmpty(uri.Fragment)) queryToParse = uri.Fragment.TrimStart('#');

                    Daily.WinUI.AuthDebug.Log($"Query to parse: {queryToParse}");

                    if (!string.IsNullOrEmpty(queryToParse))
                    {
                        var parts = queryToParse.Split('&');
                        foreach (var part in parts)
                        {
                            var kv = part.Split('=');
                            if (kv.Length == 2 && kv[0] == "code")
                            {
                                code = System.Net.WebUtility.UrlDecode(kv[1]);
                                Daily.WinUI.AuthDebug.Log("Code found!");
                                break;
                            }
                        }
                    }

                    if (!string.IsNullOrEmpty(code))
                    {
                         if(Daily.Services.AuthService.GoogleAuthTcs != null && !Daily.Services.AuthService.GoogleAuthTcs.Task.IsCompleted)
                         {
                            Daily.WinUI.AuthDebug.Log("Setting TCS Result...");
                            Daily.Services.AuthService.GoogleAuthTcs.TrySetResult(code);
                         }
                         else
                         {
                             Daily.WinUI.AuthDebug.Log("TCS is null or already completed!");
                         }
                    }
                    else
                    {
                        Daily.WinUI.AuthDebug.Log("No code found in URI.");
                    }
                    
                    // Bring window to front
                    var handle = System.Diagnostics.Process.GetCurrentProcess().MainWindowHandle;
                    if (handle != IntPtr.Zero)
                    {
                        ShowWindow(handle, 9); // SW_RESTORE = 9
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

}
