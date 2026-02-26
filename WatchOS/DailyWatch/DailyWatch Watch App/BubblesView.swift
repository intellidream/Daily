import SwiftUI
import WatchKit
import Supabase
import Charts
import WidgetKit

struct BubblesView: View {
    @State private var todayTotal: Int = 0
    @State private var todayWater: Int = 0
    @State private var todayCoffee: Int = 0
    @State private var dailyGoal: Int = 2000
    @State private var isLogging: Bool = false
    @State private var historyLogs: [HabitLog] = []
    @State private var weeklyTotals: [DailyTotal] = []
    @State private var selectedLog: HabitLog?
    @State private var showDeleteConfirm: Bool = false
    
    private func parseMetadata(_ metadata: String?) -> [String: String]? {
        guard let data = metadata?.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: []) as? [String: String]
    }
    
    private func parseDate(_ dateString: String) -> Date? {
        var norm = dateString.replacingOccurrences(of: " ", with: "T")
        // If the date string from C# lacks a timezone, append 'Z' to treat it as UTC
        if !norm.contains("Z") && !norm.hasSuffix("+00") && !norm.contains("+0") && !norm.contains("-0") {
            if norm.count > 10 { // Ensure it's not just a short string
                let lastChar = norm.last!
                if lastChar.isNumber {
                    norm += "Z"
                }
            }
        }
        
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFormatter.date(from: norm) { return d }
        
        let fallbackFormatter = ISO8601DateFormatter()
        return fallbackFormatter.date(from: norm)
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
                    Image(systemName: "drop.fill")
                        .foregroundColor(.blue)
                    Text("Bubbles")
                        .font(.headline)
                        .fontWeight(.bold)
                }
                .padding(.top, 4)
                
                // Ring & Buttons layout
                HStack(spacing: 12) {
                    // Circular Progress
                    ZStack {
                        let totalG = CGFloat(max(dailyGoal, 1))
                        let wProg = CGFloat(todayWater) / totalG
                        let cProg = CGFloat(todayCoffee) / totalG
                        
                        Circle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 10)
                        
                        Circle()
                            .trim(from: 0.0, to: min(wProg, 1.0))
                            .stroke(Color.cyan, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.easeOut(duration: 0.8), value: wProg)
                            
                        Circle()
                            .trim(from: min(wProg, 1.0), to: min(wProg + cProg, 1.0))
                            .stroke(Color.orange, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.easeOut(duration: 0.8), value: cProg)
                        
                        VStack(spacing: 0) {
                            Text("\(todayTotal)")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                            Text("/ \(dailyGoal)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 90, height: 90)
                    
                    // Buttons
                    VStack(spacing: 6) {
                        QuickAddMiniButton(icon: "drop.fill", amount: 300, color: .cyan, fullWidth: true) {
                            logWater(amount: 300, type: "Large Water")
                        }
                        QuickAddMiniButton(icon: "drop", amount: 150, color: .cyan, fullWidth: true) {
                            logWater(amount: 150, type: "Small Water")
                        }
                        QuickAddMiniButton(icon: "cup.and.saucer.fill", amount: 100, color: .orange, fullWidth: true) {
                            logWater(amount: 100, type: "Coffee")
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
                                .foregroundStyle(Color.blue.gradient)
                                .cornerRadius(2)
                            }
                            RuleMark(y: .value("Goal", dailyGoal))
                                .foregroundStyle(Color.blue.opacity(0.5))
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
                                let type = parseMetadata(log.metadata)?["drink"] ?? "Water"
                                Image(systemName: type.contains("Coffee") ? "cup.and.saucer.fill" : "drop.fill")
                                    .foregroundColor(type.contains("Coffee") ? .orange : .cyan)
                                    .font(.system(size: 12))
                                
                                Text("\(Int(log.value)) \(log.unit) " + (type.contains("Coffee") ? "Coffee" : "Water"))
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
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
                    .eq("habit_type", value: "water")
                    .eq("is_deleted", value: false)
                    .gte("logged_at", value: startString)
                    .lt("logged_at", value: endString)
                    .order("logged_at", ascending: false)
                    .execute()
                    .value
                
                let todayString = formatter.string(from: todayStart)
                let todayLogs = logs.filter { $0.logged_at.replacingOccurrences(of: " ", with: "T") >= todayString }
                let sum = todayLogs.reduce(0.0) { $0 + $1.value }
                
                var tWater = 0.0
                var tCoffee = 0.0
                for log in todayLogs {
                    let type = parseMetadata(log.metadata)?["drink"] ?? "Water"
                    if type.contains("Coffee") {
                        tCoffee += log.value
                    } else {
                        tWater += log.value
                    }
                }
                
                var totalsByDay: [Date: Double] = [:]
                for i in 0..<7 {
                    let d = calendar.date(byAdding: .day, value: -i, to: todayStart)!
                    totalsByDay[d] = 0.0
                }
                
                for log in logs {
                    if let date = self.parseDate(log.logged_at) {
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
                    self.todayWater = Int(tWater)
                    self.todayCoffee = Int(tCoffee)
                    WidgetCenter.shared.reloadAllTimelines() // Force complication update on load
                }
            } catch {
                print("Error fetching bubbles: \(error)")
            }
        }
    }
    
    private func deleteLog(_ log: HabitLog) {
        let idStr = log.id.uuidString
        let type = parseMetadata(log.metadata)?["drink"] ?? "Water"
        
        withAnimation {
            self.historyLogs.removeAll { $0.id == log.id }
            self.todayTotal -= Int(log.value)
            self.todayWater -= type.contains("Coffee") ? 0 : Int(log.value)
            self.todayCoffee -= type.contains("Coffee") ? Int(log.value) : 0
            
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
        guard let date = self.parseDate(dateString) else { return "" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func logWater(amount: Int, type: String) {
        guard !isLogging else { return }
        isLogging = true
        WKInterfaceDevice.current().play(.success)
        
        withAnimation {
            todayTotal += amount
            if type.contains("Coffee") {
                todayCoffee += amount
            } else {
                todayWater += amount
            }
            
            if let today = self.weeklyTotals.last {
                self.weeklyTotals[self.weeklyTotals.count - 1] = DailyTotal(date: today.date, total: today.total + Double(amount))
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
                    habit_type: "water",
                    value: Double(amount),
                    unit: "ml",
                    logged_at: nowString,
                    metadata: "{ \"drink\": \"\(type)\" }"
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
                print("Error logging water: \(error)")
                DispatchQueue.main.async {
                    fetchData()
                    isLogging = false
                }
            }
        }
    }
}

struct QuickAddMiniButton: View {
    let icon: String
    let amount: Int
    let color: Color
    var fullWidth: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
                
                Text("\(amount)")
                    .font(.system(size: 10, weight: .semibold))
            }
            .frame(maxWidth: fullWidth ? .infinity : .infinity, minHeight: 28)
            .background(Color.white.opacity(0.1))
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
