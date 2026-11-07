package com.intellidream.daily.model

import kotlinx.serialization.Serializable
import java.time.Instant
import java.util.Locale

@Serializable
data class SupabaseAdminCredentials(
    val managementAccessToken: String? = null,
    val dashboardAccessToken: String? = null,
    val dashboardRefreshToken: String? = null,
    val adminIdentity: String? = null,
    val selectedProjectRef: String = "akkfouifxztnfwwiclwg",
    val selectedOrgSlug: String? = null,
    val requireBiometrics: Boolean = false,
    val connectedAtEpochMs: Long = System.currentTimeMillis()
) {
    val hasValidToken: Boolean
        get() = !managementAccessToken.isNullOrBlank() || !dashboardAccessToken.isNullOrBlank()

    val primaryManagementBearer: String?
        get() = managementAccessToken?.trim()?.takeIf { it.isNotEmpty() }
            ?: dashboardAccessToken?.trim()?.takeIf { it.isNotEmpty() }

    val primaryPlatformBearer: String?
        get() = dashboardAccessToken?.trim()?.takeIf { it.isNotEmpty() }
            ?: managementAccessToken?.trim()?.takeIf { it.isNotEmpty() }
}

@Serializable
data class SupabaseProjectSummary(
    val ref: String,
    val name: String,
    val organizationSlug: String,
    val region: String,
    val status: String,
    val postgresVersion: String = "17",
    val createdAt: String? = null
)

@Serializable
data class SupabaseServiceHealthItem(
    val name: String,
    val displayName: String,
    val status: String,
    val healthy: Boolean,
    val detail: String? = null
)

@Serializable
data class SupabaseDailyEgressPoint(
    val date: String,
    val restBytes: Long = 0L,
    val functionBytes: Long = 0L,
    val realtimeBytes: Long = 0L,
    val authBytes: Long = 0L,
    val storageBytes: Long = 0L,
    val supavisorBytes: Long = 0L
) {
    val totalBytes: Long
        get() = restBytes + functionBytes + realtimeBytes + authBytes + storageBytes + supavisorBytes
}

@Serializable
data class SupabaseApiCountPoint(
    val timestamp: String,
    val restRequests: Int = 0,
    val authRequests: Int = 0,
    val realtimeRequests: Int = 0,
    val storageRequests: Int = 0
) {
    val totalRequests: Int
        get() = restRequests + authRequests + realtimeRequests + storageRequests
}

@Serializable
data class SupabaseTopRouteStat(
    val method: String,
    val path: String,
    val requests24h: Int,
    val responseBytes24h: Long,
    val avgLatencyMs: Double,
    val errors4xx5xx: Int
)

@Serializable
data class SupabaseGatewayErrorItem(
    val id: String,
    val timestamp: String,
    val statusCode: Int,
    val method: String,
    val path: String,
    val userAgent: String,
    val message: String
)

@Serializable
data class SupabaseTableStat(
    val schema: String,
    val tableName: String,
    val dataBytes: Long,
    val indexBytes: Long,
    val totalBytes: Long,
    val liveRows: Long,
    val deadRows: Long,
    val totalWrites: Long,
    val lastAutovacuum: String? = null
) {
    val hasIndexBloatWarning: Boolean
        get() = indexBytes > 2_097_152L && indexBytes > maxOf(dataBytes * 3L, 1L)

    val bloatRatio: Double
        get() = if (dataBytes > 0L) indexBytes.toDouble() / dataBytes.toDouble() else if (indexBytes > 0L) 99.0 else 1.0
}

@Serializable
data class SupabaseSqlStatementStat(
    val id: String,
    val queryPreview: String,
    val calls: Long,
    val totalExecTimeMs: Double,
    val meanExecTimeMs: Double,
    val rowsReturned: Long
)

@Serializable
data class SupabaseCronJobRun(
    val id: String,
    val jobName: String,
    val schedule: String,
    val status: String,
    val startTime: String,
    val durationMs: Double? = null,
    val returnMessage: String? = null
) {
    val isSucceeded: Boolean
        get() = status.lowercase().contains("succeed")
}

