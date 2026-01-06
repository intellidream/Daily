using Daily.Models;
using SQLite;

namespace Daily.Services
{
    public class HabitsRepository : IHabitsRepository
    {
        private readonly IDatabaseService _databaseService;

        public HabitsRepository(IDatabaseService databaseService)
        {
            _databaseService = databaseService;
        }

        public async Task<List<HabitLog>> GetLogsAsync(string habitType, DateTime date, string userId)
        {
            await _databaseService.InitializeAsync();
            
            // Ensure we use Local Midnight as anchor, regardless of what time comes in
            var localMidnight = date.Date;
            var startUtc = localMidnight.ToUniversalTime(); 
            var endUtc = localMidnight.AddDays(1).ToUniversalTime();

            // Fetch from Local DB with UserID filter
            var localLogs = await _databaseService.Connection.Table<LocalHabitLog>()
                                .Where(l => l.HabitType == habitType && l.UserId == userId && l.IsDeleted == false) 
                                .ToListAsync();
            
            return localLogs
                .Where(l => l.LoggedAt >= startUtc && l.LoggedAt < endUtc)
                .Select(ToDomain)
                .OrderByDescending(l => l.LoggedAt)
                .ToList();
        }

        public async Task SaveLogAsync(HabitLog log)
        {
             await _databaseService.InitializeAsync();
             
             var local = ToLocal(log);
             // Ensure ID is set
             if (string.IsNullOrEmpty(local.Id)) local.Id = Guid.NewGuid().ToString();
             
             await _databaseService.Connection.InsertOrReplaceAsync(local);
        }

        public async Task DeleteLogAsync(Guid logId)
        {
            await _databaseService.InitializeAsync();
            
            // Soft Delete using ID only (ID is PK)
            await _databaseService.Connection.ExecuteAsync(
                "UPDATE local_habit_logs SET IsDeleted = 1, SyncedAt = NULL WHERE Id = ?", 
                logId.ToString());
        }

        public async Task<HabitGoal?> GetGoalAsync(string habitType, string userId)
        {
            await _databaseService.InitializeAsync();

            var local = await _databaseService.Connection.Table<LocalHabitGoal>()
                            .Where(g => g.HabitType == habitType && g.UserId == userId)
                            .FirstOrDefaultAsync();

            return local == null ? null : ToDomain(local);
        }

        public async Task SaveGoalAsync(HabitGoal goal)
        {
            await _databaseService.InitializeAsync();
            var local = ToLocal(goal);
            await _databaseService.Connection.InsertOrReplaceAsync(local);
        }

        public async Task MigrateGuestDataAsync(string newUserId)
        {
            await _databaseService.InitializeAsync();

            // 1. Migrate Logs
            // Find all logs belonging to "guest" OR Guid.Empty
            // We can't do OR in one SQLite Where usually, so let's do two checks or a contains.
            // Simple approach: Check both.
            
            var guestIds = new[] { "guest", Guid.Empty.ToString() };
            var guestLogs = await _databaseService.Connection.Table<LocalHabitLog>()
                                .Where(l => guestIds.Contains(l.UserId))
                                .ToListAsync();

            if (guestLogs.Any())
            {
                foreach (var log in guestLogs)
                {
                    log.UserId = newUserId;
                    log.SyncedAt = null; // Mark Dirty for Push
                }
                await _databaseService.Connection.UpdateAllAsync(guestLogs);
                Console.WriteLine($"[HabitsRepository] Migrated {guestLogs.Count} logs from Guest to {newUserId}");
            }

            // 2. Migrate Goals
            var guestGoals = await _databaseService.Connection.Table<LocalHabitGoal>()
                                .Where(g => guestIds.Contains(g.UserId))
                                .ToListAsync();

            if (guestGoals.Any())
            {
                foreach (var goal in guestGoals)
                {
                    var existing = await _databaseService.Connection.Table<LocalHabitGoal>()
                                    .Where(g => g.UserId == newUserId && g.HabitType == goal.HabitType)
                                    .CountAsync();
                    
                    if (existing == 0)
                    {
                        goal.UserId = newUserId;
                        goal.SyncedAt = null;
                        await _databaseService.Connection.UpdateAsync(goal);
                    }
                    else
                    {
                         // Clean up redundant
                         await _databaseService.Connection.DeleteAsync(goal);
                    }
                }
                Console.WriteLine($"[HabitsRepository] Processed migration for {guestGoals.Count} guest goals.");
            }
        }

        // Mappers
        private HabitLog ToDomain(LocalHabitLog local)
        {
            return new HabitLog
            {
                Id = Guid.Parse(local.Id),
                UserId = Guid.Parse(local.UserId),
                HabitType = local.HabitType,
                Value = local.Value,
                Unit = local.Unit,
                LoggedAt = local.LoggedAt,
                Metadata = local.Metadata,
                CreatedAt = local.CreatedAt,
                UpdatedAt = local.UpdatedAt,
                SyncedAt = local.SyncedAt,
                IsDeleted = local.IsDeleted
            };
        }

        private LocalHabitLog ToLocal(HabitLog domain)
        {
            return new LocalHabitLog
            {
                Id = domain.Id.ToString(),
                UserId = domain.UserId.ToString(),
                HabitType = domain.HabitType,
                Value = domain.Value,
                Unit = domain.Unit,
                LoggedAt = domain.LoggedAt,
                Metadata = domain.Metadata,
                CreatedAt = domain.CreatedAt,
                UpdatedAt = domain.UpdatedAt,
                SyncedAt = domain.SyncedAt, // Usually null on save
                IsDeleted = domain.IsDeleted
            };
        }

        private HabitGoal ToDomain(LocalHabitGoal local)
        {
            return new HabitGoal
            {
                Id = Guid.Parse(local.Id),
                UserId = Guid.Parse(local.UserId),
                HabitType = local.HabitType,
                TargetValue = local.TargetValue,
                Unit = local.Unit,
                CreatedAt = local.CreatedAt,
                UpdatedAt = local.UpdatedAt,
                SyncedAt = local.SyncedAt,
                IsDeleted = local.IsDeleted
            };
        }

        private LocalHabitGoal ToLocal(HabitGoal domain)
        {
            return new LocalHabitGoal
            {
                Id = domain.Id.ToString(),
                UserId = domain.UserId.ToString(),
                HabitType = domain.HabitType,
                TargetValue = domain.TargetValue,
                Unit = domain.Unit,
                CreatedAt = domain.CreatedAt,
                UpdatedAt = domain.UpdatedAt,
                SyncedAt = domain.SyncedAt,
                IsDeleted = domain.IsDeleted
            };
        }
    }
}
