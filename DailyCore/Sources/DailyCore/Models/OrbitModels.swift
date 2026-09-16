import Foundation

/// Supported smartwatch platforms in the DayOne Orbit ecosystem.
public enum WatchPlatform: String, Codable, CaseIterable, Identifiable, Sendable {
    case watchOS = "watchos"
    case wearOS = "wearos"
    case harmonyOS = "harmonyos"
    case zeppOS = "zeppos"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .watchOS: return "Apple Watch"
        case .wearOS: return "Wear OS"
        case .harmonyOS: return "HarmonyOS"
        case .zeppOS: return "Zepp OS"
        }
    }
    
    public var shortDisplayName: String {
        switch self {
        case .watchOS: return "Apple"
        case .wearOS: return "Wear OS"
        case .harmonyOS: return "Harmony"
        case .zeppOS: return "Zepp OS"
        }
    }
    
    public var defaultDeviceName: String {
        switch self {
        case .watchOS: return "Apple Watch"
        case .wearOS: return "Wear OS Watch"
        case .harmonyOS: return "HarmonyOS Watch"
        case .zeppOS: return "Zepp OS Watch"
        }
    }
    
    public var systemImage: String {
        switch self {
        case .watchOS: return "applewatch"
        case .wearOS: return "watch.analog"
        case .harmonyOS: return "circle.grid.cross"
        case .zeppOS: return "speedometer"
        }
    }
    
    public var brandColorHex: String {
        switch self {
        case .watchOS: return "#30D158" // Green / Apple Watch
        case .wearOS: return "#4285F4"  // Google Blue
        case .harmonyOS: return "#FF3B30" // Red
        case .zeppOS: return "#00D2FF"  // Cyan
        }
    }
}

/// Represents a linked smartwatch in the `paired_watches` database table.
public struct PairedWatch: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let userId: String
    public let platform: String
    public var deviceName: String?
    public var pairedAt: Date?
    public var lastTokenPush: Date?
    public var pendingAccessToken: String?
    public var pendingRefreshToken: String?
    public var isActive: Bool
    
    public var platformType: WatchPlatform? {
        WatchPlatform(rawValue: platform.lowercased())
    }
    
    public var displayTitle: String {
        if let name = deviceName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return platformType?.displayName ?? "Smartwatch"
    }
    
    public init(
        id: String = UUID().uuidString.lowercased(),
        userId: String,
        platform: String,
        deviceName: String? = nil,
        pairedAt: Date? = Date(),
        lastTokenPush: Date? = Date(),
        pendingAccessToken: String? = nil,
        pendingRefreshToken: String? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.userId = userId
        self.platform = platform
        self.deviceName = deviceName
        self.pairedAt = pairedAt
        self.lastTokenPush = lastTokenPush
        self.pendingAccessToken = pendingAccessToken
        self.pendingRefreshToken = pendingRefreshToken
        self.isActive = isActive
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case platform
        case deviceName = "device_name"
        case pairedAt = "paired_at"
        case lastTokenPush = "last_token_push"
        case pendingAccessToken = "pending_access_token"
        case pendingRefreshToken = "pending_refresh_token"
        case isActive = "is_active"
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.userId = try container.decode(String.self, forKey: .userId)
        self.platform = try container.decode(String.self, forKey: .platform)
        self.deviceName = try container.decodeIfPresent(String.self, forKey: .deviceName)
        self.pendingAccessToken = try container.decodeIfPresent(String.self, forKey: .pendingAccessToken)
        self.pendingRefreshToken = try container.decodeIfPresent(String.self, forKey: .pendingRefreshToken)
        self.isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        
        // Flexible Date decoding (ISO8601 string or Date)
        if let date = try? container.decodeIfPresent(Date.self, forKey: .pairedAt) {
            self.pairedAt = date
        } else if let dateStr = try? container.decodeIfPresent(String.self, forKey: .pairedAt) {
            self.pairedAt = HabitDateParser.parse(dateStr)
        } else {
            self.pairedAt = nil
        }
        
        if let push = try? container.decodeIfPresent(Date.self, forKey: .lastTokenPush) {
            self.lastTokenPush = push
        } else if let pushStr = try? container.decodeIfPresent(String.self, forKey: .lastTokenPush) {
            self.lastTokenPush = HabitDateParser.parse(pushStr)
        } else {
            self.lastTokenPush = nil
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(platform, forKey: .platform)
        try container.encodeIfPresent(deviceName, forKey: .deviceName)
        try container.encodeIfPresent(pendingAccessToken, forKey: .pendingAccessToken)
        try container.encodeIfPresent(pendingRefreshToken, forKey: .pendingRefreshToken)
        try container.encode(isActive, forKey: .isActive)
        
        if let pairedAt = pairedAt {
            try container.encode(ISO8601DateFormatter().string(from: pairedAt), forKey: .pairedAt)
        }
        if let lastTokenPush = lastTokenPush {
            try container.encode(ISO8601DateFormatter().string(from: lastTokenPush), forKey: .lastTokenPush)
        }
    }
}

/// Represents a record in the `watch_pairing_codes` table.
public struct WatchPairingCodeRecord: Codable, Sendable {
    public let pinCode: String
    public var userId: String?
    public var accessToken: String?
    public var refreshToken: String?
    public var createdAt: String?
    public var expiresAt: String?
    public var claimed: Bool?
    
    public init(
        pinCode: String,
        userId: String? = nil,
        accessToken: String? = nil,
        refreshToken: String? = nil,
        createdAt: String? = nil,
        expiresAt: String? = nil,
        claimed: Bool? = false
    ) {
        self.pinCode = pinCode
        self.userId = userId
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.claimed = claimed
    }
    
    enum CodingKeys: String, CodingKey {
        case pinCode = "pin_code"
        case userId = "user_id"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case claimed
    }
}
