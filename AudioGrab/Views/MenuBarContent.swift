import AppKit
import SwiftUI

struct MenuBarContent: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(model.isRecording ? "Stop Recording" : "Start Recording") {
            model.toggleRecording()
        }
        .keyboardShortcut("r", modifiers: [.command, .option])
        .disabled(model.isStarting || model.isFinishing)

        if model.isRecording {
            Text("Recording · \(TimeFormat.clock(model.elapsed))")
        } else if model.isFinishing {
            Text("Saving…")
        } else if let error = model.lastErrorTitle, model.alert != nil {
            Text("⚠︎ \(error)")
        }
        if !model.permissionGranted {
            Button("Allow Screen & System Audio Recording…") { model.openPermissionSettings() }
        }

        Divider()
        Button("Open AudioGrab") {
            openWindow(id: "main")
            NSApp.activate()
        }
        Button("Show Recordings Folder") { model.openOutputFolder() }
        Divider()
        Button("Quit AudioGrab") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
