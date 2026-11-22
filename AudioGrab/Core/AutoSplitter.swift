import Foundation

/// Decides, buffer by buffer, when auto-split mode should close the current file and
/// when a new one should begin. A new file only starts when sound returns, so the
/// silence between takes isn't saved.
struct AutoSplitter {
    enum Action: Equatable {
        /// Silence while no file is open: throw the buffer away.
        case drop
        /// Sound arrived while no file is open: open the next file and write this buffer.
        case startSegmentAndWrite
        /// Write the buffer to the open file.
        case write
        /// Enough silence: close the open file (this buffer is not written).
        case closeSegment
    }

    let silenceDuration: TimeInterval
    private(set) var inSegment = false
    private(set) var silenceRun: TimeInterval = 0
    private(set) var segmentsStarted = 0

    init(silenceDuration: TimeInterval) {
        self.silenceDuration = max(0.1, silenceDuration)
    }

    mutating func process(bufferDuration: TimeInterval, isSilent: Bool) -> Action {
        guard inSegment else {
            if isSilent { return .drop }
            inSegment = true
            silenceRun = 0
            segmentsStarted += 1
            return .startSegmentAndWrite
        }
        guard isSilent else {
            silenceRun = 0
            return .write
        }
        silenceRun += bufferDuration
        if silenceRun + 1e-9 >= silenceDuration {
            inSegment = false
            silenceRun = 0
            return .closeSegment
        }
        return .write
    }
}
