import SwiftUI
import DailyCore
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Liquid Glass Settings section for unlocking, configuring, and reviewing Loreen Veil.
public struct LoreenVeilSettingsSection: View {
    @ObservedObject private var settingsService = SettingsService.shared
    @State private var showInitiationSheet = false
    @State private var showCodexSheet = false
    @State private var showRelockAlert = false

    public init() {}

    private var settings: AppSettings {
        settingsService.settings
    }

    public var body: some View {
        GlassCard(cornerRadius: 18, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: settings.loreenVeilUnlocked ? "eye.slash.fill" : "lock.shield.fill")
                        .foregroundColor(settings.loreenVeilEnabled ? ThemeColors.accentCyan : ThemeColors.accentPurple)
                    Text("Loreen Veil")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)

                    Spacer()

                    Text(statusLabel)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(statusColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(statusColor.opacity(0.15))
                        .clipShape(Capsule())
                }

                if !settings.loreenVeilUnlocked {
                    Text("Visual Privacy Shield for Tagdos & Notes. Demonstrate fluency in Loreen Script to unlock.")
                        .font(.system(size: 12))
                        .foregroundColor(ThemeColors.fgMutedDark)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        showInitiationSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "pencil.tip.crop.circle")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Prove Fluency to Unlock")
                                .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(ThemeColors.accentCyan)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else {
                    Toggle("Enable Loreen Veil", isOn: Binding(
                        get: { settings.loreenVeilEnabled },
                        set: { newVal in
                            settingsService.update { $0.loreenVeilEnabled = newVal }
                            reloadWidgets()
                        }
                    ))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .tint(ThemeColors.accentCyan)

                    // Live 120Hz Morph Preview Strip
                    HStack(spacing: 8) {
                        Image(systemName: settings.loreenVeilEnabled ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(settings.loreenVeilEnabled ? ThemeColors.accentCyan : ThemeColors.accentPurple)
                        LoreenVeilText(
                            "Loreen — Secretele tale în siguranță",
                            isVeiled: settings.loreenVeilEnabled,
                            size: 13.5,
                            weight: .semibold,
                            design: .rounded
                        )
                        .foregroundColor(.white.opacity(0.92))
                        .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(
                                        (settings.loreenVeilEnabled ? ThemeColors.accentCyan : ThemeColors.accentPurple).opacity(0.32),
                                        lineWidth: 1
                                    )
                            )
                    )

                    Divider().background(Color.white.opacity(0.12))

                    VStack(spacing: 10) {
                        Toggle("Shield Tagdos Streams & Pills", isOn: Binding(
                            get: { settings.loreenVeilApplyToTagdos },
                            set: { newVal in
                                settingsService.update { $0.loreenVeilApplyToTagdos = newVal }
                                reloadWidgets()
                            }
                        ))
                        .font(.system(size: 13))
                        .foregroundColor(Color.white.opacity(0.88))
                        .tint(ThemeColors.accentPurple)

                        Toggle("Shield Active Memos & Quick Notes", isOn: Binding(
                            get: { settings.loreenVeilApplyToNotes },
                            set: { newVal in
                                settingsService.update { $0.loreenVeilApplyToNotes = newVal }
                            }
                        ))
                        .font(.system(size: 13))
                        .foregroundColor(Color.white.opacity(0.88))
                        .tint(ThemeColors.accentPurple)

                        Toggle("Shield Home & Lock Widgets", isOn: Binding(
                            get: { settings.loreenVeilApplyToWidgets },
                            set: { newVal in
                                settingsService.update { $0.loreenVeilApplyToWidgets = newVal }
                                reloadWidgets()
                            }
                        ))
                        .font(.system(size: 13))
                        .foregroundColor(Color.white.opacity(0.88))
                        .tint(ThemeColors.accentPurple)

                        Toggle("Require Face ID to Reveal", isOn: Binding(
                            get: { settings.loreenVeilRequireBiometricsForPeek },
                            set: { newVal in
                                settingsService.update { $0.loreenVeilRequireBiometricsForPeek = newVal }
                            }
                        ))
                        .font(.system(size: 13))
                        .foregroundColor(Color.white.opacity(0.88))
                        .tint(ThemeColors.accentCyan)
                    }

                    Divider().background(Color.white.opacity(0.12))

                    HStack(spacing: 10) {
                        Button {
                            showCodexSheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "book.closed.fill")
                                    .font(.system(size: 12))
                                Text("Loreen Codex & Docs")
                                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(ThemeColors.accentCyan)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(ThemeColors.accentCyan.opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            showRelockAlert = true
                        } label: {
                            Image(systemName: "lock.rotation")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color.white.opacity(0.65))
                                .padding(9)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Re-lock Loreen Veil")
                    }
                }
            }
        }
        .sheet(isPresented: $showInitiationSheet) {
            LoreenInitiationSheet {
                settingsService.update {
                    $0.loreenVeilUnlocked = true
                    $0.loreenVeilEnabled = true
                }
                reloadWidgets()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCodexSheet) {
            LoreenCodexView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert("Re-lock Loreen Veil?", isPresented: $showRelockAlert) {
            Button("Re-lock", role: .destructive) {
                settingsService.update {
                    $0.loreenVeilUnlocked = false
                    $0.loreenVeilEnabled = false
                }
                reloadWidgets()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will need to pass the Loreen Initiation handwriting check again to re-enable Loreen Veil.")
        }
    }

    private var statusLabel: String {
        if !settings.loreenVeilUnlocked { return "Locked" }
        return settings.loreenVeilEnabled ? "Active" : "Ready"
    }

    private var statusColor: Color {
        if !settings.loreenVeilUnlocked { return ThemeColors.accentPurple }
        return settings.loreenVeilEnabled ? ThemeColors.accentGreen : ThemeColors.accentCyan
    }

    private func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetDataCoordinator.WidgetKind.tagdos)
        #endif
    }
}
