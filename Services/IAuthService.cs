using Daily.Models;

namespace Daily.Services
{
    public interface IAuthService
    {
        Task<bool> SignInWithGoogleAsync();
        Task SignOutAsync();
    }
}
