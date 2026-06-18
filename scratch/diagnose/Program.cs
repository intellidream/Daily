using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using SQLite;
using Daily.Models;
using Daily.Configuration;

namespace Daily.Diagnose
{
    class Program
    {
        static async Task Main(string[] args)
        {
            Console.WriteLine("=== Daily RSS Diagnostics ===");
            var dbPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DailyApp", "Daily.db3");
            Console.WriteLine($"Local SQLite DB Path: {dbPath}");
            if (!File.Exists(dbPath))
            {
                Console.WriteLine("SQLite Database file not found!");
                return;
            }

            var conn = new SQLiteAsyncConnection(dbPath);
            try
            {
                // Query all local subscriptions
                var localSubs = await conn.Table<LocalRssSubscription>().ToListAsync();
                Console.WriteLine($"\n--- Local SQLite Subscriptions (Count: {localSubs.Count}) ---");
                foreach (var sub in localSubs)
                {
                    Console.WriteLine($"- ID: {sub.Id} | Name: {sub.Name} | User: {sub.UserId} | Deleted: {sub.IsDeleted} | Synced: {sub.SyncedAt} | Url: {sub.Url}");
                }

                // Check distinct users in SQLite
                var userIds = localSubs.Select(s => s.UserId).Distinct().ToList();
                Console.WriteLine($"\nDistinct user IDs in local SQLite: {string.Join(", ", userIds)}");

                // Check Supabase
                Console.WriteLine("\nConnecting to Supabase...");
                var supabaseUrl = Secrets.SupabaseUrl;
                var supabaseKey = Secrets.SupabaseKey;
                Console.WriteLine($"Supabase URL: {supabaseUrl}");

                var options = new Supabase.SupabaseOptions
                {
                    AutoRefreshToken = false,
                    AutoConnectRealtime = false
                };
                var supabase = new Supabase.Client(supabaseUrl, supabaseKey, options);

                // If userIds contains any actual user IDs (excluding local_user), query Supabase for them
                foreach (var userId in userIds)
                {
                    if (userId == "local_user") continue;
                    
                    Console.WriteLine($"\n--- Querying Supabase for User: {userId} ---");
                    try
                    {
                        var remoteResponse = await supabase.From<RssSubscription>()
                                                    .Where(x => x.UserId == Guid.Parse(userId))
                                                    .Get();
                        var remoteSubs = remoteResponse.Models;
                        Console.WriteLine($"Found {remoteSubs.Count} subscriptions in Supabase for user {userId}:");
                        foreach (var sub in remoteSubs)
                        {
                            Console.WriteLine($"- ID: {sub.Id} | Name: {sub.Name} | User: {sub.UserId} | Deleted: {sub.IsDeleted} | Url: {sub.Url}");
                        }
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"Error querying Supabase for user {userId}: {ex.Message}");
                    }
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error during diagnostics: {ex}");
            }
            finally
            {
                await conn.CloseAsync();
            }
        }
    }
}