@Serializable
data class SupabaseEdgeFunctionStat(
    val id: String,
    val slug: String,
    val name: String,
    val status: String,
    val version: Int,
    val verifyJwt: Boolean,
    val invocations24h: Int = 0,
    val errors24h: Int = 0,
    val avgExecutionMs: Double = 0.0,
    val maxExecutionMs: Double = 0.0
) {
    val successRatePercent: Double
        get() = if (invocations24h <= 0) 100.0 else (maxOf(0, invocations24h - errors24h).toDouble() * 100.0) / invocations24h.toDouble()
}

@Serializable
data class SupabaseAdvisorLint(
    val id: String,
    val category: String,
    val level: String,
    val title: String,
    val detail: String,
    val remediationUrl: String? = null
)

@Serializable
data class SupabaseFleetDeviceStat(
    val platformKey: String,
    val displayName: String,
    val requests24h: Int,
    val sharePercent: Double,
    val responseBytes24h: Long,
    val errors4xx24h: Int,
    val registeredSources: List<String> = emptyList()
)

@Serializable
data class SupabaseAdminSnapshot(
    val fetchedAtEpochMs: Long = System.currentTimeMillis(),
    val project: SupabaseProjectSummary,
    val availableProjects: List<SupabaseProjectSummary> = emptyList(),
    val orgName: String = "DayOne Cloud",
    val orgPlan: String = "free",
    val computeTier: String = "Micro (Shared)",
    val serviceHealth: List<SupabaseServiceHealthItem> = emptyList(),
    val resourceWarnings: List<String> = emptyList(),
    val isExactBillingUsageAvailable: Boolean = false,
    val billingCyclePeriod: String? = null,
    val egressUsedBytes: Long = 0L,
    val egressQuotaBytes: Long = 5_368_709_120L,
    val cachedEgressUsedBytes: Long = 0L,
    val egress24hBytes: Long = 0L,
    val dbSizeBytes: Long = 0L,
    val dbQuotaBytes: Long = 524_288_000L,
    val storageSizeBytes: Long = 0L,
    val storageQuotaBytes: Long = 1_073_741_824L,
    val functionInvocations: Long = 0L,
    val functionInvocationsQuota: Long = 500_000L,
    val realtimeMessages: Long = 0L,
    val realtimeMessagesQuota: Long = 2_000_000L,
    val realtimePeakConnections: Long = 0L,
    val realtimePeakConnectionsQuota: Long = 200L,
    val mauCount: Long = 0L,
    val mauQuota: Long = 50_000L,
    val logIngestionBytes: Long = 0L,
    val logIngestionQuotaBytes: Long = 1_073_741_824L,
    val logQueryBytes: Long = 0L,
    val logQueryQuotaBytes: Long = 107_374_182_400L,
    val logIngestionEvents: Long = 0L,
    val dailyEgress: List<SupabaseDailyEgressPoint> = emptyList(),
    val apiCounts24h: List<SupabaseApiCountPoint> = emptyList(),
    val logCountsBySource: Map<String, Int> = emptyMap(),
    val http2xxCount24h: Int = 0,
    val http4xxCount24h: Int = 0,
    val http5xxCount24h: Int = 0,
    val topRoutes24h: List<SupabaseTopRouteStat> = emptyList(),
    val recentErrors24h: List<SupabaseGatewayErrorItem> = emptyList(),
    val diskUsedBytes: Long = 0L,
    val diskTotalBytes: Long = 8_589_934_592L,
    val diskIops: Int = 3000,
    val diskThroughputMibps: Int = 125,
    val heapDataBytes: Long = 0L,
    val indexTotalBytes: Long = 0L,
    val activeDbConnections: Int = 0,
    val cacheHitRatioPercent: Double = 99.0,
    val tables: List<SupabaseTableStat> = emptyList(),
    val topSqlStatements: List<SupabaseSqlStatementStat> = emptyList(),
    val cronJobs: List<SupabaseCronJobRun> = emptyList(),
    val edgeFunctions: List<SupabaseEdgeFunctionStat> = emptyList(),
    val realtimeActiveSubscriptions: Int = 0,
    val realtimeSubscriptionsByTable: Map<String, Int> = emptyMap(),
    val realtimeWalListChangesCalls: Long = 0L,
    val realtimeWalCpuSharePercent: Double = 0.0,
    val totalUsersCount: Long = 0L,
    val activeAuthSessionsCount: Long = 0L,
    val refreshTokenWritesCumulative: Long = 0L,
    val pairedWatchesCount: Int = 0,
    val fleetDevices: List<SupabaseFleetDeviceStat> = emptyList(),
    val performanceLints: List<SupabaseAdvisorLint> = emptyList(),
    val securityLints: List<SupabaseAdvisorLint> = emptyList()
) {
    val egressQuotaPercent: Double
        get() = if (egressQuotaBytes > 0L) minOf(999.0, egressUsedBytes.toDouble() * 100.0 / egressQuotaBytes.toDouble()) else 0.0

    val egressCycleUsedBytes: Long
        get() = egressUsedBytes

    val egressCycleQuotaBytes: Long
        get() = egressQuotaBytes

    val egressCycleQuotaPercent: Double
        get() = egressQuotaPercent

    val egress24hQuotaPercent: Double
        get() = if (egressQuotaBytes > 0L) {
            val dailyBudget = egressQuotaBytes.toDouble() / 30.0
            minOf(999.0, (egress24hBytes.toDouble() * 100.0) / maxOf(dailyBudget, 1.0))
        } else 0.0

    val dbQuotaPercent: Double
        get() = if (dbQuotaBytes > 0L) minOf(999.0, dbSizeBytes.toDouble() * 100.0 / dbQuotaBytes.toDouble()) else 0.0

    val totalHttpRequests24h: Int
        get() = http2xxCount24h + http4xxCount24h + http5xxCount24h

    val errorRate24hPercent: Double
        get() {
            val total = totalHttpRequests24h
            return if (total > 0) ((http4xxCount24h + http5xxCount24h).toDouble() * 100.0) / total.toDouble() else 0.0
        }

    fun toMarkdownReport(): String {
        val ts = Instant.ofEpochMilli(fetchedAtEpochMs).toString()
        val sb = StringBuilder()
        sb.appendLine("# Supabase Cloud Forensic Telemetry Report — ${project.name} (`${project.ref}`)")
        sb.appendLine()
        sb.appendLine("- **Generated At:** `$ts`")
        sb.appendLine("- **Organization & Plan:** `$orgName` (`${orgPlan.uppercase()}`) · **Compute:** `$computeTier` · **Region:** `${project.region}`")
        sb.appendLine("- **PostgreSQL Engine:** `${project.postgresVersion}` · **Cache Hit Ratio:** `${String.format(Locale.US, "%.2f%%", cacheHitRatioPercent)}`")
        sb.appendLine()
        sb.appendLine("## 1. Executive Quota Summary")
        sb.appendLine()
        sb.appendLine("| Resource Metric | Current Usage | Plan Quota | Utilization |")
        sb.appendLine("| :--- | :--- | :--- | :--- |")
        sb.appendLine("| **Unified Egress (Cycle)** | ${formatBytes(egressCycleUsedBytes)} | ${formatBytes(egressCycleQuotaBytes)} | **${String.format(Locale.US, "%.1f%%", egressCycleQuotaPercent)}** |")
        sb.appendLine("| **24h Gateway Egress** | ${formatBytes(egress24hBytes)} | ${totalHttpRequests24h} reqs | **${String.format(Locale.US, "%.1f%%", egress24hQuotaPercent)}** (vs daily share) |")
        sb.appendLine("| **Database Size** | ${formatBytes(dbSizeBytes)} | ${formatBytes(dbQuotaBytes)} | **${String.format(Locale.US, "%.1f%%", dbQuotaPercent)}** |")
        sb.appendLine("| **Storage Size** | ${formatBytes(storageSizeBytes)} | ${formatBytes(storageQuotaBytes)} | ${if (storageQuotaBytes > 0) String.format(Locale.US, "%.1f%%", storageSizeBytes * 100.0 / storageQuotaBytes) else "—"} |")
        sb.appendLine("| **Edge Function Invocations** | $functionInvocations | $functionInvocationsQuota | — |")
        sb.appendLine("| **Realtime Active / Peak** | $realtimeActiveSubscriptions / $realtimePeakConnections | $realtimePeakConnectionsQuota | — |")
        sb.appendLine("| **Monthly Active Users (MAU)** | $mauCount | $mauQuota | — |")
        sb.appendLine()
        sb.appendLine("## 2. PostgreSQL Table Storage & Index Bloat")
        sb.appendLine()
        sb.appendLine("| Schema.Table | Data Size | Index Size | Total Size | Live Rows | Status |")
        sb.appendLine("| :--- | :--- | :--- | :--- | :--- | :--- |")
        tables.take(15).forEach { t ->
            val status = if (t.hasIndexBloatWarning) "⚠️ Bloat (${String.format(Locale.US, "%.1fx", t.bloatRatio)})" else "OK"
            sb.appendLine("| `${t.schema}.${t.tableName}` | ${formatBytes(t.dataBytes)} | ${formatBytes(t.indexBytes)} | **${formatBytes(t.totalBytes)}** | ${t.liveRows} | $status |")
        }
        sb.appendLine()
        if (topRoutes24h.isNotEmpty()) {
            sb.appendLine("## 3. Top 24h HTTP Gateway Routes")
            sb.appendLine()
            sb.appendLine("| Method & Path | Requests | Response Sum | Avg Latency | 4xx/5xx |")
            sb.appendLine("| :--- | :--- | :--- | :--- | :--- |")
            topRoutes24h.take(10).forEach { r ->
                sb.appendLine("| `${r.method} ${r.path}` | ${r.requests24h} | ${formatBytes(r.responseBytes24h)} | ${String.format(Locale.US, "%.1f ms", r.avgLatencyMs)} | ${r.errors4xx5xx} |")
            }
            sb.appendLine()
        }
        return sb.toString()
    }

    companion object {
        fun formatBytes(bytes: Long): String {
            val b = maxOf(0L, bytes).toDouble()
            return when {
                b >= 1_073_741_824.0 -> String.format(Locale.US, "%.2f GB", b / 1_073_741_824.0)
                b >= 1_048_576.0 -> String.format(Locale.US, "%.1f MB", b / 1_048_576.0)
                b >= 1024.0 -> String.format(Locale.US, "%.1f KB", b / 1024.0)
                else -> "${b.toLong()} B"
            }
        }

        fun formatBillingCyclePeriod(startEpochSeconds: Long, endEpochSeconds: Long): String {
            val fmt = java.time.format.DateTimeFormatter.ofPattern("d MMM yyyy", Locale.US).withZone(java.time.ZoneOffset.UTC)
            val s = fmt.format(java.time.Instant.ofEpochSecond(startEpochSeconds))
            val e = fmt.format(java.time.Instant.ofEpochSecond(endEpochSeconds))
            return "$s - $e"
        }

        fun computeBillingCyclePeriodFromCreation(dateString: String, referenceTimeMs: Long = System.currentTimeMillis()): String {
            var anchorDay = 19
            val clean = dateString.trim()
            if (clean.length >= 10) {
                val parts = clean.substring(0, 10).split("-")
                if (parts.size == 3) {
                    parts[2].toIntOrNull()?.let { d ->
                        if (d in 1..31) anchorDay = d
                    }
                }
            }

            val now = java.time.ZonedDateTime.ofInstant(java.time.Instant.ofEpochMilli(referenceTimeMs), java.time.ZoneOffset.UTC)
            val currentYear = now.year
            val currentMonth = now.monthValue
            val currentDay = now.dayOfMonth

            var startYear = currentYear
            var startMonth = currentMonth
            if (currentDay < anchorDay) {
                startMonth -= 1
                if (startMonth < 1) {
                    startMonth = 12
                    startYear -= 1
                }
            }

            var endYear = startYear
            var endMonth = startMonth + 1
            if (endMonth > 12) {
                endMonth = 1
                endYear += 1
            }

            val startDate = java.time.LocalDate.of(startYear, startMonth, minOf(anchorDay, java.time.YearMonth.of(startYear, startMonth).lengthOfMonth()))
            val endDate = java.time.LocalDate.of(endYear, endMonth, minOf(anchorDay, java.time.YearMonth.of(endYear, endMonth).lengthOfMonth()))
            val fmt = java.time.format.DateTimeFormatter.ofPattern("d MMM yyyy", Locale.US)
            return "${startDate.format(fmt)} - ${endDate.format(fmt)}"
        }
    }
}
