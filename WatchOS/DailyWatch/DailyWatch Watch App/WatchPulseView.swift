import SwiftUI
import WatchKit

struct WatchPulseView: View {
    @ObservedObject private var pulseStore = WatchPulseStore.shared
    @State private var activeBreathingProtocol: BreathingProtocol? = nil

    private var snap: WatchPulseSnapshot {
        pulseStore.snapshot
    }

    private var readinessAccentColor: Color {
        if !snap.hasSleepData {
            return Color.white.opacity(0.6)
        }
        if snap.sleepScore >= 75 {
            return Color(hex: "#34D399")
        } else if snap.sleepScore >= 60 {
            return Color(hex: "#FBBF24")
        } else {
            return Color(hex: "#F87171")
        }
    }

    private var stressAccentColor: Color {
        if !snap.hasStressData {
            return Color(hex: "#38BDF8")
        }
        if snap.stressScore <= 25 {
            return Color(hex: "#00E5FF")
        } else if snap.stressScore <= 50 {
            return Color(hex: "#34D399")
        } else if snap.stressScore <= 75 {
            return Color(hex: "#FBBF24")
        } else {
            return Color(hex: "#F87171")
        }
    }

    private var recommendedProtocol: BreathingProtocol {
        let lower = snap.recommendedBreathing.lowercased()
        if lower.contains("4-7-8") {
            return .relax478
        } else if lower.contains("box") {
            return .boxBreathing
        } else if lower.contains("resonance") || lower.contains("coherent") {
            return .resonance
        } else {
            return .physiologicalSigh
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Header (TagDoS-style title + compact refresh indicator next to title)
                HStack(spacing: 5) {
                    Image(systemName: "heart.fill")
                        .foregroundColor(Color(hex: "#FF2D55"))
                        .font(.system(size: 14, weight: .bold))
                    Text("Pulse Studio")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    if pulseStore.isSyncing {
                        ProgressView()
                            .tint(Color(hex: "#FF2D55"))
                            .scaleEffect(0.55)
                            .frame(width: 12, height: 12)
                    }
                    Spacer()
                }
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    WKInterfaceDevice.current().play(.click)
                    Task {
                        await pulseStore.fetchPulseData(force: true)
                    }
                }

                // 1. Sleep & Morning Recovery Verdict Card
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("SLEEP & RECOVERY")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(hex: "#A855F7"))
                            .tracking(0.5)
                        Spacer()
                        Text(snap.sleepDurationFormatted)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(1)
                    }

                    HStack(spacing: 8) {
                        // Score Ring
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.1), lineWidth: 4.5)
                                .frame(width: 44, height: 44)
                            Circle()
                                .trim(from: 0, to: snap.hasSleepData ? CGFloat(snap.sleepScore) / 100.0 : 0.0)
                                .stroke(Color(hex: "#A855F7"), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .frame(width: 44, height: 44)
                            VStack(spacing: 0) {
                                Text(snap.hasSleepData ? "\(snap.sleepScore)" : "--")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                Text("SCORE")
                                    .font(.system(size: 6.5, weight: .bold))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(snap.readinessHeadline)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(readinessAccentColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                                .allowsTightening(true)
                            Text(snap.sleepNarrative)
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.75))
                                .lineLimit(2)
                            HStack(spacing: 4) {
                                Text(snap.restingHrText)
                                    .font(.system(size: 8.5, weight: .semibold))
                                    .foregroundColor(Color(hex: "#F87171"))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                    .fixedSize(horizontal: true, vertical: false)
                                Text("•")
                                    .font(.system(size: 8.5))
                                    .foregroundColor(.white.opacity(0.3))
                                Text(snap.hrvText)
                                    .font(.system(size: 8.5, weight: .semibold))
                                    .foregroundColor(Color(hex: "#38BDF8"))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                    }

                    // Proportional Sleep Stage Breakdown Bar (Deep, REM, Core/Light, Awake)
                    GeometryReader { geo in
                        let spacing: CGFloat = 2
                        let usableWidth = max(16, geo.size.width - (spacing * 3))
                        HStack(spacing: spacing) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(hex: "#6366F1"))
                                .frame(width: usableWidth * CGFloat(snap.deepFraction), height: 5)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(hex: "#A855F7"))
                                .frame(width: usableWidth * CGFloat(snap.remFraction), height: 5)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(hex: "#38BDF8"))
                                .frame(width: usableWidth * CGFloat(snap.lightFraction), height: 5)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(hex: "#F59E0B"))
                                .frame(width: usableWidth * CGFloat(snap.awakeFraction), height: 5)
                        }
                    }
                    .frame(height: 5)
                    .padding(.top, 2)
                }
                .padding(10)
                .background(Color(hex: "#141820"))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(hex: "#A855F7").opacity(0.22), lineWidth: 1)
                )

                // 2. Autonomic Stress & MonkeyMood Vitals Card (Engine v2.0)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("AUTONOMIC STRESS")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(hex: "#38BDF8"))
                            .tracking(0.5)
                        Spacer()
                        Text(snap.stressBadgeText)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(stressAccentColor)
                    }

                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(snap.stressHeadline)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(snap.monkeyMoodText)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white.opacity(0.68))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(snap.stepsText)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color(hex: "#FBBF24"))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                            Text(snap.parasympatheticText)
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.55))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }

                    Divider().background(Color.white.opacity(0.06))

                    HStack(alignment: .center, spacing: 6) {
                        Text(snap.adviceQuote)
                            .font(.system(size: 8.5))
                            .foregroundColor(.white.opacity(0.65))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button(action: {
                            WKInterfaceDevice.current().play(.click)
                            activeBreathingProtocol = recommendedProtocol
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "wind")
                                    .font(.system(size: 8, weight: .bold))
                                Text("Breathe")
                                    .font(.system(size: 9, weight: .bold))
                                    .lineLimit(1)
                            }
                            .fixedSize()
                            .foregroundColor(Color(hex: "#00E5FF"))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color(hex: "#00E5FF").opacity(0.16))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(Color(hex: "#141820"))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )

                // 3. Guided Breathing Protocols Section
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "wind")
                            .foregroundColor(.cyan)
                            .font(.system(size: 10))
                        Text("GUIDED BREATHING")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.55))
                            .tracking(0.5)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 4)

                    ForEach(BreathingProtocol.allCases) { proto in
                        Button(action: {
                            WKInterfaceDevice.current().play(.click)
                            activeBreathingProtocol = proto
                        }) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(proto.accentColor.opacity(0.25))
                                    .frame(width: 22, height: 22)
                                    .overlay(
                                        Image(systemName: "wind")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(proto.accentColor)
                                    )

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(proto.rawValue)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.white)
                                    Text(proto.shortTitle)
                                        .font(.system(size: 9))
                                        .foregroundColor(.white.opacity(0.55))
                                }

                                Spacer()

                                Image(systemName: "play.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(proto.accentColor)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(hex: "#141820"))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white.opacity(0.04), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer(minLength: 16)
            }
            .padding(.horizontal, 6)
        }
        .task {
            await pulseStore.fetchPulseData(force: false)
        }
        .sheet(item: $activeBreathingProtocol) { proto in
            WatchBreathingView(initialProtocol: proto)
        }
    }
}
