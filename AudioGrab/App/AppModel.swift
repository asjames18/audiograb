import AppKit
import AVFoundation
import CoreGraphics
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    // MARK: Recording state
    @Published private(set) var isRecording = false
    @Published private(set) var isStarting = false
    @Published private(set) var isFinishing = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var levelDB: Float = AudioLevel.floorDB
    @Published private(set) var waitingForSound = false
    @Published var nameInput = ""
    @Published var statusMessage: String?
    @Published var alert: AppError?
    @Published private(set) var lastErrorTitle: String?
    @Published private(set) var permissionGranted: Bool
    @Published private(set) var hotKeyRegistered = false

    // MARK: Sources
    @Published private(set) var runningApps: [CaptureApp] = []
    @Published var selectedAppID: String { didSet { defaults.set(selectedAppID, forKey: Keys.selectedApp) } }

    // MARK: Options
    @Published var format: OutputFormat { didSet { defaults.set(format.rawValue, forKey: Keys.format) } }
    @Published var trimSilence: Bool { didSet { defaults.set(trimSilence, forKey: Keys.trim) } }
    @Published var autoSplit: Bool { didSet { defaults.set(autoSplit, forKey: Keys.autoSplit) } }
    @Published var thresholdDB: Double { didSet { defaults.set(thresholdDB, forKey: Keys.threshold) } }
    @Published var splitSilenceSeconds: Double { didSet { defaults.set(splitSilenceSeconds, forKey: Keys.splitSeconds) } }

    // MARK: Library
    @Published private(set) var outputFolder: URL
    @Published private(set) var recordings: [RecordingItem] = []
    @Published private(set) var playingURL: URL?

    private enum Keys {
        static let selectedApp = "selectedAppBundleID"
        static let format = "outputFormat"
        static let trim = "trimSilence"
        static let autoSplit = "autoSplit"
        static let threshold = "silenceThresholdDB"
        static let splitSeconds = "splitSilenceSeconds"
    }

    private let defaults = UserDefaults.standard
    private let folderStore = FolderStore()
    private let capture = SystemAudioCapture()
    private let playback = AudioPlayback()
    private var session: RecordingSession?
    private var startDate: Date?
    private var timer: Timer?
    private var hotKey: GlobalHotKey?
    private var savedThisRecording = 0
    private var activationObserver: NSObjectProtocol?

    init() {
        let d = UserDefaults.standard
        selectedAppID = d.string(forKey: Keys.selectedApp) ?? ""
        format = OutputFormat(rawValue: d.string(forKey: Keys.format) ?? "") ?? .m4a
        trimSilence = d.object(forKey: Keys.trim) as? Bool ?? false
        autoSplit = d.object(forKey: Keys.autoSplit) as? Bool ?? false
        thresholdDB = d.object(forKey: Keys.threshold) as? Double ?? -50
        splitSilenceSeconds = d.object(forKey: Keys.splitSeconds) as? Double ?? 3
        permissionGranted = CGPreflightScreenCaptureAccess()
        outputFolder = FolderStore.defaultFolder
        outputFolder = folderStore.resolve()

        hotKey = GlobalHotKey(keyCode: GlobalHotKey.defaultKeyCode, modifiers: GlobalHotKey.defaultModifiers) { [weak self] in
            Task { @MainActor in self?.toggleRecording() }
        }
        hotKeyRegistered = hotKey != nil
        playback.onFinish = { [weak self] in
            Task { @MainActor in self?.playingURL = nil }
        }
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                                    object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.applicationBecameActive() }
        }
        try? FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        refreshRecordings()
        if permissionGranted {
            Task { await refreshApps() }
        }
    }

    // MARK: - Derived

    var selectedAppName: String? {
        guard !selectedAppID.isEmpty else { return nil }
        return runningApps.first { $0.bundleID == selectedAppID }?.name ?? selectedAppID
    }

    var outputFolderDisplay: String {
        (outputFolder.path as NSString).abbreviatingWithTildeInPath
    }

    /// What the next file will be called, shown under the name field.
    var fileNamePreview: String {
        let base = FileNaming.baseName(from: nameInput)
        let ext = format.fileExtension
        if autoSplit {
            return "\(FileNaming.segmentName(base: base, index: 1)).\(ext), \(FileNaming.segmentName(base: base, index: 2)).\(ext), …"
        }
        return "\(base).\(ext)"
    }

    var isBusy: Bool { isRecording || isStarting || isFinishing }

    // MARK: - Recording

    func toggleRecording() {
        if isRecording {
            Task { await stopRecording() }
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard !isBusy else { return }
        statusMessage = nil
        let folder = outputFolder
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            present(.folderUnavailable(outputFolderDisplay))
            return
        }
        guard FileManager.default.isWritableFile(atPath: folder.path) else {
            present(.folderUnavailable(outputFolderDisplay))
            return
        }
        if let free = DiskSpace.availableBytes(at: folder), free < DiskSpace.minimumFreeToStart {
            present(.diskFull)
            return
        }

        let configuration = RecordingSession.Configuration(
            baseName: FileNaming.baseName(from: nameInput),
            outputFolder: folder,
            tempFolder: FileManager.default.temporaryDirectory.appendingPathComponent("AudioGrab", isDirectory: true),
            format: format,
            autoSplit: autoSplit,
            thresholdDB: Float(thresholdDB),
            splitAfterSilence: splitSilenceSeconds,
            trimSilence: trimSilence)
        let newSession: RecordingSession
        do {
            newSession = try RecordingSession(configuration: configuration, queue: capture.sampleQueue)
        } catch {
            present(.writeFailed(error.localizedDescription))
            return
        }
        newSession.onLevel = { [weak self] level, waiting in
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                self.levelDB = level
                self.waitingForSound = waiting
            }
        }
        newSession.onFileSaved = { [weak self] url in
            Task { @MainActor in self?.fileSaved(url) }
        }
        newSession.onSilentSkipped = { [weak self] name in
            Task { @MainActor in self?.statusMessage = "“\(name)” was silent, so it wasn't saved." }
        }
        newSession.onError = { [weak self] error in
            Task { @MainActor in self?.sessionFailed(error) }
        }
        capture.onBuffer = { [weak newSession] buffer in newSession?.handle(buffer) }
        capture.onStop = { [weak self] error in
            Task { @MainActor in self?.streamDidStop(error) }
        }

        session = newSession
        savedThisRecording = 0
        isStarting = true
        let appID = selectedAppID.isEmpty ? nil : selectedAppID
        let appName = selectedAppName
        Task {
            do {
                try await capture.start(appBundleID: appID, appName: appName)
                permissionGranted = true
                isStarting = false
                isRecording = true
                waitingForSound = autoSplit
                startDate = Date()
                elapsed = 0
                startTimer()
            } catch {
                isStarting = false
                session = nil
                newSession.discard()
                present(AppError.fromCapture(error, whileRecording: false))
            }
        }
    }

    func stopRecording() async {
        guard isRecording, let session else { return }
        isRecording = false
        isFinishing = true
        stopTimer()
        await capture.stop()
        await session.finish()
        self.session = nil
        isFinishing = false
        levelDB = AudioLevel.floorDB
        waitingForSound = false
        if savedThisRecording == 0 && statusMessage == nil && alert == nil {
            statusMessage = "Nothing was saved: no audio was captured."
        }
        nameInput = ""
        refreshRecordings()
    }

    private func fileSaved(_ url: URL) {
        savedThisRecording += 1
        statusMessage = savedThisRecording == 1 ? "Saved “\(url.lastPathComponent)”" : "Saved \(savedThisRecording) files, latest “\(url.lastPathComponent)”"
        refreshRecordings()
    }

    private func sessionFailed(_ error: AppError) {
        present(error)
        if isRecording { Task { await stopRecording() } }
    }

    private func streamDidStop(_ error: Error) {
        guard isRecording else { return }
        let appError = AppError.fromCapture(error, whileRecording: true)
        Task {
            await stopRecording()
            present(appError)
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.startDate else { return }
                self.elapsed = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func present(_ error: AppError) {
        alert = error
        lastErrorTitle = error.title
        if error.isPermissionProblem { permissionGranted = false }
    }

    // MARK: - Permission

    private func applicationBecameActive() {
        if !permissionGranted && CGPreflightScreenCaptureAccess() {
            permissionGranted = true
            Task { await refreshApps() }
        }
        if !isBusy { refreshRecordings() }
    }

    func requestPermission() {
        if !CGRequestScreenCaptureAccess() {
            openPermissionSettings()
        } else {
            permissionGranted = true
            Task { await refreshApps() }
        }
    }

    func openPermissionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// macOS only applies a newly granted permission after the app restarts.
    func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    // MARK: - Sources

    func refreshApps() async {
        do {
            runningApps = try await SystemAudioCapture.runningApps()
            permissionGranted = true
        } catch {
            if AppError.isPermissionError(error) { permissionGranted = false }
        }
    }

    // MARK: - Output folder

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose where AudioGrab saves recordings."
        panel.directoryURL = outputFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folderStore.set(url)
        outputFolder = url
        refreshRecordings()
    }

    func resetOutputFolder() {
        folderStore.reset()
        outputFolder = FolderStore.defaultFolder
        try? FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        refreshRecordings()
    }

    func openOutputFolder() {
        try? FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(outputFolder)
    }

    // MARK: - Recordings list

    func refreshRecordings() {
        let folder = outputFolder
        Task {
            let items = await Task.detached(priority: .utility) { RecordingLibrary.scan(folder: folder) }.value
            if folder == self.outputFolder { self.recordings = items }
        }
    }

    func togglePlay(_ item: RecordingItem) {
        if playingURL == item.url {
            stopPlayback()
            return
        }
        do {
            try playback.play(item.url)
            playingURL = item.url
        } catch {
            playingURL = nil
            present(.fileOperation("“\(item.url.lastPathComponent)” couldn't be played: \(error.localizedDescription)"))
        }
    }

    func stopPlayback() {
        playback.stop()
        playingURL = nil
    }

    func reveal(_ item: RecordingItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func rename(_ item: RecordingItem, to newName: String) {
        let cleaned = FileNaming.sanitize(newName)
        guard !cleaned.isEmpty else {
            present(.fileOperation("Please enter a name that isn't empty."))
            return
        }
        let destination = item.url.deletingLastPathComponent()
            .appendingPathComponent(cleaned)
            .appendingPathExtension(item.url.pathExtension)
        guard destination.path != item.url.path else { return }
        let caseOnlyChange = destination.path.lowercased() == item.url.path.lowercased()
        if !caseOnlyChange && FileManager.default.fileExists(atPath: destination.path) {
            present(.fileOperation("A recording named “\(destination.lastPathComponent)” already exists."))
            return
        }
        if playingURL == item.url { stopPlayback() }
        do {
            try FileManager.default.moveItem(at: item.url, to: destination)
        } catch {
            present(.fileOperation("“\(item.url.lastPathComponent)” couldn't be renamed: \(error.localizedDescription)"))
        }
        refreshRecordings()
    }

    func moveToTrash(_ item: RecordingItem) {
        if playingURL == item.url { stopPlayback() }
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            statusMessage = "Moved “\(item.url.lastPathComponent)” to the Trash."
        } catch {
            present(.fileOperation("“\(item.url.lastPathComponent)” couldn't be moved to the Trash: \(error.localizedDescription)"))
        }
        refreshRecordings()
    }
}
