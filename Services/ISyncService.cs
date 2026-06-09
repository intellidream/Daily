using System;
using System.Threading.Tasks;

namespace Daily.Services
{
    [Flags]
    public enum SyncScope
    {
        None = 0,
        Habits = 1 << 0,
        Finances = 1 << 1,
        Preferences = 1 << 2,
        SavedArticles = 1 << 3,
        RssSubscriptions = 1 << 4,
        CalendarAccounts = 1 << 5,
        All = Habits | Finances | Preferences | SavedArticles | RssSubscriptions | CalendarAccounts
    }

    [Flags]
    public enum SyncAction
    {
        None = 0,
        Push = 1 << 0,
        Pull = 1 << 1,
        Sync = Push | Pull
    }

    public interface ISyncService
    {
        Task SyncAsync(SyncScope scope = SyncScope.All);
        Task PushAsync(SyncScope scope = SyncScope.All);
        Task<int> PullAsync(SyncScope scope = SyncScope.All);
        void StartBackgroundSync();
        string? LastSyncError { get; }
        string LastSyncMessage { get; }
        string DebugLog { get; }
        event Action? OnDebugLogUpdated;
        event Action? OnPreferencesPulled;
        void Log(string message);
    }
}

