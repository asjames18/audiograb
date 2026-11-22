import AVFoundation

enum ExportError: LocalizedError {
    case bufferAllocation
    case converterUnavailable

    var errorDescription: String? {
        switch self {
        case .bufferAllocation: return "Not enough memory for an audio buffer."
        case .converterUnavailable: return "The audio format couldn't be converted."
        }
    }
}

/// Turns a temporary capture file into the final WAV or M4A, optionally trimming
/// leading and trailing silence.
enum RecordingExporter {
    struct Options {
        var format: OutputFormat
        var trimSilence: Bool
        var thresholdDB: Float
        var paddingSeconds: Double = 0.15
    }

    static let sampleRate: Double = 48_000
    static let channelCount: AVAudioChannelCount = 2

    static func fileSettings(for format: OutputFormat) -> [String: Any] {
        switch format {
        case .wav:
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: Int(channelCount),
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
        case .m4a:
            return [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: Int(channelCount),
                AVEncoderBitRateKey: 256_000,
            ]
        }
    }

    /// Returns false (and writes nothing) when there's nothing to keep, e.g. the
    /// segment was completely silent and trimming is on.
    @discardableResult
    static func export(source: URL, to destination: URL, options: Options) throws -> Bool {
        let input = try AVAudioFile(forReading: source)
        let total = Int(input.length)
        guard total > 0 else { return false }
        var range = 0..<total
        if options.trimSilence {
            guard let kept = try keepRange(of: input, thresholdDB: options.thresholdDB, paddingSeconds: options.paddingSeconds) else {
                return false
            }
            range = kept
        }
        input.framePosition = AVAudioFramePosition(range.lowerBound)
        try write(from: input, frameCount: range.count, to: destination, settings: fileSettings(for: options.format))
        return true
    }

    static func keepRange(of input: AVAudioFile, thresholdDB: Float, paddingSeconds: Double) throws -> Range<Int>? {
        let format = input.processingFormat
        let window = AVAudioFrameCount(max(1, Int(format.sampleRate * 0.05)))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: window) else { throw ExportError.bufferAllocation }
        var levels: [Float] = []
        input.framePosition = 0
        while input.framePosition < input.length {
            try input.read(into: buffer, frameCount: window)
            if buffer.frameLength == 0 { break }
            levels.append(AudioLevel.decibels(fromLinear: AudioLevel.rms(of: buffer)))
        }
        return SilenceTrimmer.keepRange(levelsDB: levels,
                                        windowFrames: Int(window),
                                        totalFrames: Int(input.length),
                                        thresholdDB: thresholdDB,
                                        paddingFrames: Int(format.sampleRate * paddingSeconds))
    }

    private static func write(from input: AVAudioFile, frameCount: Int, to destination: URL, settings: [String: Any]) throws {
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                         channels: channelCount, interleaved: false) else {
            throw ExportError.converterUnavailable
        }
        let output = try AVAudioFile(forWriting: destination, settings: settings,
                                     commonFormat: .pcmFormatFloat32, interleaved: false)
        let inFormat = input.processingFormat
        if inFormat.sampleRate == sampleRate && inFormat.channelCount == channelCount {
            try copy(from: input, frameCount: frameCount, to: output)
        } else {
            try convert(from: input, frameCount: frameCount, to: output, target: target)
        }
    }

    private static func copy(from input: AVAudioFile, frameCount: Int, to output: AVAudioFile) throws {
        let capacity: AVAudioFrameCount = 32_768
        guard let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: capacity) else {
            throw ExportError.bufferAllocation
        }
        var remaining = frameCount
        while remaining > 0 {
            try input.read(into: buffer, frameCount: AVAudioFrameCount(min(Int(capacity), remaining)))
            if buffer.frameLength == 0 { break }
            try output.write(from: buffer)
            remaining -= Int(buffer.frameLength)
        }
    }

    private static func convert(from input: AVAudioFile, frameCount: Int, to output: AVAudioFile, target: AVAudioFormat) throws {
        let inFormat = input.processingFormat
        guard let converter = AVAudioConverter(from: inFormat, to: target) else { throw ExportError.converterUnavailable }
        let inCapacity: AVAudioFrameCount = 8_192
        guard let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: inCapacity) else {
            throw ExportError.bufferAllocation
        }
        let outCapacity = AVAudioFrameCount(Double(inCapacity) * target.sampleRate / inFormat.sampleRate) + 1_024
        var remaining = frameCount
        var readError: Error?
        while true {
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outCapacity) else {
                throw ExportError.bufferAllocation
            }
            var conversionError: NSError?
            let status = converter.convert(to: outBuffer, error: &conversionError) { _, inputStatus in
                if remaining <= 0 {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                do {
                    try input.read(into: inBuffer, frameCount: AVAudioFrameCount(min(Int(inCapacity), remaining)))
                } catch {
                    readError = error
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                if inBuffer.frameLength == 0 {
                    remaining = 0
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                remaining -= Int(inBuffer.frameLength)
                inputStatus.pointee = .haveData
                return inBuffer
            }
            if let conversionError { throw conversionError }
            if let readError { throw readError }
            if outBuffer.frameLength > 0 { try output.write(from: outBuffer) }
            if status == .endOfStream || status == .error { break }
        }
    }
}
