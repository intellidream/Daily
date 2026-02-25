import SwiftUI
import WatchKit
import Supabase
import Charts
import WidgetKit

struct SmokesView: View {
    @State private var todayTotal: Int = 0
    @State private var dailyGoal: Int = 20
    @State private var isLogging: Bool = false
    @State private var historyLogs: [HabitLog] = []
    @State private var weeklyTotals: [DailyTotal] = []
    @State private var selectedLog: HabitLog?
    @State private var showDeleteConfirm: Bool = false
    
    private func parseMetadata(_ metadata: String?) -> [String: String]? {
        guard let data = metadata?.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: []) as? [String: String]
    }
    
    struct DailyTotal: Identifiable {
        let id = UUID()
        let date: Date
        let total: Double
    }
    
    struct DeleteUpdate: Encodable {
        let is_deleted = true
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Header
                HStack {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.red)
                    Text("Smokes")
                        .font(.headline)
                        .fontWeight(.bold)
                }
                .padding(.top, 4)
                
                // Ring & Buttons layout
                HStack(spacing: 12) {
                    // Circular Progress
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                        
                        let remaining = max(0, dailyGoal - todayTotal)
                        let progress = CGFloat(remaining) / CGFloat(max(dailyGoal, 1))
                        let ringColor = progress < 0.25 ? Color.red : (progress < 0.5 ? Color.orange : Color.green)
                        
                        Circle()
                            .trim(from: 0.0, to: progress)
                            .stroke(ringColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.easeOut(duration: 0.8), value: progress)
                        
                        VStack(spacing: 0) {
                            Text("\(todayTotal)")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(todayTotal > dailyGoal ? .red : .primary)
                            Text("/ \(dailyGoal)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 90, height: 90)
                    
                    // Buttons
                    VStack(spacing: 6) {
                        SmokesMiniButton(icon: "flame.fill", color: .red, title: "Cig") {
                            logSmoke(type: "Cigarette")
                        }
                        SmokesMiniButton(icon: "bolt.fill", color: .blue, title: "Heat") {
                            logSmoke(type: "Heated Tobacco")
                        }
                    }
                    .frame(width: 70)
                }
                .padding(.vertical, 4)
                
                if !weeklyTotals.isEmpty {
                    VStack(alignment: .leading) {
                        Text("LAST 7 DAYS")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.bottom, 2)
                        
                        Chart {
                            ForEach(weeklyTotals) { item in
                                BarMark(
                                    x: .value("Day", item.date, unit: .day),
                                    y: .value("Total", item.total)
                                )
                                .foregroundStyle(Color.red.gradient)
                                .cornerRadius(2)
                            }
                            RuleMark(y: .value("Baseline", dailyGoal))
                                .foregroundStyle(Color.red.opacity(0.5))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2]))
                        }
                        .frame(height: 70)
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day, count: 1)) { _ in
                                AxisValueLabel(format: .dateTime.weekday(.narrow))
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                
                if !historyLogs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TODAY'S LOGS")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.bottom, 2)
                        
                        ForEach(historyLogs) { log in
                            HStack {
                                let type = parseMetadata(log.metadata)?["type"] ?? "Cigarette"
                                let isHeated = type.contains("Heated") || type.contains("Heat")
                                
                                Image(systemName: isHeated ? "bolt.fill" : "flame.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(isHeated ? .blue : .red)
                                    
                                Text("1 " + (isHeated ? "Heat" : "Cig"))
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                Spacer()
                                Text(formatTime(dateString: log.logged_at))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(6)
                            .onLongPressGesture {
                                selectedLog = log
                                showDeleteConfirm = true
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .alert("Delete Log?", isPresented: $showDeleteConfirm, presenting: selectedLog) { log in
            Button("Delete", role: .destructive) {
                deleteLog(log)
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            fetchData()
        }
    }
    
    private func fetchData() {
        Task {
            do {
                guard let pClient = WatchSessionManager.shared.supabaseClient else { return }
                
                let calendar = Calendar.current
                let todayStart = calendar.startOfDay(for: Date())
                let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart)!
                
                let sevenDaysAgo = calendar.date(byAdding: .day, value: -6, to: todayStart)!
                
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let startString = formatter.string(from: sevenDaysAgo)
                let endString = formatter.string(from: todayEnd)
                
                let logs: [HabitLog] = try await pClient
                    .from("habits_logs")
                    .select()
                    .eq("habit_type", value: "smokes")
                    .eq("is_deleted", value: false)
                    .gte("logged_at", value: startString)
                    .lt("logged_at", value: endString)
                    .order("logged_at", ascending: false)
                    .execute()
                    .value
                
                let todayString = formatter.string(from: todayStart)
                let todayLogs = logs.filter { $0.logged_at >= todayString }
                let sum = todayLogs.reduce(0.0) { $0 + $1.value }
                
                var totalsByDay: [Date: Double] = [:]
                for i in 0..<7 {
                    let d = calendar.date(byAdding: .day, value: -i, to: todayStart)!
                    totalsByDay[d] = 0.0
                }
                
                let isoFormatter = ISO8601DateFormatter()
                isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let fallbackFormatter = ISO8601DateFormatter()
                
                for log in logs {
                    if let date = isoFormatter.date(from: log.logged_at) ?? fallbackFormatter.date(from: log.logged_at) {
                        let day = calendar.startOfDay(for: date)
                        if totalsByDay[day] != nil {
                            totalsByDay[day]! += log.value
                        }
                    }
                }
                
                let chartData = totalsByDay.map { DailyTotal(date: $0.key, total: $0.value) }
                    .sorted { $0.date < $1.date }
                
                DispatchQueue.main.async {
                    self.historyLogs = todayLogs
                    self.weeklyTotals = chartData
                    self.todayTotal = Int(sum)
                }
            } catch {
                print("Error fetching smokes: \(error)")
            }
        }
    }
    
    private func deleteLog(_ log: HabitLog) {
        let idStr = log.id.uuidString
        
        withAnimation {
            self.historyLogs.removeAll { $0.id == log.id }
            self.todayTotal -= Int(log.value)
            
            if let today = self.weeklyTotals.last {
                let newTotal = max(0, today.total - log.value)
                self.weeklyTotals[self.weeklyTotals.count - 1] = DailyTotal(date: today.date, total: newTotal)
            }
        }
        
        Task {
            do {
                guard let pClient = WatchSessionManager.shared.supabaseClient else { return }
                try await pClient
                    .from("habits_logs")
                    .update(DeleteUpdate())
                    .eq("id", value: idStr)
                    .execute()
                    
                DispatchQueue.main.async {
                    WidgetCenter.shared.reloadAllTimelines()
                }
            } catch {
                print("Error deleting log: \(error)")
                fetchData() // revert UI
            }
        }
    }
    
    private func formatTime(dateString: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()
        
        guard let date = isoFormatter.date(from: dateString) ?? fallbackFormatter.date(from: dateString) else { return "" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func logSmoke(type: String) {
        guard !isLogging else { return }
        isLogging = true
        WKInterfaceDevice.current().play(.success)
        
        withAnimation {
            todayTotal += 1
            if let today = self.weeklyTotals.last {
                self.weeklyTotals[self.weeklyTotals.count - 1] = DailyTotal(date: today.date, total: today.total + 1.0)
            }
        }
        
        Task {
            do {
                guard let pClient = WatchSessionManager.shared.supabaseClient else {
                    DispatchQueue.main.async { isLogging = false }
                    return
                }
                
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let nowString = formatter.string(from: Date())
                
                let newLog = HabitLog(
                    id: UUID(),
                    user_id: WatchSessionManager.shared.currentUserId,
                    habit_type: "smokes",
                    value: 1.0,
                    unit: "cig",
                    logged_at: nowString,
                    metadata: "{ \"type\": \"\(type)\" }"
                )
                
                DispatchQueue.main.async {
                    self.historyLogs.insert(newLog, at: 0)
                }
                
                try await pClient.from("habits_logs").insert(newLog).execute()
                
                DispatchQueue.main.async { 
                    isLogging = false 
                    WidgetCenter.shared.reloadAllTimelines()
                }
            } catch {
                print("Error logging smoke: \(error)")
                DispatchQueue.main.async {
                    fetchData()
                    isLogging = false
                }
            }
        }
    }
}

struct SmokesMiniButton: View {
    let icon: String
    let color: Color
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
                
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(Color.white.opacity(0.1))
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
