import Foundation
import CoreText
#if canImport(SwiftUI)
import SwiftUI
#endif

/// Registers and exposes the bundled `Loreen-Regular.ttf` font once per process.
public enum LoreenFontRegistry {
    public static let postScriptName = "Loreen-Regular"
    public static let familyName = "Loreen"

    private static let lock = NSLock()
    nonisolated(unsafe) private static var didRegister = false
    nonisolated(unsafe) private static var didSucceed = false

    /// Registers `Loreen-Regular.ttf` from `DailyCore`'s `Bundle.module` if not already registered.
    @discardableResult
    public static func registerIfNeeded() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if didRegister {
            return didSucceed
        }
        didRegister = true

        guard let url = resolveFontURL() else {
            didSucceed = false
            return false
        }

        var errorRef: Unmanaged<CFError>?
        let registered = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &errorRef)
        if registered {
            didSucceed = true
            return true
        }

        // If already registered by another bundle/module in the same process, treat as success.
        if let err = errorRef?.takeRetainedValue() {
            let code = CFErrorGetCode(err)
            // kCTFontManagerErrorAlreadyRegistered == 105
            if code == 105 {
                didSucceed = true
                return true
            }
        }

        // Fallback verification via CoreText lookup
        let probe = CTFontCreateWithName(postScriptName as CFString, 16, nil)
        let resolvedName = CTFontCopyPostScriptName(probe) as String
        didSucceed = (resolvedName == postScriptName)
        return didSucceed
    }

    public static func resolveFontURL() -> URL? {
        if let url = Bundle.module.url(forResource: "Loreen-Regular", withExtension: "ttf", subdirectory: "Fonts") {
            return url
        }
        if let url = Bundle.module.url(forResource: "Loreen-Regular", withExtension: "ttf") {
            return url
        }
        if let resourceRoot = Bundle.module.resourceURL {
            let candidate = resourceRoot.appendingPathComponent("Fonts/Loreen-Regular.ttf")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}

#if canImport(SwiftUI)
public extension Font {
    /// Returns the Loreen Script custom font at the requested size, registering it lazily if needed.
    static func loreen(size: CGFloat) -> Font {
        LoreenFontRegistry.registerIfNeeded()
        return .custom(LoreenFontRegistry.postScriptName, size: size)
    }
}
#endif
