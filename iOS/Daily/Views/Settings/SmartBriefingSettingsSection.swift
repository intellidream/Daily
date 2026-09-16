import SwiftUI
import DailyCore
#if canImport(UIKit)
import UIKit
#endif

/// Liquid Glass settings card configuring Smart Briefings across 4 daily slots,
/// automatic morning launch presentation, and optional Google Gemini API key integration.
public struct SmartBriefingSettingsSection: View {
    @ObservedObject private var settingsService = SettingsService.shared
    @State private var apiKeyInput: String = ""
    @State private var showingPreviewSheet: Bool = false
    @State private var isSavedFeedback: Bool = false

    public init() {}

    public var body: some View {
        GlassCard(cornerRadius: 18, padding: 18) {
            VStack(alignment: .leading, spacing: 18) {
                // Header
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(ThemeColors.accentCyan)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(ThemeColors.accentCyan.opacity(0.15))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Smart Briefing & AI")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        Text("Cross-platform periodic intelligence summary")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundColor(ThemeColors.textSecondary)
                    }

                    Spacer()

                    Text("Standard")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundColor(ThemeColors.accentCyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(ThemeColors.accentCyan.opacity(0.14))
                        )
                }

                Divider()
                    .background(Color.white.opacity(0.12))

                // Toggle: Enable Smart Briefings
                Toggle(isOn: Binding(
                    get: { settingsService.settings.smartBriefingEnabled },
                    set: { val in
                        triggerHaptic()
                        settingsService.update { $0.smartBriefingEnabled = val }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Periodic Briefings")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                        Text("Synthesizes Weather, Health, Habits, Finances, and TagDoS across 4 daily slots.")
                            .font(.system(size: 11.5, weight: .regular, design: .rounded))
                            .foregroundColor(ThemeColors.textSecondary)
                    }
                }
                .tint(ThemeColors.accentCyan)

                // Toggle: Automatic Morning Presentation
                Toggle(isOn: Binding(
                    get: { settingsService.settings.smartBriefingAutoMorning },
                    set: { val in
                        triggerHaptic()
                        settingsService.update { $0.smartBriefingAutoMorning = val }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatic Morning Pop-up")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                        Text("Presents automatically between 05:00 and 11:59 once all data sources finish loading.")
                            .font(.system(size: 11.5, weight: .regular, design: .rounded))
                            .foregroundColor(ThemeColors.textSecondary)
                    }
                }
                .tint(ThemeColors.accentCyan)
                .disabled(!settingsService.settings.smartBriefingEnabled)

                Divider()
                    .background(Color.white.opacity(0.12))

                // Optional Gemini Flash API Key
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Google Gemini Cloud AI (Optional)", systemImage: "bolt.badge.clock.fill")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(ThemeColors.accentBlue)

                        Spacer()

                        if settingsService.settings.geminiApiKey?.isEmpty == false {
                            Text("Active")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(ThemeColors.success)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(ThemeColors.success.opacity(0.15)))
                        }
                    }

                    Text("DayOne uses fast on-device synthesis (<10ms) by default. Entering a Gemini API key upgrades briefings with generative nuance under a guaranteed 3.5s timeout.")
                        .font(.system(size: 11.5, weight: .regular, design: .rounded))
                        .foregroundColor(ThemeColors.textSecondary)

                    HStack(spacing: 8) {
                        SecureField("AIzaSy... (Gemini API Key)", text: $apiKeyInput)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )

                        Button {
                            triggerHaptic()
                            settingsService.update { $0.geminiApiKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines) }
                            withAnimation {
                                isSavedFeedback = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation {
                                    isSavedFeedback = false
                                }
                            }
                        } label: {
                            Text(isSavedFeedback ? "Saved!" : "Save")
                                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(isSavedFeedback ? ThemeColors.success : ThemeColors.accentBlue)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Preview Current Briefing Button
                Button {
                    triggerHaptic()
                    showingPreviewSheet = true
                } label: {
                    HStack {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Preview Current Briefing")
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(ThemeColors.accentCyan)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(ThemeColors.accentCyan.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(ThemeColors.accentCyan.opacity(0.25), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showingPreviewSheet) {
                    SmartBriefingOverlayView()
                }
            }
        }
        .onAppear {
            self.apiKeyInput = settingsService.settings.geminiApiKey ?? ""
        }
    }

    private func triggerHaptic() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
}
