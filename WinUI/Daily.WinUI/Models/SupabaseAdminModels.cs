using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;

namespace Daily_WinUI.Models;

public sealed class SupabaseAdminCredentials
{
    public string? PatToken { get; set; }
    public string? DashboardAccessToken { get; set; }
    public string? DashboardRefreshToken { get; set; }
    public long? DashboardExpiresAtEpochSec { get; set; }
    public string SelectedProjectRef { get; set; } = SupabaseAdminSnapshot.DefaultProjectRef;
    public string? SelectedOrgSlug { get; set; }
    public string? AdminIdentity { get; set; }
    public string AuthMethod { get; set; } = "none";
    public long AuthenticatedAtEpochMs { get; set; }
    public bool RequireBiometrics { get; set; } = false;

    public bool IsAuthenticated => !string.IsNullOrWhiteSpace(PatToken) || !string.IsNullOrWhiteSpace(DashboardAccessToken);

    public bool HasValidDashboardJwt
    {
        get
        {
            if (string.IsNullOrWhiteSpace(DashboardAccessToken)) return false;
            if (DashboardExpiresAtEpochSec is long exp && exp > 0)
            {
                return DateTimeOffset.UtcNow.ToUnixTimeSeconds() < (exp - 120);
            }
            return false;
        }
    }
}

public sealed class SupabaseCliHandshakeSession
{
    public required string SessionId { get; init; }
    public required string TokenName { get; init; }
    public required string PublicKeyHex { get; init; }
    public required byte[] PrivateKeyPkcs8 { get; init; }
    public required Uri AuthorizeUri { get; init; }
}

public sealed class SupabaseProjectSummary
{
    public string Ref { get; init; } = SupabaseAdminSnapshot.DefaultProjectRef;
    public string OrganizationId { get; init; } = string.Empty;
    public string OrganizationSlug { get; init; } = string.Empty;
    public string Name { get; init; } = "Daily";
    public string Region { get; init; } = "eu-central-1";
    public string Status { get; init; } = "ACTIVE_HEALTHY";
    public string PostgresVersion { get; init; } = "17";
    public string CreatedAt { get; init; } = string.Empty;

    public string DisplayLabel => $"{Name} ({Ref} · {Region})";
}

public sealed class SupabaseTableFootprint
{
    public string SchemaName { get; init; } = "public";
    public string TableName { get; init; } = string.Empty;
    public long TotalBytes { get; init; }
    public long TableHeapBytes { get; init; }
    public long IndexBytes { get; init; }
    public long LiveRows { get; init; }
    public long DeadRows { get; init; }
    public long WritesTotal { get; init; }

    public string QualifiedName => SchemaName == "public" ? TableName : $"{SchemaName}.{TableName}";
    public string TotalFormatted => SupabaseAdminFormatter.FormatBytes(TotalBytes);
    public string HeapFormatted => SupabaseAdminFormatter.FormatBytes(TableHeapBytes);
    public string IndexFormatted => SupabaseAdminFormatter.FormatBytes(IndexBytes);
    public double IndexToHeapRatio => TableHeapBytes > 0 ? (double)IndexBytes / TableHeapBytes : 0.0;
    public bool HasIndexBloatWarning => IndexBytes > 2_097_152 && IndexToHeapRatio > 3.0;
}

public sealed class SupabaseSqlHotspot
{
    public string QueryPreview { get; init; } = string.Empty;
    public long Calls { get; init; }
    public double TotalExecTimeMs { get; init; }
    public double MeanExecTimeMs { get; init; }
    public long RowsReturned { get; init; }
}

public sealed class SupabaseCronJobHealth
{
    public long JobId { get; init; }
    public string JobName { get; init; } = string.Empty;
    public string Schedule { get; init; } = string.Empty;
    public bool Active { get; init; }
    public string? LastStatus { get; init; }
    public string? LastStartTime { get; init; }
    public string? LastMessage { get; init; }

    public bool IsHealthy => Active && (string.IsNullOrEmpty(LastStatus) || LastStatus.Equals("succeeded", StringComparison.OrdinalIgnoreCase));
}

