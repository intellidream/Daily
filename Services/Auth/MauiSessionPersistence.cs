using Newtonsoft.Json;
using Supabase.Gotrue;
using Supabase.Gotrue.Interfaces;

namespace Daily.Services.Auth
{
    public class MauiSessionPersistence : IGotrueSessionPersistence<Session>
    {
        private const string SessionKey = "supabase.session";
        private readonly Daily.Services.DebugLogger? _logger;

        public MauiSessionPersistence(Daily.Services.DebugLogger? logger = null)
        {
            _logger = logger;
        }

        private void Log(string message)
        {
            Console.WriteLine(message);
            _logger?.Log(message);
        }

        public void SaveSession(Session session)
        {
            try
            {
                // CRITICAL FIX: Preserve Provider Tokens if missing (Token Loss Prevention)
                // This handles the case where Supabase library refreshes the JWT but returns a "headless" session 
                // without the provider token, potentially overwriting our valid saved token.
                if (string.IsNullOrEmpty(session.ProviderToken))
                {
                     var stored = LoadSession();
                     if (stored != null)
                     {
                         if (!string.IsNullOrEmpty(stored.ProviderToken)) 
                         {
                             session.ProviderToken = stored.ProviderToken;
                             // Log preserved if needed?
                         }
                         if (!string.IsNullOrEmpty(stored.ProviderRefreshToken))
                         {
                             session.ProviderRefreshToken = stored.ProviderRefreshToken;
                         }
                     }
                }

                var json = JsonConvert.SerializeObject(session);
                Log($"[MauiSessionPersistence] Saving Session...");
                
                try 
                {
                    SecureStorage.SetAsync(SessionKey, json).GetAwaiter().GetResult();
                    Log($"[MauiSessionPersistence] Session Saved via SecureStorage.");
                }
                catch (Exception ex)
                {
                    Log($"[MauiSessionPersistence] SecureStorage Failed ({ex.Message}). Falling back to Preferences...");
                    Preferences.Set(SessionKey, json);
                    Log($"[MauiSessionPersistence] Session Saved via Preferences.");
                }
            }
            catch (Exception ex)
            {
                Log($"[MauiSessionPersistence] Save Failed: {ex.Message}");
            }
        }

        public void DestroySession()
        {
            try
            {
                Log($"[MauiSessionPersistence] Destroying Session...");
                
                // Try remove from both to be safe
                bool secureRemoved = false;
                try
                {
                    SecureStorage.Remove(SessionKey);
                    secureRemoved = true;
                }
                catch {}

                if (Preferences.ContainsKey(SessionKey))
                {
                    Preferences.Remove(SessionKey);
                    Log($"[MauiSessionPersistence] Session Removed from Preferences.");
                }
                
                if (secureRemoved) Log($"[MauiSessionPersistence] Session Removed from SecureStorage.");

            }
            catch (Exception ex)
            {
                Log($"[MauiSessionPersistence] Destroy Failed: {ex.Message}");
            }
        }

        public Session? LoadSession()
        {
            try
            {
                Log($"[MauiSessionPersistence] Loading Session...");
                string? json = null;

                // Try SecureStorage First
                try
                {
                    json = SecureStorage.GetAsync(SessionKey).GetAwaiter().GetResult();
                }
                catch (Exception ex)
                {
                    Log($"[MauiSessionPersistence] SecureStorage Load Failed ({ex.Message}). Checking Preferences...");
                }

                // Fallback to Preferences if null
                if (string.IsNullOrEmpty(json))
                {
                     if (Preferences.ContainsKey(SessionKey))
                     {
                         json = Preferences.Get(SessionKey, null);
                         Log($"[MauiSessionPersistence] Loaded Session from Preferences.");
                     }
                }
                else
                {
                     Log($"[MauiSessionPersistence] Loaded Session from SecureStorage.");
                }

                if (!string.IsNullOrEmpty(json))
                {
                    return JsonConvert.DeserializeObject<Session>(json);
                }
            }
            catch (Exception ex)
            {
                Log($"[MauiSessionPersistence] Load Failed: {ex.Message}");
            }

            Log($"[MauiSessionPersistence] No saved session found.");
            return null;
        }
    }
}
