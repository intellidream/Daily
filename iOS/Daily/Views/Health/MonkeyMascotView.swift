import SwiftUI
import DailyCore

/// Size variant for the stylized monkey mascot.
public enum MonkeySize {
    case badge // 24x24 for pills and widgets
    case mini  // 44x44 for widget headers and list items
    case card  // 80x80 for dashboard cards
    case hero  // 130x130 for Stress Studio hero
    
    var dimension: CGFloat {
        switch self {
        case .badge: return 24
        case .mini: return 44
        case .card: return 80
        case .hero: return 130
        }
    }
}

/// A charming, procedural vector monkey mascot with expressive moods and animated autonomic breath glow.
public struct MonkeyMascotView: View {
    public let mood: MonkeyMood
    public let size: MonkeySize
    public let animated: Bool
    
    @State private var breatheScale: CGFloat = 1.0
    @State private var earWiggle: Double = 0.0
    
    public init(mood: MonkeyMood = .curious, size: MonkeySize = .card, animated: Bool = true) {
        self.mood = mood
        self.size = size
        self.animated = animated
    }
    
    private var primaryAuraColor: Color {
        switch mood {
        case .zen: return Color(hex: "#00E5FF")        // Mint / neon cyan
        case .curious: return Color(hex: "#00FFB2")    // Teal / spring green
        case .busy: return Color(hex: "#FFA726")       // Warm amber
        case .overheated: return Color(hex: "#FF5252") // Coral red
        }
    }
    
    public var body: some View {
        let dim = size.dimension
        
        ZStack {
            // Background Autonomic Aura Halo
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            primaryAuraColor.opacity(0.35),
                            primaryAuraColor.opacity(0.08),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: dim * 0.2,
                        endRadius: dim * 0.65
                    )
                )
                .scaleEffect(breatheScale)
            
