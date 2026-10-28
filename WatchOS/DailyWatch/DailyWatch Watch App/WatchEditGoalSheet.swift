import SwiftUI
import WatchKit

struct WatchEditGoalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = WatchHabitStore.shared
    
    let isWater: Bool
    @State private var crownValue: Double
    
    init(isWater: Bool) {
        self.isWater = isWater
        let initial = isWater ? Double(WatchHabitStore.shared.waterGoal) : Double(WatchHabitStore.shared.smokesBaseline)
        _crownValue = State(initialValue: initial)
    }
    
    var body: some View {
        VStack(spacing: 12) {
            Text(isWater ? "Edit Water Goal" : "Edit Daily Baseline")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(isWater ? .cyan : .red)
                .padding(.top, 4)
            
            VStack(spacing: 2) {
                Text("\(Int(crownValue))")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text(isWater ? "ml per day" : "cigarettes / day")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
            
            HStack(spacing: 12) {
                Button(action: {
                    dismiss()
                }) {
                    Text("Cancel")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    if isWater {
                        store.updateWaterGoal(Int(crownValue))
                    } else {
                        store.updateSmokesBaseline(Int(crownValue))
                    }
                    dismiss()
                }) {
                    Text("Save")
                        .font(.system(size: 12, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(isWater ? Color.cyan : Color.red)
                        .foregroundColor(isWater ? .black : .white)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
        }
        .focusable()
        .digitalCrownRotation(
            $crownValue,
            from: isWater ? 500.0 : 1.0,
            through: isWater ? 6000.0 : 100.0,
            by: isWater ? 100.0 : 1.0,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
    }
}
