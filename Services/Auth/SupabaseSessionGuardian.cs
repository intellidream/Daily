using System;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Newtonsoft.Json.Linq;
using Supabase.Gotrue;
using Supabase.Gotrue.Exceptions;
using Supabase.Gotrue.Interfaces;

namespace Daily.Services.Auth
{
    public class SupabaseSessionGuardian : ISupabaseSessionGuardian
    {
        private static readonly TimeSpan ProactiveRefreshMargin = TimeSpan.FromMinutes(10);
        private static readonly TimeSpan GuardianTickInterval = TimeSpan.FromMinutes(1);
        private static readonly TimeSpan WakeJumpThreshold = TimeSpan.FromSeconds(135);
        private const long MaxReasonableExpiresInSeconds = 86400 * 7; // 7 days; anything larger is a Unix timestamp bug

        public event Action? OnSystemWakeDetected;

        private readonly Supabase.Client _supabase;
        private readonly SemaphoreSlim _refreshLock = new(1, 1);
        private readonly SemaphoreSlim _realtimeLock = new(1, 1);
        private readonly IGotrueClient<User, Session>.AuthEventHandler _authListener;

        private string? _lastKnownAccessToken;
        private string? _lastKnownRefreshToken;
        private DateTime _lastRefreshCompletedUtc = DateTime.MinValue;
        private volatile bool _explicitlySignedOut;

        private CancellationTokenSource? _guardianCts;
        private Task? _guardianLoopTask;

        public SupabaseSessionGuardian(Supabase.Client supabase)
        {
            _supabase = supabase;
            ConfigureRealtimeHandshakeHeaders();

            var initial = _supabase.Auth.CurrentSession;
            if (initial != null)
            {
                if (!string.IsNullOrEmpty(initial.AccessToken))
                    _lastKnownAccessToken = initial.AccessToken;
                if (!string.IsNullOrEmpty(initial.RefreshToken))
                    _lastKnownRefreshToken = initial.RefreshToken;
            }

            _authListener = OnAuthStateChanged;
            _supabase.Auth.AddStateChangedListener(_authListener);
        }

        private void OnAuthStateChanged(IGotrueClient<User, Session> sender, Constants.AuthState state)
        {
            if (state == Constants.AuthState.SignedIn || state == Constants.AuthState.TokenRefreshed)
            {
                var session = sender.CurrentSession;
                if (session != null && !string.IsNullOrEmpty(session.AccessToken))
                {
                    _explicitlySignedOut = false;
                    _lastKnownAccessToken = session.AccessToken;
                    if (!string.IsNullOrEmpty(session.RefreshToken))
                        _lastKnownRefreshToken = session.RefreshToken;

                    var expUtc = GetAccessTokenExpiryUtc(session.AccessToken);
                    if (expUtc.HasValue)
                    {
                        NormalizeSessionExpiresIn(session, expUtc.Value);
                    }

                    PersistSessionIfSupported(session);

                    try
                    {
                        ConfigureRealtimeHandshakeHeaders();
                        _supabase.Realtime.SetAuth(session.AccessToken);
                    }
                    catch (Exception ex)
                    {
                        LogGuardian($"Realtime.SetAuth warning on {state}: {ex.Message}");
                    }
                }
            }
            else if (state == Constants.AuthState.SignedOut)
            {
#if WINUI_NATIVE
                if (Daily_WinUI.Services.WinUISessionPersistence.AllowDestroySession)
                {
                    _explicitlySignedOut = true;
                    _lastKnownAccessToken = null;
                    _lastKnownRefreshToken = null;
                }
#else
                _explicitlySignedOut = true;
                _lastKnownAccessToken = null;
                _lastKnownRefreshToken = null;
#endif
            }
        }

