import Foundation
import Security

/// Secure Keychain management supporting shared App Group access across iOS, WatchOS, and macOS.
public final class KeychainManager: @unchecked Sendable {
    public static let shared = KeychainManager()
    
    public let accessGroup: String?
    private let serviceName = "com.intellidream.daily"
    
    public init(accessGroup: String? = "group.com.intellidream.daily") {
        self.accessGroup = accessGroup
    }
    
    @discardableResult
    public func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        return save(key: key, data: data)
    }
    
    @discardableResult
    public func save(key: String, data: Data) -> Bool {
        delete(key: key)
        
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        // Only set access group if available on the platform and device
        #if !targetEnvironment(simulator)
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        #endif
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        // If failed with group permission error, fallback without access group
        if status != errSecSuccess && accessGroup != nil {
            query.removeValue(forKey: kSecAttrAccessGroup as String)
            return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
        }
        
        return status == errSecSuccess
    }
    
    public func get(key: String) -> String? {
        guard let data = getData(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    public func getData(key: String) -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        #if !targetEnvironment(simulator)
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        #endif
        
        var result: AnyObject?
        var status = SecItemCopyMatching(query as CFDictionary, &result)
        
        // Fallback without group if item was stored locally
        if status != errSecSuccess && accessGroup != nil {
            query.removeValue(forKey: kSecAttrAccessGroup as String)
            status = SecItemCopyMatching(query as CFDictionary, &result)
        }
        
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return data
    }
    
    @discardableResult
    public func delete(key: String) -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        
        #if !targetEnvironment(simulator)
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        #endif
        
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && accessGroup != nil {
            query.removeValue(forKey: kSecAttrAccessGroup as String)
            return SecItemDelete(query as CFDictionary) == errSecSuccess
        }
        
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    public func clearAllAuthTokens() {
        delete(key: "supabase_access_token")
        delete(key: "supabase_refresh_token")
        delete(key: "supabase_user_id")
    }
}
