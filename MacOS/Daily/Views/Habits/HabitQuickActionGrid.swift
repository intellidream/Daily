import SwiftUI
import DailyCore
#if canImport(UIKit)
import UIKit
#endif

/// Quick logging grid for Bubbles and Smokes with tactile haptics.
public struct HabitQuickActionGrid: View {
    public let habitType: HabitType
    public let onLogWater: (WaterPreset, Int) -> Void
    public let onLogCustomWater: (Double, String) -> Void
    public let onLogSmoke: (SmokePreset, Int) -> Void
    public let onOpenCravingEmergency: () -> Void
    
    @ObservedObject private var settingsService = SettingsService.shared
    @State private var selectedMultiplier: Int = 1
    @State private var showingCustomWaterSheet = false
    @State private var customAmountText = ""
    @State private var customDrinkName = "Water"
    
    public init(
        habitType: HabitType,
        onLogWater: @escaping (WaterPreset, Int) -> Void,
        onLogCustomWater: @escaping (Double, String) -> Void = { _, _ in },
        onLogSmoke: @escaping (SmokePreset, Int) -> Void,
        onOpenCravingEmergency: @escaping () -> Void
    ) {
        self.habitType = habitType
        self.onLogWater = onLogWater
        self.onLogCustomWater = onLogCustomWater
        self.onLogSmoke = onLogSmoke
        self.onOpenCravingEmergency = onOpenCravingEmergency
    }
    
    public init(
        habitType: HabitType,
        onLogWater: @escaping (WaterPreset) -> Void,
        onLogCustomWater: @escaping (Double, String) -> Void = { _, _ in },
        onLogSmoke: @escaping (SmokePreset) -> Void,
        onOpenCravingEmergency: @escaping () -> Void
    ) {
        self.habitType = habitType
        self.onLogWater = { preset, _ in onLogWater(preset) }
        self.onLogCustomWater = onLogCustomWater
        self.onLogSmoke = { preset, _ in onLogSmoke(preset) }
        self.onOpenCravingEmergency = onOpenCravingEmergency
    }
    
    private func triggerHaptic() {
        if settingsService.settings.hapticsEnabled {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
        }
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(habitType == .water ? "QUICK INTAKE" : "QUICK LOG")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(ThemeColors.fgMutedDark)
                Spacer()
                
                // Multiplier Selector Pill Bar: 1x, 2x, 3x, 5x
                HStack(spacing: 4) {
                    ForEach([1, 2, 3, 5], id: \.self) { mult in
                        Button {
                            triggerHaptic()
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                selectedMultiplier = mult
                            }
                        } label: {
                            Text("\(mult)x")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(selectedMultiplier == mult ? .white : ThemeColors.fgMutedDark)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(selectedMultiplier == mult ? (habitType == .water ? ThemeColors.accentCyan.opacity(0.35) : Color(hex: "#FF4D4D").opacity(0.35)) : Color.white.opacity(0.06))
                                .clipShape(Capsule())
                                .overlay {
                                    if selectedMultiplier == mult {
                                        Capsule().strokeBorder(habitType == .water ? ThemeColors.accentCyan : Color(hex: "#FF4D4D"), lineWidth: 1)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                if habitType == .water {
                    Button {
                        showingCustomWaterSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 11))
                            Text("Custom")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(ThemeColors.accentCyan)
                    }
                    .padding(.leading, 4)
                }
            }
            .padding(.horizontal, 4)
            
            if habitType == .water {
                // Water Presets 2x3 Grid
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(WaterPreset.defaults) { preset in
                        Button {
                            triggerHaptic()
                            onLogWater(preset, selectedMultiplier)
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: preset.iconName)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(Color(hex: preset.colorHex))
                                
                                Text(preset.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                
                                Text("+\(Int(preset.amountMl * Double(selectedMultiplier))) ml")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(ThemeColors.accentCyan)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                // Smokes Presets 2x2 Grid + Emergency Craving Button
                VStack(spacing: 10) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(SmokePreset.defaults) { preset in
                            Button {
                                triggerHaptic()
                                onLogSmoke(preset, selectedMultiplier)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: preset.iconName)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(Color(hex: preset.colorHex))
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(preset.name)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.white)
                                        Text(selectedMultiplier > 1 ? "+\(selectedMultiplier) Logs" : "+1 Log")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(ThemeColors.fgMutedDark)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    // Craving Emergency 4D Button
                    Button {
                        triggerHaptic()
                        onOpenCravingEmergency()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(Color(hex: "#00FFB2"))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Craving Emergency Protocol (4D)")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                Text("Delay • Deep Breathe • Drink Water • Distract")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(Color.white.opacity(0.7))
                            }
                            Spacer()
                            Image(systemName: "timer")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color(hex: "#00FFB2"))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(hex: "#00FFB2").opacity(0.2),
                                    ThemeColors.accentBlue.opacity(0.25)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color(hex: "#00FFB2").opacity(0.4), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $showingCustomWaterSheet) {
            NavigationStack {
                LiquidGlassBackground {
                    VStack(spacing: 20) {
                        Text("Log Custom Hydration")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.top, 20)
                        
                        GlassCard(cornerRadius: 16, padding: 16) {
                            VStack(spacing: 14) {
                                TextField("Amount in ml (e.g. 400)", text: $customAmountText)
                                    .keyboardType(.numberPad)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(12)
                                    .background(Color.white.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                
                                TextField("Beverage (e.g. Sparkling Water, Juice)", text: $customDrinkName)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(12)
                                    .background(Color.white.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        Button {
                            if let amount = Double(customAmountText), amount > 0 {
                                triggerHaptic()
                                onLogCustomWater(amount, customDrinkName.isEmpty ? "Water" : customDrinkName)
                                showingCustomWaterSheet = false
                                customAmountText = ""
                            }
                        } label: {
                            Text("Confirm Intake")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(ThemeColors.accentCyan)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.horizontal, 20)
                        
                        Spacer()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showingCustomWaterSheet = false
                        }
                        .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
            .presentationDetents([.fraction(0.45)])
        }
    }
}
