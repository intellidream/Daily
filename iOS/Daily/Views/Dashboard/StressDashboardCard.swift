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
        let score = healthService.currentStressScore
        let level = healthService.currentStressLevel
        let mood = healthService.stressAnalysis?.monkeyMood ?? .curious
        let levelColor = Color(hex: level.hexColor)
        
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
                Text("\(score)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text(level.displayName.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(levelColor)
            }
            
            // Mini gradient gauge
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
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
            .frame(height: 5)
            
            Spacer(minLength: 2)
            
            HStack {
                Text(mood.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(ThemeColors.fgMutedDark)
                    .lineLimit(1)
                
                Spacer()
                
                if let hrv = healthService.stressAnalysis?.currentHrvMs {
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
        let score = healthService.currentStressScore
        let level = healthService.currentStressLevel
        let mood = healthService.stressAnalysis?.monkeyMood ?? .curious
        let levelColor = Color(hex: level.hexColor)
        let para = healthService.stressAnalysis?.parasympatheticPercent ?? 65
        
        HStack(spacing: 16) {
            MonkeyMascotView(mood: mood, size: .card, animated: true)
                .frame(width: 64, height: 64)
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("STRESS LEVEL")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundColor(levelColor)
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Circle().fill(levelColor).frame(width: 6, height: 6)
                        Text(level.displayName)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(levelColor)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(levelColor.opacity(0.15))
                    .clipShape(Capsule())
                }
                
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
            }
        }
    }
    
    // MARK: - Tall (1x2) Vertical Tile
    @ViewBuilder
    private var tallContent: some View {
        let score = healthService.currentStressScore
        let level = healthService.currentStressLevel
        let mood = healthService.stressAnalysis?.monkeyMood ?? .curious
        let levelColor = Color(hex: level.hexColor)
        
        VStack(spacing: 12) {
            HStack {
                Label("Stress", systemImage: "brain.head.profile")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(levelColor)
                Spacer()
                Text(level.displayName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(levelColor)
            }
            
            MonkeyMascotView(mood: mood, size: .card, animated: true)
                .frame(width: 64, height: 64)
            
            VStack(spacing: 2) {
                Text("\(score)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(mood.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(ThemeColors.fgMutedDark)
            }
            
            Divider().background(Color.white.opacity(0.08))
            
            Text(mood.adviceQuote)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
    }
    
    // MARK: - Large (2x2) Full Feature Card
    @ViewBuilder
    private var largeContent: some View {
        let score = healthService.currentStressScore
        let level = healthService.currentStressLevel
        let mood = healthService.stressAnalysis?.monkeyMood ?? .curious
        let levelColor = Color(hex: level.hexColor)
        let para = healthService.stressAnalysis?.parasympatheticPercent ?? 65
        let symp = healthService.stressAnalysis?.sympatheticPercent ?? 35
        let hrv = healthService.stressAnalysis?.currentHrvMs ?? 48
        
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                MonkeyMascotView(mood: mood, size: .card, animated: true)
                    .frame(width: 72, height: 72)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("STRESS & AUTONOMIC TONE")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundColor(levelColor)
                        Spacer()
                        Text(level.displayName.uppercased())
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(levelColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(levelColor.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(score)")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("/ 100")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(ThemeColors.fgMutedDark)
                        
                        Spacer()
                        
                        Text("\(Int(hrv)) ms HRV")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "#00E5FF"))
                    }
                }
            }
            
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
        }
    }
}
