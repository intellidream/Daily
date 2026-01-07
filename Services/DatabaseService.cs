using SQLite;
using Daily.Models;

namespace Daily.Services
{
    public class DatabaseService : IDatabaseService
    {
        private SQLiteAsyncConnection _connection;
        private bool _initialized = false;
        private const string DbName = "Daily.db3";

        public SQLiteAsyncConnection Connection => _connection;

        public DatabaseService()
        {
            var dbPath = Path.Combine(FileSystem.AppDataDirectory, DbName);
            var flags = SQLiteOpenFlags.ReadWrite | SQLiteOpenFlags.Create | SQLiteOpenFlags.SharedCache;
            
            // Fix: Store DateTime as Strings (ISO 8601) instead of Ticks for compatibility and readability
            _connection = new SQLiteAsyncConnection(dbPath, flags, storeDateTimeAsTicks: false);
        }

        public async Task InitializeAsync()
        {
            if (_initialized) return;

            try 
            {
                Console.WriteLine($"[DatabaseService] Initializing DB at: {_connection.DatabasePath}");
                
                // MIGRATION: Rename legacy tables if they exist
                await RenameTableIfExists("local_habit_logs", "habits_logs");
                await RenameTableIfExists("local_habit_goals", "habits_goals");
                await RenameTableIfExists("local_user_preferences", "user_preferences");
                
                var res1 = await _connection.CreateTableAsync<LocalHabitLog>();
                var res2 = await _connection.CreateTableAsync<LocalHabitGoal>();
                var res3 = await _connection.CreateTableAsync<LocalUserPreferences>();
                var res4 = await _connection.CreateTableAsync<LocalDailySummary>();
                Console.WriteLine($"[DatabaseService] Tables Created results: {res1}, {res2}, {res3}, {res4}");
                
                _initialized = true;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[DatabaseService] Init Critical Error: {ex}");
                throw;
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
                         // Both exist? Maybe merge? For now, we assume new code uses new table.
                         // But if user wants to keep old data, they might be in old table.
                         // Since this is a dev environment transition, let's just Log and ignore, 
                         // or maybe we should have merged? 
                         // Safest: Do nothing if target exists.
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
