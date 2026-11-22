import Foundation
import AuthenticationServices
import CommonCrypto
import CryptoKit
import Supabase

// MARK: - Models

public enum ExternalTaskProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case microsoftToDo = "MicrosoftToDo"
    case googleTasks = "GoogleTasks"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .microsoftToDo: return "Microsoft To Do"
        case .googleTasks: return "Google Tasks"
        }
    }

    public var shortName: String {
        switch self {
        case .microsoftToDo: return "To Do"
        case .googleTasks: return "Google Tasks"
        }
    }
}

public struct ExternalTaskAccount: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let provider: ExternalTaskProvider
    public var email: String
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var oauthClientKind: String // "mobile" or "desktop"
    public var fromCalendarSync: Bool

    public init(
        id: String,
        provider: ExternalTaskProvider,
        email: String,
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        oauthClientKind: String = "mobile",
        fromCalendarSync: Bool = false
    ) {
        self.id = id
        self.provider = provider
        self.email = email
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.oauthClientKind = oauthClientKind
        self.fromCalendarSync = fromCalendarSync
    }
}

public struct ExternalTaskList: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let isDefault: Bool

    public init(id: String, title: String, isDefault: Bool = false) {
        self.id = id
        self.title = title
        self.isDefault = isDefault
    }
}

public struct ExternalTaskItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let notes: String?
    public let isHighImportance: Bool
    public let dueDate: Date?

    public init(
        id: String,
        title: String,
        notes: String? = nil,
        isHighImportance: Bool = false,
        dueDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.isHighImportance = isHighImportance
        self.dueDate = dueDate
    }
}

public enum ExternalTasksAuthError: LocalizedError, Sendable {
    case missingTasksPermission(ExternalTaskProvider)
    case tokenExpired(ExternalTaskProvider)
    case cancelled
    case message(String)

    public var errorDescription: String? {
        switch self {
        case .missingTasksPermission(let provider):
            return "\(provider.displayName) requires Tasks read permission. Please sign in to grant access."
        case .tokenExpired(let provider):
            return "\(provider.displayName) session expired. Please sign in again."
        case .cancelled:
            return "Sign-in was cancelled."
        case .message(let msg):
            return msg
        }
    }
}

// MARK: - Service

@MainActor
public final class TagdosExternalTasksService: ObservableObject {
    public static let shared = TagdosExternalTasksService()

    @Published public private(set) var accounts: [ExternalTaskAccount] = []
    @Published public private(set) var isLoadingAccounts: Bool = false

    private let localAccountsKey = "daily_tagdos_external_accounts_v1"

    // Shared OAuth App Registrations loaded from gitignored DailyOAuthSecrets
    private var microsoftClientId: String { DailyOAuthSecrets.microsoftClientId }
    private let microsoftRedirectUri = "com.intellidream.daily.desktop://login-callback"
    private let microsoftCallbackScheme = "com.intellidream.daily.desktop"

    private var googleMobileClientId: String { DailyOAuthSecrets.googleMobileClientId }
    private var googleMobileCallbackScheme: String {
        let prefix = DailyOAuthSecrets.googleMobileClientId
            .replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        return "com.googleusercontent.apps.\(prefix)"
    }
    private var googleMobileRedirectUri: String { "\(googleMobileCallbackScheme):/oauth2redirect" }

    private var googleDesktopClientId: String { DailyOAuthSecrets.googleDesktopClientId }
    private var googleDesktopClientSecret: String { DailyOAuthSecrets.googleDesktopClientSecret }

    private var webAuthCoordinator: ExternalWebAuthCoordinator?

    private init() {
        loadLocalAccounts()
    }

    // MARK: - Account Loading (On-Demand Only)

    public func loadLocalAccounts() {
        let defaults = GroupDefaults.shared.userDefaults
        guard let data = defaults.data(forKey: localAccountsKey),
              let decoded = try? JSONDecoder().decode([ExternalTaskAccount].self, from: data) else {
            self.accounts = []
            return
        }
        let userId = currentEncryptionKeyScope()
        self.accounts = decoded.map { acc in
            var copy = acc
            copy.accessToken = Self.decryptToken(acc.accessToken, keyScope: userId)
            copy.refreshToken = Self.decryptToken(acc.refreshToken, keyScope: userId)
            return copy
        }
    }

