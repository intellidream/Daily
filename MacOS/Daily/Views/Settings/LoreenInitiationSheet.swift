import SwiftUI
import AppKit
import DailyCore

/// Interactive "Loreen Initiation" handwriting challenge sheet for macOS.
/// Users prove fluency by drawing `LOREEN` or their own first name in Loreen Script
/// using mouse, trackpad, or stylus via the 100% offline `$P` multistroke recognizer.
public struct LoreenInitiationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var authService = AuthService.shared

    public var onUnlocked: () -> Void

    private enum ChallengeMode: String, CaseIterable, Identifiable {
        case loreen = "LOREEN"
        case myName = "My Name"
        var id: String { rawValue }
    }

    @State private var mode: ChallengeMode = .loreen
    @State private var showHintGuides: Bool = false
    @State private var tileStrokes: [Int: [[LoreenPoint]]] = [:]
    @State private var tileVerified: [Int: Bool] = [:]
    @State private var tileLastGuess: [Int: Character] = [:]

    public init(onUnlocked: @escaping () -> Void = {}) {
        self.onUnlocked = onUnlocked
    }

    private var personalNameWord: String {
        LoreenGlyphCatalog.challengeWord(for: authService.currentUser?.firstName)
    }

    private var targetWord: String {
        switch mode {
        case .loreen:
            return "LOREEN"
        case .myName:
            return personalNameWord
        }
    }

    private var targetCharacters: [Character] {
        Array(targetWord)
    }

    private var verifiedCount: Int {
        targetCharacters.indices.filter { tileVerified[$0] == true }.count
    }

    private var allVerified: Bool {
        !targetCharacters.isEmpty && verifiedCount == targetCharacters.count
    }

    private func triggerHaptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern = .generic) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Sheet Toolbar
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(Color.white.opacity(0.75))

                Spacer()

                Text("Loreen Initiation")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Spacer()

                Button("Clear All") {
                    tileStrokes = [:]
                    tileVerified = [:]
                    tileLastGuess = [:]
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(ThemeColors.accentCyan)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.04))

            Divider().background(Color.white.opacity(0.1))

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "eye.slash.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(ThemeColors.accentCyan)
                            Text("Prove Fluency in Loreen Script")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }

                        Text("Draw each letter below with your mouse or trackpad to unlock Loreen Veil across Tagdos & Notes.")
                            .font(.system(size: 12.5))
                            .foregroundColor(Color.white.opacity(0.72))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Challenge Word", selection: $mode) {
                            Text("LOREEN").tag(ChallengeMode.loreen)
                            Text("My Name (\(personalNameWord))").tag(ChallengeMode.myName)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: mode) { _, _ in
                            tileStrokes = [:]
                            tileVerified = [:]
                            tileLastGuess = [:]
                        }

                        HStack {
                            Text("Progress: \(verifiedCount) / \(targetCharacters.count) glyphs verified")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(allVerified ? ThemeColors.accentGreen : ThemeColors.accentCyan)

                            Spacer()

                            Toggle("Faint Guide", isOn: $showHintGuides)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .tint(ThemeColors.accentPurple)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.75))
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.05))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                    )

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 128, maximum: 156), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(Array(targetCharacters.enumerated()), id: \.offset) { idx, expectedChar in
                            MacLoreenDrawingTile(
                                expectedLetter: expectedChar,
                                showHintGuide: showHintGuides,
                                strokes: Binding(
                                    get: { tileStrokes[idx] ?? [] },
                                    set: { tileStrokes[idx] = $0 }
                                ),
                                isVerified: tileVerified[idx] ?? false,
                                lastGuess: tileLastGuess[idx],
                                onEvaluate: { strokes in
                                    evaluateTile(index: idx, expected: expectedChar, strokes: strokes)
                                },
                                onClear: {
                                    tileStrokes[idx] = []
                                    tileVerified[idx] = false
                                    tileLastGuess[idx] = nil
                                }
                            )
                        }
                    }

                    if allVerified {
                        VStack(spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(ThemeColors.accentGreen)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Fluency Verified!")
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                    Text("Loreen Veil is ready to shield your Tagdos & Notes.")
                                        .font(.system(size: 12))
                                        .foregroundColor(Color.white.opacity(0.75))
                                }
                                Spacer()
                            }

                            Button {
                                triggerHaptic(.alignment)
                                onUnlocked()
                                dismiss()
                            } label: {
                                Text("Unlock & Enable Loreen Veil")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                                    .background(ThemeColors.accentGreen)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(ThemeColors.accentGreen.opacity(0.14))
                                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(ThemeColors.accentGreen.opacity(0.45), lineWidth: 1))
                        )
                    } else {
                        Text("Tip: Multi-stroke glyphs are evaluated automatically 450ms after releasing the mouse/trackpad.")
                            .font(.system(size: 11.5))
                            .foregroundColor(Color.white.opacity(0.5))
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 540, minHeight: 540)
        .background(Color(hex: "060D1A"))
        .preferredColorScheme(.dark)
    }

    private func evaluateTile(index: Int, expected: Character, strokes: [[LoreenPoint]]) {
        guard !strokes.isEmpty else {
            tileVerified[index] = false
            tileLastGuess[index] = nil
            return
        }
        let result = LoreenStrokeRecognizer.recognize(strokes: strokes)
        tileLastGuess[index] = result?.letter
        let matched = LoreenStrokeRecognizer.matches(strokes: strokes, expected: expected)
        tileVerified[index] = matched
        if matched {
            triggerHaptic(.alignment)
        }
    }
}

