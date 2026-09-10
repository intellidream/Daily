import SwiftUI
import DailyCore

/// Main Habits Hub for Bubbles (Hydration) and Smokes (Tobacco reduction).
public struct HabitsMainView: View {
    @ObservedObject private var habitsService = HabitsService.shared
    @State private var showingGuidanceSheet = false
    @State private var showingDatePicker = false
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Top Day Navigator & Guidance Header
                headerDayNavigator
                
                // Habit Switcher: Bubbles vs Smokes
                habitTypeSwitcher
                
                // Hero Visual Gauge
                if habitsService.activeHabit == .water {
                    WaterProgressWaveView(
                        currentMl: habitsService.totalWaterMlToday,
                        goalMl: habitsService.waterGoalMl,
                        progressPercent: habitsService.waterProgressPercent
                    )
                    .padding(.vertical, 8)
                } else {
                    SmokesLungsGaugeView(
                        countToday: habitsService.totalSmokesToday,
                        baselineCount: habitsService.smokesBaselineCount,
                        lastSmokeDate: habitsService.lastSmokeTimestamp
                    )
                    .padding(.vertical, 8)
                }
                
                // Quick Logging Grid
                HabitQuickActionGrid(
                    habitType: habitsService.activeHabit,
                    onLogWater: { preset in
                        habitsService.logWater(preset: preset)
                    },
                    onLogCustomWater: { amount, drink in
                        habitsService.logWater(amountMl: amount, drink: drink)
                    },
                    onLogSmoke: { preset in
                        habitsService.logSmoke(preset: preset)
                    },
                    onOpenCravingEmergency: {
                        showingGuidanceSheet = true
                    }
                )
                
                // Analytics: 7-Day Performance & 120-Day Heatmap
                HabitHistoryAndHeatmapView(
                    habitType: habitsService.activeHabit,
                    trendDays: habitsService.trendDays,
                    heatmapCells: habitsService.consistencyHeatmap,
                    goalValue: habitsService.activeHabit == .water ? habitsService.waterGoalMl : Double(habitsService.smokesBaselineCount),
                    financialMetrics: habitsService.smokesFinancialMetrics,
                    drinkBreakdown: habitsService.drinkBreakdown
                )
                
                // Today's Logs Timeline
                todayLogsTimeline
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 110) // Leave space for FloatingGlassCapsule
        }

        .refreshable {
            await habitsService.fetchDay(date: habitsService.selectedDate)
        }
        .sheet(isPresented: $showingGuidanceSheet) {
            HabitGuidanceSheet(initialHabit: habitsService.activeHabit)
        }
        .sheet(isPresented: $showingDatePicker) {
            NavigationStack {
                LiquidGlassBackground {
                    VStack {
                        DatePicker("Select Date", selection: Binding(
                            get: { habitsService.selectedDate },
                            set: { habitsService.selectDate($0) }
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
                }
                .navigationTitle("Calendar")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            showingDatePicker = false
                        }
                        .foregroundColor(.white)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
    
    // MARK: - Header & Day Navigator
    
    private var headerDayNavigator: some View {
        HStack {
            HStack(spacing: 8) {
                Button {
                    habitsService.goToPreviousDay()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                
                Button {
                    showingDatePicker = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(ThemeColors.accentCyan)
                        
                        Text(habitsService.formattedDateTitle)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                }
                
                Button {
                    habitsService.goToNextDay()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                if !habitsService.isToday {
                    Button {
                        habitsService.goToToday()
                    } label: {
                        Text("Today")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(ThemeColors.accentCyan)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                
                Button {
                    showingGuidanceSheet = true
                } label: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(ThemeColors.accentCyan)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.top, 12)
    }
    
    // MARK: - Habit Switcher: Bubbles vs Smokes
    
    private var habitTypeSwitcher: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    habitsService.activeHabit = .water
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Bubbles (Water)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .foregroundColor(habitsService.activeHabit == .water ? .white : Color.white.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background {
                    if habitsService.activeHabit == .water {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [ThemeColors.accentBlue, ThemeColors.accentCyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .overlay {
                                Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                            }
                            .shadow(color: ThemeColors.accentCyan.opacity(0.4), radius: 8)
                    }
                }
            }
            .buttonStyle(.plain)
            
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    habitsService.activeHabit = .smokes
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Smokes (Tobacco)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .foregroundColor(habitsService.activeHabit == .smokes ? .white : Color.white.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background {
                    if habitsService.activeHabit == .smokes {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "#00FFB2").opacity(0.8), ThemeColors.accentBlue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .overlay {
                                Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                            }
                            .shadow(color: Color(hex: "#00FFB2").opacity(0.4), radius: 8)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(4)
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
        .overlay {
            Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        }
    }
    
    // MARK: - Today's Logs Timeline
    
    private var todayLogsTimeline: some View {
        GlassCard(cornerRadius: 18, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("TODAY'S LOGS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                    Spacer()
                    Text("\(habitsService.dailyLogs.count) entries")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
                
                if habitsService.dailyLogs.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "tray")
                                .font(.system(size: 24))
                                .foregroundColor(ThemeColors.fgMutedDark)
                            Text("No entries logged for this date")
                                .font(.system(size: 13))
                                .foregroundColor(ThemeColors.fgMutedDark)
                        }
                        .padding(.vertical, 14)
                        Spacer()
                    }
                } else {
                    VStack(spacing: 10) {
                        ForEach(habitsService.dailyLogs) { log in
                            HabitLogRow(log: log) {
                                habitsService.deleteLog(log)
                            }
                            if log.id != habitsService.dailyLogs.last?.id {
                                Divider().background(Color.white.opacity(0.08))
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Single row item in the Today's Logs timeline
private struct HabitLogRow: View {
    let log: HabitLogRecord
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: log.habitType == "water" ? "drop.fill" : "flame.fill")
                .font(.system(size: 14))
                .foregroundColor(log.habitType == "water" ? ThemeColors.accentCyan : Color(hex: "#FFB800"))
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(log.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text(log.formattedTime)
                    .font(.system(size: 11))
                    .foregroundColor(ThemeColors.fgMutedDark)
            }
            
            Spacer()
            
            Text(log.habitType == "water" ? "+\(Int(log.amount)) ml" : "+\(Int(log.amount))")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(ThemeColors.fgMutedDark)
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
    }
}

