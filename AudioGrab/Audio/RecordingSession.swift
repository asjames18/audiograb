import AVFoundation

/// One press of Record. Receives captured buffers (on `queue`), feeds the level meter,
/// applies auto-split, writes temporary segment files and exports each finished
/// segment to its own WAV/M4A file.
final class RecordingSession {
    struct Configuration {
        var baseName: String
        var outputFolder: URL
        var tempFolder: URL
        var format: OutputFormat
        var autoSplit: Bool
        var thresholdDB: Float
        var splitAfterSilence: TimeInterval
        var trimSilence: Bool
        var minimumFreeBytes: Int64 = DiskSpace.minimumFreeWhileRecording
    }

    let configuration: Configuration
    let queue: DispatchQueue

    /// Peak level in dBFS (about 20 times a second) and whether auto-split is waiting for sound.
    var onLevel: ((Float, Bool) -> Void)?
    var onFileSaved: ((URL) -> Void)?
    var onSilentSkipped: ((String) -> Void)?
    var onError: ((AppError) -> Void)?

    private var splitter: AutoSplitter?
    private var writer: SegmentWriter?
    private(set) var segmentIndex = 0
    private var stopped = false
    private var levelPeak: Float = AudioLevel.floorDB
    private var levelFrames = 0
    private var framesSinceDiskCheck = 0
    private let exportQueue = DispatchQueue(label: "AudioGrab.export", qos: .utility)
    private let exportGroup = DispatchGroup()

    init(configuration: Configuration, queue: DispatchQueue) throws {
        self.configuration = configuration
        self.queue = queue
        try FileManager.default.createDirectory(at: configuration.tempFolder, withIntermediateDirectories: true)
        if configuration.autoSplit {
            splitter = AutoSplitter(silenceDuration: configuration.splitAfterSilence)
        }
    }

    var isWaitingForSound: Bool {
        guard let splitter else { return false }
        return !splitter.inSegment
    }

    /// The file name (without extension) for a segment number.
    func fileName(forSegment index: Int) -> String {
        configuration.autoSplit ? FileNaming.segmentName(base: configuration.baseName, index: index) : configuration.baseName
    }

    func handle(_ buffer: AVAudioPCMBuffer) {
        guard !stopped, buffer.frameLength > 0 else { return }
        let sampleRate = buffer.format.sampleRate
        let frames = Int(buffer.frameLength)
        let level = AudioLevel.decibels(fromLinear: AudioLevel.rms(of: buffer))
        let silent = SilenceDetector(thresholdDB: configuration.thresholdDB).isSilent(levelDB: level)

        if var current = splitter {
            let action = current.process(bufferDuration: Double(frames) / sampleRate, isSilent: silent)
            splitter = current
            switch action {
            case .drop: break
            case .closeSegment: finishSegment()
            case .startSegmentAndWrite:
                openSegment()
                write(buffer)
            case .write: write(buffer)
            }
        } else {
            if writer == nil { openSegment() }
            write(buffer)
        }

        reportLevel(level, frames: frames, sampleRate: sampleRate)
        checkDiskSpace(frames: frames, sampleRate: sampleRate)
    }

    /// Stops accepting audio, saves the open segment and waits for all exports.
    func finish() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.stopped = true
                self.finishSegment()
                self.exportGroup.notify(queue: .global()) { continuation.resume() }
            }
        }
    }

    /// Throws away anything captured (used when the stream never started).
    func discard() {
        queue.async {
            self.stopped = true
            self.writer?.discard()
            self.writer = nil
        }
    }

    // MARK: - Private

    private func openSegment() {
        segmentIndex += 1
        writer = SegmentWriter(tempFolder: configuration.tempFolder)
    }

    private func write(_ buffer: AVAudioPCMBuffer) {
        guard let writer else { return }
        do {
            try writer.write(buffer)
        } catch {
            fail(DiskSpace.isOutOfSpace(error) ? .diskFull : .writeFailed(error.localizedDescription))
        }
    }

    private func fail(_ error: AppError) {
        guard !stopped else { return }
        stopped = true
        finishSegment()
        onError?(error)
    }

    private func finishSegment() {
        guard let finished = writer else { return }
        writer = nil
        finished.close()
        guard finished.framesWritten > 0 else {
            finished.discard()
            return
        }
        let name = fileName(forSegment: segmentIndex)
        let config = configuration
        exportGroup.enter()
        exportQueue.async {
            defer {
                finished.discard()
                self.exportGroup.leave()
            }
            let destination = FileNaming.uniqueFileURL(in: config.outputFolder, name: name, fileExtension: config.format.fileExtension)
            do {
                let options = RecordingExporter.Options(format: config.format, trimSilence: config.trimSilence, thresholdDB: config.thresholdDB)
                if try RecordingExporter.export(source: finished.tempURL, to: destination, options: options) {
                    self.onFileSaved?(destination)
                } else {
                    self.onSilentSkipped?(name)
                }
            } catch {
                try? FileManager.default.removeItem(at: destination)
                self.onError?(DiskSpace.isOutOfSpace(error) ? .diskFull : .saveFailed(name: name, reason: error.localizedDescription))
            }
        }
    }

    private func reportLevel(_ level: Float, frames: Int, sampleRate: Double) {
        levelPeak = max(levelPeak, level)
        levelFrames += frames
        if Double(levelFrames) >= sampleRate * 0.05 {
            onLevel?(levelPeak, isWaitingForSound)
            levelPeak = AudioLevel.floorDB
            levelFrames = 0
        }
    }

    private func checkDiskSpace(frames: Int, sampleRate: Double) {
        framesSinceDiskCheck += frames
        guard Double(framesSinceDiskCheck) >= sampleRate * 5 else { return }
        framesSinceDiskCheck = 0
        for folder in [configuration.outputFolder, configuration.tempFolder] {
            if let free = DiskSpace.availableBytes(at: folder), free < configuration.minimumFreeBytes {
                fail(.diskFull)
                return
            }
        }
    }
}