            // Stylized Monkey Head & Facial Features
            monkeyFace(dimension: dim)
        }
        .frame(width: dim, height: dim)
        .onAppear {
            if animated {
                withAnimation(
                    .easeInOut(duration: mood == .overheated ? 1.4 : 3.0)
                    .repeatForever(autoreverses: true)
                ) {
                    breatheScale = 1.12
                    earWiggle = mood == .busy ? 4.0 : 1.5
                }
            }
        }
    }
    
    @ViewBuilder
    private func monkeyFace(dimension: CGFloat) -> some View {
        let scale = dimension / 100.0
        
        ZStack {
            // Ears (Outer)
            HStack(spacing: 64 * scale) {
                // Left Ear
                earView(scale: scale, isLeft: true)
                // Right Ear
                earView(scale: scale, isLeft: false)
            }
            .offset(y: -6 * scale)
            
            // Main Head (Warm Caramel Coat)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "#8D5B4C"),
                            Color(hex: "#6D3B2C")
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 72 * scale, height: 68 * scale)
                .overlay(
                    Circle()
                        .stroke(primaryAuraColor.opacity(0.4), lineWidth: 1.5 * scale)
                )
            
            // Face Mask (Peaches & Cream Inset)
            HStack(spacing: -8 * scale) {
                Circle()
                    .fill(Color(hex: "#F7D6BF"))
                    .frame(width: 36 * scale, height: 36 * scale)
                Circle()
                    .fill(Color(hex: "#F7D6BF"))
                    .frame(width: 36 * scale, height: 36 * scale)
            }
            .offset(y: -4 * scale)
            
            // Lower Muzzle
            Capsule()
                .fill(Color(hex: "#F7D6BF"))
                .frame(width: 50 * scale, height: 32 * scale)
                .offset(y: 10 * scale)
            
            // Eyes & Expression
            eyesView(scale: scale)
                .offset(y: -2 * scale)
            
            // Nose
            Capsule()
                .fill(Color(hex: "#4E271E"))
                .frame(width: 8 * scale, height: 5 * scale)
                .offset(y: 9 * scale)
            
            // Mouth Expression
            mouthView(scale: scale)
                .offset(y: 18 * scale)
            
            // Mood Specific Accessories
            moodAccessory(scale: scale)
        }
    }
    
    // Ears with Inner Pink Cavity
    @ViewBuilder
    private func earView(scale: CGFloat, isLeft: Bool) -> some View {
        ZStack {
            Circle()
                .fill(Color(hex: "#7A4333"))
                .frame(width: 24 * scale, height: 24 * scale)
            Circle()
                .fill(Color(hex: "#F7B8A1"))
                .frame(width: 14 * scale, height: 14 * scale)
        }
        .rotationEffect(.degrees(isLeft ? -earWiggle : earWiggle))
    }
    
    // Expressive Eyes Based on Stress State
    @ViewBuilder
    private func eyesView(scale: CGFloat) -> some View {
        HStack(spacing: 16 * scale) {
            switch mood {
            case .zen:
                // Serene curved closed eyes (smiling arcs)
                Text("◜  ◝")
                    .font(.system(size: 14 * scale, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "#3D1E15"))
                
            case .curious:
                // Big round shiny eyes with light reflection
                eyePupil(scale: scale)
                eyePupil(scale: scale)
                
            case .busy:
                // Thoughtful focused eyes (one slightly squinted)
                eyePupil(scale: scale)
                Circle()
                    .fill(Color(hex: "#2D120B"))
                    .frame(width: 6.5 * scale, height: 5 * scale)
                
            case .overheated:
                // Squinting stress eyes: > <
                HStack(spacing: 14 * scale) {
                    Text("✕")
                        .font(.system(size: 10 * scale, weight: .heavy))
                        .foregroundColor(Color(hex: "#FF5252"))
                    Text("✕")
                        .font(.system(size: 10 * scale, weight: .heavy))
                        .foregroundColor(Color(hex: "#FF5252"))
                }
            }
        }
    }
    
    @ViewBuilder
    private func eyePupil(scale: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(Color(hex: "#241009"))
                .frame(width: 8 * scale, height: 8 * scale)
            Circle()
                .fill(Color.white)
                .frame(width: 2.5 * scale, height: 2.5 * scale)
                .offset(x: -1.5 * scale, y: 1.5 * scale)
        }
    }
    
    // Expressive Mouth
    @ViewBuilder
    private func mouthView(scale: CGFloat) -> some View {
        switch mood {
        case .zen:
            // Gentle serene smile
            Text("‿")
                .font(.system(size: 14 * scale, weight: .semibold, design: .rounded))
                .foregroundColor(Color(hex: "#4E271E"))
                .offset(y: -4 * scale)
            
        case .curious:
            // Cute open half-smile
            Capsule()
                .fill(Color(hex: "#D85A5A"))
                .frame(width: 8 * scale, height: 4 * scale)
            
        case .busy:
            // Straight pensive line
            Capsule()
                .fill(Color(hex: "#4E271E"))
                .frame(width: 10 * scale, height: 2 * scale)
            
        case .overheated:
            // Wavy or open sigh mouth
            Capsule()
                .fill(Color(hex: "#C62828"))
                .frame(width: 10 * scale, height: 6 * scale)
        }
    }
    
    // Mood Specific Accessories (Zen Lotus / Overheated Ice Pack)
    @ViewBuilder
    private func moodAccessory(scale: CGFloat) -> some View {
        switch mood {
        case .zen:
            // Floating green lotus / leaf
            Image(systemName: "leaf.fill")
                .font(.system(size: 10 * scale))
                .foregroundColor(Color(hex: "#00E5FF"))
                .offset(x: 18 * scale, y: -26 * scale)
                .shadow(color: Color(hex: "#00E5FF").opacity(0.6), radius: 4 * scale)
            
        case .curious:
            EmptyView()
            
        case .busy:
            // Thinking bubble
            Circle()
                .fill(Color.white.opacity(0.85))
                .frame(width: 5 * scale, height: 5 * scale)
                .offset(x: 26 * scale, y: -22 * scale)
            
        case .overheated:
            // Cute cool ice-pack on forehead
            ZStack {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#64B5F6"), Color(hex: "#1E88E5")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 28 * scale, height: 12 * scale)
                Text("❄︎")
                    .font(.system(size: 8 * scale, weight: .bold))
                    .foregroundColor(.white)
            }
            .offset(y: -28 * scale)
            .shadow(color: Color.black.opacity(0.3), radius: 3 * scale)
        }
    }
}
