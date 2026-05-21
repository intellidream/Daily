using Newtonsoft.Json;
using Supabase.Gotrue;
using Supabase.Gotrue.Interfaces;

namespace Daily.Services.Auth
{
    public class MauiSessionPersistence : IGotrueSessionPersistence<Session>
    {
        private const string SessionKey = "supabase.session";
        private readonly Daily.Services.DebugLogger? _logger;
        private readonly Daily.Services.IWatchConnectivityService? _watchConnectivityService;
        
        // In-memory cache to avoid recursive LoadSession→SaveSession deadlocks on iOS
        private Session? _cachedSession;

        public MauiSessionPersistence(Daily.Services.DebugLogger? logger = null, Daily.Services.IWatchConnectivityService? watchConnectivityService = null)
        {
            _logger = logger;
            _watchConnectivityService = watchConnectivityService;
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
                // Use in-memory cache to avoid recursive LoadSession() call that double-blocks on iOS Keychain
                if (string.IsNullOrEmpty(session.ProviderToken) && _cachedSession != null)
                {
                    if (!string.IsNullOrEmpty(_cachedSession.ProviderToken)) 
                    {
                        session.ProviderToken = _cachedSession.ProviderToken;
                    }
                    if (!string.IsNullOrEmpty(_cachedSession.ProviderRefreshToken))
                    {
                        session.ProviderRefreshToken = _cachedSession.ProviderRefreshToken;
                    }
                }
                
                // Update cache
                _cachedSession = session;

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
                    
                    // DEADLOCK FIX: Wrap in Task.Run + timeout to prevent permanent blocking on iOS
                    Task.Run(async () => await SecureStorage.SetAsync(SessionKey, json))
                        .WaitAsync(TimeSpan.FromSeconds(5))
                        .GetAwaiter().GetResult();
                    
                    Log($"[MauiSessionPersistence] Session Saved via SecureStorage.");
                    #if WINDOWS
                    Daily.WinUI.AuthDebug.Log($"[MauiSessionPersistence] SecureStorage Success.");
                    #endif
                    
                    // Share with WatchOS
                    _watchConnectivityService?.SendSupabaseSession(session.AccessToken ?? "", session.RefreshToken ?? "");
                }
                catch (Exception ex)
                {
                    Log($"[MauiSessionPersistence] SecureStorage Failed ({ex.Message}). Falling back to Preferences...");
                    #if WINDOWS
                    Daily.WinUI.AuthDebug.Log($"[MauiSessionPersistence] SecureStorage Failed: {ex.Message}. Falling back...");
                    #endif
                    Preferences.Set(SessionKey, json);
                    Log($"[MauiSessionPersistence] Session Saved via Preferences.");
                    
                    // Share with WatchOS even on fallback
                    _watchConnectivityService?.SendSupabaseSession(session.AccessToken ?? "", session.RefreshToken ?? "");
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
                    // DEADLOCK FIX: Wrap in Task.Run + timeout
                    json = Task.Run(async () => await SecureStorage.GetAsync(SessionKey))
                        .WaitAsync(TimeSpan.FromSeconds(5))
                        .GetAwaiter().GetResult();
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
                    var session = JsonConvert.DeserializeObject<Session>(json);
                    if (session != null)
                    {
                        // Update in-memory cache
                        _cachedSession = session;
                        
                        // IMPORTANT: Sync loaded session to Apple Watch proactively on app startup
                        _watchConnectivityService?.SendSupabaseSession(session.AccessToken ?? "", session.RefreshToken ?? "");
                    }
                    return session;
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
