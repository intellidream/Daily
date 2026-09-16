import SwiftUI
import DailyCore
#if canImport(UIKit)
import UIKit
#endif

/// Samsung Galaxy AI-style progressive word-reveal typewriter text with smooth opacity fade
/// and glowing ambient trailing cursor. Supports tap-to-complete.
public struct FadingTypewriterText: View {
    public let fullText: String
    public let wordIntervalMs: UInt64
    public var onFinished: (() -> Void)? = nil

    @State private var words: [String] = []
    @State private var revealedCount: Int = 0
    @State private var isFinished: Bool = false
    @State private var streamTask: Task<Void, Never>? = nil

    public init(
        fullText: String,
        wordIntervalMs: UInt64 = 40,
        onFinished: (() -> Void)? = nil
    ) {
        self.fullText = fullText
        self.wordIntervalMs = wordIntervalMs
        self.onFinished = onFinished
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                // Invisible full text to reserve layout geometry and prevent page jumping
                Text(fullText)
                    .font(.system(size: 15.5, weight: .regular, design: .rounded))
                    .lineSpacing(5)
                    .foregroundColor(.clear)
                    .accessibilityHidden(true)

                // Rendered animated text
                renderedTextView
            }
            .contentShape(Rectangle())
            .onTapGesture {
                completeInstantly()
            }

            if !isFinished {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(ThemeColors.accentCyan)
                    Text("Thinking & synthesizing...")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(ThemeColors.textSecondary)

                    Spacer()

                    Text("Tap text to skip")
                        .font(.system(size: 10.5, weight: .regular, design: .rounded))
                        .foregroundColor(ThemeColors.textMuted)
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            prepareAndStart()
        }
        .onChange(of: fullText) { _, _ in
            prepareAndStart()
        }
        .onDisappear {
            streamTask?.cancel()
        }
    }

    @ViewBuilder
    private var renderedTextView: some View {
        let currentText: String = {
            guard !words.isEmpty else { return fullText }
            if isFinished || revealedCount >= words.count {
                return fullText
            }
            return words.prefix(revealedCount).joined(separator: " ")
        }()

        (
            Text(currentText)
                .font(.system(size: 15.5, weight: .regular, design: .rounded))
                .foregroundColor(Color.white.opacity(0.92))
            +
            Text(!isFinished ? " ✨" : "")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(ThemeColors.accentCyan)
        )
        .lineSpacing(5)
        .animation(.easeOut(duration: 0.15), value: revealedCount)
    }

    private func prepareAndStart() {
        streamTask?.cancel()
        
        let cleaned = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            isFinished = true
            return
        }

        // Tokenize words while preserving structure
        self.words = cleaned.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        self.revealedCount = 0
        self.isFinished = false

        streamTask = Task { @MainActor in
            for i in 1...words.count {
                if Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: wordIntervalMs * 1_000_000)
                self.revealedCount = i
            }
            self.isFinished = true
            self.onFinished?()
            triggerHapticLight()
        }
    }

    private func completeInstantly() {
        guard !isFinished else { return }
        streamTask?.cancel()
        self.revealedCount = words.count
        self.isFinished = true
        self.onFinished?()
        triggerHapticLight()
    }

    private func triggerHapticLight() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}
