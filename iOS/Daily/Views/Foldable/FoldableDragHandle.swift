import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Minimalist interactive horizontal drag handle pill for foldable secondary panes.
/// Provides a clean visual cue indicating swipe-down to dismiss without consuming
/// header space or duplicating hub titles and close buttons.
public struct FoldableDragHandle: View {
    public let onDismiss: () -> Void
    
    @State private var dragOffsetY: CGFloat = 0
    
    public init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }
    
    private func triggerHaptic() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.35))
                .frame(width: 48, height: 5)
                .offset(y: dragOffsetY)
                .gesture(
                    DragGesture(minimumDistance: 5, coordinateSpace: .local)
                        .onChanged { value in
                            if value.translation.height > 0 {
                                // Apply slight damping resistance
                                dragOffsetY = value.translation.height * 0.75
                            }
                        }
                        .onEnded { value in
                            if value.translation.height > 50 || value.predictedEndTranslation.height > 75 {
                                triggerHaptic()
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    onDismiss()
                                }
                            }
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                dragOffsetY = 0
                            }
                        }
                )
                .padding(.top, 8)
                .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}
