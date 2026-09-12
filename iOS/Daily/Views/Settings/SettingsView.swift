import SwiftUI
import DailyCore

public struct SettingsView: View {
    public var onNavigateBack: (() -> Void)? = nil

    public init(onNavigateBack: (() -> Void)? = nil) {
        self.onNavigateBack = onNavigateBack
    }
    
    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    // Settings Header
                    HStack(alignment: .center) {
                        Button {
                            onNavigateBack?()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(
                                    Circle().fill(Color.white.opacity(0.08))
                                        .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                                )
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                        
                        VStack(spacing: 2) {
                            Text("Settings")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text("Preferences & Cloud Sync")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(ThemeColors.fgMutedDark)
                        }
                        
                        Spacer()
                        
                        // Balanced placeholder for exact centering
                        Color.clear
                            .frame(width: 36, height: 36)
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
