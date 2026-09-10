import SwiftUI
import DailyCore

public enum HealthSubTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case sleep = "Sleep Studio"
    case vitals = "Heart & Vitals"
    case trends = "Trends"
    
    public var id: String { rawValue }
}

/// Master Health & Vitals screen integrating multi-device telemetry, clinical sleep studio, and evolution trends.
public struct HealthMainView: View {
    @ObservedObject private var healthService = HealthDataService.shared
    @State private var activeSubTab: HealthSubTab = .overview
    
    public init() {}
    
    public var body: some View {
        LiquidGlassBackground {
            VStack(spacing: 0) {
                // Top Header Bar
                headerBar
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 8)
                
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Day Navigator
                        dayNavigatorBar
                        
                        // Device Origin Filter Bar
                        if !healthService.availableDevices.isEmpty {
                            deviceFilterBar
                        }
                        
                        // Sub-Tab Switcher
                        subTabSwitcher
                        
                        // Main Content Based on Active Sub-Tab
                        switch activeSubTab {
                        case .overview:
                            overviewSection
                        case .sleep:
                            SleepStudioView()
                        case .vitals:
                            vitalsSection
                        case .trends:
                            HealthTrendsView()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 110) // Room for FloatingGlassCapsule
                }
                .refreshable {
                    await healthService.loadDataForSelectedDate(forceRefresh: true)
                }
            }
        }
    }
    
    // MARK: - Header Bar
    
    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("HEALTH & TELEMETRY")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(ThemeColors.accentCyan)
                Text("Biometrics")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            // Refresh Button
            Button {
                Task {
                    await healthService.loadDataForSelectedDate(forceRefresh: true)
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Day Navigator Bar
    
    private var dayNavigatorBar: some View {
        HStack {
            // Previous Day Button
            Button {
                healthService.prevDay()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Date Title
            Text(formattedDateTitle)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            Spacer()
            
            // Jump to Today or Next Day Button
            let isToday = Calendar.current.isDateInToday(healthService.selectedDate)
            if !isToday {
                Button {
                    healthService.jumpToToday()
                } label: {
                    Text("Today")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(ThemeColors.accentCyan)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(ThemeColors.accentCyan.opacity(0.15)))
                }
                .buttonStyle(.plain)
                
                Button {
                    healthService.nextDay()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.2))
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.06))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        )
    }
    
    private var formattedDateTitle: String {
        let cal = Calendar.current
        if cal.isDateInToday(healthService.selectedDate) {
            return "Today, \(dateString(healthService.selectedDate, format: "MMM d"))"
        } else if cal.isDateInYesterday(healthService.selectedDate) {
            return "Yesterday, \(dateString(healthService.selectedDate, format: "MMM d"))"
        } else {
            return dateString(healthService.selectedDate, format: "EEEE, MMM d")
        }
    }
    
    private func dateString(_ date: Date, format: String) -> String {
        let f = DateFormatter()
        f.dateFormat = format
        return f.string(from: date)
    }
    
    // MARK: - Device Filter Bar
    
    private var deviceFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All Devices" pill
                let isAllSelected = healthService.selectedDeviceSource == nil
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        healthService.setDeviceFilter(nil as DeviceSource?)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "circle.grid.cross.fill")
                            .font(.system(size: 10))
                        Text("All Devices")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(isAllSelected ? .white : .white.opacity(0.6))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(
                        Capsule()
                            .fill(isAllSelected ? ThemeColors.accentCyan.opacity(0.6) : Color.white.opacity(0.06))
                            .overlay(Capsule().strokeBorder(isAllSelected ? ThemeColors.accentCyan : Color.white.opacity(0.1), lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)
                
                // Device-specific pills
                ForEach(healthService.availableSources) { source in
                    let isSelected = healthService.selectedDeviceSource == source
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            healthService.setDeviceFilter(source)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: source.systemImage)
                                .font(.system(size: 10))
                            Text(source.displayName)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(
                            Capsule()
                                .fill(isSelected ? ThemeColors.accentCyan.opacity(0.6) : Color.white.opacity(0.06))
                                .overlay(Capsule().strokeBorder(isSelected ? ThemeColors.accentCyan : Color.white.opacity(0.1), lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - Sub-Tab Switcher
    
    private var subTabSwitcher: some View {
        HStack(spacing: 6) {
            ForEach(HealthSubTab.allCases) { tab in
                let isSelected = activeSubTab == tab
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        activeSubTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
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
                activeSubTab = .sleep
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
