using Daily.Models;
using Supabase.Postgrest;

namespace Daily.Services
{
    public class SettingsService : ISettingsService
    {
        private readonly Supabase.Client _supabase;
        private UserPreferences _currentSettings = new UserPreferences();
        
        public UserPreferences Settings => _currentSettings;
        public bool IsAuthenticated => _supabase.Auth.CurrentSession != null;
        public string? CurrentUserEmail => _supabase.Auth.CurrentSession?.User?.Email;
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

        public event Action OnSettingsChanged;

        public SettingsService(Supabase.Client supabase)
        {
            _supabase = supabase;
        }

        public async Task InitializeAsync()
        {
            // 1. Load local defaults (or local storage if we had it)
            try 
            {
                var json = Microsoft.Maui.Storage.Preferences.Get("user_prefs", null);
                if (!string.IsNullOrEmpty(json))
                {
                    var local = System.Text.Json.JsonSerializer.Deserialize<UserPreferences>(json);
                    if (local != null) _currentSettings = local;
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error loading local settings: {ex.Message}");
            }

            // 2. If online, fetch from Supabase
            if (IsAuthenticated)
            {
                await LinkToUserAndSync();
            }
            
            // Notify initial state
            OnSettingsChanged?.Invoke();
        }

        private async Task LinkToUserAndSync()
        {
            try
            {
                var userId = _supabase.Auth.CurrentUser.Id;
                var response = await _supabase.From<UserPreferences>()
                                            .Where(x => x.Id == userId)
                                            .Get();
                
                var remoteSettings = response.Models.FirstOrDefault();
                if (remoteSettings != null)
                {
                    // Merge remote synced properties into current settings
                    // Only overwrite properties that are actually synced to DB
                    _currentSettings.Id = remoteSettings.Id;
                    _currentSettings.Theme = remoteSettings.Theme;
                    _currentSettings.UnitSystem = remoteSettings.UnitSystem;
                    _currentSettings.PressureUnit = remoteSettings.PressureUnit;
                    _currentSettings.Interests = remoteSettings.Interests;
                    
                    // Sync General Config
                    _currentSettings.WindUnit = remoteSettings.WindUnit;
                    _currentSettings.VisibilityUnit = remoteSettings.VisibilityUnit;
                    _currentSettings.PrecipitationUnit = remoteSettings.PrecipitationUnit;
                    _currentSettings.NotificationsEnabled = remoteSettings.NotificationsEnabled;
                    _currentSettings.DailyForecastAlert = remoteSettings.DailyForecastAlert;
                    _currentSettings.PrecipitationAlert = remoteSettings.PrecipitationAlert;

                    // Sync Smokes Config
                    _currentSettings.SmokesBaselineDaily = remoteSettings.SmokesBaselineDaily;
                    _currentSettings.SmokesPackSize = remoteSettings.SmokesPackSize;
                    _currentSettings.SmokesPackCost = remoteSettings.SmokesPackCost;
                    _currentSettings.SmokesCurrency = remoteSettings.SmokesCurrency;
                    _currentSettings.SmokesQuitDate = remoteSettings.SmokesQuitDate;

                    // Do NOT overwrite local-only properties (WindUnit, etc) with remote defaults
                }
                else
                {
                    // No remote settings yet, but we are auth'd. 
                    // Let's adopt the current ID so next save works.
                    _currentSettings.Id = userId;
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error syncing settings: {ex.Message}");
            }
        }

        public async Task SaveSettingsAsync()
        {
            try
            {
                // Notify listeners immediately for responsive UI
                OnSettingsChanged?.Invoke();
                
                // Save to local storage
                var json = System.Text.Json.JsonSerializer.Serialize(_currentSettings);
                Microsoft.Maui.Storage.Preferences.Set("user_prefs", json);

                if (IsAuthenticated)
                {
                    var userId = _supabase.Auth.CurrentUser.Id;
                    _currentSettings.Id = userId; // Ensure ID matches
                    
                    await _supabase.From<UserPreferences>().Upsert(_currentSettings);
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error saving settings: {ex.Message}");
                // Revert or notify error? For now, silent fail log.
            }
        }
    }
}
