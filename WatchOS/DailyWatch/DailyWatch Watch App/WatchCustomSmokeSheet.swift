import SwiftUI
import WatchKit

struct WatchCustomSmokeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = WatchHabitStore.shared
    
    @State private var selectedType: String = "Cigarette"
    @State private var selectedTimeOffsetMinutes: Int = 0
    
    private let presets: [(name: String, icon: String, color: Color)] = [
        ("Cigarette", "flame.fill", .red),
        ("Heated Tobacco", "bolt.fill", .blue),
        ("Rolled", "leaf.fill", .orange),
        ("Cigarillo", "flame", .purple)
    ]
    
    private let timeOffsets: [(label: String, minutes: Int)] = [
        ("Now", 0),
        ("-15m", 15),
        ("-30m", 30),
        ("-1h", 60)
    ]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("Custom Smoke")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.red)
                    .padding(.top, 2)
                
                // Smoke Type Presets
                VStack(spacing: 6) {
                    Text("TYPE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        ForEach(presets, id: \.name) { p in
                            Button(action: {
                                WKInterfaceDevice.current().play(.click)
                                selectedType = p.name
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: p.icon)
                                        .foregroundColor(p.color)
                                        .font(.system(size: 11))
                                    Text(p.name)
                                        .font(.system(size: 11, weight: .semibold))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 8)
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .background(selectedType == p.name ? Color.red.opacity(0.25) : Color.white.opacity(0.10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedType == p.name ? Color.red : Color.clear, lineWidth: 1)
                                )
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                // Time Offset / Retroactive Logging
                VStack(spacing: 6) {
                    Text("TIME LOGGED")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                    
                    HStack(spacing: 6) {
                        ForEach(timeOffsets, id: \.minutes) { t in
                            Button(action: {
                                WKInterfaceDevice.current().play(.click)
                                selectedTimeOffsetMinutes = t.minutes
                            }) {
                                Text(t.label)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .frame(maxWidth: .infinity, minHeight: 28)
                                    .background(selectedTimeOffsetMinutes == t.minutes ? Color.white.opacity(0.25) : Color.white.opacity(0.10))
                                    .foregroundColor(selectedTimeOffsetMinutes == t.minutes ? .primary : .secondary)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(selectedTimeOffsetMinutes == t.minutes ? Color.white.opacity(0.4) : Color.clear, lineWidth: 1)
                                    )
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                // Confirm Log Button
                Button(action: {
                    logSmoke()
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                        Text("Log +1 \(selectedType)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }
    
    private func logSmoke() {
        if selectedTimeOffsetMinutes == 0 {
            store.logSmoke(type: selectedType)
        } else {
            // Retroactive logging with offset minutes
            let now = Date()
            let retroDate = Calendar.current.date(byAdding: .minute, value: -selectedTimeOffsetMinutes, to: now) ?? now
            let loggedAt = HabitDateParser.toIsoUtcString(retroDate)
            let isHeat = selectedType.lowercased().contains("heat") || selectedType.lowercased().contains("vape")
            let canonicalType = isHeat ? "Heated Tobacco" : (selectedType.lowercased().contains("cigarillo") ? "Cigarillo" : (selectedType.lowercased().contains("roll") ? "Rolled" : "Cigarette"))
            let metadataString = "{\"type\":\"\(canonicalType)\",\"drink\":\"\(canonicalType)\",\"brand\":\"\(canonicalType)\",\"smokeType\":\"\(canonicalType)\"}"
            
            let newLog = HabitLog(
                id: UUID(),
                user_id: WatchSessionManager.shared.currentUserId,
                habit_type: "smokes",
                value: 1.0,
                unit: "cigs",
                logged_at: loggedAt,
                metadata: metadataString
            )
            
            store.todaySmokesLogs.insert(newLog, at: 0)
            store.smokesTotalToday += 1
            if isHeat {
                store.heatCountToday += 1
            } else {
                store.cigsCountToday += 1
            }
            store.saveToAppGroup()
            
            Task {
                await OfflineSyncManager.shared.enqueueInsert(newLog)
                await OfflineSyncManager.shared.processQueue()
            }
        }
    }
}
