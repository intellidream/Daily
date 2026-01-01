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
                    RedirectTo = "com.intellidream.daily://login-callback", 
                    FlowType = global::Supabase.Gotrue.Constants.OAuthFlowType.PKCE,
                    Scopes = "https://www.googleapis.com/auth/youtube.readonly"
                });

                Console.WriteLine($"[AuthService] Generated Auth URI: {state.Uri}");

                // 2. Open the browser (Manual Flow for ALL Platforms)
                string? code = null;
                GoogleAuthTcs = new TaskCompletionSource<string>();

                try 
                {
                    // Use Launcher instead of WebAuthenticator to bypass Intent checks
                    await Launcher.OpenAsync(state.Uri);
                    
                    // Wait for the callback (handled in WebAuthenticationCallbackActivity or Windows App.xaml.cs)
                    var completedTask = await Task.WhenAny(GoogleAuthTcs.Task, Task.Delay(TimeSpan.FromMinutes(2)));

                    if (completedTask == GoogleAuthTcs.Task)
                    {
                        code = await GoogleAuthTcs.Task;
                    }
                    else
                    {
                        GoogleAuthTcs.TrySetCanceled();
                        await CommunityToolkit.Maui.Alerts.Toast.Make("Login Timed Out").Show();
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[AuthService] LAUNCHER FAILED: {ex}");
                    await CommunityToolkit.Maui.Alerts.Toast.Make($"Launcher Error: {ex.Message}").Show();
                    throw;
                }
                finally
                {
                    GoogleAuthTcs = null; // Cleanup
                }
                
                if (!string.IsNullOrEmpty(code))
                {
                    // Exchange code for session using the PKCE Verifier from the state
                    await _supabase.Auth.ExchangeCodeForSession(state.PKCEVerifier, code);
                }
                else
                {
                    await CommunityToolkit.Maui.Alerts.Toast.Make("Auth Failed: No code received").Show();
                }

                // 4. Update Settings Service (Triggers UI update)
                await _settingsService.InitializeAsync();
                
                // Allow UI to settle
                await Task.Delay(500);

                // 5. Trigger Global Refresh nicely
                await _refreshService.TriggerRefreshAsync();
                await Task.Delay(500); 
                await _refreshService.TriggerDetailRefreshAsync();
                
                await CommunityToolkit.Maui.Alerts.Toast.Make("Login Successful!").Show();
                return _supabase.Auth.CurrentSession != null;

            }
            catch (TaskCanceledException)
            {
                // User closed the window
                await CommunityToolkit.Maui.Alerts.Toast.Make("Login Canceled").Show();
                return false;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Login Failed: {ex.Message}");
                await CommunityToolkit.Maui.Alerts.Toast.Make($"Login Exception: {ex.Message}").Show();
                return false;
            }
        }

        // Static TCS for manual callback handling
        public static TaskCompletionSource<string>? GoogleAuthTcs;

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
