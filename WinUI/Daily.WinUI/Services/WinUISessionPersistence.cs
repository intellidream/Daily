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
                var vault = new PasswordVault();
                
                // Save access/refresh tokens via Vault for security
                if (!string.IsNullOrEmpty(session.AccessToken))
                {
                    vault.Add(new PasswordCredential(PasswordVaultResource, "AccessToken", session.AccessToken));
                }
                if (!string.IsNullOrEmpty(session.RefreshToken))
                {
                    vault.Add(new PasswordCredential(PasswordVaultResource, "RefreshToken", session.RefreshToken));
                }
                
                // Save ProviderToken (used for YouTube) in Vault as well
                if (!string.IsNullOrEmpty(session.ProviderToken))
                {
                    vault.Add(new PasswordCredential(PasswordVaultResource, "ProviderToken", session.ProviderToken));
                }
                else
                {
                    RemoveCredential("ProviderToken");
                }

                // Save non-sensitive session data
                SaveSetting(SessionKey + "_TokenType", session.TokenType ?? "bearer");
                SaveSetting(SessionKey + "_ExpiresIn", session.ExpiresIn.ToString());
                
                if (session.User != null)
                {
                    SaveSetting(SessionKey + "_UserId", session.User.Id ?? "");
                    SaveSetting(SessionKey + "_UserEmail", session.User.Email ?? "");
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[WinUISessionPersistence] Error saving session: {ex.Message}");
            }
        }

        public void DestroySession()
        {
            RemoveCredential("AccessToken");
            RemoveCredential("RefreshToken");
            RemoveCredential("ProviderToken");

            DeleteSetting(SessionKey + "_TokenType");
            DeleteSetting(SessionKey + "_ExpiresIn");
            DeleteSetting(SessionKey + "_UserId");
            DeleteSetting(SessionKey + "_UserEmail");
        }

        public Session? LoadSession()
        {
            try
            {
                var vault = new PasswordVault();
                var accessToken = GetCredential("AccessToken");
                var refreshToken = GetCredential("RefreshToken");
                var providerToken = GetCredential("ProviderToken");

                if (string.IsNullOrEmpty(accessToken) && string.IsNullOrEmpty(refreshToken))
                {
                    return null;
                }

                long expiresIn = 3600;
                var expiresInStr = LoadSetting(SessionKey + "_ExpiresIn");
                if (!string.IsNullOrEmpty(expiresInStr) && long.TryParse(expiresInStr, out long parsed))
                {
                    expiresIn = parsed;
                }

                var session = new Session
                {
                    AccessToken = accessToken,
                    RefreshToken = refreshToken,
                    ProviderToken = providerToken,
                    TokenType = LoadSetting(SessionKey + "_TokenType") ?? "bearer",
                    ExpiresIn = expiresIn
                };

                var userId = LoadSetting(SessionKey + "_UserId");
                if (!string.IsNullOrEmpty(userId))
                {
                    session.User = new User
                    {
                        Id = userId,
                        Email = LoadSetting(SessionKey + "_UserEmail")
                    };
                }

                return session;
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
