import SwiftUI
import UIKit
import DailyCore

public enum PrismStudioTab: String, CaseIterable, Identifiable {
    case copilot = "Co-Pilot"
    case vault = "Vault"

    public var id: String { rawValue }
}

/// Assisted Exploration & Vault Studio Pane for iOS (docked 35% right pane on Foldables/SimulaDuo, or .medium/.large Bottom Sheet on iPhone).
public struct PrismSideStudioPane: View {
    @Binding public var activeStudioTab: PrismStudioTab
    @ObservedObject public var engine: PrismWebEngineModel
    @ObservedObject private var prismStore = PrismStore.shared
    @ObservedObject private var settingsService = SettingsService.shared

    public let onOpenUrlInPrism: (String, String?) -> Void
    public let onClosePane: (() -> Void)?

    @State private var turns: [PrismCoPilotTurn] = []
    @State private var isGeneratingTurn: Bool = false
    @State private var customQuestion: String = ""

    @State private var selectedClipFilter: PrismClipType? = nil
    @State private var selectedTagFilter: String? = nil
    @State private var vaultSearchQuery: String = ""
    @State private var editingClip: PrismClip? = nil
    @State private var editNoteText: String = ""
    @State private var editTagsText: String = ""

    public init(
        activeStudioTab: Binding<PrismStudioTab>,
        engine: PrismWebEngineModel,
        onOpenUrlInPrism: @escaping (String, String?) -> Void,
        onClosePane: (() -> Void)? = nil
    ) {
        self._activeStudioTab = activeStudioTab
        self.engine = engine
        self.onOpenUrlInPrism = onOpenUrlInPrism
        self.onClosePane = onClosePane
    }

    private var allUniqueTags: [String] {
        Array(Set(prismStore.clips.flatMap(\.tags))).sorted()
    }

    private var filteredClips: [PrismClip] {
        prismStore.clips.filter { clip in
            if let typeFilter = selectedClipFilter, clip.clipType != typeFilter {
                return false
            }
            if let tagFilter = selectedTagFilter, !clip.tags.contains(tagFilter) {
                return false
            }
            let q = vaultSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !q.isEmpty {
                let hay = "\(clip.title) \(clip.domain) \(clip.contentText) \(clip.userNote) \(clip.tags.joined(separator: " "))".lowercased()
                return hay.contains(q)
            }
            return true
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerSwitcher

            Divider().background(Color.white.opacity(0.10))

            if activeStudioTab == .copilot {
                coPilotBody
            } else {
                vaultBody
            }
        }
        .background(Color(hex: "#090F1E").ignoresSafeArea())
        .onAppear {
            Task { @MainActor in
                await prismStore.syncWithSupabase()
            }
        }
        .sheet(item: $editingClip) { clip in
            clipAnnotationSheet(for: clip)
        }
    }

