import SwiftUI

struct RecorderPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("File name").font(.subheadline.weight(.medium))
                TextField("File name", text: $model.nameInput,
                          prompt: Text(FileNaming.defaultBaseName()))
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.isBusy)
                    .onSubmit { model.startRecording() }
                Text("Saves as \(model.fileNamePreview)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack {
                Text("Source").font(.subheadline.weight(.medium))
                Picker("Source", selection: $model.selectedAppID) {
                    Text("All system audio").tag("")
                    if !model.selectedAppID.isEmpty && !model.runningApps.contains(where: { $0.bundleID == model.selectedAppID }) {
                        Text("\(model.selectedAppID) (not running)").tag(model.selectedAppID)
                    }
                    if !model.runningApps.isEmpty { Divider() }
                    ForEach(model.runningApps) { app in
                        Text(app.name).tag(app.bundleID)
                    }
                }
                .labelsHidden()
                .disabled(model.isBusy)
                Button {
                    Task { await model.refreshApps() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh the list of running apps")
                .disabled(model.isBusy)
            }

            HStack(spacing: 24) {
                RecordButton()
                VStack(alignment: .leading, spacing: 10) {
                    Text(TimeFormat.clock(model.elapsed))
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(model.isRecording ? .primary : .secondary)
                    LevelMeter(levelDB: model.levelDB,
                               thresholdDB: (model.autoSplit || model.trimSilence) ? Float(model.thresholdDB) : nil)
                    Text(stateText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(.background.secondary))
    }

    private var stateText: String {
        if model.isStarting { return "Starting…" }
        if model.isFinishing { return "Saving…" }
        if model.isRecording {
            let source = model.selectedAppName.map { "Recording \($0)" } ?? "Recording all system audio"
            return model.waitingForSound ? "\(source), waiting for sound…" : source
        }
        if let status = model.statusMessage { return status }
        return model.hotKeyRegistered ? "Press Record or \(GlobalHotKey.defaultDisplay) from anywhere." : "Press Record to start."
    }
}

struct RecordButton: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Button {
            model.toggleRecording()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 4)
                    .frame(width: 104, height: 104)
                if model.isRecording {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red)
                        .frame(width: 38, height: 38)
                } else {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 80, height: 80)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(model.isStarting || model.isFinishing)
        .opacity(model.isStarting || model.isFinishing ? 0.5 : 1)
        .help(model.isRecording ? "Stop (\(GlobalHotKey.defaultDisplay))" : "Record (\(GlobalHotKey.defaultDisplay))")
        .accessibilityLabel(model.isRecording ? "Stop recording" : "Start recording")
    }
}
