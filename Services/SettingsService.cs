using Daily.Models;
using Supabase.Postgrest;

namespace Daily.Services
{
    public class SettingsService : ISettingsService
    {
        private readonly Supabase.Client _supabase;
        private readonly IDatabaseService _databaseService;
        private readonly ISyncService _syncService; // To trigger sync on save
        private UserPreferences _currentSettings = new UserPreferences();
        
        public UserPreferences Settings => _currentSettings;
        public bool IsAuthenticated => _supabase.Auth.CurrentSession != null;
        public string? CurrentUserId => _supabase.Auth.CurrentUser?.Id;
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

        public SettingsService(Supabase.Client supabase, IDatabaseService databaseService, ISyncService syncService)
        {
            _supabase = supabase;
            _databaseService = databaseService;
            _syncService = syncService;

            // Setup Auth Listener ONCE in Constructor
             _supabase.Auth.AddStateChangedListener((sender, state) => 
            {
                Console.WriteLine($"[SettingsService] Auth State Changed: {state}");
                if (state == Supabase.Gotrue.Constants.AuthState.SignedIn)
                {
                     // Use robust fire-and-forget with extensive logging
                     Task.Run(async () => 
                     {
                         try 
                         {
                             await InitializeAsync();
                         }
                         catch(Exception ex)
                         {
                             Console.WriteLine($"[SettingsService] CRITICAL: Post-Auth Reload Failed: {ex}");
                         }
                     });
                }
            });
        }

        public async Task InitializeAsync()
        {
            await _databaseService.InitializeAsync();
             
             // 1. Determine Identity
             var isAuth = IsAuthenticated;
             // Unify Guest Identity to Guid.Empty (Zeros)
             var userId = isAuth ? CurrentUserId : Guid.Empty.ToString();
             
             Console.WriteLine($"[SettingsService] Initializing. Auth: {isAuth}, UserID: {userId}");

             // 2. Load Target Settings (Local)
             var localTarget = await _databaseService.Connection.Table<LocalUserPreferences>()
                                    .Where(x => x.Id == userId)
                                    .FirstOrDefaultAsync();

             // 3. Authenticated Identity Logic
             if (isAuth)
             {
                 // SCENARIO A: Authenticated but no local data for this user ID.
                 if (localTarget == null)
                 {
                     Console.WriteLine("[SettingsService] No local settings for User. Checking for migration or Cloud pull...");
                     
                     // 3a. Try to Pull from Cloud first (Source of Truth)
                     int pulled = await _syncService.PullAsync(); 
                     
                     // Re-check local after pull
                     localTarget = await _databaseService.Connection.Table<LocalUserPreferences>()
                                    .Where(x => x.Id == userId)
                                    .FirstOrDefaultAsync();

                     // 3b. If STILL NULL, check for "Guest" data to migrate
                     // Check BOTH legacy "guest" string AND Guid.Empty zero-string
                     if (localTarget == null)
                     {
                         var guestIds = new[] { "guest", Guid.Empty.ToString() };
                         var localGuest = await _databaseService.Connection.Table<LocalUserPreferences>()
                                            .Where(x => guestIds.Contains(x.Id))
                                            .FirstOrDefaultAsync();
                         
                         if (localGuest != null)
                         {
                             // MIGRATION: Guest -> User
                             Console.WriteLine($"[SettingsService] Migrating Guest Settings ({localGuest.Id}) to User {userId}...");
                             
                             // Delete old guest record first to avoid PK collision if we were to insert new
                             // But since we are modifying ID in memory and inserting "New", it's fine.
                             // Actually, better to Delete old, then Insert new, OR Update if we could.
                             // Since ID is PK, we can't update ID. Must Insert New, Delete Old.
                             
                             var oldId = localGuest.Id;
                             localTarget = localGuest;
                             localTarget.Id = userId; // Rebrand as User
                             localTarget.SyncedAt = null; // Mark Dirty for Push
                             
                             await _databaseService.Connection.InsertOrReplaceAsync(localTarget);
                             await _databaseService.Connection.DeleteAsync<LocalUserPreferences>(oldId);

                             // Trigger Push of migrated data
                             Task.Run(async () => await _syncService.PushAsync());
                         }
                         else
                         {
                             // No Guest data? Just defaults.
                             Console.WriteLine("[SettingsService] No Guest data to migrate. Using Defaults.");
                         }
                     }
                 }
                 else
                 {
                     // SCENARIO B: Authenticated AND Local Data Exists.
                     Console.WriteLine("[SettingsService] Local User Settings found. Triggering Background Sync.");
                     Task.Run(async () => await _syncService.SyncAsync());
                 }
             }

             // 4. Final Load
             if (localTarget != null)
             {
                 _currentSettings = ToDomain(localTarget);
             }
             else
             {
                 // Default Fallback
                 _currentSettings = new UserPreferences { Id = userId };
             }

            // Notify UI
            OnSettingsChanged?.Invoke();
        }

