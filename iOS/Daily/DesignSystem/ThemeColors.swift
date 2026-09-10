import SwiftUI

public extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

public struct ThemeColors {
    // WinUI Background stops
    public static let bgStop0 = Color(hex: "030609")
    public static let bgStop1 = Color(hex: "050F1A")
    public static let bgStop2 = Color(hex: "0D1A35")
    public static let bgStop3 = Color(hex: "132B4A")
    
    // Light theme background
    public static let lightBgColor = Color(hex: "D4C9B0")
    
    // Accent Glow & Highlights
    public static let accentCyan = Color(hex: "00E5FF")
    public static let accentBlue = Color(hex: "4A9EFF")
    public static let glowPurple = Color(hex: "8A2BE2")
    
    // Status colors
    public static let error = Color(hex: "FF6B6B")
    public static let warning = Color(hex: "FFD166")
    public static let success = Color(hex: "00E676")
    
    // Foreground
    public static let fgPrimaryDark = Color.white
    public static let fgMutedDark = Color.white.opacity(0.7)
    public static let fgPrimaryLight = Color(hex: "1A1A1A")
    public static let fgMutedLight = Color(hex: "1A1A1A").opacity(0.65)
    
    // Glass styling
    public static let glassDarkBorder = LinearGradient(
        colors: [
            Color.white.opacity(0.35),
            Color.white.opacity(0.10),
            Color.clear,
            Color.white.opacity(0.18)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    public static let glassLightBorder = LinearGradient(
        colors: [
            Color.black.opacity(0.18),
            Color.black.opacity(0.06),
            Color.clear,
            Color.black.opacity(0.12)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
