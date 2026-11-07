import Foundation

// MARK: - Credentials & Session Models

/// Device-local credentials for Supabase Admin Mode.
/// Strictly persisted in device-only storage (Keychain ThisDeviceOnly on iOS, sandboxed GroupDefaults on macOS)
/// and NEVER synchronized to cloud AppSettings or user_settings tables.
public struct SupabaseAdminCredentials: Codable, Sendable, Equatable {
    public var managementAccessToken: String?
    public var dashboardAccessToken: String?
    public var dashboardRefreshToken: String?
    public var adminIdentity: String?
    public var selectedProjectRef: String
    public var selectedOrgSlug: String?
    public var requireBiometrics: Bool
    public var connectedAt: Date

    public init(
        managementAccessToken: String? = nil,
        dashboardAccessToken: String? = nil,
        dashboardRefreshToken: String? = nil,
        adminIdentity: String? = nil,
        selectedProjectRef: String = "akkfouifxztnfwwiclwg",
        selectedOrgSlug: String? = nil,
        requireBiometrics: Bool = false,
        connectedAt: Date = Date()
    ) {
        self.managementAccessToken = managementAccessToken
        self.dashboardAccessToken = dashboardAccessToken
        self.dashboardRefreshToken = dashboardRefreshToken
        self.adminIdentity = adminIdentity
        self.selectedProjectRef = selectedProjectRef
        self.selectedOrgSlug = selectedOrgSlug
        self.requireBiometrics = requireBiometrics
        self.connectedAt = connectedAt
    }

    public var hasValidToken: Bool {
        let mgmt = managementAccessToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let dash = dashboardAccessToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !mgmt.isEmpty || !dash.isEmpty
    }

    /// Primary bearer token for `/v1/` endpoints (prefers durable `sbp_...` token, falls back to dashboard token).
    public var primaryManagementBearer: String? {
        if let mgmt = managementAccessToken?.trimmingCharacters(in: .whitespacesAndNewlines), !mgmt.isEmpty {
            return mgmt
        }
        if let dash = dashboardAccessToken?.trimmingCharacters(in: .whitespacesAndNewlines), !dash.isEmpty {
            return dash
        }
        return nil
    }

    /// Primary bearer token for `/platform/` billing/usage endpoints (prefers GoTrue dashboard session token, falls back to management PAT).
    public var primaryPlatformBearer: String? {
        if let dash = dashboardAccessToken?.trimmingCharacters(in: .whitespacesAndNewlines), !dash.isEmpty {
            return dash
        }
        if let mgmt = managementAccessToken?.trimmingCharacters(in: .whitespacesAndNewlines), !mgmt.isEmpty {
            return mgmt
        }
        return nil
    }
}

// MARK: - Project & Service Health

public struct SupabaseProjectSummary: Codable, Sendable, Equatable, Identifiable {
    public var id: String { ref }
    public let ref: String
    public let name: String
    public let organizationSlug: String
    public let region: String
    public let status: String
    public let postgresVersion: String
    public let createdAt: String?

    public init(
        ref: String,
        name: String,
        organizationSlug: String,
        region: String,
        status: String,
        postgresVersion: String,
        createdAt: String? = nil
    ) {
        self.ref = ref
        self.name = name
        self.organizationSlug = organizationSlug
        self.region = region
        self.status = status
        self.postgresVersion = postgresVersion
        self.createdAt = createdAt
    }
}

public struct SupabaseServiceHealthItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let displayName: String
    public let status: String
    public let healthy: Bool
    public let detail: String?

    public init(name: String, displayName: String, status: String, healthy: Bool, detail: String? = nil) {
        self.name = name
        self.displayName = displayName
        self.status = status
        self.healthy = healthy
        self.detail = detail
    }
}

// MARK: - Usage, Quotas & Egress Time-Series

public struct SupabaseDailyEgressPoint: Codable, Sendable, Equatable, Identifiable {
    public var id: String { date }
    public let date: String // YYYY-MM-DD
    public let restBytes: Int64
    public let functionBytes: Int64
    public let realtimeBytes: Int64
    public let authBytes: Int64
    public let storageBytes: Int64
    public let supavisorBytes: Int64

    public var totalBytes: Int64 {
        restBytes + functionBytes + realtimeBytes + authBytes + storageBytes + supavisorBytes
    }

