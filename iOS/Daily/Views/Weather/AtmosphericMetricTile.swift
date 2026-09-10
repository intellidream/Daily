import SwiftUI
import DailyCore

/// Reusable Liquid Glass atmospheric metric tile (Wind, Humidity, Pressure, etc.)
public struct AtmosphericMetricTile: View {
    public let iconName: String
    public let title: String
    public let value: String
    public let unit: String?
    public let subtitle: String?
    public let accentColor: Color

    public init(
        iconName: String,
        title: String,
        value: String,
        unit: String? = nil,
        subtitle: String? = nil,
        accentColor: Color = ThemeColors.accentCyan
    ) {
        self.iconName = iconName
        self.title = title
        self.value = value
        self.unit = unit
        self.subtitle = subtitle
        self.accentColor = accentColor
    }

    public var body: some View {
        GlassCard(cornerRadius: 18, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                // Header with icon and title
                HStack(spacing: 6) {
                    Image(systemName: iconName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(accentColor)
                    
                    Text(title.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .tracking(0.8)
                }

                // Main Metric Value
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    if let unit = unit {
                        Text(unit)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                // Subtitle / context description
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