private struct MacLoreenDrawingTile: View {
    let expectedLetter: Character
    let showHintGuide: Bool
    @Binding var strokes: [[LoreenPoint]]
    let isVerified: Bool
    let lastGuess: Character?
    let onEvaluate: ([[LoreenPoint]]) -> Void
    let onClear: () -> Void

    @State private var activeStroke: [LoreenPoint] = []
    @State private var debounceTask: Task<Void, Never>? = nil

    private var borderColor: Color {
        if isVerified { return ThemeColors.accentGreen }
        if !strokes.isEmpty && lastGuess != nil { return ThemeColors.accentOrange.opacity(0.7) }
        return Color.white.opacity(0.16)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isVerified ? ThemeColors.accentGreen.opacity(0.10) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: isVerified ? 1.8 : 1)
                    )

                if showHintGuide {
                    Text(String(expectedLetter))
                        .font(.loreen(size: 64))
                        .foregroundColor(Color.white.opacity(0.12))
                        .allowsHitTesting(false)
                }

                Canvas { context, _ in
                    var combinedPath = Path()
                    for stroke in strokes where !stroke.isEmpty {
                        combinedPath.move(to: CGPoint(x: stroke[0].x, y: stroke[0].y))
                        for pt in stroke.dropFirst() {
                            combinedPath.addLine(to: CGPoint(x: pt.x, y: pt.y))
                        }
                    }
                    if !activeStroke.isEmpty {
                        combinedPath.move(to: CGPoint(x: activeStroke[0].x, y: activeStroke[0].y))
                        for pt in activeStroke.dropFirst() {
                            combinedPath.addLine(to: CGPoint(x: pt.x, y: pt.y))
                        }
                    }
                    context.stroke(
                        combinedPath,
                        with: .color(isVerified ? ThemeColors.accentGreen : ThemeColors.accentCyan),
                        style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round)
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            debounceTask?.cancel()
                            let pt = LoreenPoint(x: value.location.x, y: value.location.y)
                            activeStroke.append(pt)
                        }
                        .onEnded { _ in
                            if !activeStroke.isEmpty {
                                strokes.append(activeStroke)
                                activeStroke = []
                            }
                            let snapshot = strokes
                            debounceTask?.cancel()
                            debounceTask = Task {
                                try? await Task.sleep(nanoseconds: 450_000_000)
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    onEvaluate(snapshot)
                                }
                            }
                        }
                )

                VStack {
                    HStack {
                        Spacer()
                        if isVerified {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(ThemeColors.accentGreen)
                        } else if !strokes.isEmpty {
                            Button {
                                debounceTask?.cancel()
                                activeStroke = []
                                onClear()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color.white.opacity(0.45))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Spacer()
                }
                .padding(8)
            }
            .frame(height: 128)

            HStack(spacing: 4) {
                Text(String(expectedLetter))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(isVerified ? ThemeColors.accentGreen : .white)

                if !isVerified, let guess = lastGuess {
                    Text("(\(String(guess))?)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(ThemeColors.accentOrange)
                }
            }
        }
    }
}
