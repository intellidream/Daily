using Foundation;
using UIKit;
using Microsoft.Maui.ApplicationModel;

namespace Daily
{
    [Register("AppDelegate")]
    public class AppDelegate : MauiUIApplicationDelegate
    {
        protected override MauiApp CreateMauiApp() => MauiProgram.CreateMauiApp();

        public override bool OpenUrl(UIApplication app, NSUrl url, NSDictionary options)
        {
            // Manual interception for Supabase PKCE Flow
            if (url.AbsoluteString.StartsWith("com.intellidream.daily://login-callback"))
            {
                try
                {
                    var uri = new Uri(url.AbsoluteString);
                    var components = uri.Query.TrimStart('?').Split('&');
                    foreach (var component in components)
                    {
                        var parts = component.Split('=');
                        if (parts.Length == 2 && parts[0] == "code")
                        {
                            var code = parts[1];
                            Daily.Services.AuthService.GoogleAuthTcs?.TrySetResult(code);
                            return true;
                        }
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[AppDelegate] Error parsing auth callback: {ex}");
                }
            }

            if (Platform.OpenUrl(app, url, options))
                return true;

            return base.OpenUrl(app, url, options);
        }

        public override bool ContinueUserActivity(UIApplication application, NSUserActivity userActivity, UIApplicationRestorationHandler completionHandler)
        {
            if (Platform.ContinueUserActivity(application, userActivity, completionHandler))
                return true;

            return base.ContinueUserActivity(application, userActivity, completionHandler);
        }
    }
}
