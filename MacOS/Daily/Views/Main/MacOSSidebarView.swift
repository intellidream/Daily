import SwiftUI
import DailyCore
import AppKit

public struct MacOSSidebarView: View {
    @Binding public var selectedTab: NavigationTab
    @Binding public var isSidebarVisible: Bool
    @ObservedObject private var settingsService = SettingsService.shared
    
    public init(selectedTab: Binding<NavigationTab>, isSidebarVisible: Binding<Bool>) {
        self._selectedTab = selectedTab
        self._isSidebarVisible = isSidebarVisible
    }
    
    private func triggerHaptic() {
        if settingsService.settings.hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView
            
            Divider()
                .background(Color.white.opacity(0.12))
                .padding(.horizontal, 12)
            
            navigationListView
            
            Spacer()
            
            userFooterView
        }
        .frame(width: 220)
        .background {
            sidebarBackground
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 1)
        }
    }
    
    @ViewBuilder
    private var headerView: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [ThemeColors.accentCyan.opacity(0.4), ThemeColors.accentBlue.opacity(0.1), Color.clear],
                            center: .center,
                            startRadius: 2,
                            endRadius: 18
                        )
                    )
                    .frame(width: 32, height: 32)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [ThemeColors.accentCyan, ThemeColors.accentBlue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            Text("DayOne")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            Spacer()
            
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isSidebarVisible.toggle()
                }
                triggerHaptic()
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.7))
                    .padding(6)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Collapse Sidebar (⌘S)")
        }
        .padding(.horizontal, 16)
        .padding(.top, 28)
    }
    
    @ViewBuilder
    private var navigationListView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 4) {
                ForEach(NavigationTab.allNavTabs) { tab in
                    sidebarItem(for: tab)
                }
            }
            .padding(.horizontal, 10)
        }
    }
    
    @ViewBuilder
    private var userFooterView: some View {
        if let user = AuthService.shared.currentUser {
            HStack(spacing: 10) {
                Circle()
                    .fill(LinearGradient(colors: [ThemeColors.accentBlue, ThemeColors.accentCyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 28, height: 28)
                    .overlay {
                        Text(String((user.email ?? user.displayName ?? "U").prefix(1)).uppercased())
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.displayName ?? "User")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    if let email = user.email, !email.isEmpty {
                        Text(email)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(ThemeColors.fgMutedDark)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
            }
            .padding(10)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
        }
    }
    
    @ViewBuilder
    private var sidebarBackground: some View {
        RoundedRectangle(cornerRadius: 0)
            .fill(Color(hex: "080F1E").opacity(0.85))
            .background(.ultraThinMaterial)
    }
    
    @ViewBuilder
    private func sidebarItem(for tab: NavigationTab) -> some View {
        let isSelected = selectedTab == tab
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                selectedTab = tab
            }
            triggerHaptic()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isSelected ? ThemeColors.accentCyan : Color.white.opacity(0.7))
                    .frame(width: 22, alignment: .center)
                
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? .white : Color.white.opacity(0.8))
                
                Spacer()
                
                Text("⌘\(tab.shortcutNumber)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.35))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [ThemeColors.accentBlue.opacity(0.35), ThemeColors.accentCyan.opacity(0.2)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(ThemeColors.accentCyan.opacity(0.4), lineWidth: 1)
                        }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
