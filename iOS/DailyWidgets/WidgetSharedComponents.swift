import SwiftUI
import WidgetKit
import DailyCore

// MARK: - Color Hex Extension
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

// MARK: - Standard Widget Design System Colors
public struct WidgetColors {
    public static let accentCyan = Color(hex: "#00E5FF")
    public static let accentBlue = Color(hex: "#3B82F6")
    public static let accentGreen = Color(hex: "#00E676")
    public static let accentMint = Color(hex: "#00FFB2")
    public static let accentPink = Color(hex: "#FF2D55")
    public static let accentRed = Color(hex: "#EF4444")
    public static let accentAmber = Color(hex: "#FFB800")
    public static let accentOrange = Color(hex: "#F97316")
    public static let accentPurple = Color(hex: "#A855F7")
    public static let coffeeYellow = Color(hex: "#F59E0B")
    public static let teaLime = Color(hex: "#84CC16")
    public static let fgMuted = Color.white.opacity(0.6)
    
    public static let bgGradient = LinearGradient(
        colors: [Color(hex: "#040810"), Color(hex: "#0A1424")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Anatomical Vector Lungs Shape & Bronchi
public struct WidgetVectorLungsShape: Shape {
    public init() {}
    
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        // Trachea / Airway
        path.move(to: CGPoint(x: w * 0.48, y: h * 0.05))
        path.addLine(to: CGPoint(x: w * 0.52, y: h * 0.05))
        path.addLine(to: CGPoint(x: w * 0.52, y: h * 0.28))
        path.addLine(to: CGPoint(x: w * 0.48, y: h * 0.28))
        path.closeSubpath()
        
        // Left Lung lobe
        path.move(to: CGPoint(x: w * 0.46, y: h * 0.29))
        path.addCurve(
            to: CGPoint(x: w * 0.12, y: h * 0.52),
            control1: CGPoint(x: w * 0.30, y: h * 0.26),
            control2: CGPoint(x: w * 0.12, y: h * 0.38)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.38, y: h * 0.90),
            control1: CGPoint(x: w * 0.12, y: h * 0.72),
            control2: CGPoint(x: w * 0.22, y: h * 0.88)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.46, y: h * 0.38),
            control1: CGPoint(x: w * 0.42, y: h * 0.80),
            control2: CGPoint(x: w * 0.44, y: h * 0.52)
        )
        path.closeSubpath()
        
        // Right Lung lobe
        path.move(to: CGPoint(x: w * 0.54, y: h * 0.29))
        path.addCurve(
            to: CGPoint(x: w * 0.88, y: h * 0.52),
            control1: CGPoint(x: w * 0.70, y: h * 0.26),
            control2: CGPoint(x: w * 0.88, y: h * 0.38)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.62, y: h * 0.90),
            control1: CGPoint(x: w * 0.88, y: h * 0.72),
            control2: CGPoint(x: w * 0.78, y: h * 0.88)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.54, y: h * 0.38),
            control1: CGPoint(x: w * 0.58, y: h * 0.80),
            control2: CGPoint(x: w * 0.56, y: h * 0.52)
        )
        path.closeSubpath()
        
        return path
    }
}

public struct WidgetVectorLungsBronchiShape: Shape {
    public init() {}
    
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        path.move(to: CGPoint(x: w * 0.50, y: h * 0.10))
        path.addLine(to: CGPoint(x: w * 0.50, y: h * 0.28))
        
        // Left main bronchus & branches
        path.move(to: CGPoint(x: w * 0.50, y: h * 0.28))
        path.addQuadCurve(to: CGPoint(x: w * 0.33, y: h * 0.46), control: CGPoint(x: w * 0.42, y: h * 0.34))
        path.addQuadCurve(to: CGPoint(x: w * 0.27, y: h * 0.66), control: CGPoint(x: w * 0.30, y: h * 0.56))
        
        path.move(to: CGPoint(x: w * 0.33, y: h * 0.46))
        path.addQuadCurve(to: CGPoint(x: w * 0.38, y: h * 0.62), control: CGPoint(x: w * 0.37, y: h * 0.53))
        
        // Right main bronchus & branches
        path.move(to: CGPoint(x: w * 0.50, y: h * 0.28))
        path.addQuadCurve(to: CGPoint(x: w * 0.67, y: h * 0.46), control: CGPoint(x: w * 0.58, y: h * 0.34))
        path.addQuadCurve(to: CGPoint(x: w * 0.73, y: h * 0.66), control: CGPoint(x: w * 0.70, y: h * 0.56))
        
