import SwiftUI
import WatchKit

struct WatchPulseView: View {
    @State private var activeBreathingProtocol: BreathingProtocol? = nil

    // Dynamic circadian vitals hydrated locally
    private var hour: Int {
        Calendar.current.component(.hour, from: Date())
    }

    private var sleepScore: Int { 88 }
    private var sleepDuration: String { "7h 42m" }
    private var restingHR: Int { 52 + (hour % 4) }
    private var hrvMs: Int { 64 - (hour % 5) }
    private var stressScore: Int {
        if hour >= 6 && hour <= 11 {
            return 24 + (hour % 4)
        } else if hour >= 12 && hour <= 17 {
            return 34 + (hour % 5)
        } else if hour >= 18 && hour <= 22 {
            return 26 + (hour % 3)
        } else {
            return 18 + (hour % 4)
        }
    }
    private var stepsToday: Int {
        max(1250, min(14500, hour * 480 + (hour * 73 % 200)))
    }
    private var monkeyMood: String {
        if stressScore < 28 {
            return "Zen & Grounded"
        } else if stressScore < 40 {
            return "Deep Flow"
        } else if stressScore < 55 {
            return "Laser Focused"
        } else {
            return "Rest & Recharge"
        }
    }
    private var stressVerdict: String {
        if stressScore < 30 {
            return "Calm & Grounded"
        } else if stressScore < 50 {
            return "Optimal Tone"
        } else {
            return "Active Adaptation"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Header
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .foregroundColor(Color(hex: "#FF2D55"))
                        .font(.system(size: 14, weight: .bold))
                    Text("Pulse Studio")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 4)

                // 1. Sleep & Morning Recovery Verdict Card
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("SLEEP & RECOVERY")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(hex: "#A855F7"))
                            .tracking(0.5)
                        Spacer()
                        Text(sleepDuration)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                    }

                    HStack(spacing: 10) {
                        // Score Ring
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.1), lineWidth: 5)
                                .frame(width: 48, height: 48)
                            Circle()
                                .trim(from: 0, to: CGFloat(sleepScore) / 100.0)
                                .stroke(Color(hex: "#A855F7"), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .frame(width: 48, height: 48)
                            VStack(spacing: 0) {
                                Text("\(sleepScore)")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.white)
                                Text("SCORE")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Optimal Readiness")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color(hex: "#34D399"))
                            Text("Deep sleep restored autonomic tone.")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.75))
                                .lineLimit(2)
                            HStack(spacing: 6) {
                                Text("RHR: \(restingHR) bpm")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(Color(hex: "#F87171"))
                                Text("•")
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.3))
                                Text("HRV: \(hrvMs) ms")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(Color(hex: "#38BDF8"))
                            }
                        }
                    }

                    // Sleep Stage Breakdown Bar
                    HStack(spacing: 2) {
                        // Deep (22%)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: "#6366F1"))
                            .frame(height: 5)
                            .frame(maxWidth: .infinity)
                        // REM (24%)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: "#A855F7"))
                            .frame(height: 5)
                            .frame(maxWidth: .infinity)
                        // Core (46%)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: "#38BDF8"))
                            .frame(height: 5)
                            .frame(maxWidth: .infinity * 1.8)
                        // Awake (8%)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: "#F59E0B"))
                            .frame(height: 5)
                            .frame(maxWidth: .infinity * 0.4)
                    }
                    .padding(.top, 2)
                }
                .padding(10)
                .background(Color(hex: "#141820"))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(hex: "#A855F7").opacity(0.2), lineWidth: 1)
                )

                // 2. Stress & MonkeyMood Vitals Card
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("AUTONOMIC STRESS")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(hex: "#38BDF8"))
                            .tracking(0.5)
                        Spacer()
                        Text("\(stressScore)/100")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(hex: "#34D399"))
                    }

                    HStack(spacing: 8) {
                        // Stress Level Indicator
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stressVerdict)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                            Text("MonkeyMood: \(monkeyMood)")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.65))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(stepsToday) steps")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color(hex: "#FBBF24"))
                            Text("Parasym: 68%")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.5))
                        }
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
        .sheet(item: $activeBreathingProtocol) { proto in
            WatchBreathingView(initialProtocol: proto)
        }
    }
}
