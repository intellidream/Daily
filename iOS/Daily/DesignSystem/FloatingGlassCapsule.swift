import SwiftUI
import DailyCore
#if canImport(UIKit)
import UIKit
#endif

public enum NavigationTab: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case weather = "Weather"
    case news = "News"
    case health = "Health"
    case habits = "Habits"
    case settings = "Settings"
    case finances = "Money"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .weather: return "cloud.sun.fill"
        case .news: return "newspaper.fill"
        case .health: return "heart.fill"
        case .habits: return "drop.fill"
        case .settings: return "gearshape.fill"
        case .finances: return "wallet.bifold.fill"
        }
    }
    
    public static let primaryTabs: [NavigationTab] = [.dashboard, .finances, .health, .habits]
}

/// Floating Liquid Glass navigation capsule anchored at the bottom of the viewport.
public struct FloatingGlassCapsule: View {
    @Binding public var selectedTab: NavigationTab
    @Namespace private var capsuleNamespace
    @ObservedObject private var settingsService = SettingsService.shared
    
    @State private var dragStartTab: NavigationTab? = nil
    @State private var totalCapsuleWidth: CGFloat = 0
    
    public init(selectedTab: Binding<NavigationTab>) {
        self._selectedTab = selectedTab
    }
    
    private func triggerHaptic() {
        if settingsService.settings.hapticsEnabled {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
        }
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            ForEach(NavigationTab.primaryTabs) { tab in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        selectedTab = tab
                    }
                    triggerHaptic()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 14, weight: .semibold))
                        
                        if selectedTab == tab {
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: .semibold))
                                .fixedSize(horizontal: true, vertical: false)
                                .lineLimit(1)
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
                    .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.6))
                    .padding(.vertical, 9)
                    .padding(.horizontal, selectedTab == tab ? 14 : 10)

                    .background {
                        if selectedTab == tab {
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            ThemeColors.accentBlue.opacity(0.65),
                                            ThemeColors.accentCyan.opacity(0.4)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .matchedGeometryEffect(id: "ActiveTabIndicator", in: capsuleNamespace)
                                .overlay {
                                    Capsule(style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                                }
                                .shadow(color: ThemeColors.accentCyan.opacity(0.3), radius: 8, x: 0, y: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.12))
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(ThemeColors.glassDarkBorder, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.4), radius: 18, x: 0, y: 8)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: CapsuleWidthKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(CapsuleWidthKey.self) { newWidth in
            totalCapsuleWidth = newWidth
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    if dragStartTab == nil {
                        dragStartTab = selectedTab
                    }
                    
                    let tabs = NavigationTab.primaryTabs
                    let tabCount = tabs.count
                    guard tabCount > 0 else { return }
                    
                    let targetIndex: Int
                    if totalCapsuleWidth > 60 {
                        let segmentWidth = totalCapsuleWidth / CGFloat(tabCount)
                        let rawIndex = Int(value.location.x / segmentWidth)
                        targetIndex = max(0, min(tabCount - 1, rawIndex))
                    } else if let startTab = dragStartTab, let startIndex = tabs.firstIndex(of: startTab) {
                        let step = Int(round(value.translation.width / 35.0))
                        targetIndex = max(0, min(tabCount - 1, startIndex + step))
                    } else {
                        return
                    }
                    
                    let newTab = tabs[targetIndex]
                    if newTab != selectedTab {
                        triggerHaptic()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            selectedTab = newTab
                        }
                    }
                }
                .onEnded { value in
                    let tabs = NavigationTab.primaryTabs
                    let tabCount = tabs.count
                    
                    // Quick flick / swipe detection when scrub didn't change tab
                    let flickVelocity = value.predictedEndTranslation.width - value.translation.width
                    if let startTab = dragStartTab, let startIndex = tabs.firstIndex(of: startTab), selectedTab == startTab {
                        var targetIndex = startIndex
                        if value.translation.width > 20 || flickVelocity > 45 {
                            targetIndex = min(tabCount - 1, startIndex + 1)
                        } else if value.translation.width < -20 || flickVelocity < -45 {
                            targetIndex = max(0, startIndex - 1)
                        }
                        
                        let targetTab = tabs[targetIndex]
                        if targetTab != selectedTab {
                            triggerHaptic()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                selectedTab = targetTab
                            }
                        }
                    }
                    
                    dragStartTab = nil
                }
        )
    }
}

private struct CapsuleWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
