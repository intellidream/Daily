using Foundation;

namespace Daily
{
    [Register("AppDelegate")]
    public class AppDelegate : MauiUIApplicationDelegate
    {
        protected override MauiApp CreateMauiApp() => MauiProgram.CreateMauiApp();

        [Export("application:openURL:options:")]
        public override bool OpenUrl(UIKit.UIApplication app, Foundation.NSUrl url, Foundation.NSDictionary options)
        {
            if (url != null)
            {
                 // Handle Google Auth Callback
                 if (url.Scheme == "com.intellidream.daily" && (url.Host == "login-callback" || url.Path == "login-callback"))
                 {
                     // Parse code
                     string urlStr = url.AbsoluteString;
                     var components = new Foundation.NSUrlComponents(url, true);
                     var code = components.QueryItems?.FirstOrDefault(q => q.Name == "code")?.Value;
                     
                     if (!string.IsNullOrEmpty(code) && Daily.Services.AuthService.GoogleAuthTcs != null && !Daily.Services.AuthService.GoogleAuthTcs.Task.IsCompleted)
                     {
                         Daily.Services.AuthService.GoogleAuthTcs.TrySetResult(code);
                         return true;
                     }
                 }
            }
            return base.OpenUrl(app, url, options);
        }

    }
}
