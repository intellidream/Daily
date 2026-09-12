import SwiftUI
import DailyCore

/// Tactile Liquid Glass tile representing an individual health biometric with device origin attribution.
public struct VitalMetricTile: View {
    public let metricType: HealthMetricType
    public let record: VitalMetricRecord?
    public let tint: Color
    
    public init(metricType: HealthMetricType, record: VitalMetricRecord?, tint: Color = ThemeColors.accentCyan) {
        self.metricType = metricType
        self.record = record
        self.tint = tint
    }
    
    public var body: some View {
        GlassCard(cornerRadius: 18, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                // Header: Icon + Metric Name + Source Device Badge
                HStack {
                    ZStack {
                        Circle()
                            .fill(tint.opacity(0.16))
                            .frame(width: 32, height: 32)
                        Image(systemName: metricType.systemImage)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(tint)
                    }
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(metricType.displayName)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        if let device = record?.sourceDevice, !device.isEmpty {
                            Text(DeviceSource.from(name: device).displayName)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(ThemeColors.fgMutedDark)
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer()
                }
                
                // Value + Unit
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formattedValue)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text(record?.unit ?? metricType.defaultUnit)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
            }
        }
    }
    
    private var formattedValue: String {
        guard let v = record?.value else { return "--" }
        switch metricType {
        case .steps, .activeEnergy, .basalEnergy, .floorsClimbed, .heartRate, .restingHeartRate, .hrvSdnn, .hrvRmssd, .oxygenSaturation, .bloodPressureSystolic, .bloodPressureDiastolic, .hydration, .stress, .pai, .mindfulSession:
            return "\(Int(round(v)))"
        case .distance, .weight, .leanBodyMass, .height, .bmi, .respiratoryRate, .bodyTemperature, .bodyFatPercentage:
            return String(format: "%.1f", v)
        case .sleepDuration, .sleepDeep, .sleepRem, .sleepLight, .sleepAwake, .napDuration:
            let hours = Int(v) / 60
            let mins = Int(v) % 60
            return hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
        default:
            return String(format: "%.1f", v)
        }
    }
}
