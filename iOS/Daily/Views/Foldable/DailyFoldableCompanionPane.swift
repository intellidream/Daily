import SwiftUI
import DailyCore
#if canImport(UIKit)
import UIKit
#endif

/// Signature Foldable Companion Pane displayed in the secondary / detail pane on expanded displays
/// (iPhone Duo, foldable form factors) when on the Dashboard tab and no hub is explicitly active.
///
/// Features a live diurnal intelligence header adapted to the time of day,
/// concentric recovery rings (Steps, Sleep, Hydration) with animated procedural Monkey Mascot,
/// Smart Briefing audio trigger, and a rich Executive Multi-Hub Digest summarizing biometrics,
/// habits, wealth, tasks, and news.
public struct DailyFoldableCompanionPane: View {
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var healthService = HealthDataService.shared
    @ObservedObject private var habitsService = HabitsService.shared
    @ObservedObject private var financeService = FinanceService.shared
    @ObservedObject private var tagdosStore = TagdosStore.shared
    @ObservedObject private var newsService = NewsService.shared
    @ObservedObject private var weatherService = WeatherService.shared
    @ObservedObject private var briefingService = SmartBriefingService.shared
    @ObservedObject private var settingsService = SettingsService.shared
    
    public let onOpenHub: (NavigationTab) -> Void
    public let onOpenBriefing: () -> Void
    
    public init(
        onOpenHub: @escaping (NavigationTab) -> Void,
        onOpenBriefing: @escaping () -> Void
    ) {
        self.onOpenHub = onOpenHub
        self.onOpenBriefing = onOpenBriefing
    }
    
    private func triggerHaptic() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
    
    // MARK: - Diurnal Greetings
    private var timeSlot: BriefingTimeSlot {
        BriefingTimeSlot.current()
    }
    
    private var firstName: String {
        let fullName = authService.currentUser?.fullName ?? authService.currentUser?.email ?? "Friend"
        return fullName.components(separatedBy: " ").first ?? fullName
    }
    
    private var diurnalGreeting: (title: String, badge: String, icon: String, badgeColor: Color) {
        switch timeSlot {
        case .morning:
            return ("Good morning, \(firstName)!", "MORNING PULSE", "sun.horizon.fill", Color(hex: "#FFB300"))
        case .intraday:
            return ("Good afternoon, \(firstName)!", "AFTERNOON FOCUS", "sun.max.fill", Color(hex: "#FF9100"))
        case .evening:
            return ("Enjoy a restful evening, \(firstName)!", "EVENING REVIEW", "sunset.fill", Color(hex: "#AB47BC"))
        case .nightly:
            return ("Sleep tight & rest well!", "NIGHT RECOVERY", "moon.stars.fill", Color(hex: "#5C6BC0"))
        }
    }
    
