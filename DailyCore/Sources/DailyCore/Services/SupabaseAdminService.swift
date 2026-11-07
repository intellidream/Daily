import Foundation
import LocalAuthentication
#if !os(macOS)
import Security
#endif

/// Centralized, strictly read-only Cloud Observability & Admin Telemetry service for Supabase.
///
/// Architectural guarantees:
/// 1. Zero idle background polling — network queries execute ONLY when the Admin Console is opened (10-min TTL) or explicitly refreshed.
/// 2. Zero mutating API/SQL calls — strictly GET telemetry endpoints and `/database/query/read-only`.
/// 3. Strict local credential isolation — `GroupDefaults` on macOS (zero Keychain prompts), `ThisDeviceOnly` Keychain on iOS; NEVER synced to cloud `user_settings`.
@MainActor
public final class SupabaseAdminService: ObservableObject {
    public static let shared = SupabaseAdminService()

    public static let defaultProjectRef = "akkfouifxztnfwwiclwg"
    private static let credentialsStorageKey = "com.intellidream.daily.supabase.admin.credentials.v1"
    private static let snapshotCacheKeyPrefix = "com.intellidream.daily.supabase.admin.snapshot.v1."
    private static let cacheTtlSeconds: TimeInterval = 600 // 10 minutes

    @Published public private(set) var credentials: SupabaseAdminCredentials
    @Published public private(set) var snapshot: SupabaseAdminSnapshot?
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var isAuthenticating: Bool = false
    @Published public private(set) var isAnalyzingAI: Bool = false
    @Published public private(set) var aiAnalysis: String?
    @Published public var errorMessage: String?
    @Published public private(set) var isUnlockedInMemory: Bool = false

    private let session: URLSession

    public var isConnected: Bool {
        credentials.hasValidToken
    }

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 18.0
        config.timeoutIntervalForResource = 30.0
        self.session = URLSession(configuration: config)

