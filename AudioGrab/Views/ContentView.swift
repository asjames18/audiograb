import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                if !model.permissionGranted {
                    PermissionBanner()
                }
                RecorderPanel()
                OptionsPanel()
            }
            .padding(20)
            Divider()
            RecordingsPanel()
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .alert(model.alert?.title ?? "",
               isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } }),
               presenting: model.alert) { error in
            if error.isPermissionProblem {
                Button("Open System Settings") { model.openPermissionSettings() }
            }
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
    }
}
