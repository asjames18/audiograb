import Foundation

enum SilenceTrimmer {
    /// Given per-window levels for a whole file, returns the frame range to keep, or nil
    /// when every window is silent. `paddingFrames` of audio is kept on each side so the
    /// start and end of the sound aren't clipped.
    static func keepRange(levelsDB: [Float],
                          windowFrames: Int,
                          totalFrames: Int,
                          thresholdDB: Float,
                          paddingFrames: Int) -> Range<Int>? {
        guard windowFrames > 0, totalFrames > 0,
              let first = levelsDB.firstIndex(where: { $0 >= thresholdDB }),
              let last = levelsDB.lastIndex(where: { $0 >= thresholdDB }) else { return nil }
        let start = max(0, first * windowFrames - max(0, paddingFrames))
        let end = min(totalFrames, (last + 1) * windowFrames + max(0, paddingFrames))
        guard start < end else { return nil }
        return start..<end
    }
}
