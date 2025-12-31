using Supabase.Gotrue;
using static Supabase.Gotrue.Constants;
using Microsoft.Maui.Authentication;
using Daily.Configuration;

namespace Daily.Services
{
    public class AuthService : IAuthService
    {
        private readonly Supabase.Client _supabase;
        private readonly ISettingsService _settingsService;
        private readonly IRefreshService _refreshService;

        // Static TCS to handle the callback from App.xaml.cs on Windows
        public static TaskCompletionSource<string>? WindowsAuthTcs;

        public AuthService(Supabase.Client supabase, ISettingsService settingsService, IRefreshService refreshService)
        {
            _supabase = supabase;
            _settingsService = settingsService;
            _refreshService = refreshService;
        }

        public async Task<bool> SignInWithGoogleAsync()
        {
            try
            {
                // 1. Ask Supabase for the Google Login URL - requesting YouTube scopes
                var state = await _supabase.Auth.SignIn(global::Supabase.Gotrue.Constants.Provider.Google, new SignInOptions
                {
                    RedirectTo = "com.intellidream.daily://callback", 
                    FlowType = global::Supabase.Gotrue.Constants.OAuthFlowType.PKCE,
                    Scopes = "https://www.googleapis.com/auth/youtube.readonly"
                });

                Console.WriteLine($"[AuthService] Generated Auth URI: {state.Uri}");


                if (string.IsNullOrEmpty(state.Uri?.ToString()))
                    return false;

                // 2. Open the browser (WebAuthenticator)
                string? code = null;

#if WINDOWS
                // Manual Protocol Activation for Windows (overcoming WebAuthenticator issues)
                WindowsAuthTcs = new TaskCompletionSource<string>();
                
                // Launch System Browser
                await Launcher.OpenAsync(state.Uri);

                // Wait for the callback (handled in App.xaml.cs)
                // Timeout after 2 minutes to prevent hanging
                var completedTask = await Task.WhenAny(WindowsAuthTcs.Task, Task.Delay(TimeSpan.FromMinutes(2)));
                
                if (completedTask == WindowsAuthTcs.Task)
                {
                    var callbackUrl = await WindowsAuthTcs.Task;
                    code = string.IsNullOrEmpty(callbackUrl) ? null : System.Web.HttpUtility.ParseQueryString(new Uri(callbackUrl).Query).Get("code");
                }
                else
                {
                    Console.WriteLine("[AuthService] Windows Auth Timed Out");
                    WindowsAuthTcs.TrySetCanceled(); 
                }
                
                WindowsAuthTcs = null; // Cleanup
#else
                WebAuthenticatorResult? authResult = null;
                try 
                {
                    Console.WriteLine($"[AuthService] Attempting to open browser with URI: {state.Uri}");
                    authResult = await WebAuthenticator.Default.AuthenticateAsync(
                        state.Uri,
                        new Uri("com.intellidream.daily://callback"));
                    Console.WriteLine("[AuthService] Browser authentication completed successfully.");
                }
                catch (Exception androidEx)
                {
                    Console.WriteLine($"[AuthService] ANDROID OPEN BROWSER FAILED: {androidEx}");
                    Console.WriteLine($"[AuthService] Stack Trace: {androidEx.StackTrace}");
                    throw; // Re-throw to be caught by outer catch
                }
                
                // 3. Extract the Access Token & Refresh Token from the callback URL
                
                code = authResult?.Properties.TryGetValue("code", out var c) == true ? c : null;
#endif
                
                if (!string.IsNullOrEmpty(code))
                {
                    // Exchange code for session using the PKCE Verifier from the state
                    await _supabase.Auth.ExchangeCodeForSession(state.PKCEVerifier, code);
                }
                else
                {
                    // Fallback or error handling
                    Console.WriteLine("AuthService: No code received in callback.");
                }

                // 4. Update Settings Service (Triggers UI update)
                await _settingsService.InitializeAsync();

                // 5. Trigger Global Refresh (Media Widget, etc.)
                await _refreshService.TriggerRefreshAsync();
                await _refreshService.TriggerDetailRefreshAsync();
                
                return _supabase.Auth.CurrentSession != null;

            }
            catch (TaskCanceledException)
            {
                // User closed the window
                return false;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Login Failed: {ex.Message}");
                return false;
            }
        }

        public string? GetProviderToken()
        {
            // Supabase stores the provider's access token in the session if Scopes were requested
            return _supabase.Auth.CurrentSession?.ProviderToken;
        }

        public async Task SignOutAsync()
        {
            await _supabase.Auth.SignOut();
            await _settingsService.InitializeAsync();
            
            // Trigger Global Refresh to clear UI
            await _refreshService.TriggerRefreshAsync();
            await _refreshService.TriggerDetailRefreshAsync();
        }
    }
}
