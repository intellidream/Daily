import SwiftUI
import WatchKit

public enum BreathingProtocol: String, CaseIterable, Identifiable {
    case physiologicalSigh = "Physiological Sigh"
    case boxBreathing = "Box 4-4-4-4"
    case resonance = "Resonance 5.5s"
    case relax478 = "4-7-8 Relax"

    public var id: String { rawValue }

    public var shortTitle: String {
        switch self {
        case .physiologicalSigh: return "Sigh (48s)"
        case .boxBreathing: return "Box (64s)"
        case .resonance: return "Resonance"
        case .relax478: return "4-7-8 (76s)"
        }
    }

    public var totalCycles: Int {
        switch self {
        case .physiologicalSigh: return 5
        case .boxBreathing: return 4
        case .resonance: return 6
        case .relax478: return 4
        }
    }

    public var accentColor: Color {
        switch self {
        case .physiologicalSigh: return .cyan
        case .boxBreathing: return Color(hex: "#38BDF8")
        case .resonance: return Color(hex: "#10B981")
        case .relax478: return Color(hex: "#A855F7")
        }
    }
}

enum BreathingPhase: String {
    case inhale1 = "Inhale"
    case inhale2 = "Top Up"
    case hold = "Hold"
    case exhale = "Exhale"
    case finished = "Done"

    var color: Color {
        switch self {
        case .inhale1, .inhale2: return .cyan
        case .hold: return .yellow
        case .exhale: return .green
        case .finished: return .mint
        }
    }
}

public struct WatchBreathingView: View {
    @Environment(\.dismiss) private var dismiss
    public var initialProtocol: BreathingProtocol = .physiologicalSigh

    @State private var selectedProtocol: BreathingProtocol
    @State private var currentCycle: Int = 1
    @State private var phase: BreathingPhase = .inhale1
    @State private var phaseTimeRemaining: Double = 2.0
    @State private var circleScale: CGFloat = 0.5
    @State private var isRunning: Bool = true
    @State private var timerTask: Task<Void, Never>?

    public init(initialProtocol: BreathingProtocol = .physiologicalSigh) {
        self.initialProtocol = initialProtocol
        _selectedProtocol = State(initialValue: initialProtocol)
    }

