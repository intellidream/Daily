import SwiftUI
import DailyCore
import UIKit

/// Interactive sheet for importing tasks from Microsoft To Do or Google Tasks into TagDoS streams.
struct TagdosImportTasksSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = TagdosStore.shared
    @ObservedObject private var externalService = TagdosExternalTasksService.shared

    let initialStreamId: UUID?
    let onImported: (UUID) -> Void

    @State private var selectedProvider: ExternalTaskProvider = .microsoftToDo
    @State private var selectedAccountId: String? = nil
    @State private var taskLists: [ExternalTaskList] = []
    @State private var selectedListId: String? = nil
    @State private var stagedByTaskKey: [String: ImportTaskDraft] = [:]
    @State private var visibleTaskKeys: [String] = []

    @State private var isAuthenticating: Bool = false
    @State private var isLoadingLists: Bool = false
    @State private var isLoadingTasks: Bool = false
    @State private var errorMessage: String? = nil
    @State private var needsPermissionReauth: Bool = false

    @State private var defaultTargetChoice: ImportRowTargetChoice? = nil

    private var providerAccounts: [ExternalTaskAccount] {
        externalService.accounts.filter { $0.provider == selectedProvider }
    }

    private var selectedAccount: ExternalTaskAccount? {
        if let id = selectedAccountId, let match = providerAccounts.first(where: { $0.id == id }) {
            return match
        }
        return providerAccounts.first
    }

    private var selectedList: ExternalTaskList? {
        taskLists.first(where: { $0.id == selectedListId })
    }

    private var effectiveDefaultTarget: ImportRowTargetChoice {
        if let choice = defaultTargetChoice, isValidTargetChoice(choice) {
            return choice
        }
        if let firstId = initialStreamId ?? store.streams.first?.id {
            return .replaceStream(firstId)
        }
        return .newStream
    }

    private var selectedDraftsOrdered: [ImportTaskDraft] {
        let visibleSet = Set(visibleTaskKeys)
        let visibleSelected = visibleTaskKeys.compactMap { stagedByTaskKey[$0] }.filter {
            $0.isSelected && !$0.editedTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let offListSelected = stagedByTaskKey.values
            .filter { !visibleSet.contains($0.id) && $0.isSelected && !$0.editedTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.id < $1.id }
        return visibleSelected + offListSelected
    }

    private var selectedCount: Int {
        selectedDraftsOrdered.count
    }

    private var offListSelectedCount: Int {
        let visibleSet = Set(visibleTaskKeys)
        return stagedByTaskKey.values.filter {
            !visibleSet.contains($0.id) && $0.isSelected && !$0.editedTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
    }

    private func isValidTargetChoice(_ choice: ImportRowTargetChoice) -> Bool {
        switch choice {
        case .replaceStream(let id), .appendToStream(let id):
            return store.streams.contains(where: { $0.id == id })
        case .newStream:
            return true
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "060E1E").ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        providerSelectorSection
                        accountSection
                        if selectedAccount != nil {
                            listsAndTasksSection
                        }
                        if selectedCount > 0 {
                            importSummarySection
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Import Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Color.white.opacity(0.75))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import (\(selectedCount))") {
                        performImport()
                    }
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(selectedCount > 0 ? ThemeColors.accentCyan : Color.white.opacity(0.35))
                    .disabled(selectedCount == 0)
                }
            }
        }
        .task {
            if defaultTargetChoice == nil, let streamId = initialStreamId ?? store.streams.first?.id {
                defaultTargetChoice = .replaceStream(streamId)
            }
            await externalService.refreshAvailableAccounts()
            if selectedAccount == nil, let firstAny = externalService.accounts.first {
                selectedProvider = firstAny.provider
                selectedAccountId = firstAny.id
            } else {
                selectedAccountId = selectedAccount?.id
            }
            if let acc = selectedAccount {
                await loadLists(for: acc)
            }
        }
        .onChange(of: selectedProvider) { _, _ in
            errorMessage = nil
            needsPermissionReauth = false
            taskLists = []
            selectedListId = nil
            visibleTaskKeys = []
            selectedAccountId = providerAccounts.first?.id
            if let acc = selectedAccount {
                Task { await loadLists(for: acc) }
            }
        }
    }

    // MARK: - Provider Selector

    private var providerSelectorSection: some View {
        HStack(spacing: 8) {
            ForEach(ExternalTaskProvider.allCases) { provider in
                let isSelected = selectedProvider == provider
                Button {
                    selectedProvider = provider
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: provider == .microsoftToDo ? "checklist.checked" : "checkmark.circle.badge.questionmark")
                            .font(.system(size: 13, weight: .bold))
                        Text(provider.displayName)
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(isSelected ? .white : Color.white.opacity(0.65))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isSelected ? ThemeColors.accentPurple.opacity(0.38) : Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(isSelected ? ThemeColors.accentPurple : Color.white.opacity(0.12), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ACCOUNT")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.5))
                Spacer()
                if !providerAccounts.isEmpty {
                    Button {
                        Task { await signInCurrentProvider() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 11))
                            Text("Add Account")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(ThemeColors.accentCyan)
                    }
                }
            }

            if externalService.isLoadingAccounts {
                HStack(spacing: 8) {
                    ProgressView().tint(ThemeColors.accentCyan)
                    Text("Checking connected accounts...")
                        .font(.system(size: 12))
                        .foregroundColor(Color.white.opacity(0.7))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
            } else if providerAccounts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Connect your \(selectedProvider.displayName) account to browse your lists and import tasks into TagDoS.")
                        .font(.system(size: 12))
                        .foregroundColor(Color.white.opacity(0.7))

                    Button {
                        Task { await signInCurrentProvider() }
                    } label: {
                        HStack(spacing: 8) {
                            if isAuthenticating {
                                ProgressView().tint(.black)
                            } else {
                                Image(systemName: "person.badge.key.fill")
                            }
                            Text(isAuthenticating ? "Signing in..." : "Sign in with \(selectedProvider.displayName)")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(ThemeColors.accentCyan)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isAuthenticating)
                }
                .padding(14)
                .background(Color.white.opacity(0.05))
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(providerAccounts) { acc in
                            let isSelected = selectedAccount?.id == acc.id
                            Button {
                                selectedAccountId = acc.id
                                Task { await loadLists(for: acc) }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "person.circle")
                                        .font(.system(size: 12))
                                        .foregroundColor(isSelected ? ThemeColors.accentCyan : Color.white.opacity(0.5))
                                    Text(acc.email)
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? ThemeColors.accentCyan.opacity(0.2) : Color.white.opacity(0.06))
                                        .overlay(Capsule().strokeBorder(isSelected ? ThemeColors.accentCyan : Color.white.opacity(0.12), lineWidth: 1))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if let err = errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(err)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(ThemeColors.accentPink)

                    if needsPermissionReauth {
                        Button {
                            Task { await signInCurrentProvider() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Re-authenticate & Grant Tasks Access")
                            }
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(ThemeColors.accentCyan)
                            .clipShape(Capsule())
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ThemeColors.accentPink.opacity(0.12))
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Lists & Tasks Section

    private var listsAndTasksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("LISTS & TASKS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.5))
                Spacer()
                if let acc = selectedAccount {
                    Button {
                        Task { await loadLists(for: acc) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(ThemeColors.accentCyan)
                    }
                }
            }

            if isLoadingLists {
                HStack(spacing: 8) {
                    ProgressView().tint(ThemeColors.accentCyan)
                    Text("Loading task lists...")
                        .font(.system(size: 12))
                        .foregroundColor(Color.white.opacity(0.7))
                }
                .padding(12)
            } else if !taskLists.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(taskLists) { list in
                            let isSelected = selectedListId == list.id
                            Button {
                                selectedListId = list.id
                                if let acc = selectedAccount {
                                    Task { await loadTasks(for: acc, listId: list.id) }
                                }
                            } label: {
                                Text(list.title)
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundColor(isSelected ? .black : .white)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(isSelected ? ThemeColors.accentCyan : Color.white.opacity(0.08))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if isLoadingTasks {
                    HStack(spacing: 8) {
                        ProgressView().tint(ThemeColors.accentCyan)
                        Text("Fetching active tasks...")
                            .font(.system(size: 12))
                            .foregroundColor(Color.white.opacity(0.7))
                    }
                    .padding(.vertical, 12)
                } else if visibleTaskKeys.isEmpty {
                    Text("No active tasks in this list.")
                        .font(.system(size: 12))
                        .foregroundColor(Color.white.opacity(0.5))
                        .padding(.vertical, 10)
                } else {
                    defaultTargetBar

                    HStack {
                        Text("\(visibleTaskKeys.count) active tasks")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.6))
                        Spacer()
                        Button("Select All") {
                            for key in visibleTaskKeys {
                                stagedByTaskKey[key]?.isSelected = true
                            }
                        }
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(ThemeColors.accentCyan)
                        Text("•").foregroundColor(Color.white.opacity(0.3))
                        Button("Clear") {
                            for key in visibleTaskKeys {
                                stagedByTaskKey[key]?.isSelected = false
                            }
                        }
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.6))
                    }

                    VStack(spacing: 8) {
                        ForEach(visibleTaskKeys, id: \.self) { key in
                            if let draftBinding = bindingForDraft(key: key) {
                                ImportTaskDraftRow(
                                    draft: draftBinding,
                                    streams: store.streams
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private func bindingForDraft(key: String) -> Binding<ImportTaskDraft>? {
        guard stagedByTaskKey[key] != nil else { return nil }
        return Binding(
            get: { stagedByTaskKey[key]! },
            set: { stagedByTaskKey[key] = $0 }
        )
    }

    private var defaultTargetBar: some View {
        HStack(spacing: 8) {
            Text("Default:")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Color.white.opacity(0.65))

            Menu {
                targetChoiceMenuItems { choice in
                    defaultTargetChoice = choice
                }
            } label: {
                HStack(spacing: 5) {
                    Text(effectiveDefaultTarget.shortLabel(for: store.streams))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundColor(ThemeColors.accentCyan)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(ThemeColors.accentCyan.opacity(0.14))
                .clipShape(Capsule())
            }

            Spacer()

            let visibleSelectedCount = visibleTaskKeys.filter { stagedByTaskKey[$0]?.isSelected == true }.count
            if visibleSelectedCount > 0 {
                Button("Apply to \(visibleSelectedCount) checked") {
                    let chosenTarget = effectiveDefaultTarget
                    for key in visibleTaskKeys where stagedByTaskKey[key]?.isSelected == true {
                        stagedByTaskKey[key]?.targetChoice = chosenTarget
                    }
                }
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(ThemeColors.accentPurple.opacity(0.45))
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.045))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    @ViewBuilder
    private func targetChoiceMenuItems(onSelect: @escaping (ImportRowTargetChoice) -> Void) -> some View {
        Section("Replace Stream") {
            ForEach(store.streams) { stream in
                Button("Replace S\(stream.orderIndex + 1): \(stream.displayTitle)") {
                    onSelect(.replaceStream(stream.id))
                }
            }
        }
        Section("Append to Stream") {
            ForEach(store.streams) { stream in
                Button("Append S\(stream.orderIndex + 1): \(stream.displayTitle)") {
                    onSelect(.appendToStream(stream.id))
                }
            }
        }
        Section("Create Stream") {
            Button("+ New Stream") {
                onSelect(.newStream)
            }
        }
    }

    // MARK: - Staged Batch Summary Section

    private var importSummarySection: some View {
        let groupedSummary = buildBatchSummaryLines()
        let hasReplace = selectedDraftsOrdered.contains {
            if case .replaceStream = $0.targetChoice { return true }
            return false
        }

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("BATCH SUMMARY (\(selectedCount) TASK\(selectedCount == 1 ? "" : "S"))")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.5))
                Spacer()
                if offListSelectedCount > 0 {
                    Text("\(offListSelectedCount) from other list\(offListSelectedCount == 1 ? "" : "s")")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(ThemeColors.accentCyan)
                }
            }

            ForEach(groupedSummary, id: \.self) { line in
                Text(line)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.88))
            }

            if hasReplace {
                Text("Note: Replace targets clear existing pills and active memos on those streams before combining the mapped tasks.")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(ThemeColors.accentOrange)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func buildBatchSummaryLines() -> [String] {
        var counts: [ImportRowTargetChoice: Int] = [:]
        var order: [ImportRowTargetChoice] = []
        for draft in selectedDraftsOrdered {
            let resolved = isValidTargetChoice(draft.targetChoice) ? draft.targetChoice : .newStream
            if counts[resolved] == nil {
                order.append(resolved)
            }
            counts[resolved, default: 0] += 1
        }
        return order.map { choice in
            let c = counts[choice, default: 0]
            return "• \(c) task\(c == 1 ? "" : "s") → \(choice.shortLabel(for: store.streams))"
        }
    }

    // MARK: - Actions

    private func signInCurrentProvider() async {
        guard let windowScene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let anchor = windowScene.windows.first(where: \.isKeyWindow) ?? windowScene.windows.first else {
            errorMessage = "Unable to locate active window for sign-in."
            return
        }

        isAuthenticating = true
        errorMessage = nil
        needsPermissionReauth = false
        defer { isAuthenticating = false }

        do {
            let acc = try await externalService.signIn(provider: selectedProvider, presentationAnchor: anchor)
            selectedAccountId = acc.id
            await loadLists(for: acc)
        } catch ExternalTasksAuthError.cancelled {
            // User dismissed browser login
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadLists(for account: ExternalTaskAccount) async {
        isLoadingLists = true
        errorMessage = nil
        needsPermissionReauth = false
        visibleTaskKeys = []
        defer { isLoadingLists = false }

        do {
            let lists = try await externalService.fetchTaskLists(for: account)
            taskLists = lists
            let defaultList = lists.first(where: \.isDefault) ?? lists.first
            selectedListId = defaultList?.id
            if let list = defaultList {
                await loadTasks(for: account, listId: list.id)
            }
        } catch let authErr as ExternalTasksAuthError {
            errorMessage = authErr.localizedDescription
            switch authErr {
            case .missingTasksPermission, .tokenExpired:
                needsPermissionReauth = true
            default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadTasks(for account: ExternalTaskAccount, listId: String) async {
        isLoadingTasks = true
        errorMessage = nil
        defer { isLoadingTasks = false }

        do {
            let items = try await externalService.fetchTasks(for: account, listId: listId)
            var keys: [String] = []
            let fallbackTarget = effectiveDefaultTarget
            for item in items {
                let key = "\(account.provider.rawValue)::\(account.id)::\(listId)::\(item.id)"
                keys.append(key)
                if stagedByTaskKey[key] == nil {
                    let prep = TagdosParser.shared.prepareImportItem(
                        title: item.title,
                        notes: item.notes,
                        isHighImportance: item.isHighImportance
                    )
                    stagedByTaskKey[key] = ImportTaskDraft(
                        id: key,
                        originalTitle: item.title,
                        originalNotes: item.notes,
                        isHighImportance: item.isHighImportance,
                        isAlreadyDsl: prep.isAlreadyDsl,
                        editedTag: prep.tagOrDsl,
                        isSelected: false,
                        targetChoice: fallbackTarget,
                        newStreamTitle: ""
                    )
                }
            }
            visibleTaskKeys = keys
        } catch let authErr as ExternalTasksAuthError {
            errorMessage = authErr.localizedDescription
            switch authErr {
            case .missingTasksPermission, .tokenExpired:
                needsPermissionReauth = true
            default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performImport() {
        let chosen = selectedDraftsOrdered
        guard !chosen.isEmpty else { return }

        let batchItems: [TagdosStore.TagdosTaskImportItem] = chosen.map { draft in
            let tag = draft.editedTag.trimmingCharacters(in: .whitespacesAndNewlines)
            let notes = draft.originalNotes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let memoLine: String?
            if draft.isAlreadyDsl {
                memoLine = notes.isEmpty ? nil : notes
            } else {
                memoLine = notes.isEmpty
                    ? "• [\(tag)] \(draft.originalTitle)"
                    : "• [\(tag)] \(draft.originalTitle) — \(notes)"
            }

            let resolvedChoice = isValidTargetChoice(draft.targetChoice) ? draft.targetChoice : .newStream
            let storeTarget: TagdosStore.TagdosTaskImportTarget
            switch resolvedChoice {
            case .replaceStream(let streamId):
                storeTarget = .replaceStream(streamId)
            case .appendToStream(let streamId):
                storeTarget = .appendToStream(streamId)
            case .newStream:
                storeTarget = .newStream(title: draft.newStreamTitle)
            }

            return TagdosStore.TagdosTaskImportItem(
                dslOrTag: tag,
                memoLine: memoLine,
                target: storeTarget
            )
        }

        if let importedStreamId = store.importExternalTaskBatch(batchItems) {
            onImported(importedStreamId)
            dismiss()
        }
    }
}

private enum ImportRowTargetChoice: Equatable, Hashable {
    case replaceStream(UUID)
    case appendToStream(UUID)
    case newStream

    func shortLabel(for streams: [TagDoStream]) -> String {
        switch self {
        case .replaceStream(let id):
            if let idx = streams.firstIndex(where: { $0.id == id }) {
                return "Replace S\(idx + 1) (\(streams[idx].displayTitle))"
            }
            return "Replace Stream"
        case .appendToStream(let id):
            if let idx = streams.firstIndex(where: { $0.id == id }) {
                return "Append S\(idx + 1) (\(streams[idx].displayTitle))"
            }
            return "Append Stream"
        case .newStream:
            return "+ New Stream"
        }
    }

    var isReplace: Bool {
        if case .replaceStream = self { return true }
        return false
    }
}

private struct ImportTaskDraft: Identifiable {
    let id: String
    let originalTitle: String
    let originalNotes: String?
    let isHighImportance: Bool
    let isAlreadyDsl: Bool
    var editedTag: String
    var isSelected: Bool
    var targetChoice: ImportRowTargetChoice
    var newStreamTitle: String
}

private struct ImportTaskDraftRow: View {
    @Binding var draft: ImportTaskDraft
    let streams: [TagDoStream]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    draft.isSelected.toggle()
                } label: {
                    Image(systemName: draft.isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(draft.isSelected ? ThemeColors.accentCyan : Color.white.opacity(0.4))
                }
                .buttonStyle(.plain)

                TextField("Tag or DSL", text: $draft.editedTag)
                    .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.35))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))

                Text(draft.isAlreadyDsl ? "DSL" : "AUTO + MEMO")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundColor(draft.isAlreadyDsl ? ThemeColors.accentCyan : ThemeColors.accentOrange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background((draft.isAlreadyDsl ? ThemeColors.accentCyan : ThemeColors.accentOrange).opacity(0.15))
                    .clipShape(Capsule())
            }

            if !draft.isAlreadyDsl {
                Text(draft.originalTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.65))
                    .lineLimit(2)
                    .padding(.leading, 24)
            }
            if let notes = draft.originalNotes, !notes.isEmpty {
                Text(notes)
                    .font(.system(size: 10.5))
                    .foregroundColor(Color.white.opacity(0.45))
                    .lineLimit(2)
                    .padding(.leading, 24)
            }

            HStack(spacing: 8) {
                Menu {
                    Section("Replace Stream") {
                        ForEach(streams) { stream in
                            Button("Replace S\(stream.orderIndex + 1): \(stream.displayTitle)") {
                                draft.targetChoice = .replaceStream(stream.id)
                                draft.isSelected = true
                            }
                        }
                    }
                    Section("Append to Stream") {
                        ForEach(streams) { stream in
                            Button("Append S\(stream.orderIndex + 1): \(stream.displayTitle)") {
                                draft.targetChoice = .appendToStream(stream.id)
                                draft.isSelected = true
                            }
                        }
                    }
                    Section("Create Stream") {
                        Button("+ New Stream") {
                            draft.targetChoice = .newStream
                            draft.isSelected = true
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: draft.targetChoice.isReplace ? "arrow.triangle.2.circlepath" : (draft.targetChoice == .newStream ? "sparkles" : "plus.rectangle.on.rectangle"))
                            .font(.system(size: 9.5, weight: .bold))
                        Text(draft.targetChoice.shortLabel(for: streams))
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8.5, weight: .bold))
                    }
                    .foregroundColor(draft.targetChoice.isReplace ? ThemeColors.accentOrange : ThemeColors.accentCyan)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background((draft.targetChoice.isReplace ? ThemeColors.accentOrange : ThemeColors.accentCyan).opacity(0.14))
                    .clipShape(Capsule())
                }

                if draft.targetChoice == .newStream {
                    TextField("Optional title...", text: $draft.newStreamTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(6)
                }
            }
            .padding(.leading, 24)
        }
        .padding(10)
        .background(Color.white.opacity(draft.isSelected ? 0.055 : 0.025))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(draft.isSelected ? 0.16 : 0.08), lineWidth: 1))
    }
}
