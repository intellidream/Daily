import SwiftUI
import WatchKit

struct AboutView: View {
    @StateObject private var sessionManager = WatchSessionManager.shared
    @State private var showUnpairConfirmation: Bool = false
    @State private var lastHealthSyncTime: Double = UserDefaults.standard.double(forKey: "last_health_sync_time")
    
    private var healthSyncStatusText: (text: String, color: Color) {
        guard lastHealthSyncTime > 0 else {
            return ("not synced", .red)
        }
        
        let date = Date(timeIntervalSince1970: lastHealthSyncTime)
        let calendar = Calendar.current
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let timeStr = timeFormatter.string(from: date)
        
        if calendar.isDateInToday(date) {
            return ("synced at \(timeStr)", .yellow)
        } else {
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "d MMM"
            return ("synced at \(timeStr), \(dayFormatter.string(from: date))", .yellow)
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // App Logo from Zepp OS
                Image("OrbitLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 46, height: 46)
                    .cornerRadius(11)
                    .shadow(color: .cyan.opacity(0.35), radius: 5)
                    .padding(.top, 4)
                
                VStack(spacing: 2) {
                    Text("DayOne Orbit")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.primary)
                    Text("v1.0")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Divider()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 2)
                
                VStack(spacing: 5) {
                    HStack {
                        Text("Status:")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Connected")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.green)
                    }
                    
                    HStack {
                        Text("Health:")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        let status = healthSyncStatusText
                        Text(status.text)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(status.color)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .padding(.horizontal, 10)
                
                Divider()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 2)
                
                // Unpair Button
                Button(role: .destructive, action: {
                    showUnpairConfirmation = true
                }) {
                    HStack {
                        Image(systemName: "link.badge.minus")
                            .font(.system(size: 13))
                        Text("Unpair Watch")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(Color.red.opacity(0.15))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.top, 2)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 12)
        }
        .onAppear {
            lastHealthSyncTime = UserDefaults.standard.double(forKey: "last_health_sync_time")
        }
        .confirmationDialog(
            "Are you sure you want to unpair this Apple Watch? You will need to pair it again with a PIN.",
            isPresented: $showUnpairConfirmation,
            titleVisibility: .visible
        ) {
            Button("Unpair", role: .destructive) {
                WKInterfaceDevice.current().play(.notification)
                sessionManager.logout()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
