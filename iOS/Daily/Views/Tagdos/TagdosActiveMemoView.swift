import SwiftUI
import PhotosUI
import QuickLook
import DailyCore

/// Interactive per-stream memo and attachment viewer with Markdown formatting, clickable hyperlinks,
/// on-demand cloud downloading, and local caching.
public struct TagdosActiveMemoView: View {
    public let streamId: UUID
    public let streamNumber: Int
    @ObservedObject private var store = TagdosStore.shared

    @State private var isCollapsed: Bool = true
    @State private var isEditingText: Bool = false
    @State private var memoDraft: String = ""
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var showingFileImporter: Bool = false
    @State private var downloadingAttachmentId: UUID? = nil
    @State private var previewAttachment: TagDoAttachment? = nil
    @State private var previewURL: URL? = nil

    public init(streamId: UUID, streamNumber: Int) {
        self.streamId = streamId
        self.streamNumber = streamNumber
    }

    private var currentStream: TagDoStream? {
        store.streams.first(where: { $0.id == streamId })
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: isCollapsed ? 0 : 14) {
            // MARK: - Collapsible Header
            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isCollapsed.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "note.text")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(ThemeColors.accentCyan)
                        Text("Active Memos")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        let hasMemos = currentStream?.activeMemos.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        let attCount = currentStream?.attachments.count ?? 0

