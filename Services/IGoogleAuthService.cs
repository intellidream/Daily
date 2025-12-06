using System.Threading.Tasks;

namespace Daily.Services
{
    public interface IGoogleAuthService
    {
        Task<(string? AccessToken, string? Error)> LoginAsync();
        Task LogoutAsync();
        Task<string?> GetAccessTokenAsync();
        bool IsAuthenticated { get; }
    }
}
