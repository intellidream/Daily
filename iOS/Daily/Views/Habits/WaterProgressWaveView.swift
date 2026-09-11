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

/// Represents a single stratified fluid layer inside the Bubbles circular vessel
struct LiquidStratum: Identifiable {
    let id: String
    let name: String
    let amountMl: Double
    let fraction: Double
    let cumProgress: Double
    let startProgress: Double
    let primaryColor: Color
    let secondaryColor: Color
    let iconName: String
}

/// Circular Liquid Glass wave hero gauge for Bubbles (Hydration) with multi-liquid stratification.
public struct WaterProgressWaveView: View {
    public let currentMl: Double
    public let goalMl: Double
    public let progressPercent: Double
    public let drinkBreakdown: [HabitDrinkBreakdown]
    
    @State private var waveOffset1 = Angle(degrees: 0)
    @State private var waveOffset2 = Angle(degrees: 90)
    
    public init(
        currentMl: Double,
        goalMl: Double,
        progressPercent: Double,
        drinkBreakdown: [HabitDrinkBreakdown] = []
    ) {
        self.currentMl = currentMl
        self.goalMl = goalMl
        self.progressPercent = progressPercent
        self.drinkBreakdown = drinkBreakdown
    }
    
    private var normalizedProgress: Double {
        guard goalMl > 0 else { return 0 }
        return min(max(currentMl / goalMl, 0.0), 1.0)
    }
    
    private var percentageDisplay: Int {
        guard goalMl > 0 else { return 0 }
        return Int((currentMl / goalMl) * 100.0)
    }
    
    /// Calculate stratified fluid layers (Water at bottom, Tea in middle, Coffee at top, etc.)
    private var strata: [LiquidStratum] {
        guard currentMl > 0, !drinkBreakdown.isEmpty else {
            return [
                LiquidStratum(
                    id: "default_water",
                    name: "Water",
                    amountMl: currentMl,
                    fraction: 1.0,
                    cumProgress: normalizedProgress,
                    startProgress: 0.0,
                    primaryColor: ThemeColors.accentCyan,
                    secondaryColor: ThemeColors.accentBlue,
                    iconName: "drop.fill"
                )
            ]
        }
        
        // Aggregate breakdown items into normalized beverage categories
        var catMap: [String: (amount: Double, primaryColor: Color, secondaryColor: Color, iconName: String, sortOrder: Int)] = [:]
        
        for item in drinkBreakdown {
            let lower = item.drink.lowercased()
            if lower.contains("coffee") || lower.contains("espresso") || lower.contains("cappuccino") || lower.contains("latte") {
                let existing = catMap["Coffee"]?.amount ?? 0
                catMap["Coffee"] = (
                    existing + item.amount,
                    Color(hex: "#F59E0B"),
                    Color(hex: "#92400E"),
                    "cup.and.saucer.fill",
                    2 // Coffee at top
                )
            } else if lower.contains("tea") || lower.contains("matcha") || lower.contains("infusion") {
                let existing = catMap["Tea"]?.amount ?? 0
                catMap["Tea"] = (
                    existing + item.amount,
                    Color(hex: "#84CC16"),
                    Color(hex: "#3F6212"),
                    "mug.fill",
                    1 // Tea in middle
                )
            } else if lower.contains("water") || lower.contains("glass") || lower.contains("bottle") {
                let existing = catMap["Water"]?.amount ?? 0
                catMap["Water"] = (
                    existing + item.amount,
                    ThemeColors.accentCyan,
                    ThemeColors.accentBlue,
                    "drop.fill",
                    0 // Water at bottom
                )
            } else {
                let existing = catMap[item.drink]?.amount ?? 0
                catMap[item.drink] = (
                    existing + item.amount,
                    Color(hex: item.hexColor),
                    Color(hex: item.hexColor).opacity(0.6),
                    item.iconName,
                    1
                )
            }
        }
        
        let sortedEntries = catMap.map { key, val in
            (name: key, amount: val.amount, primary: val.primaryColor, secondary: val.secondaryColor, icon: val.iconName, order: val.sortOrder)
        }.sorted { $0.order < $1.order }
        
        var result: [LiquidStratum] = []
        var runningCumProgress = 0.0
        
        for entry in sortedEntries {
            let fraction = currentMl > 0 ? (entry.amount / currentMl) : 0
            let stratumHeight = fraction * normalizedProgress
            let startProgress = runningCumProgress
            runningCumProgress += stratumHeight
            
            result.append(
                LiquidStratum(
                    id: entry.name,
                    name: entry.name,
                    amountMl: entry.amount,
                    fraction: fraction,
                    cumProgress: min(runningCumProgress, 1.0),
                    startProgress: startProgress,
                    primaryColor: entry.primary,
                    secondaryColor: entry.secondary,
                    iconName: entry.icon
                )
            )
        }
        
        return result
    }
    
