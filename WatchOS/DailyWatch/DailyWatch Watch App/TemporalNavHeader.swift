import SwiftUI
import WatchKit

struct TemporalNavHeader: View {
    let title: String
    let canGoForward: Bool
    let accentColor: Color
    let onPrevious: () -> Void
    let onNext: () -> Void
    
    var body: some View {
        HStack(spacing: 6) {
            Button(action: {
                WKInterfaceDevice.current().play(.click)
                onPrevious()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(accentColor)
                    .frame(width: 28, height: 26)
                    .background(Color.white.opacity(0.12))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .center)
            
            if canGoForward {
                Button(action: {
                    WKInterfaceDevice.current().play(.click)
                    onNext()
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(accentColor)
                        .frame(width: 28, height: 26)
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            } else {
                // Invisible placeholder to keep the center title perfectly centered
                Color.clear
                    .frame(width: 28, height: 26)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }
}
