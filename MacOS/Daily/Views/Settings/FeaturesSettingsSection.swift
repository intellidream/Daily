import SwiftUI
import WebKit
import DailyCore

public struct FeaturesSettingsSection: View {
    @ObservedObject private var settingsService = SettingsService.shared
    @ObservedObject private var habitsService = HabitsService.shared
    
    @State private var showMediumLoginSheet = false
    @State private var clearMediumSessionBeforeLogin = false
    @State private var hasActiveMediumSession = false
    @State private var showDisconnectMediumAlert = false
    
    @State private var showSubstackLoginSheet = false
    @State private var clearSubstackSessionBeforeLogin = false
    @State private var hasActiveSubstackSession = false
    @State private var showDisconnectSubstackAlert = false
    
    public init() {}
    
    public var body: some View {
        GlassCard(cornerRadius: 18, padding: 18) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(ThemeColors.accentCyan)
                    Text("Features Configuration")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                weatherSection
                Divider().background(Color.white.opacity(0.15))
                healthSection
                Divider().background(Color.white.opacity(0.15))
                habitsSection
                Divider().background(Color.white.opacity(0.15))
                smokesSection
                Divider().background(Color.white.opacity(0.15))
                newsSection
                Divider().background(Color.white.opacity(0.15))
                mediumSection
                Divider().background(Color.white.opacity(0.15))
                substackSection
            }
        }
        .task {
            await refreshSessions()
        }
        .onChange(of: showMediumLoginSheet) { _, isPresented in
            if !isPresented {
                Task {
                    hasActiveMediumSession = await HeadlessReadabilityParser.shared.hasAuthenticatedMediumSession()
                }
            }
        }
        .onChange(of: showSubstackLoginSheet) { _, isPresented in
            if !isPresented {
                Task {
                    hasActiveSubstackSession = await HeadlessReadabilityParser.shared.hasAuthenticatedSubstackSession()
                }
            }
        }
        .sheet(isPresented: $showMediumLoginSheet) {
            MediumLoginSheet(clearExistingSession: clearMediumSessionBeforeLogin)
        }
        .sheet(isPresented: $showSubstackLoginSheet) {
            SubstackLoginSheet(clearExistingSession: clearSubstackSessionBeforeLogin)
        }
        .alert("Disconnect Medium", isPresented: $showDisconnectMediumAlert) {
            Button("Disconnect", role: .destructive) {
                settingsService.update {
                    $0.newsMediumUsername = nil
                    $0.newsMediumReadingListUrl = nil
                }
                hasActiveMediumSession = false
                Task {
                    let cookieStore = WKWebsiteDataStore.default().httpCookieStore
                    let cookies = await cookieStore.allCookies()
                    for cookie in cookies where cookie.domain.lowercased().contains("medium.com") {
                        await cookieStore.deleteCookie(cookie)
                    }
                    await ArticleExtractor.clearCache()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to disconnect your Medium account and remove your reading list?")
        }
        .alert("Disconnect Substack", isPresented: $showDisconnectSubstackAlert) {
            Button("Disconnect", role: .destructive) {
                settingsService.update {
                    $0.newsSubstackUsername = nil
                }
                hasActiveSubstackSession = false
                Task {
                    let cookieStore = WKWebsiteDataStore.default().httpCookieStore
                    let cookies = await cookieStore.allCookies()
                    for cookie in cookies where cookie.domain.lowercased().contains("substack.com") {
                        await cookieStore.deleteCookie(cookie)
                    }
                    await ArticleExtractor.clearCache()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to disconnect your Substack account?")
        }
    }
    
    private func refreshSessions() async {
        hasActiveMediumSession = await HeadlessReadabilityParser.shared.hasAuthenticatedMediumSession()
        hasActiveSubstackSession = await HeadlessReadabilityParser.shared.hasAuthenticatedSubstackSession()
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private var weatherSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WEATHER")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(ThemeColors.accentCyan)
            
            Toggle(isOn: Binding(
                get: { settingsService.settings.weatherAlwaysAutoLocation },
                set: { val in settingsService.update { $0.weatherAlwaysAutoLocation = val } }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-Location Detection")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    Text("Always detect current coordinates on startup")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
            }
            .tint(ThemeColors.accentBlue)
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Measurement Units")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(ThemeColors.fgMutedDark)
                
                Picker("Unit System", selection: Binding(
                    get: { settingsService.settings.weatherUnitSystem },
                    set: { val in settingsService.update { $0.weatherUnitSystem = val } }
                )) {
                    ForEach(WeatherUnitSystem.allCases, id: \.self) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }
    
    @ViewBuilder
    private var healthSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HEALTH & VITALS")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(ThemeColors.accentCyan)
            
            Toggle(isOn: Binding(
                get: { settingsService.settings.healthMockDataEnabled },
                set: { val in settingsService.update { $0.healthMockDataEnabled = val } }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mock Health Store")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    Text("Simulate vitals history for development")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
            }
            .tint(ThemeColors.accentBlue)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Target Sleep Duration")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Text(String(format: "%.1fh", settingsService.settings.healthSleepTargetHours))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(ThemeColors.accentCyan)
                }
                
                Slider(
                    value: Binding(
                        get: { settingsService.settings.healthSleepTargetHours },
                        set: { val in
                            let rounded = (val * 2).rounded() / 2
                            settingsService.update { $0.healthSleepTargetHours = rounded }
                        }
                    ),
                    in: 6.0...10.0,
                    step: 0.5
                )
                .tint(ThemeColors.accentBlue)
            }
        }
    }
    
    @ViewBuilder
    private var habitsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HABITS & HYDRATION")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(ThemeColors.accentCyan)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Daily Hydration Target")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Text(String(format: "%.2fL", settingsService.settings.habitsWaterTargetLiters))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(ThemeColors.accentCyan)
                }
                
                Slider(
                    value: Binding(
                        get: { settingsService.settings.habitsWaterTargetLiters },
                        set: { val in
                            let rounded = (val * 4).rounded() / 4
                            settingsService.update { $0.habitsWaterTargetLiters = rounded }
                            Task { await habitsService.updateWaterGoal(rounded * 1000) }
                        }
                    ),
                    in: 1.0...4.0,
                    step: 0.25
                )
                .tint(ThemeColors.accentBlue)
            }
            
            Toggle(isOn: Binding(
                get: { settingsService.settings.habitsRemindersEnabled },
                set: { val in settingsService.update { $0.habitsRemindersEnabled = val } }
            )) {
                Text("Habit Logging Reminders")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
            }
            .tint(ThemeColors.accentBlue)
        }
    }
    
    @ViewBuilder
    private var smokesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TOBACCO & SMOKES REDUCTION")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color(hex: "#FF6B6B"))
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily Baseline")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    Text("Target ceiling before quitting")
                        .font(.system(size: 11))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
                Spacer()
                Stepper("\(habitsService.smokesSettings.baselineCigsPerDay) cigs", value: Binding(
                    get: { habitsService.smokesSettings.baselineCigsPerDay },
                    set: { val in
                        var s = habitsService.smokesSettings
                        s.baselineCigsPerDay = max(0, val)
                        Task { await habitsService.updateSmokesSettings(s) }
                    }
                ), in: 0...100)
                .labelsHidden()
                
                Text("\(habitsService.smokesSettings.baselineCigsPerDay)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "#FF6B6B"))
                    .frame(minWidth: 28, alignment: .trailing)
            }
            
            HStack {
                Text("Cigarettes per Pack")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
                Stepper("\(habitsService.smokesSettings.cigsPerPack)", value: Binding(
                    get: { habitsService.smokesSettings.cigsPerPack },
                    set: { val in
                        var s = habitsService.smokesSettings
                        s.cigsPerPack = max(1, val)
                        Task { await habitsService.updateSmokesSettings(s) }
                    }
                ), in: 10...50)
                .labelsHidden()
                
                Text("\(habitsService.smokesSettings.cigsPerPack)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(ThemeColors.accentCyan)
                    .frame(minWidth: 28, alignment: .trailing)
            }
            
            HStack {
                Text("Pack Cost (\(habitsService.smokesSettings.currency))")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
                Stepper(value: Binding(
                    get: { habitsService.smokesSettings.costPerPack },
                    set: { val in
                        var s = habitsService.smokesSettings
                        s.costPerPack = max(0, (val * 10).rounded() / 10)
                        Task { await habitsService.updateSmokesSettings(s) }
                    }
                ), in: 0...200, step: 0.50) {
                    EmptyView()
                }
                .labelsHidden()
                
                Text(String(format: "%.2f", habitsService.smokesSettings.costPerPack))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(ThemeColors.accentCyan)
                    .frame(minWidth: 48, alignment: .trailing)
            }
        }
    }
    
    @ViewBuilder
    private var newsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NEWS READER")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(ThemeColors.accentCyan)
            
            Toggle(isOn: Binding(
                get: { settingsService.settings.newsAutoRefreshOnStartup },
                set: { val in settingsService.update { $0.newsAutoRefreshOnStartup = val } }
            )) {
                Text("Auto-Refresh on Launch")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
            }
            .tint(ThemeColors.accentBlue)
            
            Toggle(isOn: Binding(
                get: { settingsService.settings.newsShowImages },
                set: { val in settingsService.update { $0.newsShowImages = val } }
            )) {
                Text("Display Article Cover Images")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
            }
            .tint(ThemeColors.accentBlue)
        }
    }
    
    private var mediumSection: some View {
        MediumSetupSubSection(
            settingsService: settingsService,
            hasActiveMediumSession: hasActiveMediumSession,
            showMediumLoginSheet: $showMediumLoginSheet,
            clearMediumSessionBeforeLogin: $clearMediumSessionBeforeLogin,
            showDisconnectMediumAlert: $showDisconnectMediumAlert
        )
    }
    
    private var substackSection: some View {
        SubstackSetupSubSection(
            settingsService: settingsService,
            hasActiveSubstackSession: hasActiveSubstackSession,
            showSubstackLoginSheet: $showSubstackLoginSheet,
            clearSubstackSessionBeforeLogin: $clearSubstackSessionBeforeLogin,
            showDisconnectSubstackAlert: $showDisconnectSubstackAlert
        )
    }
}

