using Android.App;
using Android.Content.PM;

namespace Daily.Platforms.Android
{
    [Activity(NoHistory = true, LaunchMode = LaunchMode.SingleTop, Exported = true, Name = "com.intellidream.daily.WebAuthenticationCallbackActivity")]
    public class WebAuthenticationCallbackActivity : Microsoft.Maui.Authentication.WebAuthenticatorCallbackActivity
    {
    }
}