    private func persistLocalAccounts(_ localOnly: [ExternalTaskAccount]) {
        let userId = currentEncryptionKeyScope()
        let encrypted = localOnly.map { acc in
            var copy = acc
            copy.accessToken = Self.encryptToken(acc.accessToken, keyScope: userId)
            copy.refreshToken = Self.encryptToken(acc.refreshToken, keyScope: userId)
            return copy
        }
        if let data = try? JSONEncoder().encode(encrypted) {
            GroupDefaults.shared.userDefaults.set(data, forKey: localAccountsKey)
        }
    }

    private func currentEncryptionKeyScope() -> String {
        if let uid = AuthService.shared.currentUser?.id, uid != "guest" {
            return uid.lowercased()
        }
        if let stored = GroupDefaults.shared.userDefaults.string(forKey: "supabase_user_id"), stored != "guest" {
            return stored.lowercased()
        }
        return "daily_local_tagdos_scope"
    }

    /// Loads local accounts + on-demand Supabase `calendar_accounts` (if authenticated) with zero background polling.
    public func refreshAvailableAccounts() async {
        isLoadingAccounts = true
        defer { isLoadingAccounts = false }

        loadLocalAccounts()
        var merged = accounts.filter { !$0.fromCalendarSync }

        // Read existing connected calendar accounts from Supabase on-demand if logged in
        guard let session = try? await SupabaseService.shared.client.auth.session else {
            self.accounts = merged
            return
        }
        let userId = session.user.id.uuidString.lowercased()
        guard userId != "guest" else {
            self.accounts = merged
            return
        }

        struct RemoteCalendarAccountDTO: Codable {
            let id: UUID
            let user_id: UUID
            let account_type: String
            let email: String
            let access_token: String
            let refresh_token: String?
            let token_expires_at: Date
            let is_deleted: Bool?
        }

        do {
            let res = try await SupabaseService.shared.client
                .from("calendar_accounts")
                .select("id,user_id,account_type,email,access_token,refresh_token,token_expires_at,is_deleted")
                .eq("user_id", value: userId)
                .execute()

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let remoteRows = try decoder.decode([RemoteCalendarAccountDTO].self, from: res.data)

            for row in remoteRows where row.is_deleted != true {
                let provider: ExternalTaskProvider?
                let clientKind: String
                switch row.account_type {
                case "MicrosoftPersonal", "MicrosoftWork":
                    provider = .microsoftToDo
                    clientKind = "desktop"
                case "Google":
                    provider = .googleTasks
                    clientKind = "desktop"
                default:
                    provider = nil
                    clientKind = "desktop"
                }
                guard let resolvedProvider = provider else { continue }

                let decryptedAccess = Self.decryptToken(row.access_token, keyScope: userId)
                let decryptedRefresh = Self.decryptToken(row.refresh_token ?? "", keyScope: userId)

                let alreadyLocal = merged.contains {
                    $0.provider == resolvedProvider && $0.email.caseInsensitiveCompare(row.email) == .orderedSame
                }
                if !alreadyLocal && (!decryptedAccess.isEmpty || !decryptedRefresh.isEmpty) {
                    merged.append(
                        ExternalTaskAccount(
                            id: row.id.uuidString.lowercased(),
                            provider: resolvedProvider,
                            email: row.email,
                            accessToken: decryptedAccess,
                            refreshToken: decryptedRefresh,
                            expiresAt: row.token_expires_at,
                            oauthClientKind: clientKind,
                            fromCalendarSync: true
                        )
                    )
                }
            }
        } catch {
            print("[TagdosExternalTasksService] Calendar accounts lookup notice: \(error.localizedDescription)")
        }

        self.accounts = merged
    }

    public func removeLocalAccount(_ account: ExternalTaskAccount) {
        let localRemaining = accounts.filter { !$0.fromCalendarSync && $0.id != account.id }
        persistLocalAccounts(localRemaining)
        accounts.removeAll { $0.id == account.id }
    }

    // MARK: - OAuth PKCE Sign-In

