import SwiftUI
import DailyCore

/// Master Health & Vitals screen integrating multi-device telemetry, clinical sleep studio, and evolution trends.
public struct HealthMainView: View {
    @ObservedObject private var healthService = HealthDataService.shared
    @State private var dragStartSubTab: HealthSubTab? = nil
    @State private var hasSwitchedSubTabInDrag: Bool = false
    @State private var showingDatePicker = false
    public var onNavigateBack: (() -> Void)? = nil
    
    private func triggerHaptic() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
    
    public init(onNavigateBack: (() -> Void)? = nil) {
        self.onNavigateBack = onNavigateBack
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-healthSubTabSleep") || args.contains("-testSleepStudio") {
            healthService.activeSubTab = .sleep
        } else if args.contains("-healthSubTabStress") {
            healthService.activeSubTab = .stress
        } else if args.contains("-healthSubTabTrends") {
            healthService.activeSubTab = .trends
        } else if args.contains("-healthSubTabVitals") {
            healthService.activeSubTab = .vitals
        }
        if args.contains("-healthPrevDay") {
            healthService.prevDay()
        }
    }
    
    public var body: some View {
        LiquidGlassBackground {
            VStack(spacing: 0) {
                // Top Header Bar: Back Button, Centered Date Navigator & Device Selector Menu
                headerBar
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 12)
                
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Sub-Tab Switcher (Overview, Sleep, Stress, Vitals, Trends)
                        subTabSwitcher
                        
                        // Main Content Based on Active Sub-Tab
                        switch healthService.activeSubTab {
                        case .overview:
                            overviewSection
                        case .sleep:
                            SleepStudioView()
                        case .stress:
                            StressStudioView()
                        case .vitals:
                            vitalsSection
                        case .trends:
                            HealthTrendsView()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 110) // Room for FloatingGlassCapsule
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 25, coordinateSpace: .local)
                        .onEnded { value in
                            let dx = value.translation.width
                            let dy = value.translation.height
                            let startX = value.startLocation.x
                            guard startX > 60 else { return } // Preserve edge-swipe back to Dashboard
                            guard abs(dx) > abs(dy) * 1.8 && abs(dx) > 55 else { return }
                            
                            let tabs = HealthSubTab.allCases
                            guard let currentIndex = tabs.firstIndex(of: healthService.activeSubTab) else { return }
                            if dx > 0 && currentIndex < tabs.count - 1 {
                                triggerHaptic()
                                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                    healthService.activeSubTab = tabs[currentIndex + 1]
                                }
                            } else if dx < 0 && currentIndex > 0 {
                                triggerHaptic()
                                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                    healthService.activeSubTab = tabs[currentIndex - 1]
                                }
                            }
                        }
                )
                .refreshable {
                    await healthService.loadDataForSelectedDate(forceRefresh: true)
                }
                .task {
                    await healthService.loadDataForSelectedDate()
                }
                .sheet(isPresented: $showingDatePicker) {
                    NavigationStack {
                        LiquidGlassBackground {
                            VStack {
                                DatePicker("Select Date", selection: Binding(
                                    get: { healthService.selectedDate },
                                    set: { healthService.selectDate($0) }
                                ), displayedComponents: [.date])
                                .datePickerStyle(.graphical)
                                .padding()
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .padding(20)
                                
                                Button("Confirm") {
                                    showingDatePicker = false
                                }
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 30)
                                .padding(.vertical, 12)
                                .background(ThemeColors.accentCyan)
                                .clipShape(Capsule())
                                
                                Spacer()
                            }
                            .padding(.top, 20)
                            .navigationTitle("Select Date")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button("Done") {
                                        showingDatePicker = false
                                    }
                                    .foregroundColor(.white)
                                }
                            }
                        }
                    }
                    .presentationDetents([.medium])
                }
            }
        }
    }
    
    // MARK: - Header Bar
    
    private var headerBar: some View {
        HStack(alignment: .center, spacing: 10) {
            // Back Button
            Button {
                onNavigateBack?()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(Color.white.opacity(0.08))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Centered Date Navigator
            dayNavigatorBar
            
            Spacer()
            
            // Top Right Device/Source Selector Button with Dropdown Menu
            deviceSelectorMenu
        }
    }
    
    // MARK: - Device Selector Menu
    
    private var deviceSelectorMenu: some View {
        Menu {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    healthService.setDeviceFilter(nil as DeviceSource?)
                }
            } label: {
                HStack {
                    Text("All Devices")
                    if healthService.selectedDeviceSource == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }
            
            Divider()
            
            ForEach(healthService.availableSources) { source in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        healthService.setDeviceFilter(source)
                    }
                } label: {
                    HStack {
                        Label(source.displayName, systemImage: source.systemImage)
                        if healthService.selectedDeviceSource == source {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            let isFiltered = healthService.selectedDeviceSource != nil
            let iconName = healthService.selectedDeviceSource?.systemImage ?? "applewatch.radiowaves.left.and.right"
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isFiltered ? ThemeColors.accentCyan : .white.opacity(0.85))
                .frame(width: 36, height: 36)
                .background(
                    Circle().fill(isFiltered ? ThemeColors.accentCyan.opacity(0.2) : Color.white.opacity(0.08))
                        .overlay(Circle().strokeBorder(isFiltered ? ThemeColors.accentCyan.opacity(0.6) : Color.white.opacity(0.12), lineWidth: 1))
                )
                .shadow(color: isFiltered ? ThemeColors.accentCyan.opacity(0.3) : .clear, radius: 4)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Day Navigator Bar
    
    private var dayNavigatorBar: some View {
        HStack(spacing: 8) {
            // Previous Day Button
            Button {
                healthService.goToPreviousDay()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            
            // Calendar Button with Icon and Date Title
            Button {
                showingDatePicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(ThemeColors.accentCyan)
                    
                    Text(healthService.formattedDateTitle)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            
            // Jump to Today or Next Day Button
            if !healthService.isToday {
                Button {
                    healthService.goToToday()
                } label: {
                    Text("Today")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(ThemeColors.accentCyan)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(ThemeColors.accentCyan.opacity(0.18)))
                }
                .buttonStyle(.plain)
                
                Button {
                    healthService.goToNextDay()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.2))
                    .frame(width: 26, height: 26)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.06))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        )
    }
    
    // MARK: - Sub-Tab Switcher
    
    private var subTabSwitcher: some View {
        HStack(spacing: 6) {
            ForEach(HealthSubTab.allCases) { tab in
                let isSelected = healthService.activeSubTab == tab
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        healthService.activeSubTab = tab
                    }
                } label: {
                    Text(tab.shortTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.white.opacity(0.12) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.05))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    if dragStartSubTab == nil {
                        dragStartSubTab = healthService.activeSubTab
                        hasSwitchedSubTabInDrag = false
                    }
                    guard !hasSwitchedSubTabInDrag else { return }
                    
                    let tabs = HealthSubTab.allCases
                    guard let start = dragStartSubTab, let startIdx = tabs.firstIndex(of: start) else { return }
                    
                    let dx = value.translation.width
                    // Dragging right -> moves to tab on the right (+1)
                    if dx > 35 && startIdx < tabs.count - 1 {
                        hasSwitchedSubTabInDrag = true
                        triggerHaptic()
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                            healthService.activeSubTab = tabs[startIdx + 1]
                        }
                    // Dragging left -> moves to tab on the left (-1)
                    } else if dx < -35 && startIdx > 0 {
                        hasSwitchedSubTabInDrag = true
                        triggerHaptic()
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                            healthService.activeSubTab = tabs[startIdx - 1]
                        }
                    }
                }
                .onEnded { _ in
                    dragStartSubTab = nil
                    hasSwitchedSubTabInDrag = false
                }
        )
    }
    
    // MARK: - Overview Section
    
    private var overviewSection: some View {
        VStack(spacing: 16) {
            // Activity Hero Rings & Live Pulse
            activityHeroCard
            
            // Hourly Step Cadence
            HourlyStepsHistogramView()
            
            // Sleep Summary Preview Card (Tap opens Sleep Studio)
            if let sleep = healthService.primarySleepSession {
                sleepOverviewPreviewCard(session: sleep)
            }
            
            // Stress & Autonomic Tone Preview Card (Tap opens Stress Studio)
            stressOverviewPreviewCard
            
            // Primary Vitals Tiles Grid
            vitalsGrid
        }
    }
    
    private var activityHeroCard: some View {
        GlassCard(cornerRadius: 22, padding: 20) {
            HStack(spacing: 20) {
                // Dual Activity Rings
                ZStack {
                    // Steps Ring
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 10)
                        .frame(width: 90, height: 90)
                    Circle()
                        .trim(from: 0, to: min(1.0, CGFloat(healthService.totalStepsToday) / 10_000.0))
                        .stroke(ThemeColors.accentCyan, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 90, height: 90)
                    
                    // Calories Ring
                    Circle()
                        .stroke(Color.white.opacity(0.05), lineWidth: 8)
                        .frame(width: 66, height: 66)
                    Circle()
                        .trim(from: 0, to: min(1.0, CGFloat(healthService.totalActiveCalories) / 550.0))
                        .stroke(Color(red: 1.0, green: 0.45, blue: 0.2), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 66, height: 66)
                    
                    // Pulsing Heart Icon
                    Image(systemName: "heart.fill")
                        .font(.system(size: 16))
                        .foregroundColor(ThemeColors.accentPink)
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(healthService.totalStepsToday)")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text("/ 10,000 steps")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(ThemeColors.fgMutedDark)
                        }
                    }
                    
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Active Calories")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(ThemeColors.fgMutedDark)
                            Text("\(Int(healthService.totalActiveCalories)) kcal")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(Color(red: 1.0, green: 0.5, blue: 0.2))
                        }
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Current BPM")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(ThemeColors.fgMutedDark)
                            Text(healthService.averageBpm > 0 ? "\(Int(healthService.averageBpm)) bpm" : "--")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(ThemeColors.accentPink)
                        }
                    }
                }
                
                Spacer()
            }
        }
    }
    
    private func sleepOverviewPreviewCard(session: SleepSession) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                healthService.activeSubTab = .sleep
            }
        } label: {
            GlassCard(cornerRadius: 18, padding: 16) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(ThemeColors.accentPurple.opacity(0.18))
                            .frame(width: 42, height: 42)
                        Image(systemName: "bed.double.fill")
                            .font(.system(size: 18))
                            .foregroundColor(ThemeColors.accentPurple)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LAST NIGHT'S SLEEP")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(ThemeColors.accentPurple)
                        Text(session.totalAsleepFormatted)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("\(session.sleepScore) Score • \(session.sleepQualityRating)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    private var stressOverviewPreviewCard: some View {
        let score = healthService.currentStressScore
        let level = healthService.currentStressLevel
        let mood = healthService.stressAnalysis?.monkeyMood ?? .curious
        let levelColor = Color(hex: level.hexColor)
        
        return Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                healthService.activeSubTab = .stress
            }
        } label: {
            GlassCard(cornerRadius: 18, padding: 16) {
                HStack(spacing: 14) {
                    MonkeyMascotView(mood: mood, size: .mini, animated: false)
                        .frame(width: 42, height: 42)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("STRESS & AUTONOMIC BALANCE")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(levelColor)
                            
                            Circle()
                                .fill(levelColor)
                                .frame(width: 6, height: 6)
                        }
                        
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(score)")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text("• \(level.displayName)")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(levelColor)
                            Text("(\(mood.displayName))")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(ThemeColors.fgMutedDark)
                        }
                        
                        Text(mood.adviceQuote)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.75))
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    private var vitalsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            VitalMetricTile(metricType: .restingHeartRate, record: healthService.currentVitals[.restingHeartRate], tint: ThemeColors.accentPink)
            VitalMetricTile(metricType: .hrvSdnn, record: healthService.currentVitals[.hrvSdnn], tint: ThemeColors.accentCyan)
            VitalMetricTile(metricType: .oxygenSaturation, record: healthService.currentVitals[.oxygenSaturation], tint: ThemeColors.accentBlue)
            VitalMetricTile(metricType: .respiratoryRate, record: healthService.currentVitals[.respiratoryRate], tint: ThemeColors.accentCyan)
            VitalMetricTile(metricType: .bloodPressureSystolic, record: healthService.currentVitals[.bloodPressureSystolic], tint: Color(red: 1.0, green: 0.4, blue: 0.4))
            VitalMetricTile(metricType: .stress, record: healthService.currentVitals[.stress], tint: Color(red: 1.0, green: 0.7, blue: 0.2))
            VitalMetricTile(metricType: .hydration, record: healthService.currentVitals[.hydration], tint: ThemeColors.accentCyan)
            VitalMetricTile(metricType: .weight, record: healthService.currentVitals[.weight], tint: ThemeColors.accentPurple)
        }
    }
    
    // MARK: - Vitals Section
    
    private var vitalsSection: some View {
        VStack(spacing: 16) {
            HeartRateCurveView()
            
            Text("ALL SENSOR VITALS")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(ThemeColors.accentCyan)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)
            
            vitalsGrid
        }
    }
}

