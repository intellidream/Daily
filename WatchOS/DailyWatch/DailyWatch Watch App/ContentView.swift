import SwiftUI
import WatchConnectivity

struct ContentView: View {
    @StateObject private var sessionManager = WatchSessionManager.shared
    @State private var inputPin: String = ""
    
    var body: some View {
        if sessionManager.isAuthenticated {
            TabView {
                BubblesView()
                    .tabItem {
                        Label("Bubbles", systemImage: "drop.fill")
                    }
                
                SmokesView()
                    .tabItem {
                        Label("Smokes", systemImage: "flame.fill")
                    }
            }
        } else {
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
                            
                        Text("Enter the 6-digit PIN from the Desktop App.")
                            .font(.system(size: 11))
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 2)
                        
                        TextField("123456", text: $inputPin)
                            .textContentType(.oneTimeCode)
                            .multilineTextAlignment(.center)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                        
                        Button("Link Watch") {
                            sessionManager.claimOrbitPin(pin: inputPin)
                        }
                        .disabled(inputPin.count != 6)
                        .buttonStyle(.borderedProminent)
                        .tint(.accentColor)
                        
                        Divider().padding(.vertical, 4)
                        
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
