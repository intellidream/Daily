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
                    RedirectTo = "com.intellidream.daily://", 
                    FlowType = global::Supabase.Gotrue.Constants.OAuthFlowType.PKCE,
                    Scopes = "https://www.googleapis.com/auth/youtube.readonly"
                });

                Console.WriteLine($"[AuthService] Generated Auth URI: {state.Uri}");


                if (string.IsNullOrEmpty(state.Uri?.ToString()))
                    return false;

                // 2. Open the browser (WebAuthenticator)
#if WINDOWS
                // Use native WebAuthenticationBroker on Windows to avoid PlatformNotSupportedException in MAUI wrapper
                // This requires the app to be packaged (MSIX)
                var wapResult = await Windows.Security.Authentication.Web.WebAuthenticationBroker.AuthenticateAsync(
                    Windows.Security.Authentication.Web.WebAuthenticationOptions.None,
                    state.Uri,
                    new Uri("com.intellidream.daily://"));

                string? callbackUrl = null;
                if (wapResult.ResponseStatus == Windows.Security.Authentication.Web.WebAuthenticationStatus.Success)
                {
                    callbackUrl = wapResult.ResponseData;
                }
                else
                {
                    Console.WriteLine($"[AuthService] Windows Auth Failed: {wapResult.ResponseStatus} - {wapResult.ResponseErrorDetail}");
                }
#else
                 var authResult = await WebAuthenticator.Default.AuthenticateAsync(
                    state.Uri,
                    new Uri("com.intellidream.daily://"));
                 
                 string? callbackUrl = authResult?.Properties.TryGetValue("code", out var c) == true ? $"?code={c}" : authResult?.AccessToken; 
                 // Note: WebAuthenticator usually parses the updated URL or returns the result properties. 
                 // Actually, Supabase needs the 'code' from the query parameters basically.
                 // Let's stick to existing logic for non-Windows but adapt variables.
#endif

                // 3. Extract the Access Token & Refresh Token from the callback URL
                 
#if WINDOWS
                // Extract code from callbackUrl for Windows
                var code = string.IsNullOrEmpty(callbackUrl) ? null : System.Web.HttpUtility.ParseQueryString(new Uri(callbackUrl).Query).Get("code");
#else
                var code = authResult?.Properties.TryGetValue("code", out var c) == true ? c : null;
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
