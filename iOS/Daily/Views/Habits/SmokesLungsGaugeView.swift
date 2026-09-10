import SwiftUI
import DailyCore

/// Vector Lungs minimal silhouette icon
struct VectorLungsShape: Shape {
    func path(in rect: CGRect) -> Path {
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

/// Hero gauge for Smokes (Tobacco & Nicotine Reduction Tracker).
public struct SmokesLungsGaugeView: View {
    public let countToday: Int
    public let baselineCount: Int
    public let lastSmokeDate: Date?
    
    @State private var pulseScale: CGFloat = 1.0
    
    public init(countToday: Int, baselineCount: Int, lastSmokeDate: Date?) {
        self.countToday = countToday
        self.baselineCount = max(baselineCount, 1)
        self.lastSmokeDate = lastSmokeDate
    }
    
    private var progressRatio: Double {
        return min(max(Double(countToday) / Double(baselineCount), 0.0), 1.5)
    }
    
    private var statusColor: Color {
        if countToday == 0 {
            return Color(hex: "#00FFB2") // Pure smoke-free green
        } else if progressRatio <= 0.6 {
            return Color(hex: "#00E5FF") // Healthy control cyan
        } else if progressRatio <= 1.0 {
            return Color(hex: "#FFB800") // Approaching baseline amber
        } else {
            return Color(hex: "#FF3B30") // Exceeded baseline red
        }
    }
    
    private var timeSinceLastSmokeFormatted: String {
        guard let last = lastSmokeDate else {
            return "Smoke-Free Today!"
        }
        let interval = Date().timeIntervalSince(last)
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m craving-free"
        } else {
            let hours = Int(interval / 3600)
            let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(minutes)m clean"
        }
    }
    
    public var body: some View {
        ZStack {
            // Ambient Radial Glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            statusColor.opacity(0.22),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 50,
                        endRadius: 130
                    )
                )
                .frame(width: 250, height: 250)
            
            // Glass container
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.04))
                    .background(.ultraThinMaterial, in: Circle())
                
                // Vector Lungs background silhouette
                VectorLungsShape()
                    .fill(
                        LinearGradient(
                            colors: [
                                statusColor.opacity(0.25),
                                statusColor.opacity(0.08)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 135, height: 135)
                    .scaleEffect(pulseScale)
                
                // Center text & craving status
                VStack(spacing: 4) {
                    Image(systemName: countToday == 0 ? "sparkles" : "flame.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(statusColor)
                        .shadow(color: statusColor.opacity(0.6), radius: 6)
                    
                    Text("\(countToday)")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: Color.black.opacity(0.4), radius: 4)
                    
                    Text("of \(baselineCount) baseline max")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.85))
                    
                    // Live craving timer badge
                    HStack(spacing: 5) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                        
                        Text(timeSinceLastSmokeFormatted)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.35))
                    .clipShape(Capsule())
                    .overlay {
                        Capsule().strokeBorder(statusColor.opacity(0.3), lineWidth: 1)
                    }
                    .padding(.top, 4)
                }
            }
            .frame(width: 210, height: 210)
            .overlay {
                // Background Track Arc
                Circle()
                    .trim(from: 0.15, to: 0.85)
                    .stroke(
                        Color.white.opacity(0.1),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(Angle(degrees: 90))
                    .frame(width: 218, height: 218)
                
                // Active Progress Arc
                Circle()
                    .trim(from: 0.15, to: 0.15 + (0.70 * min(progressRatio, 1.0)))
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color(hex: "#00FFB2"),
                                Color(hex: "#00E5FF"),
                                statusColor
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(Angle(degrees: 90))
                    .frame(width: 218, height: 218)
                    .shadow(color: statusColor.opacity(0.5), radius: 8)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                pulseScale = 1.04
            }
        }
    }
}
