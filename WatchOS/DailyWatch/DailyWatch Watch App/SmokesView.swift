import SwiftUI
import WatchKit
import Supabase

struct SmokesView: View {
    @State private var todayTotal: Int = 0
    @State private var baseline: Int = 20
    @State private var isLogging: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                HStack {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.red)
                    Text("Smokes")
                        .font(.headline)
                        .fontWeight(.bold)
                }
                .padding(.top, 4)
                
                // Big Metric
                VStack(spacing: 2) {
                    Text("\(todayTotal)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundColor(todayTotal >= baseline ? .red : .green)
                    
                    Text("OF \(baseline) TODAY")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fontWeight(.semibold)
                }
                .padding(.vertical, 8)
                
                // Add Buttons
                HStack(spacing: 12) {
                    SmokesAddButton(icon: "flame.fill", color: .red, title: "Cigarette") {
                        logSmoke(type: "Cigarette")
                    }
                    
                    SmokesAddButton(icon: "bolt.fill", color: .blue, title: "Heated") {
                        logSmoke(type: "Heated Tobacco")
                    }
                }
            }
            .padding(.horizontal)
        }
        .onAppear {
            fetchTodayTotal()
        }
    }
    
    private func fetchTodayTotal() {
        Task {
            do {
                guard let pClient = WatchSessionManager.shared.supabaseClient else { return }
                
                let calendar = Calendar.current
                let startOfDay = calendar.startOfDay(for: Date())
                let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
                
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let startString = formatter.string(from: startOfDay)
                let endString = formatter.string(from: endOfDay)
                
                let logs: [HabitLog] = try await pClient
                    .from("habits_logs")
                    .select()
                    .eq("habit_type", value: "smokes")
                    .gte("logged_at", value: startString)
                    .lt("logged_at", value: endString)
                    .execute()
                    .value
                
                let sum = logs.reduce(0.0) { $0 + $1.value }
                DispatchQueue.main.async {
                    self.todayTotal = Int(sum)
                }
            } catch {
                print("Error fetching smokes: \(error)")
            }
        }
    }
    
    private func logSmoke(type: String) {
        guard !isLogging else { return }
        isLogging = true
        
        // Haptic feedback
        WKInterfaceDevice.current().play(.success)
        
        withAnimation {
            todayTotal += 1
        }
        
        Task {
            do {
                guard let pClient = WatchSessionManager.shared.supabaseClient else {
                    print("Supabase client not initialized")
                    DispatchQueue.main.async { isLogging = false }
                    return
                }
                
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let nowString = formatter.string(from: Date())
                
                let newLog = HabitLog(
                    user_id: WatchSessionManager.shared.currentUserId,
                    habit_type: "smokes",
                    value: 1.0,
                    unit: "cig",
                    logged_at: nowString,
                    metadata: "{ \"type\": \"\(type)\" }"
                )
                
                try await pClient
                    .from("habits_logs")
                    .insert(newLog)
                    .execute()
                
                print("Successfully logged 1 smoke (\(type))")
                
                DispatchQueue.main.async {
                    isLogging = false
                }
            } catch {
                print("Error logging smoke: \(error)")
                DispatchQueue.main.async {
                    withAnimation { todayTotal -= 1 }
                    isLogging = false
                }
            }
        }
    }
}

struct SmokesAddButton: View {
    let icon: String
    let color: Color
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                    .padding(.bottom, 2)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