    public func signIn(
        provider: ExternalTaskProvider,
        presentationAnchor: ASPresentationAnchor
    ) async throws -> ExternalTaskAccount {
        switch provider {
        case .microsoftToDo:
            return try await signInMicrosoft(presentationAnchor: presentationAnchor)
        case .googleTasks:
            return try await signInGoogle(presentationAnchor: presentationAnchor)
        }
    }

    private func signInMicrosoft(presentationAnchor: ASPresentationAnchor) async throws -> ExternalTaskAccount {
        let codeVerifier = Self.generateCodeVerifier()
        let codeChallenge = Self.generateCodeChallenge(codeVerifier)
        let scopes = "offline_access https://graph.microsoft.com/User.Read https://graph.microsoft.com/Calendars.Read https://graph.microsoft.com/Tasks.Read"

        var components = URLComponents(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: microsoftClientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: microsoftRedirectUri),
            URLQueryItem(name: "response_mode", value: "query"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "prompt", value: "select_account"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        let callbackURL = try await startWebAuth(
            url: components.url!,
            callbackScheme: microsoftCallbackScheme,
            anchor: presentationAnchor
        )

        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else {
            let errDesc = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "error_description" || $0.name == "error" })?.value
            throw ExternalTasksAuthError.message(errDesc ?? "Microsoft authorization did not return a code.")
        }

        // Exchange authorization code for tokens
        var tokenReq = URLRequest(url: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!)
        tokenReq.httpMethod = "POST"
        tokenReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        tokenReq.httpBody = Self.formURLEncodedBody([
            "client_id": microsoftClientId,
            "code": code,
            "redirect_uri": microsoftRedirectUri,
            "grant_type": "authorization_code",
            "code_verifier": codeVerifier
        ])

        let (tokenData, tokenResp) = try await URLSession.shared.data(for: tokenReq)
        guard let httpResp = tokenResp as? HTTPURLResponse, (200..<300).contains(httpResp.statusCode),
              let tokenObj = try? JSONSerialization.jsonObject(with: tokenData) as? [String: Any],
              let accessToken = tokenObj["access_token"] as? String else {
            let raw = String(data: tokenData, encoding: .utf8) ?? "Token exchange failed"
            throw ExternalTasksAuthError.message("Microsoft sign-in failed: \(raw)")
        }

        let refreshToken = tokenObj["refresh_token"] as? String ?? ""
        let expiresIn = tokenObj["expires_in"] as? Int ?? 3600

        // Fetch profile email
        var email = "Microsoft Account"
        if let meObj = try? await fetchJSONObject(url: URL(string: "https://graph.microsoft.com/v1.0/me")!, bearerToken: accessToken) {
            if let mail = meObj["mail"] as? String, !mail.isEmpty {
                email = mail
            } else if let upn = meObj["userPrincipalName"] as? String, !upn.isEmpty {
                email = upn
            }
        }
        if email == "Microsoft Account",
           let calObj = try? await fetchJSONObject(url: URL(string: "https://graph.microsoft.com/v1.0/me/calendar")!, bearerToken: accessToken),
           let owner = calObj["owner"] as? [String: Any],
           let address = owner["address"] as? String, !address.isEmpty {
            email = address
        }

