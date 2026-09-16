import Foundation
import Supabase
import Combine

/// Manages DayOne Orbit smartwatch connections, PIN pairing, and cloud telemetry synchronization.
@MainActor
public final class OrbitWatchService: ObservableObject {
    public static let shared = OrbitWatchService()
    
    @Published public private(set) var pairedWatches: [PairedWatch] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var isPairing: Bool = false
    @Published public var pairingError: String? = nil
    @Published public var pairingSuccessMessage: String? = nil
    
    private let supabase = SupabaseService.shared.client
    
    public init() {
        Task {
            await loadPairedWatches()
        }
    }
    
    // MARK: - Paired Watches Query
    
    public func loadPairedWatches() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let session = try await supabase.auth.session
            let currentUserId = session.user.id.uuidString.lowercased()
            
            let watches: [PairedWatch] = try await supabase.from("paired_watches")
                .select()
                .eq("user_id", value: currentUserId)
                .eq("is_active", value: true)
                .order("paired_at", ascending: false)
                .execute()
                .value
            
            self.pairedWatches = watches
        } catch {
            // Note: If unauthenticated or offline, pairedWatches stays empty
            print("[OrbitWatchService] Failed to load paired watches: \(error)")
        }
    }
    
    // MARK: - Smartwatch Pairing
    
    /// Links a smartwatch by claiming the 6-digit PIN generated on the watch.
    /// Injects a long-lived (10-year) watch token to prevent background token expiration desyncs.
    public func pairWatch(pin: String, platform: WatchPlatform) async -> Bool {
        let cleanedPin = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanedPin.count == 6, CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: cleanedPin)) else {
            self.pairingError = "Please enter a valid 6-digit numeric PIN."
            self.pairingSuccessMessage = nil
            return false
        }
        
        isPairing = true
        pairingError = nil
        pairingSuccessMessage = nil
        defer { isPairing = false }
        
        do {
            let session = try await supabase.auth.session
            let currentUserId = session.user.id.uuidString.lowercased()
            
            // 1. Find the unclaimed PIN in watch_pairing_codes
            let rows: [WatchPairingCodeRecord] = try await supabase.from("watch_pairing_codes")
                .select()
                .eq("pin_code", value: cleanedPin)
                .eq("claimed", value: false)
                .execute()
                .value
            
            guard let pairingCode = rows.first else {
                self.pairingError = "Invalid PIN or already claimed."
                return false
            }
            
            // 2. Validate expiration (10 min lifetime)
            if let expStr = pairingCode.expiresAt, let expDate = HabitDateParser.parse(expStr), expDate < Date() {
                self.pairingError = "This PIN has expired. Request a new one on your watch."
                return false
            }
            
            // 3. Obtain 10-year watch JWT via RPC generate_watch_token (fallback to active session token)
            var watchToken: String = session.accessToken
            if let rpcToken: String = try? await supabase.rpc("generate_watch_token").execute().value,
               !rpcToken.trimmingCharacters(in: CharacterSet(charactersIn: "\" \n\r\t")).isEmpty {
                watchToken = rpcToken.trimmingCharacters(in: CharacterSet(charactersIn: "\" \n\r\t"))
            } else if let rpcResp = try? await supabase.rpc("generate_watch_token").execute(),
                      let raw = String(data: rpcResp.data, encoding: .utf8)?.trimmingCharacters(in: CharacterSet(charactersIn: "\" \n\r\t")),
                      !raw.isEmpty {
                watchToken = raw
            }
            
            // 4. Claim the pairing record in Supabase
            struct ClaimPayload: Encodable {
                let user_id: String
                let access_token: String
                let refresh_token: String
                let claimed: Bool
            }
            let claimPayload = ClaimPayload(
                user_id: currentUserId,
                access_token: watchToken,
                refresh_token: "",
                claimed: true
            )
            
            try await supabase.from("watch_pairing_codes")
                .update(claimPayload)
                .eq("pin_code", value: cleanedPin)
                .execute()
            
            // 5. Register new watch in paired_watches
            struct InsertPayload: Encodable {
                let id: String
                let user_id: String
                let platform: String
                let device_name: String
                let paired_at: String
                let last_token_push: String
                let is_active: Bool
            }
            let nowIso = ISO8601DateFormatter().string(from: Date())
            let insertPayload = InsertPayload(
                id: UUID().uuidString.lowercased(),
                user_id: currentUserId,
                platform: platform.rawValue,
                device_name: platform.defaultDeviceName,
                paired_at: nowIso,
                last_token_push: nowIso,
                is_active: true
            )
            
            try await supabase.from("paired_watches")
                .insert(insertPayload)
                .execute()
            
            // 6. Reload paired devices and set success state
            await loadPairedWatches()
            self.pairingSuccessMessage = "\(platform.displayName) successfully linked!"
            return true
        } catch {
            print("[OrbitWatchService] Failed to pair watch: \(error)")
            self.pairingError = "An error occurred during pairing: \(error.localizedDescription)"
            return false
        }
    }
    
    // MARK: - Unpair Watch
    
    /// Unpairs a smartwatch by removing its record from paired_watches.
    /// The smartwatch detects this upon returning to foreground and gracefully unpairs.
    public func unpairWatch(id: String) async -> Bool {
        do {
            try await supabase.from("paired_watches")
                .delete()
                .eq("id", value: id)
                .execute()
            
            await loadPairedWatches()
            return true
        } catch {
            print("[OrbitWatchService] Failed to unpair watch: \(error)")
            return false
        }
    }
    
    // MARK: - Sync Frequency Preference
    
    public func setWatchSyncFrequency(_ minutes: Int) {
        SettingsService.shared.update {
            $0.watchSyncFrequency = minutes
        }
    }
}
