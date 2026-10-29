import SwiftUI
import DailyCore
import AppKit

// MARK: - Prefabricated Co-Pilot Prompt Topic

public enum CoPilotPrefabTopic: String, CaseIterable, Identifiable {
    case sleepRecovery = "sleep_recovery"
    case circadianHydration = "circadian_hydration"
    case tonightsSky = "tonights_sky"
    case urgentFocus = "urgent_focus"
    case stressReset = "stress_reset"
    case wealthPulse = "wealth_pulse"
    
    public var id: String { rawValue }
    
    public var chipLabel: String {
        switch self {
        case .sleepRecovery: return "Sleep & Readiness"
        case .circadianHydration: return "Circadian Hydration"
        case .tonightsSky: return "Tonight's Sky"
        case .urgentFocus: return "Urgent Focus"
        case .stressReset: return "Stress & Breathing"
        case .wealthPulse: return "Cashflow Pulse"
        }
    }
    
    public var fullQuestion: String {
        switch self {
        case .sleepRecovery: return "How did my sleep architecture & recovery look last night?"
        case .circadianHydration: return "What is my optimal circadian hydration & craving protocol right now?"
        case .tonightsSky: return "What can I observe in tonight's sky, and what is my Stargazing Score?"
        case .urgentFocus: return "What are my top priorities and active memos in Tagdos?"
        case .stressReset: return "How is my autonomic stress balance? Guide me through a quick reset."
        case .wealthPulse: return "How does my monthly inflow vs. outflow & net worth look?"
        }
    }
    
    public var iconName: String {
        switch self {
        case .sleepRecovery: return "bed.double.fill"
        case .circadianHydration: return "drop.fill"
        case .tonightsSky: return "moon.stars.fill"
        case .urgentFocus: return "target"
        case .stressReset: return "wind"
        case .wealthPulse: return "chart.line.uptrend.xyaxis"
        }
    }
    
    public var accentColor: Color {
        switch self {
        case .sleepRecovery: return Color(hex: "#A855F7")
        case .circadianHydration: return Color(hex: "#00E5FF")
        case .tonightsSky: return Color(hex: "#38BDF8")
        case .urgentFocus: return Color(hex: "#FFB300")
        case .stressReset: return Color(hex: "#00E676")
        case .wealthPulse: return Color(hex: "#10B981")
        }
    }
    
    public var targetTab: NavigationTab {
        switch self {
        case .sleepRecovery: return .health
        case .circadianHydration: return .habits
        case .tonightsSky: return .cosmos
        case .urgentFocus: return .tagdos
        case .stressReset: return .health
        case .wealthPulse: return .finances
        }
    }
    
    public var portalButtonTitle: String {
        switch self {
        case .sleepRecovery: return "Open Sleep & Health Hub"
        case .circadianHydration: return "Open Habits & Hydration Hub"
        case .tonightsSky: return "Open Cosmos Observatory"
        case .urgentFocus: return "Open Tagdos & Notes Hub"
        case .stressReset: return "Open Stress & Vitals Hub"
        case .wealthPulse: return "Open Smart Ledger Hub"
        }
    }
}

// MARK: - Inline Co-Pilot Response Model

private struct CoPilotInlineTurn: Identifiable, Equatable {
    let id = UUID()
    let question: String
    let headline: String
    let body: String
    let highlights: [String]
    let targetTab: NavigationTab
    let portalTitle: String
    let accentColor: Color
}

/// Signature Foldable & Desktop Workspace Companion Pane ("The Hybrid Co-Pilot")
/// displayed in the secondary / detail pane on macOS Dual-Pane Workspace, iPhone Duo,
/// and Samsung Galaxy Z Fold 8 ("RADAR").
///
/// 1:1 visual and functional parity across iOS, Android, and macOS:
/// 1. Diurnal Intelligence Header + Live BPM Pill
/// 2. Hero Widget: Concentric Recovery Rings (Steps, Sleep, Water) + Animated Monkey Mascot + Interactive Legend
/// 3. Interactive Monkey Co-Pilot Studio: Live cross-domain synthesis, Prefabricated Smart Prompt Chips,
///    inline conversational answers with clinical/actionable highlights, free-form query input, and Hub portals
/// 4. Unified "Daily Spotlight & Portals" Composite Card: Non-redundant qualitative insights across
///    Focus Streams, Circadian Bio-Guidance, Cashflow Momentum, and Radar & Sky with 1-tap Hub navigation.
public struct DailyFoldableCompanionPane: View {
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var healthService = HealthDataService.shared
    @ObservedObject private var habitsService = HabitsService.shared
    @ObservedObject private var ledgerStore = SmartLedgerStore.shared
    @ObservedObject private var tagdosStore = TagdosStore.shared
    @ObservedObject private var newsService = NewsService.shared
    @ObservedObject private var weatherService = WeatherService.shared
    @ObservedObject private var briefingService = SmartBriefingService.shared
    
    @State private var selectedPrefab: CoPilotPrefabTopic? = nil
    @State private var activeTurn: CoPilotInlineTurn? = nil
    @State private var customQueryText: String = ""
    
