namespace Daily.Services
{
    public interface IWatchConnectivityService
    {
        void SendSupabaseSession(string accessToken, string refreshToken);
    }
}
