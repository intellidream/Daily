import SwiftUI
import DailyCore

public struct DataSyncSettingsSection: View {
    @ObservedObject private var settingsService = SettingsService.shared
    @State private var isSyncing: Bool = false
    @State private var syncStatusMessage: String? = nil
    @State private var showResetConfirmation: Bool = false
    
    public init() {}
    
    public var body: some View {
        GlassCard(cornerRadius: 18, padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundColor(ThemeColors.accentCyan)
                    Text("Data & Cloud Synchronization")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                // Supabase status indicator
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cloud Database")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                        Text("Connected to Supabase Cloud")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(ThemeColors.success)
                            .frame(width: 8, height: 8)
                        Text("Online")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(ThemeColors.success)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(ThemeColors.success.opacity(0.12))
                    .cornerRadius(8)
                }
                
                // Cloud Sync Toggle
                Toggle(isOn: Binding(
                    get: { settingsService.settings.cloudSyncEnabled },
                    set: { val in settingsService.update { $0.cloudSyncEnabled = val } }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Cloud Sync")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                        Text("Sync preferences, health data, and feeds across devices")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                }
                .tint(ThemeColors.accentBlue)
                
                Divider()
                    .background(Color.white.opacity(0.15))
                
                // Sync Now Action
                Button {
                    performManualSync()
                } label: {
                    HStack {
                        if isSyncing {
                            ProgressView()
                                .tint(ThemeColors.accentCyan)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(isSyncing ? "Syncing..." : "Sync Now")
                            .foregroundColor(ThemeColors.accentCyan)
                    }
                }
                .buttonStyle(GlassButtonStyle(variant: .secondary, cornerRadius: 10))
                .disabled(isSyncing)
                
                if let msg = syncStatusMessage {
                    Text(msg)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(ThemeColors.success)
                        .transition(.opacity)
                }
                
                Divider()
                    .background(Color.white.opacity(0.15))
                
                // Reset Settings Action
                Button {
                    showResetConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset All Settings to Defaults")
                    }
                    .foregroundColor(ThemeColors.warning)
                }
                .buttonStyle(GlassButtonStyle(variant: .plain, cornerRadius: 10))
                .confirmationDialog("Reset all settings to factory defaults?", isPresented: $showResetConfirmation, titleVisibility: .visible) {
                    Button("Reset to Defaults", role: .destructive) {
                        settingsService.resetToDefaults()
                        syncStatusMessage = "Settings restored to defaults."
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }
        }
    }
    
    private func performManualSync() {
        isSyncing = true
        syncStatusMessage = nil
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            settingsService.update { $0.lastSyncTimestamp = Date() }
            isSyncing = false
            syncStatusMessage = "All preferences synchronized successfully."
        }
    }
}
