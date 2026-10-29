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
                    
                    // DayOne Orbit Section (Smartwatch Cloud Link)
                    OrbitSettingsSection()
                        .id("orbit")
                    
                    // Smart Periodic Briefing & AI Section
                    SmartBriefingSettingsSection()
                        .id("smart_briefing")

                    // Cosmos & Night Sky Observatory Section
                    CosmosObservatorySettingsSection()
                        .id("cosmos_settings")
                    
                    // Data & Cloud Sync Section
                    DataSyncSettingsSection()
                
                // About DayOne
                AboutSettingsSection()
                    .id("about")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 140) // Leave space for FloatingGlassCapsule
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
            } else if ProcessInfo.processInfo.arguments.contains("-scrollToOrbitBottom") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation {
                        proxy.scrollTo("orbit_bottom", anchor: .bottom)
                    }
                }
            } else if ProcessInfo.processInfo.arguments.contains("-scrollToOrbit") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation {
                        proxy.scrollTo("orbit", anchor: .top)
                    }
                }
            } else if ProcessInfo.processInfo.arguments.contains("-scrollToBriefing") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation {
                        proxy.scrollTo("smart_briefing", anchor: .center)
                    }
                }
            }
        }
    }
}
}

public struct CosmosObservatorySettingsSection: View {
    @ObservedObject private var settingsService = SettingsService.shared
    @State private var nasaKeyInput: String = SettingsService.shared.settings.nasaApiKey ?? ""
    @State private var weatherEndpointInput: String = SettingsService.shared.settings.cosmosWeatherEndpoint ?? ""
    @State private var weatherKeyInput: String = SettingsService.shared.settings.cosmosWeatherApiKey ?? ""
    @State private var savedBadge: Bool = false

    public init() {}

    public var body: some View {
        GlassCard(cornerRadius: 18, padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(ThemeColors.accentCyan)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(ThemeColors.accentCyan.opacity(0.15)))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cosmos & Night Sky Observatory")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("NASA APOD key, astronomical weather & sky alerts")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundColor(ThemeColors.textSecondary)
                    }
                    Spacer()
                }

                Divider().background(Color.white.opacity(0.12))

                Toggle(isOn: Binding(
                    get: { settingsService.settings.cosmosNotifyIssPasses },
                    set: { val in settingsService.update { $0.cosmosNotifyIssPasses = val } }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bright ISS Visible Pass Alerts")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                        Text("Notify 15 minutes before sunlit passes above 40° altitude.")
                            .font(.system(size: 11.5))
                            .foregroundColor(ThemeColors.textSecondary)
                    }
                }
                .tint(ThemeColors.accentCyan)

                Toggle(isOn: Binding(
                    get: { settingsService.settings.cosmosNotifyAurora },
                    set: { val in settingsService.update { $0.cosmosNotifyAurora = val } }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Geomagnetic Storm & Aurora Alerts")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                        Text("Notify when NOAA SWPC planetary Kp reaches 5.0+ (G1+ storm).")
                            .font(.system(size: 11.5))
                            .foregroundColor(ThemeColors.textSecondary)
                    }
                }
                .tint(ThemeColors.accentCyan)

                Toggle(isOn: Binding(
                    get: { settingsService.settings.cosmosNotifyPristineSky },
                    set: { val in settingsService.update { $0.cosmosNotifyPristineSky = val } }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pristine Dark-Sky Window Alerts")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                        Text("Notify when tonight's Sky Score exceeds 85/100 under clear skies.")
                            .font(.system(size: 11.5))
                            .foregroundColor(ThemeColors.textSecondary)
                    }
                }
                .tint(ThemeColors.accentCyan)

                Divider().background(Color.white.opacity(0.12))

                VStack(alignment: .leading, spacing: 8) {
                    Text("NASA APOD API Key (Optional — Free at api.nasa.gov)")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(ThemeColors.accentCyan)
                    TextField("DEMO_KEY (or paste personal NASA key)", text: $nasaKeyInput)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        .foregroundColor(.white)

                    Text("Custom Forecast Endpoint & Key (Optional — Defaults to Open-Meteo UTC + 7Timer ASTRO)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(ThemeColors.textSecondary)
                    TextField("https://api.open-meteo.com/v1/forecast", text: $weatherEndpointInput)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        .foregroundColor(.white)
                    TextField("Optional commercial forecast API key", text: $weatherKeyInput)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        .foregroundColor(.white)

                    HStack {
                        Text("Catalogs: ESA Hipparcos (I/239), Yale Bright Star (V/50), IAU WGSN, d3-celestial (BSD-3), NASA/Hubble PD.")
                            .font(.system(size: 10.5))
                            .foregroundColor(ThemeColors.fgMutedDark)
                        Spacer()
                        Button {
                            settingsService.update {
                                let nk = nasaKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                let we = weatherEndpointInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                let wk = weatherKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                $0.nasaApiKey = nk.isEmpty ? nil : nk
                                $0.cosmosWeatherEndpoint = we.isEmpty ? nil : we
                                $0.cosmosWeatherApiKey = wk.isEmpty ? nil : wk
                            }
                            savedBadge = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { savedBadge = false }
                        } label: {
                            Text(savedBadge ? "Saved ✓" : "Save Keys")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(ThemeColors.accentCyan, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
