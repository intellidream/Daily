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
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        
        // Only set access group if available on the platform and device
        #if !targetEnvironment(simulator)
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        #endif
        
        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data
        ]
        
        // 1. Attempt non-destructive in-place update first to preserve Keychain ACL and user permissions
        var status = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        
        // 2. If item does not exist yet (errSecItemNotFound / -25300), create it fresh with SecItemAdd
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            
            status = SecItemAdd(addQuery as CFDictionary, nil)
            
            // If failed with group permission error, fallback without access group
            if status != errSecSuccess && accessGroup != nil {
                addQuery.removeValue(forKey: kSecAttrAccessGroup as String)
                status = SecItemAdd(addQuery as CFDictionary, nil)
            }
        } else if status != errSecSuccess && accessGroup != nil {
            // Update may have failed due to accessGroup mismatch; try fallback without access group
            query.removeValue(forKey: kSecAttrAccessGroup as String)
            status = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
            if status == errSecItemNotFound {
                var addQuery = query
                addQuery[kSecValueData as String] = data
                addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
                status = SecItemAdd(addQuery as CFDictionary, nil)
            }
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