    public init(
        date: String,
        restBytes: Int64,
        functionBytes: Int64,
        realtimeBytes: Int64,
        authBytes: Int64,
        storageBytes: Int64,
        supavisorBytes: Int64
    ) {
        self.date = date
        self.restBytes = restBytes
        self.functionBytes = functionBytes
        self.realtimeBytes = realtimeBytes
        self.authBytes = authBytes
        self.storageBytes = storageBytes
        self.supavisorBytes = supavisorBytes
    }
}

public struct SupabaseApiCountPoint: Codable, Sendable, Equatable, Identifiable {
    public var id: String { timestamp }
    public let timestamp: String
    public let restRequests: Int
    public let authRequests: Int
    public let realtimeRequests: Int
    public let storageRequests: Int

    public var totalRequests: Int {
        restRequests + authRequests + realtimeRequests + storageRequests
    }

    public init(
        timestamp: String,
        restRequests: Int,
        authRequests: Int,
        realtimeRequests: Int,
        storageRequests: Int
    ) {
        self.timestamp = timestamp
        self.restRequests = restRequests
        self.authRequests = authRequests
        self.realtimeRequests = realtimeRequests
        self.storageRequests = storageRequests
    }
}

// MARK: - ClickHouse Logs & Gateway Forensics

public struct SupabaseTopRouteStat: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(method):\(path)" }
    public let method: String
    public let path: String
    public let requests24h: Int
    public let responseBytes24h: Int64
    public let avgLatencyMs: Double
    public let errors4xx5xx: Int

    public init(
        method: String,
        path: String,
        requests24h: Int,
        responseBytes24h: Int64,
        avgLatencyMs: Double,
        errors4xx5xx: Int
    ) {
        self.method = method
        self.path = path
        self.requests24h = requests24h
        self.responseBytes24h = responseBytes24h
        self.avgLatencyMs = avgLatencyMs
        self.errors4xx5xx = errors4xx5xx
    }
}

public struct SupabaseGatewayErrorItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let timestamp: String
    public let statusCode: Int
    public let method: String
    public let path: String
    public let userAgent: String
    public let message: String

    public init(
        id: String,
        timestamp: String,
        statusCode: Int,
        method: String,
        path: String,
        userAgent: String,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.statusCode = statusCode
        self.method = method
        self.path = path
        self.userAgent = userAgent
        self.message = message
    }
}

// MARK: - PostgreSQL Storage, Bloat, SQL & Cron

public struct SupabaseTableStat: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(schema).\(tableName)" }
    public let schema: String
    public let tableName: String
    public let dataBytes: Int64
    public let indexBytes: Int64
    public let totalBytes: Int64
    public let liveRows: Int64
    public let deadRows: Int64
    public let totalWrites: Int64
    public let lastAutovacuum: String?

    /// Flags disproportionate B-tree index bloat (e.g. index > 3x heap and > 2 MB).
    public var hasIndexBloatWarning: Bool {
        indexBytes > 2_097_152 && indexBytes > max(dataBytes * 3, 1)
    }

    public var bloatRatio: Double {
        guard dataBytes > 0 else { return indexBytes > 0 ? 99.0 : 1.0 }
        return Double(indexBytes) / Double(dataBytes)
    }

    public init(
        schema: String,
        tableName: String,
        dataBytes: Int64,
        indexBytes: Int64,
        totalBytes: Int64,
        liveRows: Int64,
        deadRows: Int64,
        totalWrites: Int64,
        lastAutovacuum: String? = nil
    ) {
        self.schema = schema
        self.tableName = tableName
        self.dataBytes = dataBytes
        self.indexBytes = indexBytes
        self.totalBytes = totalBytes
        self.liveRows = liveRows
        self.deadRows = deadRows
        self.totalWrites = totalWrites
        self.lastAutovacuum = lastAutovacuum
    }
}

public struct SupabaseSqlStatementStat: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let queryPreview: String
    public let calls: Int64
    public let totalExecTimeMs: Double
    public let meanExecTimeMs: Double
    public let rowsReturned: Int64

    public init(
        id: String,
        queryPreview: String,
        calls: Int64,
        totalExecTimeMs: Double,
        meanExecTimeMs: Double,
        rowsReturned: Int64
    ) {
        self.id = id
        self.queryPreview = queryPreview
        self.calls = calls
        self.totalExecTimeMs = totalExecTimeMs
        self.meanExecTimeMs = meanExecTimeMs
        self.rowsReturned = rowsReturned
    }
}

