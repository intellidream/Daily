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

/// Internal bronchial airway tree branches for realistic anatomical depth
struct VectorLungsBronchiShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        // Trachea center line
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

/// Hero gauge for Smokes (Tobacco & Nicotine Reduction Tracker).
public struct SmokesLungsGaugeView: View {
    public let countToday: Int
    public let baselineCount: Int
    public let lastSmokeDate: Date?
    public let smokeBreakdown: [HabitDrinkBreakdown]
    
    @State private var pulseScale: CGFloat = 1.0
    
    public init(
        countToday: Int,
        baselineCount: Int,
        lastSmokeDate: Date?,
        smokeBreakdown: [HabitDrinkBreakdown] = []
    ) {
        self.countToday = countToday
        self.baselineCount = max(baselineCount, 1)
        self.lastSmokeDate = lastSmokeDate
        self.smokeBreakdown = smokeBreakdown
    }
    
    private var progressRatio: Double {
        return min(max(Double(countToday) / Double(baselineCount), 0.0), 1.5)
    }
    
    /// Status color for numerical alerts, warning indicators, and status badges
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
    
    /// Lungs tissue color transitioning from radiant healthy pink (#FF6B8B) at 0 smokes,
    /// through dusky rose to a sickly ashen gray (#78716C) near baseline,
    /// deepening to an unpleasant diseased dark charcoal/tar gray (>100% baseline).
    private var lungHealthColor: Color {
        let r = progressRatio
        if r == 0 {
            // Radiant anatomical healthy lung pink (#FF6B8B)
            return Color(red: 255.0 / 255.0, green: 107.0 / 255.0, blue: 139.0 / 255.0)
        } else if r <= 0.35 {
            // Soft loss of vibrant pink into a muted dusty rose
            let t = r / 0.35
            return Color(
                red: (255.0 - t * (255.0 - 215.0)) / 255.0,
                green: (107.0 + t * (125.0 - 107.0)) / 255.0,
                blue: (139.0 + t * (145.0 - 139.0)) / 255.0
            )
        } else if r <= 0.75 {
            // Transition from muted rose (#D77D91) to sickly ashen gray (#78716C)
            let t = (r - 0.35) / 0.40
            return Color(
                red: (215.0 - t * (215.0 - 120.0)) / 255.0,
                green: (125.0 - t * (125.0 - 113.0)) / 255.0,
                blue: (145.0 - t * (145.0 - 108.0)) / 255.0
            )
        } else if r <= 1.0 {
            // Sickly gray (#78716C) to cold unwholesome dark slate (#4B5563)
            let t = (r - 0.75) / 0.25
            return Color(
                red: (120.0 - t * (120.0 - 75.0)) / 255.0,
                green: (113.0 - t * (113.0 - 85.0)) / 255.0,
                blue: (108.0 - t * (108.0 - 99.0)) / 255.0
            )
        } else {
            // Over baseline max: diseased dark soot charcoal (#27272A)
            let t = min((r - 1.0) / 0.5, 1.0)
            return Color(
                red: (75.0 - t * (75.0 - 39.0)) / 255.0,
                green: (85.0 - t * (85.0 - 39.0)) / 255.0,
                blue: (99.0 - t * (99.0 - 42.0)) / 255.0
            )
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
    
    /// Proportional segments for outer rim gauge
    private struct SmokeArcSegment: Identifiable {
        let id: String
        let startTrim: Double
        let endTrim: Double
        let color: Color
    }
    
    private var arcSegments: [SmokeArcSegment] {
        guard countToday > 0, !smokeBreakdown.isEmpty else { return [] }
        
        let totalActiveSpan = 0.70 * min(progressRatio, 1.0)
        let totalAmount = smokeBreakdown.reduce(0.0) { $0 + $1.amount }
        guard totalAmount > 0 else { return [] }
        
        var segments: [SmokeArcSegment] = []
        var currentOffset = 0.15
        
        for item in smokeBreakdown {
            let fraction = item.amount / totalAmount
            let span = fraction * totalActiveSpan
            let endOffset = currentOffset + span
            
            segments.append(
                SmokeArcSegment(
                    id: item.id,
                    startTrim: currentOffset,
                    endTrim: min(endOffset, 0.85),
                    color: Color(hex: item.hexColor)
                )
            )
            currentOffset = endOffset
        }
        
        return segments
    }
    
    public var body: some View {
        ZStack {
            // Ambient Radial Glow (soft pink when healthy, transitioning to dark ashen / status alert)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            lungHealthColor.opacity(0.32),
                            statusColor.opacity(0.12),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 45,
                        endRadius: 130
                    )
                )
                .frame(width: 250, height: 250)
            
            // Glass container
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.04))
                    .background(.ultraThinMaterial, in: Circle())
                
                // Vector Lungs with dynamic health color (pink -> diseased gray)
                ZStack {
                    VectorLungsShape()
                        .fill(
                            LinearGradient(
                                colors: [
                                    lungHealthColor.opacity(0.62),
                                    lungHealthColor.opacity(0.30)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    VectorLungsShape()
                        .stroke(
                            lungHealthColor.opacity(0.80),
                            lineWidth: 1.5
                        )
                    
                    VectorLungsBronchiShape()
                        .stroke(
                            lungHealthColor.opacity(0.70),
                            style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
                        )
                }
                .frame(width: 135, height: 135)
                .scaleEffect(pulseScale)
                .shadow(color: lungHealthColor.opacity(0.4), radius: 8)
                
                // Center text & craving status
                VStack(spacing: 3) {
                    Image(systemName: countToday == 0 ? "sparkles" : "flame.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(statusColor)
                        .shadow(color: statusColor.opacity(0.6), radius: 6)
                    
                    Text("\(countToday)")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: Color.black.opacity(0.4), radius: 4)
                    
                    Text("of \(baselineCount) baseline max")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.85))
                    
                    // Live craving timer badge
                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 5, height: 5)
                        
                        Text(timeSinceLastSmokeFormatted)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.35))
                    .clipShape(Capsule())
                    .overlay {
                        Capsule().strokeBorder(statusColor.opacity(0.3), lineWidth: 1)
                    }
                    .padding(.top, 2)
                    
                    // Smoke Type Breakdown Ticker (displays totals per type: Cigarettes, Heated, Rolled, etc.)
                    if !smokeBreakdown.isEmpty {
                        HabitCircleBreakdownTicker(items: smokeBreakdown, habitType: .smokes)
                            .padding(.top, 3)
                    }
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
                
                // Active Progress Arc (Segmented by smoke type if multiple, or unified gradient)
                if arcSegments.count > 1 {
                    ForEach(arcSegments) { segment in
                        Circle()
                            .trim(from: segment.startTrim, to: segment.endTrim)
                            .stroke(
                                segment.color,
                                style: StrokeStyle(lineWidth: 6, lineCap: .round)
                            )
                            .rotationEffect(Angle(degrees: 90))
                            .frame(width: 218, height: 218)
                            .shadow(color: segment.color.opacity(0.6), radius: 6)
                    }
                } else {
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
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                pulseScale = 1.04
            }
        }
    }
}
