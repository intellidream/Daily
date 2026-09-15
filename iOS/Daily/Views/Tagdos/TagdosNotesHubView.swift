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
    @State private var newNoteText: String = ""

    // Pill Action Sheet / Dialog state
    @State private var activePillAction: TagDoPillAction? = nil
    @State private var newPillClusterIndex: Int = 0
    @State private var showingAddTagSheet: Bool = false
    @State private var newTagInput: String = ""

    // Stream Reminder Sheet state
    @State private var showingReminderPicker: Bool = false
    @State private var reminderPickerDate: Date = Date()

    public init() {}

    private var currentStream: TagDoStream? {
        guard selectedStreamIndex < store.streams.count else { return nil }
        return store.streams[selectedStreamIndex]
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

                // Stream Selector Tabs (1 to 5)
                streamSelectorBar
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                // Main Content Body: Interactive Canvas or Raw Text Editor
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        if isRawEditMode {
                            rawEditorCard
                        } else {
                            interactiveCanvasCard
                        }

                        // Bottom Memos & Notes Section
                        notesSectionCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }
        }
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
    }

    // MARK: - Navigation Bar
    private var navigationBar: some View {
        HStack {
            Button {
                triggerHaptic()
                dismiss()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                    Text("Dashboard")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .foregroundColor(ThemeColors.accentCyan)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
            }

            Spacer()

            Text("TAGDOS & NOTES")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Spacer()

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
                        HStack(spacing: 5) {
                            Text("S\(index + 1)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                            
                            if let driving = stream.drivingPill {
                                Text(driving.rawText)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .lineLimit(1)
                            }

                            if stream.streamReminder != nil {
                                Image(systemName: "bell.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(ThemeColors.accentCyan)
                            }
                        }
                        .foregroundColor(isSelected ? .white : Color.white.opacity(0.6))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
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
            VStack(alignment: .leading, spacing: 2) {
                Text(stream.title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("\(stream.activePills.count) active tags • \(stream.clusters.count) clusters")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.55))
            }

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

    // MARK: - Notes Section Card
    private var notesSectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "note.text")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(ThemeColors.accentOrange)
                    Text("ACTIVE MEMOS & QUICK NOTES")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                Spacer()
                Text("\(store.quickNotes.count) notes")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.5))
            }

            // Add Note Field
            HStack(spacing: 8) {
                TextField("Add quick memo or decode...", text: $newNoteText)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Button {
                    triggerHaptic()
                    store.addQuickNote(newNoteText)
                    newNoteText = ""
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(ThemeColors.accentCyan)
                }
                .disabled(newNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            // Notes List
            VStack(spacing: 6) {
                ForEach(Array(store.quickNotes.enumerated()), id: \.offset) { index, note in
                    HStack {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 4))
                            .foregroundColor(ThemeColors.accentOrange)
                        Text(note)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.85))
                        Spacer()
                        Button {
                            triggerHaptic()
                            store.removeQuickNote(at: index)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color.white.opacity(0.4))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
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