public struct SupabaseCronJobRun: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let jobName: String
    public let schedule: String
    public let status: String
    public let startTime: String
    public let durationMs: Double?
    public let returnMessage: String?

    public var isSucceeded: Bool {
        status.lowercased().contains("succeed")
    }

    public init(
        id: String,
        jobName: String,
        schedule: String,
        status: String,
        startTime: String,
        durationMs: Double? = nil,
        returnMessage: String? = nil
    ) {
        self.id = id
        self.jobName = jobName
        self.schedule = schedule
        self.status = status
        self.startTime = startTime
        self.durationMs = durationMs
        self.returnMessage = returnMessage
    }
}

// MARK: - Edge Functions, Advisors & Ecosystem Fleet

public struct SupabaseEdgeFunctionStat: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let slug: String
    public let name: String
    public let status: String
    public let version: Int
    public let verifyJwt: Bool
    public let invocations24h: Int
    public let errors24h: Int
    public let avgExecutionMs: Double
    public let maxExecutionMs: Double

    public var successRatePercent: Double {
        guard invocations24h > 0 else { return 100.0 }
        let ok = max(0, invocations24h - errors24h)
        return (Double(ok) / Double(invocations24h)) * 100.0
    }

    public init(
        id: String,
        slug: String,
        name: String,
        status: String,
        version: Int,
        verifyJwt: Bool,
        invocations24h: Int = 0,
        errors24h: Int = 0,
        avgExecutionMs: Double = 0,
        maxExecutionMs: Double = 0
    ) {
        self.id = id
        self.slug = slug
        self.name = name
        self.status = status
        self.version = version
        self.verifyJwt = verifyJwt
        self.invocations24h = invocations24h
        self.errors24h = errors24h
        self.avgExecutionMs = avgExecutionMs
        self.maxExecutionMs = maxExecutionMs
    }
}

public struct SupabaseAdvisorLint: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let category: String // "PERFORMANCE" | "SECURITY"
    public let level: String    // "ERROR" | "WARN" | "INFO"
    public let title: String
    public let detail: String
    public let remediationUrl: String?

    public init(
        id: String,
        category: String,
        level: String,
        title: String,
        detail: String,
        remediationUrl: String? = nil
    ) {
        self.id = id
        self.category = category
        self.level = level
        self.title = title
        self.detail = detail
        self.remediationUrl = remediationUrl
    }
}

public struct SupabaseFleetDeviceStat: Codable, Sendable, Equatable, Identifiable {
    public var id: String { platformKey }
    public let platformKey: String
    public let displayName: String
    public let sfSymbol: String
    public let requests24h: Int
    public let sharePercent: Double
    public let responseBytes24h: Int64
    public let errors4xx24h: Int
    public let registeredSources: [String]

    public init(
        platformKey: String,
        displayName: String,
        sfSymbol: String,
        requests24h: Int,
        sharePercent: Double,
        responseBytes24h: Int64,
        errors4xx24h: Int,
        registeredSources: [String] = []
    ) {
        self.platformKey = platformKey
        self.displayName = displayName
        self.sfSymbol = sfSymbol
        self.requests24h = requests24h
        self.sharePercent = sharePercent
        self.responseBytes24h = responseBytes24h
        self.errors4xx24h = errors4xx24h
        self.registeredSources = registeredSources
    }
}

// MARK: - Canonical Snapshot

public struct SupabaseAdminSnapshot: Codable, Sendable, Equatable {
    public var fetchedAt: Date
    public var project: SupabaseProjectSummary
    public var availableProjects: [SupabaseProjectSummary]
    public var orgName: String
    public var orgPlan: String // "free", "pro", "team", "enterprise"
    public var computeTier: String

    // Health & Resource Warnings
    public var serviceHealth: [SupabaseServiceHealthItem]
    public var resourceWarnings: [String]

    // Billing & Quotas
    public var isExactBillingUsageAvailable: Bool
    public var billingCyclePeriod: String?
    public var egressUsedBytes: Int64
    public var egressQuotaBytes: Int64
    public var cachedEgressUsedBytes: Int64
    public var egress24hBytes: Int64
    public var dbSizeBytes: Int64
    public var dbQuotaBytes: Int64
    public var storageSizeBytes: Int64
    public var storageQuotaBytes: Int64
    public var functionInvocations: Int64
    public var functionInvocationsQuota: Int64
    public var realtimeMessages: Int64
    public var realtimeMessagesQuota: Int64
    public var realtimePeakConnections: Int64
    public var realtimePeakConnectionsQuota: Int64
    public var mauCount: Int64
    public var mauQuota: Int64
    public var logIngestionBytes: Int64
    public var logIngestionQuotaBytes: Int64
    public var logQueryBytes: Int64
    public var logQueryQuotaBytes: Int64
    public var logIngestionEvents: Int64

