import Foundation
import Supabase
import Combine
import SwiftUI
import WatchConnectivity
import WatchKit

struct WatchPairingCodeRecord: Codable {
    let pin_code: String
    let user_id: String?
    let access_token: String?
    let refresh_token: String?
    let created_at: String?
    let expires_at: String?
    let claimed: Bool?
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
    @Published var isCheckingSession: Bool = true
    @Published var isPairing: Bool = false
    @Published var pairingPin: String = ""
    @Published var pairingStatus: String = "Connecting..."
    @Published var errorMessage: String = ""
    @Published var currentUserId: UUID?
    
    let supabaseUrl = URL(string: "https://akkfouifxztnfwwiclwg.supabase.co")!
    let supabaseAnonKey = "sb_publishable_6FzrRSdmsH4arDhZS09PSQ_QK_I31DG"
    
    var supabaseClient: SupabaseClient?
    private var baseClient: SupabaseClient
    private var pollTimer: Timer?
    private var authStateTask: Task<Void, Never>?
    private(set) var activeAccessToken: String?
    
    private override init() {
        let options = SupabaseClientOptions(
            auth: SupabaseClientOptions.AuthOptions(
                autoRefreshToken: false,
                emitLocalSessionAsInitialSession: true
            )
        )
        self.baseClient = SupabaseClient(supabaseURL: supabaseUrl, supabaseKey: supabaseAnonKey, options: options)
        super.init()
        
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
        
        self.checkExistingSession()
    }
    
    // MARK: - Session Verification
    
    func checkExistingSession() {
        // Priority: 1. Keychain (Hardware Protected), 2. UserDefaults fallback
        let accessToken = KeychainHelper.shared.get(key: "supabase_access_token")
            ?? UserDefaults.standard.string(forKey: "supabase_access_token")
        
        if let token = accessToken, !token.isEmpty {
            self.applyExistingToken(token)
        } else {
            DispatchQueue.main.async {
                self.isCheckingSession = false
                self.isAuthenticated = false
                self.startWatchPinPairing()
            }
        }
    }
    
    private func applyExistingToken(_ token: String) {
        self.activeAccessToken = token
        let userId = extractUserId(from: token)
        
        // Ensure tokens are mirrored across Keychain, UserDefaults, and Widget AppGroup
        KeychainHelper.shared.save(key: "supabase_access_token", value: token)
        UserDefaults.standard.set(token, forKey: "supabase_access_token")
        if let groupPrefs = UserDefaults(suiteName: "group.com.intellidream.daily") {
            groupPrefs.set(token, forKey: "supabase_access_token")
        }
        
        let options = SupabaseClientOptions(
            auth: SupabaseClientOptions.AuthOptions(
                autoRefreshToken: false,
                emitLocalSessionAsInitialSession: true
            )
        )
        self.supabaseClient = SupabaseClient(supabaseURL: supabaseUrl, supabaseKey: supabaseAnonKey, options: options)
        self.listenToAuthState()
        
        DispatchQueue.main.async {
            self.currentUserId = userId
            self.isAuthenticated = true
            self.isCheckingSession = false
            self.isPairing = false
        }
        
        Task {
            // Attempt setSession without treating empty refresh token as a fatal failure
            let refreshToken = UserDefaults.standard.string(forKey: "supabase_refresh_token") ?? ""
            try? await self.supabaseClient?.auth.setSession(accessToken: token, refreshToken: refreshToken)
            
            // Check for repair tokens safely in the background
            await self.checkForRepairTokens()
        }
    }
    
    // MARK: - Watch-Driven PIN Pairing (New Standard)
    
    /// Generates a 6-digit random PIN, posts it to Supabase `watch_pairing_codes`,
    /// and polls until the desktop or mobile client claims it.
    func startWatchPinPairing() {
        pollTimer?.invalidate()
        let pin = String(format: "%06d", Int.random(in: 100000...999999))
        
        DispatchQueue.main.async {
            self.pairingPin = pin
            self.isPairing = true
            self.pairingStatus = "Connecting to cloud..."
            self.errorMessage = ""
        }
        
        Task {
            do {
                let postUrl = supabaseUrl.appendingPathComponent("rest/v1/watch_pairing_codes")
                var request = URLRequest(url: postUrl)
                request.httpMethod = "POST"
                request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
                request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("return=representation", forHTTPHeaderField: "Prefer")
                request.httpBody = try JSONSerialization.data(withJSONObject: ["pin_code": pin])
                
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                    DispatchQueue.main.async {
                        self.pairingStatus = "Waiting for Daily on PC..."
                        self.startPolling(pin: pin)
                    }
                } else {
                    DispatchQueue.main.async {
                        self.pairingStatus = "Waiting for Daily on PC..."
                        // Even if 409 (conflict), we still poll in case it exists
                        self.startPolling(pin: pin)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Network error: \(error.localizedDescription)"
                    self.pairingStatus = "Tap retry to reconnect"
                }
            }
        }
    }
    