        let loadedCreds = Self.loadCredentialsFromLocalStorage() ?? SupabaseAdminCredentials()
        self.credentials = loadedCreds
        self.isUnlockedInMemory = !loadedCreds.requireBiometrics
        if loadedCreds.hasValidToken {
            self.snapshot = Self.loadCachedSnapshot(projectRef: loadedCreds.selectedProjectRef)
        }
    }

    // MARK: - Local Isolated Storage (Zero Cloud Sync, Zero macOS Prompts)

    private static func loadCredentialsFromLocalStorage() -> SupabaseAdminCredentials? {
        #if os(macOS)
        guard let raw = GroupDefaults.shared.userDefaults.string(forKey: credentialsStorageKey),
              let data = raw.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(SupabaseAdminCredentials.self, from: data)
        #else
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.intellidream.daily.supabase.admin",
            kSecAttrAccount as String: credentialsStorageKey,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        if status == errSecSuccess, let data = dataTypeRef as? Data {
            return try? JSONDecoder().decode(SupabaseAdminCredentials.self, from: data)
        }
        return nil
        #endif
    }

    private static func saveCredentialsToLocalStorage(_ creds: SupabaseAdminCredentials) {
        guard let data = try? JSONEncoder().encode(creds) else { return }
        #if os(macOS)
        if let raw = String(data: data, encoding: .utf8) {
            GroupDefaults.shared.userDefaults.set(raw, forKey: credentialsStorageKey)
        }
        #else
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.intellidream.daily.supabase.admin",
            kSecAttrAccount as String: credentialsStorageKey
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.intellidream.daily.supabase.admin",
            kSecAttrAccount as String: credentialsStorageKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
        #endif
    }

    private static func removeCredentialsFromLocalStorage(projectRefs: [String]) {
        #if os(macOS)
        GroupDefaults.shared.userDefaults.removeObject(forKey: credentialsStorageKey)
        #else
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.intellidream.daily.supabase.admin",
            kSecAttrAccount as String: credentialsStorageKey
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        #endif

        var refs = Set(projectRefs)
        refs.insert(defaultProjectRef)
        for ref in refs {
            GroupDefaults.shared.userDefaults.removeObject(forKey: snapshotCacheKeyPrefix + ref)
        }
    }

    private static func loadCachedSnapshot(projectRef: String) -> SupabaseAdminSnapshot? {
        guard let raw = GroupDefaults.shared.userDefaults.string(forKey: snapshotCacheKeyPrefix + projectRef),
              let data = raw.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(SupabaseAdminSnapshot.self, from: data)
    }

    private static func saveCachedSnapshot(_ snap: SupabaseAdminSnapshot) {
        guard let data = try? JSONEncoder().encode(snap),
              let raw = String(data: data, encoding: .utf8) else { return }
        GroupDefaults.shared.userDefaults.set(raw, forKey: snapshotCacheKeyPrefix + snap.project.ref)
    }

    // MARK: - Biometric Gate

    public var biometryTypeString: String {
        let context = LAContext()
        var authError: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError)
        switch context.biometryType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        default:
            return "Passcode"
        }
    }

    public var canUseBiometrics: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
            || context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    public func lock() {
        if credentials.requireBiometrics {
            isUnlockedInMemory = false
        }
    }

    @discardableResult
    public func setRequireBiometrics(_ enabled: Bool) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var authError: NSError?
        let policy: LAPolicy = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError)
            ? .deviceOwnerAuthenticationWithBiometrics
            : .deviceOwnerAuthentication

        if context.canEvaluatePolicy(policy, error: &authError) {
            let prompt = enabled
                ? "Authenticate with \(biometryTypeString) to protect Supabase Admin Console"
                : "Authenticate with \(biometryTypeString) to disable protection"
            do {
                let success = try await context.evaluatePolicy(policy, localizedReason: prompt)
                guard success else { return false }
            } catch {
                return false
            }
        }

        credentials.requireBiometrics = enabled
        isUnlockedInMemory = true
        Self.saveCredentialsToLocalStorage(credentials)
        return true
    }

    @discardableResult
    public func unlockIfNeeded() async -> Bool {
        guard credentials.requireBiometrics else {
            isUnlockedInMemory = true
            return true
        }
        if isUnlockedInMemory { return true }

        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var authError: NSError?
        let policy: LAPolicy = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError)
            ? .deviceOwnerAuthenticationWithBiometrics
            : .deviceOwnerAuthentication

        guard context.canEvaluatePolicy(policy, error: &authError) else {
            isUnlockedInMemory = false
            return false
        }

        do {
            let success = try await context.evaluatePolicy(
                policy,
                localizedReason: "Unlock DayOne Supabase Cloud Admin Console"
            )
            isUnlockedInMemory = success
            return success
        } catch {
            isUnlockedInMemory = false
            return false
        }
    }

    // MARK: - Authentication Flows (GitHub CLI Handshake & PAT Fallback)

    public func completeCliHandshake(
        handshake: SupabaseCliLoginHandshake,
        deviceCode: String,
        dashboardSessionJson: String?
    ) async throws {
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }

        var pollComponents = URLComponents(string: "https://api.supabase.com/platform/cli/login/\(handshake.sessionId)")!
        pollComponents.queryItems = [URLQueryItem(name: "device_code", value: deviceCode)]
        let pollUrl = pollComponents.url!

        var decryptedMgmtToken: String?
        var lastPollError: Error?

        for attempt in 1...3 {
            do {
                var req = URLRequest(url: pollUrl)
                req.httpMethod = "GET"
                req.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, resp) = try await session.data(for: req)
                if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let encToken = obj["access_token"] as? String,
                   let pubKey = obj["public_key"] as? String,
                   let nonce = obj["nonce"] as? String {
                    decryptedMgmtToken = try handshake.decryptToken(
                        encryptedHex: encToken,
                        serverPublicKeyHex: pubKey,
                        nonceHex: nonce
                    )
                    break
                } else {
                    lastPollError = NSError(
                        domain: "SupabaseAdminService",
                        code: (resp as? HTTPURLResponse)?.statusCode ?? 500,
                        userInfo: [NSLocalizedDescriptionKey: "Pending CLI token exchange from Supabase."]
                    )
                }
            } catch {
                lastPollError = error
            }
            if attempt < 3 {
                try? await Task.sleep(nanoseconds: 650_000_000)
            }
        }

        let parsedDash = SupabaseAdminCrypto.parseDashboardSessionJson(dashboardSessionJson)

        guard decryptedMgmtToken != nil || parsedDash.accessToken != nil else {
            throw lastPollError ?? NSError(
                domain: "SupabaseAdminService",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Could not obtain Supabase Admin token from GitHub login session."]
            )
        }

        let bearerToVerify = decryptedMgmtToken ?? parsedDash.accessToken!
        let (projects, resolvedIdentity) = try await verifyBearerAndFetchProjects(
            bearer: bearerToVerify,
            fallbackIdentity: parsedDash.identity
        )

        let preferredProject = projects.first(where: { $0.ref == Self.defaultProjectRef }) ?? projects.first
        let newCreds = SupabaseAdminCredentials(
            managementAccessToken: decryptedMgmtToken,
            dashboardAccessToken: parsedDash.accessToken,
            dashboardRefreshToken: parsedDash.refreshToken,
            adminIdentity: resolvedIdentity,
            selectedProjectRef: preferredProject?.ref ?? Self.defaultProjectRef,
            selectedOrgSlug: preferredProject?.organizationSlug,
            requireBiometrics: credentials.requireBiometrics,
            connectedAt: Date()
        )

        self.credentials = newCreds
        self.isUnlockedInMemory = true
        Self.saveCredentialsToLocalStorage(newCreds)

        await refreshSnapshot(force: true)
    }

    public func connectWithPersonalAccessToken(_ rawPat: String) async throws {
        let trimmed = rawPat.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(
                domain: "SupabaseAdminService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Please enter a valid Supabase Personal Access Token (sbp_...)."]
            )
        }

        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }

        let (projects, identity) = try await verifyBearerAndFetchProjects(bearer: trimmed, fallbackIdentity: nil)
        let preferredProject = projects.first(where: { $0.ref == Self.defaultProjectRef }) ?? projects.first

        let newCreds = SupabaseAdminCredentials(
            managementAccessToken: trimmed,
            dashboardAccessToken: nil,
            dashboardRefreshToken: nil,
            adminIdentity: identity ?? "PAT Admin",
            selectedProjectRef: preferredProject?.ref ?? Self.defaultProjectRef,
            selectedOrgSlug: preferredProject?.organizationSlug,
            requireBiometrics: credentials.requireBiometrics,
            connectedAt: Date()
        )

        self.credentials = newCreds
        self.isUnlockedInMemory = true
        Self.saveCredentialsToLocalStorage(newCreds)

        await refreshSnapshot(force: true)
    }

    public func selectProject(ref: String) async {
        guard ref != credentials.selectedProjectRef else { return }
        if let found = snapshot?.availableProjects.first(where: { $0.ref == ref }) {
            credentials.selectedOrgSlug = found.organizationSlug
        }
        credentials.selectedProjectRef = ref
        Self.saveCredentialsToLocalStorage(credentials)
        aiAnalysis = nil

        if let cached = Self.loadCachedSnapshot(projectRef: ref) {
            self.snapshot = cached
            if Date().timeIntervalSince(cached.fetchedAt) < Self.cacheTtlSeconds {
                return
            }
        }
        await refreshSnapshot(force: true)
    }

    public func disconnect() {
        let knownRefs = (snapshot?.availableProjects.map(\.ref) ?? []) + [credentials.selectedProjectRef]
        Self.removeCredentialsFromLocalStorage(projectRefs: knownRefs)
        credentials = SupabaseAdminCredentials()
        snapshot = nil
        aiAnalysis = nil
        errorMessage = nil
        isUnlockedInMemory = false
    }

    // MARK: - Snapshot Refresh (10-Minute Local Cache + Parallel Aggregation)

    public func ensureLoadedOnAppear() async {
        guard isConnected else { return }
        if let current = snapshot,
           current.project.ref == credentials.selectedProjectRef,
           Date().timeIntervalSince(current.fetchedAt) < Self.cacheTtlSeconds {
            return
        }
        if let cached = Self.loadCachedSnapshot(projectRef: credentials.selectedProjectRef) {
            self.snapshot = cached
            if Date().timeIntervalSince(cached.fetchedAt) < Self.cacheTtlSeconds {
                return
            }
        }
        await refreshSnapshot(force: false)
    }

    public func refreshSnapshot(force: Bool = true) async {
        guard let mgmtBearer = credentials.primaryManagementBearer else { return }
        if !force, let snap = snapshot, Date().timeIntervalSince(snap.fetchedAt) < Self.cacheTtlSeconds {
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let targetRef = credentials.selectedProjectRef
        let platformBearer = credentials.primaryPlatformBearer ?? mgmtBearer
        let hasDashboardToken = (credentials.dashboardAccessToken?.isEmpty == false)

        do {
            let projects = try await fetchProjectsList(bearer: mgmtBearer)
            let activeProject = projects.first(where: { $0.ref == targetRef })
                ?? projects.first
                ?? SupabaseProjectSummary(
                    ref: targetRef,
                    name: "Daily",
                    organizationSlug: credentials.selectedOrgSlug ?? "",
                    region: "eu-central-1",
                    status: "ACTIVE_HEALTHY",
                    postgresVersion: "17"
                )

            let ref = activeProject.ref
            let orgSlug = activeProject.organizationSlug.isEmpty
                ? (credentials.selectedOrgSlug ?? "")
                : activeProject.organizationSlug

            // Fire all read-only control-plane, ClickHouse, and Postgres telemetry requests concurrently
            async let orgTask = fetchOrgDetails(bearer: mgmtBearer, orgSlug: orgSlug)
            async let addonsTask = fetchComputeTier(bearer: mgmtBearer, ref: ref)
            async let healthTask = fetchServicesHealth(bearer: mgmtBearer, ref: ref)
            async let diskTask = fetchDiskTelemetry(bearer: mgmtBearer, ref: ref)
            async let apiCountsTask = fetchApiCounts24h(bearer: mgmtBearer, ref: ref)
            async let functionsTask = fetchEdgeFunctionsTelemetry(bearer: mgmtBearer, ref: ref)
            async let advisorsTask = fetchAdvisors(bearer: mgmtBearer, ref: ref)
            async let logsForensicsTask = fetchClickHouseLogsForensics(bearer: mgmtBearer, ref: ref)
            async let pgCatalogTask = fetchPostgresCatalogForensics(bearer: mgmtBearer, ref: ref)
            async let platformUsageTask = fetchPlatformBillingUsage(
                bearer: platformBearer,
                orgSlug: orgSlug,
                ref: ref,
                preferDashboardEndpoint: hasDashboardToken
            )

            let (orgName, orgPlan) = await orgTask
            let computeTier = await addonsTask
            let serviceHealth = await healthTask
            let diskInfo = await diskTask
            let apiCounts = await apiCountsTask
            let edgeFunctions = await functionsTask
            let (perfLints, secLints) = await advisorsTask
            let logsData = await logsForensicsTask
            let pgData = await pgCatalogTask
            let billingData = await platformUsageTask

            // Plan-aware default quotas when exact `/platform/organizations/{slug}/usage` isn't returned (e.g. PAT-only mode)
            let isProOrHigher = ["pro", "team", "enterprise"].contains(orgPlan.lowercased())
            let defaultEgressQuota: Int64 = isProOrHigher ? 268_435_456_000 : 5_368_709_120 // 250 GB vs 5 GB
            let defaultDbQuota: Int64 = isProOrHigher ? 8_589_934_592 : 524_288_000          // 8 GB vs 500 MB
            let defaultStorageQuota: Int64 = isProOrHigher ? 107_374_182_400 : 1_073_741_824 // 100 GB vs 1 GB
            let defaultFnQuota: Int64 = isProOrHigher ? 2_000_000 : 500_000
            let defaultRtMsgQuota: Int64 = isProOrHigher ? 5_000_000 : 2_000_000
            let defaultRtPeakQuota: Int64 = isProOrHigher ? 500 : 200
            let defaultMauQuota: Int64 = isProOrHigher ? 100_000 : 50_000

            // Multi-tier 24h Egress resolution:
            // 1. Direct ClickHouse edge logs bytes (with chunked encoding estimation fallback)
            // 2. Today's point in the daily egress series
            // 3. Fallback request count estimation from apiCounts
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            df.timeZone = TimeZone(secondsFromGMT: 0)
            let todayStr = df.string(from: Date())
            let todayDailyPointBytes = billingData.dailyEgress.first(where: { $0.date == todayStr })?.totalBytes ?? 0
            let apiCountEstimatedBytes: Int64 = apiCounts.reduce(0) { acc, pt in
                acc + Int64(pt.restRequests) * 1280
                    + Int64(pt.authRequests) * 850
                    + Int64(pt.storageRequests) * 8192
                    + Int64(pt.realtimeRequests) * 450
            }

            var resolved24hEgress: Int64 = logsData.totalEdgeResponseBytes24h
            if resolved24hEgress == 0 {
                if todayDailyPointBytes > 0 {
                    resolved24hEgress = todayDailyPointBytes
                } else if apiCountEstimatedBytes > 0 {
                    resolved24hEgress = apiCountEstimatedBytes
                }
            }

            // Billing Cycle / Monthly Egress resolution:
            // 1. Direct billing usage (when exact or non-zero)
            // 2. Sum of all points in dailyEgress series
            // 3. Fallback to at least 24h burst
            let sumDailyEgressBytes = billingData.dailyEgress.reduce(0) { $0 + $1.totalBytes }
            var resolvedCycleEgress: Int64 = billingData.egressUsedBytes
            if resolvedCycleEgress == 0 {
                if sumDailyEgressBytes > 0 {
                    resolvedCycleEgress = sumDailyEgressBytes
                } else {
                    resolvedCycleEgress = resolved24hEgress
                }
            } else if resolved24hEgress > resolvedCycleEgress {
                resolvedCycleEgress = max(resolvedCycleEgress, resolved24hEgress)
            }

            let resolvedDbSize = max(billingData.dbSizeBytes, pgData.dbSizeBytes)
            let resolvedFnInvocations = billingData.functionInvocations > 0
                ? billingData.functionInvocations
                : Int64(edgeFunctions.reduce(0) { $0 + $1.invocations24h })
            let resolvedMau = billingData.mauCount > 0 ? billingData.mauCount : pgData.totalUsersCount
            let resolvedLogEvents = billingData.logIngestionEvents > 0
                ? billingData.logIngestionEvents
                : Int64(logsData.logCountsBySource.values.reduce(0, +))

            // Merge registered health sources into Fleet devices
            let fleetDevices = buildFleetStats(
                rawFleetBuckets: logsData.fleetBuckets,
                registeredHealthSources: pgData.healthSourceNames
            )

            // Build daily egress fallback point from 24h logs if `/platform/.../usage/daily` wasn't available
            var dailySeries = billingData.dailyEgress
            if dailySeries.isEmpty && resolved24hEgress > 0 {
                dailySeries = [
                    SupabaseDailyEgressPoint(
                        date: todayStr,
                        restBytes: logsData.restBytes24h > 0 ? logsData.restBytes24h : resolved24hEgress,
                        functionBytes: logsData.functionBytes24h,
                        realtimeBytes: logsData.realtimeBytes24h,
                        authBytes: logsData.authBytes24h,
                        storageBytes: logsData.storageBytes24h,
                        supavisorBytes: 0
                    )
                ]
            }

            let newSnapshot = SupabaseAdminSnapshot(
                fetchedAt: Date(),
                project: activeProject,
                availableProjects: projects,
                orgName: orgName,
                orgPlan: orgPlan,
                computeTier: computeTier,
                serviceHealth: serviceHealth,
                resourceWarnings: billingData.resourceWarnings,
                isExactBillingUsageAvailable: billingData.isExact,
                egressUsedBytes: resolvedCycleEgress,
                egressQuotaBytes: billingData.egressQuotaBytes > 0 ? billingData.egressQuotaBytes : defaultEgressQuota,
                cachedEgressUsedBytes: billingData.cachedEgressUsedBytes,
                egress24hBytes: resolved24hEgress,
                dbSizeBytes: resolvedDbSize,
                dbQuotaBytes: billingData.dbQuotaBytes > 0 ? billingData.dbQuotaBytes : defaultDbQuota,
                storageSizeBytes: max(billingData.storageSizeBytes, pgData.storageObjectsBytes),
                storageQuotaBytes: billingData.storageQuotaBytes > 0 ? billingData.storageQuotaBytes : defaultStorageQuota,
                functionInvocations: resolvedFnInvocations,
                functionInvocationsQuota: billingData.functionInvocationsQuota > 0 ? billingData.functionInvocationsQuota : defaultFnQuota,
                realtimeMessages: billingData.realtimeMessages,
                realtimeMessagesQuota: billingData.realtimeMessagesQuota > 0 ? billingData.realtimeMessagesQuota : defaultRtMsgQuota,
                realtimePeakConnections: max(billingData.realtimePeakConnections, Int64(pgData.realtimeActiveSubscriptions)),
                realtimePeakConnectionsQuota: billingData.realtimePeakConnectionsQuota > 0 ? billingData.realtimePeakConnectionsQuota : defaultRtPeakQuota,
                mauCount: resolvedMau,
                mauQuota: billingData.mauQuota > 0 ? billingData.mauQuota : defaultMauQuota,
                logIngestionEvents: resolvedLogEvents,
                dailyEgress: dailySeries,
                apiCounts24h: apiCounts,
                logCountsBySource: logsData.logCountsBySource,
                http2xxCount24h: logsData.http2xxCount,
                http4xxCount24h: logsData.http4xxCount,
                http5xxCount24h: logsData.http5xxCount,
                topRoutes24h: logsData.topRoutes,
                recentErrors24h: logsData.recentErrors,
                diskUsedBytes: diskInfo.usedBytes > 0 ? diskInfo.usedBytes : resolvedDbSize,
                diskTotalBytes: diskInfo.totalBytes,
                diskIops: diskInfo.iops,
                diskThroughputMibps: diskInfo.throughputMibps,
                heapDataBytes: pgData.heapDataBytes,
                indexTotalBytes: pgData.indexTotalBytes,
                activeDbConnections: pgData.activeConnections,
                cacheHitRatioPercent: pgData.cacheHitRatio,
                tables: pgData.tables,
                topSqlStatements: pgData.topSql,
                cronJobs: pgData.cronJobs,
                edgeFunctions: edgeFunctions,
                realtimeActiveSubscriptions: pgData.realtimeActiveSubscriptions,
                realtimeSubscriptionsByTable: pgData.realtimeByTable,
                realtimeWalListChangesCalls: pgData.realtimeListChangesCalls,
                realtimeWalCpuSharePercent: pgData.realtimeWalCpuPercent,
                totalUsersCount: pgData.totalUsersCount,
                activeAuthSessionsCount: pgData.activeSessionsCount,
                refreshTokenWritesCumulative: pgData.refreshTokenWrites,
                pairedWatchesCount: pgData.pairedWatchesCount,
                fleetDevices: fleetDevices,
                performanceLints: perfLints,
                securityLints: secLints
            )

            self.snapshot = newSnapshot
            Self.saveCachedSnapshot(newSnapshot)

            if credentials.selectedProjectRef != activeProject.ref || credentials.selectedOrgSlug != orgSlug {
                credentials.selectedProjectRef = activeProject.ref
                credentials.selectedOrgSlug = orgSlug
                Self.saveCredentialsToLocalStorage(credentials)
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    // MARK: - AI Telemetry Co-Pilot (Gemini + Deterministic Fallback)

    public func analyzeWithAI() async {
        guard let snap = snapshot else { return }
        isAnalyzingAI = true
        defer { isAnalyzingAI = false }

        let geminiKey = SettingsService.shared.settings.geminiApiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !geminiKey.isEmpty {
            do {
                let narrative = try await requestGeminiAnalysis(apiKey: geminiKey, snapshot: snap)
                self.aiAnalysis = narrative
                return
            } catch {
                // Gracefully fall back to deterministic local diagnostic analysis
            }
        }

        self.aiAnalysis = Self.buildDeterministicDiagnosticSummary(snapshot: snap)
    }

    private func requestGeminiAnalysis(apiKey: String, snapshot: SupabaseAdminSnapshot) async throws -> String {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=\(apiKey)") else {
            throw URLError(.badURL)
        }
        let reportSnippet = String(snapshot.toMarkdownReport().prefix(7500))
        let prompt = """
        You are a Staff PostgreSQL & Supabase SRE auditing the DayOne ecosystem cloud backend (\(snapshot.project.name), plan: \(snapshot.orgPlan.uppercased())).
        Analyze this live read-only telemetry report and provide 4 concise, high-signal bullet points covering:
        1. Egress & Gateway efficiency (identify top bandwidth routes or 4xx/5xx anomalies).
        2. PostgreSQL storage & index bloat health (flag any tables where index size >> heap size or dead rows accumulate).
        3. Realtime WAL / Edge Functions / pg_cron operational status.
        4. Concrete, prioritized next engineering optimizations (without destructive SQL).
        Keep it under 190 words in crisp Markdown bullets.

        TELEMETRY:
        \(reportSnippet)
        """

        let body: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": prompt]]]],
            "generationConfig": ["temperature": 0.25, "maxOutputTokens": 450]
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 12.0
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw URLError(.cannotParseResponse)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated public static func buildDeterministicDiagnosticSummary(snapshot: SupabaseAdminSnapshot) -> String {
        var bullets: [String] = []

        // 1. Egress & Quota posture (Billing Cycle + 24h Gateway)
        let cycleFormatted = "\(SupabaseAdminSnapshot.formatBytes(snapshot.egressCycleUsedBytes)) / \(SupabaseAdminSnapshot.formatBytes(snapshot.egressCycleQuotaBytes))"
        let h24Formatted = SupabaseAdminSnapshot.formatBytes(snapshot.egress24hBytes)
        if snapshot.egressCycleQuotaPercent >= 90 {
            bullets.append("- **⚠️ Billing Cycle Egress Quota Pressure (\(String(format: "%.1f%%", snapshot.egressCycleQuotaPercent))):** Unified billing cycle egress has reached **\(cycleFormatted)** (24h burst: **\(h24Formatted)** across **\(snapshot.totalHttpRequests24h)** gateway requests). Prioritize delta-sync (`updated_at > lastSync`) and column projection on the heaviest PostgREST endpoints.")
        } else {
            bullets.append("- **✅ Bandwidth Posture (\(String(format: "%.1f%%", snapshot.egressCycleQuotaPercent))):** Billing cycle egress stands at **\(cycleFormatted)**; 24h gateway egress is **\(h24Formatted)** across **\(snapshot.totalHttpRequests24h)** requests. Top 24h route: `\(snapshot.topRoutes24h.first.map { "\($0.method) \($0.path)" } ?? "nominal")`.")
        }

        // 2. Database & Index Bloat
        let bloated = snapshot.tables.filter(\.hasIndexBloatWarning)
        if let worst = bloated.first {
            bullets.append("- **🔍 B-Tree Index Bloat Detected (`\(worst.schema).\(worst.tableName)`):** Indexes consume **\(SupabaseAdminSnapshot.formatBytes(worst.indexBytes))** vs **\(SupabaseAdminSnapshot.formatBytes(worst.dataBytes))** heap (**\(String(format: "%.1fx", worst.bloatRatio))**). Total DB is **\(SupabaseAdminSnapshot.formatBytes(snapshot.dbSizeBytes))** (\(String(format: "%.1f%%", snapshot.dbQuotaPercent)) of quota); `REINDEX TABLE CONCURRENTLY` during a maintenance window can reclaim disk.")
        } else {
            bullets.append("- **🗄️ PostgreSQL Storage Healthy:** Database uses **\(SupabaseAdminSnapshot.formatBytes(snapshot.dbSizeBytes))** (**\(String(format: "%.1f%%", snapshot.dbQuotaPercent))** of quota) with **\(String(format: "%.2f%%", snapshot.cacheHitRatioPercent))** buffer cache hit ratio and zero severe index bloat anomalies.")
        }

        // 3. Gateway error rate & Realtime WAL
        if snapshot.http4xxCount24h + snapshot.http5xxCount24h > 50 || snapshot.errorRate24hPercent > 3.0 {
            bullets.append("- **🛡️ Gateway Error Watch:** Logged **\(snapshot.http4xxCount24h)** `4xx` and **\(snapshot.http5xxCount24h)** `5xx` responses in the last 24h (**\(String(format: "%.1f%%", snapshot.errorRate24hPercent))** error ratio). Inspect stale refresh-token retries or schema column mismatches in the Recent Errors panel.")
        } else if snapshot.realtimeWalCpuSharePercent > 25.0 {
            bullets.append("- **⚡ Realtime WAL Load:** `realtime.list_changes` accounts for **\(String(format: "%.1f%%", snapshot.realtimeWalCpuSharePercent))** of tracked SQL execution across **\(snapshot.realtimeActiveSubscriptions)** active subscriptions. Keep dormant desktop/mobile background tabs unsubscribed.")
        } else {
            bullets.append("- **⚡ Runtime & Realtime Nominal:** Gateway error rate is **\(String(format: "%.2f%%", snapshot.errorRate24hPercent))** over **\(snapshot.totalHttpRequests24h)** 24h requests, with **\(snapshot.realtimeActiveSubscriptions)** active Realtime subscriptions.")
        }

        // 4. Advisors & Cron
        let totalAdvisors = snapshot.securityLints.count + snapshot.performanceLints.count
        let failedCrons = snapshot.cronJobs.filter { !$0.isSucceeded }
        if !failedCrons.isEmpty {
            bullets.append("- **⏱️ Retention Cron Alert:** `\(failedCrons[0].jobName)` reported status `\(failedCrons[0].status)`. Verify `pg_cron` retention jobs so high-frequency telemetry tables stay bounded.")
        } else if totalAdvisors > 0 {
            bullets.append("- **🧭 Supabase Advisors:** **\(snapshot.securityLints.count)** security and **\(snapshot.performanceLints.count)** performance lints surfaced ( review unindexed foreign keys or RLS `initplan` wrappers).")
        } else {
            bullets.append("- **🧭 Zero Critical Lints:** All monitored Supabase services, `pg_cron` jobs, and security advisors report clean operational state.")
        }

        return bullets.joined(separator: "\n")
    }

    // MARK: - Internal Control-Plane & SQL Fetchers

    private func verifyBearerAndFetchProjects(
        bearer: String,
        fallbackIdentity: String?
    ) async throws -> ([SupabaseProjectSummary], String?) {
        let projects = try await fetchProjectsList(bearer: bearer)
        var identity = fallbackIdentity
        if identity == nil {
            if let profileJson = try? await performGetJson(url: "https://api.supabase.com/v1/profile", bearer: bearer) as? [String: Any] {
                if let gh = profileJson["gotrue_meta_security"] as? String, !gh.isEmpty {
                    identity = gh
                }
                if let email = profileJson["primary_email"] as? String, !email.isEmpty {
                    identity = email
                } else if let username = profileJson["username"] as? String, !username.isEmpty {
                    identity = "@\(username)"
                }
            }
        }
        return (projects, identity)
    }

    private func fetchProjectsList(bearer: String) async throws -> [SupabaseProjectSummary] {
        let raw = try await performGetJson(url: "https://api.supabase.com/v1/projects", bearer: bearer)
        guard let arr = raw as? [[String: Any]] else { return [] }
        return arr.compactMap { item in
            let ref = Self.str(item["id"]) ?? Self.str(item["ref"]) ?? ""
            guard !ref.isEmpty else { return nil }
            let name = Self.str(item["name"]) ?? ref
            let orgSlug = Self.str(item["organization_slug"]) ?? Self.str(item["organization_id"]) ?? ""
            let region = Self.str(item["region"]) ?? "unknown"
            let status = Self.str(item["status"]) ?? "ACTIVE_HEALTHY"
            var pgVersion = "17"
            if let db = item["database"] as? [String: Any], let v = Self.str(db["version"]) {
                pgVersion = v
            }
            return SupabaseProjectSummary(
                ref: ref,
                name: name,
                organizationSlug: orgSlug,
                region: region,
                status: status,
                postgresVersion: pgVersion,
                createdAt: Self.str(item["created_at"])
            )
        }
    }

    private func fetchOrgDetails(bearer: String, orgSlug: String) async -> (String, String) {
        if !orgSlug.isEmpty,
           let detail = try? await performGetJson(url: "https://api.supabase.com/v1/organizations/\(orgSlug)", bearer: bearer) as? [String: Any] {
            let name = Self.str(detail["name"]) ?? orgSlug
            let plan = Self.str(detail["plan"]) ?? "free"
            return (name, plan)
        }
        if let list = try? await performGetJson(url: "https://api.supabase.com/v1/organizations", bearer: bearer) as? [[String: Any]],
           let match = list.first(where: { Self.str($0["id"]) == orgSlug || Self.str($0["slug"]) == orgSlug }) ?? list.first {
            let name = Self.str(match["name"]) ?? "Organization"
            let plan = Self.str(match["plan"]) ?? "free"
            return (name, plan)
        }
        return ("DayOne Cloud", "free")
    }

    private func fetchComputeTier(bearer: String, ref: String) async -> String {
        guard let json = try? await performGetJson(
            url: "https://api.supabase.com/v1/projects/\(ref)/billing/addons",
            bearer: bearer
        ) as? [String: Any] else {
            return "Micro (Shared)"
        }
        if let selected = json["selected_addons"] as? [[String: Any]] {
            for addon in selected {
                if Self.str(addon["type"]) == "compute_instance",
                   let variant = addon["variant"] as? [String: Any],
                   let name = Self.str(variant["name"]) {
                    return name
                }
            }
        }
        return "Nano / Micro"
    }

    private func fetchServicesHealth(bearer: String, ref: String) async -> [SupabaseServiceHealthItem] {
        guard let arr = try? await performGetJson(
            url: "https://api.supabase.com/v1/projects/\(ref)/health?services=auth,db,pooler,realtime,rest,storage",
            bearer: bearer
        ) as? [[String: Any]] else {
            return []
        }
        let labels: [String: String] = [
            "db": "PostgreSQL",
            "rest": "PostgREST",
            "auth": "GoTrue Auth",
            "realtime": "Realtime Elixir",
            "storage": "Object Storage",
            "pooler": "Supavisor Pooler"
        ]
        return arr.compactMap { item in
            guard let name = Self.str(item["name"]) else { return nil }
            let status = Self.str(item["status"]) ?? "ACTIVE_HEALTHY"
            let healthy = (item["healthy"] as? Bool) ?? status.uppercased().contains("HEALTHY")
            return SupabaseServiceHealthItem(
                name: name,
                displayName: labels[name] ?? name.capitalized,
                status: status,
                healthy: healthy,
                detail: Self.str(item["error"])
            )
        }
    }

    private struct DiskTelemetryResult: Sendable {
        var usedBytes: Int64 = 0
        var totalBytes: Int64 = 8_589_934_592 // 8 GB gp3 default
        var iops: Int = 3000
        var throughputMibps: Int = 125
    }

    private func fetchDiskTelemetry(bearer: String, ref: String) async -> DiskTelemetryResult {
        var res = DiskTelemetryResult()
        if let cfg = try? await performGetJson(url: "https://api.supabase.com/v1/projects/\(ref)/config/disk", bearer: bearer) as? [String: Any],
           let attrs = cfg["attributes"] as? [String: Any] {
            if let sizeGb = Self.int64(attrs["size_gb"]), sizeGb > 0 {
                res.totalBytes = sizeGb * 1_073_741_824
            }
            if let iops = Self.int(attrs["iops"]), iops > 0 {
                res.iops = iops
            }
            if let tp = Self.int(attrs["throughput_mbps"]), tp > 0 {
                res.throughputMibps = tp
            }
        }
        if let util = try? await performGetJson(url: "https://api.supabase.com/v1/projects/\(ref)/config/disk/util", bearer: bearer) as? [String: Any] {
            if let metrics = (util["metrics"] as? [[String: Any]])?.last {
                let total = Self.int64(metrics["fs_size_bytes"]) ?? res.totalBytes
                let avail = Self.int64(metrics["fs_avail_bytes"]) ?? 0
                if total > 0 {
                    res.totalBytes = total
                    if avail > 0 && avail <= total {
                        res.usedBytes = total - avail
                    }
                }
                if let usedDirect = Self.int64(metrics["fs_used_bytes"]), usedDirect > 0 {
                    res.usedBytes = usedDirect
                }
            }
        }
        return res
    }

    private func fetchApiCounts24h(bearer: String, ref: String) async -> [SupabaseApiCountPoint] {
        guard let json = try? await performGetJson(
            url: "https://api.supabase.com/v1/projects/\(ref)/analytics/endpoints/usage.api-counts?interval=1day",
            bearer: bearer
        ) as? [String: Any],
              let result = json["result"] as? [[String: Any]] else {
            return []
        }
        return result.compactMap { row in
            guard let ts = Self.str(row["timestamp"]) else { return nil }
            return SupabaseApiCountPoint(
                timestamp: ts,
                restRequests: Self.int(row["total_rest_requests"]) ?? 0,
                authRequests: Self.int(row["total_auth_requests"]) ?? 0,
                realtimeRequests: Self.int(row["total_realtime_requests"]) ?? 0,
                storageRequests: Self.int(row["total_storage_requests"]) ?? 0
            )
        }
    }

    private func fetchEdgeFunctionsTelemetry(bearer: String, ref: String) async -> [SupabaseEdgeFunctionStat] {
        guard let list = try? await performGetJson(
            url: "https://api.supabase.com/v1/projects/\(ref)/functions",
            bearer: bearer
        ) as? [[String: Any]] else {
            return []
        }

        return await withTaskGroup(of: SupabaseEdgeFunctionStat?.self) { group in
            for item in list {
                guard let id = Self.str(item["id"]),
                      let slug = Self.str(item["slug"]) else { continue }
                let name = Self.str(item["name"]) ?? slug
                let status = Self.str(item["status"]) ?? "ACTIVE"
                let version = Self.int(item["version"]) ?? 1
                let verifyJwt = (item["verify_jwt"] as? Bool) ?? true

                group.addTask { [session] in
                    var totalInv = 0
                    var totalErr = 0
                    var weightedExecSum = 0.0
                    var maxExec = 0.0

                    var comps = URLComponents(string: "https://api.supabase.com/v1/projects/\(ref)/analytics/endpoints/functions.combined-stats")!
                    comps.queryItems = [
                        URLQueryItem(name: "function_id", value: id),
                        URLQueryItem(name: "interval", value: "1day")
                    ]
                    if let url = comps.url {
                        var req = URLRequest(url: url)
                        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
                        if let (data, resp) = try? await session.data(for: req),
                           let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let rows = root["result"] as? [[String: Any]] {
                            for r in rows {
                                let count = Self.int(r["requests_count"]) ?? Self.int(r["count"]) ?? 0
                                let errs = (Self.int(r["log_Functions_Error"]) ?? 0)
                                    + (Self.int(r["status_4xx_count"]) ?? 0)
                                    + (Self.int(r["status_5xx_count"]) ?? 0)
                                    + (Self.int(r["errors_count"]) ?? 0)
                                let avgMs = Self.double(r["avg_execution_time"]) ?? Self.double(r["execution_time_avg"]) ?? 0
                                let mxMs = Self.double(r["max_execution_time"]) ?? avgMs
                                totalInv += count
                                totalErr += errs
                                weightedExecSum += avgMs * Double(max(count, 1))
                                if mxMs > maxExec { maxExec = mxMs }
                            }
                        }
                    }

                    let avgExec = totalInv > 0 ? (weightedExecSum / Double(totalInv)) : 0
                    return SupabaseEdgeFunctionStat(
                        id: id,
                        slug: slug,
                        name: name,
                        status: status,
                        version: version,
                        verifyJwt: verifyJwt,
                        invocations24h: totalInv,
                        errors24h: min(totalErr, totalInv),
                        avgExecutionMs: avgExec,
                        maxExecutionMs: maxExec
                    )
                }
            }

            var out: [SupabaseEdgeFunctionStat] = []
            for await stat in group {
                if let stat { out.append(stat) }
            }
            return out.sorted { $0.invocations24h > $1.invocations24h }
        }
    }

    private func fetchAdvisors(bearer: String, ref: String) async -> ([SupabaseAdvisorLint], [SupabaseAdvisorLint]) {
        async let perfData = try? performGetData(url: "https://api.supabase.com/v1/projects/\(ref)/advisors/performance", bearer: bearer)
        async let secData = try? performGetData(url: "https://api.supabase.com/v1/projects/\(ref)/advisors/security", bearer: bearer)

        let perfObj = (await perfData).flatMap { try? JSONSerialization.jsonObject(with: $0) }
        let secObj = (await secData).flatMap { try? JSONSerialization.jsonObject(with: $0) }

        let perf = Self.parseAdvisorResponse(perfObj, category: "PERFORMANCE")
        let sec = Self.parseAdvisorResponse(secObj, category: "SECURITY")
        return (perf, sec)
    }

    nonisolated private static func parseAdvisorResponse(_ raw: Any?, category: String) -> [SupabaseAdvisorLint] {
        guard let dict = raw as? [String: Any],
              let lints = dict["lints"] as? [[String: Any]] else {
            return []
        }
        return lints.enumerated().map { idx, item in
            let name = str(item["name"]) ?? "\(category.lowercased())_\(idx)"
            let title = str(item["title"]) ?? name.replacingOccurrences(of: "_", with: " ").capitalized
            let level = (str(item["level"]) ?? "WARN").uppercased()
            let detail = str(item["detail"]) ?? str(item["description"]) ?? ""
            let remediation = str(item["remediation"])
            return SupabaseAdvisorLint(
                id: "\(category)_\(name)_\(idx)",
                category: category,
                level: level,
                title: title,
                detail: detail,
                remediationUrl: remediation
            )
        }
    }

    // MARK: - ClickHouse Unified Logs Forensics (24h Window)

    private struct FleetRawBucket: Sendable {
        let ua: String
        let count: Int
        let bytes: Int64
        let errors4xx: Int
    }

    private struct LogsForensicsResult: Sendable {
        var logCountsBySource: [String: Int] = [:]
        var http2xxCount: Int = 0
        var http4xxCount: Int = 0
        var http5xxCount: Int = 0
        var totalEdgeResponseBytes24h: Int64 = 0
        var restBytes24h: Int64 = 0
        var functionBytes24h: Int64 = 0
        var realtimeBytes24h: Int64 = 0
        var authBytes24h: Int64 = 0
        var storageBytes24h: Int64 = 0
        var topRoutes: [SupabaseTopRouteStat] = []
        var recentErrors: [SupabaseGatewayErrorItem] = []
        var fleetBuckets: [FleetRawBucket] = []
    }

    private func fetchClickHouseLogsForensics(bearer: String, ref: String) async -> LogsForensicsResult {
        var out = LogsForensicsResult()
        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-23.8 * 3600) // Strictly < 24h per Supabase ClickHouse validation rule
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let startIso = iso.string(from: startDate)
        let endIso = iso.string(from: endDate)

        // 1. Source volume distribution across unified `logs`
        let sourceSql = """
        SELECT source, count() AS cnt
        FROM logs
        GROUP BY source
        ORDER BY cnt DESC
        LIMIT 12
        """

        // 2. Top HTTP routes + response content-length + status buckets from `edge_logs`
        // Note: Unified ClickHouse tables may identify edge logs via `source = 'edge_logs'` or `source_name = 'edge_logs'`.
        // Content-Length can also be logged under multiple response headers or body size fields.
        let routesSql = """
        SELECT
          log_attributes['request.method'] AS method,
          log_attributes['request.path'] AS path,
          count() AS req_count,
          sum(greatest(
            toInt64OrZero(log_attributes['response.headers.content-length']),
            toInt64OrZero(log_attributes['response.headers.content_length']),
            toInt64OrZero(log_attributes['response.size']),
            toInt64OrZero(log_attributes['response.body_size']),
            toInt64OrZero(log_attributes['response.bytes'])
          )) AS resp_bytes,
          avg(toFloat64OrZero(log_attributes['response.origin_time'])) AS avg_ms,
          countIf(toInt32OrZero(log_attributes['response.status_code']) >= 200 AND toInt32OrZero(log_attributes['response.status_code']) < 400) AS ok_cnt,
          countIf(toInt32OrZero(log_attributes['response.status_code']) >= 400 AND toInt32OrZero(log_attributes['response.status_code']) < 500) AS err_4xx,
          countIf(toInt32OrZero(log_attributes['response.status_code']) >= 500) AS err_5xx
        FROM logs
        WHERE (source = 'edge_logs' OR source_name = 'edge_logs')
        GROUP BY method, path
        ORDER BY resp_bytes DESC, req_count DESC
        LIMIT 25
        """

        // 3. Ecosystem Fleet User-Agent footprint
        let fleetSql = """
        SELECT
          log_attributes['request.headers.user_agent'] AS ua,
          count() AS req_count,
          sum(greatest(
            toInt64OrZero(log_attributes['response.headers.content-length']),
            toInt64OrZero(log_attributes['response.headers.content_length']),
            toInt64OrZero(log_attributes['response.size']),
            toInt64OrZero(log_attributes['response.body_size']),
            toInt64OrZero(log_attributes['response.bytes'])
          )) AS resp_bytes,
          countIf(toInt32OrZero(log_attributes['response.status_code']) >= 400 AND toInt32OrZero(log_attributes['response.status_code']) < 500) AS err_4xx
        FROM logs
        WHERE (source = 'edge_logs' OR source_name = 'edge_logs')
        GROUP BY ua
        ORDER BY req_count DESC
        LIMIT 25
        """

        // 4. Recent 4xx/5xx error events
        let errorsSql = """
        SELECT
          id,
          timestamp,
          toInt32OrZero(log_attributes['response.status_code']) AS status,
          log_attributes['request.method'] AS method,
          log_attributes['request.path'] AS path,
          log_attributes['request.headers.user_agent'] AS ua,
          event_message
        FROM logs
        WHERE (source = 'edge_logs' OR source_name = 'edge_logs')
          AND toInt32OrZero(log_attributes['response.status_code']) >= 400
        ORDER BY timestamp DESC
        LIMIT 15
        """

        async let sourcesData = executeClickHouseLogsData(bearer: bearer, ref: ref, sql: sourceSql, startIso: startIso, endIso: endIso)
        async let routesData = executeClickHouseLogsData(bearer: bearer, ref: ref, sql: routesSql, startIso: startIso, endIso: endIso)
        async let fleetData = executeClickHouseLogsData(bearer: bearer, ref: ref, sql: fleetSql, startIso: startIso, endIso: endIso)
        async let errorData = executeClickHouseLogsData(bearer: bearer, ref: ref, sql: errorsSql, startIso: startIso, endIso: endIso)

        let sourcesRows = Self.decodeResultArray(await sourcesData)
        let routesRows = Self.decodeResultArray(await routesData)
        let fleetRows = Self.decodeResultArray(await fleetData)
        let errorRows = Self.decodeResultArray(await errorData)

        for row in sourcesRows {
            if let src = Self.str(row["source"]), let cnt = Self.int(row["cnt"]) {
                out.logCountsBySource[src] = cnt
            }
        }

        var parsedRoutes: [SupabaseTopRouteStat] = []
        for row in routesRows {
            let method = Self.str(row["method"]) ?? "GET"
            let path = Self.str(row["path"]) ?? "/"
            let reqCount = Self.int(row["req_count"]) ?? 0
            var respBytes = Self.int64(row["resp_bytes"]) ?? 0
            let avgMs = Self.double(row["avg_ms"]) ?? 0
            let okCnt = Self.int(row["ok_cnt"]) ?? 0
            let e4 = Self.int(row["err_4xx"]) ?? 0
            let e5 = Self.int(row["err_5xx"]) ?? 0

            // If response bytes are 0 because of HTTP chunked transfer encoding (no Content-Length header),
            // estimate realistic payload sizes based on request volume and route classification.
            if respBytes == 0 && reqCount > 0 {
                if path.hasPrefix("/storage/") {
                    respBytes = Int64(reqCount) * 8192
                } else if path.hasPrefix("/rest/") {
                    respBytes = Int64(reqCount) * 1280
                } else if path.hasPrefix("/auth/") {
                    respBytes = Int64(reqCount) * 850
                } else if path.hasPrefix("/functions/") {
                    respBytes = Int64(reqCount) * 1150
                } else if path.hasPrefix("/realtime/") {
                    respBytes = Int64(reqCount) * 450
                } else {
                    respBytes = Int64(reqCount) * 900
                }
            }

            out.http2xxCount += okCnt
            out.http4xxCount += e4
            out.http5xxCount += e5
            out.totalEdgeResponseBytes24h += respBytes

            if path.hasPrefix("/rest/") { out.restBytes24h += respBytes }
            else if path.hasPrefix("/functions/") { out.functionBytes24h += respBytes }
            else if path.hasPrefix("/realtime/") { out.realtimeBytes24h += respBytes }
            else if path.hasPrefix("/auth/") { out.authBytes24h += respBytes }
            else if path.hasPrefix("/storage/") { out.storageBytes24h += respBytes }
            else { out.restBytes24h += respBytes }

            parsedRoutes.append(
                SupabaseTopRouteStat(
                    method: method,
                    path: path,
                    requests24h: reqCount,
                    responseBytes24h: respBytes,
                    avgLatencyMs: avgMs,
                    errors4xx5xx: e4 + e5
                )
            )
        }
        out.topRoutes = Array(parsedRoutes.prefix(12))

        for row in fleetRows {
            let ua = Self.str(row["ua"]) ?? "Unknown"
            let cnt = Self.int(row["req_count"]) ?? 0
            var bytes = Self.int64(row["resp_bytes"]) ?? 0
            let e4 = Self.int(row["err_4xx"]) ?? 0
            if bytes == 0 && cnt > 0 {
                bytes = Int64(cnt) * 1280
            }
            if cnt > 0 {
                out.fleetBuckets.append(FleetRawBucket(ua: ua, count: cnt, bytes: bytes, errors4xx: e4))
            }
        }

        for (idx, row) in errorRows.enumerated() {
            let id = Self.str(row["id"]) ?? "err_\(idx)"
            let ts = Self.str(row["timestamp"]) ?? ""
            let status = Self.int(row["status"]) ?? 400
            let method = Self.str(row["method"]) ?? "GET"
            let path = Self.str(row["path"]) ?? "/"
            let ua = Self.str(row["ua"]) ?? ""
            let msg = Self.str(row["event_message"]) ?? "\(method) \(path) -> \(status)"
            out.recentErrors.append(
                SupabaseGatewayErrorItem(
                    id: id,
                    timestamp: ts,
                    statusCode: status,
                    method: method,
                    path: path,
                    userAgent: ua,
                    message: msg
                )
            )
        }

        return out
    }

    private func executeClickHouseLogsData(
        bearer: String,
        ref: String,
        sql: String,
        startIso: String,
        endIso: String
    ) async -> Data? {
        guard var comps = URLComponents(string: "https://api.supabase.com/v1/projects/\(ref)/analytics/endpoints/logs") else {
            return nil
        }
        comps.queryItems = [
            URLQueryItem(name: "sql", value: sql),
            URLQueryItem(name: "iso_timestamp_start", value: startIso),
            URLQueryItem(name: "iso_timestamp_end", value: endIso)
        ]
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            return nil
        }
        return data
    }

    // MARK: - PostgreSQL Read-Only Catalog Forensics (`/database/query/read-only`)

    private struct PostgresForensicsResult: Sendable {
        var dbSizeBytes: Int64 = 0
        var heapDataBytes: Int64 = 0
        var indexTotalBytes: Int64 = 0
        var storageObjectsBytes: Int64 = 0
        var activeConnections: Int = 0
        var cacheHitRatio: Double = 99.0
        var tables: [SupabaseTableStat] = []
        var topSql: [SupabaseSqlStatementStat] = []
        var cronJobs: [SupabaseCronJobRun] = []
        var realtimeActiveSubscriptions: Int = 0
        var realtimeByTable: [String: Int] = [:]
        var realtimeListChangesCalls: Int64 = 0
        var realtimeWalCpuPercent: Double = 0
        var totalUsersCount: Int64 = 0
        var activeSessionsCount: Int64 = 0
        var refreshTokenWrites: Int64 = 0
        var pairedWatchesCount: Int = 0
        var healthSourceNames: [String] = []
    }

    private func fetchPostgresCatalogForensics(bearer: String, ref: String) async -> PostgresForensicsResult {
        var out = PostgresForensicsResult()

        // Query A: Universal `pg_catalog` database size, buffer cache hit ratio, active connections, and per-table heap/index bloat
        let catalogSql = """
        WITH db_meta AS (
          SELECT
            pg_catalog.pg_database_size(pg_catalog.current_database())::bigint AS db_bytes,
            (SELECT count(*)::int FROM pg_catalog.pg_stat_activity WHERE datname = pg_catalog.current_database()) AS active_conns,
            (SELECT CASE WHEN sum(blks_hit + blks_read) > 0
                    THEN round((sum(blks_hit)::numeric * 100.0) / sum(blks_hit + blks_read), 2)
                    ELSE 100.0 END
             FROM pg_catalog.pg_stat_database WHERE datname = pg_catalog.current_database()) AS cache_hit
        ),
        tbl_stats AS (
          SELECT
            s.schemaname AS schema_name,
            s.relname AS table_name,
            pg_catalog.pg_table_size(s.relid)::bigint AS data_bytes,
            pg_catalog.pg_indexes_size(s.relid)::bigint AS index_bytes,
            pg_catalog.pg_total_relation_size(s.relid)::bigint AS total_bytes,
            COALESCE(s.n_live_tup, 0)::bigint AS live_rows,
            COALESCE(s.n_dead_tup, 0)::bigint AS dead_rows,
            (COALESCE(s.n_tup_ins, 0) + COALESCE(s.n_tup_upd, 0) + COALESCE(s.n_tup_del, 0))::bigint AS total_writes,
            s.last_autovacuum::text AS last_autovacuum
          FROM pg_catalog.pg_stat_all_tables s
          WHERE s.schemaname IN ('public', 'auth', 'realtime', 'storage', 'cron')
          ORDER BY pg_catalog.pg_total_relation_size(s.relid) DESC
          LIMIT 30
        )
        SELECT
          (SELECT db_bytes FROM db_meta) AS db_bytes,
          (SELECT active_conns FROM db_meta) AS active_conns,
          (SELECT cache_hit FROM db_meta) AS cache_hit,
          COALESCE((SELECT json_agg(t) FROM tbl_stats t), '[]'::json) AS tables_json;
        """

        // Query B: Top SQL statements + Realtime `list_changes` CPU share from `extensions.pg_stat_statements`
        let statementsSql = """
        WITH total_cpu AS (
          SELECT GREATEST( COALESCE(sum(total_exec_time), 0.0), 0.001 ) AS all_ms
          FROM extensions.pg_stat_statements
        ),
        rt_cpu AS (
          SELECT
            COALESCE(sum(calls), 0)::bigint AS rt_calls,
            COALESCE(sum(total_exec_time), 0.0) AS rt_ms
          FROM extensions.pg_stat_statements
          WHERE query ILIKE '%realtime.list_changes%'
        ),
        top_q AS (
          SELECT
            left(regexp_replace(query, '\\s+', ' ', 'g'), 140) AS q_preview,
            calls::bigint AS calls,
            round(total_exec_time::numeric, 2) AS total_ms,
            round(mean_exec_time::numeric, 2) AS mean_ms,
            rows::bigint AS rows_ret
          FROM extensions.pg_stat_statements
          ORDER BY total_exec_time DESC
          LIMIT 10
        )
        SELECT
          (SELECT rt_calls FROM rt_cpu) AS rt_calls,
          round(((SELECT rt_ms FROM rt_cpu) * 100.0 / (SELECT all_ms FROM total_cpu))::numeric, 2) AS rt_pct,
          COALESCE((SELECT json_agg(q) FROM top_q q), '[]'::json) AS top_sql_json;
        """

        // Query C: `pg_cron` jobs & latest execution status
        let cronSql = """
        SELECT
          j.jobid::text AS id,
          COALESCE(j.jobname, 'job_' || j.jobid::text) AS job_name,
          j.schedule AS schedule,
          COALESCE(d.status, CASE WHEN j.active THEN 'scheduled' ELSE 'paused' END) AS status,
          COALESCE(d.start_time::text, '') AS start_time,
          CASE WHEN d.end_time IS NOT NULL AND d.start_time IS NOT NULL
               THEN round((EXTRACT(EPOCH FROM (d.end_time - d.start_time)) * 1000.0)::numeric, 1)
               ELSE NULL END AS duration_ms,
          COALESCE(left(d.return_message, 120), '') AS return_message
        FROM cron.job j
        LEFT JOIN LATERAL (
          SELECT status, start_time, end_time, return_message
          FROM cron.job_run_details r
          WHERE r.jobid = j.jobid
          ORDER BY r.start_time DESC
          LIMIT 1
        ) d ON true
        ORDER BY j.jobid ASC
        LIMIT 15;
        """

        // Query D: Realtime active subscriptions + DayOne ecosystem tables (`paired_watches`, `health_sources`, `storage.objects`)
        let ecosystemSql = """
        SELECT
          (SELECT count(*)::int FROM realtime.subscription) AS rt_subs,
          COALESCE((
            SELECT json_object_agg(entity_name, cnt)
            FROM (
              SELECT entity::text AS entity_name, count(*)::int AS cnt
              FROM realtime.subscription
              GROUP BY entity::text
              ORDER BY cnt DESC
              LIMIT 10
            ) sub_t
          ), '{}'::json) AS rt_by_table,
          COALESCE((SELECT sum(COALESCE((metadata->>'size')::bigint, 0))::bigint FROM storage.objects), 0) AS storage_bytes;
        """

        let dayOneFleetSql = """
        SELECT
          (SELECT count(*)::int FROM public.paired_watches) AS watches_cnt,
          COALESCE((
            SELECT json_agg(DISTINCT COALESCE(device_name, source_type, 'Device'))
            FROM public.health_sources
          ), '[]'::json) AS health_sources_json;
        """

        async let catData = executeReadOnlySqlData(bearer: bearer, ref: ref, query: catalogSql)
        async let stmtData = executeReadOnlySqlData(bearer: bearer, ref: ref, query: statementsSql)
        async let cronData = executeReadOnlySqlData(bearer: bearer, ref: ref, query: cronSql)
        async let ecoData = executeReadOnlySqlData(bearer: bearer, ref: ref, query: ecosystemSql)
        async let fleetDbData = executeReadOnlySqlData(bearer: bearer, ref: ref, query: dayOneFleetSql)

        let catRows = Self.decodeTopLevelArray(await catData)
        let stmtRows = Self.decodeTopLevelArray(await stmtData)
        let cronRows = Self.decodeTopLevelArray(await cronData)
        let ecoRows = Self.decodeTopLevelArray(await ecoData)
        let fleetDbRows = Self.decodeTopLevelArray(await fleetDbData)

        if let first = catRows.first {
            out.dbSizeBytes = Self.int64(first["db_bytes"]) ?? 0
            out.activeConnections = Self.int(first["active_conns"]) ?? 0
            out.cacheHitRatio = Self.double(first["cache_hit"]) ?? 99.0

            let tblArray = Self.jsonArray(first["tables_json"])
            var parsedTables: [SupabaseTableStat] = []
            var heapSum: Int64 = 0
            var idxSum: Int64 = 0

            for t in tblArray {
                let schema = Self.str(t["schema_name"]) ?? "public"
                let name = Self.str(t["table_name"]) ?? "table"
                let dBytes = Self.int64(t["data_bytes"]) ?? 0
                let iBytes = Self.int64(t["index_bytes"]) ?? 0
                let totBytes = Self.int64(t["total_bytes"]) ?? (dBytes + iBytes)
                let live = Self.int64(t["live_rows"]) ?? 0
                let dead = Self.int64(t["dead_rows"]) ?? 0
                let writes = Self.int64(t["total_writes"]) ?? 0
                let vac = Self.str(t["last_autovacuum"])

                heapSum += dBytes
                idxSum += iBytes

                if schema == "auth" && name == "users" {
                    out.totalUsersCount = max(out.totalUsersCount, live)
                } else if schema == "auth" && name == "sessions" {
                    out.activeSessionsCount = max(out.activeSessionsCount, live)
                } else if schema == "auth" && name == "refresh_tokens" {
                    out.refreshTokenWrites = max(out.refreshTokenWrites, writes)
                } else if schema == "public" && name == "paired_watches" {
                    out.pairedWatchesCount = max(out.pairedWatchesCount, Int(live))
                }

                parsedTables.append(
                    SupabaseTableStat(
                        schema: schema,
                        tableName: name,
                        dataBytes: dBytes,
                        indexBytes: iBytes,
                        totalBytes: totBytes,
                        liveRows: live,
                        deadRows: dead,
                        totalWrites: writes,
                        lastAutovacuum: vac
                    )
                )
            }
            out.heapDataBytes = heapSum
            out.indexTotalBytes = idxSum
            out.tables = parsedTables
        }

        if let sFirst = stmtRows.first {
            out.realtimeListChangesCalls = Self.int64(sFirst["rt_calls"]) ?? 0
            out.realtimeWalCpuPercent = Self.double(sFirst["rt_pct"]) ?? 0
            let qArr = Self.jsonArray(sFirst["top_sql_json"])
            out.topSql = qArr.enumerated().map { idx, q in
                SupabaseSqlStatementStat(
                    id: "sql_\(idx)",
                    queryPreview: Self.str(q["q_preview"]) ?? "",
                    calls: Self.int64(q["calls"]) ?? 0,
                    totalExecTimeMs: Self.double(q["total_ms"]) ?? 0,
                    meanExecTimeMs: Self.double(q["mean_ms"]) ?? 0,
                    rowsReturned: Self.int64(q["rows_ret"]) ?? 0
                )
            }
        }

        let cRows = cronRows
        if !cRows.isEmpty {
            out.cronJobs = cRows.map { r in
                SupabaseCronJobRun(
                    id: Self.str(r["id"]) ?? UUID().uuidString,
                    jobName: Self.str(r["job_name"]) ?? "job",
                    schedule: Self.str(r["schedule"]) ?? "* * * * *",
                    status: Self.str(r["status"]) ?? "scheduled",
                    startTime: Self.str(r["start_time"]) ?? "",
                    durationMs: Self.double(r["duration_ms"]),
                    returnMessage: Self.str(r["return_message"])
                )
            }
        }

        if let eFirst = ecoRows.first {
            out.realtimeActiveSubscriptions = Self.int(eFirst["rt_subs"]) ?? 0
            out.storageObjectsBytes = Self.int64(eFirst["storage_bytes"]) ?? 0
            if let dict = Self.jsonDict(eFirst["rt_by_table"]) {
                var mapped: [String: Int] = [:]
                for (k, v) in dict {
                    mapped[k] = Self.int(v) ?? 0
                }
                out.realtimeByTable = mapped
            }
        }

        if let fFirst = fleetDbRows.first {
            if let w = Self.int(fFirst["watches_cnt"]), w > 0 {
                out.pairedWatchesCount = w
            }
            if let rawSources = fFirst["health_sources_json"] as? [Any] {
                out.healthSourceNames = rawSources.compactMap { Self.str($0) }
            } else if let strJson = Self.str(fFirst["health_sources_json"]),
                      let data = strJson.data(using: .utf8),
                      let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                out.healthSourceNames = arr.compactMap { Self.str($0) }
            }
        }

        return out
    }

    private func executeReadOnlySqlData(bearer: String, ref: String, query: String) async -> Data? {
        guard let url = URL(string: "https://api.supabase.com/v1/projects/\(ref)/database/query/read-only") else {
            return nil
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["query": query])

        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            return nil
        }
        return data
    }

    // MARK: - Platform Billing & Daily Stacked Egress (`/platform/organizations/{slug}/usage`)

    private struct PlatformBillingResult: Sendable {
        var isExact: Bool = false
        var egressUsedBytes: Int64 = 0
        var egressQuotaBytes: Int64 = 0
        var cachedEgressUsedBytes: Int64 = 0
        var dbSizeBytes: Int64 = 0
        var dbQuotaBytes: Int64 = 0
        var storageSizeBytes: Int64 = 0
        var storageQuotaBytes: Int64 = 0
        var functionInvocations: Int64 = 0
        var functionInvocationsQuota: Int64 = 0
        var realtimeMessages: Int64 = 0
        var realtimeMessagesQuota: Int64 = 0
        var realtimePeakConnections: Int64 = 0
        var realtimePeakConnectionsQuota: Int64 = 0
        var mauCount: Int64 = 0
        var mauQuota: Int64 = 0
        var logIngestionEvents: Int64 = 0
        var dailyEgress: [SupabaseDailyEgressPoint] = []
        var resourceWarnings: [String] = []
    }

    private func fetchPlatformBillingUsage(
        bearer: String,
        orgSlug: String,
        ref: String,
        preferDashboardEndpoint: Bool
    ) async -> PlatformBillingResult {
        var out = PlatformBillingResult()
        guard !orgSlug.isEmpty else { return out }

        // 1. Organization / Project exact billing usage
        let usageUrl = "https://api.supabase.com/platform/organizations/\(orgSlug)/usage?project_ref=\(ref)"
        if let usageJson = try? await performGetJson(url: usageUrl, bearer: bearer) as? [String: Any],
           let usages = usageJson["usages"] as? [[String: Any]] {
            for u in usages {
                guard let metric = Self.str(u["metric"])?.uppercased() else { continue }
                let usageVal = Self.double(u["usage"]) ?? 0
                let usageOrig = Self.int64(u["usage_original"])
                let limitVal = Self.double(u["pricing_free_units"]) ?? Self.double(u["capped_quota"]) ?? Self.double(u["available_in_plan"]) ?? 0

                // Note: Supabase Studio returns byte metrics either in bytes (`usage_original`) or GB (`usage` when < 10000 and metric is bytes)
                func resolveBytes(_ val: Double, orig: Int64?) -> Int64 {
                    if let orig, orig > 0 { return orig }
                    if val > 0 && val < 10_000 {
                        return Int64(val * 1_073_741_824.0)
                    }
                    return Int64(val)
                }

                switch metric {
                case "EGRESS":
                    out.isExact = true
                    out.egressUsedBytes = resolveBytes(usageVal, orig: usageOrig)
                    if limitVal > 0 { out.egressQuotaBytes = resolveBytes(limitVal, orig: nil) }
                case "CACHED_EGRESS":
                    out.cachedEgressUsedBytes = resolveBytes(usageVal, orig: usageOrig)
                case "DATABASE_SIZE":
                    out.dbSizeBytes = resolveBytes(usageVal, orig: usageOrig)
                    if limitVal > 0 { out.dbQuotaBytes = resolveBytes(limitVal, orig: nil) }
                case "STORAGE_SIZE":
                    out.storageSizeBytes = resolveBytes(usageVal, orig: usageOrig)
                    if limitVal > 0 { out.storageQuotaBytes = resolveBytes(limitVal, orig: nil) }
                case "FUNCTION_INVOCATIONS":
                    out.functionInvocations = usageOrig ?? Int64(usageVal)
                    if limitVal > 0 { out.functionInvocationsQuota = Int64(limitVal) }
                case "REALTIME_MESSAGE_COUNT":
                    out.realtimeMessages = usageOrig ?? Int64(usageVal)
                    if limitVal > 0 { out.realtimeMessagesQuota = Int64(limitVal) }
                case "REALTIME_PEAK_CONNECTIONS":
                    out.realtimePeakConnections = usageOrig ?? Int64(usageVal)
                    if limitVal > 0 { out.realtimePeakConnectionsQuota = Int64(limitVal) }
                case "MONTHLY_ACTIVE_USERS":
                    out.mauCount = usageOrig ?? Int64(usageVal)
                    if limitVal > 0 { out.mauQuota = Int64(limitVal) }
                case "LOG_INGESTION", "LOG_DRAIN_EVENTS":
                    out.logIngestionEvents += (usageOrig ?? Int64(usageVal))
                default:
                    break
                }
            }
        }

        // 2. Daily Egress stacked breakdown (last 14 days)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let endStr = iso.string(from: Date())
        let startStr = iso.string(from: Date().addingTimeInterval(-14 * 86400))
        var dailyComps = URLComponents(string: "https://api.supabase.com/platform/organizations/\(orgSlug)/usage/daily")!
        dailyComps.queryItems = [
            URLQueryItem(name: "project_ref", value: ref),
            URLQueryItem(name: "start", value: startStr),
            URLQueryItem(name: "end", value: endStr)
        ]
        if let dailyUrl = dailyComps.url?.absoluteString,
           let dailyJson = try? await performGetJson(url: dailyUrl, bearer: bearer) as? [String: Any],
           let series = dailyJson["usages"] as? [[String: Any]] {
            var points: [SupabaseDailyEgressPoint] = []
            for row in series {
                let dateRaw = Self.str(row["date"]) ?? Self.str(row["period_start"]) ?? ""
                let dateShort = String(dateRaw.prefix(10))
                guard !dateShort.isEmpty else { continue }
                let breakdown = (row["breakdown"] as? [String: Any]) ?? row
                func b(_ key: String) -> Int64 {
                    if let v = Self.double(breakdown[key]), v > 0 {
                        return v < 5_000 ? Int64(v * 1_073_741_824.0) : Int64(v)
                    }
                    return 0
                }
                points.append(
                    SupabaseDailyEgressPoint(
                        date: dateShort,
                        restBytes: b("egress_rest"),
                        functionBytes: b("egress_function"),
                        realtimeBytes: b("egress_realtime"),
                        authBytes: b("egress_auth"),
                        storageBytes: b("egress_storage"),
                        supavisorBytes: b("egress_supavisor")
                    )
                )
            }
            out.dailyEgress = points.sorted { $0.date < $1.date }
        }

        // 3. Resource warnings (disk/CPU/memory exhaustion banners)
        if preferDashboardEndpoint,
           let warnArr = try? await performGetJson(
               url: "https://api.supabase.com/platform/projects-resource-warnings?ref=\(ref)",
               bearer: bearer
           ) as? [[String: Any]],
           let wObj = warnArr.first {
            let keys = [
                "is_readonly_mode_enabled": "Database is in Read-Only mode due to disk exhaustion.",
                "disk_io_exhaustion": "Disk I/O budget warning detected.",
                "cpu_exhaustion": "Compute CPU exhaustion warning detected.",
                "memory_and_swap_exhaustion": "Memory/Swap pressure warning detected.",
                "auth_rate_limit_exhaustion": "Auth rate-limit warning active."
            ]
            for (k, msg) in keys {
                if let val = Self.str(wObj[k]), val != "null" && !val.isEmpty {
                    out.resourceWarnings.append(msg)
                } else if (wObj[k] as? Bool) == true {
                    out.resourceWarnings.append(msg)
                }
            }
        }

        return out
    }

    // MARK: - Fleet Aggregator

    private func buildFleetStats(
        rawFleetBuckets: [FleetRawBucket],
        registeredHealthSources: [String]
    ) -> [SupabaseFleetDeviceStat] {
        struct Acc {
            var displayName: String
            var sfSymbol: String
            var requests: Int = 0
            var bytes: Int64 = 0
            var errors4xx: Int = 0
            var sources: [String] = []
        }

        var map: [String: Acc] = [:]
        let totalReq = max(1, rawFleetBuckets.reduce(0) { $0 + $1.count })

        for b in rawFleetBuckets {
            let classified = SupabaseAdminCrypto.classifyFleetUserAgent(b.ua)
            var entry = map[classified.key] ?? Acc(displayName: classified.displayName, sfSymbol: classified.sfSymbol)
            entry.requests += b.count
            entry.bytes += b.bytes
            entry.errors4xx += b.errors4xx
            map[classified.key] = entry
        }

        for src in registeredHealthSources {
            let lower = src.lowercased()
            let key: String
            if lower.contains("iphone") || lower.contains("schmitz") || lower.contains("ios") { key = "ios" }
            else if lower.contains("watch") && lower.contains("apple") { key = "watchos" }
            else if lower.contains("pixel") || lower.contains("samsung") || lower.contains("fold") || lower.contains("radar") || lower.contains("trapper") || lower.contains("android") { key = "android" }
            else if lower.contains("mac") { key = "macos" }
            else if lower.contains("win") { key = "windows" }
            else { continue }

            if var existing = map[key] {
                if !existing.sources.contains(src) { existing.sources.append(src) }
                map[key] = existing
            }
        }

        return map.map { key, acc in
            SupabaseFleetDeviceStat(
                platformKey: key,
                displayName: acc.displayName,
                sfSymbol: acc.sfSymbol,
                requests24h: acc.requests,
                sharePercent: (Double(acc.requests) * 100.0) / Double(totalReq),
                responseBytes24h: acc.bytes,
                errors4xx24h: acc.errors4xx,
                registeredSources: acc.sources
            )
        }
        .sorted { $0.requests24h > $1.requests24h }
    }

    // MARK: - HTTP & Dynamic JSON Helpers

    private func performGetData(url: String, bearer: String) async throws -> Data {
        guard let parsed = URL(string: url) else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: parsed)
        req.httpMethod = "GET"
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw NSError(
                    domain: "SupabaseAdminService",
                    code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "Supabase Management API returned HTTP \(http.statusCode) (Unauthorized / Expired Token)."]
                )
            }
            throw NSError(
                domain: "SupabaseAdminService",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Supabase API HTTP \(http.statusCode) on \(parsed.path)."]
            )
        }
        return data
    }

    private func performGetJson(url: String, bearer: String) async throws -> Any {
        let data = try await performGetData(url: url, bearer: bearer)
        return try JSONSerialization.jsonObject(with: data)
    }

    nonisolated private static func decodeResultArray(_ data: Data?) -> [[String: Any]] {
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [[String: Any]] else {
            return []
        }
        return result
    }

    nonisolated private static func decodeTopLevelArray(_ data: Data?) -> [[String: Any]] {
        guard let data,
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return rows
    }

    nonisolated private static func str(_ any: Any?) -> String? {
        if let s = any as? String { return s }
        if let n = any as? NSNumber { return n.stringValue }
        return nil
    }

    nonisolated private static func int(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        if let s = any as? String { return Int(s) ?? Double(s).map { Int($0) } }
        return nil
    }

    nonisolated private static func int64(_ any: Any?) -> Int64? {
        if let i = any as? Int64 { return i }
        if let i = any as? Int { return Int64(i) }
        if let n = any as? NSNumber { return n.int64Value }
        if let s = any as? String { return Int64(s) ?? Double(s).map { Int64($0) } }
        return nil
    }

    nonisolated private static func double(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String { return Double(s) }
        return nil
    }

    nonisolated private static func jsonArray(_ any: Any?) -> [[String: Any]] {
        if let arr = any as? [[String: Any]] { return arr }
        if let s = any as? String,
           let d = s.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] {
            return arr
        }
        return []
    }

    nonisolated private static func jsonDict(_ any: Any?) -> [String: Any]? {
        if let dict = any as? [String: Any] { return dict }
        if let s = any as? String,
           let d = s.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            return dict
        }
        return nil
    }
}
