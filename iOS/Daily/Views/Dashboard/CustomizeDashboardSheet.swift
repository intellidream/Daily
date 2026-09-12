import SwiftUI
import DailyCore
#if canImport(UIKit)
import UIKit
#endif

/// Modal Sheet allowing users to reorder, resize, and toggle dashboard widgets.
public struct CustomizeDashboardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settingsService = SettingsService.shared
    
    @State private var widgets: [DashboardWidgetConfig] = []
    
    public init() {}
    
    private func triggerHaptic() {
        if settingsService.settings.hapticsEnabled {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
        }
    }
    
    public var body: some View {
        NavigationStack {
            LiquidGlassBackground {
                ScrollView {
                    VStack(spacing: 20) {
                        // Header Guidance Card
                        GlassCard(cornerRadius: 16, padding: 14) {
                            HStack(spacing: 12) {
                                Image(systemName: "hand.tap.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(ThemeColors.accentCyan)
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Personalize Your Dashboard")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                    Text("Change widget sizes or reorder them. Layouts are automatically saved across app restarts.")
                                        .font(.system(size: 12))
                                        .foregroundColor(ThemeColors.fgMutedDark)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Widget Items List
                        VStack(spacing: 12) {
                            ForEach(widgets.indices, id: \.self) { index in
                                widgetConfigRow(index: index)
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Reset to Factory Default Button
                        Button {
                            triggerHaptic()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                widgets = DashboardWidgetConfig.defaultLayout
                                settingsService.update { $0.dashboardWidgets = widgets }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Reset to Default Layout")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(ThemeColors.accentPink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(ThemeColors.accentPink.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(ThemeColors.accentPink.opacity(0.3), lineWidth: 1)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 40)
                    }
                    .padding(.top, 14)
                }
            }
            .navigationTitle("Customize Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(ThemeColors.accentCyan)
                }
            }
            .onAppear {
                widgets = settingsService.settings.dashboardWidgets
            }
        }
    }
    
    @ViewBuilder
    private func widgetConfigRow(index: Int) -> some View {
        let config = widgets[index]
        let type = DashboardWidgetType(rawValue: config.id)
        
        GlassCard(cornerRadius: 16, padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    // Widget Icon & Title
                    Image(systemName: type?.iconName ?? "square.grid.2x2.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(ThemeColors.accentCyan)
                        .frame(width: 24)
                    
                    Text(type?.title ?? config.id.capitalized)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    // Move Up / Down Buttons
                    HStack(spacing: 6) {
                        Button {
                            guard index > 0 else { return }
                            triggerHaptic()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                widgets.swapAt(index, index - 1)
                                settingsService.update { $0.dashboardWidgets = widgets }
                            }
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(index > 0 ? .white : .white.opacity(0.25))
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Circle())
                        }
                        .disabled(index == 0)
                        
                        Button {
                            guard index < widgets.count - 1 else { return }
                            triggerHaptic()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                widgets.swapAt(index, index + 1)
                                settingsService.update { $0.dashboardWidgets = widgets }
                            }
                        } label: {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(index < widgets.count - 1 ? .white : .white.opacity(0.25))
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Circle())
                        }
                        .disabled(index == widgets.count - 1)
                    }
                }
                
                Divider()
                    .background(Color.white.opacity(0.10))
                
                // Size Picker Segmented Control
                VStack(alignment: .leading, spacing: 6) {
                    Text("SIZE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                    
                    HStack(spacing: 6) {
                        ForEach(DashboardWidgetSize.allCases, id: \.self) { size in
                            let isSelected = config.size == size
                            Button {
                                triggerHaptic()
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    widgets[index].size = size
                                    settingsService.update { $0.dashboardWidgets = widgets }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: size.iconName)
                                        .font(.system(size: 10, weight: .bold))
                                    Text(size.displayName)
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .foregroundColor(isSelected ? .white : ThemeColors.fgMutedDark)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(isSelected ? ThemeColors.accentCyan.opacity(0.28) : Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay {
                                    if isSelected {
                                        RoundedRectangle(cornerRadius: 10)
                                            .strokeBorder(ThemeColors.accentCyan.opacity(0.6), lineWidth: 1)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}
