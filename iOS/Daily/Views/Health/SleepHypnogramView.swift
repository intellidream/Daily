import SwiftUI
import DailyCore

/// Clinical 4-level hypnogram graphing Awake, REM, Light, and Deep stages along an hourly timeline.
public struct SleepHypnogramView: View {
    public let session: SleepSession
    @State private var selectedStage: SleepStageRecord? = nil
    
    public init(session: SleepSession) {
        self.session = session
    }
    
    private let rowHeight: CGFloat = 28
    private let laneSpacing: CGFloat = 8
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Selected stage inspection tooltip
            if let selected = selectedStage {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(hex: selected.stageType.hexColor))
                        .frame(width: 8, height: 8)
                    Text(selected.stageType.rawValue)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    Text("•")
                        .foregroundColor(ThemeColors.fgMutedDark)
                    Text("\(formatTime(selected.startTime)) - \(formatTime(selected.endTime))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Text("\(Int(round(selected.durationMinutes))) min")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(ThemeColors.accentCyan)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .transition(.opacity)
            }
            
            // Hypnogram Canvas
            GeometryReader { geo in
                let width = geo.size.width
                let totalSeconds = max(60, session.endTime.timeIntervalSince(session.startTime))
                
                ZStack(alignment: .topLeading) {
                    // 1. Horizontal lane guidelines & labels
                    VStack(alignment: .leading, spacing: laneSpacing) {
                        ForEach([SleepStageType.awake, .rem, .light, .deep], id: \.self) { stage in
                            HStack {
                                Text(stage.rawValue)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(Color(hex: stage.hexColor).opacity(0.8))
                                    .frame(width: 44, alignment: .leading)
                                
                                Rectangle()
                                    .fill(Color.white.opacity(0.06))
                                    .frame(height: 1)
                            }
                            .frame(height: rowHeight)
                        }
                    }
                    
                    // 2. Vertical Hourly Grid Lines
                    let hours = generateHourlyTicks()
                    ForEach(hours, id: \.self) { hourDate in
                        let elapsed = hourDate.timeIntervalSince(session.startTime)
                        if elapsed >= 0 && elapsed <= totalSeconds {
                            let x = 48 + ((elapsed / totalSeconds) * (width - 52))
                            
                            Path { path in
                                path.move(to: CGPoint(x: x, y: 0))
                                path.addLine(to: CGPoint(x: x, y: 4 * (rowHeight + laneSpacing) - laneSpacing))
                            }
                            .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        }
                    }
                    
                    // 3. Stage Blocks
                    ForEach(session.stages) { stage in
                        let elapsed = max(0, stage.startTime.timeIntervalSince(session.startTime))
                        let stageDur = max(30, stage.durationSeconds)
                        let left = 48 + ((elapsed / totalSeconds) * (width - 52))
                        let blockWidth = max(3, (stageDur / totalSeconds) * (width - 52))
                        let y = yPosition(for: stage.stageType)
                        let isSelected = selectedStage?.id == stage.id
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(hex: stage.stageType.hexColor).opacity(isSelected ? 1.0 : 0.85),
                                        Color(hex: stage.stageType.hexColor).opacity(isSelected ? 0.8 : 0.6)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(isSelected ? Color.white : Color.white.opacity(0.2), lineWidth: isSelected ? 1.5 : 0.5)
                            )
                            .frame(width: blockWidth, height: rowHeight - 4)
                            .offset(x: left, y: y + 2)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    if selectedStage?.id == stage.id {
                                        selectedStage = nil
                                    } else {
                                        selectedStage = stage
                                    }
                                }
                            }
                    }
                }
            }
            .frame(height: 4 * (rowHeight + laneSpacing) + 6)
            
            // X-Axis Time Ticks
            HStack {
                Text(session.bedtimeFormatted)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(ThemeColors.fgMutedDark)
                Spacer()
                Text("← \(session.totalAsleepFormatted) asleep →")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                Text(session.wakeTimeFormatted)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(ThemeColors.fgMutedDark)
            }
            .padding(.leading, 44)
        }
    }
    
    private func yPosition(for stage: SleepStageType) -> CGFloat {
        switch stage {
        case .awake: return 0
        case .rem: return rowHeight + laneSpacing
        case .light: return 2 * (rowHeight + laneSpacing)
        case .deep: return 3 * (rowHeight + laneSpacing)
        case .unknown: return 2 * (rowHeight + laneSpacing)
        }
    }
    
    private func generateHourlyTicks() -> [Date] {
        var ticks: [Date] = []
        let cal = Calendar.current
        var cur = cal.date(bySetting: .minute, value: 0, of: session.startTime) ?? session.startTime
        if cur < session.startTime {
            cur = cal.date(byAdding: .hour, value: 1, to: cur) ?? cur
        }
        while cur <= session.endTime {
            ticks.append(cur)
            cur = cal.date(byAdding: .hour, value: 1, to: cur) ?? cur.addingTimeInterval(3600)
        }
        return ticks
    }
    
    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