private struct MediumSetupSubSection: View {
    @ObservedObject var settingsService: SettingsService
    let hasActiveMediumSession: Bool
    @Binding var showMediumLoginSheet: Bool
    @Binding var clearMediumSessionBeforeLogin: Bool
    @Binding var showDisconnectMediumAlert: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("MEDIUM SETUP")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(ThemeColors.accentCyan)
                Spacer()
                statusBadge
            }
            
            if let username = settingsService.settings.newsMediumUsername, !username.isEmpty {
                connectedContent(username: username)
            } else {
                disconnectedContent
            }
        }
        .id("medium_setup")
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        if let username = settingsService.settings.newsMediumUsername, !username.isEmpty {
            HStack(spacing: 5) {
                Circle()
                    .fill(hasActiveMediumSession ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(hasActiveMediumSession ? "@\(username)" : "@\(username) · Session Inactive")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill((hasActiveMediumSession ? Color.green : Color.orange).opacity(0.16)))
        } else {
            Text("Not Configured")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(ThemeColors.fgMutedDark)
        }
    }
    
    @ViewBuilder
    private func connectedContent(username: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(hasActiveMediumSession
                ? "Member session active. Full Member-Only stories and your Reading List are unlocked."
                : "Reading List is configured, but your Medium browser session is inactive. Sign in once to unlock full Member-Only stories.")
                .font(.system(size: 12))
                .foregroundColor(hasActiveMediumSession ? ThemeColors.fgMutedDark : Color.orange.opacity(0.95))
            
            if !hasActiveMediumSession {
                Button {
                    clearMediumSessionBeforeLogin = false
                    showMediumLoginSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.badge.key.fill")
                        Text("Reconnect Medium Session")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(ThemeColors.accentCyan))
                }
                .buttonStyle(.plain)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Reading List URL")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                
                TextField("Reading List URL", text: Binding(
                    get: { settingsService.settings.newsMediumReadingListUrl ?? "https://medium.com/@\(username)/list/reading-list" },
                    set: { val in settingsService.update { s in s.newsMediumReadingListUrl = val } }
                ))
                .font(.system(size: 13))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        )
                )
            }
            
            HStack(spacing: 10) {
                Button {
                    clearMediumSessionBeforeLogin = hasActiveMediumSession
                    showMediumLoginSheet = true
                } label: {
                    Text("Change Account")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
                
                Button {
                    showDisconnectMediumAlert = true
                } label: {
                    Text("Disconnect")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(ThemeColors.error)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(ThemeColors.error.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    @ViewBuilder
    private var disconnectedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reading List URL will be automatically configured upon login.")
                .font(.system(size: 12))
                .foregroundColor(ThemeColors.fgMutedDark)
            
            Button {
                clearMediumSessionBeforeLogin = false
                showMediumLoginSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "link.badge.plus")
                    Text("Login to Medium")
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Capsule().fill(ThemeColors.accentCyan))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct SubstackSetupSubSection: View {
    @ObservedObject var settingsService: SettingsService
    @ObservedObject private var newsService = NewsService.shared
    let hasActiveSubstackSession: Bool
    @Binding var showSubstackLoginSheet: Bool
    @Binding var clearSubstackSessionBeforeLogin: Bool
    @Binding var showDisconnectSubstackAlert: Bool
    @State private var syncStatusMessage: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SUBSTACK SETUP")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(ThemeColors.accentCyan)
                Spacer()
                statusBadge
            }
            
            if let username = settingsService.settings.newsSubstackUsername, !username.isEmpty {
                connectedContent(username: username)
            } else {
                disconnectedContent
            }
        }
        .id("substack_setup")
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        if let username = settingsService.settings.newsSubstackUsername, !username.isEmpty {
            HStack(spacing: 5) {
                Circle()
                    .fill(hasActiveSubstackSession ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(hasActiveSubstackSession ? "@\(username)" : "@\(username) · Session Inactive")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill((hasActiveSubstackSession ? Color.green : Color.orange).opacity(0.16)))
        } else {
            Text("Not Configured")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(ThemeColors.fgMutedDark)
        }
    }
    
    @ViewBuilder
    private func connectedContent(username: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(hasActiveSubstackSession
                ? "Substack session active. Your Inbox and subscribed member posts are unlocked."
                : "Substack is linked, but your browser session is inactive. Sign in once to unlock your full Inbox and paid subscriber posts.")
                .font(.system(size: 12))
                .foregroundColor(hasActiveSubstackSession ? ThemeColors.fgMutedDark : Color.orange.opacity(0.95))
            
            if !hasActiveSubstackSession {
                Button {
                    clearSubstackSessionBeforeLogin = false
                    showSubstackLoginSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.badge.key.fill")
                        Text("Reconnect Substack Session")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(ThemeColors.accentCyan))
                }
                .buttonStyle(.plain)
            }
            
            Button {
                Task {
                    let count = await newsService.syncSubstackSubscriptions()
                    syncStatusMessage = count > 0
                        ? "Synced \(count) Substack publication\(count == 1 ? "" : "s") into News."
                        : (hasActiveSubstackSession ? "All Substack subscriptions are up to date." : "Reconnect browser session to sync private subscriptions.")
                }
            } label: {
                HStack(spacing: 6) {
                    if newsService.isSyncingSubstack {
                        ProgressView()
                            .controlSize(.small)
                            .tint(ThemeColors.accentCyan)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    Text(newsService.isSyncingSubstack ? "Syncing Subscriptions..." : "Sync Subscriptions")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(ThemeColors.accentCyan)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(ThemeColors.accentCyan.opacity(0.14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(ThemeColors.accentCyan.opacity(0.28), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(newsService.isSyncingSubstack)
            
            if let syncMsg = syncStatusMessage {
                Text(syncMsg)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(ThemeColors.accentCyan)
            }
            
            HStack(spacing: 10) {
                Button {
                    clearSubstackSessionBeforeLogin = hasActiveSubstackSession
                    showSubstackLoginSheet = true
                } label: {
                    Text("Change Account")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
                
                Button {
                    showDisconnectSubstackAlert = true
                } label: {
                    Text("Disconnect")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(ThemeColors.error)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(ThemeColors.error.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    @ViewBuilder
    private var disconnectedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connect your Substack account to read subscriber-only newsletters and access your Substack Inbox.")
                .font(.system(size: 12))
                .foregroundColor(ThemeColors.fgMutedDark)
            
            Button {
                clearSubstackSessionBeforeLogin = false
                showSubstackLoginSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "newspaper.fill")
                    Text("Connect Substack Account")
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Capsule().fill(ThemeColors.accentCyan))
            }
            .buttonStyle(.plain)
        }
    }
}
