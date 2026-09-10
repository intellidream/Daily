import SwiftUI
import DailyCore

/// Animated sine wave shape for realistic fluid container simulation.
struct WaveShape: Shape {
    var offset: Angle
    var percent: Double
    var amplitude: CGFloat = 8
    
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(offset.degrees, percent) }
        set {
            offset = Angle(degrees: newValue.first)
            percent = newValue.second
        }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let clampedPercent = min(max(percent, 0.0), 1.0)
        let baseHeight = rect.height * (1.0 - clampedPercent)
        
        path.move(to: CGPoint(x: 0, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: baseHeight))
        
        let width = rect.width
        let wavelength = width
        
        for x in stride(from: 0, through: width, by: 2) {
            let relativeX = x / wavelength
            let sine = sin(relativeX * 2 * .pi + offset.radians)
            let y = baseHeight + CGFloat(sine) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
        }
        
        path.addLine(to: CGPoint(x: width, y: rect.height))
        path.closeSubpath()
        return path
    }
}

/// Circular Liquid Glass wave hero gauge for Bubbles (Hydration).
public struct WaterProgressWaveView: View {
    public let currentMl: Double
    public let goalMl: Double
    public let progressPercent: Double
    
    @State private var waveOffset1 = Angle(degrees: 0)
    @State private var waveOffset2 = Angle(degrees: 90)
    
    public init(currentMl: Double, goalMl: Double, progressPercent: Double) {
        self.currentMl = currentMl
        self.goalMl = goalMl
        self.progressPercent = progressPercent
    }
    
    private var normalizedProgress: Double {
        guard goalMl > 0 else { return 0 }
        return min(max(currentMl / goalMl, 0.0), 1.0)
    }
    
    private var percentageDisplay: Int {
        guard goalMl > 0 else { return 0 }
        return Int((currentMl / goalMl) * 100.0)
    }
    
    public var body: some View {
        ZStack {
            // Background glow ambient
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            ThemeColors.accentCyan.opacity(0.25),
                            ThemeColors.accentBlue.opacity(0.1),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 40,
                        endRadius: 130
                    )
                )
                .frame(width: 250, height: 250)
            
            // Circular Glass Container
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.04))
                    .background(.ultraThinMaterial, in: Circle())
                
                // Back wave (deeper blue, softer opacity, out of phase)
                WaveShape(offset: waveOffset2, percent: normalizedProgress, amplitude: 9)
                    .fill(
                        LinearGradient(
                            colors: [
                                ThemeColors.accentBlue.opacity(0.45),
                                ThemeColors.accentCyan.opacity(0.35)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .clipShape(Circle())
                
                // Front wave (vibrant cyan/blue with higher opacity)
                WaveShape(offset: waveOffset1, percent: normalizedProgress, amplitude: 7)
                    .fill(
                        LinearGradient(
                            colors: [
                                ThemeColors.accentCyan.opacity(0.75),
                                ThemeColors.accentBlue.opacity(0.85)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .clipShape(Circle())
                
                // Surface shimmer highlight line
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.6),
                                Color.white.opacity(0.1),
                                ThemeColors.accentCyan.opacity(0.4)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                
                // Central Readout
                VStack(spacing: 4) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(normalizedProgress >= 1.0 ? Color(hex: "#00FFB2") : ThemeColors.accentCyan)
                        .shadow(color: ThemeColors.accentCyan.opacity(0.6), radius: 8)
                    
                    Text("\(Int(currentMl))")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: Color.black.opacity(0.4), radius: 6, x: 0, y: 3)
                    
                    Text("of \(Int(goalMl)) ml (\(percentageDisplay)%)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.85))
                        .shadow(color: Color.black.opacity(0.5), radius: 4)
                    
                    if currentMl >= goalMl && goalMl > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("Goal Achieved")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(Color(hex: "#00FFB2"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.35))
                        .clipShape(Capsule())
                        .padding(.top, 4)
                    } else {
                        let remaining = max(0, Int(goalMl - currentMl))
                        Text("\(remaining) ml left")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(Color.white.opacity(0.7))
                            .padding(.top, 2)
                    }
                }
            }
            .frame(width: 210, height: 210)
            .overlay {
                // Subtle rotating outer ring border
                Circle()
                    .trim(from: 0, to: normalizedProgress)
                    .stroke(
                        AngularGradient(
                            colors: [
                                ThemeColors.accentCyan,
                                ThemeColors.accentBlue,
                                Color(hex: "#00FFB2"),
                                ThemeColors.accentCyan
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                    )
                    .frame(width: 216, height: 216)
                    .rotationEffect(Angle(degrees: -90))
                    .shadow(color: ThemeColors.accentCyan.opacity(0.5), radius: 6)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 3.5).repeatForever(autoreverses: false)) {
                waveOffset1 = Angle(degrees: 360)
            }
            withAnimation(.linear(duration: 4.8).repeatForever(autoreverses: false)) {
                waveOffset2 = Angle(degrees: -270)
            }
        }
    }
}
