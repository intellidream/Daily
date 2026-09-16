import SwiftUI
import DailyCore
#if canImport(UIKit)
import UIKit
#endif

/// Comprehensive interactive hub for TagDoS mental tag pipelines and quick notes.
public struct TagdosNotesHubView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = TagdosStore.shared
    @ObservedObject private var settingsService = SettingsService.shared

    @State private var selectedStreamIndex: Int = 0
    @State private var isRawEditMode: Bool = false
    @State private var rawTextBuffer: String = ""

    // Pill Action Sheet / Dialog state
    @State private var activePillAction: TagDoPillAction? = nil
    @State private var newPillClusterIndex: Int = 0
    @State private var showingAddTagSheet: Bool = false
    @State private var newTagInput: String = ""

    // Stream Reminder Sheet state
    @State private var showingReminderPicker: Bool = false
    @State private var reminderPickerDate: Date = Date()

    // Stream Rename Sheet state
    @State private var showingRenameSheet: Bool = false
    @State private var editingStreamTitle: String = ""

    public var onNavigateBack: (() -> Void)? = nil

    public init(onNavigateBack: (() -> Void)? = nil) {
        self.onNavigateBack = onNavigateBack
    }

    private func handleBack() {
        triggerHaptic()
        if let onNavigateBack = onNavigateBack {
            onNavigateBack()
        } else {
            dismiss()
        }
    }

    private var currentStream: TagDoStream? {
        guard selectedStreamIndex < store.streams.count else { return nil }
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
        LiquidGlassBackground {
            VStack(spacing: 0) {
                // Top Navigation Bar
                navigationBar

                // Stream Selector Tabs (1 to 5 + Notes)
                streamSelectorBar
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                // Main Content Body: Interactive Canvas or Raw Text Editor or Quick Notes
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        if isNotesTab {
                            TagdosQuickNotesView()
                        } else {
                            if isRawEditMode {
                                rawEditorCard
                            } else {
                                interactiveCanvasCard
                            }

                            // Per-Stream Active Memos & Attachments
                            if let stream = currentStream {
                                TagdosActiveMemoView(streamId: stream.id, streamNumber: stream.orderIndex + 1)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
                .refreshable {
                    await store.syncWithSupabase()
                }
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 20, coordinateSpace: .global)
                .onEnded { value in
                    let startX = value.startLocation.x
                    let translationX = value.translation.width
                    let translationY = value.translation.height

                    // Edge swipe right: started within 75pt of left edge, dragged right > 50pt, horizontally dominant
                    if startX <= 75 && translationX > 50 && abs(translationX) > abs(translationY) * 1.1 {
                        handleBack()
                    }
                }
        )
        .onAppear {
            if let stream = currentStream {
                rawTextBuffer = stream.rawText
            }
        }
        .onChange(of: selectedStreamIndex) { _, newIndex in
            if newIndex < store.streams.count {
                rawTextBuffer = store.streams[newIndex].rawText
            }
        }
        .sheet(item: $activePillAction) { action in
            pillActionSheet(for: action)
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingAddTagSheet) {
            addTagSheet
                .presentationDetents([.height(200)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingReminderPicker) {
            reminderSheet
                .presentationDetents([.height(260)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingRenameSheet) {
            renameStreamSheet
                .presentationDetents([.height(240)])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Navigation Bar
    private var navigationBar: some View {
        HStack {
            Button {
                handleBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(ThemeColors.accentCyan)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }

            Spacer()

            HStack(spacing: 6) {
                Text("Tagdos & Notes")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
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

            if !isNotesTab {
                // Dual Mode Toggle: Canvas vs Raw Edit
                Button {
                    triggerHaptic()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        if isRawEditMode {
                            // Saving from raw text
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
                    HStack(spacing: 4) {
                        Image(systemName: isRawEditMode ? "square.grid.2x2.fill" : "text.cursor")
                            .font(.system(size: 11, weight: .bold))
                        Text(isRawEditMode ? "Canvas" : "Raw Text")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(isRawEditMode ? ThemeColors.accentGreen : ThemeColors.accentPurple)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background((isRawEditMode ? ThemeColors.accentGreen : ThemeColors.accentPurple).opacity(0.18))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder((isRawEditMode ? ThemeColors.accentGreen : ThemeColors.accentPurple).opacity(0.4), lineWidth: 1)
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - Stream Selector Tabs
    private var streamSelectorBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(store.streams.enumerated()), id: \.element.id) { index, stream in
                    let isSelected = selectedStreamIndex == index
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
                            
                            if let driving = stream.drivingPill {
                                Text(driving.rawText)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(isSelected ? .white : Color.white.opacity(0.85))
                                    .lineLimit(1)
                            }

                            if stream.streamReminder != nil {
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
                    }
                }

                // 6th Tab: Dedicated Quick Notes stream
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
                }
            }
            .padding(.horizontal, 16)
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
                showingRenameSheet = true
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(stream.displayTitle)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.35))
                    }

                    Text("\(stream.activePills.count) active tags • \(stream.clusters.count) clusters")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.55))
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                triggerHaptic()
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
        }
    }

    private func clustersFlowView(stream: TagDoStream) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(stream.clusters.enumerated()), id: \.element.id) { clusterIndex, cluster in
                clusterCardView(clusterIndex: clusterIndex, cluster: cluster, streamId: stream.id)

                if clusterIndex < stream.clusters.count - 1 {
                    HStack {
                        Spacer()
                        Text("&")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(ThemeColors.accentPurple)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(ThemeColors.accentPurple.opacity(0.15))
                            .clipShape(Capsule())
                        Spacer()
                    }
                }
            }
        }
    }

    private func clusterCardView(clusterIndex: Int, cluster: TagDoCluster, streamId: UUID) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CLUSTER \(clusterIndex + 1)")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.45))

                Spacer()

                Button {
                    triggerHaptic()
                    newPillClusterIndex = clusterIndex
                    newTagInput = ""
                    showingAddTagSheet = true
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                        Text("Tag")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundColor(ThemeColors.accentCyan)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(ThemeColors.accentCyan.opacity(0.12))
                    .clipShape(Capsule())
                }
            }

            FlowLayout(spacing: 6) {
                ForEach(Array(cluster.pills.enumerated()), id: \.element.id) { pillIndex, pill in
                    interactivePill(pill: pill, streamId: streamId, isLeading: pillIndex == 0)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        )
    }

    // MARK: - Interactive Pill Component
    @ViewBuilder
    private func interactivePill(pill: TagDoPill, streamId: UUID, isLeading: Bool) -> some View {
        Button {
            triggerHaptic()
            activePillAction = TagDoPillAction(streamId: streamId, pill: pill)
        } label: {
            HStack(spacing: 4) {
                if pill.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(ThemeColors.accentGreen)
                }

                Text(pill.rawText)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .strikethrough(pill.isCompleted, color: Color.white.opacity(0.4))
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
            }

            Text("Format: Cluster1/Pill1/Pill2 & Cluster2/PillA/PillB\nUse $ or € for financial, ! for urgent, numbers for dates/specs.")
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
        VStack(spacing: 16) {
            HStack {
                Text("Tag: \(action.pill.rawText)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(pillColor(for: action.pill.type))
                Spacer()
            }

            VStack(spacing: 10) {
                // Option 1: Recycle to back (Recurring)
                Button {
                    triggerHaptic()
                    store.recyclePillToBack(streamId: action.streamId, pillId: action.pill.id)
                    activePillAction = nil
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(ThemeColors.accentCyan)
                        Text("Recycle to Back (Mută la coadă • Recurent)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // Option 2: Toggle Done (Stay in place)
                Button {
                    triggerHaptic()
                    store.togglePillCompletion(streamId: action.streamId, pillId: action.pill.id)
                    activePillAction = nil
                } label: {
                    HStack {
                        Image(systemName: action.pill.isCompleted ? "arrow.uturn.backward" : "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(ThemeColors.accentGreen)
                        Text(action.pill.isCompleted ? "Unmark / Debifează" : "Mark Done (Bifează pe loc)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // Option 3: Move to Front (Prioritize)
                Button {
                    triggerHaptic()
                    store.movePillToFront(streamId: action.streamId, pillId: action.pill.id)
                    activePillAction = nil
                } label: {
                    HStack {
                        Image(systemName: "arrow.up.to.line")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(ThemeColors.accentOrange)
                        Text("Prioritizează la început de șir")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // Option 4: Delete permanently (One-off)
                Button {
                    triggerHaptic()
                    store.removePill(streamId: action.streamId, pillId: action.pill.id)
                    activePillAction = nil
                } label: {
                    HStack {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(ThemeColors.accentPink)
                        Text("Șterge definitiv (One-Off Task)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(ThemeColors.accentPink)
                        Spacer()
                    }
                    .padding(12)
                    .background(ThemeColors.accentPink.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(20)
        .background(Color(hex: "081426"))
    }

    // MARK: - Add Tag Sheet
    private var addTagSheet: some View {
        VStack(spacing: 16) {
            Text("Adaugă Tag Nou în Cluster")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            TextField("Ex: MG, C$T, PL98, !MP$", text: $newTagInput)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .padding(12)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 10) {
                Button("Anulează") {
                    showingAddTagSheet = false
                }
                .foregroundColor(.white.opacity(0.6))
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)

                Button("Adaugă Tag") {
                    triggerHaptic()
                    if let stream = currentStream {
                        let clean = newTagInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !clean.isEmpty {
                            store.addPill(streamId: stream.id, clusterIndex: newPillClusterIndex, text: clean)
                        }
                    }
                    showingAddTagSheet = false
                }
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
        VStack(spacing: 16) {
            HStack {
                Text("Redenumește Stream")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                if let stream = currentStream, stream.customTitle != nil {
                    Button("Auto-detect") {
                        triggerHaptic()
                        store.updateStreamTitle(streamId: stream.id, newTitle: nil)
                        showingRenameSheet = false
                    }
                    .foregroundColor(ThemeColors.accentCyan)
                    .font(.system(size: 12, weight: .semibold))
                }
            }

            TextField("Nume stream...", text: $editingStreamTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .padding(12)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 12) {
                Button("Anulează") {
                    showingRenameSheet = false
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)

                Button("Salvează") {
                    triggerHaptic()
                    if let stream = currentStream {
                        store.updateStreamTitle(streamId: stream.id, newTitle: editingStreamTitle)
                    }
                    showingRenameSheet = false
                }
                .foregroundColor(.white)
                .font(.system(size: 13, weight: .bold))
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(ThemeColors.accentPurple.opacity(0.6))
                .clipShape(Capsule())
            }
        }
        .padding(20)
        .background(Color(hex: "081426"))
    }

    // MARK: - Reminder Sheet
    private var reminderSheet: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Setează Reminder Stream")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                if let stream = currentStream, stream.streamReminder != nil {
                    Button("Șterge") {
                        triggerHaptic()
                        store.setStreamReminder(streamId: stream.id, date: nil)
                        showingReminderPicker = false
                    }
                    .foregroundColor(ThemeColors.accentPink)
                    .font(.system(size: 12, weight: .semibold))
                }
            }

            DatePicker("Ora", selection: $reminderPickerDate, displayedComponents: [.hourAndMinute])
                .datePickerStyle(.wheel)
                .labelsHidden()

            Button("Salvează Reminder") {
                triggerHaptic()
                if let stream = currentStream {
                    store.setStreamReminder(streamId: stream.id, date: reminderPickerDate)
                }
                showingReminderPicker = false
            }
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
