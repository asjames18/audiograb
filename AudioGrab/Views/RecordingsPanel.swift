import SwiftUI

struct RecordingsPanel: View {
    @EnvironmentObject private var model: AppModel
    @State private var renaming: RecordingItem?
    @State private var renameText = ""
    @State private var trashing: RecordingItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recordings").font(.headline)
                Text("\(model.recordings.count)").foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.refreshRecordings()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")
                Button {
                    model.openOutputFolder()
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Open the recordings folder")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            if model.recordings.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "waveform").font(.largeTitle).foregroundStyle(.tertiary)
                    Text("No recordings yet").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 20)
            } else {
                List(model.recordings) { item in
                    RecordingRow(item: item,
                                 onRename: { startRename(item) },
                                 onTrash: { trashing = item })
                }
                .listStyle(.inset)
            }
        }
        .frame(minHeight: 180)
        .sheet(item: $renaming) { item in
            RenameSheet(item: item, text: $renameText) { newName in
                model.rename(item, to: newName)
                renaming = nil
            } onCancel: {
                renaming = nil
            }
        }
        .confirmationDialog("Move “\(trashing?.url.lastPathComponent ?? "")” to the Trash?",
                            isPresented: Binding(get: { trashing != nil }, set: { if !$0 { trashing = nil } }),
                            presenting: trashing) { item in
            Button("Move to Trash", role: .destructive) { model.moveToTrash(item) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("You can restore it from the Trash later.")
        }
    }

    private func startRename(_ item: RecordingItem) {
        renameText = item.name
        renaming = item
    }
}

struct RecordingRow: View {
    @EnvironmentObject private var model: AppModel
    let item: RecordingItem
    let onRename: () -> Void
    let onTrash: () -> Void

    private var isPlaying: Bool { model.playingURL == item.url }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                model.togglePlay(item)
            } label: {
                Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(isPlaying ? Color.red : Color.accentColor)
            }
            .buttonStyle(.borderless)
            .help(isPlaying ? "Stop" : "Play")

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).lineLimit(1).truncationMode(.middle)
                Text(details).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.reveal(item)
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")
            Menu {
                actions
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.vertical, 4)
        .contextMenu { actions }
    }

    @ViewBuilder private var actions: some View {
        Button(isPlaying ? "Stop" : "Play") { model.togglePlay(item) }
        Button("Show in Finder") { model.reveal(item) }
        Button("Rename…", action: onRename)
        Divider()
        Button("Move to Trash…", role: .destructive, action: onTrash)
    }

    private var details: String {
        var parts = [item.fileExtension.uppercased()]
        if let duration = item.duration { parts.append(TimeFormat.clock(duration)) }
        parts.append(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
        parts.append(item.date.formatted(date: .abbreviated, time: .shortened))
        return parts.joined(separator: " · ")
    }
}

struct RenameSheet: View {
    let item: RecordingItem
    @Binding var text: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename Recording").font(.headline)
            HStack {
                TextField("Name", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 280)
                    .onSubmit { onSave(text) }
                Text(".\(item.url.pathExtension)").foregroundStyle(.secondary)
            }
            Text("Characters like / and : are removed.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button("Rename") { onSave(text) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(FileNaming.sanitize(text).isEmpty)
            }
        }
        .padding(20)
    }
}
