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
                .Select(l => l.ToDomain())
                .OrderByDescending(l => l.LoggedAt)
                .ToList();
        }

        public async Task SaveLogAsync(HabitLog log)
        {
             await _databaseService.InitializeAsync();
             
             var local = log.ToLocal();
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

            return local == null ? null : local.ToDomain();
        }

        public async Task SaveGoalAsync(HabitGoal goal)
        {
            await _databaseService.InitializeAsync();
            var local = goal.ToLocal();
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
        // Aggregation Methods
        public async Task<List<DailySummary>> GetDailyTotalsAsync(string habitType, DateTime startDate, DateTime endDate, string userId)
        {
             await _databaseService.InitializeAsync();
             
             // 1. Fetch Local Summaries
             // SQLite doesn't support Date range directly on DateTime columns stored as string unless we use Ticks or careful String Comp.
             // We configured "storeDateTimeAsTicks: false", so ISO strings.
             // ISO Strings are sortable/comparable directly.
             
             // Note: startDate and endDate should be Midnight UTC for reliable query.
             var sDate = startDate.ToUniversalTime().Date;
             var eDate = endDate.ToUniversalTime().Date.AddDays(1); // Include end date

             // Need strict string format for comparison if underlying is string
             // But sqlite-net-pcl handles DateTime mappings if configured.
             // Let's assume standard Linq Works:
             var summaries = await _databaseService.Connection.Table<LocalDailySummary>()
                                .Where(s => s.HabitType == habitType && s.UserId == userId && s.Date >= sDate && s.Date < eDate)
                                .ToListAsync();

             // 2. Fetch Raw Logs (for the same period)
             // We assume raw logs only exist for the last 90 days, but we query whatever is there.
             // If raw logs exist, they are "Verified Truth" and supersede summaries.
             var rawLogs = await _databaseService.Connection.Table<LocalHabitLog>()
                                .Where(l => l.HabitType == habitType && l.UserId == userId && l.IsDeleted == false && l.LoggedAt >= sDate && l.LoggedAt < eDate)
                                .ToListAsync();

            // 3. Merge: Pivot on Date
             // We want a list of DailySummary objects covering the range where data exists.
             var resultMap = new Dictionary<DateTime, DailySummary>();

             // A. Fill from Summaries
             foreach(var s in summaries)
             {
                 if (!resultMap.ContainsKey(s.Date.Date))
                 {
                     resultMap[s.Date.Date] = s.ToDomain();
                 }
             }

             // B. Fill/Overwrite from Raw Logs (Hybrid Logic)
             if (rawLogs.Any())
             {
                 var groupedRaw = rawLogs.GroupBy(x => x.LoggedAt.Date);
                 foreach(var g in groupedRaw)
                 {
                     // Re-calculate Summary from Raw
                     var freshSummary = new DailySummary
                     {
                         Id = Guid.Empty, // Ephemeral
                         UserId = Guid.Parse(userId),
                         HabitType = habitType,
                         Date = g.Key,
                         TotalValue = g.Sum(x => x.Value),
                         LogCount = g.Count(),
                         Metadata = "Realtime" // Flag logic
                     };

                     // Overwrite or Add
                     resultMap[g.Key] = freshSummary;
                 }
             }

             return resultMap.Values.OrderBy(x => x.Date).ToList();
        }

        public async Task<DailySummary> GetGlobalTotalsAsync(string habitType, string userId)
        {
            await _databaseService.InitializeAsync();
            
            // This is trickier if we have overlap.
            // Strategy: Get All Summaries + Get All Logs. 
            // Calculate Dates present in Logs -> Use Log Total.
            // Calculate Dates NOT present in Logs but in Summaries -> Use Summary Total.
            
            // Performance: If 20 years of data, getting all logs is bad.
            // But we know Logs are < 90 Days. So getting all logs is 90 days * 20 = 1800 rows. Fast.
            // Getting all Summaries is 20 * 365 = 7300 rows. Fast.
            
            var allSummaries = await _databaseService.Connection.Table<LocalDailySummary>()
                                .Where(s => s.HabitType == habitType && s.UserId == userId)
                                .ToListAsync();

            var allLogs = await _databaseService.Connection.Table<LocalHabitLog>()
                                .Where(l => l.HabitType == habitType && l.UserId == userId && l.IsDeleted == false)
                                .ToListAsync();

            var logDates = allLogs.Select(l => l.LoggedAt.Date).ToHashSet();
            
            double totalValue = 0;
            int totalCount = 0;

            // 1. Sum up Logs (The verified truth)
            totalValue += allLogs.Sum(l => l.Value);
            totalCount += allLogs.Count;

            // 2. Sum up Summaries (Only for days NOT in logs)
            foreach(var s in allSummaries)
            {
                 if (!logDates.Contains(s.Date.Date))
                 {
                     totalValue += s.TotalValue;
                     totalCount += s.LogCount;
                 }
            }
            
            return new DailySummary
            {
                Id = Guid.Empty,
                UserId = Guid.Parse(userId),
                HabitType = habitType,
                TotalValue = totalValue,
                LogCount = totalCount,
                Date = DateTime.MinValue // Meaningless for Global
            };
        }
    }
}
