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



        private readonly HttpClient _httpClient;
        private readonly Daily.Services.Auth.MauiSessionPersistence _sessionPersistence; // Direct access or via interface? 
        // We need persistence to save the new token. 
        // Ideally we should use the SessionHandler configured in Supabase, but it's private.
        // So we will instantiate a helper or rely on the fact that existing logic saves using the same keys?
        // Actually, we can just use secure storage directly or manually trigger persistence if we knew how.
        // Wait, I can just use the SecureStorage methods? No, cleaner to use the persistence class.
        // But AuthService doesn't depend on Persistence.
        // I will just rely on _supabase.Auth.UpdateSession? No.
        // I will let simple Update trigger persistence if I call _supabase.Auth.SetSession? 
        // No, SetSession wipes tokens.
        // I will manually use SecureStorage/Preferences to save the updated session. 
        // OR better: Inject the persistence logic or duplicate the SAVE logic slightly? 
        // No, duplication is bad.
        // I will Inject IServiceProvider and resolve the persistence if needed, OR just create a new one since it is stateless (just logger).
        
        public AuthService(Supabase.Client supabase, ISettingsService settingsService, IRefreshService refreshService, HttpClient httpClient)
        {
            _supabase = supabase;
            _settingsService = settingsService;
            _refreshService = refreshService;
            _httpClient = httpClient;
        }

        public string? GetProviderRefreshToken()
        {
            return _supabase.Auth.CurrentSession?.ProviderRefreshToken;
        }

        public async Task<bool> RefreshGoogleTokenAsync()
        {
            try
            {
                var refreshToken = GetProviderRefreshToken();
                if (string.IsNullOrEmpty(refreshToken))
                {
                    Console.WriteLine("[AuthService] No Refresh Token available.");
                    return false;
                }

                Console.WriteLine("[AuthService] Attempting to refresh Google Token...");

                var clientId = Secrets.AndroidClientId;
                var clientSecret = "";

                #if WINDOWS
                clientId = Secrets.WindowsClientId;
                clientSecret = Secrets.WindowsClientSecret;
                #endif

                // For Mac/iOS, we might need a different ID, but usually Android one is used as 'Native' shared.
                // If this fails, we might need to ask user for the specific Web Client ID used in Supabase.

                var content = new FormUrlEncodedContent(new[]
                {
                    new KeyValuePair<string, string>("client_id", clientId),
                    new KeyValuePair<string, string>("grant_type", "refresh_token"),
                    new KeyValuePair<string, string>("refresh_token", refreshToken),
                    new KeyValuePair<string, string>("client_secret", clientSecret) // Empty for mobile
                });

                var response = await _httpClient.PostAsync("https://oauth2.googleapis.com/token", content);
                var json = await response.Content.ReadAsStringAsync();

                if (response.IsSuccessStatusCode)
                {
                    var node = System.Text.Json.Nodes.JsonNode.Parse(json);
                    var newAccessToken = node?["access_token"]?.ToString();
                    var expiresIn = node?["expires_in"]?.ToString();

                    if (!string.IsNullOrEmpty(newAccessToken))
                    {
                         if (_supabase.Auth.CurrentSession != null)
                         {
                             _supabase.Auth.CurrentSession.ProviderToken = newAccessToken;
                             Console.WriteLine($"[AuthService] Google Token Refreshed! Expires in: {expiresIn}");

                             // PERSIST
                             // We need to save this update.
                             var persistence = new Daily.Services.Auth.MauiSessionPersistence(null);
                             persistence.SaveSession(_supabase.Auth.CurrentSession);
                             
                             return true;
                         }
                    }
                }
                else
                {
                    Console.WriteLine($"[AuthService] Refresh Failed: {response.StatusCode} - {json}");
                    // If 400 invalid_grant, token is revoked. Sign out? 
                }
                
                return false;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[AuthService] Refresh Exception: {ex}");
                return false;
            }
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
                    Scopes = "https://www.googleapis.com/auth/youtube.readonly",
                    QueryParams = new Dictionary<string, string>
                    {
                        { "access_type", "offline" }
                    }
                });

                Console.WriteLine($"[AuthService] Generated Auth URI: {state.Uri}");

                // 2. Open the browser (Manual Flow for ALL Platforms)
                string? code = null;
                GoogleAuthTcs = new TaskCompletionSource<string>();

                try 
                {
                    // Use Launcher instead of WebAuthenticator to bypass Intent checks
                    Console.WriteLine("[AuthService] Opening Browser via Launcher...");
                    #if WINDOWS
                    Daily.WinUI.AuthDebug.Log("[AuthService] Opening Browser via Launcher...");
                    #endif
                    
                    await Launcher.OpenAsync(state.Uri);
                    
                    Console.WriteLine("[AuthService] Browser Opened. Waiting for callback...");
                    #if WINDOWS
                    Daily.WinUI.AuthDebug.Log("[AuthService] Browser Opened. Waiting for callback TCS...");
                    #endif
                    
                    // Wait for the callback (handled in WebAuthenticationCallbackActivity or Windows App.xaml.cs)
                    var completedTask = await Task.WhenAny(GoogleAuthTcs.Task, Task.Delay(TimeSpan.FromMinutes(2)));

                    if (completedTask == GoogleAuthTcs.Task)
                    {
                        Console.WriteLine("[AuthService] Callback Received!");
                        #if WINDOWS
                        Daily.WinUI.AuthDebug.Log("[AuthService] Callback Received!");
                        #endif
                        code = await GoogleAuthTcs.Task;
                    }
                    else
                    {
                        Console.WriteLine("[AuthService] Login Timed Out!");
                        #if WINDOWS
                        Daily.WinUI.AuthDebug.Log("[AuthService] Login Timed Out!");
                        #endif
                        GoogleAuthTcs.TrySetCanceled();
                        await CommunityToolkit.Maui.Alerts.Toast.Make("Login Timed Out").Show();
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[AuthService] LAUNCHER FAILED: {ex}");
                    #if WINDOWS
                    Daily.WinUI.AuthDebug.Log($"[AuthService] LAUNCHER FAILED: {ex}");
                    #endif
                    await CommunityToolkit.Maui.Alerts.Toast.Make($"Launcher Error: {ex.Message}").Show();
                    throw;
                }
                finally
                {
                    GoogleAuthTcs = null; // Cleanup
                }
                
                if (!string.IsNullOrEmpty(code))
                {
                    #if WINDOWS
                    Daily.WinUI.AuthDebug.Log($"[AuthService] Exchanging Code for Session (Code len: {code.Length})...");
                    #endif
                    // Exchange code for session using the PKCE Verifier from the state
                    await _supabase.Auth.ExchangeCodeForSession(state.PKCEVerifier, code);
                    #if WINDOWS
                    Daily.WinUI.AuthDebug.Log($"[AuthService] Session Exchanged Successfully!");
                    #endif
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
