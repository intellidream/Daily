import SwiftUI
import DailyCore

/// Prominent, high-contrast badge attributing a health metric to its originating physical device.
/// Renders a solid color-coded dot, official hardware icon (Oura Ring, Apple Watch, Pixel Watch, HealthKit, etc.),
/// and the device display name.
public struct DeviceOriginBadge: View {
    public let deviceName: String?
    public let compact: Bool
    
    public init(device: String?, compact: Bool = false) {
        self.deviceName = device
        self.compact = compact
    }
    
    public var body: some View {
        if let name = deviceName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            let source = DeviceSource.from(name: name)
            if !source.isVirtualEngine {
                let color = Color(hex: source.colorHex)
                
                HStack(spacing: compact ? 4 : 5) {
                    // 1. Color-coded dot
                    Circle()
                        .fill(color)
                        .frame(width: compact ? 6 : 7, height: compact ? 6 : 7)
                        .shadow(color: color.opacity(0.6), radius: 2)
                    
                    // 2. Hardware Icon
                    Image(systemName: source.systemImage)
                        .font(.system(size: compact ? 10 : 11, weight: .bold))
                        .foregroundColor(color)
                    
                    // 3. Device Display Name
                    Text(source.displayName)
                        .font(.system(size: compact ? 10 : 11, weight: .bold, design: .rounded))
                        .foregroundColor(color)
                        .lineLimit(1)
                }
                .padding(.horizontal, compact ? 7 : 9)
                .padding(.vertical, compact ? 3 : 4)
                .background(
                    Capsule()
                        .fill(color.opacity(0.14))
                        .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 0.8))
                )
            }
        }
    }
}
