import AVFoundation

/// Writes captured buffers, unchanged, to a temporary CAF file. The final WAV/M4A is
/// made from it when the segment ends (that's where trimming happens).
final class SegmentWriter {
    let tempURL: URL
    private var file: AVAudioFile?
    private(set) var framesWritten: AVAudioFramePosition = 0

    init(tempFolder: URL) {
        tempURL = tempFolder.appendingPathComponent("segment-\(UUID().uuidString)").appendingPathExtension("caf")
    }

    func write(_ buffer: AVAudioPCMBuffer) throws {
        if file == nil {
            let format = buffer.format
            file = try AVAudioFile(forWriting: tempURL,
                                   settings: format.settings,
                                   commonFormat: format.commonFormat,
                                   interleaved: format.isInterleaved)
        }
        try file?.write(from: buffer)
        framesWritten += AVAudioFramePosition(buffer.frameLength)
    }

    /// Flushes and closes the file (AVAudioFile closes when released).
    func close() {
        file = nil
    }

    func discard() {
        close()
        try? FileManager.default.removeItem(at: tempURL)
    }
}
