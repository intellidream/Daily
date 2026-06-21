using SQLite;
using Daily.Models;

namespace Daily.Services
{
    public class DatabaseService : IDatabaseService
    {
        private SQLiteAsyncConnection _connection;
        private bool _initialized = false;
        private readonly SemaphoreSlim _initLock = new SemaphoreSlim(1, 1);
        private const string DbName = "Daily.db3";

        public SQLiteAsyncConnection Connection => _connection;

        public DatabaseService()
        {
#if WINUI_NATIVE
            var appDataPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DailyApp");
            System.IO.Directory.CreateDirectory(appDataPath);
            var dbPath = Path.Combine(appDataPath, DbName);
#else
            var dbPath = Path.Combine(Microsoft.Maui.Storage.FileSystem.AppDataDirectory, DbName);
#endif
            var flags = SQLiteOpenFlags.ReadWrite | SQLiteOpenFlags.Create | SQLiteOpenFlags.SharedCache;
            // Reverting back to default (Ticks) because historical data was already saved as Ticks.
            _connection = new SQLiteAsyncConnection(dbPath, flags);
        }

        public async Task InitializeAsync()
        {
            if (_initialized) return;

            await _initLock.WaitAsync().ConfigureAwait(false);
            try 
            {
                if (_initialized) return;

                Console.WriteLine($"[DatabaseService] Initializing DB at: {_connection.DatabasePath}");
                
                // MIGRATION: Rename legacy tables if they exist
                await RenameTableIfExists("local_habit_logs", "habits_logs").ConfigureAwait(false);
                await RenameTableIfExists("local_habit_goals", "habits_goals").ConfigureAwait(false);
                await RenameTableIfExists("local_user_preferences", "user_preferences").ConfigureAwait(false);
                
                var res1 = await _connection.CreateTableAsync<LocalHabitLog>().ConfigureAwait(false);
                var res2 = await _connection.CreateTableAsync<LocalHabitGoal>().ConfigureAwait(false);
                var res3 = await _connection.CreateTableAsync<LocalUserPreferences>().ConfigureAwait(false);
                var res4 = await _connection.CreateTableAsync<LocalDailySummary>().ConfigureAwait(false);
                
                // Finances
                var res5 = await _connection.CreateTableAsync<Daily.Models.Finances.LocalAccount>().ConfigureAwait(false);
                var res6 = await _connection.CreateTableAsync<Daily.Models.Finances.LocalTransaction>().ConfigureAwait(false);
                var res7 = await _connection.CreateTableAsync<Daily.Models.Finances.LocalSecurity>().ConfigureAwait(false);
                var res8 = await _connection.CreateTableAsync<Daily.Models.Finances.LocalHolding>().ConfigureAwait(false);
                var res9 = await _connection.CreateTableAsync<Daily.Models.Finances.LocalWatchlist>().ConfigureAwait(false);
                var res10 = await _connection.CreateTableAsync<Daily.Models.Finances.LocalMacroIndicator>().ConfigureAwait(false);
                var res11 = await _connection.CreateTableAsync<Daily.Models.Finances.LocalCountryEconomicData>().ConfigureAwait(false);
                var res11b = await _connection.CreateTableAsync<Daily.Models.Finances.LocalSmartLedger>().ConfigureAwait(false);
                
                // Smart Agent
                await _connection.CreateTableAsync<LocalBehaviorEvent>().ConfigureAwait(false);
                await _connection.CreateTableAsync<LocalNavigationTransition>().ConfigureAwait(false);

                // RSS Saved Articles
                await _connection.CreateTableAsync<LocalSavedArticle>().ConfigureAwait(false);
                await _connection.CreateTableAsync<LocalRssSubscription>().ConfigureAwait(false);
                
                // Health (Vitals)
                await _connection.CreateTableAsync<LocalVitalMetric>().ConfigureAwait(false);

                // Calendar Integration
                await _connection.CreateTableAsync<LocalCalendarAccount>().ConfigureAwait(false);
                await _connection.CreateTableAsync<LocalCalendarEvent>().ConfigureAwait(false);
                await _connection.CreateTableAsync<LocalCalendarTodo>().ConfigureAwait(false);

                // Smart Behavior
                await _connection.CreateTableAsync<SmartBehaviorEvent>().ConfigureAwait(false);

                // Smart Briefing Cache
                await _connection.CreateTableAsync<CachedSmartBriefing>().ConfigureAwait(false);
                
                // FORCE MIGRATION: Ensure UpdatedAt exists (sqlite-net-pcl upgrade glitch protection)
                await AddColumnIfNotExists("user_preferences", "UpdatedAt", "varchar").ConfigureAwait(false);
                
                // Habits & Smokes Migrations
                await AddColumnIfNotExists("user_preferences", "SmokesBaselineDaily", "integer").ConfigureAwait(false);
                await AddColumnIfNotExists("user_preferences", "SmokesPackSize", "integer").ConfigureAwait(false);
                await AddColumnIfNotExists("user_preferences", "SmokesPackCost", "real").ConfigureAwait(false);
                await AddColumnIfNotExists("user_preferences", "SmokesCurrency", "varchar").ConfigureAwait(false);
                await AddColumnIfNotExists("user_preferences", "SmokesQuitDate", "bigint").ConfigureAwait(false);
                
                // WinUI Widgets Migration
                await AddColumnIfNotExists("user_preferences", "WinUIDashboardWidgetsJson", "varchar").ConfigureAwait(false);
                
                Console.WriteLine($"[DatabaseService] Tables Created results: {res1}, {res2}, {res3}, {res4}");
                
                _initialized = true;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[DatabaseService] Init Critical Error: {ex}");
                throw;
            }
            finally
            {
                 _initLock.Release();
            }
        }

        private class TableInfo
        {
            public string Name { get; set; } = string.Empty;
        }

        private async Task AddColumnIfNotExists(string tableName, string columnName, string columnType)
        {
            try
            {
                var columns = await _connection.QueryAsync<TableInfo>($"PRAGMA table_info({tableName})");
                if (!columns.Any(c => string.Equals(c.Name, columnName, StringComparison.OrdinalIgnoreCase)))
                {
                    await _connection.ExecuteAsync($"ALTER TABLE {tableName} ADD COLUMN {columnName} {columnType}");
                    Console.WriteLine($"[DatabaseService] Added column {columnName} to {tableName}");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[DatabaseService] Add Column Error ({tableName}.{columnName}): {ex.Message}");
            }
        }

        private async Task RenameTableIfExists(string oldName, string newName)
        {
            try
            {
                // Check if old table exists
                var tableExists = await _connection.ExecuteScalarAsync<int>(
                    "SELECT count(*) FROM sqlite_master WHERE type='table' AND name=?", oldName);

                if (tableExists > 0)
                {
                    // Check if new table already exists (don't overwrite)
                    var newTableExists = await _connection.ExecuteScalarAsync<int>(
                        "SELECT count(*) FROM sqlite_master WHERE type='table' AND name=?", newName);

                    if (newTableExists == 0)
                    {
                        Console.WriteLine($"[DatabaseService] Migrating table {oldName} -> {newName}");
                        await _connection.ExecuteAsync($"ALTER TABLE {oldName} RENAME TO {newName}");
                    }
                    else
                    {
                         Console.WriteLine($"[DatabaseService] Migration skipped: {newName} already exists. Old {oldName} remains.");
                    }
                }
            }
            catch (Exception ex)
            {
                 Console.WriteLine($"[DatabaseService] Table Rename Error ({oldName}->{newName}): {ex.Message}");
            }
        }
    }
}