                        if hasMemos || attCount > 0 {
                            HStack(spacing: 4) {
                                if hasMemos {
                                    Text("Memo")
                                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                        .foregroundColor(ThemeColors.accentCyan)
                                }
                                if attCount > 0 {
                                    HStack(spacing: 2.5) {
                                        Image(systemName: "paperclip")
                                            .font(.system(size: 8, weight: .bold))
                                        Text("\(attCount)")
                                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                    }
                                    .foregroundColor(ThemeColors.accentOrange)
                                }
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                if !isCollapsed {
                    Button {
                        if isEditingText {
                            // Save edits
                            store.updateStreamMemos(streamId: streamId, memos: memoDraft)
                            isEditingText = false
                        } else {
                            memoDraft = currentStream?.activeMemos ?? ""
                            isEditingText = true
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isEditingText ? "checkmark" : "pencil")
                                .font(.system(size: 10, weight: .bold))
                            Text(isEditingText ? "Done" : "Edit")
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(isEditingText ? ThemeColors.accentGreen : ThemeColors.accentCyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background((isEditingText ? ThemeColors.accentGreen : ThemeColors.accentCyan).opacity(0.15))
                        .clipShape(Capsule())
                    }
                }

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isCollapsed.toggle()
                    }
                } label: {
                    Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.45))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            if !isCollapsed {
                // MARK: - Memo Body (View or Edit)
                if isEditingText {
                    editingView
                } else {
                    formattedViewer
                }

                // MARK: - Attachments Section
                attachmentsSection
            }
        }
        .padding(isCollapsed ? 12 : 14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        )
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem = newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    let fileName = "photo_\(Date().timeIntervalSince1970).jpg"
                    try? await store.addAttachment(
                        streamId: streamId,
                        data: data,
                        fileName: fileName,
                        mimeType: "image/jpeg"
                    )
                }
                await MainActor.run {
                    selectedPhotoItem = nil
                }
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let selectedURL = urls.first else { return }
                guard selectedURL.startAccessingSecurityScopedResource() else { return }
                defer { selectedURL.stopAccessingSecurityScopedResource() }
                
                if let data = try? Data(contentsOf: selectedURL) {
                    let fileName = selectedURL.lastPathComponent
                    let mimeType = selectedURL.pathExtension.lowercased() == "pdf" ? "application/pdf" : "application/octet-stream"
                    Task {
                        try? await store.addAttachment(
                            streamId: streamId,
                            data: data,
                            fileName: fileName,
                            mimeType: mimeType
                        )
                    }
                }
            case .failure(let error):
                print("[TagdosActiveMemoView] File import error: \(error.localizedDescription)")
            }
        }
        .sheet(item: $previewAttachment) { att in
            AttachmentPreviewSheet(attachment: att, initialURL: previewURL)
        }
    }

    // MARK: - Formatted Viewer Mode
    @ViewBuilder
    private var formattedViewer: some View {
        let text = currentStream?.activeMemos.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .foregroundColor(Color.white.opacity(0.3))
                Text("Tap Edit to add stream notes, instructions, checklists, or links...")
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.4))
            }
            .padding(.vertical, 6)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(LocalizedStringKey(text))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.9))
                    .tint(ThemeColors.accentCyan)
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.white.opacity(0.025))
            .cornerRadius(12)
        }
    }

    // MARK: - Editing Mode with Formatting Toolbar
    private var editingView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Quick formatting tools
            HStack(spacing: 8) {
                Button { insertFormatting(prefix: "**", suffix: "**") } label: {
                    Text("B").bold().frame(width: 24, height: 24)
                }
                Button { insertFormatting(prefix: "*", suffix: "*") } label: {
                    Text("I").italic().frame(width: 24, height: 24)
                }
                Button { insertFormatting(prefix: "\n- ", suffix: "") } label: {
                    Image(systemName: "list.bullet").frame(width: 24, height: 24)
                }
                Button { insertFormatting(prefix: "\n- [ ] ", suffix: "") } label: {
                    Image(systemName: "checkmark.square").frame(width: 24, height: 24)
                }
                Button { insertFormatting(prefix: "[Link](", suffix: ")") } label: {
                    Image(systemName: "link").frame(width: 24, height: 24)
                }
                Spacer()
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(ThemeColors.accentCyan)
            .padding(.horizontal, 4)

            TextEditor(text: $memoDraft)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white)
                .frame(minHeight: 110)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.black.opacity(0.35))
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(ThemeColors.accentCyan.opacity(0.3), lineWidth: 1))
        }
    }

    private func insertFormatting(prefix: String, suffix: String) {
        memoDraft += "\(prefix)text\(suffix)"
    }

    // MARK: - Attachments Carousel
    private var attachmentsSection: some View {
        let attachments = currentStream?.attachments ?? []

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(ThemeColors.accentOrange)
                    Text("Attachments (\(attachments.count))")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.85))
                }

                Spacer()

                // Add Photo Button
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    HStack(spacing: 3) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("Photo")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(ThemeColors.accentOrange)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(ThemeColors.accentOrange.opacity(0.15))
                    .clipShape(Capsule())
                }

                // Add File Button
                Button {
                    showingFileImporter = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("File")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(ThemeColors.accentCyan)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(ThemeColors.accentCyan.opacity(0.15))
                    .clipShape(Capsule())
                }
            }

            if attachments.isEmpty {
                Text("No attachments in this stream yet. Attach photos or documents for quick access.")
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.35))
                    .padding(.vertical, 2)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(attachments) { att in
                            attachmentCard(att)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Individual Attachment Card
    @ViewBuilder
    private func attachmentCard(_ att: TagDoAttachment) -> some View {
        let isLocal = TagdosAttachmentManager.shared.isDownloaded(att)
        let isDownloading = downloadingAttachmentId == att.id

        Button {
            handleAttachmentTap(att)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 100, height: 70)

                    if isDownloading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: ThemeColors.accentCyan))
                    } else if isLocal, att.isImage, let localURL = TagdosAttachmentManager.shared.getLocalFileURL(for: att),
                              let uiImage = UIImage(contentsOfFile: localURL.path) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 100, height: 70)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        VStack(spacing: 4) {
                            Image(systemName: att.isImage ? "photo.fill" : "doc.text.fill")
                                .font(.system(size: 22))
                                .foregroundColor(att.isImage ? ThemeColors.accentOrange : ThemeColors.accentCyan)
                        }
                    }

                    // Cloud status indicator
                    if !isLocal && !isDownloading {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "icloud.and.arrow.down.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white)
                                    .padding(4)
                                    .background(Color.black.opacity(0.6))
                                    .clipShape(Circle())
                            }
                            Spacer()
                        }
                        .padding(4)
                    }
                }

                Text(att.fileName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(width: 100, alignment: .leading)

                HStack {
                    Text(att.formattedSize)
                        .font(.system(size: 8.5))
                        .foregroundColor(Color.white.opacity(0.45))
                    Spacer()
                    if !isLocal {
                        Text("Cloud")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(ThemeColors.accentCyan)
                    }
                }
                .frame(width: 100)
            }
            .padding(6)
            .background(Color.white.opacity(0.03))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }
        .contextMenu {
            if isLocal, let localURL = TagdosAttachmentManager.shared.getLocalFileURL(for: att) {
                ShareLink(item: localURL) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            Button(role: .destructive) {
                Task {
                    await store.deleteAttachment(streamId: streamId, attachmentId: att.id)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func handleAttachmentTap(_ att: TagDoAttachment) {
        if TagdosAttachmentManager.shared.isDownloaded(att) {
            previewURL = TagdosAttachmentManager.shared.getLocalFileURL(for: att)
            previewAttachment = att
        } else {
            // Trigger on-demand download
            downloadingAttachmentId = att.id
            Task {
                do {
                    let localURL = try await store.downloadAttachment(att)
                    await MainActor.run {
                        downloadingAttachmentId = nil
                        previewURL = localURL
                        previewAttachment = att
                    }
                } catch {
                    await MainActor.run {
                        downloadingAttachmentId = nil
                    }
                    print("[TagdosActiveMemoView] Download error: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - Attachment Preview Sheet
struct AttachmentPreviewSheet: View {
    let attachment: TagDoAttachment
    let initialURL: URL?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if attachment.isImage, let url = initialURL ?? TagdosAttachmentManager.shared.getLocalFileURL(for: attachment),
                   let uiImage = UIImage(contentsOfFile: url.path) {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding()
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 60))
                            .foregroundColor(ThemeColors.accentCyan)
                        Text(attachment.fileName)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                        Text(attachment.formattedSize)
                            .font(.system(size: 13))
                            .foregroundColor(Color.white.opacity(0.6))

                        if let url = initialURL ?? TagdosAttachmentManager.shared.getLocalFileURL(for: attachment) {
                            ShareLink(item: url) {
                                Label("Share Document", systemImage: "square.and.arrow.up")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(ThemeColors.accentCyan)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(attachment.fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(ThemeColors.accentCyan)
                }
            }
        }
    }
}
