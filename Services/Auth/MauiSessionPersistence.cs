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
                #if WINDOWS
                Daily.WinUI.AuthDebug.Log($"[MauiSessionPersistence] SaveSession Invoked");
                #endif
                
                // CRITICAL FIX: Preserve Provider Tokens if missing (Token Loss Prevention)
                if (string.IsNullOrEmpty(session.ProviderToken))
                {
                     var stored = LoadSession();
                     if (stored != null)
                     {
                         if (!string.IsNullOrEmpty(stored.ProviderToken)) 
                         {
                             session.ProviderToken = stored.ProviderToken;
                         }
                         if (!string.IsNullOrEmpty(stored.ProviderRefreshToken))
                         {
                             session.ProviderRefreshToken = stored.ProviderRefreshToken;
                         }
                     }
                }

                #if WINDOWS
                Daily.WinUI.AuthDebug.Log($"[MauiSessionPersistence] Serializing Session...");
                #endif
                var json = JsonConvert.SerializeObject(session);
                
                #if WINDOWS
                Daily.WinUI.AuthDebug.Log($"[MauiSessionPersistence] Saving to SecureStorage (Key: {SessionKey})...");
                #endif
                
                try 
                {
                    #if WINDOWS
                    Daily.WinUI.AuthDebug.Log($"[MauiSessionPersistence] Offloading SecureStorage to Task.Run to avoid UI Deadlock...");
                    #endif
                    
                    // DEADLOCK FIX: Wrap in Task.Run to avoid capturing UI SynchronizationContext
                    Task.Run(async () => await SecureStorage.SetAsync(SessionKey, json)).GetAwaiter().GetResult();
                    
                    Log($"[MauiSessionPersistence] Session Saved via SecureStorage.");
                    #if WINDOWS
                    Daily.WinUI.AuthDebug.Log($"[MauiSessionPersistence] SecureStorage Success.");
                    #endif
                }
                catch (Exception ex)
                {
                    Log($"[MauiSessionPersistence] SecureStorage Failed ({ex.Message}). Falling back to Preferences...");
                    #if WINDOWS
                    Daily.WinUI.AuthDebug.Log($"[MauiSessionPersistence] SecureStorage Failed: {ex.Message}. Falling back...");
                    #endif
                    Preferences.Set(SessionKey, json);
                    Log($"[MauiSessionPersistence] Session Saved via Preferences.");
                }
            }
            catch (Exception ex)
            {
                Log($"[MauiSessionPersistence] Save Failed: {ex.Message}");
                #if WINDOWS
                Daily.WinUI.AuthDebug.Log($"[MauiSessionPersistence] FATAL SAVE ERROR: {ex.Message}");
                #endif
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
                    // DEADLOCK FIX: Wrap in Task.Run
                    json = Task.Run(async () => await SecureStorage.GetAsync(SessionKey)).GetAwaiter().GetResult();
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
