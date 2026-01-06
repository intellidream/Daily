using SQLite;

namespace Daily.Services
{
    public interface IDatabaseService
    {
        SQLiteAsyncConnection Connection { get; }
        Task InitializeAsync();
    }
}