    public let onOpenHub: (NavigationTab) -> Void
    public let onOpenBriefing: () -> Void
    
    public init(
        onOpenHub: @escaping (NavigationTab) -> Void,
        onOpenBriefing: @escaping () -> Void
    ) {
        self.onOpenHub = onOpenHub
        self.onOpenBriefing = onOpenBriefing
    }
    
    private func triggerHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
    
    // MARK: - Computed Telemetry & Diurnal State
    
    private var slot: BriefingTimeSlot {
        briefingService.activeBriefing?.slot ?? BriefingTimeSlot.current()
    }
    
    private var diurnalWish: String {
        if let wish = briefingService.activeBriefing?.narrative.closingWish,
           !wish.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return wish
        }
        return slot.defaultClosingWish
    }
    
    private var displayBpm: Int {
        let val = healthService.restingBpm > 0 ? healthService.restingBpm : healthService.averageBpm
        return Int(val.rounded())
    }
    
    private var stepsProgress: Double {
        min(max(Double(healthService.totalStepsToday) / 10000.0, 0.0), 1.0)
    }
    
    private var sleepScore: Int {
        healthService.primarySleepSession?.sleepScore ?? 0
    }
    
    private var sleepProgress: Double {
        let effective = sleepScore > 0 ? Double(sleepScore) : 75.0
        return min(max(effective / 100.0, 0.0), 1.0)
    }
    
    private var hydrationProgress: Double {
        let goal = max(habitsService.waterGoal, 1000.0)
        return min(max(habitsService.waterTotalToday / goal, 0.0), 1.0)
    }
    
    private var currentMood: MonkeyMood {
        switch healthService.currentStressLevel {
        case .restful: return .zen
        case .calm: return .curious
        case .moderate: return .busy
        case .high: return .overheated
        }
    }
    
    private var activeCircadianHydrationSlot: CircadianHydrationSlot {
        let hour = Calendar.current.component(.hour, from: Date())
        let slots = HabitsGuidance.circadianSlots
        guard slots.count >= 5 else {
            return CircadianHydrationSlot(
                timeRange: "All Day",
                title: "Cellular Hydration",
                recommendedVolumeMl: 300,
                rationale: "Maintain steady water intake for optimal cognitive focus.",
                iconName: "drop.fill"
            )
        }
        switch hour {
        case 5..<10: return slots[0]  // Morning Kickstart
        case 10..<13: return slots[1] // Cognitive Focus Peak
        case 13..<14: return slots[2] // Digestive Preparation
        case 14..<20: return slots[3] // Afternoon Energy Boost
        default: return slots[4]      // Night Taper
        }
    }
    
    // MARK: - Body
    
    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 14) {
                // 1. 1:1 Diurnal Intelligence Header + Live BPM Pill
                diurnalHeader
                    .padding(.top, 8)
                
                // 2. 1:1 Concentric Recovery Rings & Mascot Hero Widget
                concentricHeroWidget
                
                // 3. Monkey Co-Pilot Conversational Studio (Inline Synthesis + Prefab Chips + Chat)
                coPilotConversationalStudio
                
                // 4. Unified Daily Spotlight & Hub Matrix (Replaces redundant mini-widget tiles)
                dailySpotlightMatrix
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 60)
        }
        .scrollBounceBehavior(.always, axes: .vertical)
        .task(id: "\(healthService.primarySleepSession?.id ?? "")-\(healthService.primarySleepSession?.sleepScore ?? 0)-\(slot.rawValue)") {
            let currentBrief = briefingService.activeBriefing
            let currentSleep = healthService.primarySleepSession
            let needsRefresh = currentBrief == nil ||
                currentBrief?.slot != slot ||
                currentBrief?.metrics.sleepScore != currentSleep?.sleepScore ||
                currentBrief?.metrics.sleepDurationFormatted != currentSleep?.totalAsleepFormatted
            if needsRefresh {
                _ = await briefingService.getOrGenerateBriefing(forceRefresh: true)
            }
        }
    }
    
    // MARK: - 1. Diurnal Header (1:1 Parity with Android & iOS)
    
    private var diurnalHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: slot.systemImage)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(ThemeColors.accentCyan)
                    
                    Text(slot.displayName.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.0)
                        .foregroundColor(ThemeColors.accentCyan)
                }
                
                Text(diurnalWish)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            
            Spacer(minLength: 8)
            
            // Live Heart Rate Pill (tappable -> Health Hub)
            Button(action: {
                triggerHaptic()
                onOpenHub(.health)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(hex: "#FF2D55"))
                    
                    Text(displayBpm > 0 ? "\(displayBpm) BPM" : "-- BPM")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .help("Open Health & Vitals Hub")
        }
        .frame(height: 56)
    }
    
    // MARK: - 2. Concentric Recovery Rings & Mascot Hero Widget
    
    private var concentricHeroWidget: some View {
        GlassCard(cornerRadius: 24, padding: 20) {
            VStack(spacing: 16) {
                ZStack {
                    // Outer Ring: Steps (Orange)
                    Circle()
                        .stroke(Color(hex: "#FF9100").opacity(0.15), lineWidth: 10)
                        .frame(width: 170, height: 170)
                    Circle()
                        .trim(from: 0, to: stepsProgress)
                        .stroke(
                            LinearGradient(
                                colors: [Color(hex: "#FF9100"), Color(hex: "#FF5722")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 170, height: 170)
                        .animation(.spring(response: 0.75, dampingFraction: 0.75), value: stepsProgress)
                    
                    // Middle Ring: Sleep Recovery (Purple)
                    Circle()
                        .stroke(Color(hex: "#A855F7").opacity(0.15), lineWidth: 10)
                        .frame(width: 136, height: 136)
                    Circle()
                        .trim(from: 0, to: sleepProgress)
                        .stroke(
                            LinearGradient(
                                colors: [Color(hex: "#8B5CF6"), Color(hex: "#A855F7")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 136, height: 136)
                        .animation(.spring(response: 0.75, dampingFraction: 0.75), value: sleepProgress)
                    
                    // Inner Ring: Hydration (Cyan)
                    Circle()
                        .stroke(Color(hex: "#00E5FF").opacity(0.15), lineWidth: 10)
                        .frame(width: 102, height: 102)
                    Circle()
                        .trim(from: 0, to: hydrationProgress)
                        .stroke(
                            LinearGradient(
                                colors: [Color(hex: "#00E5FF"), Color(hex: "#00B0FF")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 102, height: 102)
                        .animation(.spring(response: 0.75, dampingFraction: 0.75), value: hydrationProgress)
                    
                    // Center: Live Stress Monkey Mascot
                    VStack(spacing: 2) {
                        MonkeyMascotView(
                            mood: currentMood,
                            size: .mini,
                            animated: true
                        )
                        Text(healthService.currentStressLevel.displayName)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.90))
                            .shadow(color: Color.black.opacity(0.75), radius: 3, x: 0, y: 1.5)
                    }
                }
                .frame(width: 174, height: 174)
                
                // Interactive Metrics Legend Grid (1:1 with Android & iOS RingMetricItem)
                HStack(spacing: 0) {
                    ringMetricItem(
                        label: "STEPS",
                        value: "\(healthService.totalStepsToday.formatted())",
                        color: Color(hex: "#FF9100"),
                        action: { onOpenHub(.health) }
                    )
                    Spacer()
                    ringMetricItem(
                        label: "SLEEP",
                        value: sleepScore > 0 ? "\(sleepScore)%" : "75%",
                        color: Color(hex: "#A855F7"),
                        action: {
                            HealthDataService.shared.activeSubTab = .sleep
                            onOpenHub(.health)
                        }
                    )
                    Spacer()
                    ringMetricItem(
                        label: "WATER",
                        value: "\(Int((hydrationProgress * 100).rounded()))%",
                        color: Color(hex: "#00E5FF"),
                        action: { onOpenHub(.habits) }
                    )
                }
                .padding(.horizontal, 12)
            }
        }
    }
    
    private func ringMetricItem(
        label: String,
        value: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            triggerHaptic()
            action()
        }) {
            VStack(spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(0.5)
                    .foregroundColor(color)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - 3. Monkey Co-Pilot Conversational Studio
    
    private var coPilotConversationalStudio: some View {
        GlassCard(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                // Studio Header
                HStack(alignment: .center) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(ThemeColors.accentCyan)
                        Text("MONKEY CO-PILOT · STUDIO")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(0.8)
                            .foregroundColor(ThemeColors.accentCyan)
                    }
                    
                    Spacer()
                    
                    if activeTurn != nil {
                        Button(action: {
                            triggerHaptic()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                selectedPrefab = nil
                                activeTurn = nil
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 10, weight: .bold))
                                Text("Overview")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(.white.opacity(0.85))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.white.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                        .help("Reset to overview pulse")
                    }
                    
                    Button(action: {
                        triggerHaptic()
                        onOpenBriefing()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "waveform")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(ThemeColors.accentCyan)
                            Text("Full Briefing")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(ThemeColors.accentCyan.opacity(0.15))
                                .overlay(
                                    Capsule().stroke(ThemeColors.accentCyan.opacity(0.35), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Open Smart Daily Briefing")
                }
                
                // Active Narrative / Inline Turn Area
                if let turn = activeTurn {
                    inlineConversationTurnView(turn: turn)
                } else {
                    defaultPulseSynthesisView
                }
                
                // Prefabricated Smart Prompt Chips
                VStack(alignment: .leading, spacing: 8) {
                    Text("INSTANT PREFABRICATED INSIGHTS")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundColor(.white.opacity(0.45))
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(CoPilotPrefabTopic.allCases) { topic in
                                prefabChipButton(topic: topic)
                            }
                        }
                    }
                }
                
                // Free-form Interactive Question Bar
                HStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 12))
                        .foregroundColor(ThemeColors.accentCyan.opacity(0.8))
                    
                    TextField("Ask Co-Pilot about sleep, water, tasks, wealth...", text: $customQueryText)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            submitCustomQuery()
                        }
                    
                    if !customQueryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button(action: submitCustomQuery) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(ThemeColors.accentCyan)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
            }
        }
    }
    
    private var defaultPulseSynthesisView: some View {
        VStack(alignment: .leading, spacing: 10) {
            let synthesis = synthesizeCrossDomainPulse()
            
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(ThemeColors.accentCyan.opacity(0.14))
                        .frame(width: 32, height: 32)
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(ThemeColors.accentCyan)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(synthesis.headline)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text(synthesis.body)
                        .font(.system(size: 12.5, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#0F1E36").opacity(0.85), Color(hex: "#14294D").opacity(0.65)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(ThemeColors.accentCyan.opacity(0.25), lineWidth: 1)
                    )
            )
        }
    }
    
    private func inlineConversationTurnView(turn: CoPilotInlineTurn) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // User Question Bubble
            HStack {
                Spacer(minLength: 24)
                Text(turn.question)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(turn.accentColor.opacity(0.28))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(turn.accentColor.opacity(0.5), lineWidth: 1)
                            )
                    )
            }
            
            // Co-Pilot Structured Answer Bubble
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(turn.accentColor)
                    Text(turn.headline)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                
                Text(turn.body)
                    .font(.system(size: 12.5, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                
                if !turn.highlights.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(turn.highlights, id: \.self) { point in
                            HStack(alignment: .top, spacing: 6) {
                                Circle()
                                    .fill(turn.accentColor)
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 5)
                                Text(point)
                                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                    .foregroundColor(.white.opacity(0.8))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
                
                // Direct Hub Action Portal Button
                Button(action: {
                    triggerHaptic()
                    if turn.targetTab == .health && selectedPrefab == .sleepRecovery {
                        HealthDataService.shared.activeSubTab = .sleep
                    } else if turn.targetTab == .health && selectedPrefab == .stressReset {
                        HealthDataService.shared.activeSubTab = .stress
                    }
                    onOpenHub(turn.targetTab)
                }) {
                    HStack(spacing: 6) {
                        Text(turn.portalTitle)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule().fill(turn.accentColor)
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(turn.accentColor.opacity(0.3), lineWidth: 1)
                    )
            )
        }
    }
    
    private func prefabChipButton(topic: CoPilotPrefabTopic) -> some View {
        let isSelected = (selectedPrefab == topic)
        return Button(action: {
            triggerHaptic()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                if isSelected {
                    selectedPrefab = nil
                    activeTurn = nil
                } else {
                    selectedPrefab = topic
                    activeTurn = buildTurn(for: topic)
                }
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: topic.iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isSelected ? .black : topic.accentColor)
                
                Text(topic.chipLabel)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundColor(isSelected ? .black : .white.opacity(0.9))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isSelected ? topic.accentColor : Color.white.opacity(0.06))
                    .overlay(
                        Capsule()
                            .stroke(isSelected ? topic.accentColor : topic.accentColor.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - 4. Unified Daily Spotlight & Hub Matrix (Replaces old redundant tiles)
    
    private var dailySpotlightMatrix: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("DAILY SPOTLIGHT & HUB PORTALS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.0)
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Text("Click any row to open Hub")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.35))
            }
            .padding(.horizontal, 4)
            
            GlassCard(cornerRadius: 22, padding: 0) {
                VStack(spacing: 0) {
                    // Row 1: Focus Stream & Active Memos -> Tagdos Hub
                    spotlightFocusBand
                    
                    spotlightDivider
                    
                    // Row 2: Circadian Bio-Guidance -> Habits & Health Hubs
                    spotlightCircadianBioBand
                    
                    spotlightDivider
                    
                    // Row 3: Cashflow Momentum & Reserve -> Finances Hub
                    spotlightCashflowBand
                    
                    spotlightDivider
                    
                    // Row 4: Editorial Radar & Sky -> News & Weather Hubs
                    spotlightRadarAndSkyBand
                }
            }
        }
    }
    
    private var spotlightDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 1)
            .padding(.horizontal, 16)
    }
    
    // Band 1: Focus Stream (Tagdos)
    private var spotlightFocusBand: some View {
        let topPills = briefingService.extractTopPills()
        let latestNote = tagdosStore.quickNotes.first
        let noteSnippet = latestNote?.displayTitle.isEmpty == false ? latestNote?.displayTitle : latestNote?.content
        
        return Button(action: {
            triggerHaptic()
            onOpenHub(.tagdos)
        }) {
            HStack(alignment: .center, spacing: 12) {
                spotlightIconBadge(icon: "checklist", color: Color(hex: "#FFB300"))
                
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text("Focus & Mental Stream")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text("TAGDOS")
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .foregroundColor(Color(hex: "#FFB300"))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color(hex: "#FFB300").opacity(0.15)))
                    }
                    
                    if !topPills.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(Array(topPills.prefix(3)), id: \.self) { pillText in
                                Text(pillText)
                                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                    .foregroundColor(ThemeColors.accentCyan)
                                    .lineLimit(1)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule()
                                            .fill(ThemeColors.accentCyan.opacity(0.14))
                                            .overlay(
                                                Capsule().stroke(ThemeColors.accentCyan.opacity(0.35), lineWidth: 1)
                                            )
                                    )
                            }
                        }
                    } else if let snippet = noteSnippet, !snippet.isEmpty {
                        Text("Memo: \"\(snippet)\"")
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(1)
                    } else {
                        Text("All task streams clear • Click to capture new ideas or pills")
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.35))
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // Band 2: Circadian Bio-Guidance (Habits & Health)
    private var spotlightCircadianBioBand: some View {
        let hydroSlot = activeCircadianHydrationSlot
        let smokesToday = habitsService.smokesTotalToday
        
        return HStack(alignment: .center, spacing: 12) {
            spotlightIconBadge(icon: hydroSlot.iconName, color: Color(hex: "#00E5FF"))
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(hydroSlot.title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text(hydroSlot.timeRange)
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "#00E5FF"))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(hex: "#00E5FF").opacity(0.14)))
                }
                
                Text("\(hydroSlot.rationale)")
                    .font(.system(size: 11.5, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    Button(action: {
                        triggerHaptic()
                        onOpenHub(.habits)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "drop.fill")
                                .font(.system(size: 9))
                            Text("+\(hydroSlot.recommendedVolumeMl)ml • Habits ↗")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .foregroundColor(Color(hex: "#00E5FF"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color(hex: "#00E5FF").opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        triggerHaptic()
                        onOpenHub(.health)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "heart.text.square.fill")
                                .font(.system(size: 9))
                            Text(smokesToday == 0 ? "Smoke-Free • Vitals ↗" : "Vitals & Recovery ↗")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .foregroundColor(Color(hex: "#A855F7"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color(hex: "#A855F7").opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }
            
            Spacer(minLength: 0)
        }
        .padding(14)
    }
    
    // Band 3: Cashflow Momentum (Finances)
    private var spotlightCashflowBand: some View {
        let ledger = ledgerStore.parsedLedger
        let inflow = max(ledger.incomingTotal, 0)
        let outflow = max(ledger.outgoingTotal, 0)
        let totalFlow = max(inflow + outflow, 1.0)
        let inflowRatio = CGFloat(inflow / totalFlow)
        let netFlow = inflow - outflow
        
        return Button(action: {
            triggerHaptic()
            onOpenHub(.finances)
        }) {
            HStack(alignment: .center, spacing: 12) {
                spotlightIconBadge(icon: "chart.pie.fill", color: Color(hex: "#10B981"))
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Cashflow Momentum")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Text(netFlow >= 0 ? "Surplus +\(Int(netFlow.rounded()))k Lei" : "Deficit \(Int(netFlow.rounded()))k Lei")
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundColor(netFlow >= 0 ? Color(hex: "#10B981") : Color(hex: "#FF2D55"))
                    }
                    
                    // Proportional Inflow vs Outflow Visual Bar
                    GeometryReader { geo in
                        HStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(hex: "#10B981"))
                                .frame(width: max(geo.size.width * inflowRatio - 2, 12))
                            
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(hex: "#FF2D55"))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 6)
                    
                    HStack {
                        Text("Inflow ratio \(Int((inflowRatio * 100).rounded()))% vs Outflow \(100 - Int((inflowRatio * 100).rounded()))%")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.65))
                        Spacer()
                        Text("Smart Ledger ↗")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "#10B981"))
                    }
                }
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // Band 4: Editorial Radar & Sky (News & Weather)
    private var spotlightRadarAndSkyBand: some View {
        let topArticle = newsService.articles.first
        let temp = Int((weatherService.currentWeather?.main.temp ?? 16.0).rounded())
        let condition = weatherService.currentWeather?.weather.first?.main ?? "Clear"
        let condLower = condition.lowercased()
        let isRainy = condLower.contains("rain") || condLower.contains("drizzle") || condLower.contains("storm")
        let skyAdvice = isRainy ? "\(temp)°C Rain • Umbrella advised" : "\(temp)°C \(condition) • Ideal for outdoor walk"
        
        return HStack(alignment: .center, spacing: 12) {
            spotlightIconBadge(icon: "newspaper.fill", color: Color(hex: "#38BDF8"))
            
            VStack(alignment: .leading, spacing: 5) {
                Button(action: {
                    triggerHaptic()
                    onOpenHub(.news)
                }) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(topArticle?.publicationName ?? "Editorial Radar")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(Color(hex: "#38BDF8"))
                            Text("•")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.4))
                            Text("Read in News Hub ↗")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.55))
                        }
                        
                        Text(topArticle?.title ?? "Curated intelligence feeds ready for deep reading.")
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.95))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    triggerHaptic()
                    onOpenHub(.weather)
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: isRainy ? "umbrella.fill" : "cloud.sun.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#FBBF24"))
                        Text("\(skyAdvice) • Weather ↗")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(hex: "#FBBF24"))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color(hex: "#FBBF24").opacity(0.12)))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            
            Spacer(minLength: 0)
        }
        .padding(14)
    }
    
    private func spotlightIconBadge(icon: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(color.opacity(0.35), lineWidth: 1)
                )
                .frame(width: 36, height: 36)
            
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(color)
        }
    }
    
    // MARK: - Deterministic Cross-Domain Intelligence Generators
    
    private func synthesizeCrossDomainPulse() -> (headline: String, body: String) {
        let hydroSlot = activeCircadianHydrationSlot
        let waterMl = Int(habitsService.waterTotalToday)
        let waterGoal = Int(habitsService.waterGoal)
        let steps = healthService.totalStepsToday
        let topPills = briefingService.extractTopPills()
        let stressName = healthService.currentStressLevel.displayName
        
        let headline = "\(slot.displayName) • \(stressName) Autonomic Tone"
        
        let liveSleepScore = healthService.primarySleepSession?.sleepScore
        let briefSleepScore = briefingService.activeBriefing?.metrics.sleepScore
        let isSleepConsistent = (liveSleepScore == briefSleepScore)
        
        if isSleepConsistent, let record = briefingService.activeBriefing {
            let parts = [
                record.narrative.healthText,
                record.narrative.stressText,
                record.narrative.tagdosText
            ].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if !parts.isEmpty {
                return (headline, parts.joined(separator: " "))
            }
        }
        
        var sleepPart = ""
        if let session = healthService.primarySleepSession {
            let sleepTime = session.totalAsleepFormatted
            let score = session.sleepScore
            if score >= 80 {
                sleepPart = "Great recovery with \(sleepTime) asleep (Score \(score)%). Ready for a focused, high-energy day."
            } else {
                sleepPart = "Logged \(sleepTime) asleep (Score \(score)%). Maintain steady energy and stay hydrated."
            }
        }
        
        let focusPart = topPills.isEmpty
            ? "Tagdos streams have no urgent blockers."
            : "Priority focus: \(topPills.prefix(3).joined(separator: ", "))."
        
        let hydroPart = "You're in the \(hydroSlot.title) window (\(waterMl)/\(waterGoal) ml logged, \(steps) steps)."
        let body = [sleepPart, hydroPart, focusPart].filter { !$0.isEmpty }.joined(separator: " ")
        return (headline, body)
    }
    
    private func buildTurn(for topic: CoPilotPrefabTopic) -> CoPilotInlineTurn {
        switch topic {
        case .sleepRecovery:
            if let session = healthService.primarySleepSession {
                let analysis = SleepAnalysisEngine.shared.analyze(
                    session: session,
                    nocturnalRestingBpm: healthService.restingBpm > 0 ? healthService.restingBpm : nil,
                    nocturnalHrvMs: nil
                )
                let tipStrings = analysis.tips.map { "\($0.title): \($0.advice)" }
                return CoPilotInlineTurn(
                    question: topic.fullQuestion,
                    headline: "\(analysis.verdict.status.displayName) • Readiness \(analysis.verdict.readinessScore)%",
                    body: analysis.verdict.narrative,
                    highlights: [
                        "Physical Repair: \(analysis.verdict.physicalRepairRating) • Cognitive Restore: \(analysis.verdict.cognitiveRestoreRating)",
                        tipStrings.first ?? "Keep bedroom temperature between 18–20°C for slow-wave NREM sleep."
                    ],
                    targetTab: .health,
                    portalTitle: topic.portalButtonTitle,
                    accentColor: topic.accentColor
                )
            } else {
                return CoPilotInlineTurn(
                    question: topic.fullQuestion,
                    headline: "Sleep Architecture & Circadian Readiness",
                    body: "No nocturnal session synced yet for today. To maximize slow-wave Deep Sleep and REM consolidation tonight, anchor your circadian clock with morning daylight and cool your bedroom to 18–20°C.",
                    highlights: [
                        "Circadian Anchor: 15–20 min outdoor daylight boosts evening melatonin onset.",
                        "Thermoregulation: A 1°C core temperature drop triggers deep NREM stages."
                    ],
                    targetTab: .health,
                    portalTitle: topic.portalButtonTitle,
                    accentColor: topic.accentColor
                )
            }
            
        case .circadianHydration:
            let hydroSlot = activeCircadianHydrationSlot
            let waterMl = Int(habitsService.waterTotalToday)
            let waterGoal = Int(habitsService.waterGoal)
            let smokes = habitsService.smokesTotalToday
            let cravingStep = HabitsGuidance.fourDsCravingProtocol.first!
            return CoPilotInlineTurn(
                question: topic.fullQuestion,
                headline: "\(hydroSlot.title) (\(hydroSlot.timeRange))",
                body: "\(hydroSlot.rationale) You have logged \(waterMl) / \(waterGoal) ml today (\(Int((hydrationProgress * 100).rounded()))%).",
                highlights: [
                    "Recommended Intake Now: +\(hydroSlot.recommendedVolumeMl) ml pure or electrolyte water.",
                    smokes == 0
                        ? "Smoke-Free Streak: 0 cigarettes logged today — bronchial and vascular recovery active."
                        : "4D Craving Protocol (\(cravingStep.action)): \(cravingStep.explanation)"
                ],
                targetTab: .habits,
                portalTitle: topic.portalButtonTitle,
                accentColor: topic.accentColor
            )
            
        case .urgentFocus:
            let topPills = briefingService.extractTopPills()
            let streamCount = tagdosStore.streams.count
            let notesCount = tagdosStore.quickNotes.count
            let latestNote = tagdosStore.quickNotes.first
            let notePreview = latestNote?.displayTitle.isEmpty == false ? latestNote!.displayTitle : (latestNote?.content ?? "No active quick memos")
            
            let bodyText = topPills.isEmpty
                ? "All \(streamCount) Tagdos streams are clear of urgent blockers. You have \(notesCount) quick notes stored."
                : "Across your \(streamCount) active streams, these driving tasks require your immediate execution:"
            
            var highlights = topPills.prefix(3).map { "Priority Pill: \($0)" }
            highlights.append("Latest Memo: \"\(String(notePreview.prefix(70)))\"")
            
            return CoPilotInlineTurn(
                question: topic.fullQuestion,
                headline: "Tagdos Execution & Mental Stream",
                body: bodyText,
                highlights: highlights,
                targetTab: .tagdos,
                portalTitle: topic.portalButtonTitle,
                accentColor: topic.accentColor
            )
            
        case .stressReset:
            let score = healthService.currentStressScore
            let level = healthService.currentStressLevel
            let bpmText = displayBpm > 0 ? "\(displayBpm) BPM" : "baseline"
            return CoPilotInlineTurn(
                question: topic.fullQuestion,
                headline: "Autonomic Balance: \(level.displayName) (\(score)/100)",
                body: "Your sympathetic/parasympathetic balance is currently \(level.displayName.lowercased()) with heart rate at \(bpmText). Use a 60-second vagal reset to elevate HRV and mental clarity:",
                highlights: [
                    "Physiological Sigh: Double inhale through the nose, long slow exhale through the mouth (3x).",
                    "Box Breathing: Inhale 4s → Hold 4s → Exhale 4s → Hold 4s for parasympathetic calm."
                ],
                targetTab: .health,
                portalTitle: topic.portalButtonTitle,
                accentColor: topic.accentColor
            )
            
        case .wealthPulse:
            let ledger = ledgerStore.parsedLedger
            let netFlow = ledger.incomingTotal - ledger.outgoingTotal
            return CoPilotInlineTurn(
                question: topic.fullQuestion,
                headline: "Net Worth \(ledger.formattedNetWorth) Lei • Flow Analysis",
                body: "Your Smart Ledger tracks \(Int(ledger.incomingTotal.rounded()))k Lei incoming against \(Int(ledger.outgoingTotal.rounded()))k Lei outgoing, with liquid deposits at \(Int(ledger.depositTotal.rounded()))k Lei.",
                highlights: [
                    netFlow >= 0
                        ? "Monthly Balance: Positive net flow of +\(Int(netFlow.rounded()))k Lei."
                        : "Monthly Balance: Outflow exceeds inflow by \(Int(abs(netFlow).rounded()))k Lei — review discretionary items.",
                    "EUR Equivalent: ~\(Int(ledger.netWorthEUR.rounded()).formatted()) € total portfolio value."
                ],
                targetTab: .finances,
                portalTitle: topic.portalButtonTitle,
                accentColor: topic.accentColor
            )

        case .tonightsSky:
            let now = Date()
            let lat = weatherService.currentWeather?.coord?.lat ?? 44.4268
            let lon = weatherService.currentWeather?.coord?.lon ?? 26.1025
            let obs = (latitude: lat, longitude: lon)
            let obs3 = (latitude: lat, longitude: lon, elevation: 50.0)
            let moon = AstronomyService.shared.moonPhase(at: now, observer: obs)
            let bortle = CosmosCatalogService.shared.bortleClass(latitude: lat, longitude: lon)
            let cond = CosmosLiveService.shared.stargazingConditions ?? AstronomyService.shared.evaluateStargazingConditions(
                observer: obs,
                date: now,
                cloudCoverTotal: weatherService.currentWeather?.clouds?.all,
                cloudCoverLow: nil,
                cloudCoverMid: nil,
                cloudCoverHigh: nil,
                bortleClass: bortle
            )
            let visiblePlanets = [CelestialBody.venus, .jupiter, .saturn, .mars, .mercury, .uranus, .neptune]
                .filter { AstronomyService.shared.coordinates(of: $0, for: obs3, at: now).altitudeDegrees > 0.0 }
                .map(\.displayName)
            let planetsLine = visiblePlanets.isEmpty
                ? "Solar System planets are currently below the local horizon — scrub the Time Machine to tonight's dark window."
                : "Above horizon now: \(visiblePlanets.joined(separator: ", "))."
            let issLine: String = {
                if let pass = CosmosLiveService.shared.upcomingIssPasses.first {
                    let f = DateFormatter()
                    f.dateFormat = "HH:mm"
                    return "Next sunlit ISS pass: \(f.string(from: pass.startTime)) peaking at \(Int(pass.maxAltitudeDegrees.rounded()))°."
                }
                return "Best Dark Window: \(cond.bestWindowDescription ?? "Calculated at astronomical dusk") (NELM \(String(format: "%.1f", cond.limitingMagnitude)))."
            }()
            return CoPilotInlineTurn(
                question: topic.fullQuestion,
                headline: "Sky Score \(cond.score)/100 (\(cond.quality.displayName)) • Bortle \(cond.bortleClass)",
                body: "\(cond.narrativeAdvice) Moon is in \(moon.quarter.displayName) (\(Int((moon.illuminatedFraction * 100.0).rounded()))% illuminated).",
                highlights: [planetsLine, issLine],
                targetTab: .cosmos,
                portalTitle: topic.portalButtonTitle,
                accentColor: topic.accentColor
            )
        }
    }
    
    private func submitCustomQuery() {
        let trimmed = customQueryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        triggerHaptic()
        customQueryText = ""
        
        let q = trimmed.lowercased()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            if q.contains("sky") || q.contains("star") || q.contains("cosmos") || q.contains("planet") || q.contains("moon") || q.contains("iss") || q.contains("aurora") {
                selectedPrefab = .tonightsSky
                let turn = buildTurn(for: .tonightsSky)
                activeTurn = CoPilotInlineTurn(
                    question: trimmed,
                    headline: turn.headline,
                    body: turn.body,
                    highlights: turn.highlights,
                    targetTab: turn.targetTab,
                    portalTitle: turn.portalTitle,
                    accentColor: turn.accentColor
                )
            } else if q.contains("sleep") || q.contains("somn") || q.contains("rem") || q.contains("deep") || q.contains("obosit") {
                selectedPrefab = .sleepRecovery
                let turn = buildTurn(for: .sleepRecovery)
                activeTurn = CoPilotInlineTurn(
                    question: trimmed,
                    headline: turn.headline,
                    body: turn.body,
                    highlights: turn.highlights,
                    targetTab: turn.targetTab,
                    portalTitle: turn.portalTitle,
                    accentColor: turn.accentColor
                )
            } else if q.contains("water") || q.contains("apa") || q.contains("apă") || q.contains("hidr") || q.contains("fum") || q.contains("tig") || q.contains("crav") {
                selectedPrefab = .circadianHydration
                let turn = buildTurn(for: .circadianHydration)
                activeTurn = CoPilotInlineTurn(
                    question: trimmed,
                    headline: turn.headline,
                    body: turn.body,
                    highlights: turn.highlights,
                    targetTab: turn.targetTab,
                    portalTitle: turn.portalTitle,
                    accentColor: turn.accentColor
                )
            } else if q.contains("tag") || q.contains("task") || q.contains("urgent") || q.contains("not") || q.contains("memo") || q.contains("focus") {
                selectedPrefab = .urgentFocus
                let turn = buildTurn(for: .urgentFocus)
                activeTurn = CoPilotInlineTurn(
                    question: trimmed,
                    headline: turn.headline,
                    body: turn.body,
                    highlights: turn.highlights,
                    targetTab: turn.targetTab,
                    portalTitle: turn.portalTitle,
                    accentColor: turn.accentColor
                )
            } else if q.contains("bani") || q.contains("finan") || q.contains("lei") || q.contains("eur") || q.contains("ledger") || q.contains("cash") || q.contains("worth") {
                selectedPrefab = .wealthPulse
                let turn = buildTurn(for: .wealthPulse)
                activeTurn = CoPilotInlineTurn(
                    question: trimmed,
                    headline: turn.headline,
                    body: turn.body,
                    highlights: turn.highlights,
                    targetTab: turn.targetTab,
                    portalTitle: turn.portalTitle,
                    accentColor: turn.accentColor
                )
            } else if q.contains("stres") || q.contains("calm") || q.contains("resp") || q.contains("breath") || q.contains("puls") || q.contains("bpm") {
                selectedPrefab = .stressReset
                let turn = buildTurn(for: .stressReset)
                activeTurn = CoPilotInlineTurn(
                    question: trimmed,
                    headline: turn.headline,
                    body: turn.body,
                    highlights: turn.highlights,
                    targetTab: turn.targetTab,
                    portalTitle: turn.portalTitle,
                    accentColor: turn.accentColor
                )
            } else {
                selectedPrefab = nil
                let pulse = synthesizeCrossDomainPulse()
                activeTurn = CoPilotInlineTurn(
                    question: trimmed,
                    headline: "Integrated Daily Co-Pilot Synthesis",
                    body: pulse.body,
                    highlights: [
                        "Hydration Window: \(activeCircadianHydrationSlot.title) (+\(activeCircadianHydrationSlot.recommendedVolumeMl) ml)",
                        "Net Worth: \(ledgerStore.parsedLedger.formattedNetWorth) Lei • Steps: \(healthService.totalStepsToday)"
                    ],
                    targetTab: .health,
                    portalTitle: "Explore Health & Vitals Hub",
                    accentColor: ThemeColors.accentCyan
                )
            }
        }
    }
}
