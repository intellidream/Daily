namespace Daily.Services
{
    public interface ISyncService
    {
        Task SyncAsync();
        Task PushAsync();
        Task<int> PullAsync();
        string? LastSyncError { get; }
        string LastSyncMessage { get; }
    }
}
