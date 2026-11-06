import Foundation
import CryptoKit

// MARK: - CLI Login Ephemeral Handshake & Crypto Helpers

public struct SupabaseCliLoginHandshake: Sendable {
    public let sessionId: String
    public let tokenName: String
    public let publicKeyHex: String
    public let loginUrl: URL
    private let privateKeyRaw: Data

    public init(platformLabel: String) {
        let sid = UUID().uuidString.lowercased()
        let sanitizedPlatform = platformLabel.replacingOccurrences(
            of: "[^A-Za-z0-9_]",
            with: "_",
            options: .regularExpression
        )
        let ts = Int(Date().timeIntervalSince1970)
        let tName = "DayOne_Admin_\(sanitizedPlatform)_\(ts)"

        let privKey = P256.KeyAgreement.PrivateKey()
        // ANSI X9.63 uncompressed representation: 0x04 || X(32) || Y(32) -> 65 bytes -> 130 hex chars
        let pubHex = SupabaseAdminCrypto.hexEncode(privKey.publicKey.x963Representation)

        self.sessionId = sid
        self.tokenName = tName
        self.publicKeyHex = pubHex
        self.privateKeyRaw = privKey.rawRepresentation

        var components = URLComponents(string: "https://supabase.com/dashboard/cli/login")!
        components.queryItems = [
            URLQueryItem(name: "session_id", value: sid),
            URLQueryItem(name: "token_name", value: tName),
            URLQueryItem(name: "public_key", value: pubHex)
        ]
        self.loginUrl = components.url!
    }

    public func decryptToken(encryptedHex: String, serverPublicKeyHex: String, nonceHex: String) throws -> String {
        let privKey = try P256.KeyAgreement.PrivateKey(rawRepresentation: privateKeyRaw)
        return try SupabaseAdminCrypto.decryptCliToken(
            clientPrivateKey: privKey,
            encryptedTokenHex: encryptedHex,
            serverPublicKeyHex: serverPublicKeyHex,
            nonceHex: nonceHex
        )
    }
}

public enum SupabaseAdminCryptoError: LocalizedError {
    case invalidHexPayload
    case invalidCiphertextLength
    case invalidUtf8Token

    public var errorDescription: String? {
        switch self {
        case .invalidHexPayload:
            return "Invalid hexadecimal cryptographic payload returned by Supabase."
        case .invalidCiphertextLength:
            return "Encrypted token payload is shorter than the 16-byte AES-GCM authentication tag."
        case .invalidUtf8Token:
            return "Decrypted Supabase Management token is not valid UTF-8."
        }
    }
}

public enum SupabaseAdminCrypto {
    /// Decrypts the AES-256-GCM payload from `GET /platform/cli/login/{session_id}?device_code=...`
    /// using the raw 32-byte P-256 ECDH shared secret X-coordinate (matching Node `crypto.createECDH('prime256v1').computeSecret`).
    public static func decryptCliToken(
        clientPrivateKey: P256.KeyAgreement.PrivateKey,
        encryptedTokenHex: String,
        serverPublicKeyHex: String,
        nonceHex: String
    ) throws -> String {
        guard let serverPubData = hexDecode(serverPublicKeyHex),
              let nonceData = hexDecode(nonceHex),
              let combinedData = hexDecode(encryptedTokenHex) else {
            throw SupabaseAdminCryptoError.invalidHexPayload
        }
        guard combinedData.count > 16 else {
            throw SupabaseAdminCryptoError.invalidCiphertextLength
        }

        let serverPublicKey = try P256.KeyAgreement.PublicKey(x963Representation: serverPubData)
        let sharedSecret = try clientPrivateKey.sharedSecretFromKeyAgreement(with: serverPublicKey)
        let rawSharedKeyData = sharedSecret.withUnsafeBytes { Data($0) }
        let symmetricKey = SymmetricKey(data: rawSharedKeyData)

        let nonce = try AES.GCM.Nonce(data: nonceData)
        let ciphertext = combinedData.dropLast(16)
        let tag = combinedData.suffix(16)

        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        let plaintextData = try AES.GCM.open(sealedBox, using: symmetricKey)

        guard let token = String(data: plaintextData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            throw SupabaseAdminCryptoError.invalidUtf8Token
        }
        return token
    }

    /// Encrypts a plaintext token in the exact format emitted by Supabase `/platform/cli/login` (used for deterministic unit tests).
    public static func encryptCliTokenForTesting(
        plaintextToken: String,
        clientPublicKeyHex: String,
        serverPrivateKey: P256.KeyAgreement.PrivateKey = P256.KeyAgreement.PrivateKey()
    ) throws -> (encryptedHex: String, serverPublicKeyHex: String, nonceHex: String) {
        guard let clientPubData = hexDecode(clientPublicKeyHex) else {
            throw SupabaseAdminCryptoError.invalidHexPayload
        }
        let clientPubKey = try P256.KeyAgreement.PublicKey(x963Representation: clientPubData)
        let sharedSecret = try serverPrivateKey.sharedSecretFromKeyAgreement(with: clientPubKey)
        let symmetricKey = SymmetricKey(data: sharedSecret.withUnsafeBytes { Data($0) })

        let nonce = AES.GCM.Nonce()
        let nonceData = nonce.withUnsafeBytes { Data($0) }
        let sealed = try AES.GCM.seal(Data(plaintextToken.utf8), using: symmetricKey, nonce: nonce)

        var combined = Data()
        combined.append(sealed.ciphertext)
        combined.append(sealed.tag)

        return (
            encryptedHex: hexEncode(combined),
            serverPublicKeyHex: hexEncode(serverPrivateKey.publicKey.x963Representation),
            nonceHex: hexEncode(nonceData)
        )
    }

