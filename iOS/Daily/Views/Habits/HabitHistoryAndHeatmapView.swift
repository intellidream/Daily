import SwiftUI
import DailyCore

/// 7-Day Trend Chart and 4-Month GitHub-style Consistency Heatmap.
public struct HabitHistoryAndHeatmapView: View {
    public let habitType: HabitType
    public let trendDays: [HabitTrendDay]
    public let heatmapCells: [HabitConsistencyCell]
    public let goalValue: Double
    public let financialMetrics: SmokesFinancialMetrics?
    public let drinkBreakdown: [HabitDrinkBreakdown]
    
    @State private var selectedHeatmapCell: HabitConsistencyCell?
    
    public init(
        habitType: HabitType,
        trendDays: [HabitTrendDay],
        heatmapCells: [HabitConsistencyCell],
        goalValue: Double,
        financialMetrics: SmokesFinancialMetrics? = nil,
        drinkBreakdown: [HabitDrinkBreakdown] = []
    ) {
        self.habitType = habitType
        self.trendDays = trendDays
        self.heatmapCells = heatmapCells
        self.goalValue = goalValue
        self.financialMetrics = financialMetrics
        self.drinkBreakdown = drinkBreakdown
    }
    
    private var maxTrendValue: Double {
        let maxLogged = trendDays.map(\.amount).max() ?? 0
        return max(maxLogged, goalValue, 1.0) * 1.15
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            // --- 7-Day Trend Bar Chart ---
            GlassCard(cornerRadius: 18, padding: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("7-DAY PERFORMANCE")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(ThemeColors.fgMutedDark)
                            Text(habitType == .water ? "Hydration Volume" : "Tobacco Reduction")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(habitType == .water ? ThemeColors.accentCyan : Color(hex: "#FFB800"))
                                .frame(width: 6, height: 6)
                            Text(habitType == .water ? "Goal: \(Int(goalValue)) ml" : "Limit: \(Int(goalValue))")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(ThemeColors.fgMutedDark)
                        }
                    }
                    
                    // Bar chart area
                    HStack(alignment: .bottom, spacing: 12) {
                        ForEach(trendDays) { day in
                            VStack(spacing: 6) {
                                // Value readout on top
                                if day.amount > 0 {
                                    Text(habitType == .water ? "\(Int(day.amount))" : "\(Int(day.amount))")
                                        .font(.system(size: 9, weight: .bold, design: .rounded))
                                        .foregroundColor(day.isGoalMet ? Color(hex: "#00FFB2") : Color.white.opacity(0.8))
                                } else {
                                    Text("-")
                                        .font(.system(size: 9))
                                        .foregroundColor(ThemeColors.fgMutedDark)
                                }
                                
                                // Bar container
                                ZStack(alignment: .bottom) {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.white.opacity(0.06))
                                        .frame(height: 90)
                                    
                                    let barHeight = max(CGFloat((day.amount / maxTrendValue) * 90.0), day.amount > 0 ? 6 : 0)
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(
                                            LinearGradient(
                                                colors: habitType == .water
                                                    ? [ThemeColors.accentCyan, ThemeColors.accentBlue]
                                                    : (day.amount <= goalValue
                                                       ? [Color(hex: "#00FFB2"), Color(hex: "#00E5FF")]
                                                       : [Color(hex: "#FF3B30"), Color(hex: "#FF9500")]),
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .frame(height: min(barHeight, 90))
                                        .shadow(color: day.isGoalMet ? ThemeColors.accentCyan.opacity(0.4) : Color.clear, radius: 4)
                                }
                                
                                // Day label
                                Text(day.dayLabel)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(day.amount > 0 ? .white : ThemeColors.fgMutedDark)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 125)
                }
            }
            
            // --- Smokes Financial & Health Recovery Metrics ---
            if habitType == .smokes, let metrics = financialMetrics {
                GlassCard(cornerRadius: 18, padding: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("FINANCIAL & RECOVERY SAVINGS")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(ThemeColors.fgMutedDark)
                        
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("MONEY SAVED")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                                Text(metrics.moneySavedFormatted)
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(hex: "#00FFB2"))
                            }
                            
                            Divider()
                                .frame(height: 32)
                                .background(Color.white.opacity(0.15))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("CIGARETTES AVOIDED")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                                Text("\(metrics.cigarettesAvoidedCount)")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundColor(ThemeColors.accentCyan)
                            }
                            
