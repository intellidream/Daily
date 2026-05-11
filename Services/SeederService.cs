using Daily.Models;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace Daily.Services
{
    public interface ISeederService
    {
        Task SeedHistoryAsync(string userId);
        Task SeedRssFeedsAsync(string userId);
    }

    public class SeederService : ISeederService
    {
        private readonly IDatabaseService _databaseService;
        private readonly ISyncService _syncService;
        private readonly Supabase.Client _supabase;

        public SeederService(IDatabaseService databaseService, ISyncService syncService, Supabase.Client supabase)
        {
            _databaseService = databaseService;
            _syncService = syncService;
            _supabase = supabase;
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
        public async Task SeedRssFeedsAsync(string userId)
        {
            var existingCount = await _databaseService.Connection.Table<LocalRssSubscription>()
                                        .Where(r => r.UserId == userId && r.IsDeleted == false)
                                        .CountAsync();
            
            if (existingCount > 0)
            {
                return; // Already seeded or user has their own feeds
            }

            try 
            {
                // Check if user already has feeds in Supabase (logged into a new device)
                var remoteFeeds = await _supabase.From<RssSubscription>().Select("id").Limit(1).Get();
                if (remoteFeeds.Models.Count > 0)
                {
                    Console.WriteLine("[Seeder] User has remote RSS feeds. Skipping default seed.");
                    return; 
                }
            }
            catch { /* Ignore network errors, fall back to seeding if empty */ }

            Console.WriteLine("[Seeder] Seeding default RSS Feeds...");
            
            var defaultFeeds = new List<LocalRssSubscription>
            {
                // 🇷🇴 Local
                new LocalRssSubscription { Id = Guid.NewGuid().ToString(), UserId = userId, Name = "Republica", Url = "https://republica.ro/rss", Category = "Local", IconUrl = "https://www.google.com/s2/favicons?domain=republica.ro&sz=64", CreatedAt = DateTime.UtcNow },
                new LocalRssSubscription { Id = Guid.NewGuid().ToString(), UserId = userId, Name = "Digi24", Url = "https://www.digi24.ro/rss", Category = "Local", IconUrl = "https://www.google.com/s2/favicons?domain=digi24.ro&sz=64", CreatedAt = DateTime.UtcNow },
                new LocalRssSubscription { Id = Guid.NewGuid().ToString(), UserId = userId, Name = "Ziarul Financiar", Url = "https://www.zf.ro/rss/", Category = "Local", IconUrl = "https://www.google.com/s2/favicons?domain=zf.ro&sz=64", CreatedAt = DateTime.UtcNow },
                new LocalRssSubscription { Id = Guid.NewGuid().ToString(), UserId = userId, Name = "HotNews", Url = "https://www.hotnews.ro/rss", Category = "Local", IconUrl = "https://www.google.com/s2/favicons?domain=hotnews.ro&sz=64", CreatedAt = DateTime.UtcNow },
                new LocalRssSubscription { Id = Guid.NewGuid().ToString(), UserId = userId, Name = "Biziday", Url = "https://www.biziday.ro/feed/", Category = "Local", IconUrl = "https://www.google.com/s2/favicons?domain=biziday.ro&sz=64", CreatedAt = DateTime.UtcNow },
                new LocalRssSubscription { Id = Guid.NewGuid().ToString(), UserId = userId, Name = "Economica.net", Url = "https://www.economica.net/rss", Category = "Local", IconUrl = "https://www.google.com/s2/favicons?domain=economica.net&sz=64", CreatedAt = DateTime.UtcNow },

                // 📈 Markets
                new LocalRssSubscription { Id = Guid.NewGuid().ToString(), UserId = userId, Name = "CNBC", Url = "https://www.cnbc.com/id/100003114/device/rss/rss.html", Category = "Markets", IconUrl = "https://www.google.com/s2/favicons?domain=cnbc.com&sz=64", CreatedAt = DateTime.UtcNow },
                new LocalRssSubscription { Id = Guid.NewGuid().ToString(), UserId = userId, Name = "The Economist", Url = "https://www.economist.com/finance-and-economics/rss.xml", Category = "Markets", IconUrl = "https://www.google.com/s2/favicons?domain=economist.com&sz=64", CreatedAt = DateTime.UtcNow },

                // 🌍 World
                new LocalRssSubscription { Id = Guid.NewGuid().ToString(), UserId = userId, Name = "BBC News", Url = "https://feeds.bbci.co.uk/news/rss.xml", Category = "World", IconUrl = "https://www.google.com/s2/favicons?domain=bbc.com&sz=64", CreatedAt = DateTime.UtcNow },
                new LocalRssSubscription { Id = Guid.NewGuid().ToString(), UserId = userId, Name = "NPR", Url = "https://feeds.npr.org/1001/rss.xml", Category = "World", IconUrl = "https://www.google.com/s2/favicons?domain=npr.org&sz=64", CreatedAt = DateTime.UtcNow },
                new LocalRssSubscription { Id = Guid.NewGuid().ToString(), UserId = userId, Name = "Politico Europe", Url = "https://www.politico.eu/feed/", Category = "World", IconUrl = "https://www.google.com/s2/favicons?domain=politico.eu&sz=64", CreatedAt = DateTime.UtcNow },
                new LocalRssSubscription { Id = Guid.NewGuid().ToString(), UserId = userId, Name = "Deutsche Welle", Url = "https://rss.dw.com/rdf/rss-en-all", Category = "World", IconUrl = "https://www.google.com/s2/favicons?domain=dw.com&sz=64", CreatedAt = DateTime.UtcNow },
                new LocalRssSubscription { Id = Guid.NewGuid().ToString(), UserId = userId, Name = "Google News", Url = "https://news.google.com/rss?hl=en-US&gl=US&ceid=US:en", Category = "World", IconUrl = "https://www.google.com/s2/favicons?domain=news.google.com&sz=64", CreatedAt = DateTime.UtcNow },

                // 💡 Tech
                new LocalRssSubscription { Id = Guid.NewGuid().ToString(), UserId = userId, Name = "TechCrunch", Url = "https://techcrunch.com/feed/", Category = "Tech", IconUrl = "https://www.google.com/s2/favicons?domain=techcrunch.com&sz=64", CreatedAt = DateTime.UtcNow },
                new LocalRssSubscription { Id = Guid.NewGuid().ToString(), UserId = userId, Name = "The Verge", Url = "https://www.theverge.com/rss/index.xml", Category = "Tech", IconUrl = "https://www.google.com/s2/favicons?domain=theverge.com&sz=64", CreatedAt = DateTime.UtcNow },
                new LocalRssSubscription { Id = Guid.NewGuid().ToString(), UserId = userId, Name = "Ars Technica", Url = "https://feeds.arstechnica.com/arstechnica/index", Category = "Tech", IconUrl = "https://www.google.com/s2/favicons?domain=arstechnica.com&sz=64", CreatedAt = DateTime.UtcNow },
                new LocalRssSubscription { Id = Guid.NewGuid().ToString(), UserId = userId, Name = "Zona IT", Url = "https://zonait.ro/wp-json/wp/v2/posts?per_page=20&_embed", Category = "Tech", IconUrl = "https://www.google.com/s2/favicons?domain=zonait.ro&sz=64", CreatedAt = DateTime.UtcNow },
                new LocalRssSubscription { Id = Guid.NewGuid().ToString(), UserId = userId, Name = "Windows Central", Url = "https://www.windowscentral.com/feeds.xml", Category = "Tech", IconUrl = "https://www.google.com/s2/favicons?domain=windowscentral.com&sz=64", CreatedAt = DateTime.UtcNow }
            };

            await _databaseService.Connection.InsertAllAsync(defaultFeeds);
            await _syncService.SyncAsync(); // Push to Supabase immediately
            Console.WriteLine("[Seeder] Successfully seeded default RSS Feeds.");
        }
    }
}
