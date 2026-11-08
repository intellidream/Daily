import Foundation
import LocalAuthentication
#if canImport(WebKit) && (os(iOS) || os(macOS))
import WebKit
#endif
#if !os(macOS)
import Security
#endif

/// Centralized, strictly read-only Cloud Observability & Admin Telemetry service for Supabase.
///
/// Architectural guarantees:
/// 1. Zero idle background polling — network queries execute ONLY when the Admin Console is opened (30-min TTL) or explicitly refreshed.
/// 2. Zero-Log-Query by default — opening or refreshing the console executes ZERO ClickHouse analytics queries (`0 B` Log Query); detailed `edge_logs` scanning runs strictly On-Demand via a single-pass query.
/// 3. Zero mutating API/SQL calls — strictly GET telemetry endpoints and `/database/query/read-only`.
/// 4. Strict local credential isolation — `GroupDefaults` on macOS (zero Keychain prompts), `ThisDeviceOnly` Keychain on iOS; NEVER synced to cloud `user_settings`.
@MainActor
public final class SupabaseAdminService: ObservableObject {
    public static let shared = SupabaseAdminService()

    nonisolated public static let defaultProjectRef = "akkfouifxztnfwwiclwg"
    private static let credentialsStorageKey = "com.intellidream.daily.supabase.admin.credentials.v1"
    private static let snapshotCacheKeyPrefix = "com.intellidream.daily.supabase.admin.snapshot.v3."
    nonisolated public static let cacheTtlSeconds: TimeInterval = 1800 // 30 minutes

    @Published public private(set) var credentials: SupabaseAdminCredentials
    @Published public private(set) var snapshot: SupabaseAdminSnapshot?
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var isScanningGatewayLogs: Bool = false
    @Published public private(set) var isAuthenticating: Bool = false
    @Published public private(set) var isAnalyzingAI: Bool = false
    @Published public private(set) var aiAnalysis: String?
    @Published public var errorMessage: String?
    @Published public private(set) var isUnlockedInMemory: Bool = false

