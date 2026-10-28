import SwiftUI
import DailyCore
import AppKit

public enum NavigationTab: String, CaseIterable, Identifiable, Sendable {
    case dashboard = "Dashboard"
    case finances = "Money"
    case tagdos = "TagDoS"
    case health = "Health"
    case habits = "Habits"
    case weather = "Weather"
    case cosmos = "Cosmos"
    case news = "News"
    case settings = "Settings"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .finances: return "wallet.bifold.fill"
        case .tagdos: return "checklist"
        case .health: return "heart.fill"
        case .habits: return "drop.fill"
        case .weather: return "cloud.sun.fill"
        case .cosmos: return "moon.stars.fill"
        case .news: return "newspaper.fill"
        case .settings: return "gearshape.fill"
        }
    }
    
    public var shortcutNumber: String {
        switch self {
        case .dashboard: return "1"
        case .finances: return "2"
        case .tagdos: return "3"
        case .health: return "4"
        case .habits: return "5"
        case .weather: return "6"
        case .news: return "7"
        case .cosmos: return "8"
        case .settings: return ","
        }
    }
    
    public static let primaryTabs: [NavigationTab] = [.dashboard, .finances, .tagdos, .health, .habits]
    public static let allNavTabs: [NavigationTab] = [.dashboard, .finances, .tagdos, .health, .habits, .weather, .cosmos, .news, .settings]
}

/// Floating Liquid Glass navigation capsule anchored at the bottom of the viewport on macOS.
public struct FloatingGlassCapsule: View {
    @Binding public var selectedTab: NavigationTab
    @Namespace private var capsuleNamespace
    @ObservedObject private var settingsService = SettingsService.shared
    
    @State private var hoveredTab: NavigationTab? = nil
    
    public init(selectedTab: Binding<NavigationTab>) {
        self._selectedTab = selectedTab
    }
    
    private func triggerHaptic() {
        if settingsService.settings.hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
    }
    
    public var body: some View {
        HStack(spacing: 6) {
            ForEach(NavigationTab.primaryTabs) { tab in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        selectedTab = tab
                    }
                    triggerHaptic()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 13, weight: .semibold))
                        
                        if selectedTab == tab {
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: .semibold))
                                .fixedSize(horizontal: true, vertical: false)
                                .lineLimit(1)
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
                    .foregroundColor(selectedTab == tab ? .white : (hoveredTab == tab ? .white.opacity(0.9) : .white.opacity(0.6)))
                    .padding(.vertical, 8)
                    .padding(.horizontal, selectedTab == tab ? 14 : 10)
                    .background {
                        if selectedTab == tab {
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            ThemeColors.accentBlue.opacity(0.70),
                                            ThemeColors.accentCyan.opacity(0.45)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .matchedGeometryEffect(id: "ActiveTabIndicator", in: capsuleNamespace)
                                .overlay {
                                    Capsule(style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
                                }
                                .shadow(color: ThemeColors.accentCyan.opacity(0.35), radius: 8, x: 0, y: 2)
                        } else if hoveredTab == tab {
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        }
                    }
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .onHover { isHovering in
                    hoveredTab = isHovering ? tab : nil
                }
                .help("\(tab.rawValue) (⌘\(tab.shortcutNumber))")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.35))
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(ThemeColors.glassDarkBorder, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.45), radius: 18, x: 0, y: 8)
    }
}
