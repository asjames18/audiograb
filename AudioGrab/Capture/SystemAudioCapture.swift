import AppKit
import AVFoundation
import CoreGraphics
import ScreenCaptureKit

/// Captures system (or one app's) audio with ScreenCaptureKit. No virtual audio driver
/// is needed. ScreenCaptureKit always needs a display in the filter, so video is
/// requested at 2x2 pixels, once per second, and ignored.
final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    let sampleQueue = DispatchQueue(label: "AudioGrab.capture.audio", qos: .userInitiated)
    private let videoQueue = DispatchQueue(label: "AudioGrab.capture.video", qos: .background)
    private var stream: SCStream?

    /// Called on `sampleQueue` for every audio buffer.
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    /// Called when macOS stops the stream on its own.
    var onStop: ((Error) -> Void)?

    func start(appBundleID: String?, appName: String?) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else { throw AppError.noDisplay }

        let filter: SCContentFilter
        if let appBundleID {
            guard let app = content.applications.first(where: { $0.bundleIdentifier == appBundleID }) else {
                throw AppError.appNotRunning(appName ?? appBundleID)
            }
            filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
        } else {
            filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        }

        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.showsCursor = false

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        guard let stream else { return }
        self.stream = nil
        try? await stream.stopCapture()
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid, let buffer = Self.pcmBuffer(from: sampleBuffer) else { return }
        onBuffer?(buffer)
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStop?(error)
    }

    static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              let format = AVAudioFormat(streamDescription: asbd) else { return nil }
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(frames),
                                                                  into: buffer.mutableAudioBufferList)
        return status == noErr ? buffer : nil
    }

    /// Regular (Dock) apps that ScreenCaptureKit can record, sorted by name.
    static func runningApps() async throws -> [CaptureApp] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let regular = await MainActor.run {
            Set(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap(\.bundleIdentifier))
        }
        let own = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        var apps: [CaptureApp] = []
        for app in content.applications {
            let id = app.bundleIdentifier
            guard !id.isEmpty, id != own, regular.contains(id), seen.insert(id).inserted else { continue }
            apps.append(CaptureApp(bundleID: id, name: app.applicationName.isEmpty ? id : app.applicationName))
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

extension AppError {
    /// Maps ScreenCaptureKit errors to messages people can act on.
    static func fromCapture(_ error: Error, whileRecording: Bool) -> AppError {
        if let appError = error as? AppError { return appError }
        let ns = error as NSError
        if ns.domain == SCStreamErrorDomain {
            if ns.code == SCStreamError.Code.userDeclined.rawValue { return .permissionDenied }
            if ns.code == SCStreamError.Code.userStopped.rawValue { return .stoppedBySystem }
        }
        if !CGPreflightScreenCaptureAccess() { return .permissionDenied }
        if DiskSpace.isOutOfSpace(error) { return .diskFull }
        return whileRecording ? .streamInterrupted(ns.localizedDescription) : .captureFailed(ns.localizedDescription)
    }

    static func isPermissionError(_ error: Error) -> Bool {
        fromCapture(error, whileRecording: false).isPermissionProblem
    }
}
