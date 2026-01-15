using Android.App;
using Android.Content.PM;
using Android.OS;
using AndroidX.Core.View;

namespace Daily
{
    [Activity(Name = "com.intellidream.daily.MainActivity", Theme = "@style/MainTheme", MainLauncher = true, ConfigurationChanges = ConfigChanges.ScreenSize | ConfigChanges.Orientation | ConfigChanges.UiMode | ConfigChanges.ScreenLayout | ConfigChanges.SmallestScreenSize | ConfigChanges.Density)]
    public class MainActivity : MauiAppCompatActivity
    {
        protected override void OnCreate(Bundle? savedInstanceState)
        {
            base.OnCreate(savedInstanceState);
            
            // Enable edge-to-edge
            WindowCompat.SetDecorFitsSystemWindows(Window, false);
            
            // Ensure status bar and navigation bar are transparent
            Window.SetStatusBarColor(Android.Graphics.Color.Transparent);
            Window.SetNavigationBarColor(Android.Graphics.Color.Transparent);
        }
    }
}
