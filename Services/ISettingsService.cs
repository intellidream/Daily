using Daily.Models;

namespace Daily.Services
{
    public interface ISettingsService
    {
        UserPreferences Settings { get; }
        bool IsAuthenticated { get; }
        string? CurrentUserEmail { get; }
        string? CurrentUserAvatarUrl { get; }
        string? CurrentUserId { get; }

        event Action OnSettingsChanged;

        Task InitializeAsync();
        Task SaveSettingsAsync();
    }
}
