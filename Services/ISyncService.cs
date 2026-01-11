namespace Daily.Services
{
    public interface ISyncService
    {
        Task SyncAsync();
        Task PushAsync();
        Task<int> PullAsync();
        void StartBackgroundSync(); // New
        string? LastSyncError { get; }
        string LastSyncMessage { get; }
        string DebugLog { get; }
        event Action? OnDebugLogUpdated;
        void Log(string message);
    }
}
