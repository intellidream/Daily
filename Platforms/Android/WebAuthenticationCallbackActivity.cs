using Android.App;
using Android.Content.PM;

namespace Daily.Platforms.Android
{
    [Activity(NoHistory = true, LaunchMode = LaunchMode.SingleTop, Exported = true)]
    [IntentFilter(new[] { global::Android.Content.Intent.ActionView },
                  Categories = new[] { global::Android.Content.Intent.CategoryDefault, global::Android.Content.Intent.CategoryBrowsable },
                  DataScheme = "com.intellidream.daily",
                  DataHost = "login-callback")]
    public class WebAuthenticationCallbackActivity : Microsoft.Maui.Authentication.WebAuthenticatorCallbackActivity
    {
    }
}
