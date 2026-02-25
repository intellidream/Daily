import SwiftUI
import WatchKit
import Supabase

struct BubblesView: View {
    @State private var todayTotal: Int = 0
    @State private var isLogging: Bool = false
    
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
                
                // Progress
                VStack(spacing: 2) {
                    Text("\(todayTotal) ml")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.blue)
                    Text("TODAY")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
                
                // Quick Adds (Matches MAUI UI)
                HStack(spacing: 8) {
                    QuickAddButton(icon: "drop.fill", amount: 300, color: .blue, title: "Large") {
                        logWater(amount: 300, type: "Large Water")
                    }
                    QuickAddButton(icon: "drop", amount: 150, color: .cyan, title: "Small") {
                        logWater(amount: 150, type: "Small Water")
                    }
                }
                
                QuickAddButton(icon: "cup.and.saucer.fill", amount: 100, color: .orange, title: "Coffee", fullWidth: true) {
                    logWater(amount: 100, type: "Coffee")
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
                // End of day is start of tomorrow
                let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
                
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let startString = formatter.string(from: startOfDay)
                let endString = formatter.string(from: endOfDay)
                
                let logs: [HabitLog] = try await pClient
                    .from("habits_logs")
                    .select()
                    .eq("habit_type", value: "water")
                    .gte("logged_at", value: startString)
                    .lt("logged_at", value: endString)
                    .execute()
                    .value
                
                let sum = logs.reduce(0.0) { $0 + $1.value }
                DispatchQueue.main.async {
                    self.todayTotal = Int(sum)
                }
            } catch {
                print("Error fetching bubbles: \(error)")
            }
        }
    }
    
    private func logWater(amount: Int, type: String) {
        guard !isLogging else { return }
        isLogging = true
        
        // Haptic feedback
        WKInterfaceDevice.current().play(.success)
        
        withAnimation {
            todayTotal += amount
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
                    habit_type: "water",
                    value: Double(amount),
                    unit: "ml",
                    logged_at: nowString,
                    metadata: "{ \"drink\": \"\(type)\" }"
                )
                
                try await pClient
                    .from("habits_logs")
                    .insert(newLog)
                    .execute()
                
                print("Successfully logged \(amount)ml of \(type)")
                
                DispatchQueue.main.async {
                    isLogging = false
                }
            } catch {
                print("Error logging water: \(error)")
                DispatchQueue.main.async {
                    // Revert optimistic UI on fail
                    withAnimation { todayTotal -= amount }
                    isLogging = false
                }
            }
        }
    }
}

struct QuickAddButton: View {
    let icon: String
    let amount: Int
    let color: Color
    let title: String
    var fullWidth: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                    .padding(.bottom, 2)
                
                Text("\(amount) ml")
                    .font(.caption)
                    .fontWeight(.semibold)
                
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: fullWidth ? .infinity : .infinity)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