    private var headerSwitcher: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                studioTabButton(tab: .copilot, icon: "sparkles", badge: nil)
                studioTabButton(tab: .vault, icon: "tray.full.fill", badge: prismStore.clips.count)
            }
            .padding(4)
            .background(Color.white.opacity(0.06), in: Capsule())

            Spacer()

            if prismStore.isSyncing {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(0.7)
                    .tint(ThemeColors.accentCyan)
            } else if activeStudioTab == .vault {
                Button {
                    Task { @MainActor in
                        await prismStore.syncWithSupabase(forceFullPull: true)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
            }

            if let onClosePane = onClosePane {
                Button(action: onClosePane) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func studioTabButton(tab: PrismStudioTab, icon: String, badge: Int?) -> some View {
        let isSelected = (activeStudioTab == tab)
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                activeStudioTab = tab
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                if let badge = badge, badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Color.white.opacity(isSelected ? 0.22 : 0.10), in: Capsule())
                }
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.65))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                if isSelected {
                    Capsule()
                        .fill(LinearGradient(
                            colors: [ThemeColors.accentBlue.opacity(0.75), ThemeColors.accentCyan.opacity(0.45)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Co-Pilot Body

    private var coPilotBody: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PrismCoPilotAction.allCases) { action in
                        Button {
                            triggerCoPilotAction(action)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: action.iconName)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundColor(Color(hex: action.accentHex))
                                Text(action.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.94))
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(Color(hex: action.accentHex).opacity(0.14), in: Capsule())
                            .overlay(Capsule().strokeBorder(Color(hex: action.accentHex).opacity(0.35), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(isGeneratingTurn || engine.currentURLString.isEmpty)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            Divider().background(Color.white.opacity(0.08))

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    if isGeneratingTurn {
                        HStack(spacing: 10) {
                            ProgressView().tint(ThemeColors.accentCyan)
                            Text("Synthesizing page insights...")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundColor(ThemeColors.fgMutedDark)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                    }

                    if turns.isEmpty && !isGeneratingTurn {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .foregroundColor(ThemeColors.accentCyan)
                                Text("Prism Assisted Exploration")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            Text(engine.currentURLString.isEmpty
                                 ? "Open any web page to generate TL;DR summaries, extract actionable tasks straight into TagDoS, isolate numbers/prices, or ask questions."
                                 : "Tap a chip above or ask anything about \"\(engine.pageTitle.isEmpty ? PrismSearchEngine.extractCleanDomain(from: engine.currentURLString) : engine.pageTitle)\".")
                                .font(.system(size: 12.5))
                                .foregroundColor(ThemeColors.fgMutedDark)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                    }

                    ForEach(turns) { turn in
                        coPilotTurnCard(turn)
                    }
                }
                .padding(16)
            }

            Divider().background(Color.white.opacity(0.10))

            HStack(spacing: 8) {
                TextField("Ask about this page...", text: $customQuestion)
                    .font(.system(size: 13.5))
                    .foregroundColor(.white)
                    .submitLabel(.send)
                    .onSubmit {
                        submitCustomQuestion()
                    }

                Button {
                    submitCustomQuestion()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(customQuestion.trimmingCharacters(in: .whitespaces).isEmpty || engine.currentURLString.isEmpty
                                         ? Color.white.opacity(0.25)
                                         : ThemeColors.accentCyan)
                }
                .buttonStyle(.plain)
                .disabled(customQuestion.trimmingCharacters(in: .whitespaces).isEmpty || engine.currentURLString.isEmpty || isGeneratingTurn)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            .padding(14)
        }
    }

    private func coPilotTurnCard(_ turn: PrismCoPilotTurn) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(turn.prompt)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(ThemeColors.accentCyan)
                    .lineLimit(1)
                Spacer()
                Text(turn.isAiGenerated ? "Gemini Flash" : "Local Extract")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(ThemeColors.fgMutedDark)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.07), in: Capsule())
            }

            Text(turn.responseMarkdown)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.94))
                .fixedSize(horizontal: false, vertical: true)

            if !turn.keyBullets.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(turn.keyBullets, id: \.self) { bullet in
                        HStack(alignment: .top, spacing: 7) {
                            Circle()
                                .fill(ThemeColors.accentCyan)
                                .frame(width: 5, height: 5)
                                .padding(.top, 6)
                            Text(bullet)
                                .font(.system(size: 12.5))
                                .foregroundColor(.white.opacity(0.86))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Button {
                    _ = prismStore.saveAISummaryClip(turn: turn)
                    engine.showToast("Saved AI Note to Vault")
                } label: {
                    Label("Save to Vault", systemImage: "tray.and.arrow.down.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(ThemeColors.accentCyan)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(ThemeColors.accentCyan.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)

                if !turn.extractedTasks.isEmpty {
                    Button {
                        prismStore.sendTasksToTagdosQuickNote(
                            tasks: turn.extractedTasks,
                            pageTitle: turn.pageTitle,
                            sourceUrl: turn.sourceUrl
                        )
                        engine.showToast("Sent Tasks to TagDoS")
                    } label: {
                        Label("→ TagDoS", systemImage: "checklist")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(Color(hex: "#FFB300"))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(hex: "#FFB300").opacity(0.15), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
    }

    private func triggerCoPilotAction(_ action: PrismCoPilotAction) {
        guard !engine.currentURLString.isEmpty else { return }
        isGeneratingTurn = true

        Task {
            let ctx = await engine.extractPageContext()
            let turn = await PrismCoPilotService.shared.runAction(
                action,
                pageTitle: ctx.title.isEmpty ? engine.pageTitle : ctx.title,
                pageUrl: ctx.url.isEmpty ? engine.currentURLString : ctx.url,
                bodyText: ctx.bodyText,
                selectedText: ctx.selectedText,
                apiKey: settingsService.settings.geminiApiKey
            )
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                turns.insert(turn, at: 0)
                isGeneratingTurn = false
            }
        }
    }

    private func submitCustomQuestion() {
        let q = customQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !engine.currentURLString.isEmpty else { return }
        customQuestion = ""
        isGeneratingTurn = true

        Task {
            let ctx = await engine.extractPageContext()
            let turn = await PrismCoPilotService.shared.askQuestion(
                question: q,
                pageTitle: ctx.title.isEmpty ? engine.pageTitle : ctx.title,
                pageUrl: ctx.url.isEmpty ? engine.currentURLString : ctx.url,
                bodyText: ctx.bodyText,
                selectedText: ctx.selectedText,
                apiKey: settingsService.settings.geminiApiKey
            )
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                turns.insert(turn, at: 0)
                isGeneratingTurn = false
            }
        }
    }

    // MARK: - Vault Body

    private var vaultBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundColor(ThemeColors.fgMutedDark)
                TextField("Search links, quotes, images, #tags...", text: $vaultSearchQuery)
                    .font(.system(size: 13.5))
                    .foregroundColor(.white)
                    .autocorrectionDisabled()
                if !vaultSearchQuery.isEmpty {
                    Button {
                        vaultSearchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
            .padding(.top, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    filterChip(title: "All", icon: "square.grid.2x2", isSelected: selectedClipFilter == nil) {
                        selectedClipFilter = nil
                    }
                    ForEach(PrismClipType.allCases, id: \.self) { type in
                        filterChip(
                            title: type.displayName,
                            icon: type.iconName,
                            accentHex: type.accentHex,
                            isSelected: selectedClipFilter == type
                        ) {
                            selectedClipFilter = (selectedClipFilter == type) ? nil : type
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            if !allUniqueTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(allUniqueTags, id: \.self) { tag in
                            let active = (selectedTagFilter == tag)
                            Button {
                                selectedTagFilter = active ? nil : tag
                            } label: {
                                Text("#\(tag)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(active ? .black : ThemeColors.accentCyan)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(active ? ThemeColors.accentCyan : ThemeColors.accentCyan.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                }
            }

            Divider().background(Color.white.opacity(0.08))

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    if filteredClips.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "tray")
                                .font(.system(size: 28))
                                .foregroundColor(ThemeColors.fgMutedDark)
                            Text("Your Prism Vault is clean")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                            Text("Save links, select text on any page, long-press an image, or use Share → DayOne.")
                                .font(.system(size: 12))
                                .foregroundColor(ThemeColors.fgMutedDark)
                                .multilineTextAlignment(.center)
                        }
                        .padding(28)
                    } else {
                        ForEach(filteredClips) { clip in
                            vaultClipCard(clip)
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    private func filterChip(title: String, icon: String, accentHex: String? = nil, isSelected: Bool, action: @escaping () -> Void) -> some View {
        let tint = accentHex.map { Color(hex: $0) } ?? ThemeColors.accentCyan
        return Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.72))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? tint.opacity(0.28) : Color.white.opacity(0.06), in: Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? tint.opacity(0.65) : Color.white.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func vaultClipCard(_ clip: PrismClip) -> some View {
        let accent = Color(hex: clip.clipType.accentHex)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: clip.clipType.iconName)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundColor(accent)
                Text(clip.domain.isEmpty ? clip.clipType.singularLabel : clip.domain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(accent)
                    .lineLimit(1)

                Spacer()

                Button {
                    prismStore.toggleFavoriteClip(clip.id)
                } label: {
                    Image(systemName: clip.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 13))
                        .foregroundColor(clip.isFavorite ? Color(hex: "#FFD166") : .white.opacity(0.45))
                }
                .buttonStyle(.plain)

                Button {
                    editingClip = clip
                    editNoteText = clip.userNote
                    editTagsText = clip.tags.joined(separator: ", ")
                } label: {
                    Image(systemName: "tag")
                        .font(.system(size: 12.5))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)

                Button {
                    prismStore.deleteClip(clip.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12.5))
                        .foregroundColor(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
            }

            Button {
                onOpenUrlInPrism(clip.sourceUrl, clip.title)
                onClosePane?()
            } label: {
                Text(clip.title)
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)

            if clip.clipType == .image {
                PrismClipImageViewIOS(clip: clip)
            }

            if !clip.contentText.isEmpty {
                Text(clip.contentText)
                    .font(.system(size: 12.5))
                    .foregroundColor(.white.opacity(0.86))
                    .lineLimit(5)
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            }

            if !clip.userNote.isEmpty {
                Text(clip.userNote)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(ThemeColors.accentCyan.opacity(0.92))
                    .lineLimit(2)
            }

            if !clip.tags.isEmpty {
                HStack(spacing: 5) {
                    ForEach(clip.tags, id: \.self) { t in
                        Text("#\(t)")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(ThemeColors.fgMutedDark)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Color.white.opacity(0.06), in: Capsule())
                    }
                }
            }

            HStack(spacing: 8) {
                Button {
                    _ = prismStore.sendClipToTagdos(clip)
                    engine.showToast("Mirrored to TagDoS (#prism)")
                } label: {
                    Label(clip.tagdosNoteId != nil ? "In TagDoS" : "→ TagDoS", systemImage: clip.tagdosNoteId != nil ? "checkmark.circle.fill" : "checklist")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "#FFB300"))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color(hex: "#FFB300").opacity(0.13), in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    prismStore.saveUrlToNewsReadLater(
                        url: clip.sourceUrl,
                        title: clip.title,
                        previewImageUrl: clip.previewImageUrl,
                        summary: clip.contentText
                    )
                    engine.showToast("Added to News Read Later")
                } label: {
                    Label("Read Later", systemImage: "bookmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(ThemeColors.accentCyan)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(ThemeColors.accentCyan.opacity(0.13), in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
    }

    private func clipAnnotationSheet(for clip: PrismClip) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(clip.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Personal Note")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                    TextField("Why this matters...", text: $editNoteText)
                        .padding(12)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Tags (comma separated)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                    TextField("tech, ideas, buy", text: $editTagsText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(12)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundColor(.white)
                }

                Spacer()
            }
            .padding(20)
            .background(Color(hex: "#0D1324").ignoresSafeArea())
            .navigationTitle("Annotate Clip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { editingClip = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let parsedTags = editTagsText
                            .components(separatedBy: CharacterSet(charactersIn: ", "))
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        prismStore.updateClipTagsAndNote(clip.id, userNote: editNoteText, tags: parsedTags)
                        editingClip = nil
                    }
                    .bold()
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct PrismClipImageViewIOS: View {
    let clip: PrismClip
    @State private var loadedImage: UIImage? = nil
    @State private var isDownloading: Bool = false

    var body: some View {
        ZStack {
            if let img = loadedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else if isDownloading {
                HStack(spacing: 8) {
                    ProgressView().tint(ThemeColors.accentCyan)
                    Text("Loading image...")
                        .font(.system(size: 11.5))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
                .frame(height: 84)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            } else {
                Button {
                    downloadOnDemand()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(ThemeColors.accentCyan)
                        Text("Load Clipped Image")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .frame(height: 68)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            if let localURL = PrismAttachmentManager.shared.existingLocalFileURL(for: clip),
               let uiImg = UIImage(contentsOfFile: localURL.path) {
                loadedImage = uiImg
            } else {
                downloadOnDemand()
            }
        }
    }

    private func downloadOnDemand() {
        guard !isDownloading else { return }
        isDownloading = true
        Task {
            if let url = try? await PrismAttachmentManager.shared.downloadClipImage(for: clip),
               let uiImg = UIImage(contentsOfFile: url.path) {
                await MainActor.run {
                    self.loadedImage = uiImg
                    self.isDownloading = false
                }
            } else {
                await MainActor.run {
                    self.isDownloading = false
                }
            }
        }
    }
}
