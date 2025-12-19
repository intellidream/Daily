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
        }

        protected override MauiApp CreateMauiApp() => MauiProgram.CreateMauiApp();

        protected override void OnLaunched(LaunchActivatedEventArgs args)
        {
            base.OnLaunched(args);

            var appActivatedArgs = Microsoft.Windows.AppLifecycle.AppInstance.GetCurrent().GetActivatedEventArgs();
            if (appActivatedArgs.Kind == Microsoft.Windows.AppLifecycle.ExtendedActivationKind.Protocol)
            {
                var protocolArgs = appActivatedArgs.Data as Windows.ApplicationModel.Activation.ProtocolActivatedEventArgs;
                if (protocolArgs != null)
                {
                    var uri = protocolArgs.Uri.ToString();
                    if (Daily.Services.AuthService.WindowsAuthTcs != null && !Daily.Services.AuthService.WindowsAuthTcs.Task.IsCompleted)
                    {
                        Daily.Services.AuthService.WindowsAuthTcs.TrySetResult(uri);
                    }
                }
            }
        }
    }

}
