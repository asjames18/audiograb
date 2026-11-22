import Foundation

/// Every problem the user can see. Each has a short title and a plain explanation.
enum AppError: Error {
    case permissionDenied
    case diskFull
    case streamInterrupted(String)
    case stoppedBySystem
    case captureFailed(String)
    case appNotRunning(String)
    case noDisplay
    case folderUnavailable(String)
    case writeFailed(String)
    case saveFailed(name: String, reason: String)
    case fileOperation(String)

    var title: String {
        switch self {
        case .permissionDenied: return "Screen & System Audio Recording is off"
        case .diskFull: return "Disk is full"
        case .streamInterrupted: return "Recording was interrupted"
        case .stoppedBySystem: return "Recording stopped"
        case .captureFailed: return "Couldn't start recording"
        case .appNotRunning: return "App isn't running"
        case .noDisplay: return "No display found"
        case .folderUnavailable: return "Can't save to the output folder"
        case .writeFailed: return "Couldn't write the recording"
        case .saveFailed: return "Couldn't save a recording"
        case .fileOperation: return "Couldn't do that"
        }
    }

    var message: String {
        switch self {
        case .permissionDenied:
            return "AudioGrab needs the Screen & System Audio Recording permission to hear your Mac's audio. Turn on AudioGrab in System Settings › Privacy & Security › Screen & System Audio Recording, then quit and reopen AudioGrab."
        case .diskFull:
            return "There isn't enough free disk space to keep recording. Whatever could be saved has been saved. Free up space or choose another output folder."
        case .streamInterrupted(let reason):
            return "macOS stopped the audio stream (\(reason)). Audio recorded before the interruption has been saved."
        case .stoppedBySystem:
            return "Recording was stopped from the macOS screen-recording indicator. Audio recorded so far has been saved."
        case .captureFailed(let reason):
            return "macOS wouldn't start the audio stream: \(reason)"
        case .appNotRunning(let name):
            return "“\(name)” isn't running. Open it first, or choose “All system audio”."
        case .noDisplay:
            return "ScreenCaptureKit needs at least one display to capture audio, and none was found."
        case .folderUnavailable(let path):
            return "AudioGrab can't write to \(path). Choose another output folder in Options."
        case .writeFailed(let reason):
            return "Writing audio to disk failed: \(reason). Recording was stopped."
        case .saveFailed(let name, let reason):
            return "“\(name)” couldn't be saved: \(reason)"
        case .fileOperation(let reason):
            return reason
        }
    }

    var isPermissionProblem: Bool {
        if case .permissionDenied = self { return true }
        return false
    }
}