        public DateTime? GetAccessTokenExpiryUtc(string? jwt)
        {
            if (string.IsNullOrWhiteSpace(jwt))
                return null;

            try
            {
                var parts = jwt.Split('.');
                if (parts.Length < 2)
                    return null;

                var payloadBase64 = parts[1].Replace('-', '+').Replace('_', '/');
                switch (payloadBase64.Length % 4)
                {
                    case 2: payloadBase64 += "=="; break;
                    case 3: payloadBase64 += "="; break;
                }

                var jsonBytes = Convert.FromBase64String(payloadBase64);
                var json = Encoding.UTF8.GetString(jsonBytes);
                var payload = JObject.Parse(json);
                var expToken = payload["exp"];
                if (expToken != null && long.TryParse(expToken.ToString(), out var expSeconds) && expSeconds > 0)
                {
                    return DateTimeOffset.FromUnixTimeSeconds(expSeconds).UtcDateTime;
                }
            }
            catch (Exception ex)
            {
                LogGuardian($"Failed to decode JWT exp claim: {ex.Message}");
            }

            return null;
        }

        public async Task<bool> HydrateOrRefreshOnStartupAsync(CancellationToken ct = default)
        {
            await _refreshLock.WaitAsync(ct);
            try
            {
                _explicitlySignedOut = false;

                var session = _supabase.Auth.CurrentSession ?? LoadPersistedSessionIfSupported();
                if (session == null || string.IsNullOrEmpty(session.AccessToken) || string.IsNullOrEmpty(session.RefreshToken))
                {
                    LogGuardian("HydrateOrRefreshOnStartup: no persisted session tokens found.");
                    return false;
                }

                _lastKnownAccessToken = session.AccessToken;
                _lastKnownRefreshToken = session.RefreshToken;

                var expUtc = GetAccessTokenExpiryUtc(session.AccessToken);
                var nowUtc = DateTime.UtcNow;

                if (!expUtc.HasValue || expUtc.Value <= nowUtc.Add(ProactiveRefreshMargin))
                {
                    LogGuardian($"HydrateOrRefreshOnStartup: persisted JWT expired or near expiry (expUtc={expUtc:O}, nowUtc={nowUtc:O}). Refreshing...");
                    return await RefreshUsingTokensInternalAsync(
                        session.AccessToken,
                        session.RefreshToken,
                        isInitialHydration: _supabase.Auth.CurrentSession == null);
                }

                // Token is still fresh: ensure CurrentSession is populated and ExpiresIn is a real duration (not Unix epoch!)
                if (_supabase.Auth.CurrentSession == null)
                {
                    try
                    {
                        await _supabase.Auth.SetSession(session.AccessToken, session.RefreshToken, forceAccessTokenRefresh: false);
                    }
                    catch (Exception ex)
                    {
                        LogGuardian($"HydrateOrRefreshOnStartup: SetSession(false) warning ({ex.Message}); attempting LoadSession fallback.");
                        _supabase.Auth.LoadSession();
                    }
                }

                var active = _supabase.Auth.CurrentSession;
                if (active != null && !string.IsNullOrEmpty(active.AccessToken))
                {
                    NormalizeSessionExpiresIn(active, expUtc.Value);
                    PersistSessionIfSupported(active);
                    try { _supabase.Realtime.SetAuth(active.AccessToken); } catch { }

                    var remainingMin = (expUtc.Value - nowUtc).TotalMinutes;
                    LogGuardian($"HydrateOrRefreshOnStartup: session active for user={active.User?.Id ?? "unknown"}, valid until {expUtc.Value:O} ({remainingMin:F1}m remaining, ExpiresIn={active.ExpiresIn}s).");
                    return true;
                }

                return false;
            }
            finally
            {
                _refreshLock.Release();
            }
        }

