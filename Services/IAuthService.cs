using Daily.Models;

namespace Daily.Services
{
    public interface IAuthService
    {
        Task<bool> SignInWithGoogleAsync();
        Task SignOutAsync();
        string? GetProviderToken();
        string? GetProviderRefreshToken();
        Task<bool> RefreshGoogleTokenAsync();
    }
}
