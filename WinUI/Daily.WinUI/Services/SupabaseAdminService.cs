using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Daily_WinUI.Models;
using Microsoft.Extensions.DependencyInjection;
using Windows.Security.Credentials.UI;
using Windows.Security.Cryptography;
using Windows.Security.Cryptography.DataProtection;

namespace Daily_WinUI.Services;

public sealed class SupabaseAdminService
{
    public static SupabaseAdminService Shared { get; } = new();

    private const string ManagementBaseUrl = "https://api.supabase.com/v1";
    private const string PlatformBaseUrl = "https://api.supabase.com/platform";
    private const long SnapshotCacheTtlMs = 10L * 60L * 1000L; // 10-min TTL

    private static readonly string LocalDir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Daily.WinUI");

    private static readonly string CredentialsFilePath = Path.Combine(LocalDir, "supabase_admin_creds.dpapi");
    private static readonly string SnapshotCachePath = Path.Combine(LocalDir, "supabase_admin_snapshot_v1.json");

    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNameCaseInsensitive = true,
        WriteIndented = false
    };

    private readonly HttpClient _httpClient;
    private readonly SemaphoreSlim _loadGate = new(1, 1);

    public SupabaseAdminCredentials Credentials { get; private set; } = new();
    public SupabaseAdminSnapshot? Snapshot { get; private set; }
    public bool IsLoading { get; private set; }
    public bool IsAnalyzingAi { get; private set; }
    public string? AiAnalysis { get; private set; }
    public string? ErrorMessage { get; private set; }

    public event Action? StateChanged;

    public SupabaseAdminService()
    {
        _httpClient = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(28)
        };
        _httpClient.DefaultRequestHeaders.UserAgent.ParseAdd("DayOne-Windows11-AdminConsole/1.0");
    }

    public async Task InitializeAsync()
    {
        await _loadGate.WaitAsync().ConfigureAwait(false);
        try
        {
            Directory.CreateDirectory(LocalDir);
            if (File.Exists(CredentialsFilePath))
            {
                try
                {
                    var protectedBytes = await File.ReadAllBytesAsync(CredentialsFilePath).ConfigureAwait(false);
                    var provider = new DataProtectionProvider();
                    var protectedBuffer = CryptographicBuffer.CreateFromByteArray(protectedBytes);
                    var unprotectedBuffer = await provider.UnprotectAsync(protectedBuffer);
                    CryptographicBuffer.CopyToByteArray(unprotectedBuffer, out var plainBytes);
                    var json = Encoding.UTF8.GetString(plainBytes);
                    var loaded = JsonSerializer.Deserialize<SupabaseAdminCredentials>(json, JsonOpts);
                    if (loaded != null)
                    {
                        Credentials = loaded;
                    }
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine($"[SupabaseAdminService] Credential load warning: {ex.Message}");
                }
            }

            if (Snapshot == null && File.Exists(SnapshotCachePath))
            {
                try
                {
                    var json = await File.ReadAllTextAsync(SnapshotCachePath).ConfigureAwait(false);
                    Snapshot = JsonSerializer.Deserialize<SupabaseAdminSnapshot>(json, JsonOpts);
                }
                catch { }
            }
        }
        finally
        {
            _loadGate.Release();
        }
        NotifyStateChanged();
    }

    // -------------------------------------------------------------------------
    // Cryptographic Handshake (P-256 ECDH + Raw X-Coordinate + AES-256-GCM)
    // -------------------------------------------------------------------------

    public static SupabaseCliHandshakeSession CreateHandshakeSession(string hostLabel = "DayOne-Windows11")
    {
        using var ecdh = ECDiffieHellman.Create(ECCurve.NamedCurves.nistP256);
        var pubParams = ecdh.ExportParameters(false);
        if (pubParams.Q.X == null || pubParams.Q.Y == null || pubParams.Q.X.Length != 32 || pubParams.Q.Y.Length != 32)
        {
            throw new CryptographicException("Unexpected NIST P-256 public key coordinates.");
        }

        var uncompressed = new byte[65];
        uncompressed[0] = 0x04;
        Buffer.BlockCopy(pubParams.Q.X, 0, uncompressed, 1, 32);
        Buffer.BlockCopy(pubParams.Q.Y, 0, uncompressed, 33, 32);

        var publicKeyHex = Convert.ToHexStringLower(uncompressed);
        var privateKeyPkcs8 = ecdh.ExportPkcs8PrivateKey();
        var sessionId = Guid.NewGuid().ToString("D").ToLowerInvariant();
        var stamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds() % 100_000;
        var tokenName = $"{hostLabel}-{stamp}";

        var query = $"session_id={Uri.EscapeDataString(sessionId)}&token_name={Uri.EscapeDataString(tokenName)}&public_key={Uri.EscapeDataString(publicKeyHex)}";
        var authorizeUri = new Uri($"https://supabase.com/dashboard/cli/login?{query}");

        return new SupabaseCliHandshakeSession
        {
            SessionId = sessionId,
            TokenName = tokenName,
            PublicKeyHex = publicKeyHex,
            PrivateKeyPkcs8 = privateKeyPkcs8,
            AuthorizeUri = authorizeUri
        };
    }

    public static string DecryptCliAccessToken(
        byte[] privateKeyPkcs8,
        string remotePublicKeyHex,
        string nonceHex,
        string encryptedTokenHex)
    {
        var peerBytes = Convert.FromHexString(remotePublicKeyHex.Trim());
        if (peerBytes.Length != 65 || peerBytes[0] != 0x04)
        {
            throw new CryptographicException("Invalid uncompressed P-256 public key received from Supabase.");
        }

        var nonceBytes = Convert.FromHexString(nonceHex.Trim());
        var combined = Convert.FromHexString(encryptedTokenHex.Trim());
        if (nonceBytes.Length != 12 || combined.Length <= 16)
        {
            throw new CryptographicException("Invalid AES-256-GCM nonce or ciphertext payload.");
        }

        var peerParams = new ECParameters
        {
            Curve = ECCurve.NamedCurves.nistP256,
            Q = new ECPoint
            {
                X = peerBytes[1..33],
                Y = peerBytes[33..65]
            }
        };

        using var localEcdh = ECDiffieHellman.Create();
        localEcdh.ImportPkcs8PrivateKey(privateKeyPkcs8, out _);
        using var peerEcdh = ECDiffieHellman.Create(peerParams);

        // CRITICAL: Supabase CLI Login uses raw 32-byte ECDH shared secret Z directly as the AES-256-GCM key!
        var rawSharedSecret = localEcdh.DeriveRawSecretAgreement(peerEcdh.PublicKey);
        if (rawSharedSecret.Length != 32)
        {
            throw new CryptographicException($"Expected 32-byte ECDH secret, got {rawSharedSecret.Length} bytes.");
        }

        int cipherLen = combined.Length - 16;
        var ciphertext = combined[..cipherLen];
        var tag = combined[cipherLen..];
        var plaintext = new byte[cipherLen];

        using var aesGcm = new AesGcm(rawSharedSecret, 16);
        aesGcm.Decrypt(nonceBytes, ciphertext, tag, plaintext);

        CryptographicOperations.ZeroMemory(rawSharedSecret);
        return Encoding.UTF8.GetString(plaintext);
    }

    // -------------------------------------------------------------------------
    // Authentication Lifecycle
    // -------------------------------------------------------------------------

    public async Task AuthenticateWithPersonalAccessTokenAsync(string rawToken)
    {
        var token = rawToken.Trim();
        if (!token.StartsWith("sbp_", StringComparison.Ordinal) || token.Length < 20)
        {
            throw new InvalidOperationException("Token must start with 'sbp_' (Supabase Personal Access Token).");
        }

        IsLoading = true;
        ErrorMessage = null;
        NotifyStateChanged();

        try
        {
            using var doc = await PerformGetJsonAsync($"{ManagementBaseUrl}/projects", token).ConfigureAwait(false);
            var projects = ParseProjects(doc.RootElement);
            var preferredRef = ResolvePreferredProjectRef(projects);

            Credentials = new SupabaseAdminCredentials
            {
                PatToken = token,
                SelectedProjectRef = preferredRef,
                AdminIdentity = "Supabase PAT",
                AuthMethod = "pat",
                AuthenticatedAtEpochMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()
            };
            IsUnlockedInMemory = true;
            await PersistCredentialsAsync().ConfigureAwait(false);
            await RefreshSnapshotAsync(force: true).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            IsLoading = false;
            ErrorMessage = ex.Message;
            NotifyStateChanged();
            throw;
        }
    }

    public async Task CompleteCliHandshakeAsync(
        SupabaseCliHandshakeSession session,
        string deviceCode,
        string? dashboardSessionJson)
    {
        IsLoading = true;
        ErrorMessage = null;
        NotifyStateChanged();

        try
        {
            var pollUrl = $"{PlatformBaseUrl}/cli/login/{Uri.EscapeDataString(session.SessionId)}?device_code={Uri.EscapeDataString(deviceCode.Trim())}";
            JsonDocument? pollDoc = null;
            for (int attempt = 0; attempt < 6; attempt++)
            {
                try
                {
                    using var req = new HttpRequestMessage(HttpMethod.Get, pollUrl);
                    req.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
                    using var resp = await _httpClient.SendAsync(req).ConfigureAwait(false);
                    if (resp.IsSuccessStatusCode)
                    {
                        var body = await resp.Content.ReadAsStringAsync().ConfigureAwait(false);
                        var candidate = JsonDocument.Parse(body);
                        if (candidate.RootElement.ValueKind == JsonValueKind.Object &&
                            candidate.RootElement.TryGetProperty("access_token", out var tokProp) &&
                            !string.IsNullOrWhiteSpace(tokProp.GetString()))
                        {
                            pollDoc = candidate;
                            break;
                        }
                        candidate.Dispose();
                    }
                }
                catch { }
                await Task.Delay(700).ConfigureAwait(false);
            }

            if (pollDoc == null)
            {
                throw new InvalidOperationException("Supabase CLI Login handshake timed out waiting for encrypted token.");
            }

            string decryptedPat;
            using (pollDoc)
            {
                var root = pollDoc.RootElement;
                var serverPubKey = Str(root, "public_key");
                var nonceHex = Str(root, "nonce");
                var encTokenHex = Str(root, "access_token");
                decryptedPat = DecryptCliAccessToken(session.PrivateKeyPkcs8, serverPubKey, nonceHex, encTokenHex);
            }

            var (dashJwt, dashExp, identity) = ExtractDashboardJwt(dashboardSessionJson);

            using var projDoc = await PerformGetJsonAsync($"{ManagementBaseUrl}/projects", decryptedPat).ConfigureAwait(false);
            var projects = ParseProjects(projDoc.RootElement);
            var preferredRef = ResolvePreferredProjectRef(projects);

            Credentials = new SupabaseAdminCredentials
            {
                PatToken = decryptedPat,
                DashboardAccessToken = dashJwt,
                DashboardExpiresAtEpochSec = dashExp,
                SelectedProjectRef = preferredRef,
                AdminIdentity = identity ?? "GitHub Admin",
                AuthMethod = "cli_oauth",
                AuthenticatedAtEpochMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()
            };

            IsUnlockedInMemory = true;
            await PersistCredentialsAsync().ConfigureAwait(false);
            await RefreshSnapshotAsync(force: true).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            IsLoading = false;
            ErrorMessage = ex.Message;
            NotifyStateChanged();
            throw;
        }
    }

    public async Task SelectProjectAsync(string projectRef)
    {
        if (string.IsNullOrWhiteSpace(projectRef) || Credentials.SelectedProjectRef == projectRef) return;
        Credentials.SelectedProjectRef = projectRef;
        AiAnalysis = null;
        await PersistCredentialsAsync().ConfigureAwait(false);
        await RefreshSnapshotAsync(force: true).ConfigureAwait(false);
    }

    public void Disconnect()
    {
        Credentials = new SupabaseAdminCredentials();
        IsUnlockedInMemory = false;
        Snapshot = null;
        AiAnalysis = null;
        ErrorMessage = null;
        try
        {
            if (File.Exists(CredentialsFilePath)) File.Delete(CredentialsFilePath);
            if (File.Exists(SnapshotCachePath)) File.Delete(SnapshotCachePath);
        }
        catch { }
        NotifyStateChanged();
    }

    public bool IsUnlockedInMemory { get; private set; }

    public void Lock()
    {
        if (Credentials.RequireBiometrics)
        {
            IsUnlockedInMemory = false;
        }
    }

    public void UnlockDirectly()
    {
        IsUnlockedInMemory = true;
    }

    public async Task<bool> CanUseWindowsHelloAsync()
    {
        try
        {
            var avail = await UserConsentVerifier.CheckAvailabilityAsync();
            return avail == UserConsentVerifierAvailability.Available;
        }
        catch
        {
            return false;
        }
    }

    public async Task<bool> UnlockIfNeededAsync()
    {
        if (!Credentials.RequireBiometrics)
        {
            IsUnlockedInMemory = true;
            return true;
        }

        if (IsUnlockedInMemory) return true;

        try
        {
            var avail = await UserConsentVerifier.CheckAvailabilityAsync();
            if (avail == UserConsentVerifierAvailability.Available)
            {
                var result = await UserConsentVerifier.RequestVerificationAsync("Confirm Windows Hello or PIN to access Supabase Admin Console");
                if (result == UserConsentVerificationResult.Verified)
                {
                    IsUnlockedInMemory = true;
                    return true;
                }
                return false;
            }
            else
            {
                IsUnlockedInMemory = true;
                return true;
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[SupabaseAdminService] Windows Hello check exception: {ex.Message}");
            IsUnlockedInMemory = true;
            return true;
        }
    }

    public async Task<bool> SetRequireBiometricsAsync(bool enabled)
    {
        if (enabled)
        {
            try
            {
                var avail = await UserConsentVerifier.CheckAvailabilityAsync();
                if (avail == UserConsentVerifierAvailability.Available)
                {
                    var result = await UserConsentVerifier.RequestVerificationAsync("Authenticate with Windows Hello to protect Supabase Admin Console");
                    if (result != UserConsentVerificationResult.Verified)
                    {
                        return false;
                    }
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[SupabaseAdminService] SetRequireBiometrics exception: {ex.Message}");
            }
        }

        Credentials.RequireBiometrics = enabled;
        IsUnlockedInMemory = true;
        await PersistCredentialsAsync().ConfigureAwait(false);
        NotifyStateChanged();
        return true;
    }

    public void ClearError()
    {
        ErrorMessage = null;
        NotifyStateChanged();
    }

    // -------------------------------------------------------------------------
    // Parallel Read-Only Telemetry Fetcher (10-min TTL Cache)
    // -------------------------------------------------------------------------

    public async Task EnsureLoadedOnAppearAsync()
    {
        await InitializeAsync().ConfigureAwait(false);
        if (!Credentials.IsAuthenticated) return;

        var snap = Snapshot;
        if (snap != null)
        {
            var ageMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() - snap.FetchedAtEpochMs;
            if (ageMs < SnapshotCacheTtlMs && snap.Project.Ref == Credentials.SelectedProjectRef)
            {
                return;
            }
        }
        await RefreshSnapshotAsync(force: false).ConfigureAwait(false);
    }

    public async Task RefreshSnapshotAsync(bool force)
    {
        var pat = Credentials.PatToken;
        if (string.IsNullOrWhiteSpace(pat)) return;

        if (!force && Snapshot != null)
        {
            var ageMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() - Snapshot.FetchedAtEpochMs;
            if (ageMs < SnapshotCacheTtlMs && Snapshot.Project.Ref == Credentials.SelectedProjectRef)
            {
                return;
            }
        }

        IsLoading = true;
        ErrorMessage = null;
        NotifyStateChanged();

        try
        {
            var projectsTask = PerformGetStringOptionalAsync($"{ManagementBaseUrl}/projects", pat);
            var orgsTask = PerformGetStringOptionalAsync($"{ManagementBaseUrl}/organizations", pat);
            await Task.WhenAll(projectsTask, orgsTask).ConfigureAwait(false);

            var availableProjects = ParseProjectsFromJsonString(projectsTask.Result);
            var targetRef = Credentials.SelectedProjectRef;
            var activeProject = availableProjects.FirstOrDefault(p => p.Ref == targetRef)
                ?? availableProjects.FirstOrDefault(p => p.Ref == SupabaseAdminSnapshot.DefaultProjectRef)
                ?? availableProjects.FirstOrDefault()
                ?? new SupabaseProjectSummary { Ref = targetRef };

            if (Credentials.SelectedProjectRef != activeProject.Ref)
            {
                Credentials.SelectedProjectRef = activeProject.Ref;
                await PersistCredentialsAsync().ConfigureAwait(false);
            }

            var (orgName, orgSlug, orgCreatedAt) = ResolveOrgInfo(orgsTask.Result, activeProject.OrganizationId);
            if (string.IsNullOrWhiteSpace(orgSlug))
            {
                orgSlug = activeProject.OrganizationSlug;
            }

            // Launch all read-only telemetry queries in parallel
            var diskTask = PerformGetStringOptionalAsync($"{ManagementBaseUrl}/projects/{activeProject.Ref}/config/disk", pat);
            var addonsTask = PerformGetStringOptionalAsync($"{ManagementBaseUrl}/projects/{activeProject.Ref}/billing/addons", pat);
            var apiCountsTask = PerformGetStringOptionalAsync($"{ManagementBaseUrl}/projects/{activeProject.Ref}/analytics/endpoints/usage.api-counts?interval=1day", pat);
            var functionsTask = PerformGetStringOptionalAsync($"{ManagementBaseUrl}/projects/{activeProject.Ref}/functions", pat);
            var fnStatsTask = PerformGetStringOptionalAsync($"{ManagementBaseUrl}/projects/{activeProject.Ref}/analytics/endpoints/functions.combined-stats?interval=1day", pat);
            var perfAdvTask = PerformGetStringOptionalAsync($"{ManagementBaseUrl}/projects/{activeProject.Ref}/advisors/performance", pat);
            var secAdvTask = PerformGetStringOptionalAsync($"{ManagementBaseUrl}/projects/{activeProject.Ref}/advisors/security", pat);

            var dbSqlTask = ExecuteReadOnlySqlAsync(activeProject.Ref, pat, BuildDatabaseForensicsSql());
            var cronSqlTask = ExecuteReadOnlySqlAsync(activeProject.Ref, pat, BuildCronAndStatementsSql());
            var logsSummaryTask = ExecuteClickHouseLogsAsync(activeProject.Ref, pat, BuildGatewaySummaryClickHouseSql());
            var logsRoutesTask = ExecuteClickHouseLogsAsync(activeProject.Ref, pat, BuildTopRoutesClickHouseSql());
            var logsClientsTask = ExecuteClickHouseLogsAsync(activeProject.Ref, pat, BuildClientFootprintClickHouseSql());
            var logsErrorsTask = ExecuteClickHouseLogsAsync(activeProject.Ref, pat, BuildRecentErrorsClickHouseSql());

            var platformBearer = !string.IsNullOrWhiteSpace(pat) ? pat : (Credentials.DashboardAccessToken ?? pat);

            // Subscription query for billing cycle dates
            var subTask1 = !string.IsNullOrWhiteSpace(orgSlug)
                ? PerformGetStringOptionalAsync($"{PlatformBaseUrl}/organizations/{Uri.EscapeDataString(orgSlug!)}/billing/subscription", platformBearer)
                : Task.FromResult<string?>(null);
            var subTask2 = !string.IsNullOrWhiteSpace(orgSlug)
                ? PerformGetStringOptionalAsync($"{ManagementBaseUrl}/organizations/{Uri.EscapeDataString(orgSlug!)}/billing/subscription", pat)
                : Task.FromResult<string?>(null);

            // Platform usage queries: org-level first, then project-level fallback
            var usageOrgTask = !string.IsNullOrWhiteSpace(orgSlug)
                ? PerformGetStringOptionalAsync($"{PlatformBaseUrl}/organizations/{Uri.EscapeDataString(orgSlug!)}/usage", platformBearer)
                : Task.FromResult<string?>(null);
            var usageProjTask = !string.IsNullOrWhiteSpace(orgSlug)
                ? PerformGetStringOptionalAsync($"{PlatformBaseUrl}/organizations/{Uri.EscapeDataString(orgSlug!)}/usage?project_ref={Uri.EscapeDataString(activeProject.Ref)}", platformBearer)
                : Task.FromResult<string?>(null);
            var usageV1Task = !string.IsNullOrWhiteSpace(orgSlug)
                ? PerformGetStringOptionalAsync($"{ManagementBaseUrl}/organizations/{Uri.EscapeDataString(orgSlug!)}/usage", pat)
                : Task.FromResult<string?>(null);

            await Task.WhenAll(
                diskTask, addonsTask, apiCountsTask, functionsTask, fnStatsTask, perfAdvTask, secAdvTask,
                dbSqlTask, cronSqlTask, logsSummaryTask, logsRoutesTask, logsClientsTask, logsErrorsTask,
                subTask1, subTask2, usageOrgTask, usageProjTask, usageV1Task).ConfigureAwait(false);

            var (diskSizeGb, diskType, diskIops, diskThroughput) = ParseDiskConfig(diskTask.Result);
            var (orgPlan, computeTier) = ParseAddonsAndPlan(addonsTask.Result);
            var (rest24h, auth24h, storage24h, realtime24h, dailySeriesFromCounts) = ParseUsageApiCounts(apiCountsTask.Result);

            var dbForensics = ParseDbForensics(dbSqlTask.Result);
            var (cronJobs, topStatements, rtCpuPct, rtCalls) = ParseCronAndStatements(cronSqlTask.Result);
            var (gwTotal, gw2xx, gw4xx, gw5xx, gwBytes) = ParseGatewaySummary(logsSummaryTask.Result);
            var topRoutes = ParseTopRoutes(logsRoutesTask.Result);
            var clients = ParseEcosystemClients(logsClientsTask.Result);
            var recentErrors = ParseRecentErrors(logsErrorsTask.Result);
            var edgeFunctions = ParseEdgeFunctions(functionsTask.Result, fnStatsTask.Result);
            var advisors = ParseAdvisors(perfAdvTask.Result, secAdvTask.Result);

            string? billingCyclePeriod = null;
            var subRaw = subTask1.Result ?? subTask2.Result;
            if (!string.IsNullOrWhiteSpace(subRaw))
            {
                try
                {
                    using var sdoc = JsonDocument.Parse(subRaw);
                    var sroot = sdoc.RootElement;
                    var startSec = Long(sroot, "current_period_start");
                    var endSec = Long(sroot, "current_period_end");
                    if (startSec > 0 && endSec > startSec)
                    {
                        billingCyclePeriod = SupabaseAdminFormatter.FormatBillingCyclePeriod(startSec, endSec);
                    }
                }
                catch { }
            }

            var usageRaw = usageOrgTask.Result;
            if (string.IsNullOrWhiteSpace(usageRaw) || !usageRaw.Contains("\"usages\""))
            {
                usageRaw = usageProjTask.Result;
            }
            if (string.IsNullOrWhiteSpace(usageRaw) || !usageRaw.Contains("\"usages\""))
            {
                usageRaw = usageV1Task.Result;
            }

            bool isPro = orgPlan.Contains("pro", StringComparison.OrdinalIgnoreCase) ||
                         orgPlan.Contains("team", StringComparison.OrdinalIgnoreCase) ||
                         orgPlan.Contains("enterprise", StringComparison.OrdinalIgnoreCase);

            double defaultEgressQuotaGb = isPro ? 250.0 : 5.0;
            long defaultDbQuotaBytes = isPro ? 8L * 1024 * 1024 * 1024 : 500L * 1024 * 1024;
            long defaultStorageQuotaBytes = isPro ? 100L * 1024 * 1024 * 1024 : 1024L * 1024 * 1024;
            int defaultMauQuota = isPro ? 100_000 : 50_000;

            var billing = ParsePlatformUsage(
                usageRaw,
                billingCyclePeriod,
                orgCreatedAt ?? activeProject.CreatedAt,
                defaultEgressQuotaGb,
                defaultDbQuotaBytes,
                defaultStorageQuotaBytes,
                defaultMauQuota,
                gwBytes);

            var dailySeries = ScaleDailySeriesWithGatewayBytes(dailySeriesFromCounts, gwBytes);

            var built = new SupabaseAdminSnapshot
            {
                FetchedAtEpochMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
                Project = activeProject,
                AvailableProjects = availableProjects,
                OrgName = orgName,
                OrgPlan = billing.DetectedPlan ?? orgPlan,
                ComputeTier = computeTier,
                HasExactBillingMetrics = billing.HasExact,
                BillingCyclePeriod = billing.BillingCyclePeriod,
                EgressUsedGb = billing.EgressUsedGb,
                EgressQuotaGb = billing.EgressQuotaGb,
                CachedEgressUsedGb = billing.CachedUsedGb,
                CachedEgressQuotaGb = billing.CachedQuotaGb,
                DbTotalBytes = (billing.HasExact && billing.DbSizeBytes > 0) ? billing.DbSizeBytes : Math.Max(billing.DbSizeBytes, dbForensics.DbTotalBytes),
                DbQuotaBytes = billing.DbQuotaBytes > 0 ? billing.DbQuotaBytes : defaultDbQuotaBytes,
                DbHeapBytes = dbForensics.DbHeapBytes,
                DbIndexBytes = dbForensics.DbIndexBytes,
                DiskSizeGb = diskSizeGb,
                DiskType = diskType,
                DiskIops = diskIops,
                DiskThroughputMbps = diskThroughput,
                StorageTotalBytes = billing.StorageSizeBytes > 0 ? billing.StorageSizeBytes : dbForensics.StorageBytes,
                StorageQuotaBytes = billing.StorageQuotaBytes > 0 ? billing.StorageQuotaBytes : defaultStorageQuotaBytes,
                StorageObjectCount = dbForensics.StorageObjects,
                StorageBucketCount = dbForensics.StorageBuckets,
                MonthlyActiveUsers = billing.MauUsed > 0 ? billing.MauUsed : dbForensics.Mau30d,
                MauQuota = billing.MauQuota > 0 ? billing.MauQuota : defaultMauQuota,
                ActiveSessionsCount = dbForensics.ActiveSessions,
                PairedWatchesCount = dbForensics.PairedWatches,
                FunctionInvocations = billing.FunctionInvocations > 0 ? billing.FunctionInvocations : edgeFunctions.Sum(f => f.Invocations24h),
                FunctionInvocationsQuota = billing.FunctionInvocationsQuota,
                RealtimeMessages = billing.RealtimeMessages,
                RealtimeMessagesQuota = billing.RealtimeMessagesQuota,
                RealtimePeakConnections = billing.RealtimePeakConnections > 0 ? billing.RealtimePeakConnections : dbForensics.RealtimeTotal,
                RealtimePeakConnectionsQuota = billing.RealtimePeakConnectionsQuota,
                LogIngestionGb = billing.LogIngestionGb,
                LogIngestionQuotaGb = billing.LogIngestionQuotaGb,
                LogQueryGb = billing.LogQueryGb,
                LogQueryQuotaGb = billing.LogQueryQuotaGb,
                GatewayRequests24h = gwTotal > 0 ? gwTotal : (rest24h + auth24h + storage24h + realtime24h),
                Gateway2xx24h = gw2xx,
                Gateway4xx24h = gw4xx,
                Gateway5xx24h = gw5xx,
                GatewayEgressBytes24h = gwBytes,
                RestRequests24h = rest24h,
                AuthRequests24h = auth24h,
                StorageRequests24h = storage24h,
                RealtimeRequests24h = realtime24h,
                ActiveRealtimeSubscriptions = dbForensics.RealtimeTotal,
                RealtimeSubscriptionsByTable = dbForensics.RealtimeByTable,
                RealtimeListChangesCpuPercent = rtCpuPct,
                RealtimeListChangesCalls = rtCalls,
                DailyEgressSeries = dailySeries,
                TopTables = dbForensics.Tables,
                TopSqlStatements = topStatements,
                CronJobs = cronJobs,
                TopGatewayRoutes = topRoutes,
                RecentGatewayErrors = recentErrors,
                EdgeFunctions = edgeFunctions,
                EcosystemClients = clients,
                Advisors = advisors
            };

            Snapshot = built;
            try
            {
                await File.WriteAllTextAsync(SnapshotCachePath, JsonSerializer.Serialize(built, JsonOpts)).ConfigureAwait(false);
            }
            catch { }
        }
        catch (Exception ex)
        {
            ErrorMessage = ex.Message;
        }
        finally
        {
            IsLoading = false;
            NotifyStateChanged();
        }
    }

    // -------------------------------------------------------------------------
    // SRE AI Co-Pilot (On-Device NPU / Local LLM + Deterministic Fallback)
    // -------------------------------------------------------------------------

    public async Task AnalyzeWithAiAsync()
    {
        var snap = Snapshot;
        if (snap == null || IsAnalyzingAi) return;

        IsAnalyzingAi = true;
        NotifyStateChanged();

        try
        {
            string? aiResult = null;
            try
            {
                var smartService = App.Current?.Services?.GetService<ISmartIntelligenceService>();
                if (smartService != null && await smartService.IsModelReadyAsync().ConfigureAwait(false))
                {
                    await smartService.InitializeAsync().ConfigureAwait(false);
                    var sysPrompt = "You are a Principal PostgreSQL & Supabase Cloud SRE auditing the DayOne ecosystem (iOS, macOS, Android, Windows 11, watchOS, Wear OS). Provide 4 concise, actionable bullet points covering quota risk, table/index bloat, gateway egress/errors, and Realtime WAL efficiency.";
                    var userPrompt = snap.ToMarkdownReport();
                    using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(18));
                    var generated = await smartService.GenerateResponseAsync(sysPrompt, userPrompt, cts.Token).ConfigureAwait(false);
                    if (!string.IsNullOrWhiteSpace(generated) && generated.Length > 40)
                    {
                        aiResult = $"*[On-Device AI · {smartService.ActiveEngineName}]*\n\n{generated.Trim()}";
                    }
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[SupabaseAdminService] On-device AI fallback triggered: {ex.Message}");
            }

            AiAnalysis = aiResult ?? BuildDeterministicDiagnosticSummary(snap);
        }
        finally
        {
            IsAnalyzingAi = false;
            NotifyStateChanged();
        }
    }

    public static string BuildDeterministicDiagnosticSummary(SupabaseAdminSnapshot snap)
    {
        var sb = new StringBuilder();
        sb.AppendLine("### Cloud SRE Automated Diagnostic");

        // 1. Quota & Egress posture
        var egressState = snap.EgressUsagePercent >= 80 ? "CRITICAL" : snap.EgressUsagePercent >= 50 ? "ELEVATED" : "HEALTHY";
        sb.AppendLine($"- **Quota & Egress ({egressState})**: Database uses **{SupabaseAdminFormatter.FormatBytes(snap.DbTotalBytes)}** ({snap.DbUsagePercent:F1}% of quota) and Egress stands at **{snap.EgressUsedGb:F3} GB / {snap.EgressQuotaGb:F1} GB** ({snap.EgressUsagePercent:F1}%).");

        // 2. Index bloat & dead tuples
        var bloated = snap.TopTables.Where(t => t.HasIndexBloatWarning).ToList();
        if (bloated.Count > 0)
        {
            var names = string.Join(", ", bloated.Take(3).Select(t => $"`{t.QualifiedName}` ({t.IndexFormatted} idx vs {t.HeapFormatted} heap)"));
            sb.AppendLine($"- **B-Tree Index Bloat Detected**: {names} exceed 3x index-to-heap ratio — schedule `REINDEX TABLE CONCURRENTLY` during low traffic.");
        }
        else
        {
            sb.AppendLine($"- **Storage & B-Tree Posture**: Heap ({SupabaseAdminFormatter.FormatBytes(snap.DbHeapBytes)}) vs Indexes ({SupabaseAdminFormatter.FormatBytes(snap.DbIndexBytes)}) ratio is balanced with no severe bloat.");
        }

        // 3. Gateway & Realtime WAL
        sb.AppendLine($"- **Gateway & Realtime WAL**: {snap.GatewayRequests24h} requests in 24h (`{snap.GatewayErrorRatePercent:F2}%` non-2xx rate, {SupabaseAdminFormatter.FormatBytes(snap.GatewayEgressBytes24h)} payload). Active Realtime subscriptions: **{snap.ActiveRealtimeSubscriptions}** (`realtime.list_changes` CPU share: **{snap.RealtimeListChangesCpuPercent:F1}%**).");

        // 4. Cron & Advisors
        var failingCrons = snap.CronJobs.Where(c => !c.IsHealthy).ToList();
        if (failingCrons.Count > 0)
        {
            sb.AppendLine($"- **Retention Jobs Warning**: {failingCrons.Count} `pg_cron` job(s) inactive or failed ({string.Join(", ", failingCrons.Select(c => $"`{c.JobName}`"))}).");
        }
        else if (snap.Advisors.Count > 0)
        {
            sb.AppendLine($"- **Supabase Advisors**: {snap.Advisors.Count} active notice(s) — top item: *{snap.Advisors[0].Title}* (`{snap.Advisors[0].Category}`).");
        }
        else
        {
            sb.AppendLine("- **Advisors & Cron Hygiene**: All `pg_cron` jobs healthy and zero critical Advisor warnings.");
        }

        return sb.ToString().Trim();
    }

    // -------------------------------------------------------------------------
    // SQL & ClickHouse Queries (Strictly Read-Only & Schema-Qualified)
    // -------------------------------------------------------------------------

    private static string BuildDatabaseForensicsSql() => """
        WITH db_sz AS (
            SELECT pg_catalog.pg_database_size(pg_catalog.current_database())::bigint AS total_bytes
        ),
        tbl AS (
            SELECT
                n.nspname AS schema_name,
                c.relname AS table_name,
                pg_catalog.pg_total_relation_size(c.oid)::bigint AS total_bytes,
                pg_catalog.pg_table_size(c.oid)::bigint AS heap_bytes,
                pg_catalog.pg_indexes_size(c.oid)::bigint AS index_bytes,
                COALESCE(s.n_live_tup, 0)::bigint AS live_rows,
                COALESCE(s.n_dead_tup, 0)::bigint AS dead_rows,
                (COALESCE(s.n_tup_ins, 0) + COALESCE(s.n_tup_upd, 0) + COALESCE(s.n_tup_del, 0))::bigint AS writes_total
            FROM pg_catalog.pg_class c
            JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
            LEFT JOIN pg_catalog.pg_stat_all_tables s ON s.relid = c.oid
            WHERE c.relkind = 'r'
              AND n.nspname IN ('public', 'auth', 'storage', 'realtime')
            ORDER BY pg_catalog.pg_total_relation_size(c.oid) DESC
            LIMIT 25
        ),
        st AS (
            SELECT
                COALESCE(SUM(COALESCE((metadata->>'size')::bigint, 0)), 0)::bigint AS storage_bytes,
                COUNT(*)::int AS object_count
            FROM storage.objects
        ),
        bk AS (
            SELECT COUNT(*)::int AS bucket_count FROM storage.buckets
        ),
        au AS (
            SELECT COUNT(*)::int AS mau_30d
            FROM auth.users
            WHERE last_sign_in_at >= (NOW() - INTERVAL '30 days')
        ),
        sess AS (
            SELECT COUNT(*)::int AS active_sessions
            FROM auth.sessions
            WHERE not_after IS NULL OR not_after > NOW()
        ),
        rt AS (
            SELECT COALESCE( pg_catalog.json_agg(t), '[]'::json ) AS subs
            FROM (
                SELECT entity::text AS table_name, COUNT(*)::int AS cnt
                FROM realtime.subscription
                GROUP BY entity::text
            ) t
        )
        SELECT pg_catalog.json_build_object(
            'db_total_bytes', (SELECT total_bytes FROM db_sz),
            'storage_bytes', (SELECT storage_bytes FROM st),
            'storage_objects', (SELECT object_count FROM st),
            'storage_buckets', (SELECT bucket_count FROM bk),
            'mau_30d', (SELECT mau_30d FROM au),
            'active_sessions', (SELECT active_sessions FROM sess),
            'realtime_subs', (SELECT subs FROM rt),
            'tables', COALESCE((SELECT pg_catalog.json_agg(tbl) FROM tbl), '[]'::json)
        ) AS payload;
        """;

    private static string BuildCronAndStatementsSql() => """
        WITH crons AS (
            SELECT
                j.jobid::bigint AS job_id,
                COALESCE(j.jobname, 'job_' || j.jobid::text) AS job_name,
                j.schedule,
                j.active,
                d.status AS last_status,
                d.start_time::text AS last_start_time,
                 pg_catalog.left(COALESCE(d.return_message, ''), 160) AS last_message
            FROM cron.job j
            LEFT JOIN LATERAL (
                SELECT status, start_time, return_message
                FROM cron.job_run_details r
                WHERE r.jobid = j.jobid
                ORDER BY r.start_time DESC
                LIMIT 1
            ) d ON true
            ORDER BY j.jobid ASC
            LIMIT 20
        ),
        stmts AS (
            SELECT
                pg_catalog.left(pg_catalog.regexp_replace(query, '\s+', ' ', 'g'), 140) AS query_preview,
                calls::bigint AS calls,
                pg_catalog.round(total_exec_time::numeric, 2)::float8 AS total_ms,
                pg_catalog.round(mean_exec_time::numeric, 2)::float8 AS mean_ms,
                rows::bigint AS rows_ret
            FROM extensions.pg_stat_statements
            WHERE query NOT ILIKE '%pg_stat_statements%'
            ORDER BY total_exec_time DESC
            LIMIT 10
        ),
        tot_cpu AS (
            SELECT GREATEST(COALESCE(SUM(total_exec_time), 0), 0.001)::float8 AS all_ms,
                   COALESCE(SUM(CASE WHEN query ILIKE '%realtime.list_changes%' THEN total_exec_time ELSE 0 END), 0)::float8 AS rt_ms,
                   COALESCE(SUM(CASE WHEN query ILIKE '%realtime.list_changes%' THEN calls ELSE 0 END), 0)::bigint AS rt_calls
            FROM extensions.pg_stat_statements
        ),
        watches AS (
            SELECT COUNT(*)::int AS cnt
            FROM pg_catalog.pg_class c
            JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'public' AND c.relname = 'paired_watches'
        )
        SELECT pg_catalog.json_build_object(
            'crons', COALESCE((SELECT pg_catalog.json_agg(crons) FROM crons), '[]'::json),
            'statements', COALESCE((SELECT pg_catalog.json_agg(stmts) FROM stmts), '[]'::json),
            'rt_cpu_pct', (SELECT (rt_ms / all_ms * 100.0) FROM tot_cpu),
            'rt_calls', (SELECT rt_calls FROM tot_cpu),
            'has_watches_table', (SELECT cnt FROM watches)
        ) AS payload;
        """;

    private static string BuildGatewaySummaryClickHouseSql() => """
        SELECT
            count() AS total_requests,
            countIf(toInt32OrZero(log_attributes['response.status_code']) >= 200 AND toInt32OrZero(log_attributes['response.status_code']) < 300) AS ok_2xx,
            countIf(toInt32OrZero(log_attributes['response.status_code']) >= 400 AND toInt32OrZero(log_attributes['response.status_code']) < 500) AS err_4xx,
            countIf(toInt32OrZero(log_attributes['response.status_code']) >= 500) AS err_5xx,
            sum(greatest(
                toInt64OrZero(log_attributes['response.headers.content-length']),
                toInt64OrZero(log_attributes['response.headers.content_length']),
                toInt64OrZero(log_attributes['response.size']),
                toInt64OrZero(log_attributes['response.body_size']),
                toInt64OrZero(log_attributes['response.bytes'])
            )) AS resp_bytes
        FROM logs
        WHERE (source = 'edge_logs' OR source_name = 'edge_logs')
        """;

    private static string BuildTopRoutesClickHouseSql() => """
        SELECT
            coalesce(nullIf(log_attributes['request.method'], ''), 'GET') AS method,
            coalesce(nullIf(log_attributes['request.path'], ''), '/') AS path,
            count() AS req_count,
            countIf(toInt32OrZero(log_attributes['response.status_code']) >= 400) AS err_count,
            sum(greatest(
                toInt64OrZero(log_attributes['response.headers.content-length']),
                toInt64OrZero(log_attributes['response.headers.content_length']),
                toInt64OrZero(log_attributes['response.size']),
                toInt64OrZero(log_attributes['response.body_size']),
                toInt64OrZero(log_attributes['response.bytes'])
            )) AS resp_bytes
        FROM logs
        WHERE (source = 'edge_logs' OR source_name = 'edge_logs')
        GROUP BY method, path
        ORDER BY resp_bytes DESC, req_count DESC
        LIMIT 15
        """;

    private static string BuildClientFootprintClickHouseSql() => """
        SELECT
            multiIf(
                positionCaseInsensitive(log_attributes['request.headers.user_agent'], 'Watch') > 0 OR positionCaseInsensitive(log_attributes['request.headers.user_agent'], 'Wear') > 0, 'Smartwatches (watchOS & Wear OS)',
                positionCaseInsensitive(log_attributes['request.headers.user_agent'], 'WinUI') > 0 OR positionCaseInsensitive(log_attributes['request.headers.user_agent'], 'Windows') > 0, 'Windows 11 (WinUI 3)',
                positionCaseInsensitive(log_attributes['request.headers.user_agent'], 'Macintosh') > 0 OR positionCaseInsensitive(log_attributes['request.headers.user_agent'], 'macOS') > 0, 'macOS Desktop',
                positionCaseInsensitive(log_attributes['request.headers.user_agent'], 'iPhone') > 0 OR positionCaseInsensitive(log_attributes['request.headers.user_agent'], 'iPad') > 0 OR positionCaseInsensitive(log_attributes['request.headers.user_agent'], 'CFNetwork') > 0, 'iOS (iPhone & Foldable)',
                positionCaseInsensitive(log_attributes['request.headers.user_agent'], 'Android') > 0 OR positionCaseInsensitive(log_attributes['request.headers.user_agent'], 'okhttp') > 0 OR positionCaseInsensitive(log_attributes['request.headers.user_agent'], 'Ktor') > 0, 'Android & Fold',
                positionCaseInsensitive(log_attributes['request.headers.user_agent'], 'pg_net') > 0 OR positionCaseInsensitive(log_attributes['request.headers.user_agent'], 'Deno') > 0, 'Cloud Cron & Edge Functions',
                'Web / Other Clients'
            ) AS platform_label,
            count() AS req_count,
            sum(greatest(
                toInt64OrZero(log_attributes['response.headers.content-length']),
                toInt64OrZero(log_attributes['response.headers.content_length']),
                toInt64OrZero(log_attributes['response.size']),
                toInt64OrZero(log_attributes['response.body_size']),
                toInt64OrZero(log_attributes['response.bytes'])
            )) AS resp_bytes
        FROM logs
        WHERE (source = 'edge_logs' OR source_name = 'edge_logs')
        GROUP BY platform_label
        ORDER BY req_count DESC
        """;

    private static string BuildRecentErrorsClickHouseSql() => """
        SELECT
            toString(timestamp) AS ts,
            toInt32OrZero(log_attributes['response.status_code']) AS status_code,
            coalesce(log_attributes['request.method'], '') AS method,
            coalesce(log_attributes['request.path'], '') AS path,
            coalesce(log_attributes['request.headers.user_agent'], '') AS ua,
            coalesce(event_message, '') AS msg
        FROM logs
        WHERE (source = 'edge_logs' OR source_name = 'edge_logs')
          AND toInt32OrZero(log_attributes['response.status_code']) >= 400
        ORDER BY timestamp DESC
        LIMIT 15
        """;

    // -------------------------------------------------------------------------
    // HTTP Helpers
    // -------------------------------------------------------------------------

    private async Task<JsonDocument> PerformGetJsonAsync(string url, string bearerToken)
    {
        using var req = new HttpRequestMessage(HttpMethod.Get, url);
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearerToken);
        req.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));

        using var resp = await _httpClient.SendAsync(req).ConfigureAwait(false);
        var body = await resp.Content.ReadAsStringAsync().ConfigureAwait(false);
        if (!resp.IsSuccessStatusCode)
        {
            throw new InvalidOperationException($"Supabase API HTTP {(int)resp.StatusCode}: {Truncate(body, 200)}");
        }
        return JsonDocument.Parse(body);
    }

    private async Task<string?> PerformGetStringOptionalAsync(string url, string bearerToken)
    {
        try
        {
            using var req = new HttpRequestMessage(HttpMethod.Get, url);
            req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearerToken);
            req.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
            using var resp = await _httpClient.SendAsync(req).ConfigureAwait(false);
            if (!resp.IsSuccessStatusCode) return null;
            return await resp.Content.ReadAsStringAsync().ConfigureAwait(false);
        }
        catch
        {
            return null;
        }
    }

    private async Task<string?> ExecuteReadOnlySqlAsync(string projectRef, string pat, string sql)
    {
        try
        {
            var url = $"{ManagementBaseUrl}/projects/{Uri.EscapeDataString(projectRef)}/database/query/read-only";
            var payload = JsonSerializer.Serialize(new { query = sql });
            using var req = new HttpRequestMessage(HttpMethod.Post, url)
            {
                Content = new StringContent(payload, Encoding.UTF8, "application/json")
            };
            req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", pat);
            using var resp = await _httpClient.SendAsync(req).ConfigureAwait(false);
            if (!resp.IsSuccessStatusCode) return null;
            return await resp.Content.ReadAsStringAsync().ConfigureAwait(false);
        }
        catch
        {
            return null;
        }
    }

    private async Task<string?> ExecuteClickHouseLogsAsync(string projectRef, string pat, string sql)
    {
        var endUtc = DateTimeOffset.UtcNow;
        var startUtc = endUtc.AddHours(-23.8); // Strictly < 24h window required by Supabase Analytics
        var startIso = startUtc.ToString("yyyy-MM-ddTHH:mm:ssZ", CultureInfo.InvariantCulture);
        var endIso = endUtc.ToString("yyyy-MM-ddTHH:mm:ssZ", CultureInfo.InvariantCulture);

        var url = $"{ManagementBaseUrl}/projects/{Uri.EscapeDataString(projectRef)}/analytics/endpoints/logs" +
                  $"?iso_timestamp_start={Uri.EscapeDataString(startIso)}" +
                  $"&iso_timestamp_end={Uri.EscapeDataString(endIso)}" +
                  $"&sql={Uri.EscapeDataString(sql)}";

        return await PerformGetStringOptionalAsync(url, pat).ConfigureAwait(false);
    }

    private async Task PersistCredentialsAsync()
    {
        try
        {
            Directory.CreateDirectory(LocalDir);
            var json = JsonSerializer.Serialize(Credentials, JsonOpts);
            var plainBytes = Encoding.UTF8.GetBytes(json);
            var provider = new DataProtectionProvider("LOCAL=user");
            var plainBuffer = CryptographicBuffer.CreateFromByteArray(plainBytes);
            var protectedBuffer = await provider.ProtectAsync(plainBuffer);
            CryptographicBuffer.CopyToByteArray(protectedBuffer, out var protectedBytes);
            await File.WriteAllBytesAsync(CredentialsFilePath, protectedBytes).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[SupabaseAdminService] PersistCredentials warning: {ex.Message}");
        }
    }

    private void NotifyStateChanged()
    {
        try
        {
            StateChanged?.Invoke();
        }
        catch { }
    }

    // -------------------------------------------------------------------------
    // JSON Parsers (Defensive & Zero-Throw)
    // -------------------------------------------------------------------------

    private string ResolvePreferredProjectRef(IReadOnlyList<SupabaseProjectSummary> projects)
    {
        if (!string.IsNullOrWhiteSpace(Credentials.SelectedProjectRef) &&
            projects.Any(p => p.Ref == Credentials.SelectedProjectRef))
        {
            return Credentials.SelectedProjectRef;
        }
        if (projects.Any(p => p.Ref == SupabaseAdminSnapshot.DefaultProjectRef))
        {
            return SupabaseAdminSnapshot.DefaultProjectRef;
        }
        return projects.FirstOrDefault()?.Ref ?? SupabaseAdminSnapshot.DefaultProjectRef;
    }

    private static List<SupabaseProjectSummary> ParseProjectsFromJsonString(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return new List<SupabaseProjectSummary>();
        try
        {
            using var doc = JsonDocument.Parse(json);
            return ParseProjects(doc.RootElement);
        }
        catch
        {
            return new List<SupabaseProjectSummary>();
        }
    }

    private static List<SupabaseProjectSummary> ParseProjects(JsonElement root)
    {
        var list = new List<SupabaseProjectSummary>();
        if (root.ValueKind != JsonValueKind.Array) return list;
        foreach (var item in root.EnumerateArray())
        {
            var id = FirstNonEmpty(Str(item, "id"), Str(item, "ref"));
            if (string.IsNullOrWhiteSpace(id)) continue;
            var pgVer = "17";
            if (item.TryGetProperty("database", out var dbObj) && dbObj.ValueKind == JsonValueKind.Object)
            {
                pgVer = FirstNonEmpty(Str(dbObj, "version"), "17");
            }
            list.Add(new SupabaseProjectSummary
            {
                Ref = id,
                OrganizationId = FirstNonEmpty(Str(item, "organization_id"), Str(item, "organization_slug")),
                OrganizationSlug = FirstNonEmpty(Str(item, "organization_slug"), Str(item, "organization_id")),
                Name = FirstNonEmpty(Str(item, "name"), id),
                Region = FirstNonEmpty(Str(item, "region"), "eu-central-1"),
                Status = FirstNonEmpty(Str(item, "status"), "ACTIVE_HEALTHY"),
                PostgresVersion = pgVer,
                CreatedAt = Str(item, "created_at")
            });
        }
        return list;
    }

    private static (string OrgName, string? OrgSlug, string? OrgCreatedAt) ResolveOrgInfo(string? json, string orgId)
    {
        if (string.IsNullOrWhiteSpace(json)) return ("Personal Organization", null, null);
        try
        {
            using var doc = JsonDocument.Parse(json);
            if (doc.RootElement.ValueKind != JsonValueKind.Array) return ("Personal Organization", null, null);
            JsonElement? matched = null;
            foreach (var el in doc.RootElement.EnumerateArray())
            {
                var id = FirstNonEmpty(Str(el, "id"), Str(el, "slug"));
                var slug = Str(el, "slug");
                if (!string.IsNullOrEmpty(orgId) && (id == orgId || slug == orgId))
                {
                    matched = el;
                    break;
                }
                matched ??= el;
            }
            if (matched is JsonElement m)
            {
                var name = FirstNonEmpty(Str(m, "name"), "Organization");
                var slug = FirstNonEmpty(Str(m, "slug"), Str(m, "id"));
                var createdAt = Str(m, "created_at");
                return (name, string.IsNullOrWhiteSpace(slug) ? null : slug, createdAt);
            }
        }
        catch { }
        return ("Personal Organization", null, null);
    }

    private static (int SizeGb, string Type, int Iops, int Throughput) ParseDiskConfig(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return (8, "gp3", 3000, 125);
        try
        {
            using var doc = JsonDocument.Parse(json);
            var r = doc.RootElement;
            if (r.TryGetProperty("attributes", out var attr) && attr.ValueKind == JsonValueKind.Object)
            {
                return (
                    Math.Max(1, Int(attr, "size_gb", 8)),
                    FirstNonEmpty(Str(attr, "type"), "gp3"),
                    Int(attr, "iops", 3000),
                    Int(attr, "throughput_mbps", 125));
            }
            return (
                Math.Max(1, Int(r, "size_gb", 8)),
                FirstNonEmpty(Str(r, "type"), "gp3"),
                Int(r, "iops", 3000),
                Int(r, "throughput_mbps", 125));
        }
        catch
        {
            return (8, "gp3", 3000, 125);
        }
    }

    private static (string Plan, string Compute) ParseAddonsAndPlan(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return ("Free", "Nano");
        try
        {
            using var doc = JsonDocument.Parse(json);
            var r = doc.RootElement;
            var plan = FirstNonEmpty(Str(r, "plan"), "Free");
            var compute = "Nano";
            if (r.TryGetProperty("selected_addons", out var addons) && addons.ValueKind == JsonValueKind.Array)
            {
                foreach (var a in addons.EnumerateArray())
                {
                    if (Str(a, "type").Contains("compute", StringComparison.OrdinalIgnoreCase))
                    {
                        if (a.TryGetProperty("variant", out var v) && v.ValueKind == JsonValueKind.Object)
                        {
                            compute = FirstNonEmpty(Str(v, "name"), Str(v, "identifier"), "Micro");
                        }
                    }
                }
            }
            return (plan, compute);
        }
        catch
        {
            return ("Free", "Nano");
        }
    }

    private static (long Rest24h, long Auth24h, long Storage24h, long Realtime24h, List<SupabaseDailyEgressPoint> Series) ParseUsageApiCounts(string? json)
    {
        var series = new List<SupabaseDailyEgressPoint>();
        if (string.IsNullOrWhiteSpace(json)) return (0, 0, 0, 0, series);
        try
        {
            using var doc = JsonDocument.Parse(json);
            var arr = UnwrapResultArray(doc.RootElement);
            long restTotal = 0, authTotal = 0, storageTotal = 0, rtTotal = 0;

            var rows = arr.TakeLast(14).ToList();
            for (int i = 0; i < rows.Count; i++)
            {
                var item = rows[i];
                var ts = FirstNonEmpty(Str(item, "timestamp"), Str(item, "period_start"));
                var label = ts.Length >= 10 ? ts.Substring(5, 5) : $"D-{rows.Count - i}";
                var r = Long(item, "total_rest_requests");
                var a = Long(item, "total_auth_requests");
                var s = Long(item, "total_storage_requests");
                var rt = Long(item, "total_realtime_requests");

                if (i == rows.Count - 1)
                {
                    restTotal = r;
                    authTotal = a;
                    storageTotal = s;
                    rtTotal = rt;
                }

                series.Add(new SupabaseDailyEgressPoint
                {
                    DateLabel = label,
                    RestBytes = r * 2048L,
                    AuthBytes = a * 1024L,
                    StorageBytes = s * 8192L,
                    RealtimeBytes = rt * 768L
                });
            }
            return (restTotal, authTotal, storageTotal, rtTotal, series);
        }
        catch
        {
            return (0, 0, 0, 0, series);
        }
    }

    private static List<SupabaseDailyEgressPoint> ScaleDailySeriesWithGatewayBytes(List<SupabaseDailyEgressPoint> series, long gatewayBytes24h)
    {
        if (series.Count == 0 || gatewayBytes24h <= 0) return series;
        var last = series[^1];
        if (last.TotalBytes <= 0) return series;
        double factor = (double)gatewayBytes24h / last.TotalBytes;
        series[^1] = new SupabaseDailyEgressPoint
        {
            DateLabel = last.DateLabel,
            RestBytes = (long)(last.RestBytes * factor),
            FunctionsBytes = (long)(last.FunctionsBytes * factor),
            RealtimeBytes = (long)(last.RealtimeBytes * factor),
            StorageBytes = (long)(last.StorageBytes * factor),
            AuthBytes = (long)(last.AuthBytes * factor),
            SupavisorBytes = (long)(last.SupavisorBytes * factor)
        };
        return series;
    }

    private sealed class DbForensicsParsed
    {
        public long DbTotalBytes { get; init; }
        public long DbHeapBytes { get; init; }
        public long DbIndexBytes { get; init; }
        public long StorageBytes { get; init; }
        public int StorageObjects { get; init; }
        public int StorageBuckets { get; init; }
        public int Mau30d { get; init; }
        public int ActiveSessions { get; init; }
        public int PairedWatches { get; init; }
        public int RealtimeTotal { get; init; }
        public Dictionary<string, int> RealtimeByTable { get; init; } = new();
        public List<SupabaseTableFootprint> Tables { get; init; } = new();
    }

    private static DbForensicsParsed ParseDbForensics(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return new DbForensicsParsed();
        try
        {
            using var doc = JsonDocument.Parse(json);
            var payload = ExtractFirstSqlPayloadObject(doc.RootElement);
            if (payload == null) return new DbForensicsParsed();
            var p = payload.Value;

            var tables = new List<SupabaseTableFootprint>();
            long heapSum = 0, idxSum = 0;
            if (p.TryGetProperty("tables", out var tArr) && tArr.ValueKind == JsonValueKind.Array)
            {
                foreach (var t in tArr.EnumerateArray())
                {
                    var heap = Long(t, "heap_bytes");
                    var idx = Long(t, "index_bytes");
                    heapSum += heap;
                    idxSum += idx;
                    tables.Add(new SupabaseTableFootprint
                    {
                        SchemaName = FirstNonEmpty(Str(t, "schema_name"), "public"),
                        TableName = Str(t, "table_name"),
                        TotalBytes = Long(t, "total_bytes"),
                        TableHeapBytes = heap,
                        IndexBytes = idx,
                        LiveRows = Long(t, "live_rows"),
                        DeadRows = Long(t, "dead_rows"),
                        WritesTotal = Long(t, "writes_total")
                    });
                }
            }

            var rtMap = new Dictionary<string, int>();
            int rtTotal = 0;
            if (p.TryGetProperty("realtime_subs", out var rtArr) && rtArr.ValueKind == JsonValueKind.Array)
            {
                foreach (var r in rtArr.EnumerateArray())
                {
                    var tbl = FirstNonEmpty(Str(r, "table_name"), "unknown");
                    var cnt = Int(r, "cnt");
                    rtMap[tbl] = cnt;
                    rtTotal += cnt;
                }
            }

            int watches = (int)tables.FirstOrDefault(x => x.TableName == "paired_watches")?.LiveRows!;

            return new DbForensicsParsed
            {
                DbTotalBytes = Long(p, "db_total_bytes"),
                DbHeapBytes = heapSum,
                DbIndexBytes = idxSum,
                StorageBytes = Long(p, "storage_bytes"),
                StorageObjects = Int(p, "storage_objects"),
                StorageBuckets = Int(p, "storage_buckets"),
                Mau30d = Int(p, "mau_30d"),
                ActiveSessions = Int(p, "active_sessions"),
                PairedWatches = Math.Max(0, watches),
                RealtimeTotal = rtTotal,
                RealtimeByTable = rtMap,
                Tables = tables
            };
        }
        catch
        {
            return new DbForensicsParsed();
        }
    }

    private static (List<SupabaseCronJobHealth> Crons, List<SupabaseSqlHotspot> Statements, double RtCpuPct, long RtCalls) ParseCronAndStatements(string? json)
    {
        var crons = new List<SupabaseCronJobHealth>();
        var stmts = new List<SupabaseSqlHotspot>();
        if (string.IsNullOrWhiteSpace(json)) return (crons, stmts, 0.0, 0L);
        try
        {
            using var doc = JsonDocument.Parse(json);
            var payload = ExtractFirstSqlPayloadObject(doc.RootElement);
            if (payload == null) return (crons, stmts, 0.0, 0L);
            var p = payload.Value;

            if (p.TryGetProperty("crons", out var cArr) && cArr.ValueKind == JsonValueKind.Array)
            {
                foreach (var c in cArr.EnumerateArray())
                {
                    crons.Add(new SupabaseCronJobHealth
                    {
                        JobId = Long(c, "job_id"),
                        JobName = Str(c, "job_name"),
                        Schedule = Str(c, "schedule"),
                        Active = Bool(c, "active", true),
                        LastStatus = StrOrNull(c, "last_status"),
                        LastStartTime = StrOrNull(c, "last_start_time"),
                        LastMessage = StrOrNull(c, "last_message")
                    });
                }
            }

            if (p.TryGetProperty("statements", out var sArr) && sArr.ValueKind == JsonValueKind.Array)
            {
                foreach (var s in sArr.EnumerateArray())
                {
                    stmts.Add(new SupabaseSqlHotspot
                    {
                        QueryPreview = Str(s, "query_preview"),
                        Calls = Long(s, "calls"),
                        TotalExecTimeMs = Double(s, "total_ms"),
                        MeanExecTimeMs = Double(s, "mean_ms"),
                        RowsReturned = Long(s, "rows_ret")
                    });
                }
            }

            return (crons, stmts, Double(p, "rt_cpu_pct"), Long(p, "rt_calls"));
        }
        catch
        {
            return (crons, stmts, 0.0, 0L);
        }
    }

    private static (long Total, long Ok2xx, long Err4xx, long Err5xx, long Bytes) ParseGatewaySummary(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return (0, 0, 0, 0, 0);
        try
        {
            using var doc = JsonDocument.Parse(json);
            var arr = UnwrapResultArray(doc.RootElement);
            if (arr.Count == 0) return (0, 0, 0, 0, 0);
            var r = arr[0];
            long total = Long(r, "total_requests");
            long bytes = Long(r, "resp_bytes");
            // If proxy omitted Content-Length due to chunked streaming, apply estimation fallback
            if (bytes == 0 && total > 0)
            {
                bytes = total * 1280L;
            }
            return (
                total,
                Long(r, "ok_2xx"),
                Long(r, "err_4xx"),
                Long(r, "err_5xx"),
                bytes);
        }
        catch
        {
            return (0, 0, 0, 0, 0);
        }
    }

    private static List<SupabaseGatewayRouteStat> ParseTopRoutes(string? json)
    {
        var list = new List<SupabaseGatewayRouteStat>();
        if (string.IsNullOrWhiteSpace(json)) return list;
        try
        {
            using var doc = JsonDocument.Parse(json);
            foreach (var r in UnwrapResultArray(doc.RootElement))
            {
                var method = FirstNonEmpty(Str(r, "method"), "GET");
                var path = FirstNonEmpty(Str(r, "path"), "/");
                var reqCount = Long(r, "req_count");
                var bytes = Long(r, "resp_bytes");

                if (bytes == 0 && reqCount > 0)
                {
                    if (path.StartsWith("/storage/")) bytes = reqCount * 8192L;
                    else if (path.StartsWith("/rest/")) bytes = reqCount * 1280L;
                    else if (path.StartsWith("/auth/")) bytes = reqCount * 850L;
                    else if (path.StartsWith("/functions/")) bytes = reqCount * 1150L;
                    else if (path.StartsWith("/realtime/")) bytes = reqCount * 450L;
                    else bytes = reqCount * 900L;
                }

                list.Add(new SupabaseGatewayRouteStat
                {
                    Method = method,
                    Path = path,
                    RequestCount = reqCount,
                    ErrorCount = Long(r, "err_count"),
                    ResponseBytes = bytes
                });
            }
        }
        catch { }
        return list;
    }

    private static List<SupabaseClientFootprint> ParseEcosystemClients(string? json)
    {
        var list = new List<SupabaseClientFootprint>();
        if (string.IsNullOrWhiteSpace(json)) return list;
        try
        {
            using var doc = JsonDocument.Parse(json);
            var rows = UnwrapResultArray(doc.RootElement);
            long totalReqs = Math.Max(1L, rows.Sum(r => Long(r, "req_count")));
            foreach (var r in rows)
            {
                var reqs = Long(r, "req_count");
                list.Add(new SupabaseClientFootprint
                {
                    PlatformLabel = FirstNonEmpty(Str(r, "platform_label"), "Other"),
                    RequestCount24h = reqs,
                    EgressBytes24h = Long(r, "resp_bytes"),
                    ShareRatio = (double)reqs / totalReqs
                });
            }
        }
        catch { }
        return list;
    }

    private static List<SupabaseGatewayErrorEvent> ParseRecentErrors(string? json)
    {
        var list = new List<SupabaseGatewayErrorEvent>();
        if (string.IsNullOrWhiteSpace(json)) return list;
        try
        {
            using var doc = JsonDocument.Parse(json);
            foreach (var r in UnwrapResultArray(doc.RootElement))
            {
                list.Add(new SupabaseGatewayErrorEvent
                {
                    Timestamp = Str(r, "ts"),
                    StatusCode = Int(r, "status_code"),
                    Method = Str(r, "method"),
                    Path = Str(r, "path"),
                    UserAgent = Str(r, "ua"),
                    Message = Str(r, "msg")
                });
            }
        }
        catch { }
        return list;
    }

    private static List<SupabaseEdgeFunctionStat> ParseEdgeFunctions(string? fnJson, string? statsJson)
    {
        var list = new List<SupabaseEdgeFunctionStat>();
        if (string.IsNullOrWhiteSpace(fnJson)) return list;
        try
        {
            var statsById = new Dictionary<string, (long Calls, long Errors, double AvgMs)>();
            if (!string.IsNullOrWhiteSpace(statsJson))
            {
                try
                {
                    using var sDoc = JsonDocument.Parse(statsJson);
                    foreach (var row in UnwrapResultArray(sDoc.RootElement))
                    {
                        var fid = FirstNonEmpty(Str(row, "function_id"), Str(row, "id"));
                        if (string.IsNullOrEmpty(fid)) continue;
                        var prev = statsById.TryGetValue(fid, out var p) ? p : (0L, 0L, 0.0);
                        var calls = Long(row, "requests_count") + Long(row, "invocations");
                        var errs = Long(row, "log_error_count") + Long(row, "errors");
                        var ms = Double(row, "avg_execution_time");
                        statsById[fid] = (prev.Item1 + calls, prev.Item2 + errs, ms > 0 ? ms : prev.Item3);
                    }
                }
                catch { }
            }

            using var doc = JsonDocument.Parse(fnJson);
            if (doc.RootElement.ValueKind == JsonValueKind.Array)
            {
                foreach (var f in doc.RootElement.EnumerateArray())
                {
                    var id = Str(f, "id");
                    var slug = FirstNonEmpty(Str(f, "slug"), Str(f, "name"));
                    var st = statsById.TryGetValue(id, out var found) ? found : (0L, 0L, 0.0);
                    list.Add(new SupabaseEdgeFunctionStat
                    {
                        Id = id,
                        Slug = slug,
                        Name = FirstNonEmpty(Str(f, "name"), slug),
                        Status = FirstNonEmpty(Str(f, "status"), "ACTIVE"),
                        Version = Int(f, "version", 1),
                        VerifyJwt = Bool(f, "verify_jwt", true),
                        Invocations24h = st.Item1,
                        Errors24h = st.Item2,
                        AvgExecutionMs = st.Item3
                    });
                }
            }
        }
        catch { }
        return list;
    }

    private static List<SupabaseAdvisorNotice> ParseAdvisors(string? perfJson, string? secJson)
    {
        var list = new List<SupabaseAdvisorNotice>();
        ParseSingleAdvisorSet(perfJson, "PERFORMANCE", list);
        ParseSingleAdvisorSet(secJson, "SECURITY", list);
        return list;
    }

    private static void ParseSingleAdvisorSet(string? json, string category, List<SupabaseAdvisorNotice> target)
    {
        if (string.IsNullOrWhiteSpace(json)) return;
        try
        {
            using var doc = JsonDocument.Parse(json);
            JsonElement arr = doc.RootElement;
            if (arr.ValueKind == JsonValueKind.Object && arr.TryGetProperty("lints", out var lints))
            {
                arr = lints;
            }
            if (arr.ValueKind != JsonValueKind.Array) return;
            foreach (var item in arr.EnumerateArray())
            {
                target.Add(new SupabaseAdvisorNotice
                {
                    Name = Str(item, "name"),
                    Title = FirstNonEmpty(Str(item, "title"), Str(item, "name")),
                    Level = FirstNonEmpty(Str(item, "level"), "WARN").ToUpperInvariant(),
                    Category = category,
                    Description = FirstNonEmpty(Str(item, "description"), Str(item, "detail")),
                    Remediation = Str(item, "remediation")
                });
            }
        }
        catch { }
    }

    private sealed record PlatformBillingParsed(
        bool HasExact,
        string? DetectedPlan,
        string? BillingCyclePeriod,
        double EgressUsedGb,
        double EgressQuotaGb,
        double CachedUsedGb,
        double CachedQuotaGb,
        long DbSizeBytes,
        long DbQuotaBytes,
        long StorageSizeBytes,
        long StorageQuotaBytes,
        long FunctionInvocations,
        long FunctionInvocationsQuota,
        long RealtimeMessages,
        long RealtimeMessagesQuota,
        long RealtimePeakConnections,
        long RealtimePeakConnectionsQuota,
        int MauUsed,
        int MauQuota,
        double LogIngestionGb,
        double LogIngestionQuotaGb,
        double LogQueryGb,
        double LogQueryQuotaGb);

    private static PlatformBillingParsed ParsePlatformUsage(
        string? json,
        string? precomputedPeriod,
        string? anchorCreationDate,
        double fallbackEgressQuotaGb,
        long fallbackDbQuota,
        long fallbackStorageQuota,
        int fallbackMauQuota,
        long gatewayBytes24h)
    {
        double estGb = Math.Max(0.0, gatewayBytes24h / (1024.0 * 1024.0 * 1024.0));
        string? cyclePeriod = precomputedPeriod;

        if (string.IsNullOrWhiteSpace(json))
        {
            cyclePeriod ??= SupabaseAdminFormatter.ComputeBillingCyclePeriodFromCreation(anchorCreationDate);
            return new PlatformBillingParsed(
                false, null, cyclePeriod, estGb, fallbackEgressQuotaGb, 0.0, fallbackEgressQuotaGb,
                0L, fallbackDbQuota, 0L, fallbackStorageQuota, 0L, 500_000L, 0L, 2_000_000L, 0L, 200L, 0, fallbackMauQuota, 0.0, 1.0, 0.0, 100.0);
        }

        try
        {
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;
            string? plan = StrOrNull(root, "plan");
            double egressUsed = estGb, egressQuota = fallbackEgressQuotaGb;
            double cachedUsed = 0.0, cachedQuota = fallbackEgressQuotaGb;
            long dbSize = 0L, dbQuota = fallbackDbQuota;
            long storageSize = 0L, stQuota = fallbackStorageQuota;
            long fnInvocations = 0L, fnQuota = 500_000L;
            long rtMessages = 0L, rtMsgQuota = 2_000_000L;
            long rtPeak = 0L, rtPeakQuota = 200L;
            int mauUsed = 0, mauQuota = fallbackMauQuota;
            double logIngestGb = 0.0, logIngestQuotaGb = 1.0;
            double logQueryGb = 0.0, logQueryQuotaGb = 100.0;
            bool exact = false;

            if (cyclePeriod == null)
            {
                var startSec = Long(root, "billing_cycle_start");
                if (startSec <= 0) startSec = Long(root, "period_start");
                var endSec = Long(root, "billing_cycle_end");
                if (endSec <= 0) endSec = Long(root, "period_end");
                if (startSec > 0 && endSec > startSec)
                {
                    cyclePeriod = SupabaseAdminFormatter.FormatBillingCyclePeriod(startSec, endSec);
                }
            }

            static long ResolveBytes(double val, long orig)
            {
                if (orig > 0) return orig;
                if (val > 0 && val < 100_000.0) return (long)(val * 1_073_741_824.0);
                return (long)val;
            }

            if (root.TryGetProperty("usages", out var usages) && usages.ValueKind == JsonValueKind.Array)
            {
                foreach (var u in usages.EnumerateArray())
                {
                    var metric = Str(u, "metric").ToLowerInvariant();
                    var usageVal = Double(u, "usage");
                    var usageOrig = Long(u, "usage_original");
                    var limitVal = Double(u, "pricing_free_units");
                    if (limitVal <= 0) limitVal = Double(u, "capped_quota");
                    if (limitVal <= 0) limitVal = Double(u, "available_in_plan");

                    if (metric == "egress" || (metric.Contains("egress") && !metric.Contains("cached")))
                    {
                        var parsedEgress = (usageOrig > 0) ? (usageOrig / 1_073_741_824.0) : (usageVal > 1_000_000 ? usageVal / 1_073_741_824.0 : usageVal);
                        egressUsed = Math.Max(egressUsed, parsedEgress);
                        if (limitVal > 0) egressQuota = limitVal > 1_000_000 ? limitVal / 1_073_741_824.0 : limitVal;
                        exact = true;
                    }
                    else if (metric.Contains("cached_egress"))
                    {
                        cachedUsed = (usageOrig > 0) ? (usageOrig / 1_073_741_824.0) : (usageVal > 1_000_000 ? usageVal / 1_073_741_824.0 : usageVal);
                        if (limitVal > 0) cachedQuota = limitVal > 1_000_000 ? limitVal / 1_073_741_824.0 : limitVal;
                    }
                    else if (metric == "database_size" || metric == "db_size")
                    {
                        dbSize = ResolveBytes(usageVal, usageOrig);
                        if (limitVal > 0) dbQuota = ResolveBytes(limitVal, 0);
                    }
                    else if (metric == "storage_size")
                    {
                        storageSize = ResolveBytes(usageVal, usageOrig);
                        if (limitVal > 0) stQuota = ResolveBytes(limitVal, 0);
                    }
                    else if (metric == "function_invocations")
                    {
                        fnInvocations = usageOrig > 0 ? usageOrig : (long)usageVal;
                        if (limitVal > 0) fnQuota = (long)limitVal;
                    }
                    else if (metric == "realtime_message_count")
                    {
                        rtMessages = usageOrig > 0 ? usageOrig : (long)usageVal;
                        if (limitVal > 0) rtMsgQuota = (long)limitVal;
                    }
                    else if (metric == "realtime_peak_connections")
                    {
                        rtPeak = usageOrig > 0 ? usageOrig : (long)usageVal;
                        if (limitVal > 0) rtPeakQuota = (long)limitVal;
                    }
                    else if (metric == "monthly_active_users")
                    {
                        mauUsed = (int)(usageOrig > 0 ? usageOrig : (long)usageVal);
                        if (limitVal > 0) mauQuota = (int)limitVal;
                    }
                    else if (metric == "log_ingestion" || metric == "log_drain_events")
                    {
                        logIngestGb = (usageOrig > 0) ? (usageOrig / 1_073_741_824.0) : (usageVal > 1_000_000 ? usageVal / 1_073_741_824.0 : usageVal);
                        if (limitVal > 0) logIngestQuotaGb = limitVal > 1_000_000 ? limitVal / 1_073_741_824.0 : limitVal;
                    }
                    else if (metric == "log_query" || metric == "log_querying")
                    {
                        logQueryGb = (usageOrig > 0) ? (usageOrig / 1_073_741_824.0) : (usageVal > 1_000_000 ? usageVal / 1_073_741_824.0 : usageVal);
                        if (limitVal > 0) logQueryQuotaGb = limitVal > 1_000_000 ? limitVal / 1_073_741_824.0 : limitVal;
                    }
                }
            }

            cyclePeriod ??= SupabaseAdminFormatter.ComputeBillingCyclePeriodFromCreation(anchorCreationDate);

            return new PlatformBillingParsed(
                exact, plan, cyclePeriod, egressUsed, egressQuota, cachedUsed, cachedQuota,
                dbSize, dbQuota, storageSize, stQuota, fnInvocations, fnQuota,
                rtMessages, rtMsgQuota, rtPeak, rtPeakQuota, mauUsed, mauQuota,
                logIngestGb, logIngestQuotaGb, logQueryGb, logQueryQuotaGb);
        }
        catch
        {
            cyclePeriod ??= SupabaseAdminFormatter.ComputeBillingCyclePeriodFromCreation(anchorCreationDate);
            return new PlatformBillingParsed(
                false, null, cyclePeriod, estGb, fallbackEgressQuotaGb, 0.0, fallbackEgressQuotaGb,
                0L, fallbackDbQuota, 0L, fallbackStorageQuota, 0L, 500_000L, 0L, 2_000_000L, 0L, 200L, 0, fallbackMauQuota, 0.0, 1.0, 0.0, 100.0);
        }
    }

    private static (string? Jwt, long? ExpiresAt, string? Identity) ExtractDashboardJwt(string? rawJson)
    {
        if (string.IsNullOrWhiteSpace(rawJson)) return (null, null, null);
        try
        {
            using var doc = JsonDocument.Parse(rawJson);
            var root = doc.RootElement;
            if (root.ValueKind == JsonValueKind.String)
            {
                using var inner = JsonDocument.Parse(root.GetString() ?? "{}");
                return ExtractDashboardJwtFromElement(inner.RootElement);
            }
            return ExtractDashboardJwtFromElement(root);
        }
        catch
        {
            return (null, null, null);
        }
    }

    private static (string? Jwt, long? ExpiresAt, string? Identity) ExtractDashboardJwtFromElement(JsonElement el)
    {
        if (el.ValueKind != JsonValueKind.Object) return (null, null, null);
        var target = el.TryGetProperty("currentSession", out var cs) && cs.ValueKind == JsonValueKind.Object ? cs : el;
        var jwt = StrOrNull(target, "access_token");
        long? exp = target.TryGetProperty("expires_at", out var expProp) && expProp.TryGetInt64(out var e) ? e : null;
        string? identity = null;
        if (target.TryGetProperty("user", out var u) && u.ValueKind == JsonValueKind.Object)
        {
            identity = StrOrNull(u, "email");
            if (u.TryGetProperty("user_metadata", out var meta) && meta.ValueKind == JsonValueKind.Object)
            {
                identity = FirstNonEmpty(Str(meta, "user_name"), Str(meta, "preferred_username"), identity ?? string.Empty);
            }
        }
        return (jwt, exp, string.IsNullOrWhiteSpace(identity) ? null : identity);
    }

    private static JsonElement? ExtractFirstSqlPayloadObject(JsonElement root)
    {
        var arr = UnwrapResultArray(root);
        if (arr.Count == 0) return null;
        var row0 = arr[0];
        if (row0.TryGetProperty("payload", out var p))
        {
            if (p.ValueKind == JsonValueKind.Object) return p;
            if (p.ValueKind == JsonValueKind.String)
            {
                using var nested = JsonDocument.Parse(p.GetString() ?? "{}");
                return nested.RootElement.Clone();
            }
        }
        return row0.ValueKind == JsonValueKind.Object ? row0 : null;
    }

    private static List<JsonElement> UnwrapResultArray(JsonElement root)
    {
        if (root.ValueKind == JsonValueKind.Array)
        {
            return root.EnumerateArray().ToList();
        }
        if (root.ValueKind == JsonValueKind.Object &&
            root.TryGetProperty("result", out var res) &&
            res.ValueKind == JsonValueKind.Array)
        {
            return res.EnumerateArray().ToList();
        }
        return new List<JsonElement>();
    }

    private static string Str(JsonElement el, string prop)
    {
        if (el.ValueKind == JsonValueKind.Object && el.TryGetProperty(prop, out var v))
        {
            return v.ValueKind switch
            {
                JsonValueKind.String => v.GetString() ?? string.Empty,
                JsonValueKind.Number => v.GetRawText(),
                JsonValueKind.True => "true",
                JsonValueKind.False => "false",
                _ => string.Empty
            };
        }
        return string.Empty;
    }

    private static string? StrOrNull(JsonElement el, string prop)
    {
        var s = Str(el, prop);
        return string.IsNullOrWhiteSpace(s) ? null : s;
    }

    private static int Int(JsonElement el, string prop, int fallback = 0)
    {
        if (el.ValueKind == JsonValueKind.Object && el.TryGetProperty(prop, out var v))
        {
            if (v.ValueKind == JsonValueKind.Number && v.TryGetInt32(out var n)) return n;
            if (v.ValueKind == JsonValueKind.String && int.TryParse(v.GetString(), NumberStyles.Any, CultureInfo.InvariantCulture, out var parsed)) return parsed;
        }
        return fallback;
    }

    private static long Long(JsonElement el, string prop, long fallback = 0L)
    {
        if (el.ValueKind == JsonValueKind.Object && el.TryGetProperty(prop, out var v))
        {
            if (v.ValueKind == JsonValueKind.Number && v.TryGetInt64(out var n)) return n;
            if (v.ValueKind == JsonValueKind.Number && v.TryGetDouble(out var d)) return (long)d;
            if (v.ValueKind == JsonValueKind.String && long.TryParse(v.GetString(), NumberStyles.Any, CultureInfo.InvariantCulture, out var parsed)) return parsed;
        }
        return fallback;
    }

    private static double Double(JsonElement el, string prop, double fallback = 0.0)
    {
        if (el.ValueKind == JsonValueKind.Object && el.TryGetProperty(prop, out var v))
        {
            if (v.ValueKind == JsonValueKind.Number && v.TryGetDouble(out var d)) return d;
            if (v.ValueKind == JsonValueKind.String && double.TryParse(v.GetString(), NumberStyles.Any, CultureInfo.InvariantCulture, out var parsed)) return parsed;
        }
        return fallback;
    }

    private static bool Bool(JsonElement el, string prop, bool fallback = false)
    {
        if (el.ValueKind == JsonValueKind.Object && el.TryGetProperty(prop, out var v))
        {
            if (v.ValueKind == JsonValueKind.True) return true;
            if (v.ValueKind == JsonValueKind.False) return false;
            if (v.ValueKind == JsonValueKind.String && bool.TryParse(v.GetString(), out var b)) return b;
        }
        return fallback;
    }

    private static string FirstNonEmpty(params string[] values)
    {
        foreach (var v in values)
        {
            if (!string.IsNullOrWhiteSpace(v)) return v;
        }
        return string.Empty;
    }

    private static string Truncate(string s, int maxLen) =>
        s.Length <= maxLen ? s : s[..maxLen] + "…";
}
