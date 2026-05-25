using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using SQLite;
using Daily.Models;
using Daily.Services;

namespace Daily_WinUI.Services
{
    public interface IBehaviorService
    {
        Task TrackEventAsync(string feature, string actionType, string metadataJson);
        Task SyncEventsAsync();
        Task<string> GetWeeklyBehaviorSummaryAsync();
        Task ClearHistoryAsync();
    }

    public sealed class BehaviorService : IBehaviorService
    {
        private readonly IDatabaseService _db;
        private readonly Supabase.Client _supabase;

        public BehaviorService(IDatabaseService db, Supabase.Client supabase)
        {
            _db = db;
            _supabase = supabase;
        }

        public async Task TrackEventAsync(string feature, string actionType, string metadataJson)
        {
            try
            {
                var settings = SettingsService.Load();
                if (!settings.EnableSmartBehavior) return;

                await _db.InitializeAsync();

                string userId = _supabase.Auth?.CurrentUser?.Id ?? "local_user";

                var ev = new SmartBehaviorEvent
                {
                    Id = Guid.NewGuid().ToString(),
                    UserId = userId,
                    Feature = feature,
                    ActionType = actionType,
                    Metadata = metadataJson ?? "{}",
                    Timestamp = DateTime.UtcNow,
                    IsSynced = false
                };

                await _db.Connection.InsertAsync(ev);
                System.Diagnostics.Debug.WriteLine($"[BehaviorService] Tracked local event: {feature} - {actionType}");

                // Flush queue in background
                if (settings.SyncSmartBehaviorToCloud)
                {
                    _ = Task.Run(async () =>
                    {
                        try
                        {
                            await SyncEventsAsync();
                        }
                        catch { }
                    });
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[BehaviorService] TrackEventAsync Error: {ex.Message}");
            }
        }

        public async Task SyncEventsAsync()
        {
            try
            {
                var settings = SettingsService.Load();
                if (!settings.EnableSmartBehavior || !settings.SyncSmartBehaviorToCloud) return;

                string userId = _supabase.Auth?.CurrentUser?.Id;
                if (string.IsNullOrEmpty(userId)) return;

                await _db.InitializeAsync();

                // Get unsynced local events
                var unsynced = await _db.Connection.Table<SmartBehaviorEvent>()
                    .Where(e => e.UserId == userId && !e.IsSynced)
                    .ToListAsync();

                if (unsynced == null || unsynced.Count == 0) return;

                // Map to remote Postgrest models
                var remoteList = unsynced.Select(e => new SmartBehaviorEventRemote
                {
                    Id = e.Id,
                    UserId = e.UserId,
                    Feature = e.Feature,
                    ActionType = e.ActionType,
                    Metadata = e.Metadata,
                    Timestamp = e.Timestamp
                }).ToList();

                // Batch Upsert to Supabase
                await _supabase.From<SmartBehaviorEventRemote>().Upsert(remoteList);

                // Mark as synced locally
                foreach (var ev in unsynced)
                {
                    ev.IsSynced = true;
                }
                await _db.Connection.UpdateAllAsync(unsynced);
                System.Diagnostics.Debug.WriteLine($"[BehaviorService] Synced {unsynced.Count} behavior events to Supabase.");
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[BehaviorService] SyncEventsAsync Error: {ex.Message}");
            }
        }

        public async Task<string> GetWeeklyBehaviorSummaryAsync()
        {
            try
            {
                string userId = _supabase.Auth?.CurrentUser?.Id ?? "local_user";
                var cutoff = DateTime.UtcNow.AddDays(-7);

                await _db.InitializeAsync();

                var events = await _db.Connection.Table<SmartBehaviorEvent>()
                    .Where(e => e.UserId == userId && e.Timestamp > cutoff)
                    .OrderBy(e => e.Timestamp)
                    .ToListAsync();

                if (events == null || events.Count == 0)
                {
                    return "No behavior events logged this week.";
                }

                var sb = new StringBuilder();
                sb.AppendLine("User Behavior Insights (Last 7 Days):");

                var grouped = events.GroupBy(e => e.Feature);
                foreach (var group in grouped)
                {
                    sb.AppendLine($"- Feature: {group.Key}");
                    var actions = group.GroupBy(e => e.ActionType);
                    foreach (var act in actions)
                    {
                        sb.AppendLine($"  * {act.Key}: {act.Count()} times");
                    }
                }

                return sb.ToString();
            }
            catch (Exception ex)
            {
                return $"Error generating behavior summary: {ex.Message}";
            }
        }

        public async Task ClearHistoryAsync()
        {
            try
            {
                string userId = _supabase.Auth?.CurrentUser?.Id ?? "local_user";
                await _db.InitializeAsync();

                await _db.Connection.Table<SmartBehaviorEvent>()
                    .DeleteAsync(e => e.UserId == userId);
                
                System.Diagnostics.Debug.WriteLine("[BehaviorService] Cleared user behavior history locally.");
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[BehaviorService] ClearHistoryAsync Error: {ex.Message}");
            }
        }
    }
}