    public var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(selectedProtocol.rawValue)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(selectedProtocol.accentColor)
                Spacer()
                Text("\(currentCycle)/\(selectedProtocol.totalCycles)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 10)

            Spacer()

            // Central Pulsing Breathing Disc
            ZStack {
                Circle()
                    .stroke(phase.color.opacity(0.25), lineWidth: 6)
                    .frame(width: 84, height: 84)

                Circle()
                    .fill(phase.color.opacity(0.18))
                    .frame(width: 84, height: 84)
                    .scaleEffect(circleScale)
                    .animation(.easeInOut(duration: phaseDuration), value: circleScale)

                VStack(spacing: 2) {
                    Text(phase.rawValue)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(phase.color)

                    if phase != .finished {
                        Text(String(format: "%.1fs", phaseTimeRemaining))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 2)

            Spacer()

            if phase == .finished {
                Button(action: {
                    dismiss()
                }) {
                    Text("Complete")
                        .font(.system(size: 12, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(Color.mint)
                        .foregroundColor(.black)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
            } else {
                Button(action: {
                    timerTask?.cancel()
                    dismiss()
                }) {
                    Text("Cancel")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            startBreathingEngine()
        }
        .onDisappear {
            timerTask?.cancel()
        }
    }

    private var phaseDuration: Double {
        switch selectedProtocol {
        case .physiologicalSigh:
            switch phase {
            case .inhale1: return 2.0
            case .inhale2: return 1.5
            case .hold: return 0.0
            case .exhale: return 6.0
            case .finished: return 0.0
            }
        case .boxBreathing:
            switch phase {
            case .inhale1, .inhale2: return 4.0
            case .hold: return 4.0
            case .exhale: return 4.0
            case .finished: return 0.0
            }
        case .resonance:
            switch phase {
            case .inhale1, .inhale2: return 5.5
            case .hold: return 0.0
            case .exhale: return 5.5
            case .finished: return 0.0
            }
        case .relax478:
            switch phase {
            case .inhale1, .inhale2: return 4.0
            case .hold: return 7.0
            case .exhale: return 8.0
            case .finished: return 0.0
            }
        }
    }

    private func startBreathingEngine() {
        timerTask?.cancel()
        currentCycle = 1
        timerTask = Task {
            while currentCycle <= selectedProtocol.totalCycles && !Task.isCancelled {
                switch selectedProtocol {
                case .physiologicalSigh:
                    // 1. Inhale 1 (2.0s)
                    await runStep(targetPhase: .inhale1, duration: 2.0, targetScale: 0.8, haptic: .directionUp)
                    if Task.isCancelled { return }

                    // 2. Inhale 2 (1.5s)
                    await runStep(targetPhase: .inhale2, duration: 1.5, targetScale: 1.0, haptic: .directionUp)
                    if Task.isCancelled { return }

                    // 3. Exhale (6.0s)
                    await runStep(targetPhase: .exhale, duration: 6.0, targetScale: 0.35, haptic: .directionDown)
                    if Task.isCancelled { return }

                case .boxBreathing:
                    // 1. Inhale (4.0s)
                    await runStep(targetPhase: .inhale1, duration: 4.0, targetScale: 1.0, haptic: .directionUp)
                    if Task.isCancelled { return }

                    // 2. Hold (4.0s)
                    await runStep(targetPhase: .hold, duration: 4.0, targetScale: 1.0, haptic: .click)
                    if Task.isCancelled { return }

                    // 3. Exhale (4.0s)
                    await runStep(targetPhase: .exhale, duration: 4.0, targetScale: 0.35, haptic: .directionDown)
                    if Task.isCancelled { return }

                    // 4. Hold (4.0s)
                    await runStep(targetPhase: .hold, duration: 4.0, targetScale: 0.35, haptic: .click)
                    if Task.isCancelled { return }

                case .resonance:
                    // 1. Inhale (5.5s)
                    await runStep(targetPhase: .inhale1, duration: 5.5, targetScale: 1.0, haptic: .directionUp)
                    if Task.isCancelled { return }

                    // 2. Exhale (5.5s)
                    await runStep(targetPhase: .exhale, duration: 5.5, targetScale: 0.35, haptic: .directionDown)
                    if Task.isCancelled { return }

                case .relax478:
                    // 1. Inhale (4.0s)
                    await runStep(targetPhase: .inhale1, duration: 4.0, targetScale: 1.0, haptic: .directionUp)
                    if Task.isCancelled { return }

                    // 2. Hold (7.0s)
                    await runStep(targetPhase: .hold, duration: 7.0, targetScale: 1.0, haptic: .click)
                    if Task.isCancelled { return }

                    // 3. Exhale (8.0s)
                    await runStep(targetPhase: .exhale, duration: 8.0, targetScale: 0.35, haptic: .directionDown)
                    if Task.isCancelled { return }
                }

                currentCycle += 1
            }

            if !Task.isCancelled {
                phase = .finished
                WKInterfaceDevice.current().play(.success)
            }
        }
    }

    private func runStep(targetPhase: BreathingPhase, duration: Double, targetScale: CGFloat, haptic: WKHapticType) async {
        phase = targetPhase
        phaseTimeRemaining = duration
        circleScale = targetScale
        WKInterfaceDevice.current().play(haptic)

        let stepMs: UInt64 = 100_000_000 // 100ms
        var elapsed: Double = 0.0
        while elapsed < duration {
            try? await Task.sleep(nanoseconds: stepMs)
            if Task.isCancelled { return }
            elapsed += 0.1
            phaseTimeRemaining = max(0.0, duration - elapsed)
        }
    }
}