public sealed class SupabaseGatewayRouteStat
{
    public string Method { get; init; } = "GET";
    public string Path { get; init; } = "/";
    public long RequestCount { get; init; }
    public long ErrorCount { get; init; }
    public long ResponseBytes { get; init; }

    public string RouteLabel => $"{Method} {Path}";
    public string EgressFormatted => SupabaseAdminFormatter.FormatBytes(ResponseBytes);
}

public sealed class SupabaseGatewayErrorEvent
{
    public string Timestamp { get; init; } = string.Empty;
    public int StatusCode { get; init; }
    public string Method { get; init; } = string.Empty;
    public string Path { get; init; } = string.Empty;
    public string UserAgent { get; init; } = string.Empty;
    public string Message { get; init; } = string.Empty;
}

public sealed class SupabaseEdgeFunctionStat
{
    public string Id { get; init; } = string.Empty;
    public string Slug { get; init; } = string.Empty;
    public string Name { get; init; } = string.Empty;
    public string Status { get; init; } = "ACTIVE";
    public int Version { get; init; } = 1;
    public bool VerifyJwt { get; init; }
    public long Invocations24h { get; init; }
    public long Errors24h { get; init; }
    public double AvgExecutionMs { get; init; }
}

public sealed class SupabaseClientFootprint
{
    public string PlatformLabel { get; init; } = string.Empty;
    public long RequestCount24h { get; init; }
    public long EgressBytes24h { get; init; }
    public double ShareRatio { get; init; }

    public string SharePercentLabel => $"{ShareRatio * 100.0:F1}%";
    public string EgressFormatted => SupabaseAdminFormatter.FormatBytes(EgressBytes24h);
}

public sealed class SupabaseDailyEgressPoint
{
    public string DateLabel { get; init; } = string.Empty;
    public long RestBytes { get; init; }
    public long FunctionsBytes { get; init; }
    public long RealtimeBytes { get; init; }
    public long StorageBytes { get; init; }
    public long AuthBytes { get; init; }
    public long SupavisorBytes { get; init; }

    public long TotalBytes => RestBytes + FunctionsBytes + RealtimeBytes + StorageBytes + AuthBytes + SupavisorBytes;
    public string TotalFormatted => SupabaseAdminFormatter.FormatBytes(TotalBytes);
}

public sealed class SupabaseAdvisorNotice
{
    public string Name { get; init; } = string.Empty;
    public string Title { get; init; } = string.Empty;
    public string Level { get; init; } = "INFO";
    public string Category { get; init; } = "PERFORMANCE";
    public string Description { get; init; } = string.Empty;
    public string Remediation { get; init; } = string.Empty;
}

public sealed class SupabaseAdminSnapshot
{
    public const string DefaultProjectRef = "akkfouifxztnfwwiclwg";

    public long FetchedAtEpochMs { get; init; } = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
    public SupabaseProjectSummary Project { get; init; } = new();
    public IReadOnlyList<SupabaseProjectSummary> AvailableProjects { get; init; } = Array.Empty<SupabaseProjectSummary>();
    public string OrgName { get; init; } = "Organization";
    public string OrgPlan { get; init; } = "Free";
    public string ComputeTier { get; init; } = "Nano";

    // Quotas & Billing / Estimated Usage
    public bool HasExactBillingMetrics { get; init; }
    public string? BillingCyclePeriod { get; init; }
    public double EgressUsedGb { get; init; }
    public double EgressQuotaGb { get; init; } = 5.0;
    public double CachedEgressUsedGb { get; init; }
    public double CachedEgressQuotaGb { get; init; } = 5.0;

    // Database & Disk
    public long DbTotalBytes { get; init; }
    public long DbQuotaBytes { get; init; } = 500_000_000L;
    public long DbHeapBytes { get; init; }
    public long DbIndexBytes { get; init; }
    public int DiskSizeGb { get; init; } = 8;
    public string DiskType { get; init; } = "gp3";
    public int DiskIops { get; init; } = 3000;
    public int DiskThroughputMbps { get; init; } = 125;

