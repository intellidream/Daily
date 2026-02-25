import Foundation
import Supabase
import Combine
import SwiftUI

// Struct to match the Supabase table for decoding
struct WatchPairing: Codable {
    let code: String
    let access_token: String?
    let refresh_token: String?
    let created_at: String?
}

class WatchSessionManager: ObservableObject {
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
    
    private init() {
        let options = SupabaseClientOptions(auth: SupabaseClientOptions.AuthOptions(emitLocalSessionAsInitialSession: true))
        self.baseClient = SupabaseClient(supabaseURL: supabaseUrl, supabaseKey: supabaseAnonKey, options: options)
        self.checkExistingSession()
    }
    
    func checkExistingSession() {
        if let accessToken = UserDefaults.standard.string(forKey: "supabase_access_token"),
           let refreshToken = UserDefaults.standard.string(forKey: "supabase_refresh_token") {
            
            // Initialize the main client right away so auth can take over
            let options = SupabaseClientOptions(auth: SupabaseClientOptions.AuthOptions(emitLocalSessionAsInitialSession: true))
            self.supabaseClient = SupabaseClient(supabaseURL: supabaseUrl, supabaseKey: supabaseAnonKey, options: options)
            
            Task {
                do {
                    // This command tells the Supabase Swift library to take ownership of these tokens.
                    // It will automatically refresh them in the background when they expire!
                    try await self.supabaseClient?.auth.setSession(accessToken: accessToken, refreshToken: refreshToken)
                    
                    DispatchQueue.main.async {
                        // Extract user_id from the active JWT token
                        if let userId = self.extractUserId(from: accessToken) {
                            self.currentUserId = userId
                        }
                        self.isAuthenticated = true
                        self.isPairing = false
                        
                        // Mirror the active token to the Widget Extension App Group
                        if let groupPrefs = UserDefaults(suiteName: "group.com.intellidream.daily") {
                            groupPrefs.set(accessToken, forKey: "supabase_access_token")
                        }
                    }
                } catch {
                    // Session restoration failed (e.g., refresh token is completely dead/revoked)
                    DispatchQueue.main.async {
                        self.logout()
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
                let pairing = WatchPairing(code: self.pairingCode, access_token: nil, refresh_token: nil, created_at: nil)
                try await baseClient.from("watch_pairings").insert(pairing).execute()
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
                        let options = SupabaseClientOptions(auth: SupabaseClientOptions.AuthOptions(emitLocalSessionAsInitialSession: true))
                        self.supabaseClient = SupabaseClient(supabaseURL: supabaseUrl, supabaseKey: supabaseAnonKey, options: options)
                        
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
                    } else {
                        // Reached row but token is null, just wait
                    }
                } else {
                     DispatchQueue.main.async {
                         self.errorMessage = "Row deleted/missing"
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
    
    func logout() {
        UserDefaults.standard.removeObject(forKey: "supabase_access_token")
        UserDefaults.standard.removeObject(forKey: "supabase_refresh_token")
        if let groupPrefs = UserDefaults(suiteName: "group.com.intellidream.daily") {
            groupPrefs.removeObject(forKey: "supabase_access_token")
        }
        
        self.isAuthenticated = false
        self.currentUserId = nil
        self.supabaseClient = nil
        self.generatePairingCode()
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
}
