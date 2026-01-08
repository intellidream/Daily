using Daily.Models;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace Daily.Services
{
    public interface ISeederService
    {
        Task SeedHistoryAsync(string userId);
    }

    public class SeederService : ISeederService
    {
        private readonly IDatabaseService _databaseService;
        private readonly ISyncService _syncService;

        public SeederService(IDatabaseService databaseService, ISyncService syncService)
        {
            _databaseService = databaseService;
            _syncService = syncService;
        }

        public async Task SeedHistoryAsync(string userId)
        {
            var logs = new List<LocalHabitLog>();
            var random = new Random();
            var startDate = new DateTime(2023, 1, 1, 0, 0, 0, DateTimeKind.Utc);
            var endDate = new DateTime(2025, 12, 31, 23, 59, 59, DateTimeKind.Utc);
            
            // 1. Water (Bubbles): Avg 2000ml/day (8 x 250ml)
            // Some days good (3000ml), some days bad (500ml).
            var currentDate = startDate;
            while(currentDate <= endDate)
            {
                // 90% chance to log something
                if (random.NextDouble() > 0.1)
                {
                    int cups = random.Next(2, 12); // 2 to 12 cups
                    for(int i=0; i<cups; i++)
                    {
                        // Spread throughout the day
                        var logTime = currentDate.AddHours(7 + random.Next(0, 14)).AddMinutes(random.Next(0, 60));
                        logs.Add(new LocalHabitLog
                        {
                            Id = GenerateGuid(logTime.ToString("O") + "w" + i).ToString(),
                            UserId = userId,
                            HabitType = "water",
                            Value = 250, // Standard cup
                            Unit = "ml",
                            LoggedAt = logTime,
                            CreatedAt = logTime, // Backdated
                            SyncedAt = null // Dirty
                        });
                    }
                }
                currentDate = currentDate.AddDays(1);
            }

            // 2. Smokes: Starting at 20/day, decreasing to 5/day over 3 years
            currentDate = startDate;
            double startCigs = 20;
            double endCigs = 5;
            double totalDays = (endDate - startDate).TotalDays;
            
            int dayIndex = 0;
            while(currentDate <= endDate)
            {
                // Linear reduction trend + noise
                double progress = dayIndex / totalDays;
                double trend = startCigs - (progress * (startCigs - endCigs));
                int actual = (int)(trend + random.Next(-3, 4)); // +/- 3 cigs noise
                if (actual < 0) actual = 0;

                for(int i=0; i<actual; i++)
                {
                    var logTime = currentDate.AddHours(8 + random.Next(0, 14)).AddMinutes(random.Next(0, 60));
                     logs.Add(new LocalHabitLog
                        {
                            Id = GenerateGuid(logTime.ToString("O") + "s" + i).ToString(),
                            UserId = userId,
                            HabitType = "smokes",
                            Value = 1, 
                            Unit = "count",
                            LoggedAt = logTime,
                            CreatedAt = logTime,
                            SyncedAt = null
                        });
                }
                
                dayIndex++;
                currentDate = currentDate.AddDays(1);
            }

            // Batch Insert
            Console.WriteLine($"[Seeder] Inserting {logs.Count} logs...");
            await _databaseService.Connection.InsertAllAsync(logs);
            
            // Trigger Consolidation
            Console.WriteLine("[Seeder] Triggering Consolidation...");
            await _syncService.SyncAsync(); // This will consolidate old logs
        }
        
        private Guid GenerateGuid(string input)
        {
            using (System.Security.Cryptography.MD5 md5 = System.Security.Cryptography.MD5.Create())
            {
                byte[] hash = md5.ComputeHash(System.Text.Encoding.Default.GetBytes(input));
                return new Guid(hash);
            }
        }
    }
}
