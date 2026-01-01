using Android.App;
using Android.Content.PM;
using Android.OS;

namespace Daily.Platforms.Android
{
    [Activity(NoHistory = true, LaunchMode = LaunchMode.SingleTop, Exported = true, Name = "com.intellidream.daily.WebAuthCallback")]
    [IntentFilter(new[] { global::Android.Content.Intent.ActionView },
        Categories = new[] { global::Android.Content.Intent.CategoryDefault, global::Android.Content.Intent.CategoryBrowsable },
        DataScheme = "com.intellidream.daily",
        DataHost = "login-callback")]
    public class WebAuthenticationCallbackActivity : Activity
    {
        protected override void OnCreate(Bundle? savedInstanceState)
        {
            base.OnCreate(savedInstanceState);
            HandleIntent(Intent);
            Finish();
        }

        protected override void OnNewIntent(global::Android.Content.Intent? intent)
        {
            base.OnNewIntent(intent);
            HandleIntent(intent);
            Finish();
        }

        private void HandleIntent(global::Android.Content.Intent? intent)
        {
            if (intent?.Data == null) return;
            var uri = intent.Data;
            
            // Allow for com.intellidream.daily://login-callback#code=... or ?code=...
            // Supabase/Google usually returns code in Query
            var code = uri.GetQueryParameter("code");
            
            if (!string.IsNullOrEmpty(code))
            {
                Daily.Services.AuthService.GoogleAuthTcs?.TrySetResult(code);
            }
            else
            {
                // Fallback: Check fragment if it's there (implicit flow, though using PKCE)
                // Just in case
                var fragment = uri.Fragment; // includes #
                if (!string.IsNullOrEmpty(fragment))
                {
                   var q = System.Web.HttpUtility.ParseQueryString(fragment.TrimStart('#'));
                   var fragCode = q.Get("code");
                   if (!string.IsNullOrEmpty(fragCode))
                   {
                       Daily.Services.AuthService.GoogleAuthTcs?.TrySetResult(fragCode);
                   }
                }
            }
        }
    }
}
