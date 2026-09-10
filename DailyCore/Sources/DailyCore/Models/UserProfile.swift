import Foundation

public enum AuthProvider: String, Codable, Sendable {
    case google = "google"
    case apple = "apple"
    case email = "email"
    case guest = "guest"
    
    public var displayName: String {
        switch self {
        case .google: return "Google"
        case .apple: return "Apple"
        case .email: return "Email"
        case .guest: return "Guest"
        }
    }
}

public struct UserProfile: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let email: String?
    public let fullName: String?
    public let avatarUrl: String?
    public let provider: AuthProvider
    public let createdAt: Date?
    
    public init(
        id: String,
        email: String? = nil,
        fullName: String? = nil,
        avatarUrl: String? = nil,
        provider: AuthProvider = .guest,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.email = email
        self.fullName = fullName
        self.avatarUrl = avatarUrl
        self.provider = provider
        self.createdAt = createdAt
    }
    
    /// Derives the user's first name using the same heuristic as WinUI's `WinUIAuthService.CurrentUserFirstName`.
    public var firstName: String {
        if let fullName = fullName?.trimmingCharacters(in: .whitespacesAndNewlines), !fullName.isEmpty {
            let parts = fullName.split(separator: " ")
            if let first = parts.first, !first.isEmpty {
                return String(first)
            }
        }
        
        if let email = email, !email.isEmpty {
            let localPart = email.split(separator: "@").first ?? ""
            let nameParts = localPart.split { $0 == "." || $0 == "_" || $0 == "-" }
            if let first = nameParts.first, !first.isEmpty {
                return first.prefix(1).uppercased() + first.dropFirst()
            }
        }
        
        return provider == .guest ? "Friend" : "User"
    }
    
    public static let guest = UserProfile(
        id: "guest_\(UUID().uuidString.prefix(8))",
        email: nil,
        fullName: "Guest User",
        avatarUrl: nil,
        provider: .guest,
        createdAt: Date()
    )
}

public enum AuthSessionState: Equatable, Sendable {
    case initializing
    case unauthenticated
    case authenticated(UserProfile)
    case guest
    
    public var isAuthenticatedOrGuest: Bool {
        switch self {
        case .authenticated, .guest:
            return true
        default:
            return false
        }
    }
    
    public var profile: UserProfile? {
        switch self {
        case .authenticated(let user):
            return user
        case .guest:
            return .guest
        default:
            return nil
        }
    }
}
