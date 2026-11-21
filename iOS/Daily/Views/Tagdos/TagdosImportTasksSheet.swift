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
    @State private var draftItems: [ImportTaskDraft] = []

    @State private var isAuthenticating: Bool = false
    @State private var isLoadingLists: Bool = false
    @State private var isLoadingTasks: Bool = false
    @State private var errorMessage: String? = nil
    @State private var needsPermissionReauth: Bool = false

    @State private var destinationMode: TagdosStore.TagdosImportDestinationMode = .appendToStream
    @State private var targetStreamId: UUID? = nil
    @State private var newStreamTitle: String = ""

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

    private var selectedCount: Int {
        draftItems.filter { $0.isSelected && !$0.editedTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
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
                            destinationSection
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
            if targetStreamId == nil {
                targetStreamId = initialStreamId ?? store.streams.first?.id
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
            draftItems = []
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
                                if newStreamTitle.isEmpty || taskLists.contains(where: { $0.title == newStreamTitle }) {
                                    newStreamTitle = list.title
                                }
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
                } else if draftItems.isEmpty {
                    Text("No active tasks in this list.")
                        .font(.system(size: 12))
                        .foregroundColor(Color.white.opacity(0.5))
                        .padding(.vertical, 10)
                } else {
                    HStack {
                        Text("\(draftItems.count) active tasks")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.6))
                        Spacer()
                        Button("Select All") {
                            for idx in draftItems.indices { draftItems[idx].isSelected = true }
                        }
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(ThemeColors.accentCyan)
                        Text("•").foregroundColor(Color.white.opacity(0.3))
                        Button("Clear") {
                            for idx in draftItems.indices { draftItems[idx].isSelected = false }
                        }
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.6))
                    }

                    VStack(spacing: 8) {
                        ForEach($draftItems) { $draft in
                            ImportTaskDraftRow(draft: $draft)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Destination Section

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DESTINATION")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Color.white.opacity(0.5))

            HStack(spacing: 8) {
                destinationModeButton(mode: .appendToStream, label: "Append", icon: "plus.rectangle.on.rectangle")
                destinationModeButton(mode: .replaceStream, label: "Replace", icon: "arrow.triangle.2.circlepath")
                destinationModeButton(mode: .createNewStream, label: "New Stream", icon: "sparkles.rectangle.stack")
            }

            if destinationMode == .createNewStream {
                TextField("New stream title...", text: $newStreamTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(10)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.streams) { stream in
                            let isTarget = targetStreamId == stream.id
                            Button {
                                targetStreamId = stream.id
                            } label: {
                                Text("S\(stream.orderIndex + 1): \(stream.displayTitle)")
                                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                    .foregroundColor(isTarget ? .white : Color.white.opacity(0.7))
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule()
                                            .fill(isTarget ? ThemeColors.accentPurple.opacity(0.45) : Color.white.opacity(0.06))
                                            .overlay(Capsule().strokeBorder(isTarget ? ThemeColors.accentPurple : Color.white.opacity(0.12), lineWidth: 1))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if destinationMode == .replaceStream {
                    Text("Warning: Existing pills and active memos in the selected stream will be replaced.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(ThemeColors.accentOrange)
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func destinationModeButton(mode: TagdosStore.TagdosImportDestinationMode, label: String, icon: String) -> some View {
        let isSelected = destinationMode == mode
        return Button {
            destinationMode = mode
            if mode == .createNewStream && newStreamTitle.isEmpty {
                newStreamTitle = selectedList?.title ?? "Imported Stream"
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(label)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
            }
            .foregroundColor(isSelected ? .black : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? ThemeColors.accentCyan : Color.white.opacity(0.08))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
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
        draftItems = []
        defer { isLoadingLists = false }

        do {
            let lists = try await externalService.fetchTaskLists(for: account)
            taskLists = lists
            let defaultList = lists.first(where: \.isDefault) ?? lists.first
            selectedListId = defaultList?.id
            if let list = defaultList {
                if newStreamTitle.isEmpty {
                    newStreamTitle = list.title
                }
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
            draftItems = items.map { item in
                let prep = TagdosParser.shared.prepareImportItem(
                    title: item.title,
                    notes: item.notes,
                    isHighImportance: item.isHighImportance
                )
                return ImportTaskDraft(
                    id: item.id,
                    originalTitle: item.title,
                    originalNotes: item.notes,
                    isHighImportance: item.isHighImportance,
                    isAlreadyDsl: prep.isAlreadyDsl,
                    editedTag: prep.tagOrDsl
                )
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

    private func performImport() {
        let chosen = draftItems.filter {
            $0.isSelected && !$0.editedTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !chosen.isEmpty else { return }

        var dslChunks: [String] = []
        var memoLines: [String] = []

        for item in chosen {
            let tag = item.editedTag.trimmingCharacters(in: .whitespacesAndNewlines)
            dslChunks.append(tag)

            let notes = item.originalNotes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if item.isAlreadyDsl {
                if !notes.isEmpty {
                    memoLines.append("• [\(tag)] \(notes)")
                }
            } else {
                if notes.isEmpty {
                    memoLines.append("• [\(tag)] \(item.originalTitle)")
                } else {
                    memoLines.append("• [\(tag)] \(item.originalTitle) — \(notes)")
                }
            }
        }

        let updatedStream = store.importExternalTasks(
            mode: destinationMode,
            targetStreamId: targetStreamId,
            newStreamTitle: newStreamTitle,
            rawDslChunks: dslChunks,
            memoLines: memoLines
        )
        onImported(updatedStream.id)
        dismiss()
    }
}

private struct ImportTaskDraft: Identifiable {
    let id: String
    let originalTitle: String
    let originalNotes: String?
    let isHighImportance: Bool
    let isAlreadyDsl: Bool
    var editedTag: String
    var isSelected: Bool = true
}

private struct ImportTaskDraftRow: View {
    @Binding var draft: ImportTaskDraft

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
        }
        .padding(10)
        .background(Color.white.opacity(draft.isSelected ? 0.055 : 0.025))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
    }
}