        path.move(to: CGPoint(x: w * 0.67, y: h * 0.46))
        path.addQuadCurve(to: CGPoint(x: w * 0.62, y: h * 0.62), control: CGPoint(x: w * 0.63, y: h * 0.53))
        
        return path
    }
}

// MARK: - Dynamic Lung Health & Ring Colors
public func widgetLungHealthColor(countToday: Int, baseline: Int) -> Color {
    let base = max(baseline, 1)
    let ratio = Double(countToday) / Double(base)
    if countToday == 0 {
        return Color(red: 255.0 / 255.0, green: 107.0 / 255.0, blue: 139.0 / 255.0) // Healthy pink
    } else if ratio <= 0.35 {
        let t = ratio / 0.35
        return Color(
            red: (255.0 - t * (255.0 - 215.0)) / 255.0,
            green: (107.0 + t * (125.0 - 107.0)) / 255.0,
            blue: (139.0 + t * (145.0 - 139.0)) / 255.0
        )
    } else if ratio <= 0.75 {
        let t = (ratio - 0.35) / 0.40
        return Color(
            red: (215.0 - t * (215.0 - 120.0)) / 255.0,
            green: (125.0 - t * (125.0 - 113.0)) / 255.0,
            blue: (145.0 - t * (145.0 - 108.0)) / 255.0
        )
    } else if ratio <= 1.0 {
        let t = (ratio - 0.75) / 0.25
        return Color(
            red: (120.0 - t * (120.0 - 75.0)) / 255.0,
            green: (113.0 - t * (113.0 - 85.0)) / 255.0,
            blue: (108.0 - t * (108.0 - 99.0)) / 255.0
        )
    } else {
        let t = min((ratio - 1.0) / 0.5, 1.0)
        return Color(
            red: (75.0 - t * (75.0 - 39.0)) / 255.0,
            green: (85.0 - t * (85.0 - 39.0)) / 255.0,
            blue: (99.0 - t * (99.0 - 42.0)) / 255.0
        )
    }
}

public func widgetSmokeRingColor(countToday: Int, baseline: Int) -> Color {
    let base = max(baseline, 1)
    let ratio = Double(countToday) / Double(base)
    if countToday == 0 {
        return WidgetColors.accentGreen
    } else if ratio < 0.4 {
        return WidgetColors.accentGreen
    } else if ratio < 0.75 {
        return WidgetColors.accentAmber
    } else if ratio <= 1.0 {
        return WidgetColors.accentOrange
    } else {
        return WidgetColors.accentRed
    }
}

// MARK: - Compact Formatting Helpers
public func widgetFormatCompactTimeAgo(_ date: Date?) -> String {
    guard let date = date else { return "0s" }
    let diff = max(0, Int(Date().timeIntervalSince(date)))
    let hours = diff / 3600
    let minutes = (diff % 3600) / 60
    let seconds = diff % 60
    if hours > 0 {
        return "\(hours)h"
    } else if minutes > 0 {
        return "\(minutes)m"
    } else {
        return "\(seconds)s"
    }
}

public func widgetFormatCompactNumber(_ amount: Double) -> String {
    if amount >= 1_000_000 {
        return String(format: "%.1fM", amount / 1_000_000)
    } else if amount >= 1_000 {
        let thousands = amount / 1_000
        if thousands.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0fK", thousands)
        } else {
            return String(format: "%.1fK", thousands)
        }
    } else {
        return String(format: "%.0f", amount)
    }
}

public func widgetFormatCompactIntegerEUR(_ amount: Double) -> String {
    if amount >= 1_000_000 {
        return "\(Int(round(amount / 1_000_000)))M"
    } else if amount >= 1_000 {
        return "\(Int(round(amount / 1_000)))k"
    } else {
        return "\(Int(round(amount)))"
    }
}

// MARK: - Procedural Vector Monkey Mascot for Widgets
public struct WidgetMonkeyMascotView: View {
    public let mood: MonkeyMood
    public var size: CGFloat = 24
    
    public init(mood: MonkeyMood, size: CGFloat = 24) {
        self.mood = mood
        self.size = size
    }
    
    private var moodAccentColor: Color {
        switch mood {
        case .zen: return Color(hex: "#00FFB2")
        case .curious: return Color(hex: "#00E5FF")
        case .busy: return Color(hex: "#FFB800")
        case .overheated: return Color(hex: "#FF3B30")
        }
    }
    
