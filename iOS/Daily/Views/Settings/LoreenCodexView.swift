import SwiftUI
import DailyCore

/// Interactive Loreen Codex & Feature Documentation sheet accessible once Loreen Veil is unlocked.
public struct LoreenCodexView: View {
    @Environment(\.dismiss) private var dismiss

    private enum CodexTab: String, CaseIterable, Identifiable {
        case codex = "A–Z Codex"
        case practice = "Practice Pad"
        case docs = "How It Works"
        var id: String { rawValue }
    }

    @State private var selectedTab: CodexTab = .codex
    @State private var practiceStrokes: [[LoreenPoint]] = []
    @State private var activePracticeStroke: [LoreenPoint] = []
    @State private var practiceResult: LoreenRecognitionResult? = nil

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Picker("Section", selection: $selectedTab) {
                    ForEach(CodexTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                ScrollView {
                    switch selectedTab {
                    case .codex:
                        codexGridSection
                    case .practice:
                        practicePadSection
                    case .docs:
                        documentationSection
                    }
                }
            }
            .background(Color(hex: "060D1A").ignoresSafeArea())
            .navigationTitle("Loreen Codex")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(ThemeColors.accentCyan)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Complete A-Z Reference Grid
    private var codexGridSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Complete 26-letter Loreen Script reference. Black/white dots mark the 18 original recalled glyphs; purple marks the 8 pattern-completed glyphs.")
                .font(.system(size: 12))
                .foregroundColor(Color.white.opacity(0.68))

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 98, maximum: 130), spacing: 10)],
                spacing: 10
            ) {
                ForEach(LoreenGlyphCatalog.allGlyphs) { glyph in
                    let isCompleted = glyph.origin == .completed
                    VStack(spacing: 6) {
                        HStack {
                            Text(String(glyph.id))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(isCompleted ? ThemeColors.accentPurple : ThemeColors.accentCyan)
                            Spacer()
                            Circle()
                                .fill(isCompleted ? ThemeColors.accentPurple : Color.white.opacity(0.4))
                                .frame(width: 6, height: 6)
                        }

                        Text(String(glyph.id))
                            .font(.loreen(size: 36))
                            .foregroundColor(.white)
                            .frame(height: 44)

                        Text(glyph.family)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.5))
                            .lineLimit(1)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(isCompleted ? ThemeColors.accentPurple.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1)
                            )
                    )
                }
            }
        }
        .padding(16)
    }

    // MARK: - Freehand Practice Pad
    private var practicePadSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Draw any Loreen letter below to test real-time offline recognition.")
                .font(.system(size: 12))
                .foregroundColor(Color.white.opacity(0.68))

            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.15), lineWidth: 1))

                Canvas { context, _ in
                    var path = Path()
                    for stroke in practiceStrokes where !stroke.isEmpty {
                        path.move(to: CGPoint(x: stroke[0].x, y: stroke[0].y))
                        for pt in stroke.dropFirst() {
                            path.addLine(to: CGPoint(x: pt.x, y: pt.y))
                        }
                    }
                    if !activePracticeStroke.isEmpty {
                        path.move(to: CGPoint(x: activePracticeStroke[0].x, y: activePracticeStroke[0].y))
                        for pt in activePracticeStroke.dropFirst() {
                            path.addLine(to: CGPoint(x: pt.x, y: pt.y))
                        }
                    }
                    context.stroke(
                        path,
                        with: .color(ThemeColors.accentCyan),
                        style: StrokeStyle(lineWidth: 5.5, lineCap: .round, lineJoin: .round)
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            activePracticeStroke.append(LoreenPoint(x: value.location.x, y: value.location.y))
                        }
                        .onEnded { _ in
                            if !activePracticeStroke.isEmpty {
                                practiceStrokes.append(activePracticeStroke)
                                activePracticeStroke = []
                                practiceResult = LoreenStrokeRecognizer.recognize(strokes: practiceStrokes)
                            }
                        }
                )
            }
            .frame(height: 240)

            HStack {
                if let res = practiceResult {
                    HStack(spacing: 10) {
                        Text(String(res.letter))
                            .font(.loreen(size: 28))
                            .foregroundColor(ThemeColors.accentCyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Recognized: \(String(res.letter))")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            let alts = res.topCandidates.dropFirst().prefix(3).map { String($0.letter) }.joined(separator: ", ")
                            if !alts.isEmpty {
                                Text("Next closest: \(alts)")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.white.opacity(0.55))
                            }
                        }
                    }
                } else {
                    Text("Draw a glyph above...")
                        .font(.system(size: 13))
                        .foregroundColor(Color.white.opacity(0.5))
                }

                Spacer()

                Button("Clear") {
                    practiceStrokes = []
                    activePracticeStroke = []
                    practiceResult = nil
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(ThemeColors.accentCyan)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(ThemeColors.accentCyan.opacity(0.15))
                .clipShape(Capsule())
            }
        }
        .padding(16)
    }

    // MARK: - Feature Documentation
    private var documentationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            docCard(
                icon: "eye.slash.fill",
                title: "What Loreen Veil Does",
                body: "Loreen Veil renders your Tagdos pills, stream titles, active memos, and Quick Notes in Loreen Script — protecting personal thoughts from casual glances in public spaces or during screen sharing."
            )

            docCard(
                icon: "hand.tap.fill",
                title: "Hold-to-Peek & Biometric Reveal",
                body: "Press and hold the eye button in the Tagdos & Notes header to temporarily reveal readable Latin text, then release to re-veil instantly. Optionally require Face ID / Touch ID in Settings."
            )

            docCard(
                icon: "pencil.and.outline",
                title: "Safe Editing & Zero Cloud Impact",
                body: "Opening any pill editor, Raw DSL editor, or Markdown note editor automatically switches back to readable Latin. Your data remains standard UTF-8 in Supabase and local caches, so search, sync, AI briefings, and widgets keep working with zero extra network egress."
            )

            docCard(
                icon: "globe.europe.africa.fill",
                title: "Romanian Diacritics & Monocase",
                body: "Loreen is monocase and maps Romanian diacritics automatically inside the font itself (Ă/Â → A, Î → I, Ș → S, Ț → T), alongside clean geometric numerals and TagDoS DSL symbols (/, &, $, €, !)."
            )
        }
        .padding(16)
    }

    private func docCard(icon: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(ThemeColors.accentCyan)
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            Text(body)
                .font(.system(size: 12.5))
                .foregroundColor(Color.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        )
    }
}