        public async Task<bool> EnsureValidSessionAsync(bool forceRefresh = false, CancellationToken ct = default)
        {
            if (_explicitlySignedOut)
                return false;

            var requestStartUtc = DateTime.UtcNow;

            // Fast lock-free check when token is healthy and caller did not request a forced refresh
            if (!forceRefresh)
            {
                var current = _supabase.Auth.CurrentSession;
                if (current != null && !string.IsNullOrEmpty(current.AccessToken))
                {
                    var expUtc = GetAccessTokenExpiryUtc(current.AccessToken);
                    if (expUtc.HasValue && expUtc.Value > requestStartUtc.Add(ProactiveRefreshMargin))
                    {
                        NormalizeSessionExpiresIn(current, expUtc.Value);
                        return true;
                    }
                }
            }

            await _refreshLock.WaitAsync(ct);
            try
            {
                if (_explicitlySignedOut)
                    return false;

                var nowUtc = DateTime.UtcNow;
                var current = _supabase.Auth.CurrentSession;

                if (current != null && !string.IsNullOrEmpty(current.AccessToken))
                {
                    var expUtc = GetAccessTokenExpiryUtc(current.AccessToken);
                    if (expUtc.HasValue && expUtc.Value > nowUtc.Add(ProactiveRefreshMargin))
                    {
                        // Even if forceRefresh was requested, if another concurrent caller JUST refreshed
                        // the session while we waited on _refreshLock, reuse the brand-new session to avoid
                        // double-spending a rotated refresh token!
                        if (!forceRefresh || _lastRefreshCompletedUtc >= requestStartUtc)
                        {
                            NormalizeSessionExpiresIn(current, expUtc.Value);
                            return true;
                        }
                    }
                }

                // Resolve best available token pair (CurrentSession -> in-memory backup -> disk persistence)
                string? accessToken = current?.AccessToken ?? _lastKnownAccessToken;
                string? refreshToken = current?.RefreshToken ?? _lastKnownRefreshToken;

                if (string.IsNullOrEmpty(accessToken) || string.IsNullOrEmpty(refreshToken))
                {
                    var persisted = LoadPersistedSessionIfSupported();
                    if (persisted != null)
                    {
                        if (string.IsNullOrEmpty(accessToken)) accessToken = persisted.AccessToken;
                        if (string.IsNullOrEmpty(refreshToken)) refreshToken = persisted.RefreshToken;
                    }
                }

                if (string.IsNullOrEmpty(accessToken) || string.IsNullOrEmpty(refreshToken))
                {
                    LogGuardian("EnsureValidSessionAsync: no session tokens available to refresh.");
                    return false;
                }

                var currentExp = GetAccessTokenExpiryUtc(accessToken);
                LogGuardian($"EnsureValidSessionAsync: refreshing JWT (force={forceRefresh}, prevExpUtc={currentExp:O}, nowUtc={nowUtc:O})...");

                return await RefreshUsingTokensInternalAsync(
                    accessToken,
                    refreshToken,
                    isInitialHydration: _supabase.Auth.CurrentSession == null);
            }
            finally
            {
                _refreshLock.Release();
            }
        }

        public async Task<T> ExecuteWithAuthRetryAsync<T>(Func<Task<T>> operation, string operationName = "")
        {
            await EnsureValidSessionAsync(forceRefresh: false);

            try
            {
                return await operation();
            }
            catch (Exception ex) when (IsJwtAuthError(ex))
            {
                LogGuardian($"ExecuteWithAuthRetryAsync('{operationName}'): caught expired/401 JWT ({SummarizeException(ex)}). Forcing refresh and retrying once...");
                var refreshed = await EnsureValidSessionAsync(forceRefresh: true);
                if (!refreshed)
                {
                    LogGuardian($"ExecuteWithAuthRetryAsync('{operationName}'): forced token refresh did not succeed; rethrowing original error.");
                    throw;
                }

                return await operation();
            }
        }

        public async Task ExecuteWithAuthRetryAsync(Func<Task> operation, string operationName = "")
        {
            await ExecuteWithAuthRetryAsync<bool>(async () =>
            {
                await operation();
                return true;
            }, operationName);
        }

