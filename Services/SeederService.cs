using Daily.Models;
using System;
using System.Collections.Generic;
using System.Linq;
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
            await _syncService.SyncAsync(SyncScope.Habits); // This will consolidate old logs
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
            if (string.IsNullOrEmpty(userId) || userId == "local_user")
            {
                var localCount = await _databaseService.Connection.Table<LocalRssSubscription>()
                                            .Where(r => r.UserId == userId && r.IsDeleted == false)
                                            .CountAsync();
                
                if (localCount == 0)
                {
                    Console.WriteLine("[Seeder] Guest user. Seeding default RSS feeds locally...");
                    var defaultFeeds = GetDefaultFeeds(userId);
                    await _databaseService.Connection.InsertAllAsync(defaultFeeds);
                }
                return;
            }

            try 
            {
                var auth = _supabase.Auth;
                if (auth?.CurrentSession != null && auth.CurrentSession.Expired())
                {
                    try { await auth.RefreshSession(); } catch { }
                }

                // Check if user already has feeds in Supabase
                var remoteResponse = await _supabase.From<RssSubscription>()
                                            .Where(x => x.UserId == Guid.Parse(userId))
                                            .Get();
                var remoteFeeds = remoteResponse.Models;

                if (remoteFeeds.Count == 0)
                {
                    Console.WriteLine("[Seeder] No RSS subscriptions in Supabase. Seeding defaults to Supabase and local...");
                    var defaultFeedsLocal = GetDefaultFeeds(userId);
                    
                    // Map to domain and upsert to Supabase
                    var remoteToInsert = defaultFeedsLocal.Select(f => f.ToDomain()).ToList();
                    await _supabase.From<RssSubscription>().Upsert(remoteToInsert);

                    // Mark as synced and write to local SQLite
                    foreach (var localFeed in defaultFeedsLocal)
                    {
                        localFeed.SyncedAt = DateTime.UtcNow;
                    }
                    await _databaseService.Connection.InsertAllAsync(defaultFeedsLocal);
                    Console.WriteLine("[Seeder] Successfully seeded defaults to Supabase and local SQLite.");
                }
                else
                {
                    Console.WriteLine($"[Seeder] Found {remoteFeeds.Count} RSS subscriptions in Supabase. Merging missing ones locally...");
                    var localFeeds = await _databaseService.Connection.Table<LocalRssSubscription>()
                                            .Where(x => x.UserId == userId)
                                            .ToListAsync();

                    var defaultFeeds = GetDefaultFeeds(userId);
                    var defaultUrls = defaultFeeds.Select(f => NormalizeUrl(f.Url)).ToHashSet();
                    var localUrls = localFeeds.Select(l => NormalizeUrl(l.Url)).ToHashSet();
                    var localFeedsToInsert = new List<LocalRssSubscription>();

                    foreach (var remoteFeed in remoteFeeds)
                    {
                        var remoteUrlNorm = NormalizeUrl(remoteFeed.Url);
                        
                        // 1. If it's a default feed URL, skip it (as we already have the local default version loaded)
                        if (defaultUrls.Contains(remoteUrlNorm))
                        {
                            continue;
                        }

                        // 2. If the URL is already present locally, skip it to avoid duplicates
                        if (localUrls.Contains(remoteUrlNorm))
                        {
                            continue;
                        }

                        // 3. Otherwise, it is a custom extra feed from Supabase. Bring it local!
                        var localModel = remoteFeed.ToLocal();
                        localModel.SyncedAt = DateTime.UtcNow; // Already on Supabase
                        localFeedsToInsert.Add(localModel);
                        Console.WriteLine($"[Seeder] Bringing extra feed from Supabase to local: {remoteFeed.Name} (URL: {remoteFeed.Url})");
                    }

                    if (localFeedsToInsert.Any())
                    {
                        await _databaseService.Connection.InsertAllAsync(localFeedsToInsert);
                        Console.WriteLine($"[Seeder] Successfully inserted {localFeedsToInsert.Count} extra feeds locally.");
                    }
                    else
                    {
                        Console.WriteLine("[Seeder] Local SQLite is already fully synchronized with Supabase subscriptions.");
                    }
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Seeder] SeedRssFeedsAsync Error: {ex.Message}");
                // Fallback: If network/Supabase fails, but we don't have local feeds, we seed them locally
                var localCount = await _databaseService.Connection.Table<LocalRssSubscription>()
                                            .Where(r => r.UserId == userId && r.IsDeleted == false)
                                            .CountAsync();
                if (localCount == 0)
                {
                    Console.WriteLine("[Seeder] Supabase offline and local empty. Seeding defaults locally as fallback...");
                    var defaultFeeds = GetDefaultFeeds(userId);
                    await _databaseService.Connection.InsertAllAsync(defaultFeeds);
                }
            }
        }

        private static string NormalizeUrl(string url)
        {
            if (string.IsNullOrWhiteSpace(url)) return string.Empty;
            var normalized = url.Trim().ToLowerInvariant();
            if (normalized.EndsWith("/"))
            {
                normalized = normalized.TrimEnd('/');
            }
            return normalized;
        }

        private List<LocalRssSubscription> GetDefaultFeeds(string userId)
        {
            var defaultFeedsData = new List<(string Name, string Url, string Category)>
            {
                // 🇷🇴 Local
                ("Republica", "https://republica.ro/rss", "Local"),
                ("Digi24", "https://www.digi24.ro/rss", "Local"),
                ("Ziarul Financiar", "https://www.zf.ro/rss/", "Local"),
                ("HotNews", "https://www.hotnews.ro/rss", "Local"),
                ("Biziday", "https://www.biziday.ro/feed/", "Local"),
                ("Economica.net", "https://www.economica.net/rss", "Local"),

                // 📈 Markets
                ("CNBC", "https://www.cnbc.com/id/100003114/device/rss/rss.html", "Markets"),
                ("The Economist", "https://www.economist.com/finance-and-economics/rss.xml", "Markets"),

                // 🌍 World
                ("BBC News", "https://feeds.bbci.co.uk/news/rss.xml", "World"),
                ("NPR", "https://feeds.npr.org/1001/rss.xml", "World"),
                ("Politico Europe", "https://www.politico.eu/feed/", "World"),
                ("Deutsche Welle", "https://rss.dw.com/rdf/rss-en-all", "World"),
                ("Google News", "https://news.google.com/rss?hl=en-US&gl=US&ceid=US:en", "World"),

                // 💡 Tech
                ("TechCrunch", "https://techcrunch.com/feed/", "Tech"),
                ("The Verge", "https://www.theverge.com/rss/index.xml", "Tech"),
                ("Ars Technica", "https://feeds.arstechnica.com/arstechnica/index", "Tech"),
                ("Zona IT", "https://zonait.ro/wp-json/wp/v2/posts?per_page=20&_embed", "Tech"),
                ("Windows Central", "https://www.windowscentral.com/feeds.xml", "Tech")
            };

            var list = new List<LocalRssSubscription>();
            for (int i = 0; i < defaultFeedsData.Count; i++)
            {
                var f = defaultFeedsData[i];
                var id = GenerateGuid(f.Url).ToString(); // Deterministic URL-based ID
                list.Add(new LocalRssSubscription
                {
                    Id = id,
                    UserId = userId,
                    Name = f.Name,
                    Url = f.Url,
                    Category = f.Category,
                    IconUrl = $"https://www.google.com/s2/favicons?domain={new Uri(f.Url).Host}&sz=64",
                    CreatedAt = DateTime.UtcNow,
                    DisplayOrder = i
                });
            }
            return list;
        }
    }
}

