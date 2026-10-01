import SwiftUI
import DailyCore

/// Modular Stress & Mind Balance Card on the main Dashboard.
/// Adaptively renders across Small (1x1), Wide (2x1), Tall (1x2), and Large (2x2) modular sizes.
public struct StressDashboardCard: View, Equatable {
    @ObservedObject private var healthService = HealthDataService.shared
    
    public let size: DashboardWidgetSize
    private let onTap: () -> Void
    
    public init(size: DashboardWidgetSize = .wide, onTap: @escaping () -> Void = {}) {
        self.size = size
        self.onTap = onTap
    }
    
    public static func == (lhs: StressDashboardCard, rhs: StressDashboardCard) -> Bool {
        lhs.size == rhs.size
    }
    
    public var body: some View {
        Button(action: onTap) {
            GlassCard(cornerRadius: 20, padding: size == .small ? 14 : 18) {
                switch size {
                case .small:
                    smallContent
                case .wide:
                    wideContent
                case .tall:
                    tallContent
                case .large:
                    largeContent
                }
            }
            .dashboardCardFrame(for: size)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Small (1x1) Compact Glance
    @ViewBuilder
    private var smallContent: some View {
        let analysis = healthService.stressAnalysis
        let hasData = analysis != nil
        let score = analysis?.stressScore ?? 0
        let level = analysis?.stressLevel ?? .calm
        let mood = analysis?.monkeyMood ?? .zen
        let levelColor = hasData ? Color(hex: level.hexColor) : ThemeColors.fgMutedDark
        
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Stress", systemImage: "brain.head.profile")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(levelColor)
                
                Spacer()
                
                MonkeyMascotView(mood: mood, size: .badge, animated: false)
            }
            
            Spacer(minLength: 2)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(hasData ? "\(score)" : "--")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(hasData ? .white : .white.opacity(0.5))
                
                Text(hasData ? level.displayName.uppercased() : "NO DATA")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(levelColor)
            }
            
            // Mini gradient gauge
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                    if hasData {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "#00FFB2"), levelColor],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * CGFloat(min(max(Double(score) / 100.0, 0.08), 1.0)))
                    }
                }
            }
            .frame(height: 5)
            
            Spacer(minLength: 2)
            
            HStack {
                Text(hasData ? mood.displayName : "Wear watch")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(ThemeColors.fgMutedDark)
                    .lineLimit(1)
                
                Spacer()
                
                if let hrv = analysis?.currentHrvMs {
                    Text("\(Int(hrv))ms")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "#00E5FF"))
                }
            }
        }
    }
    
    // MARK: - Wide (2x1) Standard Tile
    @ViewBuilder
    private var wideContent: some View {
        let analysis = healthService.stressAnalysis
        let hasData = analysis != nil
        let score = analysis?.stressScore ?? 0
        let level = analysis?.stressLevel ?? .calm
        let mood = analysis?.monkeyMood ?? .zen
        let levelColor = hasData ? Color(hex: level.hexColor) : ThemeColors.fgMutedDark
        let para = analysis?.parasympatheticPercent ?? 65
        
        HStack(spacing: 16) {
            MonkeyMascotView(mood: mood, size: .card, animated: hasData)
                .frame(width: 64, height: 64)
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("STRESS LEVEL")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundColor(levelColor)
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Circle().fill(levelColor).frame(width: 6, height: 6)
                        Text(hasData ? level.displayName : "No Data")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(levelColor)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(levelColor.opacity(0.15))
                    .clipShape(Capsule())
                }
                
                if hasData {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(score)")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("/ 100")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(ThemeColors.fgMutedDark)
                        
                        Spacer()
                        
                        Text("\(para)% Recovery Tone")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(hex: "#00FFB2"))
                    }
                    
                    Text(mood.adviceQuote)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.85))
                        .lineLimit(1)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("--")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                        Text("/ 100")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                    
                    Text("Wear your smartwatch to track autonomic stress and HRV")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(ThemeColors.fgMutedDark)
                        .lineLimit(1)
                }
            }
        }
    }
    
    // MARK: - Tall (1x2) Vertical Tile
    @ViewBuilder
    private var tallContent: some View {
        let analysis = healthService.stressAnalysis
        let hasData = analysis != nil
        let score = analysis?.stressScore ?? 0
        let level = analysis?.stressLevel ?? .calm
        let mood = analysis?.monkeyMood ?? .zen
        let levelColor = hasData ? Color(hex: level.hexColor) : ThemeColors.fgMutedDark
        
        VStack(spacing: 12) {
            HStack {
                Label("Stress", systemImage: "brain.head.profile")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(levelColor)
                Spacer()
                Text(hasData ? level.displayName : "No Data")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(levelColor)
            }
            
            MonkeyMascotView(mood: mood, size: .card, animated: hasData)
                .frame(width: 64, height: 64)
            
            VStack(spacing: 2) {
                Text(hasData ? "\(score)" : "--")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(hasData ? .white : .white.opacity(0.5))
                Text(hasData ? mood.displayName : "Unmeasured")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(ThemeColors.fgMutedDark)
            }
            
            Divider().background(Color.white.opacity(0.08))
            
            Text(hasData ? mood.adviceQuote : "Wear your smartwatch during the day to track real-time autonomic stress.")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(hasData ? Color.white.opacity(0.85) : ThemeColors.fgMutedDark)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
    }
    
    // MARK: - Large (2x2) Full Feature Card
    @ViewBuilder
    private var largeContent: some View {
        let analysis = healthService.stressAnalysis
        let hasData = analysis != nil
        let score = analysis?.stressScore ?? 0
        let level = analysis?.stressLevel ?? .calm
        let mood = analysis?.monkeyMood ?? .zen
        let levelColor = hasData ? Color(hex: level.hexColor) : ThemeColors.fgMutedDark
        let para = analysis?.parasympatheticPercent ?? 65
        let symp = analysis?.sympatheticPercent ?? 35
        let hrv = analysis?.currentHrvMs
        
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                MonkeyMascotView(mood: mood, size: .card, animated: hasData)
                    .frame(width: 72, height: 72)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("STRESS & AUTONOMIC TONE")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundColor(levelColor)
                        Spacer()
                        Text(hasData ? level.displayName.uppercased() : "NO DATA")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(levelColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(levelColor.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(hasData ? "\(score)" : "--")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundColor(hasData ? .white : .white.opacity(0.5))
                        Text("/ 100")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(ThemeColors.fgMutedDark)
                        
                        Spacer()
                        
                        if let hrv = hrv {
                            Text("\(Int(hrv)) ms HRV")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(Color(hex: "#00E5FF"))
                        }
                    }
                }
            }
            
            if hasData {
                // Autonomic Split Bar
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: "#00FFB2"))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: "#FFA726"))
                        .frame(width: CGFloat(symp) * 1.5, height: 6)
                }
                
                HStack {
                    Text("\(para)% Rest & Digest")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "#00FFB2"))
                    Spacer()
                    Text("\(symp)% Arousal")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "#FFA726"))
                }
                
                Divider().background(Color.white.opacity(0.08))
                
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "quote.bubble.fill")
                        .font(.system(size: 13))
                        .foregroundColor(levelColor)
                    Text(mood.adviceQuote)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.9))
                        .lineSpacing(2)
                }
            } else {
                Divider().background(Color.white.opacity(0.08))
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("No biometric telemetry recorded today.")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Daily calculates physiological stress by correlating continuous Heart Rate Variability (HRV) and sedentary heart rate elevation from your Apple Watch, Amazfit, or Oura Ring.")
                        .font(.system(size: 11.5))
                        .foregroundColor(ThemeColors.fgMutedDark)
                        .lineSpacing(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