    // Storage
    public long StorageTotalBytes { get; init; }
    public long StorageQuotaBytes { get; init; } = 1_000_000_000L;
    public int StorageObjectCount { get; init; }
    public int StorageBucketCount { get; init; }

    // Auth & Ecosystem
    public int MonthlyActiveUsers { get; init; }
    public int MauQuota { get; init; } = 50_000;
    public int ActiveSessionsCount { get; init; }
    public int PairedWatchesCount { get; init; }

    // Function Invocations & Realtime Peak
    public long FunctionInvocations { get; init; }
    public long FunctionInvocationsQuota { get; init; } = 500_000;
    public long RealtimeMessages { get; init; }
    public long RealtimeMessagesQuota { get; init; } = 2_000_000;
    public long RealtimePeakConnections { get; init; }
    public long RealtimePeakConnectionsQuota { get; init; } = 200;
    public double LogIngestionGb { get; init; }
    public double LogIngestionQuotaGb { get; init; } = 1.0;
    public double LogQueryGb { get; init; }
    public double LogQueryQuotaGb { get; init; } = 100.0;

    // Gateway 24h
    public long GatewayRequests24h { get; init; }
    public long Gateway2xx24h { get; init; }
    public long Gateway4xx24h { get; init; }
    public long Gateway5xx24h { get; init; }
    public long GatewayEgressBytes24h { get; init; }
    public long RestRequests24h { get; init; }
    public long AuthRequests24h { get; init; }
    public long StorageRequests24h { get; init; }
    public long RealtimeRequests24h { get; init; }

    // Realtime & WAL
    public int ActiveRealtimeSubscriptions { get; init; }
    public IReadOnlyDictionary<string, int> RealtimeSubscriptionsByTable { get; init; } = new Dictionary<string, int>();
    public double RealtimeListChangesCpuPercent { get; init; }
    public long RealtimeListChangesCalls { get; init; }

    // Detailed Collections
    public IReadOnlyList<SupabaseDailyEgressPoint> DailyEgressSeries { get; init; } = Array.Empty<SupabaseDailyEgressPoint>();
    public IReadOnlyList<SupabaseTableFootprint> TopTables { get; init; } = Array.Empty<SupabaseTableFootprint>();
    public IReadOnlyList<SupabaseSqlHotspot> TopSqlStatements { get; init; } = Array.Empty<SupabaseSqlHotspot>();
    public IReadOnlyList<SupabaseCronJobHealth> CronJobs { get; init; } = Array.Empty<SupabaseCronJobHealth>();
    public IReadOnlyList<SupabaseGatewayRouteStat> TopGatewayRoutes { get; init; } = Array.Empty<SupabaseGatewayRouteStat>();
    public IReadOnlyList<SupabaseGatewayErrorEvent> RecentGatewayErrors { get; init; } = Array.Empty<SupabaseGatewayErrorEvent>();
    public IReadOnlyList<SupabaseEdgeFunctionStat> EdgeFunctions { get; init; } = Array.Empty<SupabaseEdgeFunctionStat>();
    public IReadOnlyList<SupabaseClientFootprint> EcosystemClients { get; init; } = Array.Empty<SupabaseClientFootprint>();
    public IReadOnlyList<SupabaseAdvisorNotice> Advisors { get; init; } = Array.Empty<SupabaseAdvisorNotice>();

    public double DbUsagePercent => DbQuotaBytes > 0 ? Math.Min(100.0, (double)DbTotalBytes / DbQuotaBytes * 100.0) : 0.0;
    public double EgressUsagePercent => EgressQuotaGb > 0 ? Math.Min(100.0, EgressUsedGb / EgressQuotaGb * 100.0) : 0.0;
    public double StorageUsagePercent => StorageQuotaBytes > 0 ? Math.Min(100.0, (double)StorageTotalBytes / StorageQuotaBytes * 100.0) : 0.0;
    public double GatewayErrorRatePercent => GatewayRequests24h > 0
        ? (double)(Gateway4xx24h + Gateway5xx24h) / GatewayRequests24h * 100.0
        : 0.0;

