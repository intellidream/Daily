import SwiftUI
import LocalAuthentication
import DailyCore
#if canImport(UIKit)
import UIKit
#endif

/// Comprehensive interactive hub for TagDoS mental tag pipelines and quick notes.
public struct TagdosNotesHubView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = TagdosStore.shared
    @ObservedObject private var settingsService = SettingsService.shared

    /// -1 = "All" overview tab, 0..<streams.count = S1..SN, streams.count = "Notes"
    @State private var selectedStreamIndex: Int = -1
    @State private var isRawEditMode: Bool = false
    @State private var rawTextBuffer: String = ""
    @State private var isDraggingCluster: Bool = false
    @State private var highlightedClusterKey: String? = nil

    // Pill Action Sheet / Dialog state
    @State private var activePillAction: TagDoPillAction? = nil
    @State private var editingPillText: String = ""
    @State private var newPillClusterIndex: Int = 0
    @State private var addTagTargetStreamId: UUID? = nil
    @State private var showingAddTagSheet: Bool = false
    @State private var newTagInput: String = ""

    // Stream & Cluster Reminder Sheet state
    @State private var showingReminderPicker: Bool = false
    @State private var reminderPickerDate: Date = Date()
    @State private var editingReminderClusterIndex: Int? = nil

    // Stream Rename Sheet state
    @State private var showingRenameSheet: Bool = false
    @State private var editingStreamTitle: String = ""
    @State private var confirmDeleteStream: Bool = false

    // Stream Reorder Sheet state
    @State private var showingReorderSheet: Bool = false

    // External Tasks Import Sheet state
    @State private var showingImportSheet: Bool = false

    // Quick Note Editor Sheet state (used in "All" tab)
    @State private var activeOverviewNote: TagDoQuickNote? = nil
    @State private var isCreatingOverviewNote: Bool = false

    // Loreen Veil Peek / Biometric Reveal state
    @State private var isPeekingLoreen: Bool = false
    @State private var isBiometricRevealed: Bool = false

    public var onNavigateBack: (() -> Void)? = nil

    public init(onNavigateBack: (() -> Void)? = nil) {
        self.onNavigateBack = onNavigateBack
    }

    private var isLoreenMasterEnabled: Bool {
        settingsService.settings.loreenVeilUnlocked && settingsService.settings.loreenVeilEnabled
    }

    private var isLoreenRevealedNow: Bool {
        isPeekingLoreen || isBiometricRevealed
    }

    private var isTagdosVeiled: Bool {
        settingsService.settings.isLoreenVeilActiveForTagdos && !isLoreenRevealedNow
    }

    private var isNotesVeiled: Bool {
        settingsService.settings.isLoreenVeilActiveForNotes && !isLoreenRevealedNow
    }

    private func handleBack() {
        triggerHaptic()
        if let onNavigateBack = onNavigateBack {
            onNavigateBack()
        } else {
            dismiss()
        }
    }

    private var isAllTab: Bool {
        selectedStreamIndex == -1
    }

    private var currentStream: TagDoStream? {
        guard selectedStreamIndex >= 0 && selectedStreamIndex < store.streams.count else { return nil }
        return store.streams[selectedStreamIndex]
    }

    private var isNotesTab: Bool {
        selectedStreamIndex >= store.streams.count
    }

    private func triggerHaptic() {
        if settingsService.settings.hapticsEnabled {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
        }
    }

    public var body: some View {
        ScrollViewReader { scrollProxy in
            VStack(spacing: 0) {
                // Top Navigation Bar
                navigationBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                // Stream Selector Tabs (All + S1..SN + Notes)
                streamSelectorBar
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 12)

                // Main Content Body: All Overview, Interactive Canvas / Raw Editor, or Quick Notes
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        if isAllTab {
                            allOverviewContent
                        } else if isNotesTab {
                            TagdosQuickNotesView(isPeeking: isLoreenRevealedNow)
                        } else {
                            if isRawEditMode {
                                rawEditorCard
                            } else {
                                interactiveCanvasCard
                            }

                            // Per-Stream Active Memos & Attachments
                            if let stream = currentStream {
                                TagdosActiveMemoView(streamId: stream.id, streamNumber: stream.orderIndex + 1, isPeeking: isLoreenRevealedNow)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 28, coordinateSpace: .local)
                        .onEnded { value in
                            guard !isDraggingCluster else { return }
                            let dx = value.translation.width
                            let dy = value.translation.height
                            let startX = value.startLocation.x
                            guard startX > 75 else { return }
                            guard abs(dx) > abs(dy) * 1.8 && abs(dx) > 55 else { return }
                            let maxIndex = store.streams.count
                            if dx < 0 && selectedStreamIndex < maxIndex {
                                triggerHaptic()
                                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                    selectedStreamIndex += 1
                                }
                            } else if dx > 0 && selectedStreamIndex > -1 {
                                triggerHaptic()
                                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                    selectedStreamIndex -= 1
                                }
                            }
                        }
                )
                .refreshable {
                    await store.syncWithSupabase()
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .global)
                    .onEnded { value in
                        guard !isDraggingCluster else { return }
                        let startX = value.startLocation.x
                        let translationX = value.translation.width
                        let translationY = value.translation.height

                        if startX <= 75 && translationX > 50 && abs(translationX) > abs(translationY) * 1.1 {
                            handleBack()
                        }
                    }
            )
            .onAppear {
                if let stream = currentStream {
                    rawTextBuffer = stream.rawText
                }
                if let pending = store.pendingNavigation {
                    applyPendingNavigation(pending, scrollProxy: scrollProxy)
                }
            }
            .onChange(of: store.pendingNavigation) { _, newTarget in
                if let target = newTarget {
                    applyPendingNavigation(target, scrollProxy: scrollProxy)
                }
            }
            .onDisappear {
                isPeekingLoreen = false
                isBiometricRevealed = false
            }
            .onChange(of: selectedStreamIndex) { _, newIndex in
                if newIndex >= 0 && newIndex < store.streams.count {
                    rawTextBuffer = store.streams[newIndex].rawText
                } else {
                    isRawEditMode = false
                }
            }
        }
        .sheet(item: $activePillAction) { action in
            pillActionSheet(for: action)
                .frame(minWidth: 360)
                .presentationDetents([.height(380)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingAddTagSheet) {
            addTagSheet
                .frame(minWidth: 340)
                .presentationDetents([.height(210)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingReminderPicker) {
            reminderSheet
                .frame(minWidth: 340)
                .presentationDetents([.height(280)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingRenameSheet) {
            renameStreamSheet
                .frame(minWidth: 360)
                .presentationDetents([.height(340)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingReorderSheet) {
            reorderStreamsSheet
                .frame(minWidth: 400, minHeight: 360)
        }
        .sheet(isPresented: $showingImportSheet) {
            TagdosImportTasksSheet(initialStreamId: currentStream?.id) { importedStreamId in
                if let idx = store.streams.firstIndex(where: { $0.id == importedStreamId }) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedStreamIndex = idx
                        rawTextBuffer = store.streams[idx].rawText
                    }
                }
            }
        }
        .sheet(item: $activeOverviewNote) { note in
            MarkdownNoteEditorSheet(
                note: note,
                isNew: isCreatingOverviewNote,
                isVeiled: isNotesVeiled
            ) { updatedNote in
                if isCreatingOverviewNote {
                    store.createQuickNote(title: updatedNote.title, content: updatedNote.content)
                } else {
                    store.updateQuickNote(id: updatedNote.id, title: updatedNote.title, content: updatedNote.content)
                }
            }
            .frame(minWidth: 480, minHeight: 380)
        }
    }

    // MARK: - Deep-Link & Notification Navigation Handler
    private func applyPendingNavigation(_ target: TagdosNavigationTarget, scrollProxy: ScrollViewProxy) {
        defer { store.consumePendingNavigation() }

        if let sid = target.streamId,
           let idx = store.streams.firstIndex(where: { $0.id == sid }) {
            let stream = store.streams[idx]
            isRawEditMode = false

            if target.openPillEditor,
               let pid = target.pillId,
               let pill = stream.allPills.first(where: { $0.id == pid }) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    selectedStreamIndex = idx
                    rawTextBuffer = stream.rawText
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    editingPillText = pill.rawText
                    activePillAction = TagDoPillAction(streamId: sid, pill: pill)
                }
                return
            }

            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                selectedStreamIndex = idx
                rawTextBuffer = stream.rawText
            }

            if let cIdx = target.clusterIndex, cIdx >= 0 && cIdx < stream.clusters.count {
                let clusterKey = "cluster_\(sid.uuidString)_\(cIdx)"
                withAnimation(.easeInOut(duration: 0.25)) {
                    highlightedClusterKey = clusterKey
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        scrollProxy.scrollTo(clusterKey, anchor: .center)
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    if highlightedClusterKey == clusterKey {
                        withAnimation(.easeOut(duration: 0.35)) {
                            highlightedClusterKey = nil
                        }
                    }
                }
            }
        }
    }

    // MARK: - Navigation Bar
    private var navigationBar: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                handleBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(Color.white.opacity(0.08))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 6) {
                Text("Tagdos & Notes")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                if store.isSyncing {
                    ProgressView()
                        .scaleEffect(0.65)
                        .tint(ThemeColors.accentCyan)
                } else if store.lastSyncedAt != nil {
                    Image(systemName: "icloud.fill")
                        .font(.system(size: 11))
                        .foregroundColor(ThemeColors.accentGreen.opacity(0.85))
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if isLoreenMasterEnabled {
                    loreenPeekButton
                }

                Button {
                    triggerHaptic()
                    showingImportSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(ThemeColors.accentCyan)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle().fill(ThemeColors.accentCyan.opacity(0.16))
                                .overlay(Circle().strokeBorder(ThemeColors.accentCyan.opacity(0.35), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
                .help("Import tasks from Microsoft To Do or Google Tasks")

                if currentStream != nil {
                    let modeColor = isRawEditMode ? ThemeColors.accentGreen : ThemeColors.accentPurple
                    Button {
                        triggerHaptic()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            if isRawEditMode {
                                if let stream = currentStream {
                                    store.updateStreamRawText(streamId: stream.id, newRawText: rawTextBuffer)
                                }
                            } else {
                                if let stream = currentStream {
                                    rawTextBuffer = stream.rawText
                                }
                            }
                            isRawEditMode.toggle()
                        }
                    } label: {
                        Image(systemName: isRawEditMode ? "square.grid.2x2.fill" : "text.cursor")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(modeColor)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle().fill(modeColor.opacity(0.18))
                                    .overlay(Circle().strokeBorder(modeColor.opacity(0.4), lineWidth: 1))
                            )
                    }
                    .buttonStyle(.plain)
                    .help(isRawEditMode ? "Switch to Canvas View" : "Switch to Raw Text View")
                }
            }
        }
    }

    @ViewBuilder
    private var loreenPeekButton: some View {
        let revealed = isLoreenRevealedNow
        let requiresBio = settingsService.settings.loreenVeilRequireBiometricsForPeek
        let btnColor = revealed ? ThemeColors.accentGreen : ThemeColors.accentPurple

        if requiresBio {
            Button {
                triggerHaptic()
                if isBiometricRevealed {
                    withAnimation(.easeInOut(duration: 0.46)) {
                        isBiometricRevealed = false
                    }
                } else {
                    authenticateForLoreenReveal()
                }
            } label: {
                Image(systemName: revealed ? "eye.fill" : "eye.slash.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(btnColor)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(btnColor.opacity(0.18))
                            .overlay(Circle().strokeBorder(btnColor.opacity(revealed ? 0.85 : 0.4), lineWidth: revealed ? 1.5 : 1))
                    )
                    .shadow(color: revealed ? btnColor.opacity(0.45) : .clear, radius: 6)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(revealed ? "Re-veil Loreen (⌘⇧L)" : "Unlock Loreen Reveal")
        } else {
            Image(systemName: revealed ? "eye.fill" : "eye.slash.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(btnColor)
                .frame(width: 36, height: 36)
                .background(
                    Circle().fill(btnColor.opacity(0.18))
                        .overlay(Circle().strokeBorder(btnColor.opacity(revealed ? 0.85 : 0.4), lineWidth: revealed ? 1.5 : 1))
                )
                .shadow(color: revealed ? btnColor.opacity(0.45) : .clear, radius: 6)
                .scaleEffect(revealed ? 1.08 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: revealed)
                .contentShape(Circle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if !isPeekingLoreen {
                                triggerHaptic()
                                withAnimation(.easeInOut(duration: 0.46)) {
                                    isPeekingLoreen = true
                                }
                            }
                        }
                        .onEnded { _ in
                            withAnimation(.easeInOut(duration: 0.46)) {
                                isPeekingLoreen = false
                            }
                        }
                )
                .help("Hold to peek Loreen Veil (⌘⇧L to toggle)")
        }
    }

    private func authenticateForLoreenReveal() {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Reveal veiled Tagdos & Notes") { success, _ in
                Task { @MainActor in
                    if success {
                        withAnimation(.easeInOut(duration: 0.46)) {
                            isBiometricRevealed = true
                        }
                    }
                }
            }
        } else {
            withAnimation(.easeInOut(duration: 0.46)) {
                isBiometricRevealed = true
            }
        }
    }

    // MARK: - Stream Selector Tabs (All + S1..SN + Notes)
    private var streamSelectorBar: some View {
        let totalActive = store.streams.reduce(0) { $0 + $1.activePills.count }

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // First Tab: "All" (All Streams & Notes)
                Button {
                    triggerHaptic()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedStreamIndex = -1
                        isRawEditMode = false
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("All")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                        if totalActive > 0 {
                            Text("\(totalActive)")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.white.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    .foregroundColor(isAllTab ? .white : Color.white.opacity(0.68))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6.5)
                    .background(
                        Capsule()
                            .fill(isAllTab ? ThemeColors.accentCyan.opacity(0.32) : Color.white.opacity(0.06))
                            .overlay(
                                Capsule()
                                    .strokeBorder(isAllTab ? ThemeColors.accentCyan : Color.white.opacity(0.12), lineWidth: 1)
                            )
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)

                ForEach(Array(store.streams.enumerated()), id: \.element.id) { index, stream in
                    let isSelected = selectedStreamIndex == index
                    let hasAnyReminder = stream.streamReminder != nil || stream.clusters.contains(where: { $0.reminderDate != nil })

                    Button {
                        triggerHaptic()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedStreamIndex = index
                            rawTextBuffer = stream.rawText
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("S\(index + 1)")
                                .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                                .foregroundColor(isSelected ? .white : ThemeColors.accentPurple)
                                .frame(width: 20, height: 20)
                                .background(
                                    Circle()
                                        .fill(isSelected ? ThemeColors.accentPurple : ThemeColors.accentPurple.opacity(0.18))
                                        .overlay(
                                            Circle()
                                                .strokeBorder(ThemeColors.accentPurple.opacity(isSelected ? 0.8 : 0.4), lineWidth: 1)
                                        )
                                )

                            let trimmedCustom = stream.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
                            if let trimmedCustom, !trimmedCustom.isEmpty {
                                LoreenVeilText(trimmedCustom, isVeiled: isTagdosVeiled, size: 11, weight: .bold, design: .rounded)
                                    .foregroundColor(isSelected ? .white : Color.white.opacity(0.85))
                                    .lineLimit(1)
                                    .frame(maxWidth: 120, alignment: .leading)
                            } else if let driving = stream.drivingPill {
                                LoreenVeilText(driving.rawText, isVeiled: isTagdosVeiled, size: 11, weight: .bold, design: .rounded)
                                    .foregroundColor(isSelected ? .white : Color.white.opacity(0.85))
                                    .lineLimit(1)
                            }

                            if hasAnyReminder {
                                Image(systemName: "bell.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(ThemeColors.accentCyan)
                            }
                        }
                        .foregroundColor(isSelected ? .white : Color.white.opacity(0.6))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(isSelected ? ThemeColors.accentPurple.opacity(0.35) : Color.white.opacity(0.06))
                                .overlay(
                                    Capsule()
                                        .strokeBorder(isSelected ? ThemeColors.accentPurple : Color.white.opacity(0.12), lineWidth: 1)
                                )
                        )
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if index > 0 {
                            Button {
                                moveStreamPreservingSelection(from: index, to: index - 1)
                            } label: {
                                Label("Move Left", systemImage: "arrow.left")
                            }
                        }
                        if index < store.streams.count - 1 {
                            Button {
                                moveStreamPreservingSelection(from: index, to: index + 1)
                            } label: {
                                Label("Move Right", systemImage: "arrow.right")
                            }
                        }
                        Button {
                            triggerHaptic()
                            selectedStreamIndex = index
                            rawTextBuffer = stream.rawText
                            editingStreamTitle = stream.customTitle ?? stream.title
                            confirmDeleteStream = false
                            showingRenameSheet = true
                        } label: {
                            Label("Rename Stream...", systemImage: "pencil")
                        }
                        if store.streams.count > 1 {
                            Button {
                                triggerHaptic()
                                showingReorderSheet = true
                            } label: {
                                Label("Reorder Streams...", systemImage: "arrow.left.arrow.right")
                            }
                        }
                    }
                }

                // Add New Stream Button
                Button {
                    triggerHaptic()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        let created = store.createStream()
                        selectedStreamIndex = max(0, store.streams.count - 1)
                        rawTextBuffer = created.rawText
                        isRawEditMode = false
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(ThemeColors.accentCyan)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(ThemeColors.accentCyan.opacity(0.15))
                                .overlay(Circle().strokeBorder(ThemeColors.accentCyan.opacity(0.35), lineWidth: 1))
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Create New Stream")

                if store.streams.count > 1 {
                    Button {
                        triggerHaptic()
                        showingReorderSheet = true
                    } label: {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(ThemeColors.accentPurple)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(ThemeColors.accentPurple.opacity(0.15))
                                    .overlay(Circle().strokeBorder(ThemeColors.accentPurple.opacity(0.35), lineWidth: 1))
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Reorder Streams")
                }

                // Dedicated Quick Notes stream
                let isNotesSelected = selectedStreamIndex >= store.streams.count
                Button {
                    triggerHaptic()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedStreamIndex = store.streams.count
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "note.text")
                            .font(.system(size: 10, weight: .bold))
                        Text("Notes")
                            .font(.system(size: 11, weight: .bold, design: .rounded))

                        if !store.quickNotes.isEmpty {
                            Text("\(store.quickNotes.count)")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.white.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    .foregroundColor(isNotesSelected ? .white : Color.white.opacity(0.6))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(isNotesSelected ? ThemeColors.accentCyan.opacity(0.35) : Color.white.opacity(0.06))
                            .overlay(
                                Capsule()
                                    .strokeBorder(isNotesSelected ? ThemeColors.accentCyan : Color.white.opacity(0.12), lineWidth: 1)
                            )
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - "All" Overview Tab (Large-Widget-Style Full Hub Overview)
    @ViewBuilder
    private var allOverviewContent: some View {
        let totalActive = store.streams.reduce(0) { $0 + $1.activePills.count }
        let sortedNotes = store.quickNotes.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
            return $0.updatedAt > $1.updatedAt
        }

        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "checklist")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(ThemeColors.accentPurple)
                    Text("ALL STREAMS")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundColor(ThemeColors.accentPurple)

                    Spacer()

                    Text("\(totalActive) Active Tags")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(ThemeColors.accentCyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(ThemeColors.accentCyan.opacity(0.15))
                        .clipShape(Capsule())
                }

                Divider().background(Color.white.opacity(0.1))

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(store.streams.enumerated()), id: \.element.id) { index, stream in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 6) {
                                Button {
                                    triggerHaptic()
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                                        selectedStreamIndex = index
                                        rawTextBuffer = stream.rawText
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text("S\(index + 1)")
                                            .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                                            .foregroundColor(.white)
                                            .frame(width: 20, height: 20)
                                            .background(Circle().fill(ThemeColors.accentPurple.opacity(0.75)))

                                        LoreenVeilText(stream.displayTitle, isVeiled: isTagdosVeiled, size: 13, weight: .bold, design: .rounded)
                                            .foregroundColor(.white)
                                            .lineLimit(1)

                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(Color.white.opacity(0.35))
                                    }
                                }
                                .buttonStyle(.plain)

                                Spacer(minLength: 4)

                                if let rem = earliestReminder(for: stream) {
                                    HStack(spacing: 3) {
                                        Image(systemName: "bell.fill")
                                            .font(.system(size: 8))
                                        Text(timeFormatted(rem))
                                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                    }
                                    .foregroundColor(ThemeColors.accentCyan)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(ThemeColors.accentCyan.opacity(0.14))
                                    .clipShape(Capsule())
                                }

                                Text("\(stream.activePills.count) tags")
                                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                    .foregroundColor(Color.white.opacity(0.45))

                                if let driving = stream.drivingPill {
                                    HStack(spacing: 4) {
                                        Button {
                                            triggerHaptic()
                                            store.togglePillCompletion(streamId: stream.id, pillId: driving.id)
                                        } label: {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 8.5, weight: .heavy))
                                                .foregroundColor(ThemeColors.accentGreen)
                                                .frame(width: 20, height: 20)
                                                .background(
                                                    Circle()
                                                        .fill(ThemeColors.accentGreen.opacity(0.16))
                                                        .overlay(Circle().strokeBorder(ThemeColors.accentGreen.opacity(0.4), lineWidth: 0.8))
                                                )
                                        }
                                        .buttonStyle(.plain)

                                        Button {
                                            triggerHaptic()
                                            store.recyclePillToBack(streamId: stream.id, pillId: driving.id)
                                        } label: {
                                            Image(systemName: "arrow.triangle.2.circlepath")
                                                .font(.system(size: 8.5, weight: .bold))
                                                .foregroundColor(ThemeColors.accentCyan)
                                                .frame(width: 20, height: 20)
                                                .background(
                                                    Circle()
                                                        .fill(ThemeColors.accentCyan.opacity(0.16))
                                                        .overlay(Circle().strokeBorder(ThemeColors.accentCyan.opacity(0.4), lineWidth: 0.8))
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            let allPills = stream.allPills
                            if allPills.isEmpty {
                                Text("No tags yet")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.white.opacity(0.4))
                            } else {
                                let leadingId = stream.drivingPill?.id
                                FlowLayout(spacing: 6) {
                                    ForEach(allPills) { pill in
                                        interactivePill(pill: pill, streamId: stream.id, isLeading: pill.id == leadingId)
                                    }
                                }
                            }

                            let memoTrimmed = stream.activeMemos.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !memoTrimmed.isEmpty {
                                HStack(spacing: 5) {
                                    Image(systemName: "doc.text")
                                        .font(.system(size: 9.5))
                                        .foregroundColor(Color.white.opacity(0.45))
                                    LoreenVeilText(memoTrimmed.replacingOccurrences(of: "\n", with: " · "), isVeiled: isNotesVeiled, size: 10.5, weight: .medium)
                                        .foregroundColor(Color.white.opacity(0.6))
                                        .lineLimit(1)
                                }
                                .padding(.top, 2)
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white.opacity(0.04))
                                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                        )
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(hex: "081426").opacity(0.75))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            )

            // Quick Notes Overview Section (All Quick Notes)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "note.text")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(ThemeColors.accentOrange)
                        Text("QUICK NOTES")
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundColor(ThemeColors.accentOrange)
                        if !sortedNotes.isEmpty {
                            Text("\(sortedNotes.count)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(Color.white.opacity(0.65))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }

                    Spacer()

                    Button {
                        triggerHaptic()
                        isCreatingOverviewNote = true
                        activeOverviewNote = TagDoQuickNote(title: "", content: "")
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                            Text("New Note")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(ThemeColors.accentCyan)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Divider().background(Color.white.opacity(0.1))

                if sortedNotes.isEmpty {
                    Text("No quick notes yet. Click + New Note to jot down thoughts or markdown checklists.")
                        .font(.system(size: 12))
                        .foregroundColor(Color.white.opacity(0.5))
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 8) {
                        ForEach(sortedNotes) { note in
                            Button {
                                triggerHaptic()
                                isCreatingOverviewNote = false
                                activeOverviewNote = note
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        LoreenVeilText(note.displayTitle, isVeiled: isNotesVeiled, size: 13.5, weight: .bold, design: .rounded)
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Spacer()
                                        if note.isPinned {
                                            Image(systemName: "pin.fill")
                                                .font(.system(size: 10))
                                                .foregroundColor(ThemeColors.accentOrange)
                                        }
                                    }
                                    if !note.previewSnippet.isEmpty {
                                        LoreenVeilText(note.previewSnippet, isVeiled: isNotesVeiled, size: 11.5)
                                            .foregroundColor(Color.white.opacity(0.65))
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                                .padding(11)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.04))
                                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    store.togglePinQuickNote(id: note.id)
                                } label: {
                                    Label(note.isPinned ? "Unpin" : "Pin to Top", systemImage: note.isPinned ? "pin.slash" : "pin")
                                }
                                Button(role: .destructive) {
                                    store.deleteQuickNote(id: note.id)
                                } label: {
                                    Label("Delete Note", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(hex: "081426").opacity(0.75))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            )
        }
    }

    // MARK: - Interactive Canvas Card
    @ViewBuilder
    private var interactiveCanvasCard: some View {
        if let stream = currentStream {
            VStack(alignment: .leading, spacing: 14) {
                streamHeaderView(stream: stream)
                Divider().background(Color.white.opacity(0.12))
                clustersFlowView(stream: stream)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(hex: "081426").opacity(0.75))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            )
        }
    }

    private func streamHeaderView(stream: TagDoStream) -> some View {
        HStack {
            Button {
                triggerHaptic()
                editingStreamTitle = stream.customTitle ?? stream.title
                confirmDeleteStream = false
                showingRenameSheet = true
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        LoreenVeilText(stream.displayTitle, isVeiled: isTagdosVeiled, size: 16, weight: .bold, design: .rounded)
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.35))
                    }

                    Text("\(stream.activePills.count) active tags • \(stream.clusters.count) groups")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.55))
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                triggerHaptic()
                editingReminderClusterIndex = nil
                reminderPickerDate = stream.streamReminder ?? Date()
                showingReminderPicker = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: stream.streamReminder != nil ? "bell.fill" : "bell")
                        .font(.system(size: 11))
                    if let rem = stream.streamReminder {
                        Text(timeFormatted(rem))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    } else {
                        Text("+ Reminder")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .foregroundColor(ThemeColors.accentCyan)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(ThemeColors.accentCyan.opacity(0.15))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(ThemeColors.accentCyan.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private func clustersFlowView(stream: TagDoStream) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if stream.clusters.isEmpty {
                HStack {
                    Text("No tags yet. Add a tag or import external tasks.")
                        .font(.system(size: 12))
                        .foregroundColor(Color.white.opacity(0.5))
                    Spacer()
                    Button {
                        triggerHaptic()
                        addTagTargetStreamId = stream.id
                        newPillClusterIndex = 0
                        newTagInput = ""
                        showingAddTagSheet = true
                    } label: {
                        Text("+ Tag")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(ThemeColors.accentCyan)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(ThemeColors.accentCyan.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                )
            } else {
                ForEach(Array(stream.clusters.enumerated()), id: \.element.id) { clusterIndex, cluster in
                    let clusterKey = "cluster_\(stream.id.uuidString)_\(clusterIndex)"
                    SwipeableClusterCard(
                        cluster: cluster,
                        isHighlighted: highlightedClusterKey == clusterKey,
                        reminderFormattedText: cluster.reminderDate.map { timeFormatted($0) },
                        isDraggingAnyCluster: $isDraggingCluster,
                        onAddTag: {
                            triggerHaptic()
                            addTagTargetStreamId = stream.id
                            newPillClusterIndex = clusterIndex
                            newTagInput = ""
                            showingAddTagSheet = true
                        },
                        onSetReminder: {
                            triggerHaptic()
                            editingReminderClusterIndex = clusterIndex
                            reminderPickerDate = cluster.reminderDate ?? Date()
                            showingReminderPicker = true
                        }
                    ) {
                        FlowLayout(spacing: 6) {
                            ForEach(Array(cluster.pills.enumerated()), id: \.element.id) { pillIndex, pill in
                                interactivePill(pill: pill, streamId: stream.id, isLeading: pillIndex == 0)
                            }
                        }
                    }
                    .id(clusterKey)
                }
            }
        }
    }

    // MARK: - Interactive Pill Component
    @ViewBuilder
    private func interactivePill(pill: TagDoPill, streamId: UUID, isLeading: Bool) -> some View {
        Button {
            triggerHaptic()
            editingPillText = pill.rawText
            activePillAction = TagDoPillAction(streamId: streamId, pill: pill)
        } label: {
            HStack(spacing: 4) {
                if pill.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(ThemeColors.accentGreen)
                }

                LoreenVeilText(
                    pill.rawText,
                    isVeiled: isTagdosVeiled,
                    size: 12,
                    weight: .bold,
                    design: .rounded,
                    strikethrough: pill.isCompleted,
                    strikethroughColor: Color.white.opacity(0.4)
                )
                    .foregroundColor(pill.isCompleted ? Color.white.opacity(0.4) : pillColor(for: pill.type))

                if isLeading && !pill.isCompleted {
                    Image(systemName: "star.fill")
                        .font(.system(size: 7))
                        .foregroundColor(ThemeColors.accentOrange)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(pill.isCompleted ? Color.white.opacity(0.05) : pillColor(for: pill.type).opacity(0.16))
                    .overlay(
                        Capsule()
                            .strokeBorder(pill.isCompleted ? Color.white.opacity(0.1) : pillColor(for: pill.type).opacity(0.35), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Raw Text Editor Card
    private var rawEditorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 11))
                        .foregroundColor(ThemeColors.accentGreen)
                    Text("RAW LINE EDITOR (HIGH DENSITY)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(ThemeColors.accentGreen)
                }

                Spacer()

                Button {
                    triggerHaptic()
                    if let stream = currentStream {
                        store.updateStreamRawText(streamId: stream.id, newRawText: rawTextBuffer)
                        withAnimation { isRawEditMode = false }
                    }
                } label: {
                    Text("Save & Parse")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(ThemeColors.accentGreen.opacity(0.4))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Text("Format: Group1/Pill1/Pill2 & Group2/PillA/PillB\nUse $ or € for financial, ! for urgent, numbers for dates/specs.")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color.white.opacity(0.55))

            TextEditor(text: $rawTextBuffer)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
                .frame(minHeight: 160)
                .padding(10)
                .background(Color.black.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(hex: "081426").opacity(0.75))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        )
    }

    // MARK: - Pill Action Sheet
    @ViewBuilder
    private func pillActionSheet(for action: TagDoPillAction) -> some View {
        let trimmedEdit = editingPillText.trimmingCharacters(in: .whitespacesAndNewlines)
        let canSaveEdit = !trimmedEdit.isEmpty && trimmedEdit != action.pill.rawText

        VStack(spacing: 14) {
            HStack(spacing: 8) {
                TextField("Tag...", text: $editingPillText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(pillColor(for: action.pill.type))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(pillColor(for: action.pill.type).opacity(0.35), lineWidth: 1)
                    )
                    .onSubmit {
                        if canSaveEdit {
                            triggerHaptic()
                            store.updatePillText(streamId: action.streamId, pillId: action.pill.id, newText: trimmedEdit)
                            activePillAction = nil
                        }
                    }

                Button("Save") {
                    triggerHaptic()
                    store.updatePillText(streamId: action.streamId, pillId: action.pill.id, newText: trimmedEdit)
                    activePillAction = nil
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(canSaveEdit ? .black : Color.white.opacity(0.4))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(canSaveEdit ? ThemeColors.accentCyan : Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .disabled(!canSaveEdit)
            }

            VStack(spacing: 10) {
                Button {
                    triggerHaptic()
                    store.recyclePillToBack(streamId: action.streamId, pillId: action.pill.id)
                    activePillAction = nil
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(ThemeColors.accentCyan)
                        Text("Recycle to Back (Recurring)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                Button {
                    triggerHaptic()
                    store.togglePillCompletion(streamId: action.streamId, pillId: action.pill.id)
                    activePillAction = nil
                } label: {
                    HStack {
                        Image(systemName: action.pill.isCompleted ? "arrow.uturn.backward" : "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(ThemeColors.accentGreen)
                        Text(action.pill.isCompleted ? "Unmark Done" : "Mark Done (In Place)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                Button {
                    triggerHaptic()
                    store.movePillToFront(streamId: action.streamId, pillId: action.pill.id)
                    activePillAction = nil
                } label: {
                    HStack {
                        Image(systemName: "arrow.up.to.line")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(ThemeColors.accentOrange)
                        Text("Prioritize to Front")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                Button {
                    triggerHaptic()
                    store.removePill(streamId: action.streamId, pillId: action.pill.id)
                    activePillAction = nil
                } label: {
                    HStack {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(ThemeColors.accentPink)
                        Text("Delete Permanently (One-Off)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(ThemeColors.accentPink)
                        Spacer()
                    }
                    .padding(12)
                    .background(ThemeColors.accentPink.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(Color(hex: "081426"))
    }

    // MARK: - Add Tag Sheet
    private var addTagSheet: some View {
        VStack(spacing: 16) {
            Text("Add New Tag")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            TextField("e.g., MG, C$T, PL98, !MP$", text: $newTagInput)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .padding(12)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 10) {
                Button("Cancel") {
                    showingAddTagSheet = false
                }
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(0.6))
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)

                Button("Add Tag") {
                    triggerHaptic()
                    if let targetId = addTagTargetStreamId ?? currentStream?.id {
                        let clean = newTagInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !clean.isEmpty {
                            store.addPill(streamId: targetId, clusterIndex: newPillClusterIndex, text: clean)
                        }
                    }
                    showingAddTagSheet = false
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)
                .font(.system(size: 13, weight: .bold))
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(ThemeColors.accentCyan.opacity(0.35))
                .clipShape(Capsule())
            }
        }
        .padding(20)
        .background(Color(hex: "081426"))
    }

    // MARK: - Rename Stream Sheet
    private var renameStreamSheet: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Rename Stream")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                if let stream = currentStream, stream.customTitle != nil {
                    Button("Auto-detect") {
                        triggerHaptic()
                        store.updateStreamTitle(streamId: stream.id, newTitle: nil)
                        showingRenameSheet = false
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(ThemeColors.accentCyan)
                    .font(.system(size: 12, weight: .semibold))
                }
            }

            TextField("Stream title...", text: $editingStreamTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .padding(12)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            if store.streams.count > 1, selectedStreamIndex >= 0, selectedStreamIndex < store.streams.count {
                HStack(spacing: 10) {
                    Button {
                        moveStreamPreservingSelection(from: selectedStreamIndex, to: selectedStreamIndex - 1)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 11, weight: .bold))
                            Text("Move Left")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(selectedStreamIndex > 0 ? ThemeColors.accentCyan : Color.white.opacity(0.25))
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(selectedStreamIndex > 0 ? 0.08 : 0.03))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedStreamIndex == 0)

                    Button {
                        moveStreamPreservingSelection(from: selectedStreamIndex, to: selectedStreamIndex + 1)
                    } label: {
                        HStack(spacing: 5) {
                            Text("Move Right")
                                .font(.system(size: 12, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(selectedStreamIndex < store.streams.count - 1 ? ThemeColors.accentCyan : Color.white.opacity(0.25))
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(selectedStreamIndex < store.streams.count - 1 ? 0.08 : 0.03))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedStreamIndex >= store.streams.count - 1)
                }
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    showingRenameSheet = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)

                Button("Save") {
                    triggerHaptic()
                    if let stream = currentStream {
                        store.updateStreamTitle(streamId: stream.id, newTitle: editingStreamTitle)
                    }
                    showingRenameSheet = false
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)
                .font(.system(size: 13, weight: .bold))
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(ThemeColors.accentPurple.opacity(0.6))
                .clipShape(Capsule())
            }

            if store.streams.count > 1, let stream = currentStream {
                if confirmDeleteStream {
                    HStack(spacing: 10) {
                        Button("Keep Stream") {
                            confirmDeleteStream = false
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())

                        Button(role: .destructive) {
                            triggerHaptic()
                            store.deleteStream(streamId: stream.id)
                            selectedStreamIndex = min(max(0, selectedStreamIndex), max(0, store.streams.count - 1))
                            confirmDeleteStream = false
                            showingRenameSheet = false
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 12, weight: .bold))
                                Text("Confirm Delete")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(ThemeColors.accentPink.opacity(0.75))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Button(role: .destructive) {
                        triggerHaptic()
                        confirmDeleteStream = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .bold))
                            Text("Delete Stream")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(ThemeColors.accentPink)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(ThemeColors.accentPink.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .background(Color(hex: "081426"))
    }

    private func moveStreamPreservingSelection(from: Int, to: Int) {
        let activeId = currentStream?.id
        triggerHaptic()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            store.moveStream(fromIndex: from, toIndex: to)
            if let activeId, let updatedIdx = store.streams.firstIndex(where: { $0.id == activeId }) {
                selectedStreamIndex = updatedIdx
            }
        }
    }

    // MARK: - Reorder Streams Sheet
    private var reorderStreamsSheet: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Reorder Streams")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                Button("Done") {
                    showingReorderSheet = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(ThemeColors.accentCyan)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(ThemeColors.accentCyan.opacity(0.14))
                .clipShape(Capsule())
            }

            List {
                ForEach(Array(store.streams.enumerated()), id: \.element.id) { index, stream in
                    HStack(spacing: 12) {
                        Text("S\(index + 1)")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(ThemeColors.accentPurple))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(stream.displayTitle)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            if let driving = stream.drivingPill, stream.customTitle != nil {
                                Text(driving.rawText)
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundColor(.white.opacity(0.6))
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        HStack(spacing: 6) {
                            Button {
                                moveStreamPreservingSelection(from: index, to: index - 1)
                            } label: {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(index > 0 ? .white : .white.opacity(0.25))
                                    .frame(width: 28, height: 28)
                                    .background(Color.white.opacity(index > 0 ? 0.1 : 0.03))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .disabled(index == 0)

                            Button {
                                moveStreamPreservingSelection(from: index, to: index + 1)
                            } label: {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(index < store.streams.count - 1 ? .white : .white.opacity(0.25))
                                    .frame(width: 28, height: 28)
                                    .background(Color.white.opacity(index < store.streams.count - 1 ? 0.1 : 0.03))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .disabled(index >= store.streams.count - 1)
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.05))
                }
                .onMove { source, destination in
                    var ids = store.streams.map(\.id)
                    ids.move(fromOffsets: source, toOffset: destination)
                    let activeId = currentStream?.id
                    triggerHaptic()
                    store.reorderStreams(orderedIds: ids)
                    if let activeId, let updatedIdx = store.streams.firstIndex(where: { $0.id == activeId }) {
                        selectedStreamIndex = updatedIdx
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .padding(20)
        .background(Color(hex: "081426"))
    }

    // MARK: - Stream & Cluster Reminder Sheet
    private var reminderSheet: some View {
        let targetCluster: TagDoCluster? = {
            guard let cIdx = editingReminderClusterIndex,
                  let stream = currentStream,
                  cIdx >= 0 && cIdx < stream.clusters.count else { return nil }
            return stream.clusters[cIdx]
        }()
        let hasExistingReminder: Bool = {
            if let cluster = targetCluster {
                return cluster.reminderDate != nil
            }
            return currentStream?.streamReminder != nil
        }()
        let subtitle: String = {
            if let cluster = targetCluster {
                let preview = cluster.pills.prefix(4).map(\.rawText).joined(separator: " / ")
                return preview.isEmpty ? "Daily notification for this group" : "Group: \(preview)"
            }
            return currentStream?.displayTitle ?? "Daily stream notification"
        }()

        return VStack(spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(editingReminderClusterIndex != nil ? "Set Group Reminder" : "Set Stream Reminder")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.55))
                        .lineLimit(1)
                }
                Spacer()
                if hasExistingReminder, let stream = currentStream {
                    Button("Clear") {
                        triggerHaptic()
                        if let cIdx = editingReminderClusterIndex {
                            store.setClusterReminder(streamId: stream.id, clusterIndex: cIdx, date: nil)
                        } else {
                            store.setStreamReminder(streamId: stream.id, date: nil)
                        }
                        showingReminderPicker = false
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(ThemeColors.accentPink)
                    .font(.system(size: 12, weight: .semibold))
                }
            }

            DatePicker("Time", selection: $reminderPickerDate, displayedComponents: [.hourAndMinute])
                .datePickerStyle(.wheel)
                .labelsHidden()

            Button("Save Daily Reminder") {
                triggerHaptic()
                if let stream = currentStream {
                    if let cIdx = editingReminderClusterIndex {
                        store.setClusterReminder(streamId: stream.id, clusterIndex: cIdx, date: reminderPickerDate)
                    } else {
                        store.setStreamReminder(streamId: stream.id, date: reminderPickerDate)
                    }
                }
                showingReminderPicker = false
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)
            .font(.system(size: 13, weight: .bold))
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(ThemeColors.accentCyan.opacity(0.35))
            .clipShape(Capsule())
        }
        .padding(20)
        .background(Color(hex: "081426"))
    }

    // MARK: - Color & Formatter Helpers
    private func earliestReminder(for stream: TagDoStream) -> Date? {
        let candidates = ([stream.streamReminder] + stream.clusters.map(\.reminderDate)).compactMap { $0 }
        return candidates.min(by: { timeFormatted($0) < timeFormatted($1) })
    }

    private func pillColor(for type: TagDoPillType) -> Color {
        switch type {
        case .standard: return ThemeColors.accentCyan
        case .financial: return ThemeColors.accentGreen
        case .urgent: return ThemeColors.accentPink
        case .temporalOrMetric: return ThemeColors.accentOrange
        case .completed: return Color.white.opacity(0.35)
        }
    }

    private func timeFormatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Swipeable Cluster Card (Drag Right -> Left "+ Tag", Drag Left -> Right "Reminder")
private struct SwipeableClusterCard<Content: View>: View {
    let cluster: TagDoCluster
    let isHighlighted: Bool
    let reminderFormattedText: String?
    @Binding var isDraggingAnyCluster: Bool
    let onAddTag: () -> Void
    let onSetReminder: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var offsetX: CGFloat = 0
    @State private var restingOffsetX: CGFloat = 0

    private let revealWidth: CGFloat = 78
    private let fullTriggerThreshold: CGFloat = 118

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                if offsetX > 2 {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            offsetX = 0
                            restingOffsetX = 0
                        }
                        onAddTag()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .heavy))
                            Text("Tag")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.black)
                        .frame(width: min(max(offsetX - 6, 48), revealWidth - 4))
                        .frame(maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(ThemeColors.accentCyan)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 3)
                    .padding(.leading, 2)
                    .opacity(min(1.0, Double(offsetX) / 36.0))
                }

                Spacer(minLength: 0)

                if offsetX < -2 {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            offsetX = 0
                            restingOffsetX = 0
                        }
                        onSetReminder()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: reminderFormattedText != nil ? "bell.fill" : "bell.badge")
                                .font(.system(size: 11, weight: .bold))
                            if let rem = reminderFormattedText {
                                Text(rem)
                                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            } else {
                                Text("Alert")
                                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            }
                        }
                        .foregroundColor(.white)
                        .frame(width: min(max(-offsetX - 6, 48), revealWidth - 4))
                        .frame(maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(ThemeColors.accentPurple.opacity(0.88))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(ThemeColors.accentCyan.opacity(0.45), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 3)
                    .padding(.trailing, 2)
                    .opacity(min(1.0, Double(-offsetX) / 36.0))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                if let rem = reminderFormattedText {
                    HStack {
                        Spacer()
                        Button {
                            onSetReminder()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "bell.fill")
                                    .font(.system(size: 8))
                                Text(rem)
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(ThemeColors.accentCyan)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(ThemeColors.accentCyan.opacity(0.14))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                content()
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(hex: "0D1B30"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                isHighlighted ? ThemeColors.accentCyan : Color.white.opacity(0.09),
                                lineWidth: isHighlighted ? 1.8 : 1
                            )
                    )
            )
            // Subtle Left Edge Hint (Drag Right or Click -> Reveal "+ Tag")
            .overlay(alignment: .leading) {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        let next: CGFloat = restingOffsetX > 0 ? 0 : revealWidth
                        offsetX = next
                        restingOffsetX = next
                    }
                } label: {
                    Capsule()
                        .fill(ThemeColors.accentCyan.opacity(0.5))
                        .frame(width: 3, height: 18)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Drag right (or click edge) to add a tag")
            }
            // Subtle Right Edge Hint (Drag Left or Click -> Reveal "Reminder")
            .overlay(alignment: .trailing) {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        let next: CGFloat = restingOffsetX < 0 ? 0 : -revealWidth
                        offsetX = next
                        restingOffsetX = next
                    }
                } label: {
                    Capsule()
                        .fill((reminderFormattedText != nil ? ThemeColors.accentCyan : ThemeColors.accentPurple).opacity(0.55))
                        .frame(width: 3, height: 18)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Drag left (or click edge) to set a group reminder")
            }
            .offset(x: offsetX)
            .onTapGesture {
                if restingOffsetX != 0 {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        offsetX = 0
                        restingOffsetX = 0
                    }
                }
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 12, coordinateSpace: .local)
                    .onChanged { value in
                        let dx = value.translation.width
                        let dy = value.translation.height
                        guard abs(dx) > abs(dy) * 1.15 || isDraggingAnyCluster else { return }
                        if !isDraggingAnyCluster {
                            isDraggingAnyCluster = true
                        }
                        let proposed = restingOffsetX + dx
                        if proposed > revealWidth {
                            offsetX = revealWidth + (proposed - revealWidth) * 0.35
                        } else if proposed < -revealWidth {
                            offsetX = -revealWidth + (proposed + revealWidth) * 0.35
                        } else {
                            offsetX = proposed
                        }
                    }
                    .onEnded { value in
                        let totalX = restingOffsetX + value.translation.width
                        if totalX >= fullTriggerThreshold {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                offsetX = 0
                                restingOffsetX = 0
                            }
                            onAddTag()
                        } else if totalX <= -fullTriggerThreshold {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                offsetX = 0
                                restingOffsetX = 0
                            }
                            onSetReminder()
                        } else if totalX > 32 {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                offsetX = revealWidth
                                restingOffsetX = revealWidth
                            }
                        } else if totalX < -32 {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                offsetX = -revealWidth
                                restingOffsetX = -revealWidth
                            }
                        } else {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                offsetX = 0
                                restingOffsetX = 0
                            }
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                            isDraggingAnyCluster = false
                        }
                    }
            )
        }
        .clipped()
    }
}

// MARK: - Action Model for Pill Sheet
public struct TagDoPillAction: Identifiable {
    public var id: UUID { pill.id }
    public let streamId: UUID
    public let pill: TagDoPill
}

// MARK: - Custom FlowLayout for Dynamic Pill Wrapping
public struct FlowLayout: Layout {
    public var spacing: CGFloat = 6

    public init(spacing: CGFloat = 6) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? 350
        var totalH: CGFloat = 0
        var lineW: CGFloat = 0
        var lineH: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if lineW + size.width > maxW && lineW > 0 {
                totalH += lineH + spacing
                lineW = size.width + spacing
                lineH = size.height
            } else {
                lineW += size.width + spacing
                lineH = max(lineH, size.height)
            }
        }
        totalH += lineH
        return CGSize(width: maxW, height: totalH)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineH: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += lineH + spacing
                lineH = size.height
            } else {
                lineH = max(lineH, size.height)
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
        }
    }
}
