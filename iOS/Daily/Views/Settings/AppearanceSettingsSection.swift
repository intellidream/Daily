import SwiftUI
import DailyCore

public struct AppearanceSettingsSection: View {
    @ObservedObject private var settingsService = SettingsService.shared
    
    public init() {}
    
    public var body: some View {
        GlassCard(cornerRadius: 18, padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "paintpalette.fill")
                        .foregroundColor(ThemeColors.accentCyan)
                    Text("Appearance")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                // 1. Theme Picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Application Theme")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    
                    Picker("Theme", selection: Binding(
                        get: { settingsService.settings.theme },
                        set: { newTheme in
                            settingsService.update { $0.theme = newTheme }
                        }
                    )) {
                        ForEach(AppTheme.allCases, id: \.self) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Divider()
                    .background(Color.white.opacity(0.15))
                
                // 2. Glass Intensity Picker
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Liquid Glass Intensity")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                        Text(settingsService.settings.glassIntensity.displayName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(ThemeColors.accentCyan)
                    }
                    
                    Picker("Glass Intensity", selection: Binding(
                        get: { settingsService.settings.glassIntensity },
                        set: { newIntensity in
                            settingsService.update { $0.glassIntensity = newIntensity }
                        }
                    )) {
                        ForEach(GlassIntensity.allCases, id: \.self) { intensity in
                            Text(intensity.displayName).tag(intensity)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Divider()
                    .background(Color.white.opacity(0.15))
                
                // 3. Haptics Toggle
                Toggle(isOn: Binding(
                    get: { settingsService.settings.hapticsEnabled },
                    set: { enabled in
                        settingsService.update { $0.hapticsEnabled = enabled }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Haptic Feedback")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                        Text("Subtle tactile responses for buttons and switches")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                }
                .tint(ThemeColors.accentBlue)
            }
        }
    }
}