    // Time-Series Charts
    public var dailyEgress: [SupabaseDailyEgressPoint]
    public var apiCounts24h: [SupabaseApiCountPoint]

    // Gateway & Logs (24h ClickHouse)
    public var logCountsBySource: [String: Int]
    public var http2xxCount24h: Int
    public var http4xxCount24h: Int
    public var http5xxCount24h: Int
    public var topRoutes24h: [SupabaseTopRouteStat]
    public var recentErrors24h: [SupabaseGatewayErrorItem]

    // Database & Disk Forensics
    public var diskUsedBytes: Int64
    public var diskTotalBytes: Int64
    public var diskIops: Int
    public var diskThroughputMibps: Int
    public var heapDataBytes: Int64
    public var indexTotalBytes: Int64
    public var activeDbConnections: Int
    public var cacheHitRatioPercent: Double
    public var tables: [SupabaseTableStat]
    public var topSqlStatements: [SupabaseSqlStatementStat]
    public var cronJobs: [SupabaseCronJobRun]

    // Edge Functions & Realtime
    public var edgeFunctions: [SupabaseEdgeFunctionStat]
    public var realtimeActiveSubscriptions: Int
    public var realtimeSubscriptionsByTable: [String: Int]
    public var realtimeWalListChangesCalls: Int64
    public var realtimeWalCpuSharePercent: Double

    // Auth & Ecosystem Fleet
    public var totalUsersCount: Int64
    public var activeAuthSessionsCount: Int64
    public var refreshTokenWritesCumulative: Int64
    public var pairedWatchesCount: Int
    public var fleetDevices: [SupabaseFleetDeviceStat]

    // Advisors
    public var performanceLints: [SupabaseAdvisorLint]
    public var securityLints: [SupabaseAdvisorLint]

