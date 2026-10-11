import SwiftUI
import DailyCore

/// Dedicated Quick Notes stream featuring rich Markdown editing, live preview toggle,
/// search, pinning, and Supabase cloud synchronization.
public struct TagdosQuickNotesView: View {
    @ObservedObject private var store = TagdosStore.shared
    @State private var searchText: String = ""
    @State private var activeEditingNote: TagDoQuickNote? = nil
    @State private var isCreatingNewNote: Bool = false

    public init() {}

    private var filteredNotes: [TagDoQuickNote] {
        let all = store.quickNotes
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return all
        }
        let query = searchText.lowercased()
        return all.filter {
            $0.title.lowercased().contains(query) ||
            $0.content.lowercased().contains(query)
        }
    }

    private var pinnedNotes: [TagDoQuickNote] {
        filteredNotes.filter { $0.isPinned }
    }

    private var unpinnedNotes: [TagDoQuickNote] {
        filteredNotes.filter { !$0.isPinned }
    }

    public var body: some View {
        VStack(spacing: 14) {
            // MARK: - Search & New Note Action Bar
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundColor(Color.white.opacity(0.5))
                    TextField("Search notes...", text: $searchText)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(Color.white.opacity(0.5))
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.06))
                .cornerRadius(10)

                Button {
                    let newNote = TagDoQuickNote(
                        title: "",
                        content: ""
                    )
                    activeEditingNote = newNote
                    isCreatingNewNote = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("New")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(ThemeColors.accentCyan)
                    .clipShape(Capsule())
                }
            }

            // MARK: - Notes List
            if filteredNotes.isEmpty {
                emptyNotesState
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        if !pinnedNotes.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Pinned", systemImage: "pin.fill")
                                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                    .foregroundColor(ThemeColors.accentOrange)

                                ForEach(pinnedNotes) { note in
                                    noteRow(note)
                                }
                            }
                        }

                        if !unpinnedNotes.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                if !pinnedNotes.isEmpty {
                                    Label("All Notes", systemImage: "note.text")
                                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                        .foregroundColor(Color.white.opacity(0.45))
                                }

                                ForEach(unpinnedNotes) { note in
                                    noteRow(note)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .sheet(item: $activeEditingNote) { note in
            MarkdownNoteEditorSheet(
                note: note,
                isNew: isCreatingNewNote
            ) { updatedNote in
                if isCreatingNewNote {
                    store.createQuickNote(title: updatedNote.title, content: updatedNote.content)
                } else {
                    store.updateQuickNote(id: updatedNote.id, title: updatedNote.title, content: updatedNote.content)
                }
            }
        }
    }

    // MARK: - Note Row Card
    @ViewBuilder
    private func noteRow(_ note: TagDoQuickNote) -> some View {
        Button {
            isCreatingNewNote = false
            activeEditingNote = note
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(note.displayTitle)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Spacer()

                    if note.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 11))
                            .foregroundColor(ThemeColors.accentOrange)
                    }

                    Text(formattedDate(note.updatedAt))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.45))
                }

                if !note.previewSnippet.isEmpty {
                    Text(note.previewSnippet)
                        .font(.system(size: 12))
                        .foregroundColor(Color.white.opacity(0.65))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            )
        }
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

    private var emptyNotesState: some View {
        VStack(spacing: 12) {
            Image(systemName: "note.text.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(ThemeColors.accentCyan.opacity(0.5))
            Text("No Quick Notes Yet")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text("Create standalone markdown notes, research logs, checklists, or quick thoughts.")
                .font(.system(size: 12))
                .foregroundColor(Color.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .padding(.vertical, 40)
    }

    private func formattedDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return "Today \(f.string(from: date))"
        }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }
}

// MARK: - Markdown Note Editor Sheet
struct MarkdownNoteEditorSheet: View {
    @State var note: TagDoQuickNote
    let isNew: Bool
    let onSave: (TagDoQuickNote) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var isPreviewMode: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header Title Input
                TextField("Note Title", text: $note.title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.04))

                Divider().background(Color.white.opacity(0.1))

                // Toolbar: Mode Switcher + Formatting Tools
                HStack(spacing: 10) {
                    // Preview Toggle
                    Picker("Mode", selection: $isPreviewMode) {
                        Text("Edit").tag(false)
                        Text("Preview").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)

                    Spacer()

                    if !isPreviewMode {
                        HStack(spacing: 8) {
                            Button { insertText("# ") } label: {
                                Text("H1").bold().font(.system(size: 11))
                            }
                            Button { insertText("**bold**") } label: {
                                Text("B").bold().font(.system(size: 11))
                            }
                            Button { insertText("*italic*") } label: {
                                Text("I").italic().font(.system(size: 11))
                            }
                            Button { insertText("\n- [ ] ") } label: {
                                Image(systemName: "checkmark.square").font(.system(size: 11))
                            }
                            Button { insertText("\n- ") } label: {
                                Image(systemName: "list.bullet").font(.system(size: 11))
                            }
                            Button { insertText("[Link](url)") } label: {
                                Image(systemName: "link").font(.system(size: 11))
                            }
                        }
                        .foregroundColor(ThemeColors.accentCyan)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.3))

                Divider().background(Color.white.opacity(0.1))

                // Content: Editor or Rendered Markdown
                if isPreviewMode {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            if !note.title.isEmpty {
                                Text(note.title)
                                    .font(.title2.bold())
                                    .foregroundColor(.white)
                            }

                            Text(LocalizedStringKey(note.content))
                                .font(.system(size: 14))
                                .foregroundColor(Color.white.opacity(0.9))
                                .tint(ThemeColors.accentCyan)
                                .lineSpacing(5)
                                .textSelection(.enabled)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    TextEditor(text: $note.content)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.white)
                        .scrollContentBackground(.hidden)
                        .padding(16)
                        .background(Color.black)
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(isNew ? "New Note" : "Edit Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Color.white.opacity(0.7))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(note)
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(ThemeColors.accentCyan)
                }
            }
        }
    }

    private func insertText(_ text: String) {
        note.content += text
    }
}