        public void StartBackgroundGuardian()
        {
            if (_guardianLoopTask != null && !_guardianLoopTask.IsCompleted)
                return;

            _guardianCts?.Cancel();
            _guardianCts = new CancellationTokenSource();
            var ct = _guardianCts.Token;

            _guardianLoopTask = Task.Run(async () =>
            {
                LogGuardian($"Background JWT guardian started (interval={GuardianTickInterval.TotalSeconds:F0}s, margin={ProactiveRefreshMargin.TotalMinutes:F0}m).");
                using var timer = new PeriodicTimer(GuardianTickInterval);
                var lastTickUtc = DateTime.UtcNow;
                try
                {
                    while (await timer.WaitForNextTickAsync(ct))
                    {
                        var nowUtc = DateTime.UtcNow;
                        var wallElapsed = nowUtc - lastTickUtc;
                        lastTickUtc = nowUtc;

                        try
                        {
                            bool wokeFromSuspend = wallElapsed >= WakeJumpThreshold;
                            if (wokeFromSuspend)
                            {
                                LogGuardian($"Detected wall-clock jump of {wallElapsed.TotalSeconds:F0}s (Sleep/Standby/VM resume). Validating session and notifying sync...");
                                // Brief settle delay for NIC/DNS after wake
                                await Task.Delay(1500, ct);
                            }

                            var ok = await EnsureValidSessionAsync(forceRefresh: false, ct: ct);
                            if (wokeFromSuspend && ok)
                            {
                                OnSystemWakeDetected?.Invoke();
                            }
                        }
                        catch (OperationCanceledException) when (ct.IsCancellationRequested)
                        {
                            break;
                        }
                        catch (Exception ex)
                        {
                            LogGuardian($"Background guardian tick warning: {ex.Message}");
                        }
                    }
                }
                catch (OperationCanceledException)
                {
                    // Normal shutdown
                }
                LogGuardian("Background JWT guardian stopped.");
            }, ct);
        }

        public void StopBackgroundGuardian()
        {
            try
            {
                _guardianCts?.Cancel();
            }
            catch { }
        }

        private async Task<bool> RefreshUsingTokensInternalAsync(string accessToken, string refreshToken, bool isInitialHydration)
        {
            try
            {
                _supabase.Auth.Online = true;

                if (_supabase.Auth is Supabase.Gotrue.Client gotrueClient && !isInitialHydration && _supabase.Auth.CurrentSession != null)
                {
                    // Refreshes directly via GoTrue API and emits AuthState.TokenRefreshed WITHOUT calling DestroySession()!
                    await gotrueClient.RefreshToken(accessToken, refreshToken);
                }
                else
                {
                    // Initial hydration when CurrentSession is null: refreshes via GoTrue API and emits AuthState.SignedIn
                    await _supabase.Auth.SetSession(accessToken, refreshToken, forceAccessTokenRefresh: true);
                }

                var refreshed = _supabase.Auth.CurrentSession;
                if (refreshed == null || string.IsNullOrEmpty(refreshed.AccessToken))
                {
                    LogGuardian("RefreshUsingTokensInternalAsync: GoTrue returned empty session.");
                    return false;
                }

                _lastRefreshCompletedUtc = DateTime.UtcNow;
                _lastKnownAccessToken = refreshed.AccessToken;
                if (!string.IsNullOrEmpty(refreshed.RefreshToken))
                    _lastKnownRefreshToken = refreshed.RefreshToken;

                var newExpUtc = GetAccessTokenExpiryUtc(refreshed.AccessToken);
                if (newExpUtc.HasValue)
                {
                    NormalizeSessionExpiresIn(refreshed, newExpUtc.Value);
                }

                PersistSessionIfSupported(refreshed);

                try
                {
                    _supabase.Realtime.SetAuth(refreshed.AccessToken);
                }
                catch (Exception ex)
                {
                    LogGuardian($"Realtime.SetAuth after refresh warning: {ex.Message}");
                }

                LogGuardian($"RefreshUsingTokensInternalAsync: SUCCESS. New JWT valid until {newExpUtc:O} (ExpiresIn={refreshed.ExpiresIn}s).");
                return true;
            }
            catch (Exception ex)
            {
                if (IsPermanentRefreshTokenRevocation(ex))
                {
                    LogGuardian($"RefreshUsingTokensInternalAsync: Refresh token permanently revoked/invalid ({SummarizeException(ex)}). Clearing invalid session.");
                    _explicitlySignedOut = true;
                    _lastKnownAccessToken = null;
                    _lastKnownRefreshToken = null;
#if WINUI_NATIVE
                    Daily_WinUI.Services.WinUISessionPersistence.AllowDestroySession = true;
                    try
                    {
                        try { await _supabase.Auth.SignOut(); } catch { }
                        new Daily_WinUI.Services.WinUISessionPersistence().DestroySession();
                    }
                    finally
                    {
                        Daily_WinUI.Services.WinUISessionPersistence.AllowDestroySession = false;
                    }
#endif
                    return false;
                }

                // Transient error (offline, DNS not ready after wake-from-sleep, timeout, HTTP 5xx):
                // Keep _lastKnownRefreshToken & persisted session intact for next retry!
                LogGuardian($"RefreshUsingTokensInternalAsync: transient failure ({SummarizeException(ex)}). Preserving refresh token for retry.");
                return false;
            }
        }

