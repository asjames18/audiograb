import SwiftUI

struct OptionsPanel: View {
    @EnvironmentObject private var model: AppModel
    @State private var expanded = true

    var body: some View {
        DisclosureGroup("Options", isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                row("Format") {
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("Format", selection: $model.format) {
                            ForEach(OutputFormat.allCases) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 260)
                        Text(model.format.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                row("Save to") {
                    HStack {
                        Text(model.outputFolderDisplay)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(model.outputFolder.path)
                        Spacer()
                        Button("Choose…") { model.chooseOutputFolder() }
                        Menu {
                            Button("Show in Finder") { model.openOutputFolder() }
                            Button("Use ~/Music/AudioGrab") { model.resetOutputFolder() }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
                Divider()
                Toggle("Trim silence at the start and end of each file", isOn: $model.trimSilence)
                Toggle("Auto-split: start a new file after a stretch of silence", isOn: $model.autoSplit)
                row("Silence below") {
                    HStack {
                        Slider(value: $model.thresholdDB, in: -70 ... -20, step: 1)
                        Text("\(Int(model.thresholdDB)) dB").monospacedDigit().frame(width: 56, alignment: .trailing)
                    }
                }
                .disabled(!(model.autoSplit || model.trimSilence))
                if model.autoSplit {
                    row("New file after") {
                        HStack {
                            Slider(value: $model.splitSilenceSeconds, in: 1 ... 30, step: 0.5)
                            Text(String(format: "%.1f s", model.splitSilenceSeconds))
                                .monospacedDigit()
                                .frame(width: 56, alignment: .trailing)
                        }
                    }
                }
            }
            .padding(.top, 10)
            .toggleStyle(.switch)
            .disabled(model.isBusy)
        }
        .font(.body)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(.background.secondary))
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            content()
        }
    }
}