        let account = ExternalTaskAccount(
            id: "ms_\(email.lowercased())",
            provider: .microsoftToDo,
            email: email,
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)),
            oauthClientKind: "mobile",
            fromCalendarSync: false
        )
        upsertLocalAccount(account)
        return account
    }

    private func signInGoogle(presentationAnchor: ASPresentationAnchor) async throws -> ExternalTaskAccount {
        let codeVerifier = Self.generateCodeVerifier()
        let codeChallenge = Self.generateCodeChallenge(codeVerifier)
        let scopes = "https://www.googleapis.com/auth/tasks.readonly https://www.googleapis.com/auth/userinfo.email email profile"

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: googleMobileClientId),
            URLQueryItem(name: "redirect_uri", value: googleMobileRedirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "select_account consent"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        let callbackURL = try await startWebAuth(
            url: components.url!,
            callbackScheme: googleMobileCallbackScheme,
            anchor: presentationAnchor
        )

        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else {
            let errDesc = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "error" })?.value
            throw ExternalTasksAuthError.message(errDesc ?? "Google authorization did not return a code.")
        }

        var tokenReq = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        tokenReq.httpMethod = "POST"
        tokenReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        tokenReq.httpBody = Self.formURLEncodedBody([
            "client_id": googleMobileClientId,
            "code": code,
            "redirect_uri": googleMobileRedirectUri,
            "grant_type": "authorization_code",
            "code_verifier": codeVerifier
        ])

        let (tokenData, tokenResp) = try await URLSession.shared.data(for: tokenReq)
        guard let httpResp = tokenResp as? HTTPURLResponse, (200..<300).contains(httpResp.statusCode),
              let tokenObj = try? JSONSerialization.jsonObject(with: tokenData) as? [String: Any],
              let accessToken = tokenObj["access_token"] as? String else {
            let raw = String(data: tokenData, encoding: .utf8) ?? "Token exchange failed"
            throw ExternalTasksAuthError.message("Google sign-in failed: \(raw)")
        }

        let refreshToken = tokenObj["refresh_token"] as? String ?? ""
        let expiresIn = tokenObj["expires_in"] as? Int ?? 3600

        var email = "Google Account"
        if let infoObj = try? await fetchJSONObject(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!, bearerToken: accessToken),
           let fetchedEmail = infoObj["email"] as? String, !fetchedEmail.isEmpty {
            email = fetchedEmail
        }

        let account = ExternalTaskAccount(
            id: "google_\(email.lowercased())",
            provider: .googleTasks,
            email: email,
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)),
            oauthClientKind: "mobile",
            fromCalendarSync: false
        )
        upsertLocalAccount(account)
        return account
    }

    private func upsertLocalAccount(_ account: ExternalTaskAccount) {
        var localOnly = accounts.filter { !$0.fromCalendarSync }
        localOnly.removeAll { $0.provider == account.provider && $0.email.caseInsensitiveCompare(account.email) == .orderedSame }
        localOnly.insert(account, at: 0)
        persistLocalAccounts(localOnly)

        var merged = accounts
        merged.removeAll { $0.provider == account.provider && $0.email.caseInsensitiveCompare(account.email) == .orderedSame }
        merged.insert(account, at: 0)
        self.accounts = merged
    }

    private func startWebAuth(
        url: URL,
        callbackScheme: String,
        anchor: ASPresentationAnchor
    ) async throws -> URL {
        let coordinator = ExternalWebAuthCoordinator(anchor: anchor)
        self.webAuthCoordinator = coordinator
        defer { self.webAuthCoordinator = nil }

        do {
            return try await withCheckedThrowingContinuation { continuation in
                coordinator.start(url: url, callbackScheme: callbackScheme, continuation: continuation)
            }
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            throw ExternalTasksAuthError.cancelled
        }
    }

    // MARK: - Token Refresh

    private func ensureValidAccessToken(for account: ExternalTaskAccount) async throws -> ExternalTaskAccount {
        if Date().addingTimeInterval(120) < account.expiresAt && !account.accessToken.isEmpty {
            return account
        }
        guard !account.refreshToken.isEmpty else {
            if !account.accessToken.isEmpty {
                return account
            }
            throw ExternalTasksAuthError.tokenExpired(account.provider)
        }

        switch account.provider {
        case .microsoftToDo:
            var req = URLRequest(url: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpBody = Self.formURLEncodedBody([
                "client_id": microsoftClientId,
                "grant_type": "refresh_token",
                "refresh_token": account.refreshToken,
                "redirect_uri": microsoftRedirectUri
            ])

            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newAccess = obj["access_token"] as? String else {
                throw ExternalTasksAuthError.tokenExpired(.microsoftToDo)
            }
            var updated = account
            updated.accessToken = newAccess
            if let newRefresh = obj["refresh_token"] as? String, !newRefresh.isEmpty {
                updated.refreshToken = newRefresh
            }
            let expiresIn = obj["expires_in"] as? Int ?? 3600
            updated.expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
            updateCachedToken(updated)
            return updated

        case .googleTasks:
            // Try matching client kind first, then fall back to the other client if needed
            let attemptOrder: [(clientId: String, clientSecret: String?)] = account.oauthClientKind == "desktop"
                ? [(googleDesktopClientId, googleDesktopClientSecret), (googleMobileClientId, nil)]
                : [(googleMobileClientId, nil), (googleDesktopClientId, googleDesktopClientSecret)]

            for attempt in attemptOrder {
                var params = [
                    "client_id": attempt.clientId,
                    "grant_type": "refresh_token",
                    "refresh_token": account.refreshToken
                ]
                if let secret = attempt.clientSecret {
                    params["client_secret"] = secret
                }

                var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
                req.httpMethod = "POST"
                req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                req.httpBody = Self.formURLEncodedBody(params)

                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let newAccess = obj["access_token"] as? String {
                    var updated = account
                    updated.accessToken = newAccess
                    let expiresIn = obj["expires_in"] as? Int ?? 3600
                    updated.expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
                    updateCachedToken(updated)
                    return updated
                }
            }
            throw ExternalTasksAuthError.tokenExpired(.googleTasks)
        }
    }

    private func updateCachedToken(_ updated: ExternalTaskAccount) {
        if let idx = accounts.firstIndex(where: { $0.id == updated.id }) {
            accounts[idx] = updated
        }
        if !updated.fromCalendarSync {
            let localOnly = accounts.filter { !$0.fromCalendarSync }
            persistLocalAccounts(localOnly)
        }
    }

    // MARK: - Fetch Lists & Tasks

    public func fetchTaskLists(for account: ExternalTaskAccount) async throws -> [ExternalTaskList] {
        let validAccount = try await ensureValidAccessToken(for: account)

        switch validAccount.provider {
        case .microsoftToDo:
            let url = URL(string: "https://graph.microsoft.com/v1.0/me/todo/lists")!
            let obj = try await fetchJSONObjectWithRefresh(url: url, account: validAccount)
            guard let values = obj["value"] as? [[String: Any]] else { return [] }
            return values.compactMap { row in
                guard let id = row["id"] as? String,
                      let name = row["displayName"] as? String else { return nil }
                let wellKnown = (row["wellknownListName"] as? String ?? "").lowercased()
                return ExternalTaskList(id: id, title: name, isDefault: wellKnown == "defaultlist")
            }

        case .googleTasks:
            let url = URL(string: "https://tasks.googleapis.com/tasks/v1/users/@me/lists?maxResults=100")!
            let obj = try await fetchJSONObjectWithRefresh(url: url, account: validAccount)
            guard let items = obj["items"] as? [[String: Any]] else { return [] }
            return items.enumerated().compactMap { index, row in
                guard let id = row["id"] as? String,
                      let title = row["title"] as? String else { return nil }
                return ExternalTaskList(id: id, title: title, isDefault: index == 0)
            }
        }
    }

    public func fetchTasks(for account: ExternalTaskAccount, listId: String) async throws -> [ExternalTaskItem] {
        let validAccount = try await ensureValidAccessToken(for: account)
        let encodedListId = listId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? listId

        switch validAccount.provider {
        case .microsoftToDo:
            let url = URL(string: "https://graph.microsoft.com/v1.0/me/todo/lists/\(encodedListId)/tasks?$top=100")!
            let obj = try await fetchJSONObjectWithRefresh(url: url, account: validAccount)
            guard let values = obj["value"] as? [[String: Any]] else { return [] }

            return values.compactMap { row in
                let status = (row["status"] as? String ?? "notStarted").lowercased()
                guard status != "completed" else { return nil }
                guard let id = row["id"] as? String,
                      let rawTitle = row["title"] as? String else { return nil }
                let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return nil }

                var bodyText = ""
                if let bodyObj = row["body"] as? [String: Any],
                   let rawContent = bodyObj["content"] as? String {
                    let contentType = (bodyObj["contentType"] as? String ?? "").lowercased()
                    bodyText = contentType == "html"
                        ? Self.stripHtml(rawContent)
                        : rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
                }

                let importance = (row["importance"] as? String ?? "normal").lowercased()
                var dueDate: Date? = nil
                if let dueObj = row["dueDateTime"] as? [String: Any],
                   let dtStr = dueObj["dateTime"] as? String {
                    dueDate = Self.parseFlexibleDate(dtStr)
                }

                return ExternalTaskItem(
                    id: id,
                    title: title,
                    notes: bodyText.isEmpty ? nil : bodyText,
                    isHighImportance: importance == "high",
                    dueDate: dueDate
                )
            }

        case .googleTasks:
            let url = URL(string: "https://tasks.googleapis.com/tasks/v1/lists/\(encodedListId)/tasks?showCompleted=false&showHidden=false&maxResults=100")!
            let obj = try await fetchJSONObjectWithRefresh(url: url, account: validAccount)
            guard let items = obj["items"] as? [[String: Any]] else { return [] }

            return items.compactMap { row in
                let status = (row["status"] as? String ?? "needsAction").lowercased()
                guard status != "completed" else { return nil }
                guard let id = row["id"] as? String,
                      let rawTitle = row["title"] as? String else { return nil }
                let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return nil }

                let notes = (row["notes"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                var dueDate: Date? = nil
                if let dueStr = row["due"] as? String {
                    dueDate = Self.parseFlexibleDate(dueStr)
                }

                return ExternalTaskItem(
                    id: id,
                    title: title,
                    notes: notes?.isEmpty == false ? notes : nil,
                    isHighImportance: false,
                    dueDate: dueDate
                )
            }
        }
    }

    private func fetchJSONObjectWithRefresh(url: URL, account: ExternalTaskAccount) async throws -> [String: Any] {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(account.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw ExternalTasksAuthError.message("Invalid network response.")
        }

        if http.statusCode == 401 {
            // Force refresh once
            var forceAccount = account
            forceAccount.expiresAt = .distantPast
            let refreshed = try await ensureValidAccessToken(for: forceAccount)
            var retryReq = URLRequest(url: url)
            retryReq.setValue("Bearer \(refreshed.accessToken)", forHTTPHeaderField: "Authorization")
            let (retryData, retryResp) = try await URLSession.shared.data(for: retryReq)
            guard let retryHttp = retryResp as? HTTPURLResponse else {
                throw ExternalTasksAuthError.tokenExpired(account.provider)
            }
            if retryHttp.statusCode == 403 {
                throw ExternalTasksAuthError.missingTasksPermission(account.provider)
            }
            if retryHttp.statusCode == 401 {
                throw ExternalTasksAuthError.tokenExpired(account.provider)
            }
            guard (200..<300).contains(retryHttp.statusCode),
                  let jsonObj = try? JSONSerialization.jsonObject(with: retryData) as? [String: Any] else {
                let errText = String(data: retryData, encoding: .utf8) ?? "HTTP \(retryHttp.statusCode)"
                throw ExternalTasksAuthError.message(errText)
            }
            return jsonObj
        }

        if http.statusCode == 403 {
            throw ExternalTasksAuthError.missingTasksPermission(account.provider)
        }

        guard (200..<300).contains(http.statusCode),
              let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let errText = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw ExternalTasksAuthError.message(errText)
        }
        return jsonObj
    }

    private func fetchJSONObject(url: URL, bearerToken: String) async throws -> [String: Any] {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ExternalTasksAuthError.message("Failed request to \(url.host ?? "provider")")
        }
        return obj
    }

    // MARK: - AES-GCM Crypto (Compatible with EncryptionHelper.cs)

    private nonisolated static let staticSalt = Data([0x44, 0x61, 0x69, 0x6c, 0x79, 0x5f, 0x53, 0x65, 0x63, 0x75, 0x72, 0x65, 0x5f, 0x4b, 0x65, 0x79]) // "Daily_Secure_Key"

    private nonisolated static func deriveKey(keyScope: String) -> SymmetricKey? {
        guard let passwordData = keyScope.data(using: .utf8) else { return nil }
        var derived = [UInt8](repeating: 0, count: 32)
        let status = passwordData.withUnsafeBytes { passPtr in
            staticSalt.withUnsafeBytes { saltPtr in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passPtr.bindMemory(to: Int8.self).baseAddress,
                    passwordData.count,
                    saltPtr.bindMemory(to: UInt8.self).baseAddress,
                    staticSalt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    1000,
                    &derived,
                    32
                )
            }
        }
        guard status == kCCSuccess else { return nil }
        return SymmetricKey(data: Data(derived))
    }

    nonisolated public static func encryptToken(_ plainText: String, keyScope: String) -> String {
        guard !plainText.isEmpty, !keyScope.isEmpty,
              let key = deriveKey(keyScope: keyScope),
              let plainData = plainText.data(using: .utf8) else {
            return plainText
        }
        do {
            let nonce = AES.GCM.Nonce()
            let sealed = try AES.GCM.seal(plainData, using: key, nonce: nonce)
            var combined = Data()
            combined.append(contentsOf: nonce)
            combined.append(sealed.tag)
            combined.append(sealed.ciphertext)
            return combined.base64EncodedString()
        } catch {
            return plainText
        }
    }

    nonisolated public static func decryptToken(_ cipherText: String, keyScope: String) -> String {
        guard !cipherText.isEmpty, !keyScope.isEmpty else { return cipherText }
        // Peel up to 2 AES-GCM layers (handles both single-encrypted and WinUI double-encrypted tokens)
        var current = cipherText
        for _ in 0..<2 {
            var didDecrypt = false
            for candidateScope in [keyScope.lowercased(), keyScope, keyScope.uppercased()] {
                if let plain = decryptSingleLayer(current, keyScope: candidateScope) {
                    current = plain
                    didDecrypt = true
                    break
                }
            }
            if !didDecrypt { break }
        }
        return current
    }

    private nonisolated static func decryptSingleLayer(_ cipherBase64: String, keyScope: String) -> String? {
        guard let rawData = Data(base64Encoded: cipherBase64),
              rawData.count >= 28,
              let key = deriveKey(keyScope: keyScope) else {
            return nil
        }
        let nonceData = rawData.subdata(in: 0..<12)
        let tagData = rawData.subdata(in: 12..<28)
        let ciphertext = rawData.subdata(in: 28..<rawData.count)
        do {
            let nonce = try AES.GCM.Nonce(data: nonceData)
            let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tagData)
            let decrypted = try AES.GCM.open(box, using: key)
            return String(data: decrypted, encoding: .utf8)
        } catch {
            return nil
        }
    }

    // MARK: - PKCE & Utilities

    private static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64UrlEncode(Data(bytes))
    }

    private static func generateCodeChallenge(_ verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64UrlEncode(Data(digest))
    }

    private static func base64UrlEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formURLEncodedBody(_ params: [String: String]) -> Data? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        let query = params.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
        return query.data(using: .utf8)
    }

    private static func stripHtml(_ html: String) -> String {
        var text = html
            .replacingOccurrences(of: "(?is)<head[^>]*>.*?</head>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?is)<style[^>]*>.*?</style>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?i)<br\\s*/?>|</(p|div|li|h[1-6]|tr)>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#160;", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")

        let lines = text
            .components(separatedBy: .newlines)
            .map { line in
                line.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
        text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text
    }

    private static func parseFlexibleDate(_ raw: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: raw) { return d }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSS"
        if let d = df.date(from: raw) { return d }
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return df.date(from: raw)
    }
}

// MARK: - ASWebAuthenticationSession Coordinator

private final class ExternalWebAuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {
    private let anchor: ASPresentationAnchor
    private var session: ASWebAuthenticationSession?

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
        super.init()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }

    func start(url: URL, callbackScheme: String, continuation: CheckedContinuation<URL, Error>) {
        let completion: @Sendable (URL?, (any Error)?) -> Void = { callbackUrl, error in
            if let error = error {
                continuation.resume(throwing: error)
            } else if let callbackUrl = callbackUrl {
                continuation.resume(returning: callbackUrl)
            } else {
                continuation.resume(throwing: ExternalTasksAuthError.message("No callback received from provider."))
            }
        }

        let authSession = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: callbackScheme,
            completionHandler: completion
        )
        authSession.presentationContextProvider = self
        authSession.prefersEphemeralWebBrowserSession = false
        self.session = authSession

        if !authSession.start() {
            self.session = nil
            continuation.resume(throwing: ExternalTasksAuthError.message("Unable to open sign-in window."))
        }
    }
}