        private static void NormalizeSessionExpiresIn(Session session, DateTime expUtc)
        {
            var createdUtc = session.CreatedAt.Kind == DateTimeKind.Utc
                ? session.CreatedAt
                : session.CreatedAt.ToUniversalTime();

            // If CreatedAt is bogus or in the future, anchor to UtcNow
            if (createdUtc == default || createdUtc > expUtc)
            {
                session.CreatedAt = DateTime.UtcNow;
                createdUtc = session.CreatedAt;
            }

            if (session.ExpiresIn <= 0 || session.ExpiresIn > MaxReasonableExpiresInSeconds)
            {
                var computedSeconds = (long)Math.Max(60, (expUtc - createdUtc).TotalSeconds);
                session.ExpiresIn = Math.Min(computedSeconds, MaxReasonableExpiresInSeconds);
            }
        }

        private static Session? LoadPersistedSessionIfSupported()
        {
#if WINUI_NATIVE
            try
            {
                return new Daily_WinUI.Services.WinUISessionPersistence().LoadSession();
            }
            catch
            {
                return null;
            }
#else
            return null;
#endif
        }

        private static void PersistSessionIfSupported(Session? session)
        {
            if (session == null || string.IsNullOrEmpty(session.AccessToken))
                return;

#if WINUI_NATIVE
            try
            {
                new Daily_WinUI.Services.WinUISessionPersistence().SaveSession(session);
            }
            catch { }
#endif
        }

        private void ConfigureRealtimeHandshakeHeaders()
        {
            try
            {
                // Supabase's API Gateway rejects ES256 user JWTs in the HTTP Upgrade 'Authorization' header on
                // /realtime/v1/websocket (HTTP 401) when paired with sb_publishable_* keys.
                // Realtime user RLS uses Phoenix WALRUS via Realtime.SetAuth(accessToken), while the WebSocket
                // HTTP Upgrade handshake must carry only the publishable API key.
                Func<System.Collections.Generic.Dictionary<string, string>> handshakeHeaders = () =>
                    new System.Collections.Generic.Dictionary<string, string>
                    {
                        { "apikey", Daily.Configuration.Secrets.SupabaseKey },
                        { "X-Client-Info", "daily-csharp" }
                    };

                if (_supabase.Realtime != null)
                {
                    _supabase.Realtime.GetHeaders = handshakeHeaders;
                    if (_supabase.Realtime.Socket != null)
                    {
                        _supabase.Realtime.Socket.GetHeaders = handshakeHeaders;
                    }
                }
            }
            catch (Exception ex)
            {
                LogGuardian($"ConfigureRealtimeHandshakeHeaders warning: {ex.Message}");
            }
        }