    private let session: URLSession
    private var didAttemptWebKitSessionRecovery: Bool = false

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
              let data = raw.data(using: .utf8),
              let snap = try? JSONDecoder().decode(SupabaseAdminSnapshot.self, from: data) else {
            return nil
        }
        // Reject corrupted snapshots where 24h gateway egress mistakenly equaled the full billing cycle total
        if snap.egress24hBytes >= snap.egressUsedBytes && snap.egressUsedBytes > 500_000_000 {
            return nil
        }
        return snap
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
        self.didAttemptWebKitSessionRecovery = false
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
        self.didAttemptWebKitSessionRecovery = false
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
        didAttemptWebKitSessionRecovery = false
    }

    // MARK: - Dashboard Session Refresh & Silent WebKit Recovery

    /// Ensures we hold a non-expired GoTrue Dashboard JWT (`eyJ...`) for `/platform/organizations/{slug}/usage`.
    /// 1. Returns existing `dashboardAccessToken` if valid and not expiring within 2 minutes.
    /// 2. Exchanges `dashboardRefreshToken` via `POST https://auth.supabase.io/auth/v1/token?grant_type=refresh_token`.
    /// 3. On iOS/macOS, if `dashboardRefreshToken` was missed during an earlier WebView login, silently recovers
    ///    `localStorage['supabase.dashboard.auth.token']` from `WKWebsiteDataStore.default()` and refreshes it.
    private func ensureFreshDashboardBearer(forceRefresh: Bool = false) async -> String? {
        if !forceRefresh,
           let existing = credentials.dashboardAccessToken?.trimmingCharacters(in: .whitespacesAndNewlines),
           !existing.isEmpty,
           !SupabaseAdminCrypto.isJwtExpiredOrExpiringSoon(existing) {
            return existing
        }

        if let refreshTok = credentials.dashboardRefreshToken?.trimmingCharacters(in: .whitespacesAndNewlines),
           !refreshTok.isEmpty,
           let refreshed = await refreshGoTrueDashboardSession(refreshToken: refreshTok) {
            credentials.dashboardAccessToken = refreshed.accessToken
            if let newRef = refreshed.refreshToken, !newRef.isEmpty {
                credentials.dashboardRefreshToken = newRef
            }
            if credentials.adminIdentity == nil, let id = refreshed.identity {
                credentials.adminIdentity = id
            }
            Self.saveCredentialsToLocalStorage(credentials)
            return refreshed.accessToken
        }

        #if canImport(WebKit) && (os(iOS) || os(macOS))
        if !didAttemptWebKitSessionRecovery {
            didAttemptWebKitSessionRecovery = true
            let harvester = WebKitDashboardSessionHarvester()
            if let rawJson = await harvester.harvest() {
                let parsed = SupabaseAdminCrypto.parseDashboardSessionJson(rawJson)
                if let recoveredRef = parsed.refreshToken, !recoveredRef.isEmpty {
                    credentials.dashboardRefreshToken = recoveredRef
                }
                if credentials.adminIdentity == nil, let id = parsed.identity {
                    credentials.adminIdentity = id
                }
                if let recoveredAcc = parsed.accessToken,
                   !SupabaseAdminCrypto.isJwtExpiredOrExpiringSoon(recoveredAcc) {
                    credentials.dashboardAccessToken = recoveredAcc
                    Self.saveCredentialsToLocalStorage(credentials)
                    return recoveredAcc
                }
                if let recoveredRef = parsed.refreshToken,
                   let refreshed = await refreshGoTrueDashboardSession(refreshToken: recoveredRef) {
                    credentials.dashboardAccessToken = refreshed.accessToken
                    if let newRef = refreshed.refreshToken, !newRef.isEmpty {
                        credentials.dashboardRefreshToken = newRef
                    }
                    Self.saveCredentialsToLocalStorage(credentials)
                    return refreshed.accessToken
                }
                if let recoveredAcc = parsed.accessToken, !recoveredAcc.isEmpty {
                    credentials.dashboardAccessToken = recoveredAcc
                    Self.saveCredentialsToLocalStorage(credentials)
                    return recoveredAcc
                }
            }
        }
        #endif

        if let fallbackExisting = credentials.dashboardAccessToken?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fallbackExisting.isEmpty {
            return fallbackExisting
        }
        return nil
    }

    private func refreshGoTrueDashboardSession(
        refreshToken: String
    ) async -> (accessToken: String, refreshToken: String?, identity: String?)? {
        guard let url = URL(string: "https://auth.supabase.io/auth/v1/token?grant_type=refresh_token") else {
            return nil
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 10.0
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])

        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let raw = String(data: data, encoding: .utf8) else {
            return nil
        }
        let parsed = SupabaseAdminCrypto.parseDashboardSessionJson(raw)
        guard let acc = parsed.accessToken, !acc.isEmpty else { return nil }
        return (acc, parsed.refreshToken, parsed.identity)
    }

    // MARK: - Snapshot Refresh (30-Minute Local Cache + Zero-Log-Query Default Aggregation)

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
        await refreshSnapshot(force: true)
    }

    public func refreshSnapshot(force: Bool = true) async {
        guard credentials.primaryManagementBearer != nil else { return }
        if !force,
           let snap = snapshot,
           snap.project.ref == credentials.selectedProjectRef,
           Date().timeIntervalSince(snap.fetchedAt) < Self.cacheTtlSeconds {
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let freshDashboardBearer = await ensureFreshDashboardBearer(forceRefresh: false)
        guard let mgmtBearer = credentials.primaryManagementBearer else { return }

        let targetRef = credentials.selectedProjectRef
        let primaryPlatform = freshDashboardBearer ?? credentials.primaryPlatformBearer ?? mgmtBearer
        let fallbackPlatform: String? = {
            if let pat = credentials.managementAccessToken?.trimmingCharacters(in: .whitespacesAndNewlines), !pat.isEmpty, pat != primaryPlatform {
                return pat
            }
            if let dash = credentials.dashboardAccessToken?.trimmingCharacters(in: .whitespacesAndNewlines), !dash.isEmpty, dash != primaryPlatform {
                return dash
            }
            return nil
        }()
        let hasDashboardToken = (freshDashboardBearer?.isEmpty == false) || (credentials.dashboardAccessToken?.isEmpty == false)

        do {
            let knownOrgs = await fetchOrganizations(bearer: mgmtBearer)
            let projects = try await fetchProjectsList(bearer: mgmtBearer, knownOrgs: knownOrgs)
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
            let rawOrgSlug = activeProject.organizationSlug.isEmpty
                ? (credentials.selectedOrgSlug ?? "")
                : activeProject.organizationSlug

            let matchedOrg = knownOrgs.first(where: { $0.slug == rawOrgSlug || $0.id == rawOrgSlug }) ?? knownOrgs.first
            let targetOrgSlug: String = (matchedOrg != nil && !matchedOrg!.slug.isEmpty)
                ? matchedOrg!.slug
                : rawOrgSlug

            let orgCreatedAt = matchedOrg?.createdAt
            let projectCreatedAt = activeProject.createdAt

            // Fire strictly Zero-Log-Query control-plane, billing, and consolidated Postgres telemetry requests concurrently.
            // ClickHouse `/analytics/endpoints/*` (`logs`, `usage.api-counts`, `functions.combined-stats`) are NEVER called here (`0 B` Log Query).
            async let orgTask = fetchOrgDetails(bearer: mgmtBearer, orgSlug: targetOrgSlug, fallbackOrg: matchedOrg)
            async let addonsTask = fetchComputeTier(bearer: mgmtBearer, ref: ref)
            async let healthTask = fetchServicesHealth(bearer: mgmtBearer, ref: ref)
            async let diskTask = fetchDiskTelemetry(bearer: mgmtBearer, ref: ref)
            async let functionsTask = fetchEdgeFunctionsTelemetry(bearer: mgmtBearer, ref: ref)
            async let advisorsTask = fetchAdvisors(bearer: mgmtBearer, ref: ref)
            async let pgCatalogTask = fetchPostgresCatalogForensics(bearer: mgmtBearer, ref: ref)
            async let platformUsageTask = fetchPlatformBillingUsage(
                primaryBearer: primaryPlatform,
                fallbackBearer: fallbackPlatform,
                orgSlug: targetOrgSlug,
                ref: ref,
                orgCreatedAt: orgCreatedAt,
                projectCreatedAt: projectCreatedAt,
                preferDashboardEndpoint: hasDashboardToken
            )

            let (orgName, orgPlan) = await orgTask
            let computeTier = await addonsTask
            let serviceHealth = await healthTask
            let diskInfo = await diskTask
            let rawEdgeFunctions = await functionsTask
            let (perfLints, secLints) = await advisorsTask
            let pgData = await pgCatalogTask
            let billingData = await platformUsageTask

            // Preserve any previously scanned On-Demand ClickHouse Gateway Forensics for this project
            let priorSnapshot: SupabaseAdminSnapshot? = {
                if let current = self.snapshot, current.project.ref == ref {
                    return current
                }
                return Self.loadCachedSnapshot(projectRef: ref)
            }()
            let preservedScannedAt = priorSnapshot?.gatewayLogsScannedAt
            let preservedScanWindow = priorSnapshot?.gatewayScanWindowHours
            let hasPriorGatewayScan = priorSnapshot?.hasScannedGatewayLogs == true

            // Plan-aware SI decimal default quotas when exact `/platform/organizations/{slug}/usage` isn't returned (e.g. PAT-only mode)
            let isProOrHigher = ["pro", "team", "enterprise"].contains(orgPlan.lowercased())
            let defaultEgressQuota: Int64 = isProOrHigher ? 250_000_000_000 : 5_000_000_000 // 250 GB vs 5 GB (SI decimal)
            let defaultDbQuota: Int64 = isProOrHigher ? 8_000_000_000 : 500_000_000          // 8 GB vs 0.5 GB (SI decimal)
            let defaultStorageQuota: Int64 = isProOrHigher ? 100_000_000_000 : 1_000_000_000 // 100 GB vs 1 GB (SI decimal)
            let defaultFnQuota: Int64 = isProOrHigher ? 2_000_000 : 500_000
            let defaultRtMsgQuota: Int64 = isProOrHigher ? 5_000_000 : 2_000_000
            let defaultRtPeakQuota: Int64 = isProOrHigher ? 500 : 200
            let defaultMauQuota: Int64 = isProOrHigher ? 100_000 : 50_000

            // Zero-Log-Query 24h Egress resolution from `/platform/organizations/{slug}/usage/daily`:
            // 1. Today's UTC daily bucket (or latest bucket in `dailyEgress` right after UTC midnight)
            // 2. Fallback to preserved 24h On-Demand ClickHouse scan if available
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            df.timeZone = TimeZone(secondsFromGMT: 0)
            let todayStr = df.string(from: Date())
            let candidateDailyBytes = billingData.dailyEgress.first(where: { $0.date == todayStr })?.totalBytes
                ?? billingData.dailyEgress.last?.totalBytes
                ?? 0

            var resolved24hEgress: Int64 = 0
            if candidateDailyBytes > 0 && (billingData.egressUsedBytes == 0 || candidateDailyBytes < billingData.egressUsedBytes || billingData.dailyEgress.count == 1) {
                resolved24hEgress = candidateDailyBytes
            } else if let prior = priorSnapshot, prior.egress24hBytes > 0, (billingData.egressUsedBytes == 0 || prior.egress24hBytes < billingData.egressUsedBytes) {
                resolved24hEgress = prior.egress24hBytes
            }

            // Billing Cycle / Monthly Egress resolution:
            let sumDailyEgressBytes = billingData.dailyEgress.reduce(0) { $0 + $1.totalBytes }
            let resolvedCycleEgress: Int64
            if billingData.isExact && billingData.egressUsedBytes > 0 {
                resolvedCycleEgress = billingData.egressUsedBytes
            } else if sumDailyEgressBytes > 0 {
                resolvedCycleEgress = max(sumDailyEgressBytes, resolved24hEgress)
            } else {
                resolvedCycleEgress = max(billingData.egressUsedBytes, resolved24hEgress)
            }

            let resolvedDbSize = billingData.dbSizeBytes > 0 ? billingData.dbSizeBytes : pgData.dbSizeBytes
            let resolvedFnInvocations = billingData.functionInvocations
            let resolvedMau = billingData.mauCount > 0 ? billingData.mauCount : pgData.totalUsersCount
            let resolvedLogEvents = billingData.logIngestionEvents
            let resolvedRtPeak = billingData.realtimePeakConnections > 0
                ? billingData.realtimePeakConnections
                : Int64(pgData.realtimeActiveSubscriptions)

            // If there is exactly 1 deployed Edge Function and cycle invocations are known from billing, enrich its count cleanly
            let edgeFunctions: [SupabaseEdgeFunctionStat] = rawEdgeFunctions.map { fn in
                if rawEdgeFunctions.count == 1 && fn.invocations24h == 0 && resolvedFnInvocations > 0 {
                    var enriched = fn
                    enriched.invocations24h = Int(min(Int64(Int.max), resolvedFnInvocations))
                    return enriched
                }
                return fn
            }

            // Preserve scanned Fleet stats (enriching registered health sources), or build zero-ClickHouse Fleet from `public.health_sources`
            let fleetDevices: [SupabaseFleetDeviceStat] = {
                if hasPriorGatewayScan, let priorDevices = priorSnapshot?.fleetDevices, !priorDevices.isEmpty {
                    return Self.mergeRegisteredSources(into: priorDevices, registeredHealthSources: pgData.healthSourceNames)
                }
                return buildFleetStats(
                    rawFleetBuckets: [],
                    registeredHealthSources: pgData.healthSourceNames
                )
            }()

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
                billingCyclePeriod: billingData.billingCyclePeriod,
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
                realtimePeakConnections: resolvedRtPeak,
                realtimePeakConnectionsQuota: billingData.realtimePeakConnectionsQuota > 0 ? billingData.realtimePeakConnectionsQuota : defaultRtPeakQuota,
                mauCount: resolvedMau,
                mauQuota: billingData.mauQuota > 0 ? billingData.mauQuota : defaultMauQuota,
                logIngestionBytes: billingData.logIngestionBytes,
                logIngestionQuotaBytes: billingData.logIngestionQuotaBytes > 0 ? billingData.logIngestionQuotaBytes : 1_000_000_000,
                logQueryBytes: billingData.logQueryBytes,
                logQueryQuotaBytes: billingData.logQueryQuotaBytes > 0 ? billingData.logQueryQuotaBytes : 100_000_000_000,
                logIngestionEvents: resolvedLogEvents,
                dailyEgress: billingData.dailyEgress,
                apiCounts24h: priorSnapshot?.apiCounts24h ?? [],
                gatewayLogsScannedAt: preservedScannedAt,
                gatewayScanWindowHours: preservedScanWindow,
                logCountsBySource: hasPriorGatewayScan ? (priorSnapshot?.logCountsBySource ?? [:]) : [:],
                http2xxCount24h: hasPriorGatewayScan ? (priorSnapshot?.http2xxCount24h ?? 0) : 0,
                http4xxCount24h: hasPriorGatewayScan ? (priorSnapshot?.http4xxCount24h ?? 0) : 0,
                http5xxCount24h: hasPriorGatewayScan ? (priorSnapshot?.http5xxCount24h ?? 0) : 0,
                topRoutes24h: hasPriorGatewayScan ? (priorSnapshot?.topRoutes24h ?? []) : [],
                recentErrors24h: hasPriorGatewayScan ? (priorSnapshot?.recentErrors24h ?? []) : [],
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

            if credentials.selectedProjectRef != activeProject.ref || credentials.selectedOrgSlug != targetOrgSlug {
                credentials.selectedProjectRef = activeProject.ref
                credentials.selectedOrgSlug = targetOrgSlug
                Self.saveCredentialsToLocalStorage(credentials)
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    // MARK: - On-Demand Single-Pass ClickHouse Gateway Log Scanner

    /// Explicitly scans `edge_logs` in ClickHouse using a single consolidated SQL pass over `windowHours` (`1`, `6`, or `24`).
    /// Never runs automatically on appear or standard refresh so `Log Query` consumption remains `0 B` unless requested.
    public func scanGatewayLogs(windowHours: Int = 1) async {
        guard !isScanningGatewayLogs else { return }
        let freshDash = await ensureFreshDashboardBearer(forceRefresh: false)
        guard let mgmtBearer = credentials.primaryManagementBearer ?? freshDash else { return }

        if snapshot == nil {
            await refreshSnapshot(force: true)
        }
        guard var currentSnap = snapshot else { return }

        let clampedWindow: Int = (windowHours >= 24) ? 24 : (windowHours >= 6 ? 6 : 1)
        isScanningGatewayLogs = true
        defer { isScanningGatewayLogs = false }

        let parsed = await fetchSinglePassClickHouseLogs(
            bearer: mgmtBearer,
            ref: currentSnap.project.ref,
            windowHours: clampedWindow
        )

        let existingSources = currentSnap.fleetDevices.flatMap(\.registeredSources)
        let updatedFleet = buildFleetStats(
            rawFleetBuckets: parsed.fleetBuckets,
            registeredHealthSources: existingSources
        )

        currentSnap.gatewayLogsScannedAt = Date()
        currentSnap.gatewayScanWindowHours = clampedWindow
        currentSnap.http2xxCount24h = parsed.http2xxCount
        currentSnap.http4xxCount24h = parsed.http4xxCount
        currentSnap.http5xxCount24h = parsed.http5xxCount
        currentSnap.topRoutes24h = parsed.topRoutes
        currentSnap.recentErrors24h = parsed.recentErrors
        currentSnap.logCountsBySource = ["edge_logs": parsed.http2xxCount + parsed.http4xxCount + parsed.http5xxCount]
        if !updatedFleet.isEmpty {
            currentSnap.fleetDevices = updatedFleet
        }
        if clampedWindow == 24 && currentSnap.egress24hBytes == 0 && parsed.totalEdgeResponseBytes24h > 0 {
            currentSnap.egress24hBytes = parsed.totalEdgeResponseBytes24h
        }

        self.snapshot = currentSnap
        Self.saveCachedSnapshot(currentSnap)
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

        // 3. Gateway error rate, Log Query quota & Realtime WAL
        if snapshot.http4xxCount24h + snapshot.http5xxCount24h > 50 || snapshot.errorRate24hPercent > 3.0 {
            bullets.append("- **🛡️ Gateway Error Watch:** Logged **\(snapshot.http4xxCount24h)** `4xx` and **\(snapshot.http5xxCount24h)** `5xx` responses (**\(String(format: "%.1f%%", snapshot.errorRate24hPercent))** error ratio). Inspect stale refresh-token retries or schema column mismatches in the Recent Errors panel.")
        } else if snapshot.logQueryQuotaPercent >= 85.0 {
            bullets.append("- **📊 ClickHouse Log Query Guard (\(String(format: "%.1f%%", snapshot.logQueryQuotaPercent))):** Cycle `Log Query` is **\(SupabaseAdminSnapshot.formatBytes(snapshot.logQueryBytes)) / \(SupabaseAdminSnapshot.formatBytes(snapshot.logQueryQuotaBytes))**. Zero-Log-Query Default Mode is active (`0 B` scanned on open/refresh); trigger On-Demand `1h` scans only when debugging routes.")
        } else if snapshot.realtimeWalCpuSharePercent > 25.0 {
            bullets.append("- **⚡ Realtime WAL Load:** `realtime.list_changes` accounts for **\(String(format: "%.1f%%", snapshot.realtimeWalCpuSharePercent))** of tracked SQL execution across **\(snapshot.realtimeActiveSubscriptions)** active subscriptions. Keep dormant desktop/mobile background tabs unsubscribed.")
        } else {
            let gwDetail = snapshot.hasScannedGatewayLogs
                ? "Gateway error rate is **\(String(format: "%.2f%%", snapshot.errorRate24hPercent))** over **\(snapshot.totalHttpRequests24h)** scanned requests"
                : "Zero-Log-Query mode active (`0 B` ClickHouse overhead)"
            bullets.append("- **⚡ Runtime & Realtime Nominal:** \(gwDetail), with **\(snapshot.realtimeActiveSubscriptions)** active Realtime subscriptions.")
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

    private struct ResolvedOrg: Sendable {
        let id: String
        let slug: String
        let name: String
        let plan: String
        let createdAt: String?
    }

    private func fetchOrganizations(bearer: String) async -> [ResolvedOrg] {
        guard let list = try? await performGetJson(url: "https://api.supabase.com/v1/organizations", bearer: bearer) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { item in
            let slug = Self.str(item["slug"]) ?? Self.str(item["id"]) ?? ""
            guard !slug.isEmpty else { return nil }
            let id = Self.str(item["id"]) ?? slug
            let name = Self.str(item["name"]) ?? slug
            let plan = Self.str(item["plan"]) ?? "free"
            let created = Self.str(item["created_at"])
            return ResolvedOrg(id: id, slug: slug, name: name, plan: plan, createdAt: created)
        }
    }

    private func verifyBearerAndFetchProjects(
        bearer: String,
        fallbackIdentity: String?
    ) async throws -> ([SupabaseProjectSummary], String?) {
        let knownOrgs = await fetchOrganizations(bearer: bearer)
        let projects = try await fetchProjectsList(bearer: bearer, knownOrgs: knownOrgs)
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

    private func fetchProjectsList(bearer: String, knownOrgs: [ResolvedOrg] = []) async throws -> [SupabaseProjectSummary] {
        let raw = try await performGetJson(url: "https://api.supabase.com/v1/projects", bearer: bearer)
        guard let arr = raw as? [[String: Any]] else { return [] }
        return arr.compactMap { item in
            let ref = Self.str(item["id"]) ?? Self.str(item["ref"]) ?? ""
            guard !ref.isEmpty else { return nil }
            let name = Self.str(item["name"]) ?? ref
            let orgId = Self.str(item["organization_id"]) ?? ""
            let matchingOrg = knownOrgs.first(where: { $0.id == orgId || $0.slug == orgId })
            let orgSlug = matchingOrg?.slug ?? Self.str(item["organization_slug"]) ?? orgId
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

    private func fetchOrgDetails(bearer: String, orgSlug: String, fallbackOrg: ResolvedOrg? = nil) async -> (String, String) {
        if !orgSlug.isEmpty,
           let detail = try? await performGetJson(url: "https://api.supabase.com/v1/organizations/\(orgSlug)", bearer: bearer) as? [String: Any] {
            let name = Self.str(detail["name"]) ?? fallbackOrg?.name ?? orgSlug
            let plan = Self.str(detail["plan"]) ?? fallbackOrg?.plan ?? "free"
            return (name, plan)
        }
        if let fallbackOrg {
            return (fallbackOrg.name, fallbackOrg.plan)
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

    private func fetchEdgeFunctionsTelemetry(bearer: String, ref: String) async -> [SupabaseEdgeFunctionStat] {
        // Strictly Control-Plane metadata (`0 B` ClickHouse Log Query).
        // Avoids per-function `/analytics/endpoints/functions.combined-stats` ClickHouse scans.
        guard let list = try? await performGetJson(
            url: "https://api.supabase.com/v1/projects/\(ref)/functions",
            bearer: bearer
        ) as? [[String: Any]] else {
            return []
        }

        return list.compactMap { item in
            guard let id = Self.str(item["id"]),
                  let slug = Self.str(item["slug"]) else { return nil }
            let name = Self.str(item["name"]) ?? slug
            let status = Self.str(item["status"]) ?? "ACTIVE"
            let version = Self.int(item["version"]) ?? 1
            let verifyJwt = (item["verify_jwt"] as? Bool) ?? true
            return SupabaseEdgeFunctionStat(
                id: id,
                slug: slug,
                name: name,
                status: status,
                version: version,
                verifyJwt: verifyJwt,
                invocations24h: 0,
                errors24h: 0,
                avgExecutionMs: 0,
                maxExecutionMs: 0
            )
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

    // MARK: - On-Demand Single-Pass ClickHouse Edge Logs Scanner

    internal struct FleetRawBucket: Sendable {
        let ua: String
        let count: Int
        let bytes: Int64
        let errors4xx: Int
    }

    internal struct LogsForensicsResult: Sendable {
        var logCountsBySource: [String: Int] = [:]
        var http2xxCount: Int = 0
        var http4xxCount: Int = 0
        var http5xxCount: Int = 0
        var totalEdgeResponseBytes24h: Int64 = 0
        var topRoutes: [SupabaseTopRouteStat] = []
        var recentErrors: [SupabaseGatewayErrorItem] = []
        var fleetBuckets: [FleetRawBucket] = []
    }

    /// Single-pass ClickHouse SQL strictly scoped to `WHERE source = 'edge_logs'`, skipping `event_message`
    /// and unfiltered `logs` scans so a single scan reads minimal columnar data.
    nonisolated internal static func buildSinglePassGatewayClickHouseSql() -> String {
        """
        SELECT
          coalesce(nullIf(log_attributes['request.method'], ''), 'GET') AS method,
          coalesce(nullIf(log_attributes['request.path'], ''), '/') AS path,
          coalesce(log_attributes['request.headers.user_agent'], '') AS ua,
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
          countIf(toInt32OrZero(log_attributes['response.status_code']) >= 500) AS err_5xx,
          max(toInt32OrZero(log_attributes['response.status_code'])) AS max_status,
          max(toString(timestamp)) AS last_ts
        FROM logs
        WHERE source = 'edge_logs'
        GROUP BY method, path, ua
        ORDER BY resp_bytes DESC, req_count DESC
        LIMIT 100
        """
    }

    nonisolated internal static func parseSinglePassClickHouseRows(
        _ rows: [[String: Any]],
        windowHours: Int
    ) -> LogsForensicsResult {
        var out = LogsForensicsResult()

        struct RouteAcc {
            var method: String
            var path: String
            var requests: Int = 0
            var bytes: Int64 = 0
            var weightedLatencySum: Double = 0
            var errors: Int = 0
        }

        var routeMap: [String: RouteAcc] = [:]
        var uaMap: [String: (count: Int, bytes: Int64, err4xx: Int)] = [:]
        var synthesizedErrors: [SupabaseGatewayErrorItem] = []

        for (idx, row) in rows.enumerated() {
            let method = str(row["method"]) ?? "GET"
            let path = str(row["path"]) ?? "/"
            let ua = str(row["ua"]) ?? "Unknown"
            let reqCount = int(row["req_count"]) ?? 0
            guard reqCount > 0 else { continue }

            var respBytes = int64(row["resp_bytes"]) ?? 0
            let avgMs = double(row["avg_ms"]) ?? 0
            let okCnt = int(row["ok_cnt"]) ?? 0
            let e4 = int(row["err_4xx"]) ?? 0
            let e5 = int(row["err_5xx"]) ?? 0
            let maxStatus = int(row["max_status"]) ?? (e5 > 0 ? 500 : 400)
            let lastTs = str(row["last_ts"]) ?? ""

            // Chunked transfer-encoding payload estimation when Content-Length is omitted
            if respBytes == 0 {
                if path.hasPrefix("/storage/") { respBytes = Int64(reqCount) * 8192 }
                else if path.hasPrefix("/rest/") { respBytes = Int64(reqCount) * 1280 }
                else if path.hasPrefix("/auth/") { respBytes = Int64(reqCount) * 850 }
                else if path.hasPrefix("/functions/") { respBytes = Int64(reqCount) * 1150 }
                else if path.hasPrefix("/realtime/") { respBytes = Int64(reqCount) * 450 }
                else { respBytes = Int64(reqCount) * 900 }
            }

            out.http2xxCount += okCnt
            out.http4xxCount += e4
            out.http5xxCount += e5
            out.totalEdgeResponseBytes24h += respBytes

            let routeKey = "\(method) \(path)"
            var rAcc = routeMap[routeKey] ?? RouteAcc(method: method, path: path)
            rAcc.requests += reqCount
            rAcc.bytes += respBytes
            rAcc.weightedLatencySum += avgMs * Double(reqCount)
            rAcc.errors += (e4 + e5)
            routeMap[routeKey] = rAcc

            let prevUa = uaMap[ua] ?? (0, 0, 0)
            uaMap[ua] = (prevUa.count + reqCount, prevUa.bytes + respBytes, prevUa.err4xx + e4)

            if e4 + e5 > 0 && synthesizedErrors.count < 12 {
                let statusCode = maxStatus >= 400 ? maxStatus : (e5 > 0 ? 500 : 400)
                let errTotal = e4 + e5
                synthesizedErrors.append(
                    SupabaseGatewayErrorItem(
                        id: "err_\(idx)",
                        timestamp: lastTs,
                        statusCode: statusCode,
                        method: method,
                        path: path,
                        userAgent: ua,
                        message: "\(method) \(path) -> HTTP \(statusCode) (\(errTotal)× in \(windowHours)h)"
                    )
                )
            }
        }

        out.topRoutes = routeMap.values
            .sorted {
                if $0.bytes != $1.bytes { return $0.bytes > $1.bytes }
                return $0.requests > $1.requests
            }
            .prefix(12)
            .map { acc in
                SupabaseTopRouteStat(
                    method: acc.method,
                    path: acc.path,
                    requests24h: acc.requests,
                    responseBytes24h: acc.bytes,
                    avgLatencyMs: acc.requests > 0 ? (acc.weightedLatencySum / Double(acc.requests)) : 0,
                    errors4xx5xx: acc.errors
                )
            }

        out.fleetBuckets = uaMap.map { ua, stats in
            FleetRawBucket(ua: ua, count: stats.count, bytes: stats.bytes, errors4xx: stats.err4xx)
        }
        out.recentErrors = synthesizedErrors
        out.logCountsBySource = ["edge_logs": out.http2xxCount + out.http4xxCount + out.http5xxCount]
        return out
    }

    private func fetchSinglePassClickHouseLogs(
        bearer: String,
        ref: String,
        windowHours: Int
    ) async -> LogsForensicsResult {
        let endDate = Date()
        let effectiveHours: Double = windowHours >= 24 ? 23.8 : Double(max(1, windowHours))
        let startDate = endDate.addingTimeInterval(-effectiveHours * 3600.0)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let startIso = iso.string(from: startDate)
        let endIso = iso.string(from: endDate)

        let rawData = await executeClickHouseLogsData(
            bearer: bearer,
            ref: ref,
            sql: Self.buildSinglePassGatewayClickHouseSql(),
            startIso: startIso,
            endIso: endIso
        )
        let rows = Self.decodeResultArray(rawData)
        return Self.parseSinglePassClickHouseRows(rows, windowHours: windowHours)
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

    // MARK: - PostgreSQL Read-Only Catalog Forensics (Single Consolidated POST to `/database/query/read-only`)

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

        // Single consolidated JSON CTE query (1 HTTP POST instead of 5 parallel POSTs -> -80% Postgres/Kong log ingestion)
        let combinedSql = """
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
        ),
        total_cpu AS (
          SELECT GREATEST(COALESCE(sum(total_exec_time), 0.0), 0.001) AS all_ms
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
        ),
        cron_rows AS (
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
          LIMIT 15
        )
        SELECT
          (SELECT db_bytes FROM db_meta) AS db_bytes,
          (SELECT active_conns FROM db_meta) AS active_conns,
          (SELECT cache_hit FROM db_meta) AS cache_hit,
          COALESCE((SELECT json_agg(t) FROM tbl_stats t), '[]'::json) AS tables_json,
          (SELECT rt_calls FROM rt_cpu) AS rt_calls,
          round(((SELECT rt_ms FROM rt_cpu) * 100.0 / (SELECT all_ms FROM total_cpu))::numeric, 2) AS rt_pct,
          COALESCE((SELECT json_agg(q) FROM top_q q), '[]'::json) AS top_sql_json,
          COALESCE((SELECT json_agg(c) FROM cron_rows c), '[]'::json) AS crons_json,
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
          COALESCE((SELECT sum(COALESCE((metadata->>'size')::bigint, 0))::bigint FROM storage.objects), 0) AS storage_bytes,
          (SELECT count(*)::int FROM public.paired_watches) AS watches_cnt,
          COALESCE((
            SELECT json_agg(DISTINCT COALESCE(device_name, source_type, 'Device'))
            FROM public.health_sources
          ), '[]'::json) AS health_sources_json;
        """

        var rows = Self.decodeTopLevelArray(await executeReadOnlySqlData(bearer: bearer, ref: ref, query: combinedSql))

        // Resilient fallback for non-DayOne projects where optional schemas (`cron`, `public.health_sources`) may be absent
        if rows.isEmpty {
            let coreFallbackSql = """
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
            rows = Self.decodeTopLevelArray(await executeReadOnlySqlData(bearer: bearer, ref: ref, query: coreFallbackSql))
        }

        if let first = rows.first {
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

            out.realtimeListChangesCalls = Self.int64(first["rt_calls"]) ?? 0
            out.realtimeWalCpuPercent = Self.double(first["rt_pct"]) ?? 0
            let qArr = Self.jsonArray(first["top_sql_json"])
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

            let cArr = Self.jsonArray(first["crons_json"])
            out.cronJobs = cArr.map { r in
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

            out.realtimeActiveSubscriptions = Self.int(first["rt_subs"]) ?? 0
            out.storageObjectsBytes = Self.int64(first["storage_bytes"]) ?? 0
            if let dict = Self.jsonDict(first["rt_by_table"]) {
                var mapped: [String: Int] = [:]
                for (k, v) in dict {
                    mapped[k] = Self.int(v) ?? 0
                }
                out.realtimeByTable = mapped
            }

            if let w = Self.int(first["watches_cnt"]), w > 0 {
                out.pairedWatchesCount = w
            }
            if let rawSources = first["health_sources_json"] as? [Any] {
                out.healthSourceNames = rawSources.compactMap { Self.str($0) }
            } else if let strJson = Self.str(first["health_sources_json"]),
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
        var billingCyclePeriod: String? = nil
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
        var logIngestionBytes: Int64 = 0
        var logIngestionQuotaBytes: Int64 = 0
        var logQueryBytes: Int64 = 0
        var logQueryQuotaBytes: Int64 = 0
        var logIngestionEvents: Int64 = 0
        var dailyEgress: [SupabaseDailyEgressPoint] = []
        var resourceWarnings: [String] = []
    }

    private func fetchPlatformBillingUsage(
        primaryBearer: String,
        fallbackBearer: String? = nil,
        orgSlug: String,
        ref: String,
        orgCreatedAt: String? = nil,
        projectCreatedAt: String? = nil,
        preferDashboardEndpoint: Bool = false
    ) async -> PlatformBillingResult {
        var out = PlatformBillingResult()
        guard !orgSlug.isEmpty else { return out }

        var effectivePrimary = primaryBearer

        // 0. Query Organization Subscription for Billing Cycle Period & Plan
        let subUrl1 = "https://api.supabase.com/platform/organizations/\(orgSlug)/billing/subscription"
        let subUrl2 = "https://api.supabase.com/v1/organizations/\(orgSlug)/billing/subscription"
        var subJson = await performGetJsonWithFallback(url: subUrl1, primaryBearer: effectivePrimary, fallbackBearer: fallbackBearer) as? [String: Any]
        if subJson == nil {
            subJson = await performGetJsonWithFallback(url: subUrl2, primaryBearer: effectivePrimary, fallbackBearer: fallbackBearer) as? [String: Any]
        }

        // 1. Organization / Project exact billing usage
        // Note: Query org-level usage first (without project_ref) matching the Studio "All projects" scope.
        let usageUrlOrg = "https://api.supabase.com/platform/organizations/\(orgSlug)/usage"
        let usageUrlProj = "https://api.supabase.com/platform/organizations/\(orgSlug)/usage?project_ref=\(ref)"
        let usageUrlV1 = "https://api.supabase.com/v1/organizations/\(orgSlug)/usage"

        var usageJson = await performGetJsonWithFallback(url: usageUrlOrg, primaryBearer: effectivePrimary, fallbackBearer: fallbackBearer) as? [String: Any]
        if usageJson == nil,
           let rotatedDash = await ensureFreshDashboardBearer(forceRefresh: true),
           rotatedDash != effectivePrimary {
            effectivePrimary = rotatedDash
            if subJson == nil {
                subJson = await performGetJsonWithFallback(url: subUrl1, primaryBearer: effectivePrimary, fallbackBearer: fallbackBearer) as? [String: Any]
            }
            usageJson = await performGetJsonWithFallback(url: usageUrlOrg, primaryBearer: effectivePrimary, fallbackBearer: fallbackBearer) as? [String: Any]
        }
        if usageJson == nil || (usageJson?["usages"] as? [[String: Any]])?.isEmpty == true {
            usageJson = await performGetJsonWithFallback(url: usageUrlProj, primaryBearer: effectivePrimary, fallbackBearer: fallbackBearer) as? [String: Any]
        }
        if usageJson == nil || (usageJson?["usages"] as? [[String: Any]])?.isEmpty == true {
            usageJson = await performGetJsonWithFallback(url: usageUrlV1, primaryBearer: effectivePrimary, fallbackBearer: fallbackBearer) as? [String: Any]
        }

        var subscriptionStartSec: Int64?
        if let subJson {
            var startSec: Int64?
            var endSec: Int64?
            if let s = Self.int64(subJson["current_period_start"]) { startSec = s; subscriptionStartSec = s }
            if let e = Self.int64(subJson["current_period_end"]) { endSec = e }
            if let s = startSec, let e = endSec, s > 0, e > s {
                out.billingCyclePeriod = SupabaseAdminSnapshot.formatBillingCyclePeriod(startEpochSeconds: s, endEpochSeconds: e)
            }
        }

        if let usageJson, let usages = usageJson["usages"] as? [[String: Any]], !usages.isEmpty {
            out.isExact = true

            // If billing cycle period not yet resolved, check usageJson
            if out.billingCyclePeriod == nil {
                if let s = Self.int64(usageJson["billing_cycle_start"]) ?? Self.int64(usageJson["period_start"]),
                   let e = Self.int64(usageJson["billing_cycle_end"]) ?? Self.int64(usageJson["period_end"]),
                   s > 0, e > s {
                    subscriptionStartSec = s
                    out.billingCyclePeriod = SupabaseAdminSnapshot.formatBillingCyclePeriod(startEpochSeconds: s, endEpochSeconds: e)
                }
            }

            for u in usages {
                guard let metric = Self.str(u["metric"])?.uppercased() else { continue }
                let usageVal = Self.double(u["usage"]) ?? 0
                let usageOrig = Self.int64(u["usage_original"])
                let limitVal = Self.double(u["pricing_free_units"]) ?? Self.double(u["capped_quota"]) ?? Self.double(u["available_in_plan"]) ?? 0

                // Supabase Studio uses SI decimal GB (`1_000_000_000` bytes) for `pricing_free_units` and `usage`
                // while `usage_original` carries exact raw decimal bytes.
                func resolveBytes(_ val: Double, orig: Int64?) -> Int64 {
                    if let orig, orig > 0 { return orig }
                    if val > 0 && val < 100_000 {
                        return Int64(val * 1_000_000_000.0)
                    }
                    return Int64(val)
                }

                switch metric {
                case "EGRESS", "UNIFIED_EGRESS", "NETWORK_EGRESS", "TOTAL_EGRESS":
                    let b = resolveBytes(usageVal, orig: usageOrig)
                    out.egressUsedBytes = max(out.egressUsedBytes, b)
                    if limitVal > 0 { out.egressQuotaBytes = resolveBytes(limitVal, orig: nil) }
                case "CACHED_EGRESS":
                    out.cachedEgressUsedBytes = resolveBytes(usageVal, orig: usageOrig)
                case "DATABASE_SIZE", "DB_SIZE":
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
                    out.logIngestionBytes = resolveBytes(usageVal, orig: usageOrig)
                    if limitVal > 0 { out.logIngestionQuotaBytes = resolveBytes(limitVal, orig: nil) }
                    out.logIngestionEvents += (usageOrig ?? Int64(usageVal))
                case "LOG_QUERY", "LOG_QUERYING":
                    out.logQueryBytes = resolveBytes(usageVal, orig: usageOrig)
                    if limitVal > 0 { out.logQueryQuotaBytes = resolveBytes(limitVal, orig: nil) }
                default:
                    break
                }
            }
        }

        // Fallback for billing cycle period if not yet set: compute from org or project creation date
        if out.billingCyclePeriod == nil {
            if let dateStr = orgCreatedAt ?? projectCreatedAt {
                out.billingCyclePeriod = SupabaseAdminSnapshot.computeBillingCyclePeriodFromCreation(dateString: dateStr)
            } else {
                out.billingCyclePeriod = SupabaseAdminSnapshot.computeBillingCyclePeriodFromCreation(dateString: "")
            }
        }

        // Compute start of current billing cycle for daily query
        let cycleStartDate = SupabaseAdminSnapshot.computeBillingCycleStartDate(
            startEpochSeconds: subscriptionStartSec,
            creationDateString: orgCreatedAt ?? projectCreatedAt
        )

        // 2. Daily Egress stacked breakdown across the active billing cycle (deduplicated & summed per YYYY-MM-DD)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let endStr = iso.string(from: Date())
        let minAllowedStart = Date().addingTimeInterval(-35 * 86400)
        let effectiveStart = max(cycleStartDate, minAllowedStart)
        let startStr = iso.string(from: effectiveStart)

        var dailyCompsOrg = URLComponents(string: "https://api.supabase.com/platform/organizations/\(orgSlug)/usage/daily")!
        dailyCompsOrg.queryItems = [
            URLQueryItem(name: "start", value: startStr),
            URLQueryItem(name: "end", value: endStr)
        ]
        var dailyJson = await performGetJsonWithFallback(
            url: dailyCompsOrg.url?.absoluteString ?? "",
            primaryBearer: effectivePrimary,
            fallbackBearer: fallbackBearer
        ) as? [String: Any]
        if dailyJson == nil || (dailyJson?["usages"] as? [[String: Any]])?.isEmpty == true {
            var dailyCompsProj = URLComponents(string: "https://api.supabase.com/platform/organizations/\(orgSlug)/usage/daily")!
            dailyCompsProj.queryItems = [
                URLQueryItem(name: "project_ref", value: ref),
                URLQueryItem(name: "start", value: startStr),
                URLQueryItem(name: "end", value: endStr)
            ]
            dailyJson = await performGetJsonWithFallback(
                url: dailyCompsProj.url?.absoluteString ?? "",
                primaryBearer: effectivePrimary,
                fallbackBearer: fallbackBearer
            ) as? [String: Any]
        }

        if let dailyJson, let series = dailyJson["usages"] as? [[String: Any]] {
            struct DailyBucket {
                var rest: Int64 = 0
                var fn: Int64 = 0
                var rt: Int64 = 0
                var auth: Int64 = 0
                var storage: Int64 = 0
                var supavisor: Int64 = 0
            }
            var byDate: [String: DailyBucket] = [:]
            for row in series {
                let dateRaw = Self.str(row["date"]) ?? Self.str(row["period_start"]) ?? Self.str(row["timestamp"]) ?? ""
                let dateShort = String(dateRaw.prefix(10))
                guard dateShort.count == 10 else { continue }
                var bucket = byDate[dateShort] ?? DailyBucket()
                let breakdown = (row["breakdown"] as? [String: Any]) ?? row
                func b(_ key: String) -> Int64 {
                    if let orig = Self.int64(breakdown["\(key)_original"]), orig > 0 { return orig }
                    if let v = Self.double(breakdown[key]), v > 0 {
                        return v < 100_000 ? Int64(v * 1_000_000_000.0) : Int64(v)
                    }
                    return 0
                }
                let bRest = b("egress_rest") + b("database_egress")
                let bFn = b("egress_function") + b("functions_egress")
                let bRt = b("egress_realtime") + b("realtime_egress")
                let bAuth = b("egress_auth") + b("auth_egress")
                let bStorage = b("egress_storage") + b("storage_egress")
                let bSupa = b("egress_supavisor") + b("supavisor_egress")

                bucket.rest += bRest
                bucket.fn += bFn
                bucket.rt += bRt
                bucket.auth += bAuth
                bucket.storage += bStorage
                bucket.supavisor += bSupa

                if let metric = Self.str(row["metric"])?.uppercased() {
                    let orig = Self.int64(row["usage_original"])
                    let usageVal = Self.double(row["usage"]) ?? 0
                    let metricBytes: Int64 = {
                        if let orig, orig > 0 { return orig }
                        if usageVal > 0 {
                            return usageVal < 100_000 ? Int64(usageVal * 1_000_000_000.0) : Int64(usageVal)
                        }
                        return 0
                    }()
                    if metricBytes > 0 {
                        switch metric {
                        case "EGRESS_REST", "DATABASE_EGRESS", "POSTGREST_EGRESS":
                            if bRest == 0 { bucket.rest += metricBytes }
                        case "EGRESS_FUNCTION", "FUNCTION_EGRESS", "FUNCTIONS_EGRESS", "EDGE_FUNCTION_EGRESS":
                            if bFn == 0 { bucket.fn += metricBytes }
                        case "EGRESS_REALTIME", "REALTIME_EGRESS":
                            if bRt == 0 { bucket.rt += metricBytes }
                        case "EGRESS_AUTH", "AUTH_EGRESS":
                            if bAuth == 0 { bucket.auth += metricBytes }
                        case "EGRESS_STORAGE", "STORAGE_EGRESS":
                            if bStorage == 0 { bucket.storage += metricBytes }
                        case "EGRESS_SUPAVISOR", "SUPAVISOR_EGRESS", "SHARED_POOLER_EGRESS":
                            if bSupa == 0 { bucket.supavisor += metricBytes }
                        default:
                            break
                        }
                    }
                }
                byDate[dateShort] = bucket
            }
            out.dailyEgress = byDate.keys.sorted().map { d in
                let b = byDate[d]!
                return SupabaseDailyEgressPoint(
                    date: d,
                    restBytes: b.rest,
                    functionBytes: b.fn,
                    realtimeBytes: b.rt,
                    authBytes: b.auth,
                    storageBytes: b.storage,
                    supavisorBytes: b.supavisor
                )
            }
        }

        // 3. Resource warnings (disk/CPU/memory exhaustion banners)
        if preferDashboardEndpoint || effectivePrimary != fallbackBearer,
           let warnArr = await performGetJsonWithFallback(
               url: "https://api.supabase.com/platform/projects-resource-warnings?ref=\(ref)",
               primaryBearer: effectivePrimary,
               fallbackBearer: fallbackBearer
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

    nonisolated private static func defaultFleetDisplay(for key: String) -> (displayName: String, sfSymbol: String) {
        switch key {
        case "ios": return ("iOS (iPhone & Foldable)", "iphone")
        case "macos": return ("macOS Desktop", "desktopcomputer")
        case "android": return ("Android & Fold", "smartphone")
        case "windows": return ("Windows 11 (WinUI 3)", "pc")
        case "watchos": return ("Smartwatches (watchOS & Wear OS)", "applewatch")
        case "cloud_cron": return ("Cloud Cron & Edge Functions", "cloud.bolt")
        default: return ("Other Clients", "network")
        }
    }

    nonisolated private static func mergeRegisteredSources(
        into devices: [SupabaseFleetDeviceStat],
        registeredHealthSources: [String]
    ) -> [SupabaseFleetDeviceStat] {
        guard !registeredHealthSources.isEmpty else { return devices }
        var byKey: [String: SupabaseFleetDeviceStat] = Dictionary(uniqueKeysWithValues: devices.map { ($0.platformKey, $0) })
        for src in registeredHealthSources {
            let lower = src.lowercased()
            let key: String
            if lower.contains("iphone") || lower.contains("schmitz") || lower.contains("ios") { key = "ios" }
            else if lower.contains("watch") { key = "watchos" }
            else if lower.contains("pixel") || lower.contains("samsung") || lower.contains("fold") || lower.contains("radar") || lower.contains("trapper") || lower.contains("android") { key = "android" }
            else if lower.contains("mac") { key = "macos" }
            else if lower.contains("win") { key = "windows" }
            else { continue }

            if var existing = byKey[key] {
                if !existing.registeredSources.contains(src) {
                    existing.registeredSources.append(src)
                    byKey[key] = existing
                }
            }
        }
        return byKey.values.sorted {
            if $0.requests24h != $1.requests24h { return $0.requests24h > $1.requests24h }
            return $0.displayName < $1.displayName
        }
    }

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
            else if lower.contains("watch") { key = "watchos" }
            else if lower.contains("pixel") || lower.contains("samsung") || lower.contains("fold") || lower.contains("radar") || lower.contains("trapper") || lower.contains("android") { key = "android" }
            else if lower.contains("mac") { key = "macos" }
            else if lower.contains("win") { key = "windows" }
            else { continue }

            let meta = Self.defaultFleetDisplay(for: key)
            var entry = map[key] ?? Acc(displayName: meta.displayName, sfSymbol: meta.sfSymbol)
            if !entry.sources.contains(src) { entry.sources.append(src) }
            map[key] = entry
        }

        return map.map { key, acc in
            SupabaseFleetDeviceStat(
                platformKey: key,
                displayName: acc.displayName,
                sfSymbol: acc.sfSymbol,
                requests24h: acc.requests,
                sharePercent: rawFleetBuckets.isEmpty ? 0 : (Double(acc.requests) * 100.0) / Double(totalReq),
                responseBytes24h: acc.bytes,
                errors4xx24h: acc.errors4xx,
                registeredSources: acc.sources
            )
        }
        .sorted {
            if $0.requests24h != $1.requests24h { return $0.requests24h > $1.requests24h }
            return $0.displayName < $1.displayName
        }
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

    private func performGetJsonWithFallback(
        url: String,
        primaryBearer: String,
        fallbackBearer: String? = nil
    ) async -> Any? {
        if !primaryBearer.isEmpty {
            if let json = try? await performGetJson(url: url, bearer: primaryBearer) {
                return json
            }
        }
        if let fallback = fallbackBearer?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fallback.isEmpty, fallback != primaryBearer {
            if let json = try? await performGetJson(url: url, bearer: fallback) {
                return json
            }
        }
        return nil
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

#if canImport(WebKit) && (os(iOS) || os(macOS))
/// Lightweight offscreen harvester that reads `localStorage['supabase.dashboard.auth.token']`
/// from `WKWebsiteDataStore.default()` on the `https://supabase.com` origin so existing GitHub
/// admin sessions self-heal automatically without requiring a manual sign-out / sign-in.
@MainActor
private final class WebKitDashboardSessionHarvester: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<String?, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var selfRetainer: WebKitDashboardSessionHarvester?

    func harvest() async -> String? {
        guard let originUrl = URL(string: "https://supabase.com/robots.txt") else {
            return nil
        }
        return await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            self.continuation = cont
            self.selfRetainer = self

            let config = WKWebViewConfiguration()
            config.websiteDataStore = .default()
            let wv = WKWebView(frame: .zero, configuration: config)
            wv.navigationDelegate = self
            self.webView = wv

            self.timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 5_500_000_000)
                self?.finish(with: nil)
            }

            let req = URLRequest(
                url: originUrl,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: 5.5
            )
            wv.load(req)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let js = """
        (function() {
          try {
            var direct = window.localStorage.getItem('supabase.dashboard.auth.token');
            if (direct) return direct;
            for (var i = 0; i < window.localStorage.length; i++) {
              var k = window.localStorage.key(i);
              if (k && k.indexOf('supabase') !== -1 && k.indexOf('auth') !== -1) {
                var v = window.localStorage.getItem(k);
                if (v && v.indexOf('access_token') !== -1) return v;
              }
            }
          } catch (e) {}
          return null;
        })();
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            let strVal = result as? String
            Task { @MainActor in
                self?.finish(with: strVal)
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(with: nil)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(with: nil)
    }

    private func finish(with value: String?) {
        guard let cont = continuation else { return }
        continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView = nil
        selfRetainer = nil
        cont.resume(returning: value)
    }
}
#endif
