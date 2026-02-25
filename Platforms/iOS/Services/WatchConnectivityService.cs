using System;
using Foundation;
using WatchConnectivity;
using Daily.Services;

namespace Daily.Platforms.iOS.Services
{
    public class WatchConnectivityService : WCSessionDelegate, IWatchConnectivityService
    {
        private string? _pendingAccessToken;
        private string? _pendingRefreshToken;

        public WatchConnectivityService()
        {
            if (WCSession.IsSupported)
            {
                var session = WCSession.DefaultSession;
                session.Delegate = this;
                session.ActivateSession();
            }
        }

        public void SendSupabaseSession(string accessToken, string refreshToken)
        {
            if (WCSession.IsSupported)
            {
                if (WCSession.DefaultSession.ActivationState != WCSessionActivationState.Activated)
                {
                    Console.WriteLine("[WatchConnectivityService] Session not yet activated. Queuing token for later transfer.");
                    _pendingAccessToken = accessToken;
                    _pendingRefreshToken = refreshToken;
                    return;
                }

                try
                {
                    var keys = new[] { new NSString("supabase_access_token"), new NSString("supabase_refresh_token") };
                    var values = new[] { new NSString(accessToken ?? ""), new NSString(refreshToken ?? "") };
                    var userInfo = new NSDictionary<NSString, NSObject>(keys, values);
                    
                    // Queue for background delivery or foreground delivery
                    WCSession.DefaultSession.TransferUserInfo(userInfo);
                    
                    // Update latest state (often more reliable for app launches)
                    NSError err;
                    WCSession.DefaultSession.UpdateApplicationContext(userInfo, out err);
                    
                    if (err != null)
                    {
                        Console.WriteLine($"[WatchConnectivityService] UpdateApplicationContext returned error: {err.LocalizedDescription}");
                    }
                    
                    Console.WriteLine("[WatchConnectivityService] Successfully transferred session to Watch.");

                    // Clear pending since sent
                    _pendingAccessToken = null;
                    _pendingRefreshToken = null;
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[WatchConnectivityService] Error transferring session: {ex.Message}");
                }
            }
            else
            {
                Console.WriteLine($"[WatchConnectivityService] Skipped transfer. IsSupported: {WCSession.IsSupported}");
            }
        }

        public override void ActivationDidComplete(WCSession session, WCSessionActivationState activationState, NSError? error)
        {
            Console.WriteLine($"[WatchConnectivityService] Activation complete. State: {activationState}");
            if (activationState == WCSessionActivationState.Activated && !string.IsNullOrEmpty(_pendingAccessToken))
            {
                Console.WriteLine("[WatchConnectivityService] Processing pending token transfer...");
                SendSupabaseSession(_pendingAccessToken, _pendingRefreshToken ?? "");
            }
        }
    }
}
