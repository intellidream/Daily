import SwiftUI
import DailyCore

public struct SettingsView: View {
    public init() {}
    
    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    // Settings Header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Settings")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text("Preferences, customization, and cloud sync")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(ThemeColors.fgMutedDark)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 12)
                    
                    // Account Section
                    AccountSettingsSection()
                    
                    // Appearance Section
                    AppearanceSettingsSection()
                    
                    // Features Configuration Section
                    FeaturesSettingsSection()
                        .id("features")
                    
                    // Data & Cloud Sync Section
                    DataSyncSettingsSection()
                
                // About DayOne
                AboutSettingsSection()
                    .id("about")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 110) // Leave space for FloatingGlassCapsule
        }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-scrollToAbout") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation {
                        proxy.scrollTo("about", anchor: .bottom)
                    }
                }
            } else if ProcessInfo.processInfo.arguments.contains("-scrollToMedium") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation {
                        proxy.scrollTo("medium_setup", anchor: .center)
                    }
                }
            } else if ProcessInfo.processInfo.arguments.contains("-scrollToFeatures") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation {
                        proxy.scrollTo("features", anchor: .top)
                    }
                }
            }
        }
    }
}
}
