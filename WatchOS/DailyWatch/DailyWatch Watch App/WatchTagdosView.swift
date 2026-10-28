import SwiftUI
import WatchKit

struct WatchTagdosView: View {
    @ObservedObject var tagdosStore = WatchTagdosStore.shared
    @State private var showAddTaskSheet = false
    @State private var showAddNoteSheet = false
    @State private var newTaskText = ""
    @State private var newNoteTitle = ""
    @State private var newNoteContent = ""
    @State private var selectedNote: WatchTagDoQuickNote? = nil

    private var currentStream: WatchTagDoStream? {
        if tagdosStore.streams.indices.contains(tagdosStore.selectedStreamIndex) {
            return tagdosStore.streams[tagdosStore.selectedStreamIndex]
        }
        return tagdosStore.streams.first
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Header
                HStack(spacing: 4) {
                    Image(systemName: "list.bullet.rectangle.portrait")
                        .foregroundColor(Color(hex: "#00E5FF"))
                        .font(.system(size: 14, weight: .bold))
                    Text("TagDoS")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    if tagdosStore.isSyncing {
                        ProgressView()
                            .scaleEffect(0.6)
                    }
                }
                .padding(.horizontal, 4)

                // 5-Stream Driving Radar (Horizontal Scroll)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tagdosStore.streams.indices, id: \.self) { idx in
                            let stream = tagdosStore.streams[idx]
                            let isSelected = (idx == tagdosStore.selectedStreamIndex)
                            let drivingTag = stream.drivingPill?.rawText ?? "✓"
                            let count = stream.activePills.count

                            Button(action: {
                                WKInterfaceDevice.current().play(.click)
                                tagdosStore.selectedStreamIndex = idx
                            }) {
                                HStack(spacing: 4) {
                                    Text(stream.streamShortCode)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(isSelected ? .black : stream.streamColor)
                                    Text(drivingTag)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(isSelected ? .black : .white)
                                        .lineLimit(1)
                                    if count > 0 {
                                        Text("\(count)")
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(isSelected ? Color.black.opacity(0.3) : stream.streamColor.opacity(0.25))
                                            .foregroundColor(isSelected ? .black : stream.streamColor)
                                            .clipShape(Capsule())
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(isSelected ? stream.streamColor : Color(hex: "#1E222A"))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(isSelected ? stream.streamColor : Color.white.opacity(0.08), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 4)
                }

                // Active Stream Details & Queue
                if let stream = currentStream {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(stream.title.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(stream.streamColor)
                            Spacer()
                            Text("\(stream.activePills.count) pending")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .padding(.horizontal, 4)

                        if stream.activePills.isEmpty {
                            HStack {
                                Spacer()
                                VStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(Color(hex: "#10B981"))
                                        .font(.system(size: 20))
                                    Text("Queue Completed!")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                .padding(.vertical, 12)
                                Spacer()
                            }
                            .background(Color(hex: "#141820"))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        } else {
                            // Checklist items
                            ForEach(stream.activePills.prefix(6)) { pill in
                                let isDriving = (pill.id == stream.drivingPill?.id)

                                HStack(spacing: 6) {
                                    Button(action: {
                                        WKInterfaceDevice.current().play(.success)
                                        tagdosStore.completePill(streamNumber: stream.streamNumber, pillId: pill.id)
                                    }) {
                                        Image(systemName: "circle")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(pill.type.badgeColor)
                                    }
                                    .buttonStyle(.plain)

                                    Text(pill.rawText)
                                        .font(.system(size: 12, weight: isDriving ? .bold : .medium))
                                        .foregroundColor(.white)
                                        .lineLimit(1)

                                    Spacer()

                                    if isDriving {
                                        Text("LEAD")
                                            .font(.system(size: 8, weight: .black))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(pill.type.badgeColor.opacity(0.2))
                                            .foregroundColor(pill.type.badgeColor)
                                            .clipShape(Capsule())
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(isDriving ? pill.type.badgeColor.opacity(0.12) : Color(hex: "#141820"))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(isDriving ? pill.type.badgeColor.opacity(0.35) : Color.white.opacity(0.04), lineWidth: 1)
                                )
                            }

                            // Recycle Driving Action
                            if stream.activePills.count > 1 {
                                Button(action: {
                                    WKInterfaceDevice.current().play(.click)
                                    tagdosStore.recycleDrivingPill(streamNumber: stream.streamNumber)
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.uturn.forward.circle")
                                            .font(.system(size: 10))
                                        Text("Recycle Lead to End")
                                            .font(.system(size: 10, weight: .medium))
                                    }
                                    .foregroundColor(.white.opacity(0.6))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // Quick Action Buttons
                HStack(spacing: 6) {
                    Button(action: {
                        WKInterfaceDevice.current().play(.click)
                        newTaskText = ""
                        showAddTaskSheet = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 11))
                            Text("+ Task")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(Color(hex: "#00E5FF"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color(hex: "#141820"))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        WKInterfaceDevice.current().play(.click)
                        newNoteTitle = ""
                        newNoteContent = ""
                        showAddNoteSheet = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "note.text.badge.plus")
                                .font(.system(size: 11))
                            Text("+ Note")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(Color(hex: "#FFD600"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color(hex: "#141820"))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)

                // Pinned Quick Notes Section
                if !tagdosStore.quickNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "pin.fill")
                                .foregroundColor(Color(hex: "#FFD600"))
                                .font(.system(size: 10))
                            Text("PINNED NOTES")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.55))
                        }
                        .padding(.horizontal, 4)
                        .padding(.top, 6)

                        ForEach(tagdosStore.quickNotes.prefix(3)) { note in
                            Button(action: {
                                WKInterfaceDevice.current().play(.click)
                                selectedNote = note
                            }) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(note.title)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    Text(note.content)
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.6))
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(hex: "#141820"))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer(minLength: 16)
            }
            .padding(.horizontal, 6)
        }
        // Add Task Sheet
        .sheet(isPresented: $showAddTaskSheet) {
            VStack(spacing: 8) {
                Text("Add to \(currentStream?.streamShortCode ?? "Stream")")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(hex: "#00E5FF"))

                TextField("Action (e.g. CALL/BUY)", text: $newTaskText)
                    .font(.system(size: 12))

                HStack(spacing: 6) {
                    Button("Cancel") {
                        showAddTaskSheet = false
                    }
                    .font(.system(size: 11))

                    Button("Add") {
                        if !newTaskText.isEmpty, let streamNum = currentStream?.streamNumber {
                            tagdosStore.addQuickTask(streamNumber: streamNum, taskText: newTaskText)
                            WKInterfaceDevice.current().play(.success)
                        }
                        showAddTaskSheet = false
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "#00E5FF"))
                }
            }
        }
        // Add Note Sheet
        .sheet(isPresented: $showAddNoteSheet) {
            VStack(spacing: 8) {
                Text("New Quick Note")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(hex: "#FFD600"))

                TextField("Title", text: $newNoteTitle)
                    .font(.system(size: 12))

                TextField("Content", text: $newNoteContent)
                    .font(.system(size: 12))

                HStack(spacing: 6) {
                    Button("Cancel") {
                        showAddNoteSheet = false
                    }
                    .font(.system(size: 11))

                    Button("Save") {
                        tagdosStore.addQuickNote(title: newNoteTitle, content: newNoteContent)
                        WKInterfaceDevice.current().play(.success)
                        showAddNoteSheet = false
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "#FFD600"))
                }
            }
        }
        // View Note Detail Sheet
        .sheet(item: $selectedNote) { note in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "pin.fill")
                            .foregroundColor(Color(hex: "#FFD600"))
                            .font(.system(size: 11))
                        Text(note.title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }

                    Divider()

                    Text(note.content)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.85))

                    Spacer(minLength: 12)

                    Button("Close") {
                        selectedNote = nil
                    }
                    .font(.system(size: 11))
                }
                .padding()
            }
        }
    }
}