    public var body: some View {
        ZStack {
            // Subtle ambient halo
            Circle()
                .fill(moodAccentColor.opacity(0.18))
                .frame(width: size, height: size)
            
            // Left & Right Ears
            HStack(spacing: size * 0.50) {
                earView
                earView
            }
            
            // Main Monkey Head (Warm Caramel)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.65, green: 0.42, blue: 0.24),
                            Color(red: 0.45, green: 0.27, blue: 0.14)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.66, height: size * 0.66)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.22), lineWidth: max(0.75, size * 0.03))
                )
            
            // Inner Face Mask (Peaches & Cream)
            ZStack {
                HStack(spacing: size * 0.04) {
                    Circle()
                        .fill(Color(red: 0.96, green: 0.84, blue: 0.72))
                        .frame(width: size * 0.28, height: size * 0.28)
                    Circle()
                        .fill(Color(red: 0.96, green: 0.84, blue: 0.72))
                        .frame(width: size * 0.28, height: size * 0.28)
                }
                .offset(y: -size * 0.05)
                
                Capsule()
                    .fill(Color(red: 0.96, green: 0.84, blue: 0.72))
                    .frame(width: size * 0.50, height: size * 0.30)
                    .offset(y: size * 0.11)
            }
            
            // Eyes
            HStack(spacing: size * 0.15) {
                eyeView(isLeft: true)
                eyeView(isLeft: false)
            }
            .offset(y: -size * 0.05)
            
            // Cute Oval Nose
            Capsule()
                .fill(Color(red: 0.30, green: 0.16, blue: 0.08))
                .frame(width: size * 0.09, height: size * 0.055)
                .offset(y: size * 0.05)
            
            // Mouth
            mouthView
                .offset(y: size * 0.15)
            
            // Mood top accessory forZen / Overheated
            if mood == .zen {
                Image(systemName: "leaf.fill")
                    .font(.system(size: max(6, size * 0.24), weight: .bold))
                    .foregroundColor(Color(hex: "#00FFB2"))
                    .offset(x: size * 0.24, y: -size * 0.28)
            } else if mood == .overheated {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#00E5FF"), Color(hex: "#3B82F6")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: size * 0.34, height: size * 0.12)
                    .rotationEffect(.degrees(-8))
                    .offset(y: -size * 0.33)
            }
        }
        .frame(width: size, height: size)
    }
    
    private var earView: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.55, green: 0.34, blue: 0.18))
                .frame(width: size * 0.24, height: size * 0.24)
            Circle()
                .fill(Color(red: 0.92, green: 0.72, blue: 0.60))
                .frame(width: size * 0.14, height: size * 0.14)
        }
    }
    
    @ViewBuilder
    private func eyeView(isLeft: Bool) -> some View {
        let darkBrown = Color(red: 0.18, green: 0.10, blue: 0.05)
        switch mood {
        case .zen:
            Circle()
                .trim(from: 0.05, to: 0.45)
                .stroke(darkBrown, style: StrokeStyle(lineWidth: max(1.0, size * 0.045), lineCap: .round))
                .frame(width: size * 0.13, height: size * 0.13)
        case .curious:
            ZStack {
                Circle()
                    .fill(darkBrown)
                    .frame(width: size * 0.11, height: size * 0.11)
                Circle()
                    .fill(Color.white)
                    .frame(width: size * 0.04, height: size * 0.04)
                    .offset(x: -size * 0.02, y: -size * 0.02)
            }
        case .busy:
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: size * 0.13, height: size * 0.13)
                Circle()
                    .fill(darkBrown)
                    .frame(width: size * 0.08, height: size * 0.08)
            }
        case .overheated:
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: size * 0.14, height: size * 0.14)
                Circle()
                    .fill(Color(hex: "#FF3B30"))
                    .frame(width: size * 0.06, height: size * 0.06)
            }
        }
    }
    
    @ViewBuilder
    private var mouthView: some View {
        let darkBrown = Color(red: 0.22, green: 0.12, blue: 0.06)
        switch mood {
        case .zen, .curious:
            Circle()
                .trim(from: 0.12, to: 0.38)
                .stroke(darkBrown, style: StrokeStyle(lineWidth: max(1.0, size * 0.045), lineCap: .round))
                .frame(width: size * 0.18, height: size * 0.15)
                .offset(y: -size * 0.03)
        case .busy:
            Capsule()
                .fill(darkBrown)
                .frame(width: size * 0.12, height: max(1.2, size * 0.04))
        case .overheated:
            Circle()
                .stroke(darkBrown, lineWidth: max(1.0, size * 0.04))
                .frame(width: size * 0.09, height: size * 0.09)
        }
    }
}