    public string ToMarkdownReport()
    {
        var fetchedIso = DateTimeOffset.FromUnixTimeMilliseconds(FetchedAtEpochMs).ToString("yyyy-MM-ddTHH:mm:ssK", CultureInfo.InvariantCulture);
        var sb = new StringBuilder();
        sb.AppendLine($"# Supabase Cloud Forensic Telemetry — {Project.Name} (`{Project.Ref}`)");
        sb.AppendLine($"- **Generated**: {fetchedIso}");
        sb.AppendLine($"- **Organization / Plan**: {OrgName} (`{OrgPlan}`) · Compute `{ComputeTier}` · Region `{Project.Region}` · PG `{Project.PostgresVersion}`");
        sb.AppendLine($"- **Status**: `{Project.Status}`");
        sb.AppendLine();
        sb.AppendLine("## Executive Quotas");
        sb.AppendLine($"- **Database Size**: {SupabaseAdminFormatter.FormatBytes(DbTotalBytes)} / {SupabaseAdminFormatter.FormatBytes(DbQuotaBytes)} ({DbUsagePercent:F1}%) — Heap {SupabaseAdminFormatter.FormatBytes(DbHeapBytes)}, Indexes {SupabaseAdminFormatter.FormatBytes(DbIndexBytes)}");
        sb.AppendLine($"- **Unified Egress**: {EgressUsedGb:F3} GB / {EgressQuotaGb:F1} GB ({EgressUsagePercent:F1}%) {(HasExactBillingMetrics ? "[Exact Billing]" : "[Gateway Estimate]")}");
        sb.AppendLine($"- **Storage Size**: {SupabaseAdminFormatter.FormatBytes(StorageTotalBytes)} / {SupabaseAdminFormatter.FormatBytes(StorageQuotaBytes)} ({StorageObjectCount} objects in {StorageBucketCount} buckets)");
        sb.AppendLine($"- **Auth Footprint**: {MonthlyActiveUsers} MAU / {MauQuota} · {ActiveSessionsCount} active sessions · {PairedWatchesCount} paired watches");
        sb.AppendLine($"- **24h Gateway Traffic**: {GatewayRequests24h} reqs (`2xx`: {Gateway2xx24h}, `4xx`: {Gateway4xx24h}, `5xx`: {Gateway5xx24h}) · {SupabaseAdminFormatter.FormatBytes(GatewayEgressBytes24h)} response payload");
        sb.AppendLine($"- **Realtime**: {ActiveRealtimeSubscriptions} active subscriptions · `realtime.list_changes` CPU share {RealtimeListChangesCpuPercent:F1}% ({RealtimeListChangesCalls} calls)");
        sb.AppendLine();

        if (TopTables.Count > 0)
        {
            sb.AppendLine("## Top PostgreSQL Tables");
            sb.AppendLine("| Table | Total | Heap | Indexes | Live Rows | Dead Rows | Writes |");
            sb.AppendLine("|---|---:|---:|---:|---:|---:|---:|");
            foreach (var t in TopTables.Take(12))
            {
                var warn = t.HasIndexBloatWarning ? " ⚠️" : string.Empty;
                sb.AppendLine($"| `{t.QualifiedName}`{warn} | {t.TotalFormatted} | {t.HeapFormatted} | {t.IndexFormatted} | {t.LiveRows} | {t.DeadRows} | {t.WritesTotal} |");
            }
            sb.AppendLine();
        }

        if (TopGatewayRoutes.Count > 0)
        {
            sb.AppendLine("## Top 24h Gateway Endpoints");
            sb.AppendLine("| Endpoint | Requests | Errors | Egress |");
            sb.AppendLine("|---|---:|---:|---:|");
            foreach (var r in TopGatewayRoutes.Take(10))
            {
                sb.AppendLine($"| `{r.Method} {r.Path}` | {r.RequestCount} | {r.ErrorCount} | {r.EgressFormatted} |");
            }
            sb.AppendLine();
        }

        if (EdgeFunctions.Count > 0)
        {
            sb.AppendLine("## Edge Functions (24h)");
            foreach (var fn in EdgeFunctions)
            {
                sb.AppendLine($"- **`{fn.Slug}`** (v{fn.Version}, `{fn.Status}`): {fn.Invocations24h} calls, {fn.Errors24h} errors, avg {fn.AvgExecutionMs:F0} ms");
            }
            sb.AppendLine();
        }

        if (Advisors.Count > 0)
        {
            sb.AppendLine($"## Active Advisors ({Advisors.Count})");
            foreach (var a in Advisors.Take(10))
            {
                sb.AppendLine($"- **[{a.Category} / {a.Level}] {a.Title}**: {a.Description}");
            }
        }

        return sb.ToString();
    }
}