    private func startPolling(pin: String) {
        pollTimer?.invalidate()
        DispatchQueue.main.async {
            self.pollTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
                self?.pollPairingStatus(pin: pin)
            }
        }
    }
    
    private func pollPairingStatus(pin: String) {
        Task {
            do {
                guard var components = URLComponents(url: supabaseUrl.appendingPathComponent("rest/v1/watch_pairing_codes"), resolvingAgainstBaseURL: false) else { return }
                components.queryItems = [
                    URLQueryItem(name: "pin_code", value: "eq.\(pin)"),
                    URLQueryItem(name: "select", value: "*")
                ]
                guard let url = components.url else { return }
                
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
                request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.cachePolicy = .reloadIgnoringLocalCacheData
                
                let (data, _) = try await URLSession.shared.data(for: request)
                let records = try JSONDecoder().decode([WatchPairingCodeRecord].self, from: data)
                
                if let record = records.first, record.claimed == true, let token = record.access_token, !token.isEmpty {
                    // Success! Desktop has claimed the PIN and generated the 10-year watch token.
                    DispatchQueue.main.async {
                        self.pollTimer?.invalidate()
                        self.pollTimer = nil
                        self.pairingStatus = "Paired Successfully!"
                        WKInterfaceDevice.current().play(.notification)
                    }
                    
                    let refresh = record.refresh_token ?? ""
                    KeychainHelper.shared.save(key: "supabase_access_token", value: token)
                    UserDefaults.standard.set(token, forKey: "supabase_access_token")
                    UserDefaults.standard.set(refresh, forKey: "supabase_refresh_token")
                    if let groupPrefs = UserDefaults(suiteName: "group.com.intellidream.daily") {
                        groupPrefs.set(token, forKey: "supabase_access_token")
                    }
                    
                    self.activeAccessToken = token
                    let userId = self.extractUserId(from: token)
                    
                    let options = SupabaseClientOptions(
                        auth: SupabaseClientOptions.AuthOptions(
                            autoRefreshToken: false,
                            emitLocalSessionAsInitialSession: true
                        )
                    )
                    self.supabaseClient = SupabaseClient(supabaseURL: self.supabaseUrl, supabaseKey: self.supabaseAnonKey, options: options)
                    self.listenToAuthState()
                    
                    try? await self.supabaseClient?.auth.setSession(accessToken: token, refreshToken: refresh)
                    
                    DispatchQueue.main.async {
                        self.currentUserId = userId
                        self.isAuthenticated = true
                        self.isPairing = false
                        self.isCheckingSession = false
                    }
                    
                    // Cleanup pairing row
                    _ = try? await self.baseClient.from("watch_pairing_codes").delete().eq("pin_code", value: pin).execute()
                    
                    // Register paired watch record
                    await self.registerPairing(accessToken: token)
                }
            } catch {
                print("Polling error: \(error)")
            }
        }
    }
    
    // MARK: - Lifecycle & Session Resilience
    
    /// Called when the watch app returns to foreground.
    /// NEVER forces logout on empty refresh tokens or network glitches.
    func onAppBecameActive() {
        let accessToken = KeychainHelper.shared.get(key: "supabase_access_token")
            ?? UserDefaults.standard.string(forKey: "supabase_access_token")
        
        if let token = accessToken, !token.isEmpty {
            if !self.isAuthenticated {
                self.applyExistingToken(token)
            } else {
                Task {
                    await self.checkForRepairTokens()
                }
            }
        }
    }
    
    private func listenToAuthState() {
        authStateTask?.cancel()
        authStateTask = Task { [weak self] in
            guard let self = self else { return }
            guard let client = self.supabaseClient else { return }
            
            for await state in client.auth.authStateChanges {
                if state.event == .signedOut {
                    // Do NOT log out. watchOS kills background refresh timers frequently,
                    // which causes the SDK to emit spurious .signedOut events.
                    // The 10-year access token remains perfectly valid for direct queries.
                    continue
                }
                
                if let session = state.session {
                    DispatchQueue.main.async {
                        KeychainHelper.shared.save(key: "supabase_access_token", value: session.accessToken)
                        UserDefaults.standard.set(session.accessToken, forKey: "supabase_access_token")
                        UserDefaults.standard.set(session.refreshToken, forKey: "supabase_refresh_token")
                        if let groupPrefs = UserDefaults(suiteName: "group.com.intellidream.daily") {
                            groupPrefs.set(session.accessToken, forKey: "supabase_access_token")
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Logout & Unpair
    
    /// Clean user-initiated unpair or confirmed remote deletion.
    func logout() {
        pollTimer?.invalidate()
        pollTimer = nil
        authStateTask?.cancel()
        
        // Deactivate paired_watches row if we know our ID
        if let pairId = UserDefaults.standard.string(forKey: "paired_watch_id"),
           let token = self.activeAccessToken {
            Task {
                var req = URLRequest(url: self.supabaseUrl.appendingPathComponent("rest/v1/paired_watches?id=eq.\(pairId)"))
                req.httpMethod = "PATCH"
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                req.setValue(self.supabaseAnonKey, forHTTPHeaderField: "apikey")
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try? JSONSerialization.data(withJSONObject: ["is_active": false])
                _ = try? await URLSession.shared.data(for: req)
            }
        }
        
        KeychainHelper.shared.clearAll()
        UserDefaults.standard.removeObject(forKey: "supabase_access_token")
        UserDefaults.standard.removeObject(forKey: "supabase_refresh_token")
        UserDefaults.standard.removeObject(forKey: "paired_watch_id")
        if let groupPrefs = UserDefaults(suiteName: "group.com.intellidream.daily") {
            groupPrefs.removeObject(forKey: "supabase_access_token")
            groupPrefs.removeObject(forKey: "bubbles_cache")
            groupPrefs.removeObject(forKey: "smokes_cache")
        }
        
        DispatchQueue.main.async {
            self.activeAccessToken = nil
            self.isAuthenticated = false
            self.isCheckingSession = false
            self.currentUserId = nil
            self.supabaseClient = nil
            self.startWatchPinPairing()
        }
    }
    
    // MARK: - Paired Watches Management
    
    private func registerPairing(accessToken: String) async {
        guard let userId = self.extractUserId(from: accessToken) else { return }
        
        let record: [String: String] = [
            "user_id": userId.uuidString.lowercased(),
            "platform": "watchos",
            "device_name": "Apple Watch"
        ]
        
        do {
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
    
    @discardableResult
    private func checkForRepairTokens() async -> Bool {
        guard let pairId = UserDefaults.standard.string(forKey: "paired_watch_id"),
              let activeToken = self.activeAccessToken else { return false }
        
        do {
            guard var components = URLComponents(url: supabaseUrl.appendingPathComponent("rest/v1/paired_watches"), resolvingAgainstBaseURL: false) else { return false }
            components.queryItems = [
                URLQueryItem(name: "id", value: "eq.\(pairId)"),
                URLQueryItem(name: "select", value: "pending_access_token,pending_refresh_token,is_active")
            ]
            guard let url = components.url else { return false }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(activeToken)", forHTTPHeaderField: "Authorization")
            request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.cachePolicy = .reloadIgnoringLocalCacheData
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let rows = try JSONDecoder().decode([PairedWatchRecord].self, from: data)
            
            // Only unpair if the desktop app explicitly marked this watch row as is_active == false
            if let row = rows.first, row.is_active == false {
                print("Remote unpair detected. Logging out.")
                DispatchQueue.main.async { self.logout() }
                return true
            }
            
            // If repair tokens were pushed
            if let row = rows.first, let token = row.pending_access_token, !token.isEmpty {
                let refresh = row.pending_refresh_token ?? ""
                KeychainHelper.shared.save(key: "supabase_access_token", value: token)
                UserDefaults.standard.set(token, forKey: "supabase_access_token")
                UserDefaults.standard.set(refresh, forKey: "supabase_refresh_token")
                self.applyExistingToken(token)
                
                // Clear pending repair tokens
                var clearRequest = URLRequest(url: supabaseUrl.appendingPathComponent("rest/v1/paired_watches?id=eq.\(pairId)"))
                clearRequest.httpMethod = "PATCH"
                clearRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                clearRequest.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
                clearRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                clearRequest.httpBody = try JSONSerialization.data(withJSONObject: [
                    "pending_access_token": NSNull(),
                    "pending_refresh_token": NSNull()
                ] as [String : Any])
                _ = try? await URLSession.shared.data(for: clearRequest)
            }
            return false
        } catch {
            return false
        }
    }
    
    // MARK: - JWT Helpers
    
    func extractUserId(from jwt: String) -> UUID? {
        let parts = jwt.components(separatedBy: ".")
        guard parts.count == 3 else { return nil }
        
        var base64 = parts[1]
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 = base64.padding(toLength: base64.count + 4 - remainder, withPad: "=", startingAt: 0)
        }
        base64 = base64.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let sub = json["sub"] as? String else {
            return nil
        }
        
        return UUID(uuidString: sub)
    }
    
    // MARK: - WCSessionDelegate (Secondary Companion Channel)
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        handleReceivedSession(userInfo: userInfo)
    }
    
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        handleReceivedSession(userInfo: applicationContext)
    }
    
    private func handleReceivedSession(userInfo: [String: Any]) {
        guard let token = userInfo["supabase_access_token"] as? String, !token.isEmpty else { return }
        DispatchQueue.main.async {
            self.applyExistingToken(token)
        }
    }
}
