import SwiftUI
import DailyCore
import AppKit

public struct MenuBarCompanionView: View {
    @ObservedObject private var habitsService = HabitsService.shared
    @ObservedObject private var healthService = HealthDataService.shared
    @ObservedObject private var weatherService = WeatherService.shared
    @ObservedObject private var tagdosStore = TagdosStore.shared
    
    @State private var quickMemoText: String = ""
    @State private var isMemoSaved: Bool = false
    
    public var onOpenFullApp: ((NavigationTab?) -> Void)?
    
    public init(onOpenFullApp: ((NavigationTab?) -> Void)? = nil) {
        self.onOpenFullApp = onOpenFullApp
    }
    
    private func triggerHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
    
    public var body: some View {
        LiquidGlassBackground {
            VStack(spacing: 12) {
                // Header Bar
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [ThemeColors.accentCyan, ThemeColors.accentBlue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("DayOne Glance")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button {
                        triggerHaptic()
                        onOpenFullApp?(nil)
                    } label: {
                        HStack(spacing: 4) {
                            Text("Full App")
                                .font(.system(size: 11, weight: .semibold))
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(ThemeColors.accentCyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(ThemeColors.accentCyan.opacity(0.12), in: Capsule())
                        .overlay {
                            Capsule().strokeBorder(ThemeColors.accentCyan.opacity(0.3), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Open Full DayOne Window (⌘1)")
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        // 1. Weather & Vitals Quick Row
                        HStack(spacing: 10) {
                            // Weather Card
                            Button {
                                onOpenFullApp?(.weather)
                            } label: {
                                GlassCard(cornerRadius: 14, padding: 12) {
                                    HStack(spacing: 8) {
                                        let icon = WeatherConditionHelper.sfSymbol(for: weatherService.currentWeather?.weather.first?.icon ?? "")
                                        Image(systemName: icon)
                                            .font(.system(size: 22, weight: .medium))
                                            .symbolRenderingMode(.multicolor)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(weatherService.currentWeather != nil ? "\(Int(round(weatherService.currentWeather!.main.temp)))°" : "--°")
                                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                                .foregroundColor(.white)
                                            
                                            Text(weatherService.currentLocationName.isEmpty ? "Weather" : weatherService.currentLocationName)
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(ThemeColors.fgMutedDark)
                                                .lineLimit(1)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            
                            // Health Vitals Card (Consumer Mode)
                            Button {
                                onOpenFullApp?(.health)
                            } label: {
                                GlassCard(cornerRadius: 14, padding: 12) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "heart.fill")
                                            .font(.system(size: 20))
                                            .foregroundColor(ThemeColors.accentPink)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 3) {
                                                Text(healthService.latestBpm != nil ? "\(Int(round(healthService.latestBpm!)))" : (healthService.restingBpm > 0 ? "\(Int(round(healthService.restingBpm)))" : "--"))
                                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                                    .foregroundColor(.white)
                                                Text("bpm")
                                                    .font(.system(size: 10, weight: .medium))
                                                    .foregroundColor(ThemeColors.fgMutedDark)
                                            }
                                            
                                            HStack(spacing: 2) {
                                                Image(systemName: "figure.walk")
                                                    .font(.system(size: 9))
                                                Text("\(healthService.totalStepsToday)")
                                                    .font(.system(size: 11, weight: .medium))
                                            }
                                            .foregroundColor(ThemeColors.accentCyan)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        
                        // 2. Hydration Tracker Quick Log
                        GlassCard(cornerRadius: 14, padding: 12) {
                            VStack(spacing: 10) {
                                HStack {
                                    HStack(spacing: 6) {
                                        Image(systemName: "drop.fill")
                                            .foregroundColor(ThemeColors.accentCyan)
                                        Text("Water Intake")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.white)
                                    }
                                    
                                    Spacer()
                                    
                                    Text("\(Int(round(habitsService.waterTotalToday))) / \(Int(round(habitsService.waterGoal))) ml")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundColor(ThemeColors.accentCyan)
                                }
                                
                                // Progress bar
                                GeometryReader { geo in
                                    let progress = habitsService.waterProgressPercent
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(Color.white.opacity(0.12))
                                            .frame(height: 8)
                                        
                                        Capsule()
                                            .fill(
                                                LinearGradient(
                                                    colors: [ThemeColors.accentBlue, ThemeColors.accentCyan],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .frame(width: geo.size.width * CGFloat(progress), height: 8)
                                    }
                                }
                                .frame(height: 8)
                                
                                // Quick log buttons
                                HStack(spacing: 8) {
                                    Button {
                                        triggerHaptic()
                                        habitsService.logWater(amountMl: 250)
                                    } label: {
                                        Text("+250 ml")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 6)
                                            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Button {
                                        triggerHaptic()
                                        habitsService.logWater(amountMl: 500)
                                    } label: {
                                        Text("+500 ml")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 6)
                                            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Button {
                                        triggerHaptic()
                                        habitsService.logSmoke(type: "Cigarette")
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "flame.fill")
                                                .font(.system(size: 10))
                                            Text("+1 Smoke")
                                                .font(.system(size: 12, weight: .semibold))
                                        }
                                        .foregroundColor(ThemeColors.accentPink)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                        .background(ThemeColors.accentPink.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        
                        // 3. TagDoS Quick Memo Scratchpad
                        GlassCard(cornerRadius: 14, padding: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "square.and.pencil")
                                        .foregroundColor(ThemeColors.accentGreen)
                                    Text("Quick Scratchpad")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.white)
                                    
                                    Spacer()
                                    
                                    if isMemoSaved {
                                        Text("Saved!")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(ThemeColors.accentGreen)
                                            .transition(.opacity)
                                    }
                                }
                                
                                HStack(spacing: 8) {
                                    TextField("Jot down a quick thought or task...", text: $quickMemoText)
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 12))
                                        .foregroundColor(.white)
                                        .padding(8)
                                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                                        .onSubmit {
                                            saveQuickMemo()
                                        }
                                    
                                    Button {
                                        saveQuickMemo()
                                    } label: {
                                        Image(systemName: "arrow.up.circle.fill")
                                            .font(.system(size: 22))
                                            .foregroundColor(quickMemoText.trimmingCharacters(in: .whitespaces).isEmpty ? Color.white.opacity(0.2) : ThemeColors.accentCyan)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(quickMemoText.trimmingCharacters(in: .whitespaces).isEmpty)
                                }
                            }
                        }
                        
                        // 4. Quick Jump Navigation Grid
                        HStack(spacing: 8) {
                            quickNavButton(title: "Money", icon: "wallet.bifold.fill", color: ThemeColors.accentGreen, tab: .finances)
                            quickNavButton(title: "Health", icon: "heart.fill", color: ThemeColors.accentPink, tab: .health)
                            quickNavButton(title: "Habits", icon: "drop.fill", color: ThemeColors.accentCyan, tab: .habits)
                            quickNavButton(title: "TagDoS", icon: "checklist", color: ThemeColors.accentOrange, tab: .tagdos)
                            quickNavButton(title: "News", icon: "newspaper.fill", color: ThemeColors.accentBlue, tab: .news)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(width: 360, height: 480)
    }
    
    @ViewBuilder
    private func quickNavButton(title: String, icon: String, color: Color, tab: NavigationTab) -> some View {
        Button {
            triggerHaptic()
            onOpenFullApp?(tab)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
    
    private func saveQuickMemo() {
        let trimmed = quickMemoText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        triggerHaptic()
        tagdosStore.createQuickNote(title: "Quick Memo", content: trimmed)
        quickMemoText = ""
        withAnimation {
            isMemoSaved = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isMemoSaved = false
            }
        }
    }
}
