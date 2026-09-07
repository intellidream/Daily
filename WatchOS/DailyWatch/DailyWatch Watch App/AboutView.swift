import SwiftUI
import WatchKit

struct AboutView: View {
    @StateObject private var sessionManager = WatchSessionManager.shared
    @State private var showUnpairConfirmation: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // Header
                HStack(spacing: 6) {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(.gray)
                        .font(.system(size: 15))
                    Text("About")
                        .font(.system(size: 17, weight: .bold))
                }
                .padding(.top, 2)
                
                VStack(spacing: 2) {
                    Text("DayOne Orbit")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.primary)
                    Text("v1.0")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                
                Divider()
                    .padding(.horizontal, 10)
                
                VStack(spacing: 3) {
                    HStack {
                        Text("Status:")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Connected")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.green)
                    }
                    
                    if let userId = sessionManager.currentUserId {
                        HStack {
                            Text("User:")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(userId.uuidString.prefix(8) + "...")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                    }
                }
                .padding(.horizontal, 10)
                
                Divider()
                    .padding(.horizontal, 10)
                
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
                .padding(.top, 4)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 12)
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
