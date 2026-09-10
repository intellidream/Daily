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
        KeychainManager.shared.save(key: key, data: value)
        if let str = String(data: value, encoding: .utf8) {
            GroupDefaults.shared.userDefaults.set(str, forKey: key)
        }
    }
    
    public func retrieve(key: String) throws -> Data? {
        if let data = KeychainManager.shared.getData(key: key) {
            return data
        }
        if let str = GroupDefaults.shared.userDefaults.string(forKey: key) {
            return str.data(using: .utf8)
        }
        return nil
    }
    
    public func remove(key: String) throws {
        KeychainManager.shared.delete(key: key)
        GroupDefaults.shared.userDefaults.removeObject(forKey: key)
    }
}
