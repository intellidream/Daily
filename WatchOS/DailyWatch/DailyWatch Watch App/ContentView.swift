import SwiftUI
import WatchConnectivity
import HealthKit
import Supabase

struct ContentView: View {
    @StateObject private var sessionManager = WatchSessionManager.shared
    @State private var inputPin: String = ""
    
    var body: some View {
        if sessionManager.isCheckingSession {
            VStack {
                ProgressView("Orbiting DayOne...")
                    .padding()
            }
        } else if sessionManager.isAuthenticated {
            TabView {
                BubblesView()
                    .tabItem {
                        Label("Bubbles", systemImage: "drop.fill")
                    }
                
                SmokesView()
                    .tabItem {
                        Label("Smokes", systemImage: "flame.fill")
                    }
                
                #if targetEnvironment(simulator)
                VStack {
                    Button("Inject Mock HR") {
                        Task {
                            guard let pClient = WatchSessionManager.shared.supabaseClient,
                                  let userId = WatchSessionManager.shared.currentUserId else { return }
                            
                            let dateFormatter = ISO8601DateFormatter()
                            dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                            
                            // Create a direct mock payload
                            let payload = TelemetryPayload(
                                user_id: userId.uuidString,
                                type: "heart_rate",
                                value: 75.0,
                                unit: "bpm",
                                start_time: dateFormatter.string(from: Date()),
                                end_time: dateFormatter.string(from: Date()),
                                source_device: "Apple Watch (Mock Injection)"
                            )
                            
                            do {
                                try await pClient.from("health_telemetry").insert([payload]).execute()
                                print("Successfully injected mock HR directly to Supabase")
                            } catch {
                                print("Failed to inject to Supabase: \(error)")
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    
                    Text("Forces a sync to Supabase")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
                .tabItem {
                    Label("Debug", systemImage: "ladybug.fill")
                }
                #endif
            }
        } else {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 8) {
                        if !sessionManager.errorMessage.isEmpty {
                            Text(sessionManager.errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                        }
                        
                        if sessionManager.isPairing {
                            ProgressView("Pairing...")
                                .padding()
                        } else {
                            Text("DayOne Orbit")
                                .font(.headline)
                                .foregroundColor(.accentColor)
                                
                            Text("Link your watch using the 6-digit PIN from the Desktop App.")
                                .font(.system(size: 11))
                                .multilineTextAlignment(.center)
                                .padding(.bottom, 6)
                            
                            NavigationLink(destination: OrbitPinEntryView(pin: $inputPin) {
                                sessionManager.claimOrbitPin(pin: inputPin)
                            }) {
                                Text(inputPin.isEmpty ? "Enter PIN" : inputPin)
                                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                                    .foregroundColor(inputPin.isEmpty ? .primary : .accentColor)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(inputPin.isEmpty ? .gray.opacity(0.3) : .accentColor)
                            
                            Divider().padding(.vertical, 8)
                            
                            Button("Pair via iPhone") {
                                sessionManager.generatePairingCode()
                            }
                            .font(.system(size: 12))
                            
                            if !sessionManager.pairingCode.isEmpty {
                                Text(sessionManager.pairingCode)
                                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    }
}