    private var formattedDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: Date())
    }
    
    private var currentMood: MonkeyMood {
        switch healthService.currentStressLevel {
        case .restful: return .zen
        case .calm: return .curious
        case .moderate: return .busy
        case .high: return .overheated
        }
    }
    
    // MARK: - Body
    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                // 1. Diurnal Wish Header
                diurnalHeader
                    .padding(.top, 4)
                
                // 2. Hero Tile: Concentric Recovery Rings & Mascot
                concentricHeroTile
                
                // 3. Smart Briefing Intelligence Trigger
                briefingTriggerCard
                
                // 4. Executive Multi-Hub Digest Grid
                executiveDigestSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 110) // Clearance for ergonomics
        }
        .scrollBounceBehavior(.always, axes: .vertical)
    }
    
    // MARK: - 1. Diurnal Header
    private var diurnalHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: diurnalGreeting.icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(diurnalGreeting.badgeColor)
                    
                    Text(diurnalGreeting.badge)
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(1.0)
                        .foregroundColor(diurnalGreeting.badgeColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(diurnalGreeting.badgeColor.opacity(0.16))
                .clipShape(Capsule())
                
                Text(diurnalGreeting.title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Text(formattedDateString)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(height: 56)
    }
    
    // MARK: - 2. Concentric Recovery Rings & Mascot Hero Tile
    private var concentricHeroTile: some View {
        GlassCard(cornerRadius: 24, padding: 18) {
            VStack(spacing: 16) {
                ZStack {
                    // Outer Ring: Steps Progress (Orange)
                    let stepsGoal: Double = 10000
                    let stepsProgress = min(max(Double(healthService.totalStepsToday) / stepsGoal, 0.0), 1.0)
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 9)
                        .frame(width: 172, height: 172)
                    Circle()
                        .trim(from: 0, to: stepsProgress)
                        .stroke(
                            LinearGradient(
                                colors: [Color(hex: "#FF9100"), Color(hex: "#FF5722")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 9, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 172, height: 172)
                        .animation(.spring(response: 0.8, dampingFraction: 0.7), value: stepsProgress)
                    
                    // Middle Ring: Sleep Recovery (Purple)
                    let sleepScore = Double(healthService.primarySleepSession?.sleepScore ?? 75)
                    let sleepProgress = min(max(sleepScore / 100.0, 0.0), 1.0)
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 9)
                        .frame(width: 148, height: 148)
                    Circle()
                        .trim(from: 0, to: sleepProgress)
                        .stroke(
                            LinearGradient(
                                colors: [Color(hex: "#8B5CF6"), Color(hex: "#A855F7")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 9, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 148, height: 148)
                        .animation(.spring(response: 0.8, dampingFraction: 0.7), value: sleepProgress)
                    
                    // Inner Ring: Hydration Progress (Cyan)
                    let waterGoal = max(habitsService.waterGoal, 1000)
                    let waterProgress = min(max(habitsService.waterTotalToday / waterGoal, 0.0), 1.0)
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 9)
                        .frame(width: 124, height: 124)
                    Circle()
                        .trim(from: 0, to: waterProgress)
                        .stroke(
                            LinearGradient(
                                colors: [Color(hex: "#00E5FF"), Color(hex: "#00B0FF")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 9, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 124, height: 124)
                        .animation(.spring(response: 0.8, dampingFraction: 0.7), value: waterProgress)
                    
                    // Center Mascot with Live Stress Representation
                    VStack(spacing: 2) {
                        MonkeyMascotView(
                            mood: currentMood,
                            size: .mini,
                            animated: true
                        )
                        
                        let bpm = Int(healthService.restingBpm > 0 ? healthService.restingBpm : healthService.averageBpm)
                        Text(bpm > 0 ? "\(bpm) BPM" : "Restful")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
                .frame(width: 180, height: 180)
                
                // Telemetry Legend Row
                HStack(spacing: 12) {
                    legendPill(
                        icon: "figure.walk",
                        value: "\(healthService.totalStepsToday.formatted())",
                        unit: "steps",
                        color: Color(hex: "#FF9100"),
                        action: { onOpenHub(.health) }
                    )
                    
                    let sleepHours = String(format: "%.1fh", Double(healthService.primarySleepSession?.asleepSeconds ?? 27000) / 3600.0)
                    legendPill(
                        icon: "moon.fill",
                        value: sleepHours,
                        unit: "sleep",
                        color: Color(hex: "#8B5CF6"),
                        action: {
                            HealthDataService.shared.activeSubTab = .sleep
                            onOpenHub(.health)
                        }
                    )
                    
                    legendPill(
                        icon: "drop.fill",
                        value: "\(Int(habitsService.waterTotalToday))",
                        unit: "ml",
                        color: Color(hex: "#00E5FF"),
                        action: { onOpenHub(.habits) }
                    )
                }
            }
        }
    }
    
    private func legendPill(icon: String, value: String, unit: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: {
            triggerHaptic()
            action()
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(color)
                
                Text(value)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text(unit)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - 3. Smart Briefing Trigger Card
    private var briefingTriggerCard: some View {
        Button(action: {
            triggerHaptic()
            onOpenBriefing()
        }) {
            GlassCard(cornerRadius: 20, padding: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "#6366F1"), Color(hex: "#8B5CF6")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 42, height: 42)
                        
                        Image(systemName: "sparkles")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Daily Intelligence Pulse")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        let briefingPreview = briefingService.activeBriefing?.narrative.greeting.isEmpty == false
                            ? (briefingService.activeBriefing?.narrative.greeting ?? "")
                            : (briefingService.activeBriefing?.narrative.closingWish ?? "Tap to listen or read your personalized briefing digest.")
                        
                        Text(briefingPreview)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - 4. Executive Multi-Hub Digest Cards
    private var executiveDigestSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Health & Vitals
                digestCard(
                    title: "Health & Vitals",
                    icon: "heart.fill",
                    accentColor: Color(hex: "#FF5252"),
                    metric: "\(healthService.totalStepsToday.formatted()) steps",
                    detail: "\(Int(healthService.totalActiveCalories)) kcal • \(Int(healthService.restingBpm > 0 ? healthService.restingBpm : healthService.averageBpm)) bpm",
                    action: { onOpenHub(.health) }
                )
                
                // Habits & Routines
                let waterPct = Int(min(habitsService.waterTotalToday / max(habitsService.waterGoal, 1), 1.0) * 100)
                digestCard(
                    title: "Habits & Water",
                    icon: "drop.fill",
                    accentColor: Color(hex: "#00E5FF"),
                    metric: "\(Int(habitsService.waterTotalToday)) / \(Int(habitsService.waterGoal)) ml",
                    detail: "\(waterPct)% reached • \(habitsService.smokesFinancials.daysTracked)d tracked",
                    action: { onOpenHub(.habits) }
                )
            }
            
            HStack(spacing: 12) {
                // Smart Ledger & Finances
                digestCard(
                    title: "Smart Ledger",
                    icon: "dollarsign.circle.fill",
                    accentColor: Color(hex: "#10B981"),
                    metric: formatCurrency(financeService.summary.netWorth),
                    detail: "\(financeService.transactions.count) txns • \(financeService.accounts.count) accounts",
                    action: { onOpenHub(.finances) }
                )
                
                // Tagdos & Tasks
                let pendingCount = tagdosStore.streams.flatMap(\.clusters).flatMap(\.pills).filter { !$0.isCompleted }.count
                let notesCount = tagdosStore.quickNotes.count
                digestCard(
                    title: "Tagdos & Notes",
                    icon: "checklist",
                    accentColor: Color(hex: "#F59E0B"),
                    metric: "\(pendingCount) pending",
                    detail: "\(notesCount) notes • \(tagdosStore.streams.count) streams",
                    action: { onOpenHub(.tagdos) }
                )
            }
            
            HStack(spacing: 12) {
                // Curated News
                let topHeadline = newsService.articles.first?.title ?? "Feed up to date"
                digestCard(
                    title: "Curated News",
                    icon: "newspaper.fill",
                    accentColor: Color(hex: "#38BDF8"),
                    metric: "\(newsService.articles.count) stories",
                    detail: topHeadline,
                    action: { onOpenHub(.news) }
                )
                
                // Weather Radar
                let temp = weatherService.currentWeather?.main.temp ?? 21.0
                let cond = weatherService.currentWeather?.weather.first?.main ?? "Clear"
                digestCard(
                    title: "Weather Radar",
                    icon: "cloud.sun.fill",
                    accentColor: Color(hex: "#FBBF24"),
                    metric: "\(Int(round(temp)))°C",
                    detail: "\(cond) • \(weatherService.currentLocationName)",
                    action: { onOpenHub(.weather) }
                )
            }
        }
    }
    
    private func digestCard(
        title: String,
        icon: String,
        accentColor: Color,
        metric: String,
        detail: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            triggerHaptic()
            action()
        }) {
            GlassCard(cornerRadius: 18, padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(accentColor)
                        
                        Text(title)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                        
                        Spacer()
                        
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    
                    Text(metric)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(detail)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
    
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }
}