public static class SupabaseAdminFormatter
{
    public static string FormatBytes(long bytes)
    {
        if (bytes <= 0) return "0 B";
        const double kb = 1_000.0;
        const double mb = 1_000_000.0;
        const double gb = 1_000_000_000.0;
        return bytes switch
        {
            >= (long)gb => $"{bytes / gb:F2} GB",
            >= (long)mb => $"{bytes / mb:F1} MB",
            >= (long)kb => $"{bytes / kb:F1} KB",
            _ => $"{bytes} B"
        };
    }

    public static string FormatBillingCyclePeriod(long startEpochSeconds, long endEpochSeconds)
    {
        var start = DateTimeOffset.FromUnixTimeSeconds(startEpochSeconds).UtcDateTime;
        var end = DateTimeOffset.FromUnixTimeSeconds(endEpochSeconds).UtcDateTime;
        return $"{start:d MMM yyyy} - {end:d MMM yyyy}";
    }

    public static DateTime ComputeBillingCycleStartDate(long? startEpochSeconds, string? creationDateString, DateTime? referenceDate = null)
    {
        if (startEpochSeconds.HasValue && startEpochSeconds.Value > 0)
        {
            return DateTimeOffset.FromUnixTimeSeconds(startEpochSeconds.Value).UtcDateTime;
        }
        var refDate = referenceDate ?? DateTime.UtcNow;
        var anchorDay = 1;
        if (!string.IsNullOrWhiteSpace(creationDateString))
        {
            if (DateTime.TryParse(creationDateString, CultureInfo.InvariantCulture, DateTimeStyles.AdjustToUniversal, out var parsed))
            {
                anchorDay = parsed.Day;
            }
        }
        anchorDay = Math.Clamp(anchorDay, 1, 28);

        if (refDate.Day >= anchorDay)
        {
            return new DateTime(refDate.Year, refDate.Month, anchorDay, 0, 0, 0, DateTimeKind.Utc);
        }
        else
        {
            var prevMonth = refDate.AddMonths(-1);
            return new DateTime(prevMonth.Year, prevMonth.Month, Math.Min(anchorDay, DateTime.DaysInMonth(prevMonth.Year, prevMonth.Month)), 0, 0, 0, DateTimeKind.Utc);
        }
    }

    public static string ComputeBillingCyclePeriodFromCreation(string? dateString, DateTime? referenceDate = null)
    {
        var refDate = referenceDate ?? DateTime.UtcNow;
        var anchorDay = 1;
        if (!string.IsNullOrWhiteSpace(dateString))
        {
            if (DateTime.TryParse(dateString, CultureInfo.InvariantCulture, DateTimeStyles.AdjustToUniversal, out var parsed))
            {
                anchorDay = parsed.Day;
            }
        }
        anchorDay = Math.Clamp(anchorDay, 1, 28);

        DateTime cycleStart;
        if (refDate.Day >= anchorDay)
        {
            cycleStart = new DateTime(refDate.Year, refDate.Month, anchorDay, 0, 0, 0, DateTimeKind.Utc);
        }
        else
        {
            var prevMonth = refDate.AddMonths(-1);
            cycleStart = new DateTime(prevMonth.Year, prevMonth.Month, Math.Min(anchorDay, DateTime.DaysInMonth(prevMonth.Year, prevMonth.Month)), 0, 0, 0, DateTimeKind.Utc);
        }
        var cycleEnd = cycleStart.AddMonths(1);
        return $"{cycleStart:d MMM yyyy} - {cycleEnd:d MMM yyyy}";
    }
}