    public var body: some View {
        ZStack {
            // Background glow ambient (shifts according to dominant beverage)
            let dominantColor = strata.first?.primaryColor ?? ThemeColors.accentCyan
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            dominantColor.opacity(0.25),
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
                
                // Multi-Liquid Wave Strata (rendered in reverse order: top layer first, bottom layer on top)
                ForEach(strata.indices.reversed(), id: \.self) { idx in
                    let stratum = strata[idx]
                    let phase = Angle(degrees: Double(idx * 40))
                    
                    // Back wave (deeper tone, softer opacity, out of phase)
                    WaveShape(offset: waveOffset2 + phase, percent: stratum.cumProgress, amplitude: 8)
                        .fill(
                            LinearGradient(
                                colors: [
                                    stratum.secondaryColor.opacity(0.48),
                                    stratum.primaryColor.opacity(0.35)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .clipShape(Circle())
                    
                    // Front wave (vibrant primary tone with high opacity)
                    WaveShape(offset: waveOffset1 + phase, percent: stratum.cumProgress, amplitude: 6.5)
                        .fill(
                            LinearGradient(
                                colors: [
                                    stratum.primaryColor.opacity(0.85),
                                    stratum.secondaryColor.opacity(0.92)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .clipShape(Circle())
                }
                
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
                
                // Central Readout & Breakdown Ticker
                VStack(spacing: 3) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(normalizedProgress >= 1.0 ? Color(hex: "#00FFB2") : ThemeColors.accentCyan)
                        .shadow(color: ThemeColors.accentCyan.opacity(0.6), radius: 8)
                    
                    Text("\(Int(currentMl))")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: Color.black.opacity(0.4), radius: 5, x: 0, y: 2)
                    
                    Text("of \(Int(goalMl)) ml (\(percentageDisplay)%)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.85))
                        .shadow(color: Color.black.opacity(0.5), radius: 4)
                    
                    if currentMl >= goalMl && goalMl > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text("Goal Achieved")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(Color(hex: "#00FFB2"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2.5)
                        .background(Color.black.opacity(0.35))
                        .clipShape(Capsule())
                        .padding(.top, 2)
                    } else {
                        let remaining = max(0, Int(goalMl - currentMl))
                        Text("\(remaining) ml left")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(Color.white.opacity(0.7))
                            .padding(.top, 1)
                    }
                    
                    // Liquid Breakdown Ticker (displays totals per beverage: Water, Coffee, Tea, etc.)
                    if !drinkBreakdown.isEmpty {
                        HabitCircleBreakdownTicker(items: drinkBreakdown, habitType: .water)
                            .padding(.top, 4)
                    }
                }
            }
            .frame(width: 210, height: 210)
            .overlay {
                // Segmented Multi-Liquid Outer Ring Border
                if strata.count > 1 {
                    ForEach(strata) { stratum in
                        Circle()
                            .trim(from: stratum.startProgress, to: stratum.cumProgress)
                            .stroke(
                                stratum.primaryColor,
                                style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                            )
                            .frame(width: 216, height: 216)
                            .rotationEffect(Angle(degrees: -90))
                            .shadow(color: stratum.primaryColor.opacity(0.55), radius: 6)
                    }
                } else {
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
