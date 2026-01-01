using Android.App;
using Android.Content.PM;

namespace Daily.Platforms.Android
{
    [Activity(NoHistory = true, LaunchMode = LaunchMode.SingleTop, Exported = true, Name = "com.intellidream.daily.WebAuthenticationCallbackActivity")]
    [IntentFilter(new[] { global::Android.Content.Intent.ActionView },
                  Categories = new[] { global::Android.Content.Intent.CategoryDefault, global::Android.Content.Intent.CategoryBrowsable },
                  DataScheme = "com.intellidream.daily")]
    public class WebAuthenticationCallbackActivity : Microsoft.Maui.Authentication.WebAuthenticatorCallbackActivity
    {
    }
}
