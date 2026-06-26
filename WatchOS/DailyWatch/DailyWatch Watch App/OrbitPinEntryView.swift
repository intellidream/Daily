import SwiftUI

struct OrbitPinEntryView: View {
    @Binding var pin: String
    var onSubmit: () -> Void
    @Environment(\.dismiss) var dismiss
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        VStack(spacing: 8) {
            Text("Enter PIN")
                .font(.headline)
            
            // Display the dots for the PIN
            HStack(spacing: 12) {
                ForEach(0..<6, id: \.self) { index in
                    Circle()
                        .fill(index < pin.count ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 12, height: 12)
                }
            }
            .padding(.bottom, 4)
            
            // The Keypad
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(1...9, id: \.self) { number in
                    keypadButton(text: "\(number)") { appendDigit("\(number)") }
                }
                
                // Bottom row
                Button(action: deleteDigit) {
                    Image(systemName: "delete.left")
                        .font(.title3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
                .frame(height: 38)
                .background(Color.red.opacity(0.2))
                .cornerRadius(8)
                
                keypadButton(text: "0") { appendDigit("0") }
                
                Button(action: {
                    dismiss()
                    onSubmit()
                }) {
                    Image(systemName: "checkmark")
                        .font(.title3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
                .frame(height: 38)
                .background(pin.count == 6 ? Color.accentColor : Color.gray.opacity(0.2))
                .cornerRadius(8)
                .disabled(pin.count != 6)
            }
        }
        .padding(.horizontal, 4)
    }
    
    private func keypadButton(text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.title3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .frame(height: 38)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(8)
    }
    
    private func appendDigit(_ digit: String) {
        if pin.count < 6 {
            pin.append(digit)
            if pin.count == 6 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    dismiss()
                    onSubmit()
                }
            }
        }
    }
    
    private func deleteDigit() {
        if !pin.isEmpty {
            pin.removeLast()
        }
    }
}