        public async Task<bool> EnsureRealtimeConnectedAsync(CancellationToken ct = default)
        {
            if (_supabase.Realtime == null)
                return false;

            await _realtimeLock.WaitAsync(ct);
            try
            {
                ConfigureRealtimeHandshakeHeaders();

                if (_supabase.Realtime.Socket == null || !_supabase.Realtime.Socket.IsConnected)
                {
                    var connectTask = _supabase.Realtime.ConnectAsync();
                    var completed = await Task.WhenAny(connectTask, Task.Delay(5000, ct));
                    if (completed != connectTask)
                    {
                        LogGuardian("EnsureRealtimeConnectedAsync: WebSocket connect timed out after 5s.");
                        return false;
                    }

                    await connectTask; // Observe any connect exception cleanly inside try/catch
                    ConfigureRealtimeHandshakeHeaders();
                    LogGuardian("EnsureRealtimeConnectedAsync: Realtime WebSocket connected (101 Switching Protocols).");
                }

                var accessToken = _supabase.Auth.CurrentSession?.AccessToken;
                if (!string.IsNullOrEmpty(accessToken))
                {
                    _supabase.Realtime.SetAuth(accessToken);
                }

                return _supabase.Realtime.Socket?.IsConnected == true;
            }
            catch (Exception ex)
            {
                LogGuardian($"EnsureRealtimeConnectedAsync warning: {SummarizeException(ex)}");
                return false;
            }
            finally
            {
                _realtimeLock.Release();
            }
        }

        public static bool IsJwtAuthError(Exception ex)
        {
            var cur = ex;
            while (cur != null)
            {
                var msg = cur.Message ?? string.Empty;
                if (msg.Contains("PGRST303", StringComparison.OrdinalIgnoreCase) ||
                    msg.Contains("JWT expired", StringComparison.OrdinalIgnoreCase) ||
                    msg.Contains("PGRST301", StringComparison.OrdinalIgnoreCase) ||
                    msg.Contains("PGRST302", StringComparison.OrdinalIgnoreCase) ||
                    msg.Contains("invalid JWT", StringComparison.OrdinalIgnoreCase) ||
                    msg.Contains("\"code\":401", StringComparison.OrdinalIgnoreCase) ||
                    msg.Contains("status code 401", StringComparison.OrdinalIgnoreCase) ||
                    msg.Contains("401 (Unauthorized)", StringComparison.OrdinalIgnoreCase))
                {
                    return true;
                }
                cur = cur.InnerException;
            }
            return false;
        }

        private static bool IsPermanentRefreshTokenRevocation(Exception ex)
        {
            var cur = ex;
            while (cur != null)
            {
                if (cur is GotrueException gex && gex.Reason == FailureHint.Reason.UserBadMultiple)
                    return true;

                var msg = cur.Message ?? string.Empty;
                if (msg.Contains("invalid_grant", StringComparison.OrdinalIgnoreCase) ||
                    msg.Contains("refresh_token_not_found", StringComparison.OrdinalIgnoreCase) ||
                    msg.Contains("Invalid Refresh Token", StringComparison.OrdinalIgnoreCase) ||
                    msg.Contains("Token has been revoked", StringComparison.OrdinalIgnoreCase))
                {
                    return true;
                }
                cur = cur.InnerException;
            }
            return false;
        }

        private static string SummarizeException(Exception ex)
        {
            var msg = ex.Message ?? ex.GetType().Name;
            if (msg.Length > 240) msg = msg.Substring(0, 240) + "...";
            return $"{ex.GetType().Name}: {msg}";
        }

        public static void LogGuardian(string message)
        {
            var formatted = $"[{DateTime.UtcNow:O}] [SessionGuardian] {message}";
            System.Diagnostics.Debug.WriteLine(formatted);
            try
            {
                var logPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DailyApp", "sync_debug.log");
                var dir = Path.GetDirectoryName(logPath);
                if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);

                var fi = new FileInfo(logPath);
                if (fi.Exists && fi.Length > 2 * 1024 * 1024)
                {
                    var archivePath = logPath + ".old";
                    File.Move(logPath, archivePath, overwrite: true);
                }

                File.AppendAllText(logPath, formatted + Environment.NewLine);
            }
            catch { }
        }
    }
}
