import SwiftUI
import WatchKit
import Charts

struct Bubbles7DaysInlineSection: View {
    @ObservedObject private var store = WatchHabitStore.shared
    
    private var weeklyAverage: Int {
        let buckets = store.waterWeekBuckets
        guard !buckets.isEmpty else { return 0 }
        let sum = buckets.reduce(0.0) { $0 + $1.total }
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: Date())
        let daysElapsed = (weekday == 1) ? 7 : max(1, weekday - 1)
        return Int(sum / Double(daysElapsed))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("7-DAY TREND (MON - SUN)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
                Text("Avg: \(weeklyAverage) ml")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.cyan)
            }
            .padding(.horizontal, 2)
            
            if store.waterWeekBuckets.isEmpty {
                ProgressView()
                    .frame(height: 70)
            } else {
                Chart {
                    ForEach(store.waterWeekBuckets) { item in
                        BarMark(
                            x: .value("Day", item.date, unit: .day),
                            y: .value("Water", item.water)
                        )
                        .foregroundStyle(Color.cyan)
                        .cornerRadius(3)
                        
                        if item.coffee > 0 {
                            BarMark(
                                x: .value("Day", item.date, unit: .day),
                                y: .value("Coffee", item.coffee)
                            )
                            .foregroundStyle(Color.orange)
                            .cornerRadius(3)
                        }
                    }
                    
                    RuleMark(y: .value("Goal", store.waterGoal))
                        .foregroundStyle(Color.blue.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                }
                .frame(height: 75)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        if let intVal = value.as(Int.self), intVal == store.waterGoal || intVal == 0 {
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
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.white.opacity(0.06))
        .cornerRadius(12)
    }
}
