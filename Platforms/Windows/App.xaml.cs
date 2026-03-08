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
        /// Custom entry point. Runs BEFORE the WinUI Application is created.
        ///  1. Registers the protocol for the *current* unpackaged exe (updates the registry).
        ///  2. Single-instance gate – a second process redirects and returns immediately.
        ///  3. Subscribes to Activated so the running instance receives the callback.
        /// </summary>
        [System.STAThreadAttribute]
        static void Main(string[] args)
        {
            WinRT.ComWrappersSupport.InitializeComWrappers();

            // ── Register protocol for the unpackaged exe ──
            // This writes HKCU\Software\Classes\com.intellidream.daily\shell\open\command
            // pointing at the CURRENT executable, so Windows launches *this* build.
            // Idempotent – safe to call every startup.
            Microsoft.Windows.AppLifecycle.ActivationRegistrationManager
                .RegisterForProtocolActivation(
                    "com.intellidream.daily",
                    "",
                    "Daily Dashboard",
                    System.Environment.ProcessPath ?? "");

            // ── Single-Instance gate ──
            var mainInstance =
                Microsoft.Windows.AppLifecycle.AppInstance.FindOrRegisterForKey("DailyMainInstance");

            if (!mainInstance.IsCurrent)
            {
                // Another instance owns the key – redirect the activation and exit.
                var activationArgs =
                    Microsoft.Windows.AppLifecycle.AppInstance.GetCurrent().GetActivatedEventArgs();
                mainInstance.RedirectActivationToAsync(activationArgs).AsTask().Wait();
                return;                         // clean exit – no WinUI app, no windows
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

        /// <summary>
        /// Initializes the singleton application object.
        /// </summary>
        public App()
        {
            // Force WebView2 to be transparent (Critical for Light Mode spinner fix)
            System.Environment.SetEnvironmentVariable("WEBVIEW2_DEFAULT_BACKGROUND_COLOR", "0");
            this.InitializeComponent();
        }

        /// <summary>
        /// Fires on a background thread when a second process redirects its activation here.
        /// We handle directly – TrySetResult is thread-safe; no Dispatcher.Dispatch needed.
        /// </summary>
        private static void OnAppInstanceActivated(object? sender, Microsoft.Windows.AppLifecycle.AppActivationArguments e)
        {
            HandleActivation(e);
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
                Daily.Platforms.Windows.WindowHelpers.ApplySquareCorners(nativeWindow);
                Daily.Platforms.Windows.WindowHelpers.ResizeAndDockRight(nativeWindow, 400, 900);
            }

            // Handle initial launch activation (covers cold-start via protocol click)
            var appActivatedArgs = Microsoft.Windows.AppLifecycle.AppInstance.GetCurrent().GetActivatedEventArgs();
            HandleActivation(appActivatedArgs);
        }

        internal static void HandleActivation(Microsoft.Windows.AppLifecycle.AppActivationArguments args)
        {
            if (args.Kind == Microsoft.Windows.AppLifecycle.ExtendedActivationKind.Protocol)
            {
                var protocolArgs = args.Data as Windows.ApplicationModel.Activation.IProtocolActivatedEventArgs;
                if (protocolArgs != null)
                {
                    Daily.WinUI.AuthDebug.Log($"Protocol Activated: {protocolArgs.Uri}");
                    var uri = protocolArgs.Uri;

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
                         // Read the volatile field once into a local
                         var tcs = Daily.Services.AuthService.GoogleAuthTcs;
                         if (tcs != null && !tcs.Task.IsCompleted)
                         {
                            Daily.WinUI.AuthDebug.Log("Setting TCS Result...");
                            tcs.TrySetResult(code);
                         }
                         else
                         {
                             Daily.WinUI.AuthDebug.Log($"TCS is null or already completed! (tcs null: {tcs == null})");
                         }
                    }
                    else
                    {
                        Daily.WinUI.AuthDebug.Log("No code found in URI.");
                    }

                    // Bring window to front (P/Invoke is safe from any thread)
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

}
