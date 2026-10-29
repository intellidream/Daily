using System;
using System.Threading;
using System.Threading.Tasks;

namespace Daily.Services.Auth
{
    /// <summary>
    /// Centralized Supabase JWT lifecycle guardian.
    /// Decodes true JWT 'exp' timestamps directly (bypassing Supabase.Gotrue v6.0.3's SetSession ExpiresIn bug),
    /// refreshes sessions single-flight via SemaphoreSlim, protects persisted refresh tokens across offline/sleep transitions,
    /// and transparently retries PostgREST/RPC calls once on HTTP 401 / PGRST303 ("JWT expired").
    /// </summary>
    public interface ISupabaseSessionGuardian
    {
        /// <summary>
        /// Hydrates or refreshes the persisted Supabase session on application startup,
        /// ensuring CurrentSession.ExpiresIn is a true duration in seconds rather than a Unix epoch timestamp.
        /// </summary>
        Task<bool> HydrateOrRefreshOnStartupAsync(CancellationToken ct = default);

        /// <summary>
        /// Ensures CurrentSession holds an un-expired JWT (with safety margin).
        /// Safe to call concurrently from background timers, window activation, wake-from-sleep, or data services.
        /// </summary>
        Task<bool> EnsureValidSessionAsync(bool forceRefresh = false, CancellationToken ct = default);

        /// <summary>
        /// Executes a Supabase operation after ensuring a valid session, and automatically retries once
        /// with a forced token refresh if PostgREST/GoTrue rejects the request with PGRST303 / JWT expired / 401.
        /// </summary>
        Task<T> ExecuteWithAuthRetryAsync<T>(Func<Task<T>> operation, string operationName = "");

        /// <summary>
        /// Void overload of ExecuteWithAuthRetryAsync.
        /// </summary>
        Task ExecuteWithAuthRetryAsync(Func<Task> operation, string operationName = "");

        /// <summary>
        /// Starts the background PeriodicTimer loop that proactively refreshes the JWT before expiration.
        /// </summary>
        void StartBackgroundGuardian();

        /// <summary>
        /// Stops the background PeriodicTimer loop.
        /// </summary>
        void StopBackgroundGuardian();

        /// <summary>
        /// Decodes the real UTC expiration timestamp ('exp' claim) directly from a JWT string.
        /// </summary>
        DateTime? GetAccessTokenExpiryUtc(string? jwt);

        /// <summary>
        /// Fired when the background guardian detects a wall-clock jump (OS Sleep/Modern Standby/VM resume).
        /// </summary>
        event Action? OnSystemWakeDetected;
    }
}
