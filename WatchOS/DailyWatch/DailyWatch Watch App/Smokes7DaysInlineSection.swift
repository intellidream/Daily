import SwiftUI
import WatchKit
import Charts

struct Smokes7DaysInlineSection: View {
    @ObservedObject private var store = WatchHabitStore.shared
    
    private var weeklyAverage: Double {
        let buckets = store.smokesWeekBuckets
        guard !buckets.isEmpty else { return 0 }
        let sum = buckets.reduce(0.0) { $0 + $1.total }
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: Date())
        let daysElapsed = (weekday == 1) ? 7 : max(1, weekday - 1)
        return sum / Double(daysElapsed)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("7-DAY TREND (MON - SUN)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: "Avg: %.1f/d", weeklyAverage))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.red)
            }
            .padding(.horizontal, 2)
            
            if store.smokesWeekBuckets.isEmpty {
                ProgressView()
                    .frame(height: 70)
            } else {
                Chart {
                    ForEach(store.smokesWeekBuckets) { item in
                        BarMark(
                            x: .value("Day", item.date, unit: .day),
                            y: .value("Cig", item.cig)
                        )
                        .foregroundStyle(Color.red)
                        .cornerRadius(3)
                        
                        if item.heat > 0 {
                            BarMark(
                                x: .value("Day", item.date, unit: .day),
                                y: .value("Heat", item.heat)
                            )
                            .foregroundStyle(Color.blue)
                            .cornerRadius(3)
                        }
                    }
                    
                    RuleMark(y: .value("Baseline", store.smokesBaseline))
                        .foregroundStyle(Color.orange.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                }
                .frame(height: 75)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        if let intVal = value.as(Int.self), intVal == store.smokesBaseline || intVal == 0 {
                            AxisValueLabel()
                                .font(.system(size: 8))
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 1)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                            .font(.system(size: 9, weight: .semibold))
                    }
                }
                .padding(.horizontal, 2)
            }
            
            // Financial Impact Row
            HStack {
                Text(String(format: "Cheltuit: %.2f Lei", store.moneySpentTodayLei))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer()
                if store.moneySavedTodayLei > 0 {
                    Text(String(format: "+%.2f Lei salvat", store.moneySavedTodayLei))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.green)
                }
            }
            .padding(.top, 2)
            .padding(.horizontal, 2)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.white.opacity(0.06))
        .cornerRadius(12)
    }
}