    public init(
        fetchedAt: Date = Date(),
        project: SupabaseProjectSummary,
        availableProjects: [SupabaseProjectSummary] = [],
        orgName: String = "DayOne Cloud",
        orgPlan: String = "free",
        computeTier: String = "Micro (Shared)",
        serviceHealth: [SupabaseServiceHealthItem] = [],
        resourceWarnings: [String] = [],
        isExactBillingUsageAvailable: Bool = false,
        billingCyclePeriod: String? = nil,
        egressUsedBytes: Int64 = 0,
        egressQuotaBytes: Int64 = 5_000_000_000, // 5 GB default Free (SI decimal matching Supabase Portal)
        cachedEgressUsedBytes: Int64 = 0,
        egress24hBytes: Int64 = 0,
        dbSizeBytes: Int64 = 0,
        dbQuotaBytes: Int64 = 500_000_000, // 0.5 GB (500 MB) default Free
        storageSizeBytes: Int64 = 0,
        storageQuotaBytes: Int64 = 1_000_000_000, // 1 GB default Free
        functionInvocations: Int64 = 0,
        functionInvocationsQuota: Int64 = 500_000,
        realtimeMessages: Int64 = 0,
        realtimeMessagesQuota: Int64 = 2_000_000,
        realtimePeakConnections: Int64 = 0,
        realtimePeakConnectionsQuota: Int64 = 200,
        mauCount: Int64 = 0,
        mauQuota: Int64 = 50_000,
        logIngestionBytes: Int64 = 0,
        logIngestionQuotaBytes: Int64 = 1_000_000_000, // 1 GB default Free
        logQueryBytes: Int64 = 0,
        logQueryQuotaBytes: Int64 = 100_000_000_000, // 100 GB default Free
        logIngestionEvents: Int64 = 0,
        dailyEgress: [SupabaseDailyEgressPoint] = [],
        apiCounts24h: [SupabaseApiCountPoint] = [],
        logCountsBySource: [String: Int] = [:],
        http2xxCount24h: Int = 0,
        http4xxCount24h: Int = 0,
        http5xxCount24h: Int = 0,
        topRoutes24h: [SupabaseTopRouteStat] = [],
        recentErrors24h: [SupabaseGatewayErrorItem] = [],
        diskUsedBytes: Int64 = 0,
        diskTotalBytes: Int64 = 0,
        diskIops: Int = 3000,
        diskThroughputMibps: Int = 125,
        heapDataBytes: Int64 = 0,
        indexTotalBytes: Int64 = 0,
        activeDbConnections: Int = 0,
        cacheHitRatioPercent: Double = 99.0,
        tables: [SupabaseTableStat] = [],
        topSqlStatements: [SupabaseSqlStatementStat] = [],
        cronJobs: [SupabaseCronJobRun] = [],
        edgeFunctions: [SupabaseEdgeFunctionStat] = [],
        realtimeActiveSubscriptions: Int = 0,
        realtimeSubscriptionsByTable: [String: Int] = [:],
        realtimeWalListChangesCalls: Int64 = 0,
        realtimeWalCpuSharePercent: Double = 0,
        totalUsersCount: Int64 = 0,
        activeAuthSessionsCount: Int64 = 0,
        refreshTokenWritesCumulative: Int64 = 0,
        pairedWatchesCount: Int = 0,
        fleetDevices: [SupabaseFleetDeviceStat] = [],
        performanceLints: [SupabaseAdvisorLint] = [],
        securityLints: [SupabaseAdvisorLint] = []
    ) {
        self.fetchedAt = fetchedAt
        self.project = project
        self.availableProjects = availableProjects
        self.orgName = orgName
        self.orgPlan = orgPlan
        self.computeTier = computeTier
        self.serviceHealth = serviceHealth
        self.resourceWarnings = resourceWarnings
        self.isExactBillingUsageAvailable = isExactBillingUsageAvailable
        self.billingCyclePeriod = billingCyclePeriod
        self.egressUsedBytes = egressUsedBytes
        self.egressQuotaBytes = egressQuotaBytes
        self.cachedEgressUsedBytes = cachedEgressUsedBytes
        self.egress24hBytes = egress24hBytes
        self.dbSizeBytes = dbSizeBytes
        self.dbQuotaBytes = dbQuotaBytes
        self.storageSizeBytes = storageSizeBytes
        self.storageQuotaBytes = storageQuotaBytes
        self.functionInvocations = functionInvocations
        self.functionInvocationsQuota = functionInvocationsQuota
        self.realtimeMessages = realtimeMessages
        self.realtimeMessagesQuota = realtimeMessagesQuota
        self.realtimePeakConnections = realtimePeakConnections
        self.realtimePeakConnectionsQuota = realtimePeakConnectionsQuota
        self.mauCount = mauCount
        self.mauQuota = mauQuota
        self.logIngestionBytes = logIngestionBytes
        self.logIngestionQuotaBytes = logIngestionQuotaBytes
        self.logQueryBytes = logQueryBytes
        self.logQueryQuotaBytes = logQueryQuotaBytes
        self.logIngestionEvents = logIngestionEvents
        self.dailyEgress = dailyEgress
        self.apiCounts24h = apiCounts24h
        self.logCountsBySource = logCountsBySource
        self.http2xxCount24h = http2xxCount24h
        self.http4xxCount24h = http4xxCount24h
        self.http5xxCount24h = http5xxCount24h
        self.topRoutes24h = topRoutes24h
        self.recentErrors24h = recentErrors24h
        self.diskUsedBytes = diskUsedBytes
        self.diskTotalBytes = diskTotalBytes
        self.diskIops = diskIops
        self.diskThroughputMibps = diskThroughputMibps
        self.heapDataBytes = heapDataBytes
        self.indexTotalBytes = indexTotalBytes
        self.activeDbConnections = activeDbConnections
        self.cacheHitRatioPercent = cacheHitRatioPercent
        self.tables = tables
        self.topSqlStatements = topSqlStatements
        self.cronJobs = cronJobs
        self.edgeFunctions = edgeFunctions
        self.realtimeActiveSubscriptions = realtimeActiveSubscriptions
        self.realtimeSubscriptionsByTable = realtimeSubscriptionsByTable
        self.realtimeWalListChangesCalls = realtimeWalListChangesCalls
        self.realtimeWalCpuSharePercent = realtimeWalCpuSharePercent
        self.totalUsersCount = totalUsersCount
        self.activeAuthSessionsCount = activeAuthSessionsCount
        self.refreshTokenWritesCumulative = refreshTokenWritesCumulative
        self.pairedWatchesCount = pairedWatchesCount
        self.fleetDevices = fleetDevices
        self.performanceLints = performanceLints
        self.securityLints = securityLints
    }

    // MARK: - Computed Helpers & Formatters

    public static func formatBytes(_ bytes: Int64) -> String {
        let absBytes = Double(max(0, bytes))
        if absBytes >= 1_000_000_000 {
            return String(format: "%.2f GB", absBytes / 1_000_000_000.0)
        } else if absBytes >= 1_000_000 {
            return String(format: "%.1f MB", absBytes / 1_000_000.0)
        } else if absBytes >= 1_000 {
            return String(format: "%.1f KB", absBytes / 1_000.0)
        } else {
            return "\(Int(absBytes)) B"
        }
    }

