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

        public AuthService(Supabase.Client supabase, ISettingsService settingsService)
        {
            _supabase = supabase;
            _settingsService = settingsService;
        }

        public async Task<bool> SignInWithGoogleAsync()
        {
            try
            {
                // 1. Ask Supabase for the Google Login URL
                var state = await _supabase.Auth.SignIn(global::Supabase.Gotrue.Constants.Provider.Google, new SignInOptions
                {
                    RedirectTo = "com.intellidream.daily://", // Changed from com.intellidream.daily://login-callback to match generic scheme
                    FlowType = global::Supabase.Gotrue.Constants.OAuthFlowType.PKCE 
                });

                Console.WriteLine($"[AuthService] Generated Auth URI: {state.Uri}");


                if (string.IsNullOrEmpty(state.Uri?.ToString()))
                    return false;

                // 2. Open the browser (WebAuthenticator)
                var authResult = await WebAuthenticator.Default.AuthenticateAsync(
                    state.Uri,
                    new Uri("com.intellidream.daily://"));

                // 3. Extract the Access Token & Refresh Token from the callback URL
                // Supabase redirects to: com.intellidream.daily://login-callback#access_token=...&refresh_token=...
                // WebAuthenticator handles the callback capture.
                
                var accessToken = authResult?.AccessToken;
                var refreshToken = authResult?.RefreshToken;
                
                // Note: WebAuthenticator might parse parameters into 'Properties'.
                // Supabase often returns fragments. Let's check how WebAuthenticator parses it.
                // If standard OAuth, it might be in query. Supabase default is fragment for Implicit, but we requested PKCE.
                // With PKCE, it usually returns a 'code' in query.
                
                var code = authResult?.Properties.TryGetValue("code", out var c) == true ? c : null;
                
                if (!string.IsNullOrEmpty(code))
                {
                    // Exchange code for session using the PKCE Verifier from the state
                    await _supabase.Auth.ExchangeCodeForSession(state.PKCEVerifier, code);
                }
                else
                {
                    // Fallback: If implicit flow (or if Supabase handling is different), try URL parsing if needed.
                    // But we set PKCE, so 'code' should be there.
                    // If we got here, we might need to debug the response.
                }

                // 4. Update Settings Service (Triggers UI update)
                await _settingsService.InitializeAsync();
                
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

        public async Task SignOutAsync()
        {
            await _supabase.Auth.SignOut();
            await _settingsService.InitializeAsync();
        }
    }
}