                            Divider()
                                .frame(height: 32)
                                .background(Color.white.opacity(0.15))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("LIFE REGAINED")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                                Text(metrics.lifeRegainedFormatted)
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(hex: "#FFB800"))
                            }
                        }
                    }
                }
            }
            
            // --- 4-Month (120-Day) Consistency Heatmap ---
            GlassCard(cornerRadius: 18, padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("CONSISTENCY HEATMAP")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(ThemeColors.fgMutedDark)
                            Text("120-Day Discipline")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        Spacer()
                        
                        // Intensity scale legend
                        HStack(spacing: 3) {
                            Text("Less")
                                .font(.system(size: 9))
                                .foregroundColor(ThemeColors.fgMutedDark)
                            ForEach(0..<5) { level in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(heatmapColor(for: level))
                                    .frame(width: 8, height: 8)
                            }
                            Text("More")
                                .font(.system(size: 9))
                                .foregroundColor(ThemeColors.fgMutedDark)
                        }
                    }
                    
                    if let selected = selectedHeatmapCell {
                        HStack {
                            Text("\(selected.dateFormatted):")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(ThemeColors.accentCyan)
                            Text(habitType == .water ? "\(Int(selected.amount)) ml logged" : "\(Int(selected.amount)) units logged")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Spacer()
                            if selected.isGoalMet {
                                Text("Goal Met ✓")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(Color(hex: "#00FFB2"))
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    
                    // Heatmap Grid: Horizontal ScrollView for 16-17 weeks
                    ScrollView(.horizontal, showsIndicators: false) {
                        let columns = chunkedHeatmapWeeks(heatmapCells)
                        HStack(spacing: 3.5) {
                            ForEach(0..<columns.count, id: \.self) { colIndex in
                                VStack(spacing: 3.5) {
                                    ForEach(columns[colIndex]) { cell in
                                        Button {
                                            selectedHeatmapCell = cell
                                        } label: {
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(heatmapColor(for: cell.intensityLevel))
                                                .frame(width: 12, height: 12)
                                                .overlay {
                                                    if selectedHeatmapCell?.id == cell.id {
                                                        RoundedRectangle(cornerRadius: 3)
                                                            .strokeBorder(Color.white, lineWidth: 1.5)
                                                    }
                                                }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            
            // --- Drink Breakdown ---
            if habitType == .water && !drinkBreakdown.isEmpty {
                GlassCard(cornerRadius: 18, padding: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("TODAY'S BEVERAGE BREAKDOWN")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(ThemeColors.fgMutedDark)
                        
                        VStack(spacing: 8) {
                            ForEach(drinkBreakdown) { item in
                                HStack {
                                    Circle()
                                        .fill(Color(hex: item.colorHex))
                                        .frame(width: 8, height: 8)
                                    Text(item.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.white)
                                    Spacer()
                                    Text("\(Int(item.amountMl)) ml")
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                    Text("(\(Int(item.percentage))%)")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(ThemeColors.fgMutedDark)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func heatmapColor(for level: Int) -> Color {
        if habitType == .water {
            switch level {
            case 1: return ThemeColors.accentCyan.opacity(0.3)
            case 2: return ThemeColors.accentCyan.opacity(0.55)
            case 3: return ThemeColors.accentBlue.opacity(0.8)
            case 4: return Color(hex: "#00FFB2")
            default: return Color.white.opacity(0.06)
            }
        } else {
            switch level {
            case 1: return Color(hex: "#00FFB2").opacity(0.35)
            case 2: return Color(hex: "#00FFB2").opacity(0.7)
            case 3: return Color(hex: "#FFB800").opacity(0.75)
            case 4: return Color(hex: "#FF3B30")
            default: return Color.white.opacity(0.06)
            }
        }
    }
    
    private func chunkedHeatmapWeeks(_ cells: [HabitConsistencyCell]) -> [[HabitConsistencyCell]] {
        var weeks: [[HabitConsistencyCell]] = []
        var currentWeek: [HabitConsistencyCell] = []
        
        for cell in cells {
            currentWeek.append(cell)
            if currentWeek.count == 7 {
                weeks.append(currentWeek)
                currentWeek = []
            }
        }
        if !currentWeek.isEmpty {
            weeks.append(currentWeek)
        }
        return weeks
    }
}
