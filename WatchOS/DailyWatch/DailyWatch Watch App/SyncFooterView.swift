import SwiftUI

struct SyncFooterView: View {
    let isSyncing: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            if isSyncing {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
                Text("Syncing...")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            } else {
                Color.clear
                    .frame(height: 12)
            }
        }
        .frame(height: 14)
    }
}
