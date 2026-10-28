import SwiftUI
import WatchKit

struct WatchCustomWaterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = WatchHabitStore.shared
    
    @State private var amountMl: Double = 250.0
    @State private var selectedDrink: String = "Glass"
    @State private var multiplier: Int = 1
    
    private let presets: [(name: String, amount: Double, icon: String, color: Color)] = [
        ("Glass", 250, "waterbottle", .cyan),
        ("Bottle", 500, "flask.fill", .blue),
        ("Tea", 250, "mug.fill", .green),
        ("Coffee", 100, "cup.and.saucer.fill", .orange),
        ("Small", 150, "drop", .cyan),
        ("Large", 300, "drop.fill", .cyan)
    ]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("Custom Water")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.cyan)
                    .padding(.top, 2)
                
                // Hero Amount Display with Crown
                VStack(spacing: 2) {
                    Text("\(Int(amountMl * Double(multiplier))) ml")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    if multiplier > 1 {
                        Text("(\(multiplier)× \(Int(amountMl)) ml \(selectedDrink))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    } else {
                        Text(selectedDrink)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
                
                // Multiplier Stepper Row
                HStack(spacing: 8) {
                    Text("Qty:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    ForEach(1...4, id: \.self) { m in
                        Button(action: {
                            WKInterfaceDevice.current().play(.click)
                            multiplier = m
                        }) {
                            Text("\(m)×")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .frame(minWidth: 28, minHeight: 24)
                                .background(multiplier == m ? Color.cyan : Color.white.opacity(0.12))
                                .foregroundColor(multiplier == m ? .black : .primary)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
                
                // Preset Grid
                VStack(spacing: 6) {
                    Text("PRESETS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        ForEach(presets, id: \.name) { p in
                            Button(action: {
                                WKInterfaceDevice.current().play(.click)
                                selectedDrink = p.name
                                amountMl = p.amount
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: p.icon)
                                        .foregroundColor(p.color)
                                        .font(.system(size: 10))
                                    Text("\(p.name)")
                                        .font(.system(size: 11, weight: .semibold))
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    Text("\(Int(p.amount))")
                                        .font(.system(size: 9, weight: .medium, design: .rounded))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 8)
                                .frame(height: 32)
                                .background(selectedDrink == p.name ? Color.cyan.opacity(0.25) : Color.white.opacity(0.10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedDrink == p.name ? Color.cyan : Color.clear, lineWidth: 1)
                                )
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                // Confirm Log Button
                Button(action: {
                    let total = Int(amountMl * Double(multiplier))
                    store.logWater(amount: total, type: selectedDrink)
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                        Text("Log \(Int(amountMl * Double(multiplier))) ml")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(Color.cyan)
                    .foregroundColor(.black)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .focusable()
        .digitalCrownRotation(
            $amountMl,
            from: 50.0,
            through: 1200.0,
            by: 25.0,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
    }
}
