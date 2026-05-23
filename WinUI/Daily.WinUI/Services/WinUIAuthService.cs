using System;
using System.Threading.Tasks;
using Supabase.Gotrue;
using Supabase.Gotrue.Interfaces;
using static Supabase.Gotrue.Constants;
using Daily.Configuration;

namespace Daily_WinUI.Services;

/// <summary>
/// Lightweight auth service for the WinUI 3 app.
/// Handles Google OAuth via Supabase PKCE flow with custom protocol callback.
/// </summary>
public class WinUIAuthService
{
    private readonly Supabase.Client _supabase;

    /// <summary>
    /// Static TCS for the OAuth callback. Set by the protocol activation handler in App.xaml.cs.
    /// Volatile because it's written on the UI thread and read on an activation background thread.
    /// </summary>
    public static volatile TaskCompletionSource<string>? GoogleAuthTcs;

    public bool IsAuthenticated => _supabase.Auth.CurrentSession != null;
    public string? CurrentUserEmail => _supabase.Auth.CurrentSession?.User?.Email;
    public string? CurrentUserId => _supabase.Auth.CurrentSession?.User?.Id;
    public string? CurrentUserAvatarUrl
    {
        get
        {
            var metadata = _supabase.Auth.CurrentSession?.User?.UserMetadata;
            if (metadata != null)
            {
                if (metadata.TryGetValue("avatar_url", out var avatar) && avatar != null) return avatar.ToString();
                if (metadata.TryGetValue("picture", out var picture) && picture != null) return picture.ToString();
            }
            return null;
        }
    }

    public string? CurrentUserDisplayName
    {
        get
        {
            var metadata = _supabase.Auth.CurrentSession?.User?.UserMetadata;
            if (metadata != null)
            {
                if (metadata.TryGetValue("full_name", out var fullName) && fullName != null) return fullName.ToString();
                if (metadata.TryGetValue("name", out var name) && name != null) return name.ToString();
            }
            var email = CurrentUserEmail;
            return email?.Split('@').FirstOrDefault();
        }
    }

    public void AddStateChangedListener(IGotrueClient<User, Session>.AuthEventHandler handler)
    {
        _supabase.Auth.AddStateChangedListener(handler);
    }

    public void RemoveStateChangedListener(IGotrueClient<User, Session>.AuthEventHandler handler)
    {
        _supabase.Auth.RemoveStateChangedListener(handler);
    }

    public WinUIAuthService(Supabase.Client supabase)
    {
        _supabase = supabase;
    }

    public async Task<bool> SignInWithGoogleAsync()
    {
        try
        {
            System.Diagnostics.Debug.WriteLine("[WinUIAuth] Starting Google Sign-In...");

            // 1. Ask Supabase for the Google Login URL with PKCE
            var state = await _supabase.Auth.SignIn(Provider.Google, new SignInOptions
            {
                RedirectTo = "com.intellidream.daily.desktop://login-callback",
                FlowType = OAuthFlowType.PKCE,
                Scopes = "https://www.googleapis.com/auth/youtube.readonly",
                QueryParams = new System.Collections.Generic.Dictionary<string, string>
                {
                    { "access_type", "offline" }
                }
            });

            System.Diagnostics.Debug.WriteLine($"[WinUIAuth] Auth URI generated: {state.Uri}");

            // 2. Open the system browser
            string? code = null;
            GoogleAuthTcs = new TaskCompletionSource<string>();

            try
            {
                System.Diagnostics.Debug.WriteLine("[WinUIAuth] Opening browser...");
                await Windows.System.Launcher.LaunchUriAsync(state.Uri);

                System.Diagnostics.Debug.WriteLine("[WinUIAuth] Browser opened. Waiting for callback...");

                // Wait for the callback (up to 2 minutes)
                var completedTask = await Task.WhenAny(GoogleAuthTcs.Task, Task.Delay(TimeSpan.FromMinutes(2)));

                if (completedTask == GoogleAuthTcs.Task)
                {
                    System.Diagnostics.Debug.WriteLine("[WinUIAuth] Callback received!");
                    code = await GoogleAuthTcs.Task;
                }
                else
                {
                    System.Diagnostics.Debug.WriteLine("[WinUIAuth] Login timed out.");
                    GoogleAuthTcs.TrySetCanceled();
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[WinUIAuth] Browser launch failed: {ex}");
                throw;
            }
            finally
            {
                GoogleAuthTcs = null;
            }

            // 3. Exchange the code for a session
            if (!string.IsNullOrEmpty(code))
            {
                System.Diagnostics.Debug.WriteLine($"[WinUIAuth] Exchanging code for session...");
                await _supabase.Auth.ExchangeCodeForSession(state.PKCEVerifier, code);
                System.Diagnostics.Debug.WriteLine("[WinUIAuth] Session exchanged successfully!");

                // Explicitly persist the session — the Supabase SessionHandler
                // may not auto-trigger SaveSession after PKCE exchange.
                if (_supabase.Auth.CurrentSession != null)
                {
                    var persistence = new WinUISessionPersistence();
                    persistence.SaveSession(_supabase.Auth.CurrentSession);
                    System.Diagnostics.Debug.WriteLine("[WinUIAuth] Session persisted to local storage.");
                }
            }
            else
            {
                System.Diagnostics.Debug.WriteLine("[WinUIAuth] No code received.");
            }

            return _supabase.Auth.CurrentSession != null;
        }
        catch (TaskCanceledException)
        {
            System.Diagnostics.Debug.WriteLine("[WinUIAuth] Login canceled.");
            return false;
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[WinUIAuth] Login failed: {ex.Message}");
            return false;
        }
    }

    public async Task SignOutAsync()
    {
        try
        {
            await _supabase.Auth.SignOut();
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[WinUIAuth] Sign out error: {ex.Message}");
        }

        // Also destroy local persistence
        var persistence = new WinUISessionPersistence();
        persistence.DestroySession();
    }
}
