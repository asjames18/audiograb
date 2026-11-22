import AppKit
import SwiftUI

@main
struct AudioGrabApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var model = AppModel.shared

    var body: some Scene {
        Window("AudioGrab", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 560, minHeight: 680)
        }
        .defaultSize(width: 640, height: 820)

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(model)
        } label: {
            Image(systemName: model.isRecording ? "record.circle.fill" : "waveform")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Keep running in the menu bar when the window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Finish and save a recording in progress before quitting.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let model = AppModel.shared
        guard model.isRecording || model.isFinishing else { return .terminateNow }
        Task { @MainActor in
            await model.stopRecording()
            while model.isFinishing { try? await Task.sleep(nanoseconds: 100_000_000) }
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
