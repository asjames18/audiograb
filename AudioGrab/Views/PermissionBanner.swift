import SwiftUI

struct PermissionBanner: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 26))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("Allow Screen & System Audio Recording")
                    .font(.headline)
                Text("macOS only lets apps hear system audio with this permission. AudioGrab records audio only; the tiny video frames macOS requires are thrown away, and nothing leaves your Mac. After turning it on, reopen AudioGrab.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Open System Settings") { model.openPermissionSettings() }
                        .buttonStyle(.borderedProminent)
                    Button("Ask Again") { model.requestPermission() }
                    Button("Reopen AudioGrab") { model.relaunch() }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.orange.opacity(0.35)))
    }
}
