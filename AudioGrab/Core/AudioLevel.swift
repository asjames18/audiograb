import Foundation

/// Level math used by the meter, silence detection and trimming.
enum AudioLevel {
    static let floorDB: Float = -160

    /// Root-mean-square over all samples of all channels.
    static func rms(channels: [UnsafeBufferPointer<Float>]) -> Float {
        var sum: Double = 0
        var count = 0
        for channel in channels {
            for sample in channel { sum += Double(sample) * Double(sample) }
            count += channel.count
        }
        guard count > 0 else { return 0 }
        return Float((sum / Double(count)).squareRoot())
    }

    static func rms(_ samples: [Float]) -> Float {
        samples.withUnsafeBufferPointer { rms(channels: [$0]) }
    }

    static func decibels(fromLinear value: Float) -> Float {
        guard value > 0 else { return floorDB }
        return max(floorDB, 20 * log10(value))
    }

    /// Maps -60 dB ... 0 dB onto 0 ... 1 for the meter.
    static func meterFraction(_ db: Float, range: Float = 60) -> Float {
        min(1, max(0, (db + range) / range))
    }
}

struct SilenceDetector {
    /// Anything quieter than this (dBFS) counts as silence.
    var thresholdDB: Float

    func isSilent(levelDB: Float) -> Bool { levelDB < thresholdDB }

    func isSilent(rms: Float) -> Bool { isSilent(levelDB: AudioLevel.decibels(fromLinear: rms)) }
}
