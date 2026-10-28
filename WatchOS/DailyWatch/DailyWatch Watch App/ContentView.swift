import SwiftUI
import WatchKit
import Supabase

struct ContentView: View {
    @StateObject private var sessionManager = WatchSessionManager.shared
    @State private var selectedTab: Int = 0
    
    var body: some View {
        Group {
            if sessionManager.isCheckingSession {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Connecting to Orbit...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
            } else if sessionManager.isAuthenticated {
                // Horizontal Core Pager
                TabView(selection: $selectedTab) {
                    BubblesView()
                        .tag(0)
                    
                    SmokesView()
                        .tag(1)
                    
                    WatchTagdosView()
                        .tag(2)
                    
                    WatchPulseView()
                        .tag(3)

                    WatchOrbitHubView()
                        .tag(4)
                    
                    AboutView()
                        .tag(5)
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .onChange(of: selectedTab) { _, newTab in
                    if newTab == 2 {
                        Task {
                            await WatchTagdosStore.shared.fetchTagdosData()
                        }
                    } else if newTab == 4 {
                        Task {
                            await WatchSmartLedgerStore.shared.fetchLedgerData()
                        }
                    }
                }
            } else {
                // Watch-Driven PIN Pairing Screen (Zepp OS Parity)
                ScrollView {
                    VStack(spacing: 8) {
                        Text("DayOne Orbit")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.cyan)
                        
                        Text("Pairing PIN")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        if !sessionManager.pairingPin.isEmpty {
                            Text(sessionManager.pairingPin)
                                .font(.system(size: 32, weight: .bold, design: .monospaced))
                                .foregroundColor(.green)
                                .tracking(3)
                                .padding(.vertical, 4)
                        } else {
                            ProgressView()
                                .padding(.vertical, 8)
                        }
                        
                        Text("Enter this PIN in DayOne to link.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 4)
                        
                        HStack(spacing: 5) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text(sessionManager.pairingStatus)
                                .font(.system(size: 10))
                                .foregroundColor(.gray)
                        }
                        .padding(.top, 4)
                        
                        if !sessionManager.errorMessage.isEmpty {
                            Text(sessionManager.errorMessage)
                                .font(.system(size: 10))
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                        }
                        
                        Button(action: {
                            WKInterfaceDevice.current().play(.click)
                            sessionManager.startWatchPinPairing()
                        }) {
                            Text("New PIN")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.cyan)
                                .frame(maxWidth: .infinity, minHeight: 28)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 6)
                        .padding(.horizontal, 16)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
            }
        }
    }
}
