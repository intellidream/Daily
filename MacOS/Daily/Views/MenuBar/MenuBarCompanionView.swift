import SwiftUI
import DailyCore
import AppKit

public enum TagdosEntryMode: String, CaseIterable, Identifiable {
    case note = "Quick Note"
    case tagdo = "TagDo"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .note: return "square.and.pencil"
        case .tagdo: return "checklist"
        }
    }
}

public struct MenuBarCompanionView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @ObservedObject private var habitsService = HabitsService.shared
    @ObservedObject private var healthService = HealthDataService.shared
    @ObservedObject private var weatherService = WeatherService.shared
    @ObservedObject private var tagdosStore = TagdosStore.shared
    
    @State private var tagdosMode: TagdosEntryMode = .note
    @State private var quickEntryText: String = ""
    @State private var saveStatusMessage: String? = nil
    @State private var isExitHovered: Bool = false
    
    public static let standardCompanionHeight: CGFloat = 586
    
    @State private var screenAvailableHeight: CGFloat = {
        let screen = NSScreen.main ?? NSScreen.screens.first
        return screen?.visibleFrame.height ?? 800
    }()
    
    private var optimalHeight: CGFloat {
        // Safe headroom: leave margin for menu bar and dock so window never overflows any screen resolution
        let maxAllowed = max(380, screenAvailableHeight - 50)
        return min(Self.standardCompanionHeight, maxAllowed)
    }
    
    public var onOpenFullApp: ((NavigationTab?) -> Void)?
    public var onExitApp: (() -> Void)?
    
    public init(
        onOpenFullApp: ((NavigationTab?) -> Void)? = nil,
        onExitApp: (() -> Void)? = nil
    ) {
        self.onOpenFullApp = onOpenFullApp
        self.onExitApp = onExitApp
    }
    
    private func triggerHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
    
    private func openFullApp(_ tab: NavigationTab? = nil) {
        triggerHaptic()
        openWindow(id: "main")
        dismissWindow(id: "glance")
        MacOSWindowManager.shared.closeGlanceWindow()
        onOpenFullApp?(tab)
    }
    
    public var body: some View {
        LiquidGlassBackground {
            VStack(spacing: 10) {
                // Top Header Bar
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [ThemeColors.accentCyan, ThemeColors.accentBlue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("DayOne Glance")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button {
                        openFullApp(nil)
                    } label: {
                        HStack(spacing: 4) {
                            Text("Full App")
                                .font(.system(size: 11, weight: .semibold))
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(ThemeColors.accentCyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(ThemeColors.accentCyan.opacity(0.12), in: Capsule())
                        .overlay {
                            Capsule().strokeBorder(ThemeColors.accentCyan.opacity(0.3), lineWidth: 1)
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Open Full DayOne Window (⌘1)")
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 10) {
                        // 1. Weather & Vitals Quick Row
                        weatherAndVitalsRow
                        
                        // 2. Hydration Tracker Quick Log (Bubbles)
                        waterIntakeCard
                        
                        // 3. Smokes & Tobacco Tracker (Smokes)
                        smokesIntakeCard
                        
                        // 4. TagDoS Quick Entry (Notes & Tasks)
                        tagdosQuickEntryCard
                        
                        // 5. Quick Jump Navigation Grid
                        quickNavigationGrid
                        
                        // Subtle Divider (matching WinUI Taskbar Glance)
                        Rectangle()
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 1)
                            .padding(.top, 3)
                            .padding(.bottom, 2)
                        
                        // 6. Exit App Button (matching WinUI Taskbar Glance)
                        exitAppButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(width: 360, height: optimalHeight)
        .onAppear {
            updateScreenMetrics()
            MacOSWindowManager.shared.openWindowAction = openWindow
            MacOSWindowManager.shared.dismissWindowAction = dismissWindow
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            updateScreenMetrics()
        }
    }
    
    private func updateScreenMetrics() {
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
        if let vf = screen?.visibleFrame {
            screenAvailableHeight = vf.height
        }
    }
    
    // MARK: - 1. Weather & Vitals Row
    @ViewBuilder
    private var weatherAndVitalsRow: some View {
        HStack(spacing: 10) {
            // Weather Card
            Button {
                openFullApp(.weather)
            } label: {
                GlassCard(cornerRadius: 14, padding: 10) {
                    HStack(spacing: 8) {
                        let icon = WeatherConditionHelper.sfSymbol(for: weatherService.currentWeather?.weather.first?.icon ?? "")
                        Image(systemName: icon)
                            .font(.system(size: 22, weight: .medium))
                            .symbolRenderingMode(.multicolor)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(weatherService.currentWeather != nil ? "\(Int(round(weatherService.currentWeather!.main.temp)))°" : "--°")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            
                            Text(weatherService.currentLocationName.isEmpty ? "Weather" : weatherService.currentLocationName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(ThemeColors.fgMutedDark)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            
            // Health Vitals Card (Consumer Mode)
            Button {
                openFullApp(.health)
            } label: {
                GlassCard(cornerRadius: 14, padding: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 20))
                            .foregroundColor(ThemeColors.accentPink)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 3) {
                                Text(healthService.latestBpm != nil ? "\(Int(round(healthService.latestBpm!)))" : (healthService.restingBpm > 0 ? "\(Int(round(healthService.restingBpm)))" : "--"))
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                Text("bpm")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                            }
                            
                            HStack(spacing: 2) {
                                Image(systemName: "figure.walk")
                                    .font(.system(size: 9))
                                Text("\(healthService.totalStepsToday)")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(ThemeColors.accentCyan)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - 2. Hydration Card (Bubbles: 100 Water, 150 Coffee, 300 Water)
    @ViewBuilder
    private var waterIntakeCard: some View {
        GlassCard(cornerRadius: 14, padding: 12) {
            VStack(spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "drop.fill")
                            .foregroundColor(ThemeColors.accentCyan)
                        Text("Water & Hydration")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    Text("\(Int(round(habitsService.waterTotalToday))) / \(Int(round(habitsService.waterGoal))) ml")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(ThemeColors.accentCyan)
                }
                
                // Progress Bar
                GeometryReader { geo in
                    let progress = min(1.0, habitsService.waterProgressPercent)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 7)
                        
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [ThemeColors.accentBlue, ThemeColors.accentCyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(4, geo.size.width * CGFloat(progress)), height: 7)
                    }
                }
                .frame(height: 7)
                
                // Quick Log Buttons (Parity with iOS & Widgets: 100 Water, 150 Coffee, 300 Water)
                HStack(spacing: 8) {
                    // +100 Water
                    Button {
                        triggerHaptic()
                        habitsService.logWater(amountMl: 100, drink: "Water")
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "drop")
                                .font(.system(size: 11))
                            Text("100")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(ThemeColors.accentCyan)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(ThemeColors.accentCyan.opacity(0.14), in: Capsule())
                        .overlay(Capsule().strokeBorder(ThemeColors.accentCyan.opacity(0.28), lineWidth: 1))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    
                    // +150 Coffee
                    Button {
                        triggerHaptic()
                        habitsService.logWater(amountMl: 150, drink: "Coffee")
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "cup.and.saucer.fill")
                                .font(.system(size: 10))
                            Text("150")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(Color(hex: "#F59E0B"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(Color(hex: "#F59E0B").opacity(0.15), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color(hex: "#F59E0B").opacity(0.3), lineWidth: 1))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    
                    // +300 Water
                    Button {
                        triggerHaptic()
                        habitsService.logWater(amountMl: 300, drink: "Water")
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "drop.fill")
                                .font(.system(size: 11))
                            Text("300")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(ThemeColors.accentCyan)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(ThemeColors.accentCyan.opacity(0.14), in: Capsule())
                        .overlay(Capsule().strokeBorder(ThemeColors.accentCyan.opacity(0.28), lineWidth: 1))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - 3. Smokes & Tobacco Card (Dedicated Tile: Cig & Heat)
    @ViewBuilder
    private var smokesIntakeCard: some View {
        GlassCard(cornerRadius: 14, padding: 12) {
            VStack(spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .foregroundColor(Color(hex: "#EF4444"))
                        Text("Smokes")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    let total = habitsService.smokesTotalToday
                    let base = habitsService.smokesBaselineCount
                    HStack(spacing: 2) {
                        Text("\(total)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(total > base && base > 0 ? Color(hex: "#FF3B30") : Color(hex: "#EF4444"))
                        Text("/ \(base)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(Color.white.opacity(0.6))
                    }
                }
                
                // Progress Bar
                GeometryReader { geo in
                    let base = max(1, habitsService.smokesBaselineCount)
                    let progress = min(1.0, Double(habitsService.smokesTotalToday) / Double(base))
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 7)
                        
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "#3B82F6"), Color(hex: "#EF4444")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(4, geo.size.width * CGFloat(progress)), height: 7)
                    }
                }
                .frame(height: 7)
                
                // Quick Action Buttons (Parity with iOS & Widgets: Cig & Heat)
                HStack(spacing: 8) {
                    // +1 Cig (Combustible Cigarette)
                    Button {
                        triggerHaptic()
                        habitsService.logSmoke(preset: .cigarette)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 10))
                            Text("Cig")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(Color(hex: "#EF4444"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(Color(hex: "#EF4444").opacity(0.16), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color(hex: "#EF4444").opacity(0.32), lineWidth: 1))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Log 1 Cigarette")
                    
                    // +1 Heat (Heated Tobacco)
                    Button {
                        triggerHaptic()
                        habitsService.logSmoke(preset: .heated)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 10))
                            Text("Heat")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(Color(hex: "#3B82F6"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(Color(hex: "#3B82F6").opacity(0.16), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color(hex: "#3B82F6").opacity(0.32), lineWidth: 1))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Log 1 Heated Tobacco Stick")
                }
            }
        }
    }
    
    // MARK: - 4. TagDoS Quick Entry (Dual Mode: Note vs TagDo)
    @ViewBuilder
    private var tagdosQuickEntryCard: some View {
        GlassCard(cornerRadius: 14, padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "checklist")
                        .foregroundColor(ThemeColors.accentGreen)
                    Text("TagDoS Quick Entry")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    if let status = saveStatusMessage {
                        Text(status)
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundColor(ThemeColors.accentGreen)
                            .transition(.opacity)
                    }
                }
                
                // Mode Toggle: Note vs TagDo
                HStack(spacing: 6) {
                    ForEach(TagdosEntryMode.allCases) { mode in
                        Button {
                            triggerHaptic()
                            withAnimation(.easeInOut(duration: 0.15)) {
                                tagdosMode = mode
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: mode.iconName)
                                    .font(.system(size: 10))
                                Text(mode.rawValue)
                                    .font(.system(size: 11, weight: tagdosMode == mode ? .bold : .medium))
                            }
                            .foregroundColor(tagdosMode == mode ? .white : Color.white.opacity(0.6))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(tagdosMode == mode ? ThemeColors.accentGreen.opacity(0.25) : Color.white.opacity(0.06))
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(tagdosMode == mode ? ThemeColors.accentGreen.opacity(0.5) : Color.clear, lineWidth: 1)
                            )
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Spacer()
                    
                    Button {
                        triggerHaptic()
                        onOpenFullApp?(.tagdos)
                    } label: {
                        HStack(spacing: 2) {
                            Text("Hub (⌘3)")
                                .font(.system(size: 10, weight: .medium))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 8))
                        }
                        .foregroundColor(ThemeColors.accentGreen)
                    }
                    .buttonStyle(.plain)
                    .help("Open TagDoS in full window")
                }
                
                // Input TextField + Submit Button
                HStack(spacing: 8) {
                    TextField(
                        tagdosMode == .note ? "Add note (saved to TagDoS Notes tab)..." : "Add mental tag (e.g. BUY/GROC, CALL/MOM)...",
                        text: $quickEntryText
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .onSubmit {
                        submitTagdosEntry()
                    }
                    
                    Button {
                        submitTagdosEntry()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(quickEntryText.trimmingCharacters(in: .whitespaces).isEmpty ? Color.white.opacity(0.2) : ThemeColors.accentGreen)
                    }
                    .buttonStyle(.plain)
                    .disabled(quickEntryText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                
                // Context helper text explaining target destination
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 9))
                    Text(tagdosMode == .note ? "Saves to TagDoS Notes tab (accessible in ⌘3 -> Notes)" : "Adds as an active task pill to TagDoS Stream 1 (⌘3)")
                        .font(.system(size: 9.5))
                }
                .foregroundColor(ThemeColors.fgMutedDark)
            }
        }
    }
    
    // MARK: - 5. Quick Jump Navigation Grid
    @ViewBuilder
    private var quickNavigationGrid: some View {
        HStack(spacing: 8) {
            quickNavButton(title: "Money", icon: "wallet.bifold.fill", color: ThemeColors.accentGreen, tab: .finances)
            quickNavButton(title: "Health", icon: "heart.fill", color: ThemeColors.accentPink, tab: .health)
            quickNavButton(title: "Habits", icon: "drop.fill", color: ThemeColors.accentCyan, tab: .habits)
            quickNavButton(title: "TagDoS", icon: "checklist", color: ThemeColors.accentOrange, tab: .tagdos)
            quickNavButton(title: "News", icon: "newspaper.fill", color: ThemeColors.accentBlue, tab: .news)
        }
        .padding(.top, 4)
    }
    
    @ViewBuilder
    private func quickNavButton(title: String, icon: String, color: Color, tab: NavigationTab) -> some View {
        Button {
            openFullApp(tab)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - 6. Exit App Button
    @ViewBuilder
    private var exitAppButton: some View {
        Button {
            triggerHaptic()
            if let onExitApp = onExitApp {
                onExitApp()
            } else {
                NSApplication.shared.terminate(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    exit(0)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .semibold))
                Text("Exit DayOne")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isExitHovered ? Color.red.opacity(0.95) : ThemeColors.fgMutedDark)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isExitHovered ? Color.red.opacity(0.12) : Color.white.opacity(0.04))
            )
            .overlay {
                if isExitHovered {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.red.opacity(0.25), lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isExitHovered = hovering
        }
        .help("Completely quit DayOne (⌘Q)")
    }
    
    // MARK: - TagDoS Submission Logic
    private func submitTagdosEntry() {
        let trimmed = quickEntryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        triggerHaptic()
        
        switch tagdosMode {
        case .note:
            tagdosStore.createQuickNote(title: "Quick Memo", content: trimmed)
            withAnimation {
                saveStatusMessage = "✓ Saved to Notes!"
            }
        case .tagdo:
            if let firstStream = tagdosStore.streams.first {
                tagdosStore.addPill(streamId: firstStream.id, clusterIndex: 0, text: trimmed)
                withAnimation {
                    saveStatusMessage = "✓ Added to Stream 1!"
                }
            } else {
                tagdosStore.createQuickNote(title: "Quick Memo", content: trimmed)
                withAnimation {
                    saveStatusMessage = "✓ Saved to Notes!"
                }
            }
        }
        
        quickEntryText = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                saveStatusMessage = nil
            }
        }
    }
}