    public static func formatGigabytesPrecise(_ bytes: Int64, decimals: Int = 3) -> String {
        let gb = Double(max(0, bytes)) / 1_000_000_000.0
        return String(format: "%.\(decimals)f GB", gb)
    }

    public static func formatBillingCyclePeriod(startEpochSeconds: Int64, endEpochSeconds: Int64) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "d MMM yyyy"
        df.timeZone = TimeZone(secondsFromGMT: 0)
        let startDate = Date(timeIntervalSince1970: TimeInterval(startEpochSeconds))
        let endDate = Date(timeIntervalSince1970: TimeInterval(endEpochSeconds))
        return "\(df.string(from: startDate)) - \(df.string(from: endDate))"
    }

    public static func computeBillingCycleStartDate(
        startEpochSeconds: Int64? = nil,
        creationDateString: String? = nil,
        referenceDate: Date = Date()
    ) -> Date {
        if let s = startEpochSeconds, s > 0 {
            return Date(timeIntervalSince1970: TimeInterval(s))
        }
        var anchorDay = 1
        if let clean = creationDateString?.trimmingCharacters(in: .whitespacesAndNewlines), clean.count >= 10 {
            let parts = clean.prefix(10).split(separator: "-")
            if parts.count == 3, let day = Int(parts[2]), day >= 1 && day <= 31 {
                anchorDay = day
            }
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = referenceDate
        let currentYear = cal.component(.year, from: now)
        let currentMonth = cal.component(.month, from: now)
        let currentDay = cal.component(.day, from: now)

        var startYear = currentYear
        var startMonth = currentMonth
        if currentDay < anchorDay {
            startMonth -= 1
            if startMonth < 1 {
                startMonth = 12
                startYear -= 1
            }
        }
        var startComp = DateComponents()
        startComp.year = startYear
        startComp.month = startMonth
        startComp.day = anchorDay
        startComp.hour = 0
        startComp.minute = 0
        startComp.second = 0

        return cal.date(from: startComp) ?? now.addingTimeInterval(-30 * 86400)
    }

    public static func computeBillingCyclePeriodFromCreation(dateString: String, referenceDate: Date = Date()) -> String {
        var anchorDay = 1
        let clean = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.count >= 10 {
            let parts = clean.prefix(10).split(separator: "-")
            if parts.count == 3, let day = Int(parts[2]), day >= 1 && day <= 31 {
                anchorDay = day
            }
        }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!

        let now = referenceDate
        let currentYear = cal.component(.year, from: now)
        let currentMonth = cal.component(.month, from: now)
        let currentDay = cal.component(.day, from: now)

        var startYear = currentYear
        var startMonth = currentMonth
        if currentDay < anchorDay {
            startMonth -= 1
            if startMonth < 1 {
                startMonth = 12
                startYear -= 1
            }
        }

        var endYear = startYear
        var endMonth = startMonth + 1
        if endMonth > 12 {
            endMonth = 1
            endYear += 1
        }

        var startComp = DateComponents()
        startComp.year = startYear
        startComp.month = startMonth
        startComp.day = anchorDay
        startComp.hour = 0
        startComp.minute = 0
        startComp.second = 0

        var endComp = DateComponents()
        endComp.year = endYear
        endComp.month = endMonth
        endComp.day = anchorDay
        endComp.hour = 0
        endComp.minute = 0
        endComp.second = 0

        let startDate = cal.date(from: startComp) ?? now
        let endDate = cal.date(from: endComp) ?? now.addingTimeInterval(30 * 86400)

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "d MMM yyyy"
        df.timeZone = TimeZone(secondsFromGMT: 0)
        return "\(df.string(from: startDate)) - \(df.string(from: endDate))"
    }

    public var egressQuotaPercent: Double {
        guard egressQuotaBytes > 0 else { return 0 }
        return min(999.0, (Double(egressUsedBytes) / Double(egressQuotaBytes)) * 100.0)
    }

    public var egressCycleUsedBytes: Int64 {
        egressUsedBytes
    }

    public var egressCycleQuotaBytes: Int64 {
        egressQuotaBytes
    }

    public var egressCycleQuotaPercent: Double {
        egressQuotaPercent
    }

    public var egress24hQuotaPercent: Double {
        guard egressQuotaBytes > 0 else { return 0 }
        let dailyBudget = Double(egressQuotaBytes) / 30.0
        return min(999.0, (Double(egress24hBytes) * 100.0) / max(1.0, dailyBudget))
    }

    public var dbQuotaPercent: Double {
        guard dbQuotaBytes > 0 else { return 0 }
        return min(999.0, (Double(dbSizeBytes) / Double(dbQuotaBytes)) * 100.0)
    }

    public var logIngestionQuotaPercent: Double {
        guard logIngestionQuotaBytes > 0 else { return 0 }
        return min(999.0, (Double(logIngestionBytes) / Double(logIngestionQuotaBytes)) * 100.0)
    }

    public var logQueryQuotaPercent: Double {
        guard logQueryQuotaBytes > 0 else { return 0 }
        return min(999.0, (Double(logQueryBytes) / Double(logQueryQuotaBytes)) * 100.0)
    }

    public var totalHttpRequests24h: Int {
        http2xxCount24h + http4xxCount24h + http5xxCount24h
    }

    public var errorRate24hPercent: Double {
        let total = totalHttpRequests24h
        guard total > 0 else { return 0 }
        return (Double(http4xxCount24h + http5xxCount24h) / Double(total)) * 100.0
    }

    /// Generates a complete forensic Markdown snapshot matching DayOne's `Docs/` engineering audit format.
    public func toMarkdownReport() -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let ts = iso.string(from: fetchedAt)

        var lines: [String] = []
        lines.append("# Supabase Cloud Forensic Telemetry Report — \(project.name) (`\(project.ref)`)")
        lines.append("")
        lines.append("- **Generated At:** `\(ts)`")
        lines.append("- **Organization & Plan:** `\(orgName)` (`\(orgPlan.uppercased())`) · **Compute:** `\(computeTier)` · **Region:** `\(project.region)`")
        lines.append("- **PostgreSQL Engine:** `\(project.postgresVersion)` · **Cache Hit Ratio:** `\(String(format: "%.2f%%", cacheHitRatioPercent))`")
        lines.append("")
        lines.append("## 1. Executive Quota Summary")
        lines.append("")
        lines.append("| Resource Metric | Current Usage | Plan Quota | Utilization |")
        lines.append("| :--- | :--- | :--- | :--- |")
        let egressNote = isExactBillingUsageAvailable ? " *(Current Cycle)*" : " *(Billing Cycle)*"
        lines.append("| **Billing Cycle Egress** | \(Self.formatBytes(egressUsedBytes))\(egressNote) | \(Self.formatBytes(egressQuotaBytes)) | **\(String(format: "%.1f%%", egressCycleQuotaPercent))** |")
        lines.append("| **24h Gateway Egress** | \(Self.formatBytes(egress24hBytes)) *(24h traffic)* | \(Self.formatBytes(egressQuotaBytes)) | **\(String(format: "%.1f%%", egress24hQuotaPercent))** |")
        lines.append("| **Database Size** | \(Self.formatBytes(dbSizeBytes)) | \(Self.formatBytes(dbQuotaBytes)) | **\(String(format: "%.1f%%", dbQuotaPercent))** |")
        lines.append("| **Storage Size** | \(Self.formatBytes(storageSizeBytes)) | \(Self.formatBytes(storageQuotaBytes)) | \(storageQuotaBytes > 0 ? String(format: "%.1f%%", Double(storageSizeBytes) * 100.0 / Double(storageQuotaBytes)) : "—") |")
        lines.append("| **Edge Function Invocations** | \(functionInvocations) | \(functionInvocationsQuota) | \(functionInvocationsQuota > 0 ? String(format: "%.1f%%", Double(functionInvocations) * 100.0 / Double(functionInvocationsQuota)) : "—") |")
        lines.append("| **Realtime Messages** | \(realtimeMessages) | \(realtimeMessagesQuota) | \(realtimeMessagesQuota > 0 ? String(format: "%.1f%%", Double(realtimeMessages) * 100.0 / Double(realtimeMessagesQuota)) : "—") |")
        lines.append("| **Realtime Peak Connections** | \(realtimePeakConnections) | \(realtimePeakConnectionsQuota) | \(realtimePeakConnectionsQuota > 0 ? String(format: "%.1f%%", Double(realtimePeakConnections) * 100.0 / Double(realtimePeakConnectionsQuota)) : "—") |")
        lines.append("| **Monthly Active Users (MAU)** | \(mauCount) | \(mauQuota) | \(mauQuota > 0 ? String(format: "%.1f%%", Double(mauCount) * 100.0 / Double(mauQuota)) : "—") |")
        lines.append("| **Log Ingestion** | \(Self.formatBytes(logIngestionBytes)) | \(Self.formatBytes(logIngestionQuotaBytes)) | **\(String(format: "%.1f%%", logIngestionQuotaPercent))** |")
        lines.append("| **Log Query** | \(Self.formatBytes(logQueryBytes)) | \(Self.formatBytes(logQueryQuotaBytes)) | **\(String(format: "%.1f%%", logQueryQuotaPercent))** |")
        lines.append("")

        if !dailyEgress.isEmpty {
            lines.append("## 2. Daily Egress Breakdown (Recent Window)")
            lines.append("")
            lines.append("| Date | Total | PostgREST | Edge Functions | Realtime | Auth | Storage |")
            lines.append("| :--- | :--- | :--- | :--- | :--- | :--- | :--- |")
            for pt in dailyEgress.suffix(14) {
                lines.append("| `\(pt.date)` | **\(Self.formatBytes(pt.totalBytes))** | \(Self.formatBytes(pt.restBytes)) | \(Self.formatBytes(pt.functionBytes)) | \(Self.formatBytes(pt.realtimeBytes)) | \(Self.formatBytes(pt.authBytes)) | \(Self.formatBytes(pt.storageBytes)) |")
            }
            lines.append("")
        }

        lines.append("## 3. PostgreSQL Table Storage & Index Bloat")
        lines.append("")
        lines.append("- **Heap Data:** `\(Self.formatBytes(heapDataBytes))` · **Indexes:** `\(Self.formatBytes(indexTotalBytes))` · **Total DB:** `\(Self.formatBytes(dbSizeBytes))`")
        lines.append("")
        lines.append("| Schema.Table | Data Size | Index Size | Total Size | Live Rows | Dead Rows | Status |")
        lines.append("| :--- | :--- | :--- | :--- | :--- | :--- | :--- |")
        for t in tables.prefix(15) {
            let badge = t.hasIndexBloatWarning ? "⚠️ Bloat (\(String(format: "%.1fx", t.bloatRatio)))" : "OK"
            lines.append("| `\(t.schema).\(t.tableName)` | \(Self.formatBytes(t.dataBytes)) | \(Self.formatBytes(t.indexBytes)) | **\(Self.formatBytes(t.totalBytes))** | \(t.liveRows) | \(t.deadRows) | \(badge) |")
        }
        lines.append("")

        if !topRoutes24h.isEmpty {
            lines.append("## 4. Top HTTP Gateway Routes (Last 24h)")
            lines.append("")
            lines.append("| Method & Path | Requests (24h) | Content-Length Sum | Avg Latency | 4xx/5xx |")
            lines.append("| :--- | :--- | :--- | :--- | :--- |")
            for r in topRoutes24h.prefix(10) {
                lines.append("| `\(r.method) \(r.path)` | \(r.requests24h) | \(Self.formatBytes(r.responseBytes24h)) | \(String(format: "%.1f ms", r.avgLatencyMs)) | \(r.errors4xx5xx) |")
            }
            lines.append("")
        }

        if !fleetDevices.isEmpty {
            lines.append("## 5. Ecosystem Fleet Footprint (Last 24h)")
            lines.append("")
            lines.append("| Client Platform | Requests (24h) | Traffic Share | Payload Sum | 4xx Errors |")
            lines.append("| :--- | :--- | :--- | :--- | :--- |")
            for f in fleetDevices {
                lines.append("| **\(f.displayName)** | \(f.requests24h) | \(String(format: "%.1f%%", f.sharePercent)) | \(Self.formatBytes(f.responseBytes24h)) | \(f.errors4xx24h) |")
            }
            lines.append("")
        }

        if !edgeFunctions.isEmpty {
            lines.append("## 6. Edge Functions Telemetry")
            lines.append("")
            lines.append("| Slug | Status | Version | 24h Invocations | Success % | Avg / Max Latency |")
            lines.append("| :--- | :--- | :--- | :--- | :--- | :--- |")
            for fn in edgeFunctions {
                lines.append("| `\(fn.slug)` | `\(fn.status)` | v\(fn.version) | \(fn.invocations24h) | \(String(format: "%.1f%%", fn.successRatePercent)) | \(String(format: "%.0f / %.0f ms", fn.avgExecutionMs, fn.maxExecutionMs)) |")
            }
            lines.append("")
        }

        if !performanceLints.isEmpty || !securityLints.isEmpty {
            lines.append("## 7. Supabase Advisors (\(performanceLints.count) Performance · \(securityLints.count) Security)")
            lines.append("")
            for lint in (securityLints + performanceLints).prefix(12) {
                lines.append("- **[\(lint.category) · \(lint.level)] \(lint.title):** \(lint.detail)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}
