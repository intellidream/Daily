using Daily.Models;
using Supabase.Postgrest;
using Supabase.Realtime;

namespace Daily.Services
{
    public class SettingsService : ISettingsService
    {
        private readonly Supabase.Client _supabase;
        private readonly IDatabaseService _databaseService;
        private readonly ISyncService _syncService; // To trigger sync on save
        private Supabase.Realtime.RealtimeChannel? _preferencesChannel;
        private UserPreferences _currentSettings = new UserPreferences();
        private readonly System.Threading.SemaphoreSlim _realtimeSemaphore = new(1, 1);
        
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
            try
            {
                _supabase = supabase;
                _databaseService = databaseService;
                _syncService = syncService;

                // Subscribe to Background Sync Updates
                _syncService.OnPreferencesPulled += () => 
                {
                    Console.WriteLine("[SettingsService] Preferences Pulled event received. Reloading...");
                    Task.Run(async () => 
                    {
                        try { await ReloadFromDatabaseAsync(); }
                        catch(Exception ex) { Console.WriteLine($"[SettingsService] Reload Failed: {ex}"); }
                    });
                };

                // Setup Auth Listener ONCE in Constructor
                 _supabase.Auth.AddStateChangedListener((sender, state) => 
                 {
                     Console.WriteLine($"[SettingsService] Auth State Changed: {state}");
                     if (state == Supabase.Gotrue.Constants.AuthState.SignedIn || state == Supabase.Gotrue.Constants.AuthState.SignedOut)
                     {
                          Console.WriteLine($"[SettingsService] Handling Auth Change ({state}). Reloading...");
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

                // Listen for Socket State Changes to Auto-Reconnect Channels
                _supabase.Realtime.AddStateChangedHandler((sender, state) =>
                {
                    Console.WriteLine($"[SettingsService] Realtime Socket State Changed: {state}");
                    if (state == Supabase.Realtime.Constants.SocketState.Open)
                    {
                        Console.WriteLine("[SettingsService] Realtime Socket opened/reconnected. Triggering SetupRealtimeAsync...");
                        Task.Run(async () => await SetupRealtimeAsync());
                    }
                });

                // Start periodic watchdog to heal disconnected channels
                StartWatchdog();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[SettingsService] Constructor FAULT: {ex}");
            }
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
                             // FIX: Do NOT delete old Guest data. 
                             // Use Case: User logs out. We want them to fall back to the "Device Settings" (Guest), not empty defaults.
                             // So we COPY guest settings to User, but keep Guest intact.
                             // await _databaseService.Connection.DeleteAsync<LocalUserPreferences>(oldId);

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

            // Start Realtime
            await SetupRealtimeAsync();

            // Notify UI
            OnSettingsChanged?.Invoke();
        }

        private void StartWatchdog()
        {
            Task.Run(async () =>
            {
                while (true)
                {
                    await Task.Delay(TimeSpan.FromMinutes(2));
                    try
                    {
                        if (IsAuthenticated)
                        {
                            if (_preferencesChannel == null || !_preferencesChannel.IsJoined)
                            {
                                Console.WriteLine("[SettingsService] Watchdog detected preferences channel is null or not joined. Re-subscribing...");
                                await SetupRealtimeAsync();
                            }
                        }
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"[SettingsService] Watchdog error: {ex.Message}");
                    }
                }
            });
        }

        private async Task SetupRealtimeAsync()
        {
            if (!IsAuthenticated)
            {
                if (_preferencesChannel != null)
                {
                    try { _preferencesChannel.Unsubscribe(); } catch { }
                    _preferencesChannel = null;
                }
                return;
            }
            
            await _realtimeSemaphore.WaitAsync();
            try 
            {
                if (_preferencesChannel != null && !_preferencesChannel.IsJoined)
                {
                    Console.WriteLine("[SettingsService] Realtime preferences channel exists but is not joined. Removing to recreate...");
                    try
                    {
                        _supabase.Realtime.Remove(_preferencesChannel);
                    }
                    catch (Exception removeEx)
                    {
                        Console.WriteLine($"[SettingsService] Error removing channel: {removeEx.Message}");
                    }
                    _preferencesChannel = null;
                }

                if (_preferencesChannel == null)
                {
                    _preferencesChannel = _supabase.Realtime.Channel("realtime", "public", "user_preferences");
                    _preferencesChannel.AddPostgresChangeHandler(Supabase.Realtime.PostgresChanges.PostgresChangesOptions.ListenType.All, OnPreferencesReceived);
                    await _preferencesChannel.Subscribe();
                    Console.WriteLine("[SettingsService] Realtime subscribed to user_preferences");
                }
            } 
            catch (Exception ex) 
            {
                Console.WriteLine($"[SettingsService] Realtime setup failed: {ex.Message}");
            }
            finally
            {
                _realtimeSemaphore.Release();
            }
        }

        private void OnPreferencesReceived(object sender, Supabase.Realtime.PostgresChanges.PostgresChangesResponse e)
        {
            try 
            {
                var remotePref = e.Model<UserPreferences>();
                
                if (remotePref != null && remotePref.Id == CurrentUserId)
                {
                    // Structurally prevent self-overwrite / stale cache overwrite
                    if (_currentSettings != null && remotePref.UpdatedAt <= _currentSettings.UpdatedAt)
                    {
                        Console.WriteLine($"[SettingsService] Realtime: Ignored stale/self broadcast. Remote: {remotePref.UpdatedAt}, Local: {_currentSettings.UpdatedAt}");
                        return;
                    }

                    var localPrefs = ToLocal(remotePref);
                    localPrefs.SyncedAt = DateTime.UtcNow; // Prevent push loop
                    
                    _databaseService.Connection.InsertOrReplaceAsync(localPrefs).ContinueWith(_ => 
                    {
                        _currentSettings = remotePref;
                        Console.WriteLine($"[SettingsService] Realtime: Synced incoming user preferences");
                        OnSettingsChanged?.Invoke();
                    });
                }
            } 
            catch(Exception ex) { Console.WriteLine($"[SettingsService] Realtime Preferences Error: {ex}"); }
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
                local.UpdatedAt = DateTime.UtcNow; // Set Update Time
                
                // CRITICAL: Update in-memory state so subsequent saves/UI calls have valid timestamp
                _currentSettings.UpdatedAt = local.UpdatedAt;
                
                var allPrefs = await _databaseService.Connection.Table<LocalUserPreferences>().ToListAsync();
                Console.WriteLine($"[SyncService] Total Local Prefs: {allPrefs.Count}. IDs: {string.Join(", ", allPrefs.Select(x => $"{x.Id} (Synced: {x.SyncedAt}, Updated: {x.UpdatedAt})"))}");

                var result = await _databaseService.Connection.InsertOrReplaceAsync(local);
                Console.WriteLine($"[SettingsService] Save Result: {result}. Saved UpdatedAt: {local.UpdatedAt}");

                // Verify Verification
                var verify = await _databaseService.Connection.Table<LocalUserPreferences>().Where(x => x.Id == userId).FirstOrDefaultAsync();
                Console.WriteLine($"[SettingsService] Verification Read: UpdatedAt in DB = {verify?.UpdatedAt}");

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
            var userPrefs = new UserPreferences
            {
                Id = local.Id,
                Theme = local.Theme,
                UnitSystem = (local.UnitSystem == "imperial") ? "imperial" : "metric",
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

            Console.WriteLine($"[SettingsService] ToDomain Raw: '{local.UnitSystem}' -> Sanitized: '{userPrefs.UnitSystem}'");
            userPrefs.DashboardWidgetsJson = local.DashboardWidgetsJson;
            userPrefs.WinUIDashboardWidgetsJson = local.WinUIDashboardWidgetsJson;
            userPrefs.UpdatedAt = local.UpdatedAt;
            return userPrefs;
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
                
                InterestsJson = System.Text.Json.JsonSerializer.Serialize(domain.Interests),
                DashboardWidgetsJson = domain.DashboardWidgetsJson,
                WinUIDashboardWidgetsJson = domain.WinUIDashboardWidgetsJson,
                UpdatedAt = domain.UpdatedAt
            };
        }

        public async Task ReloadFromDatabaseAsync()
        {
            var userId = IsAuthenticated ? CurrentUserId : Guid.Empty.ToString();
            
            var localTarget = await _databaseService.Connection.Table<LocalUserPreferences>()
                                   .Where(x => x.Id == userId)
                                   .FirstOrDefaultAsync();

            if (localTarget != null)
            {
                _currentSettings = ToDomain(localTarget);
                Console.WriteLine($"[SettingsService] Reload success. Notifying UI. (UpdatedAt: {_currentSettings.UpdatedAt})");
                OnSettingsChanged?.Invoke();
            }
            else
            {
                Console.WriteLine("[SettingsService] Reload skipped: No local target found.");
            }
        }
    }
}
