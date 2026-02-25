import SwiftUI
import WatchConnectivity

struct ContentView: View {
    @StateObject private var sessionManager = WatchSessionManager.shared
    
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
            VStack {
                if !sessionManager.errorMessage.isEmpty {
                    Text("Error")
                        .font(.headline)
                        .foregroundColor(.red)
                    Text(sessionManager.errorMessage)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        
                    Button("Retry") {
                        sessionManager.generatePairingCode()
                    }
                    .padding(.top, 5)
                } else if sessionManager.isPairing {
                    Text("Pairing Code")
                        .font(.headline)
                        .foregroundColor(.accentColor)
                        
                    Text(sessionManager.pairingCode)
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .padding(.vertical, 8)
                        
                    Text("Open Daily on iPhone:\nSettings -> Pair Watch")
                        .font(.system(size: 11))
                        .multilineTextAlignment(.center)
                } else {
                    ProgressView("Loading...")
                }
            }
            .padding()
        }
    }
}
