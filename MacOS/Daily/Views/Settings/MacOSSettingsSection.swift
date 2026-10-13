import SwiftUI
import DailyCore

public enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case monochrome = "monochrome"
    case weather = "weather"
    case heartRate = "heart_rate"
    case iconAndWeather = "icon_and_weather"
    case iconAndVitals = "icon_and_vitals"
    case iconOnly = "icon_only" // Legacy fallback alias
    
    public var id: String { rawValue }
    
    public static var allCases: [MenuBarDisplayMode] {
        [.monochrome, .weather, .heartRate, .iconAndWeather, .iconAndVitals]
    }
    
    public var displayName: String {
        switch self {
        case .monochrome, .iconOnly: return "Monochrome App Icon"
        case .weather: return "Weather & Temp"
        case .heartRate: return "Heart Rate"
        case .iconAndWeather: return "Icon + Weather"
        case .iconAndVitals: return "Icon + Heart Rate"
        }
    }
    
    public var iconName: String {
        switch self {
        case .monochrome, .iconOnly: return "sparkles"
        case .weather: return "cloud.sun.fill"
        case .heartRate: return "heart.fill"
        case .iconAndWeather: return "sun.max.fill"
        case .iconAndVitals: return "heart.text.square.fill"
        }
    }
    
    public var description: String {
        switch self {
        case .monochrome, .iconOnly:
            return "Minimalist DayOne template icon adapting dynamically to dark/light menu bars."
        case .weather:
            return "Current outdoor condition symbol and temperature (e.g. ⛅ 17°)."
        case .heartRate:
            return "Live heart symbol and biometric pulse telemetry (e.g. ♥ 68)."
        case .iconAndWeather:
            return "DayOne sparkles icon accompanied by live outdoor temperature."
        case .iconAndVitals:
            return "DayOne sparkles icon accompanied by live biometric heart rate."
        }
    }
}

public struct MacOSSettingsSection: View {
    @ObservedObject private var launchManager = LaunchAtLoginManager.shared
    @AppStorage("useDesktopSidebar") private var useDesktopSidebar: Bool = false
    @AppStorage("menuBarDisplayMode") private var menuBarDisplayMode: String = MenuBarDisplayMode.iconAndWeather.rawValue
    @Environment(\.openWindow) private var openWindow
    
    public init() {}
    
    public var body: some View {
        GlassCard(cornerRadius: 18, padding: 18) {
            VStack(alignment: .leading, spacing: 18) {
                // Section Title
                HStack(spacing: 8) {
                    Image(systemName: "laptopcomputer")
                        .foregroundColor(ThemeColors.accentCyan)
                    Text("macOS Desktop Integration")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                // 1. Launch at Login
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: Binding(
                        get: { launchManager.isEnabled },
                        set: { launchManager.setEnabled($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Launch at Login")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                            Text("Automatically start DayOne and the MenuBar companion when logging in")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(ThemeColors.fgMutedDark)
                        }
                    }
                    .tint(ThemeColors.accentBlue)
                    
                    HStack(spacing: 6) {
                        Circle()
                            .fill(launchManager.isEnabled ? ThemeColors.accentGreen : Color.white.opacity(0.3))
                            .frame(width: 6, height: 6)
                        Text(launchManager.statusMessage)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(ThemeColors.fgMutedDark)
                        
                        if launchManager.requiresApproval {
                            Spacer()
                            Button("Open Settings") {
                                launchManager.openSystemSettings()
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .buttonStyle(.plain)
                            .foregroundColor(ThemeColors.accentCyan)
                        }
                    }
                    .padding(.top, 2)
                }
                
                Divider()
                    .background(Color.white.opacity(0.15))
                
                // 2. Navigation Style Preference
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Default Navigation Style")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                        Text(useDesktopSidebar ? "Sidebar" : "Floating Pill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(ThemeColors.accentCyan)
                    }
                    
                    Picker("Navigation Style", selection: $useDesktopSidebar) {
                        Text("Floating Pill").tag(false)
                        Text("Desktop Sidebar").tag(true)
                    }
                    .pickerStyle(.segmented)
                    
                    Text("Tip: You can toggle the sidebar anytime with ⌘S")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
                
                Divider()
                    .background(Color.white.opacity(0.15))
                
                // 3. MenuBar Extra Display Mode
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Menu Bar Companion Title")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                        if let mode = MenuBarDisplayMode(rawValue: menuBarDisplayMode) {
                            Text(mode.displayName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(ThemeColors.accentCyan)
                        }
                    }
                    
                    Picker("Menu Bar Display", selection: $menuBarDisplayMode) {
                        ForEach(MenuBarDisplayMode.allCases) { mode in
                            Label(mode.displayName, systemImage: mode.iconName)
                                .tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    if let mode = MenuBarDisplayMode(rawValue: menuBarDisplayMode) {
                        Text(mode.description)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(ThemeColors.accentCyan)
                    } else {
                        Text("Select what telemetry to display in the macOS status bar next to the icon")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                    
                    HStack {
                        Button {
                            openWindow(id: "glance")
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                Text("Open Glance Companion (⌘0)")
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(ThemeColors.accentCyan)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(ThemeColors.accentCyan.opacity(0.12), in: Capsule())
                            .overlay(Capsule().strokeBorder(ThemeColors.accentCyan.opacity(0.3), lineWidth: 1))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                    }
                    .padding(.top, 2)
                    
                    Text("💡 If your menu bar is crowded (e.g. active meeting titles or many utilities), macOS may push status icons off-screen. Use ⌘0 anytime to summon Glance, or hold ⌘ and drag menu bar icons to prioritize them.")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(ThemeColors.fgMutedDark)
                        .padding(.top, 2)
                }
                
                Divider()
                    .background(Color.white.opacity(0.15))
                
                // 4. Keyboard Shortcuts Cheatsheet
                VStack(alignment: .leading, spacing: 10) {
                    Text("Native Keyboard Shortcuts")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                    
                    VStack(spacing: 6) {
                        shortcutRow(keys: "⌘ 1 – 7", description: "Switch Hubs (Dashboard to News)")
                        shortcutRow(keys: "⌘ 0", description: "Open DayOne Glance Companion")
                        shortcutRow(keys: "⌘ S", description: "Toggle Desktop Sidebar")
                        shortcutRow(keys: "⌘ R", description: "Trigger Supabase Sync")
                        shortcutRow(keys: "⌘ ,", description: "Open Settings")
                    }
                }
            }
        }
    }
    
    private func shortcutRow(keys: String, description: String) -> some View {
        HStack {
            Text(keys)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            
            Spacer()
            
            Text(description)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(ThemeColors.fgMutedDark)
        }
    }
}
