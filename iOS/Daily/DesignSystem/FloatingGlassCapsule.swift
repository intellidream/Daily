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
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .weather: return "cloud.sun.fill"
        case .news: return "newspaper.fill"
        case .health: return "heart.fill"
        case .habits: return "drop.fill"
        case .settings: return "gearshape.fill"
        }
    }
    
    public static let primaryTabs: [NavigationTab] = [.dashboard, .news, .health, .habits]
}

/// Floating Liquid Glass navigation capsule anchored at the bottom of the viewport.
public struct FloatingGlassCapsule: View {
    @Binding public var selectedTab: NavigationTab
    @Namespace private var capsuleNamespace
    @ObservedObject private var settingsService = SettingsService.shared
    
    public init(selectedTab: Binding<NavigationTab>) {
        self._selectedTab = selectedTab
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            ForEach(NavigationTab.primaryTabs) { tab in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        selectedTab = tab
                    }
                    if settingsService.settings.hapticsEnabled {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        #endif
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 14, weight: .semibold))
                        
                        if selectedTab == tab {
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: .semibold))
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
                    .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.6))
                    .padding(.vertical, 10)
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
    }
}
