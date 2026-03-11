import Foundation
import Supabase
import Combine
import SwiftUI
import WatchConnectivity
// Struct to match the Supabase table for decoding
struct WatchPairing: Codable {
    let code: String
    let access_token: String?
    let refresh_token: String?
    let created_at: String?
}

// Persistent pairing record — mirrors the paired_watches Supabase table
struct PairedWatchRecord: Codable {
    let id: String?
    let user_id: String?
    let platform: String?
    let device_name: String?
    let paired_at: String?
    let last_token_push: String?
    let pending_access_token: String?
    let pending_refresh_token: String?
    let is_active: Bool?
}

class WatchSessionManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchSessionManager()
    
    @Published var isAuthenticated: Bool = false
    @Published var pairingCode: String = ""
    @Published var isPairing: Bool = false
    @Published var errorMessage: String = ""
    @Published var currentUserId: UUID?
    
    let supabaseUrl = URL(string: "https://akkfouifxztnfwwiclwg.supabase.co")!
    let supabaseAnonKey = "sb_publishable_6FzrRSdmsH4arDhZS09PSQ_QK_I31DG"
    
    var supabaseClient: SupabaseClient?
    private var baseClient: SupabaseClient
    private var pollTimer: Timer?
    private var authStateTask: Task<Void, Never>?
    private var isRecoveringSession = false
    
    private override init() {
        let options = SupabaseClientOptions(auth: SupabaseClientOptions.AuthOptions(autoRefreshToken: false, emitLocalSessionAsInitialSession: true))
        self.baseClient = SupabaseClient(supabaseURL: supabaseUrl, supabaseKey: supabaseAnonKey, options: options)
        super.init()
        
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
        
        self.checkExistingSession()
    }
    
    func checkExistingSession() {
        if let accessToken = UserDefaults.standard.string(forKey: "supabase_access_token"),
           let refreshToken = UserDefaults.standard.string(forKey: "supabase_refresh_token") {
            
            // Initialize the main client right away so auth can take over
            let options = SupabaseClientOptions(auth: SupabaseClientOptions.AuthOptions(autoRefreshToken: false, emitLocalSessionAsInitialSession: true))
            self.supabaseClient = SupabaseClient(supabaseURL: supabaseUrl, supabaseKey: supabaseAnonKey, options: options)
            self.listenToAuthState()
            
            Task {
                do {
                    // Hand tokens to the Supabase Auth module so it manages the session.
                    try await self.supabaseClient?.auth.setSession(accessToken: accessToken, refreshToken: refreshToken)
                    
                    // We no longer forcefully refresh tokens on wake. 
                    // Instead, we rely on the Central Hub (MAUI App) pushing fresh tokens
                    // to the paired_watches table and checkForRepairTokens() picking them up.
                    // try? await self.supabaseClient?.auth.refreshSession()
                    
                    DispatchQueue.main.async {
                        if let userId = self.extractUserId(from: accessToken) {
                            self.currentUserId = userId
                        }
                        self.isAuthenticated = true
                        self.isPairing = false
                        
                        if let groupPrefs = UserDefaults(suiteName: "group.com.intellidream.daily") {
                            groupPrefs.set(accessToken, forKey: "supabase_access_token")
                        }
                    }
                } catch {
                    // setSession failed — the access token or format is invalid.
                    // We will retry on activation if networking was unavailable.
                    print("Initial session restore failed: \(error). Will retry on activation.")
                    DispatchQueue.main.async {
                        if let userId = self.extractUserId(from: accessToken) {
                            self.currentUserId = userId
                            self.isAuthenticated = true
                            self.isPairing = false
                        }
                    }
                }
            }
        } else {
            self.generatePairingCode()
        }
    }
    
    func generatePairingCode() {
        self.isPairing = true
        self.errorMessage = ""
        // Generate random 6 digit code
        self.pairingCode = String(format: "%06d", Int.random(in: 0...999999))
        
        Task {
            do {
                let dict: [String: String] = ["code": self.pairingCode]
                
                guard var components = URLComponents(url: supabaseUrl.appendingPathComponent("rest/v1/watch_pairings"), resolvingAgainstBaseURL: false) else { return }
                guard let url = components.url else { return }
                
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
                request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: dict)
                
                let (_, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                    throw NSError(domain: "", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP Error \(httpResponse.statusCode)"])
                }
                
                self.startPolling()
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Insert Err: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func startPolling() {
        pollTimer?.invalidate()
        DispatchQueue.main.async {
            self.pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
                self.checkPairingStatus()
            }
        }
    }
    
    func checkPairingStatus() {
        Task {
            do {
                guard var components = URLComponents(url: supabaseUrl.appendingPathComponent("rest/v1/watch_pairings"), resolvingAgainstBaseURL: false) else { return }
                components.queryItems = [URLQueryItem(name: "code", value: "eq.\(self.pairingCode)")]
                guard let url = components.url else { return }
                
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
                request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.cachePolicy = .reloadIgnoringLocalCacheData
                
                let (data, _) = try await URLSession.shared.data(for: request)
                let pairings = try JSONDecoder().decode([WatchPairing].self, from: data)
                
                if let pairing = pairings.first {
                    if let token = pairing.access_token, !token.isEmpty {
                        let refresh = pairing.refresh_token ?? ""
                        
                        DispatchQueue.main.async {
                            self.pollTimer?.invalidate()
                            UserDefaults.standard.set(token, forKey: "supabase_access_token")
                            UserDefaults.standard.set(refresh, forKey: "supabase_refresh_token")
                        }
                        
                        // Hand the tokens over to the official Auth module so it manages refreshing
                        let options = SupabaseClientOptions(auth: SupabaseClientOptions.AuthOptions(autoRefreshToken: false, emitLocalSessionAsInitialSession: true))
                        self.supabaseClient = SupabaseClient(supabaseURL: supabaseUrl, supabaseKey: supabaseAnonKey, options: options)
                        self.listenToAuthState()
                        
                        do {
                            try await self.supabaseClient?.auth.setSession(accessToken: token, refreshToken: refresh)
                            
                            DispatchQueue.main.async {
                                if let userId = self.extractUserId(from: token) {
                                    self.currentUserId = userId
                                }
                                self.isAuthenticated = true
                                self.isPairing = false
                                
                                // Mirror the active token to the Widget Extension App Group
                                if let groupPrefs = UserDefaults(suiteName: "group.com.intellidream.daily") {
                                    groupPrefs.set(token, forKey: "supabase_access_token")
                                }
                            }
                        } catch {
                            print("Failed to initialize Auth session: \(error)")
                        }
                        
                        // Clean up the row
                        _ = try? await baseClient.from("watch_pairings").delete().eq("code", value: self.pairingCode).execute()
                        
                        // Register this pairing in the persistent paired_watches table
                        await self.registerPairing(accessToken: token)
                    } else {
                        // Reached row but token is null, just wait
                    }
                } else {
                    // The row disappears when the Phone app claims it OR if we explicitly delete it after success.
                    // We only consider it an error if we are still actively "Pairing".
                    DispatchQueue.main.async {
                        if self.isPairing {
                            self.errorMessage = "Row deleted/missing. Retrying..."
                            self.pollTimer?.invalidate()
                            self.generatePairingCode()
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Poll Err: \(error.localizedDescription)"
                }
                print("Polling error: \(error)")
            }
        }
    }
    
    // MARK: - Session Recovery
    
    /// Called when the watch app returns to the foreground. Proactively refreshes
    /// the Supabase session so stale tokens from watchOS sleep don't cause 401s.
    /// Must NOT guard on isAuthenticated — after process kill + relaunch,
    /// isAuthenticated may still be false even though valid tokens exist in UserDefaults.
    func onAppBecameActive() {
        Task {
            // First, check for repair tokens pushed from the main app
            await checkForRepairTokens()
            
            // We no longer attempt to force a network refresh here.
            await recoverSessionFromStorage()
        }
    }
    
    /// Attempts to restore a valid Supabase session from locally stored tokens.
    /// Uses the isRecoveringSession flag to prevent infinite loops when setSession()
    /// itself triggers another .signedOut event.
    private func recoverSessionFromStorage() async {
        guard !isRecoveringSession else { return }
        isRecoveringSession = true
        defer { isRecoveringSession = false }
        
        guard let refreshToken = UserDefaults.standard.string(forKey: "supabase_refresh_token"),
              !refreshToken.isEmpty else {
            // No refresh token stored at all — truly logged out
            DispatchQueue.main.async { self.logout() }
            return
        }
        
        let accessToken = UserDefaults.standard.string(forKey: "supabase_access_token") ?? ""
        
        if self.supabaseClient == nil {
            let options = SupabaseClientOptions(auth: SupabaseClientOptions.AuthOptions(autoRefreshToken: false, emitLocalSessionAsInitialSession: true))
            self.supabaseClient = SupabaseClient(supabaseURL: supabaseUrl, supabaseKey: supabaseAnonKey, options: options)
            self.listenToAuthState()
        }
        
        do {
            try await self.supabaseClient?.auth.setSession(accessToken: accessToken, refreshToken: refreshToken)
            // Success — the auth state listener will persist the new tokens and update UI
        } catch {
            // Recovery failed — don't logout. The refresh token may still be valid but
            // network is temporarily unavailable (common on watchOS). We'll retry on
            // the next onAppBecameActive() call or WCSession token push.
            print("Session recovery failed: \(error). Will retry on next activation.")
            // Even though refresh failed, set authenticated UI so the user can still
            // interact with cached data. The auth listener or next activation will retry.
            DispatchQueue.main.async {
                if let userId = self.extractUserId(from: accessToken) {
                    self.currentUserId = userId
                    self.isAuthenticated = true
                    self.isPairing = false
                }
            }
        }
    }
    
    // MARK: - Logout
    
    func logout() {
        authStateTask?.cancel()
        
        // Deactivate the paired_watches record so the main app reflects the unpair
        if let pairId = UserDefaults.standard.string(forKey: "paired_watch_id") {
            Task {
                _ = try? await baseClient.from("paired_watches")
                    .update(["is_active": false])
                    .eq("id", value: pairId)
                    .execute()
            }
        }
        
        UserDefaults.standard.removeObject(forKey: "supabase_access_token")
        UserDefaults.standard.removeObject(forKey: "supabase_refresh_token")
        UserDefaults.standard.removeObject(forKey: "paired_watch_id")
        if let groupPrefs = UserDefaults(suiteName: "group.com.intellidream.daily") {
            groupPrefs.removeObject(forKey: "supabase_access_token")
        }
        
        self.isAuthenticated = false
        self.currentUserId = nil
        self.supabaseClient = nil
        self.generatePairingCode()
    }
    
    // MARK: - Paired Watches (Repair support)
    
    /// Registers this watch in the persistent paired_watches table after a successful pairing.
    private func registerPairing(accessToken: String) async {
        guard let userId = self.extractUserId(from: accessToken) else { return }
        
        let record: [String: String] = [
            "user_id": userId.uuidString.lowercased(),
            "platform": "watchos",
            "device_name": "Apple Watch"
        ]
        
        do {
            // Use raw REST to get the inserted id back via Prefer: return=representation
            guard var components = URLComponents(url: supabaseUrl.appendingPathComponent("rest/v1/paired_watches"), resolvingAgainstBaseURL: false) else { return }
            guard let url = components.url else { return }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("return=representation", forHTTPHeaderField: "Prefer")
            request.httpBody = try JSONSerialization.data(withJSONObject: record)
            
            let (data, _) = try await URLSession.shared.data(for: request)
            if let rows = try? JSONDecoder().decode([PairedWatchRecord].self, from: data),
               let id = rows.first?.id {
                UserDefaults.standard.set(id, forKey: "paired_watch_id")
                print("Registered paired_watch id: \(id)")
            }
        } catch {
            print("Failed to register pairing: \(error)")
        }
    }
    
    /// Checks the paired_watches table for pending repair tokens pushed from the main app.
    /// If found, consumes them and replaces the current session.
    private func checkForRepairTokens() async {
        guard let pairId = UserDefaults.standard.string(forKey: "paired_watch_id") else { return }
        
        do {
            guard var components = URLComponents(url: supabaseUrl.appendingPathComponent("rest/v1/paired_watches"), resolvingAgainstBaseURL: false) else { return }
            components.queryItems = [
                URLQueryItem(name: "id", value: "eq.\(pairId)"),
                URLQueryItem(name: "select", value: "pending_access_token,pending_refresh_token")
            ]
            guard let url = components.url else { return }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
            request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.cachePolicy = .reloadIgnoringLocalCacheData
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let rows = try JSONDecoder().decode([PairedWatchRecord].self, from: data)
            
            guard let row = rows.first,
                  let token = row.pending_access_token, !token.isEmpty,
                  let refresh = row.pending_refresh_token, !refresh.isEmpty else {
                return  // No pending repair tokens
            }
            
            print("Repair tokens found! Applying new session.")
            
            // Apply the fresh tokens
            UserDefaults.standard.set(token, forKey: "supabase_access_token")
            UserDefaults.standard.set(refresh, forKey: "supabase_refresh_token")
            if let groupPrefs = UserDefaults(suiteName: "group.com.intellidream.daily") {
                groupPrefs.set(token, forKey: "supabase_access_token")
            }
            
            if self.supabaseClient == nil {
                let options = SupabaseClientOptions(auth: SupabaseClientOptions.AuthOptions(autoRefreshToken: false, emitLocalSessionAsInitialSession: true))
                self.supabaseClient = SupabaseClient(supabaseURL: supabaseUrl, supabaseKey: supabaseAnonKey, options: options)
                self.listenToAuthState()
            }
            
            try? await self.supabaseClient?.auth.setSession(accessToken: token, refreshToken: refresh)
            
            DispatchQueue.main.async {
                if let userId = self.extractUserId(from: token) {
                    self.currentUserId = userId
                }
                self.isAuthenticated = true
                self.isPairing = false
            }
            
            // Clear the pending tokens so we don't consume them again
            guard var clearComponents = URLComponents(url: supabaseUrl.appendingPathComponent("rest/v1/paired_watches"), resolvingAgainstBaseURL: false) else { return }
            clearComponents.queryItems = [URLQueryItem(name: "id", value: "eq.\(pairId)")]
            guard let clearUrl = clearComponents.url else { return }
            
            var clearRequest = URLRequest(url: clearUrl)
            clearRequest.httpMethod = "PATCH"
            clearRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            clearRequest.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
            clearRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            clearRequest.httpBody = try JSONSerialization.data(withJSONObject: [
                "pending_access_token": NSNull(),
                "pending_refresh_token": NSNull()
            ] as [String : Any])
            
            _ = try? await URLSession.shared.data(for: clearRequest)
            print("Repair tokens consumed and cleared.")
        } catch {
            print("Error checking repair tokens: \(error)")
        }
    }
    
    private func extractUserId(from jwt: String) -> UUID? {
        let parts = jwt.components(separatedBy: ".")
        guard parts.count == 3 else { return nil }
        
        var base64 = parts[1]
        // Pad the base64 string
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 = base64.padding(toLength: base64.count + 4 - remainder, withPad: "=", startingAt: 0)
        }
        // Base64Url to Base64
        base64 = base64.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let sub = json["sub"] as? String else {
            return nil
        }
        
        return UUID(uuidString: sub)
    }
    
    private func listenToAuthState() {
        authStateTask?.cancel()
        authStateTask = Task { [weak self] in
            guard let self = self else { return }
            guard let client = self.supabaseClient else { return }
            
            for await state in client.auth.authStateChanges {
                if state.event == .signedOut {
                    // Don't immediately logout — attempt recovery from stored tokens.
                    // watchOS often kills the SDK's refresh timer during sleep, causing
                    // spurious signedOut events. Only logout if recovery completely fails.
                    guard !self.isRecoveringSession else { continue }
                    await self.recoverSessionFromStorage()
                    continue
                }
                
                if let session = state.session {
                    DispatchQueue.main.async {
                        if let groupPrefs = UserDefaults(suiteName: "group.com.intellidream.daily") {
                            groupPrefs.set(session.accessToken, forKey: "supabase_access_token")
                        }
                        UserDefaults.standard.set(session.accessToken, forKey: "supabase_access_token")
                        UserDefaults.standard.set(session.refreshToken, forKey: "supabase_refresh_token")
                        
                        // Restore authenticated state if it was lost during recovery
                        if !self.isAuthenticated {
                            if let userId = self.extractUserId(from: session.accessToken) {
                                self.currentUserId = userId
                            }
                            self.isAuthenticated = true
                            self.isPairing = false
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - WCSessionDelegate
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        print("WCSession activation state: \(activationState.rawValue)")
    }
    
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        handleReceivedSession(userInfo: userInfo)
    }
    
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        handleReceivedSession(userInfo: applicationContext)
    }
    
    private func handleReceivedSession(userInfo: [String: Any]) {
        guard let token = userInfo["supabase_access_token"] as? String, !token.isEmpty,
              let refresh = userInfo["supabase_refresh_token"] as? String else {
            return
        }
        
        DispatchQueue.main.async {
            UserDefaults.standard.set(token, forKey: "supabase_access_token")
            UserDefaults.standard.set(refresh, forKey: "supabase_refresh_token")
            
            if let groupPrefs = UserDefaults(suiteName: "group.com.intellidream.daily") {
                groupPrefs.set(token, forKey: "supabase_access_token")
            }
            
            if let userId = self.extractUserId(from: token) {
                self.currentUserId = userId
            }
            
            self.isAuthenticated = true
            self.isPairing = false
        }
        
        Task {
            do {
                if self.supabaseClient == nil {
                     let options = SupabaseClientOptions(auth: SupabaseClientOptions.AuthOptions(autoRefreshToken: false, emitLocalSessionAsInitialSession: true))
                     self.supabaseClient = SupabaseClient(supabaseURL: self.supabaseUrl, supabaseKey: self.supabaseAnonKey, options: options)
                     self.listenToAuthState()
                }
                
                try await self.supabaseClient?.auth.setSession(accessToken: token, refreshToken: refresh)
            } catch {
                print("Failed to update auth session from WCSession: \(error)")
            }
        }
    }
}