        public async Task SaveSettingsAsync()
        {
            try
            {
                // Notify listeners immediately for responsive UI
                OnSettingsChanged?.Invoke();
                
                // Save to local storage (SQLite)
                var userId = IsAuthenticated ? CurrentUserId : Guid.Empty.ToString(); 
                _currentSettings.Id = userId; 

                Console.WriteLine($"[SettingsService] Saving settings for UserID: {userId}...");

                var local = ToLocal(_currentSettings);
                local.SyncedAt = null; // Dirty
                
                var result = await _databaseService.Connection.InsertOrReplaceAsync(local);
                Console.WriteLine($"[SettingsService] Save Result: {result}"); // Should be 1 (rows affected)

                // Trigger Background Sync
                if (IsAuthenticated)
                {
                    Task.Run(async () => await _syncService.SyncAsync());
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[SettingsService] Error saving settings: {ex.Message}");
            }
        }

        private UserPreferences ToDomain(LocalUserPreferences local)
        {
            return new UserPreferences
            {
                Id = local.Id,
                Theme = local.Theme,
                UnitSystem = local.UnitSystem,
                PressureUnit = local.PressureUnit,
                Interests = string.IsNullOrEmpty(local.InterestsJson) 
                            ? new List<string>() 
                            : System.Text.Json.JsonSerializer.Deserialize<List<string>>(local.InterestsJson) ?? new List<string>(),
                
                WindUnit = local.WindUnit,
                VisibilityUnit = local.VisibilityUnit,
                PrecipitationUnit = local.PrecipitationUnit,
                NotificationsEnabled = local.NotificationsEnabled,
                DailyForecastAlert = local.DailyForecastAlert,
                PrecipitationAlert = local.PrecipitationAlert,
                
                SmokesBaselineDaily = local.SmokesBaselineDaily,
                SmokesPackSize = local.SmokesPackSize,
                SmokesPackCost = local.SmokesPackCost,
                SmokesCurrency = local.SmokesCurrency,
                SmokesQuitDate = local.SmokesQuitDate
            };
        }

        private LocalUserPreferences ToLocal(UserPreferences domain)
        {
            return new LocalUserPreferences
            {
                Id = domain.Id, // Should be set before calling
                Theme = domain.Theme,
                UnitSystem = domain.UnitSystem,
                
                PressureUnit = domain.PressureUnit,
                WindUnit = domain.WindUnit,
                VisibilityUnit = domain.VisibilityUnit,
                PrecipitationUnit = domain.PrecipitationUnit,
                
                NotificationsEnabled = domain.NotificationsEnabled,
                DailyForecastAlert = domain.DailyForecastAlert,
                PrecipitationAlert = domain.PrecipitationAlert,
                
                SmokesBaselineDaily = domain.SmokesBaselineDaily,
                SmokesPackSize = domain.SmokesPackSize,
                SmokesPackCost = domain.SmokesPackCost,
                SmokesCurrency = domain.SmokesCurrency,
                SmokesQuitDate = domain.SmokesQuitDate,
                
                InterestsJson = System.Text.Json.JsonSerializer.Serialize(domain.Interests)
            };
        }
    }
}
