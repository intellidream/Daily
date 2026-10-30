import SwiftUI
import WatchKit

struct CravingPacingBadge: View {
    @ObservedObject private var store = WatchHabitStore.shared
    @State private var showBreathingSheet: Bool = false
    
    private var badgeColor: Color {
        if store.isCravingWarning {
            return .orange
        } else if store.timeSinceLastSmoke == nil || (store.timeSinceLastSmoke ?? 0) >= 2 * 3600 {
            return .green
        } else {
            return .yellow
        }
    }
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "timer")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(badgeColor)
            
            Text(store.formattedTimeSinceLastSmoke)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(badgeColor)
            
            Spacer()
            
            Button(action: {
                WKInterfaceDevice.current().play(.click)
                showBreathingSheet = true
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "lungs.fill")
                        .font(.system(size: 9))
                    Text("Breathe")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.mint.opacity(0.2))
                .foregroundColor(.mint)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
        .sheet(isPresented: $showBreathingSheet) {
            WatchBreathingView()
        }
    }
}