    public static func hexEncode(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    public static func hexDecode(_ hex: String) -> Data? {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count % 2 == 0, !cleaned.isEmpty else { return nil }
        var bytes = Data(capacity: cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let nextIndex = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<nextIndex], radix: 16) else { return nil }
            bytes.append(byte)
            index = nextIndex
        }
        return bytes
    }

    /// Extracts `device_code` query parameter when `/dashboard/cli/login` completes session creation.
    public static func extractDeviceCode(from urlString: String) -> String? {
        guard let components = URLComponents(string: urlString),
              let host = components.host?.lowercased(),
              host.contains("supabase.com"),
              components.path.contains("/cli/login") else {
            return nil
        }
        if let code = components.queryItems?.first(where: { $0.name == "device_code" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !code.isEmpty {
            return code
        }
        return nil
    }

    /// Detects if GitHub OAuth sign-in redirected the user to `/dashboard/organizations` or `/dashboard/projects`
    /// instead of preserving `/dashboard/cli/login?session_id=...`, allowing the WebView to re-navigate once.
    public static func shouldRecoverCliLoginRedirect(currentUrl: String) -> Bool {
        guard let components = URLComponents(string: currentUrl),
              let host = components.host?.lowercased(),
              host == "supabase.com" || host == "app.supabase.com" else {
            return false
        }
        let path = components.path.lowercased()
        if path.contains("/cli/login") || path.contains("/sign-in") || path.contains("/authorize") || path.contains("/auth") {
            return false
        }
        return path == "/dashboard"
            || path.hasPrefix("/dashboard/org")
            || path.hasPrefix("/dashboard/project")
            || path.hasPrefix("/dashboard/account")
    }

    /// Parses `localStorage['supabase.dashboard.auth.token']` JSON to extract the GoTrue session token & GitHub identity.
    public static func parseDashboardSessionJson(_ rawJson: String?) -> (accessToken: String?, refreshToken: String?, identity: String?) {
        guard let rawJson = rawJson?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawJson.isEmpty,
              let data = rawJson.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, nil, nil)
        }

        // GoTrue stores session either at root or nested inside "currentSession"
        let sessionDict: [String: Any]
        if let nested = root["currentSession"] as? [String: Any] {
            sessionDict = nested
        } else {
            sessionDict = root
        }

        let accessToken = (sessionDict["access_token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let refreshToken = (sessionDict["refresh_token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        var identity: String?
        if let user = sessionDict["user"] as? [String: Any] {
            if let meta = user["user_metadata"] as? [String: Any] {
                if let ghUser = meta["user_name"] as? String, !ghUser.isEmpty {
                    identity = "@\(ghUser)"
                } else if let prefName = meta["preferred_username"] as? String, !prefName.isEmpty {
                    identity = "@\(prefName)"
                }
            }
            if identity == nil, let email = user["email"] as? String, !email.isEmpty {
                identity = email
            }
        }
        return (
            accessToken?.isEmpty == false ? accessToken : nil,
            refreshToken?.isEmpty == false ? refreshToken : nil,
            identity
        )
    }

    /// Maps raw HTTP User-Agent headers from `edge_logs` to DayOne ecosystem devices.
    public static func classifyFleetUserAgent(_ userAgent: String) -> (key: String, displayName: String, sfSymbol: String) {
        let ua = userAgent.lowercased()
        if ua.contains("watchos") || ua.contains("watch") && ua.contains("cfnetwork") {
            return ("watchos", "Apple Watch (watchOS)", "applewatch")
        }
        if ua.contains("macos") || ua.contains("macintosh") || (ua.contains("darwin") && ua.contains("daily") && !ua.contains("iphone") && !ua.contains("ipad")) {
            // Note: CFNetwork on iOS vs macOS - check explicit iOS/macOS tokens first
            if ua.contains("iphone") || ua.contains("ios") {
                return ("ios", "iPhone · Schmitz (iOS)", "iphone")
            }
            return ("macos", "Mac · DayOne Desktop (macOS)", "macbook")
        }
        if ua.contains("iphone") || ua.contains("ipad") || ua.contains("cfnetwork") || ua.contains("supabase-swift") {
            return ("ios", "Apple · iOS / Swift SDK", "iphone")
        }
        if ua.contains("ktor") || ua.contains("okhttp") || ua.contains("dalvik") || ua.contains("android") {
            if ua.contains("wear") {
                return ("wearos", "Pixel Watch (Wear OS)", "applewatch.watchface")
            }
            return ("android", "Android · Radar / Trapper (Kotlin)", "smartphone")
        }
        if ua.contains("windows") || ua.contains("winui") || ua.contains(".net") || ua.contains("supabase-csharp") {
            return ("windows", "Windows 11 · DayOne WinUI", "pc")
        }
        if ua.contains("pg_net") || ua.contains("deno") || ua.contains("edge-runtime") || ua.contains("supabase-functions") {
            return ("cloud_cron", "Supabase Cron & Edge Workers", "cloud.bolt.fill")
        }
        return ("other", "Web & External Clients", "globe")
    }
}
