import SwiftUI
import DailyCore

/// Scientific Guidance Sheet for Circadian Hydration and 4D Tobacco Craving Recovery.
public struct HabitGuidanceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: HabitType
    
    // 4D Craving Protocol Timer State
    @State private var delaySecondsRemaining = 300 // 5 minutes
    @State private var isDelayTimerRunning = false
    @State private var timerSubscription: Timer? = nil
    
    // Breathing Orb State (4-7-8 method)
    @State private var breathScale: CGFloat = 0.8
    @State private var breathPhaseText = "Inhale (4s)"
    
    public init(initialHabit: HabitType = .water) {
        self._selectedTab = State(initialValue: initialHabit)
    }
    
    public var body: some View {
        NavigationStack {
            LiquidGlassBackground {
                ScrollView {
                    VStack(spacing: 20) {
                        // Segmented Picker
                        Picker("Guidance Mode", selection: $selectedTab) {
                            Text("Circadian Hydration").tag(HabitType.water)
                            Text("Craving Recovery (4D)").tag(HabitType.smokes)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        
                        if selectedTab == .water {
                            bubblesGuidanceContent
                        } else {
                            smokesGuidanceContent
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Scientific Guidance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        timerSubscription?.invalidate()
                        dismiss()
                    }
                    .foregroundColor(ThemeColors.accentCyan)
                }
            }
        }
    }
    
    // MARK: - Bubbles / Hydration Guidance
    
    private var bubblesGuidanceContent: some View {
        VStack(spacing: 16) {
            // 1. Circadian Hydration Schedule
            GlassCard(cornerRadius: 18, padding: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Diurnal Circadian Schedule", systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(ThemeColors.accentCyan)
                    
                    Text("Align fluid intake with cortisol peaks and renal filtration rhythms to maximize cellular hydration and sleep quality.")
                        .font(.system(size: 12))
                        .foregroundColor(ThemeColors.fgMutedDark)
                    
                    VStack(spacing: 12) {
                        ForEach(HabitsGuidance.circadianSlots) { slot in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: slot.iconName)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(ThemeColors.accentCyan)
                                    .frame(width: 24)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(slot.name)
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(.white)
                                        Spacer()
                                        Text("\(slot.timeWindow) • \(Int(slot.targetMl)) ml")
                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                            .foregroundColor(ThemeColors.accentCyan)
                                    }
                                    
                                    Text(slot.description)
                                        .font(.system(size: 11))
                                        .foregroundColor(ThemeColors.fgMutedDark)
                                }
                            }
                            if slot.id != HabitsGuidance.circadianSlots.last?.id {
                                Divider().background(Color.white.opacity(0.1))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            
            // 2. Armstrong Urine Color Scale
            GlassCard(cornerRadius: 18, padding: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Armstrong Urine Scale", systemImage: "eyedropper.halffull")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "#FFB800"))
                    
                    Text("Validated clinical metric for hydration assessment. Aim for stages 1 to 3 throughout active daylight hours.")
                        .font(.system(size: 12))
                        .foregroundColor(ThemeColors.fgMutedDark)
                    
                    VStack(spacing: 8) {
                        ForEach(HabitsGuidance.armstrongUrineScale) { item in
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(hex: item.colorHex))
                                    .frame(width: 24, height: 24)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 4)
                                            .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                                    }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text("Level \(item.level): \(item.name)")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.white)
                                        Spacer()
                                        Text(item.status)
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(item.level <= 3 ? Color(hex: "#00FFB2") : Color(hex: "#FFB800"))
                                    }
                                    Text(item.recommendation)
                                        .font(.system(size: 10))
                                        .foregroundColor(ThemeColors.fgMutedDark)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            
            // 3. Drink Hydration Index (DHI)
            GlassCard(cornerRadius: 18, padding: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Drink Hydration Index (DHI)", systemImage: "chart.bar.xaxis")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(ThemeColors.accentBlue)
                    
                    Text("Fluid retention index relative to plain water (1.0). High electrolyte and protein drinks retain cellular water longer.")
                        .font(.system(size: 12))
                        .foregroundColor(ThemeColors.fgMutedDark)
                    
                    VStack(spacing: 8) {
                        ForEach(HabitsGuidance.drinkHydrationIndex) { dhi in
                            HStack {
                                Image(systemName: dhi.iconName)
                                    .font(.system(size: 14))
                                    .foregroundColor(ThemeColors.accentCyan)
                                    .frame(width: 20)
                                Text(dhi.beverage)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                                Spacer()
                                Text(String(format: "%.2fx", dhi.index))
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(dhi.index >= 1.0 ? Color(hex: "#00FFB2") : Color(hex: "#FFB800"))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Smokes / Tobacco Recovery Guidance
    
    private var smokesGuidanceContent: some View {
        VStack(spacing: 16) {
            // 1. 4D Craving Emergency Interactive Hub
            GlassCard(cornerRadius: 18, padding: 18) {
                VStack(spacing: 16) {
                    HStack {
                        Label("4D Craving Protocol", systemImage: "shield.fill")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "#00FFB2"))
                        Spacer()
                    }
                    
                    Text("Nicotine cravings peak at 3-5 minutes and then subside. Execute the 4 steps below to survive acute craving waves.")
                        .font(.system(size: 12))
                        .foregroundColor(ThemeColors.fgMutedDark)
                    
                    // Delay Timer
                    VStack(spacing: 8) {
                        Text(formatTimer(delaySecondsRemaining))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Button {
                            toggleDelayTimer()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isDelayTimerRunning ? "pause.fill" : "play.fill")
                                Text(isDelayTimerRunning ? "Pause Craving Timer" : "Start 5-Min Delay")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(isDelayTimerRunning ? Color(hex: "#FFB800") : Color(hex: "#00FFB2"))
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, 8)
                    
                    // 4D Steps
                    VStack(spacing: 10) {
                        ForEach(HabitsGuidance.fourDsCravingProtocol) { step in
                            HStack(alignment: .top, spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: "#00FFB2").opacity(0.2))
                                        .frame(width: 28, height: 28)
                                    Text("\(step.step)")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(Color(hex: "#00FFB2"))
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(step.title) — \(step.action)")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.white)
                                    Text(step.explanation)
                                        .font(.system(size: 11))
                                        .foregroundColor(ThemeColors.fgMutedDark)
                                }
                            }
                            if step.step < 4 {
                                Divider().background(Color.white.opacity(0.1))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            
            // 2. Scientific Recovery Milestones
            GlassCard(cornerRadius: 18, padding: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Scientific Recovery Timeline", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(ThemeColors.accentCyan)
                    
                    VStack(spacing: 12) {
                        ForEach(HabitsGuidance.recoveryMilestones) { milestone in
                            HStack(alignment: .top, spacing: 12) {
                                Text(milestone.timeframe)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(hex: "#00FFB2"))
                                    .frame(width: 65, alignment: .leading)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(milestone.benefit)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.white)
                                    Text(milestone.scientificDetail)
                                        .font(.system(size: 10))
                                        .foregroundColor(ThemeColors.fgMutedDark)
                                }
                            }
                            if milestone.id != HabitsGuidance.recoveryMilestones.last?.id {
                                Divider().background(Color.white.opacity(0.1))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    private func formatTimer(_ totalSeconds: Int) -> String {
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }
    
    private func toggleDelayTimer() {
        if isDelayTimerRunning {
            timerSubscription?.invalidate()
            timerSubscription = nil
            isDelayTimerRunning = false
        } else {
            isDelayTimerRunning = true
            timerSubscription = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                if delaySecondsRemaining > 0 {
                    delaySecondsRemaining -= 1
                } else {
                    timerSubscription?.invalidate()
                    timerSubscription = nil
                    isDelayTimerRunning = false
                }
            }
        }
    }
}
