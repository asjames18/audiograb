import Foundation

/// A running app that can be recorded on its own.
struct CaptureApp: Identifiable, Hashable {
    let bundleID: String
    let name: String
    var id: String { bundleID }
}
