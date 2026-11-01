import Foundation
import Supabase

/// Centralized Supabase client for the DayOne ecosystem.
public final class SupabaseService: @unchecked Sendable {
    public static let shared = SupabaseService()
    
    public let supabaseUrl = URL(string: "https://akkfouifxztnfwwiclwg.supabase.co")!
    public let supabaseAnonKey = "sb_publishable_6FzrRSdmsH4arDhZS09PSQ_QK_I31DG"
    
    public let client: SupabaseClient
    
    public init() {
        let options = SupabaseClientOptions(
            auth: SupabaseClientOptions.AuthOptions(
                storage: SupabaseKeychainStorage(),
                autoRefreshToken: true,
                emitLocalSessionAsInitialSession: true
            )
        )
        self.client = SupabaseClient(supabaseURL: supabaseUrl, supabaseKey: supabaseAnonKey, options: options)
    }
}

/// Custom storage adapter backing Supabase Auth sessions to KeychainManager and GroupDefaults.
public final class SupabaseKeychainStorage: AuthLocalStorage, @unchecked Sendable {
    public init() {}
    
    public func store(key: String, value: Data) throws {
        #if os(macOS)
        // On macOS App Sandbox without Keychain Sharing provisioning profile,
        // login.keychain-db triggers SecurityAgent password prompts on every access.
        // GroupDefaults is team-isolated (7LZ9ZT2Z5B), FileVault-encrypted, and silent across builds and widgets.
        if let str = String(data: value, encoding: .utf8) {
            GroupDefaults.shared.userDefaults.set(str, forKey: key)
        }
        #else
        KeychainManager.shared.save(key: key, data: value)
        if let str = String(data: value, encoding: .utf8) {
            GroupDefaults.shared.userDefaults.set(str, forKey: key)
        }
        #endif
    }
    
    public func retrieve(key: String) throws -> Data? {
        #if os(macOS)
        // On macOS, retrieve from GroupDefaults directly to eliminate legacy login.keychain-db prompt loops
        if let str = GroupDefaults.shared.userDefaults.string(forKey: key) {
            return str.data(using: .utf8)
        }
        return nil
        #else
        if let data = KeychainManager.shared.getData(key: key) {
            return data
        }
        if let str = GroupDefaults.shared.userDefaults.string(forKey: key) {
            return str.data(using: .utf8)
        }
        return nil
        #endif
    }
    
    public func remove(key: String) throws {
        #if !os(macOS)
        KeychainManager.shared.delete(key: key)
        #endif
        GroupDefaults.shared.userDefaults.removeObject(forKey: key)
    }
}
