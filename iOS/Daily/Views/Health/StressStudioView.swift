import SwiftUI
import DailyCore
#if canImport(UIKit)
import UIKit
#endif

/// Master Stress Studio screen integrating autonomic tone analysis,
/// the expressive stylized monkey mascot, intraday timeline, and interactive breathwork.
public struct StressStudioView: View {
    @ObservedObject private var healthService = HealthDataService.shared
    
    // Interactive Breathing Studio State
    @State private var selectedProtocol: BreathingProtocol = .physiologicalSigh
    @State private var isBreathingActive: Bool = false
    @State private var breathPhaseText: String = "Ready to begin"
    @State private var breathBubbleScale: CGFloat = 1.0
    @State private var breathSecondsRemaining: Int = 4
    @State private var breathCycleCount: Int = 0
    @State private var breathTimer: Timer? = nil
    
    public init() {}
    
    private func triggerHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: style).impactOccurred()
        #endif
    }
    
    public var body: some View {
        VStack(spacing: 20) {
            // 1. Hero Mascot & Stress Dial Card
            heroStressCard
            
            // 2. Autonomic Balance Gauge (Sympathetic vs Parasympathetic)
            autonomicBalanceCard
            
            // 3. Biometric Physiological Drivers Grid
            physiologicalDriversGrid
            
            // 4. Intraday Stress Curve (24-Hour Timeline)
            intradayTimelineCard
            
            // 5. Interactive Guided Breathwork Studio
            interactiveBreathingStudio
            
            // 6. Science-Backed Wisdom & Micro-Habits Card
            monkeyWisdomCard
        }
        .onDisappear {
            stopBreathingSession()
        }
    }
    
    // MARK: - 1. Hero Mascot & Stress Dial Card
    
    private var heroStressCard: some View {
        let score = healthService.currentStressScore
        let level = healthService.currentStressLevel
        let mood = healthService.stressAnalysis?.monkeyMood ?? .curious
        let levelColor = Color(hex: level.hexColor)
        
        return GlassCard(cornerRadius: 24, padding: 20) {
            VStack(spacing: 16) {
                HStack(alignment: .center, spacing: 18) {
                    // Left: Stylized Vector Mascot
                    MonkeyMascotView(mood: mood, size: .card, animated: true)
                        .frame(width: 84, height: 84)
                    
                    // Right: Score Dial & Status Pill
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text("\(score)")
                                .font(.system(size: 42, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("/ 100")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                                Text("STRESS")
                                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                                    .foregroundColor(levelColor)
                            }
                        }
                        
                        // Status Badge Pill
                        HStack(spacing: 6) {
                            Circle()
                                .fill(levelColor)
                                .frame(width: 8, height: 8)
                                .shadow(color: levelColor.opacity(0.8), radius: 4)
                            
                            Text(level.displayName.uppercased())
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(levelColor)
                            
                            Text("•")
                                .foregroundColor(.white.opacity(0.4))
                            
                            Text(mood.displayName)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(levelColor.opacity(0.15))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(levelColor.opacity(0.35), lineWidth: 1))
                    }
                    
                    Spacer()
                }
                
                Divider()
                    .background(Color.white.opacity(0.08))
                
                // Monkey's Contextual Advice Bubble
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "quote.bubble.fill")
                        .font(.system(size: 14))
                        .foregroundColor(levelColor)
                        .padding(.top, 2)
                    
                    Text(mood.adviceQuote)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.92))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    
    // MARK: - 2. Autonomic Balance Card
    
    private var autonomicBalanceCard: some View {
        let para = healthService.stressAnalysis?.parasympatheticPercent ?? 65
        let symp = healthService.stressAnalysis?.sympatheticPercent ?? 35
        
        return GlassCard(cornerRadius: 20, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Autonomic Tone Balance", systemImage: "waveform.path.ecg")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(ThemeColors.accentCyan)
                    
                    Spacer()
                    
                    Text(para >= 55 ? "Recovery Dominant" : "Arousal Dominant")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(para >= 55 ? Color(hex: "#00FFB2") : Color(hex: "#FFA726"))
                }
                
                // Dual Stacked Progress Bar
                GeometryReader { geo in
                    let totalW = geo.size.width
                    let paraW = totalW * (CGFloat(para) / 100.0)
                    let sympW = totalW - paraW
                    
                    HStack(spacing: 3) {
                        // Parasympathetic Segment (Rest & Digest)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "#00E5FF"), Color(hex: "#00FFB2")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(8, paraW - 1.5), height: 10)
                        
                        // Sympathetic Segment (Fight or Flight)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "#FFA726"), Color(hex: "#FF5252")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(8, sympW - 1.5), height: 10)
                    }
                }
                .frame(height: 10)
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(para)% Parasympathetic")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "#00FFB2"))
                        Text("Rest, repair & heart adaptability")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(symp)% Sympathetic")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "#FFA726"))
                        Text("Arousal, energy & cognitive load")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                }
            }
        }
    }
    
    // MARK: - 3. Biometric Physiological Drivers Grid
    
    private var physiologicalDriversGrid: some View {
        let analysis = healthService.stressAnalysis
        let baselineHrv = analysis?.baselineHrvMs ?? 45.0
        let currentHrv = analysis?.currentHrvMs ?? 48.0
        let hrvDelta = analysis?.hrvDeltaPercent ?? 6.0
        let restingBpm = analysis?.restingHeartRateBpm ?? 60.0
        let hrDelta = analysis?.heartRateElevationBpm ?? 3.0
        
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            // Driver 1: Heart Rate Variability (SDNN)
            driverTile(
                title: "HRV (SDNN)",
                valueText: String(format: "%.0f ms", currentHrv),
                deltaText: String(format: "%+.0f%% vs base", hrvDelta),
                isPositive: hrvDelta >= 0,
                subtitle: "Baseline: \(Int(baselineHrv)) ms",
                icon: "waveform.path",
                tintColor: Color(hex: "#00E5FF")
            )
            
            // Driver 2: Resting Heart Rate
            driverTile(
                title: "Resting Heart Rate",
                valueText: "\(Int(restingBpm)) bpm",
                deltaText: "Baseline reference",
                isPositive: true,
                subtitle: "Cardiovascular floor",
                icon: "heart.fill",
                tintColor: Color(hex: "#FF5252")
            )
            
            // Driver 3: Sedentary HR Elevation
            driverTile(
                title: "Sedentary Elevation",
                valueText: String(format: "%+.0f bpm", hrDelta),
                deltaText: hrDelta <= 6 ? "Calm arousal" : "Elevated tension",
                isPositive: hrDelta <= 8,
                subtitle: "Resting delta without movement",
                icon: "flame.fill",
                tintColor: Color(hex: "#FFA726")
            )
            
            // Driver 4: Sleep Recovery Multiplier
            let sleepScore = healthService.primarySleepSession?.sleepScore ?? 82
            driverTile(
                title: "Sleep Readiness",
                valueText: "\(sleepScore)%",
                deltaText: sleepScore >= 75 ? "Optimal recovery" : "Sleep debt",
                isPositive: sleepScore >= 75,
                subtitle: healthService.primarySleepSession?.totalAsleepFormatted ?? "7h 20m",
                icon: "moon.fill",
                tintColor: ThemeColors.accentPurple
            )
        }
    }
    
    @ViewBuilder
    private func driverTile(
        title: String,
        valueText: String,
        deltaText: String,
        isPositive: Bool,
        subtitle: String,
        icon: String,
        tintColor: Color
    ) -> some View {
        GlassCard(cornerRadius: 16, padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundColor(tintColor)
                    Text(title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
                
                Text(valueText)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                HStack(spacing: 4) {
                    Text(deltaText)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(isPositive ? Color(hex: "#00FFB2") : Color(hex: "#FFA726"))
                }
                
                Text(subtitle)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }
    
    // MARK: - 4. Intraday Stress Timeline
    
    private var intradayTimelineCard: some View {
        let points = healthService.intradayStress
        let pointsToDisplay = points.isEmpty ? generateMockTimeline() : points
        
        return GlassCard(cornerRadius: 20, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Intraday Stress Rhythm", systemImage: "chart.xyaxis.line")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(ThemeColors.accentBlue)
                    
                    Spacer()
                    
                    let avg = healthService.stressAnalysis?.dailyAverageScore ?? 35
                    Text("Daily Avg: \(avg)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
                
                // Hourly timeline bar graph
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(pointsToDisplay) { pt in
                            VStack(spacing: 4) {
                                let barH = max(8.0, CGFloat(pt.score) * 0.7)
                                let barColor = Color(hex: pt.level.hexColor)
                                
                                ZStack(alignment: .bottom) {
                                    Capsule()
                                        .fill(Color.white.opacity(0.08))
                                        .frame(width: 14, height: 70)
                                    
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [barColor, barColor.opacity(0.6)],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .frame(width: 14, height: barH)
                                }
                                
                                Text("\(pt.hour)")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
    
    // MARK: - 5. Interactive Guided Breathwork Studio
    
    private var interactiveBreathingStudio: some View {
        GlassCard(cornerRadius: 22, padding: 20) {
            VStack(spacing: 16) {
                HStack {
                    Label("Guided Autonomic Breathwork", systemImage: "wind")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(ThemeColors.accentCyan)
                    
                    Spacer()
                    
                    // Protocol Picker
                    Menu {
                        ForEach(BreathingProtocol.allCases) { proto in
                            Button {
                                selectedProtocol = proto
                                if isBreathingActive {
                                    stopBreathingSession()
                                }
                            } label: {
                                if selectedProtocol == proto {
                                    Label(proto.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(proto.rawValue)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(selectedProtocol.rawValue)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundColor(ThemeColors.accentCyan)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(ThemeColors.accentCyan.opacity(0.15))
                        .clipShape(Capsule())
                    }
                }
                
                Text(selectedProtocol.description)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(ThemeColors.fgMutedDark)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                
                // Breath Animation Bubble
                ZStack {
                    Circle()
                        .stroke(ThemeColors.accentCyan.opacity(0.2), lineWidth: 2)
                        .frame(width: 140, height: 140)
                    
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    ThemeColors.accentCyan.opacity(0.4),
                                    ThemeColors.accentBlue.opacity(0.15),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 10,
                                endRadius: 70
                            )
                        )
                        .frame(width: 130, height: 130)
                        .scaleEffect(breathBubbleScale)
                    
                    VStack(spacing: 4) {
                        Text(breathPhaseText)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        if isBreathingActive {
                            Text("\(breathSecondsRemaining)s")
                                .font(.system(size: 24, weight: .heavy, design: .rounded))
                                .foregroundColor(ThemeColors.accentCyan)
                        } else {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(ThemeColors.accentCyan)
                        }
                    }
                }
                .frame(height: 150)
                .contentShape(Rectangle())
                .onTapGesture {
                    if isBreathingActive {
                        stopBreathingSession()
                    } else {
                        startBreathingSession()
                    }
                }
                
                // Control Button
                Button {
                    if isBreathingActive {
                        stopBreathingSession()
                    } else {
                        startBreathingSession()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isBreathingActive ? "pause.fill" : "play.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text(isBreathingActive ? "Pause Protocol (\(breathCycleCount)/\(selectedProtocol.cyclesRecommended) cycles)" : "Begin Session (\(selectedProtocol.cyclesRecommended) cycles)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [ThemeColors.accentCyan.opacity(0.7), ThemeColors.accentBlue.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                }
            }
        }
    }
    
    // MARK: - 6. Science-Backed Wisdom Card
    
    private var monkeyWisdomCard: some View {
        GlassCard(cornerRadius: 20, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("🐵")
                        .font(.system(size: 18))
                    Text("Monkey's Golden Rules for Autonomic Health")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    wisdomRow(
                        icon: "drop.fill",
                        title: "Hydration Floor",
                        desc: "Mild dehydration raises heart rate by 5–8 bpm without movement. Keep your Bubbles intake steady.",
                        color: ThemeColors.accentBlue
                    )
                    
                    wisdomRow(
                        icon: "sun.max.fill",
                        title: "Morning Retinal Photons",
                        desc: "10 minutes of sunlight within 1 hour of waking calibrates cortisol and prepares high nocturnal HRV.",
                        color: Color(hex: "#FFA726")
                    )
                    
                    wisdomRow(
                        icon: "figure.walk",
                        title: "5-Minute Nature Break",
                        desc: "Looking at long-horizon perspectives activates panoramic vision, suppressing sympathetic tone.",
                        color: Color(hex: "#00FFB2")
                    )
                }
            }
        }
    }
    
    @ViewBuilder
    private func wisdomRow(icon: String, title: String, desc: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(color.opacity(0.2))
                .frame(width: 26, height: 26)
                .overlay(Image(systemName: icon).font(.system(size: 11)).foregroundColor(color))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(desc)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(ThemeColors.fgMutedDark)
                    .lineSpacing(2)
            }
        }
    }
    
    // MARK: - Breathwork Session Driver
    
    private func startBreathingSession() {
        isBreathingActive = true
        breathCycleCount = 0
        triggerHaptic(style: .heavy)
        
        switch selectedProtocol {
        case .physiologicalSigh:
            runPhysiologicalSighStep(step: 0)
        case .boxBreathing:
            runBoxBreathingStep(step: 0)
        case .resonanceFlow:
            runResonanceStep(step: 0)
        case .relax478:
            run478Step(step: 0)
        }
    }
    
    private func stopBreathingSession() {
        isBreathingActive = false
        breathTimer?.invalidate()
        breathTimer = nil
        breathPhaseText = "Session Paused"
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            breathBubbleScale = 1.0
        }
    }
    
    private func runPhysiologicalSighStep(step: Int) {
        guard isBreathingActive else { return }
        
        // Step 0: Inhale 1 (nose, 2s)
        // Step 1: Inhale 2 (nose quick top-off, 1s)
        // Step 2: Long Exhale (mouth sigh, 5s)
        let phase: (text: String, duration: Int, targetScale: CGFloat)
        switch step % 3 {
        case 0:
            phase = ("Deep Inhale (Nose)", 2, 1.25)
            triggerHaptic(style: .medium)
        case 1:
            phase = ("Quick Top-Off Inhale", 1, 1.4)
            triggerHaptic(style: .light)
        default:
            phase = ("Long Sigh Exhale", 5, 0.85)
            triggerHaptic(style: .soft)
        }
        
        breathPhaseText = phase.text
        breathSecondsRemaining = phase.duration
        withAnimation(.easeInOut(duration: Double(phase.duration))) {
            breathBubbleScale = phase.targetScale
        }
        
        breathTimer?.invalidate()
        breathTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] t in
            if breathSecondsRemaining > 1 {
                breathSecondsRemaining -= 1
            } else {
                t.invalidate()
                let nextStep = step + 1
                if nextStep % 3 == 0 {
                    breathCycleCount += 1
                    if breathCycleCount >= selectedProtocol.cyclesRecommended {
                        completeSession()
                        return
                    }
                }
                runPhysiologicalSighStep(step: nextStep)
            }
        }
    }
    
    private func runBoxBreathingStep(step: Int) {
        guard isBreathingActive else { return }
        
        // Step 0: Inhale 4s -> Step 1: Hold 4s -> Step 2: Exhale 4s -> Step 3: Hold 4s
        let phase: (text: String, targetScale: CGFloat)
        switch step % 4 {
        case 0: phase = ("Inhale (4s)", 1.35)
        case 1: phase = ("Hold Breath (4s)", 1.35)
        case 2: phase = ("Exhale (4s)", 0.85)
        default: phase = ("Hold Empty (4s)", 0.85)
        }
        
        breathPhaseText = phase.text
        breathSecondsRemaining = 4
        triggerHaptic(style: .medium)
        withAnimation(.easeInOut(duration: 4.0)) {
            breathBubbleScale = phase.targetScale
        }
        
        breathTimer?.invalidate()
        breathTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] t in
            if breathSecondsRemaining > 1 {
                breathSecondsRemaining -= 1
            } else {
                t.invalidate()
                let nextStep = step + 1
                if nextStep % 4 == 0 {
                    breathCycleCount += 1
                    if breathCycleCount >= selectedProtocol.cyclesRecommended {
                        completeSession()
                        return
                    }
                }
                runBoxBreathingStep(step: nextStep)
            }
        }
    }
    
    private func runResonanceStep(step: Int) {
        guard isBreathingActive else { return }
        let phase = (step % 2 == 0) ? ("Smooth Inhale", 1.3) : ("Smooth Exhale", 0.85)
        breathPhaseText = phase.0
        breathSecondsRemaining = 5
        triggerHaptic(style: .soft)
        withAnimation(.easeInOut(duration: 5.0)) {
            breathBubbleScale = phase.1
        }
        
        breathTimer?.invalidate()
        breathTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] t in
            if breathSecondsRemaining > 1 {
                breathSecondsRemaining -= 1
            } else {
                t.invalidate()
                let next = step + 1
                if next % 2 == 0 {
                    breathCycleCount += 1
                    if breathCycleCount >= selectedProtocol.cyclesRecommended {
                        completeSession()
                        return
                    }
                }
                runResonanceStep(step: next)
            }
        }
    }
    
    private func run478Step(step: Int) {
        guard isBreathingActive else { return }
        let phase: (text: String, duration: Int, targetScale: CGFloat)
        switch step % 3 {
        case 0: phase = ("Inhale (4s)", 4, 1.35)
        case 1: phase = ("Hold (7s)", 7, 1.35)
        default: phase = ("Exhale Mouth (8s)", 8, 0.8)
        }
        
        breathPhaseText = phase.text
        breathSecondsRemaining = phase.duration
        triggerHaptic(style: .medium)
        withAnimation(.easeInOut(duration: Double(phase.duration))) {
            breathBubbleScale = phase.targetScale
        }
        
        breathTimer?.invalidate()
        breathTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] t in
            if breathSecondsRemaining > 1 {
                breathSecondsRemaining -= 1
            } else {
                t.invalidate()
                let next = step + 1
                if next % 3 == 0 {
                    breathCycleCount += 1
                    if breathCycleCount >= selectedProtocol.cyclesRecommended {
                        completeSession()
                        return
                    }
                }
                run478Step(step: next)
            }
        }
    }
    
    private func completeSession() {
        stopBreathingSession()
        breathPhaseText = "Zen Restored! 🐵"
        triggerHaptic(style: .heavy)
    }
    
    private func generateMockTimeline() -> [IntradayStressPoint] {
        let cal = Calendar.current
        let today = Date()
        return (6...22).map { h in
            let score = 25 + Int(sin(Double(h) / 3.0) * 20.0) + (h == 14 ? 25 : 0)
            let clamped = min(max(score, 12), 85)
            let hourDate = cal.date(bySettingHour: h, minute: 0, second: 0, of: today) ?? today
            return IntradayStressPoint(
                timestamp: hourDate,
                hour: h,
                score: clamped,
                level: StressLevel.from(score: clamped)
            )
        }
    }
}
