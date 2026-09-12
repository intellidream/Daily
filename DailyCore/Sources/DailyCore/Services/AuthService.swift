import Foundation
import Supabase
import AuthenticationServices
import Combine

/// Manages authentication across DayOne (Google OAuth PKCE, Apple Sign-In, and Guest mode).
@MainActor
public final class AuthService: NSObject, ObservableObject {
    public static let shared = AuthService()
    
    @Published public private(set) var sessionState: AuthSessionState = .initializing
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var statusMessage: String = ""
    @Published public private(set) var errorMessage: String? = nil
    
    private let supabase = SupabaseService.shared.client
    private let storage = GroupDefaults.shared
    private let keychain = KeychainManager.shared
    
    // Holds the active ASWebAuthenticationSession and context helper to prevent premature deallocation
    private var webAuthSession: ASWebAuthenticationSession?
    private var presentationHelper: PresentationContextHelper?
    
    public var currentUser: UserProfile? {
        sessionState.profile
    }
    
    public var isAuthenticated: Bool {
        if case .authenticated = sessionState { return true }
        return false
    }
    
    public var isGuest: Bool {
        if case .guest = sessionState { return true }
        return false
    }
    
    public override init() {
        super.init()
        Task {
            await checkExistingSession()
        }
    }
    
    // MARK: - Session Hydration
    
    public func checkExistingSession() async {
        isLoading = true
        statusMessage = "Verifying session..."
        errorMessage = nil
        
        // Check if guest mode was selected previously
        if storage.isGuestMode {
            sessionState = .guest
            isLoading = false
            return
        }
        
        do {
            let session = try await supabase.auth.session
            let profile = createProfile(from: session.user)
            sessionState = .authenticated(profile)
            
            // Mirror tokens to AppGroup for widgets/watchOS
            storage.setTokenMirror(
                accessToken: session.accessToken,
                refreshToken: session.refreshToken,
                userId: session.user.id.uuidString
            )
            
            Task { @MainActor in
                await SavedArticlesService.shared.syncWithSupabase()
            }
        } catch {
            sessionState = .unauthenticated
        }
        
        isLoading = false
        statusMessage = ""
    }
    
    // MARK: - Guest Mode
    
    public func continueAsGuest() {
        storage.isGuestMode = true
        sessionState = .guest
        errorMessage = nil
    }
    
    // MARK: - Sign In with Google (PKCE flow via ASWebAuthenticationSession)
    
    public func signInWithGoogle(presentationAnchor: ASPresentationAnchor) async -> Bool {
        isLoading = true
        statusMessage = "Opening Google sign-in..."
        errorMessage = nil
        
        let callbackScheme = "com.intellidream.daily"
        guard let redirectUrl = URL(string: "\(callbackScheme)://login-callback") else {
            errorMessage = "Invalid redirect URL configuration."
            isLoading = false
            return false
        }
        
        do {
            let signInUrl = try supabase.auth.getOAuthSignInURL(
                provider: .google,
                scopes: "https://www.googleapis.com/auth/youtube.readonly",
                redirectTo: redirectUrl,
                queryParams: [(name: "access_type", value: "offline")]
            )
            
            statusMessage = "Waiting for Google authorization..."
            
            let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                let session = ASWebAuthenticationSession(
                    url: signInUrl,
                    callbackURLScheme: callbackScheme
                ) { url, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let url = url {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(throwing: NSError(domain: "AuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No callback received."]))
                    }
                }
                
                let helper = PresentationContextHelper(anchor: presentationAnchor)
                self.presentationHelper = helper
                session.presentationContextProvider = helper
                session.prefersEphemeralWebBrowserSession = false
                self.webAuthSession = session
                
                if !session.start() {
                    continuation.resume(throwing: NSError(domain: "AuthService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to present auth session."]))
                }
            }
            
            statusMessage = "Exchanging session..."
            let session = try await supabase.auth.session(from: callbackURL)
            let profile = createProfile(from: session.user)
            
            storage.isGuestMode = false
            storage.setTokenMirror(
                accessToken: session.accessToken,
                refreshToken: session.refreshToken,
                userId: session.user.id.uuidString
            )
            
            sessionState = .authenticated(profile)
            Task { @MainActor in
                await SavedArticlesService.shared.syncWithSupabase()
            }
            isLoading = false
            statusMessage = "Success!"
            return true
            
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            statusMessage = ""
            isLoading = false
            return false
        } catch {
            errorMessage = "Google sign-in failed: \(error.localizedDescription)"
            isLoading = false
            statusMessage = ""
            return false
        }
    }
    
    // MARK: - Sign In with Apple (Native OpenIDConnect exchange)
    
    public func signInWithApple(idToken: String, nonce: String, fullName: PersonNameComponents?) async -> Bool {
        isLoading = true
        statusMessage = "Authenticating with Apple..."
        errorMessage = nil
        
        do {
            let session = try await supabase.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .apple,
                    idToken: idToken,
                    nonce: nonce
                )
            )
            
            // Build profile with full name if Apple provided it
            var nameString: String? = nil
            if let fullName = fullName {
                nameString = PersonNameComponentsFormatter().string(from: fullName)
            }
            
            var profile = createProfile(from: session.user)
            if profile.fullName == nil || profile.fullName?.isEmpty == true {
                profile = UserProfile(
                    id: profile.id,
                    email: profile.email,
                    fullName: nameString ?? profile.fullName,
                    avatarUrl: profile.avatarUrl,
                    provider: .apple,
                    createdAt: profile.createdAt
                )
            }
            
            storage.isGuestMode = false
            storage.setTokenMirror(
                accessToken: session.accessToken,
                refreshToken: session.refreshToken,
                userId: session.user.id.uuidString
            )
            
            sessionState = .authenticated(profile)
            Task { @MainActor in
                await SavedArticlesService.shared.syncWithSupabase()
            }
            isLoading = false
            statusMessage = "Success!"
            return true
            
        } catch {
            errorMessage = "Apple sign-in failed: \(error.localizedDescription)"
            isLoading = false
            statusMessage = ""
            return false
        }
    }
    
    // MARK: - Sign Out
    
    public func signOut() async {
        isLoading = true
        statusMessage = "Signing out..."
        
        try? await supabase.auth.signOut()
        
        keychain.clearAllAuthTokens()
        storage.clearTokenMirror()
        storage.isGuestMode = false
        
        sessionState = .unauthenticated
        isLoading = false
        statusMessage = ""
        errorMessage = nil
    }
    
    // MARK: - User Profile Mapping
    
    private func createProfile(from user: User) -> UserProfile {
        var fullName: String? = nil
        var avatarUrl: String? = nil
        
        // Extract metadata
        let metadata = user.userMetadata
        if let metaName = metadata["full_name"]?.stringValue ?? metadata["name"]?.stringValue {
            fullName = metaName
        }
        if let avatar = metadata["avatar_url"]?.stringValue ?? metadata["picture"]?.stringValue {
            avatarUrl = avatar
        }
        
        let provider: AuthProvider = user.appMetadata["provider"]?.stringValue == "apple" ? .apple : .google
        
        return UserProfile(
            id: user.id.uuidString,
            email: user.email,
            fullName: fullName,
            avatarUrl: avatarUrl,
            provider: provider,
            createdAt: user.createdAt
        )
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding Helper

private final class PresentationContextHelper: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let anchor: ASPresentationAnchor
    
    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
        super.init()
    }
    
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}
