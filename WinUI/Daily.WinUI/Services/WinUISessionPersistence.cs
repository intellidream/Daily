using Supabase.Gotrue;
using Supabase.Gotrue.Interfaces;
using Windows.Security.Credentials;
using System.IO;
using System;
using System.Linq;

namespace Daily_WinUI.Services
{
    public class WinUISessionPersistence : IGotrueSessionPersistence<Session>
    {
        private const string SessionKey = "SupabaseSession";
        private const string PasswordVaultResource = "Daily_Supabase";

        private string GetSettingsFile(string key)
        {
            var appDataPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DailyApp");
            Directory.CreateDirectory(appDataPath);
            return Path.Combine(appDataPath, key + ".txt");
        }

        private void SaveSetting(string key, string value)
        {
            File.WriteAllText(GetSettingsFile(key), value);
        }

        private string? LoadSetting(string key)
        {
            var file = GetSettingsFile(key);
            return File.Exists(file) ? File.ReadAllText(file) : null;
        }

        private void DeleteSetting(string key)
        {
            var file = GetSettingsFile(key);
            if (File.Exists(file)) File.Delete(file);
        }

        public void SaveSession(Session session)
        {
            try
            {
                // Serialize the ENTIRE session to JSON to preserve CreatedAt, ProviderToken, and User metadata
                // CRITICAL: Must use Newtonsoft.Json because Supabase models use [JsonProperty] attributes
                var json = Newtonsoft.Json.JsonConvert.SerializeObject(session);
                SaveSetting(SessionKey + "_JSON", json);
                
                System.Diagnostics.Debug.WriteLine("[WinUISessionPersistence] Session saved via JSON serialization.");
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[WinUISessionPersistence] Error saving session: {ex.Message}");
            }
        }

        public void DestroySession()
        {
            DeleteSetting(SessionKey + "_JSON");
            
            // Cleanup legacy files just in case
            DeleteSetting("AccessToken");
            DeleteSetting("RefreshToken");
            DeleteSetting("ProviderToken");
            DeleteSetting(SessionKey + "_TokenType");
            DeleteSetting(SessionKey + "_ExpiresIn");
            DeleteSetting(SessionKey + "_UserId");
            DeleteSetting(SessionKey + "_UserEmail");
        }

        public Session? LoadSession()
        {
            try
            {
                var json = LoadSetting(SessionKey + "_JSON");
                if (!string.IsNullOrEmpty(json))
                {
                    return Newtonsoft.Json.JsonConvert.DeserializeObject<Session>(json);
                }
                
                // Fallback for legacy format if JSON doesn't exist
                var accessToken = LoadSetting("AccessToken");
                var refreshToken = LoadSetting("RefreshToken");
                if (!string.IsNullOrEmpty(accessToken))
                {
                    // This will be expired immediately, but better than nothing
                    return new Session { AccessToken = accessToken, RefreshToken = refreshToken };
                }
                
                return null;
            }
            catch
            {
                return null;
            }
        }

        private void RemoveCredential(string userName)
        {
            try
            {
                var vault = new PasswordVault();
                var credList = vault.FindAllByResource(PasswordVaultResource);
                var cred = credList.FirstOrDefault(c => c.UserName == userName);
                if (cred != null)
                {
                    vault.Remove(cred);
                }
            }
            catch
            {
                // FindAllByResource throws if not found
            }
        }

        private string? GetCredential(string userName)
        {
            try
            {
                var vault = new PasswordVault();
                var credList = vault.FindAllByResource(PasswordVaultResource);
                var cred = credList.FirstOrDefault(c => c.UserName == userName);
                if (cred != null)
                {
                    cred.RetrievePassword();
                    return cred.Password;
                }
            }
            catch
            {
            }
            return null;
        }
    }
}
