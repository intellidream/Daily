using System;

namespace Daily.Services
{
    public class StubWatchConnectivityService : IWatchConnectivityService
    {
        public void SendSupabaseSession(string accessToken, string refreshToken)
        {
            // Do nothing on non-iOS platforms
            Console.WriteLine("[StubWatchConnectivityService] SendSupabaseSession: WatchConnectivity is not supported on this platform.");
        }
    }
}
