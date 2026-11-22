import AVFoundation

extension AudioLevel {
    /// RMS of a PCM buffer (float or 16-bit, interleaved or not).
    static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        let format = buffer.format
        let channelCount = Int(format.channelCount)
        let pointerCount = format.isInterleaved ? 1 : channelCount
        let samplesPerPointer = format.isInterleaved ? frames * channelCount : frames
        if let data = buffer.floatChannelData {
            let channels = (0..<pointerCount).map { UnsafeBufferPointer(start: data[$0], count: samplesPerPointer) }
            return rms(channels: channels)
        }
        if let data = buffer.int16ChannelData {
            var sum: Double = 0
            for c in 0..<pointerCount {
                for i in 0..<samplesPerPointer {
                    let v = Double(data[c][i]) / 32768.0
                    sum += v * v
                }
            }
            return Float((sum / Double(pointerCount * samplesPerPointer)).squareRoot())
        }
        return 0
    }
}
