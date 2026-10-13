import SwiftUI
import DailyCore
import AppKit

public struct RootView: View {
    @ObservedObject private var authService = AuthService.shared
    @State private var selectedTab: NavigationTab = .dashboard
    @AppStorage("useDesktopSidebar") private var isSidebarVisible: Bool = false
    @State private var isReadingArticleInNews: Bool = false
    @State private var isNavCapsuleExpandedWhileReading: Bool = false
    @State private var isHoveringNavBubble: Bool = false
    
    public init() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-startTabNews") {
            self._selectedTab = State(initialValue: .news)
        } else if args.contains("-startTabSettings") {
            self._selectedTab = State(initialValue: .settings)
        } else if args.contains("-startTabHabits") {
            self._selectedTab = State(initialValue: .habits)
        } else if args.contains("-startTabHealth") {
            self._selectedTab = State(initialValue: .health)
        } else if args.contains("-startTabFinances") {
            self._selectedTab = State(initialValue: .finances)
        } else if args.contains("-startTabTagdos") {
            self._selectedTab = State(initialValue: .tagdos)
        }
    }
    
    public var body: some View {
        Group {
            switch authService.sessionState {
            case .initializing:
                LiquidGlassBackground {
                    VStack(spacing: 24) {
                        Image("LaunchLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 100, height: 100)
                            .shadow(color: ThemeColors.accentCyan.opacity(0.35), radius: 24, x: 0, y: 6)
                        
                        ProgressView()
                            .tint(ThemeColors.accentCyan)
                            .scaleEffect(1.1)
                    }
                }
                
            case .unauthenticated:
                LoginView()
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96)),
                        removal: .opacity.combined(with: .scale(scale: 1.04))
                    ))
                
            case .authenticated, .guest:
                LiquidGlassBackground {
                    HStack(spacing: 0) {
                        // Optional Desktop Sidebar
                        if isSidebarVisible {
                            MacOSSidebarView(selectedTab: $selectedTab, isSidebarVisible: $isSidebarVisible)
                                .transition(.move(edge: .leading).combined(with: .opacity))
                        }
                        
                        // Main Content View
                        ZStack(alignment: .bottom) {
                            VStack(spacing: 0) {
                                // macOS Custom Top Window Chrome
                                HStack {
                                    // Sidebar Toggle button when sidebar is collapsed
                                    if !isSidebarVisible {
                                        Button {
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                isSidebarVisible.toggle()
                                            }
                                        } label: {
                                            Image(systemName: "sidebar.left")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(Color.white.opacity(0.75))
                                                .padding(7)
                                                .background(Color.white.opacity(0.10), in: Circle())
                                                .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
                                        }
                                        .buttonStyle(.plain)
                                        .help("Show Sidebar (⌘S)")
                                        .padding(.leading, 78) // Clearance for macOS traffic light buttons
                                    } else {
                                        Spacer()
                                            .frame(width: 8)
                                    }
                                    
                                    Spacer()
                                    
                                    // Quick Sync Indicator & Refresh button
                                    Button {
                                        Task { @MainActor in
                                            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                                            await HabitsService.shared.flushOfflineQueue()
                                            await HabitsService.shared.loadDataForSelectedDate()
                                            await HealthDataService.shared.refreshIfStale()
                                        }
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: "arrow.triangle.2.circlepath")
                                                .font(.system(size: 11, weight: .semibold))
                                            Text("Sync")
                                                .font(.system(size: 11, weight: .medium))
                                        }
                                        .foregroundColor(Color.white.opacity(0.7))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.white.opacity(0.08), in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                    .help("Sync with Supabase (⌘R)")
                                }
                                .padding(.top, 14)
                                .padding(.horizontal, 16)
                                .frame(height: 38)
                                
                                // Active Tab View Canvas
                                Group {
                                    switch selectedTab {
                                    case .dashboard:
                                        DashboardView(
                                            onNavigateToWeather: { switchTab(.weather) },
                                            onNavigateToNews: { switchTab(.news) },
                                            onNavigateToHealth: { switchTab(.health) },
                                            onNavigateToHabits: { switchTab(.habits) },
                                            onNavigateToFinances: { switchTab(.finances) },
                                            onNavigateToSettings: { switchTab(.settings) },
                                            onNavigateToTagdos: { switchTab(.tagdos) }
                                        )
                                    case .weather:
                                        WeatherDetailView(onNavigateBack: navigateToDashboard)
                                    case .news:
                                        NewsFeedView(
                                            onNavigateBack: navigateToDashboard,
                                            isReadingArticle: $isReadingArticleInNews
                                        )
                                    case .health:
                                        HealthMainView(onNavigateBack: navigateToDashboard)
                                    case .habits:
                                        HabitsMainView(onNavigateBack: navigateToDashboard)
                                    case .finances:
                                        FinancesMainView(onNavigateBack: navigateToDashboard)
                                    case .tagdos:
                                        TagdosNotesHubView(onNavigateBack: navigateToDashboard)
                                    case .settings:
                                        SettingsView(onNavigateBack: navigateToDashboard)
                                    }
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            
                            // Floating Liquid Glass Navigation Capsule (Shown when sidebar is collapsed or preferred)
                            if !isSidebarVisible {
                                if selectedTab == .news && isReadingArticleInNews {
                                    if isNavCapsuleExpandedWhileReading {
                                        HStack(spacing: 8) {
                                            FloatingGlassCapsule(selectedTab: $selectedTab)
                                            
                                            // Collapse / Retract Button while reading
                                            Button {
                                                withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                                                    isNavCapsuleExpandedWhileReading = false
                                                }
                                                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                                            } label: {
                                                HStack(spacing: 4) {
                                                    Text("Retract")
                                                        .font(.system(size: 11, weight: .semibold))
                                                    Image(systemName: "chevron.right.circle.fill")
                                                        .font(.system(size: 13, weight: .semibold))
                                                }
                                                .foregroundColor(ThemeColors.fgMutedDark)
                                                .padding(.horizontal, 9)
                                                .padding(.vertical, 7)
                                                .background(
                                                    Capsule()
                                                        .fill(Color.black.opacity(0.55))
                                                        .background(.ultraThinMaterial, in: Capsule())
                                                        .overlay(Capsule().strokeBorder(ThemeColors.glassDarkBorder, lineWidth: 1))
                                                )
                                            }
                                            .buttonStyle(.plain)
                                            .help("Retract Navigation Capsule")
                                        }
                                        .padding(.bottom, 20)
                                        .transition(.asymmetric(
                                            insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .move(edge: .bottom).combined(with: .opacity)
                                        ))
                                    } else {
                                        navigationBubble
                                            .transition(.asymmetric(
                                                insertion: .scale(scale: 0.85).combined(with: .opacity),
                                                removal: .scale(scale: 0.85).combined(with: .opacity)
                                            ))
                                    }
                                } else {
                                    FloatingGlassCapsule(selectedTab: $selectedTab)
                                        .padding(.bottom, 20)
                                        .transition(.asymmetric(
                                            insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .move(edge: .bottom).combined(with: .opacity)
                                        ))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 1.03)),
                    removal: .opacity.combined(with: .scale(scale: 0.97))
                ))
            }
        }
        .configureMacOSWindow(minWidth: 440, minHeight: 650)
        .animation(.easeInOut(duration: 0.3), value: authService.sessionState.isAuthenticatedOrGuest)
        // Global Keyboard Navigation Shortcuts (⌘1 - ⌘7, ⌘,, ⌘S, ⌘R)
        .background {
            Group {
                Button("") { switchTab(.dashboard) }.keyboardShortcut("1", modifiers: .command)
                Button("") { switchTab(.finances) }.keyboardShortcut("2", modifiers: .command)
                Button("") { switchTab(.tagdos) }.keyboardShortcut("3", modifiers: .command)
                Button("") { switchTab(.health) }.keyboardShortcut("4", modifiers: .command)
                Button("") { switchTab(.habits) }.keyboardShortcut("5", modifiers: .command)
                Button("") { switchTab(.weather) }.keyboardShortcut("6", modifiers: .command)
                Button("") { switchTab(.news) }.keyboardShortcut("7", modifiers: .command)
                Button("") { switchTab(.settings) }.keyboardShortcut(",", modifiers: .command)
                Button("") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isSidebarVisible.toggle()
                    }
                }.keyboardShortcut("s", modifiers: .command)
                Button("") {
                    Task { @MainActor in
                        await HabitsService.shared.flushOfflineQueue()
                        await HabitsService.shared.loadDataForSelectedDate()
                        await HealthDataService.shared.refreshIfStale()
                    }
                }.keyboardShortcut("r", modifiers: .command)
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
        // Deep Links Handling
        .onOpenURL { url in
            let fullPath = "\(url.host ?? "")/\(url.path)".trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                if fullPath.contains("bubble") || fullPath.contains("water") {
                    selectedTab = .habits
                    HabitsService.shared.activeHabit = .water
                } else if fullPath.contains("smoke") {
                    selectedTab = .habits
                    HabitsService.shared.activeHabit = .smokes
                } else if fullPath.contains("money") {
                    selectedTab = .finances
                    FinanceService.shared.activeSubTab = .money
                } else if fullPath.contains("stock") {
                    selectedTab = .finances
                    FinanceService.shared.activeSubTab = .stocks
                } else if fullPath.contains("world") {
                    selectedTab = .finances
                    FinanceService.shared.activeSubTab = .world
                } else if fullPath.contains("sleep") {
                    selectedTab = .health
                    HealthDataService.shared.activeSubTab = .sleep
                } else if fullPath.contains("stress") {
                    selectedTab = .health
                    HealthDataService.shared.activeSubTab = .stress
                } else if fullPath.contains("tagdos") {
                    selectedTab = .tagdos
                } else if fullPath.contains("summary") || fullPath.contains("briefing") {
                    selectedTab = .dashboard
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 120_000_000)
                        SmartBriefingService.shared.isBriefingPresented = true
                    }
                } else {
                    switch fullPath {
                    case "dashboard": selectedTab = .dashboard
                    case "weather": selectedTab = .weather
                    case "news": selectedTab = .news
                    case "health": selectedTab = .health
                    case "habits": selectedTab = .habits
                    case "finances": selectedTab = .finances
                    case "tagdos": selectedTab = .tagdos
                    case "settings": selectedTab = .settings
                    default: break
                    }
                }
            }
        }
        .onChange(of: isReadingArticleInNews) { _, isReading in
            if !isReading {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isNavCapsuleExpandedWhileReading = false
                }
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab != .news {
                isNavCapsuleExpandedWhileReading = false
            }
        }
    }
    
    // MARK: - Retracted Navigation Bubble (shown when reading news)
    
    private var navigationBubble: some View {
        Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                isNavCapsuleExpandedWhileReading = true
            }
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: selectedTab.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ThemeColors.accentBlue)
                
                if isHoveringNavBubble {
                    Text(selectedTab.rawValue)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .padding(.horizontal, isHoveringNavBubble ? 14 : 11)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.60))
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(ThemeColors.accentBlue.opacity(0.4), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.45), radius: 10, x: 0, y: 4)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHoveringNavBubble = isHovering
            }
        }
        .help("Show Navigation Capsule (⌘1-7)")
        .frame(maxWidth: .infinity, alignment: .bottomTrailing)
        .padding(.trailing, 20)
        .padding(.bottom, 24)
    }
    
    private func switchTab(_ tab: NavigationTab) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            selectedTab = tab
        }
    }
    
    private func navigateToDashboard() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            selectedTab = .dashboard
        }
    }
}
