import XCTest

final class SilenceDetectionTests: XCTestCase {
    func testRMSOfSilenceIsZeroAndFloorDecibels() {
        let rms = AudioLevel.rms([Float](repeating: 0, count: 480))
        XCTAssertEqual(rms, 0)
        XCTAssertEqual(AudioLevel.decibels(fromLinear: rms), AudioLevel.floorDB)
    }

    func testRMSOfConstantSignal() {
        let rms = AudioLevel.rms([Float](repeating: 0.5, count: 480))
        XCTAssertEqual(rms, 0.5, accuracy: 1e-6)
        XCTAssertEqual(AudioLevel.decibels(fromLinear: rms), -6.0206, accuracy: 0.001)
    }

    func testRMSOfFullScaleSineIsMinus3dB() {
        let samples = (0..<48_000).map { Float(sin(2 * Double.pi * 440 * Double($0) / 48_000)) }
        let rms = AudioLevel.rms(samples)
        XCTAssertEqual(rms, Float(1 / 2.0.squareRoot()), accuracy: 0.001)
        XCTAssertEqual(AudioLevel.decibels(fromLinear: rms), -3.01, accuracy: 0.02)
    }

    func testRMSAcrossChannels() {
        let left = [Float](repeating: 1, count: 100)
        let right = [Float](repeating: 0, count: 100)
        let rms = left.withUnsafeBufferPointer { l in
            right.withUnsafeBufferPointer { r in AudioLevel.rms(channels: [l, r]) }
        }
        XCTAssertEqual(rms, Float(0.5.squareRoot()), accuracy: 1e-6)
    }

    func testDetectorUsesThreshold() {
        let detector = SilenceDetector(thresholdDB: -50)
        XCTAssertTrue(detector.isSilent(levelDB: -60))
        XCTAssertTrue(detector.isSilent(levelDB: -50.01))
        XCTAssertFalse(detector.isSilent(levelDB: -50))
        XCTAssertFalse(detector.isSilent(levelDB: -12))
        XCTAssertTrue(detector.isSilent(rms: 0))
        XCTAssertTrue(detector.isSilent(rms: 0.001))   // -60 dB
        XCTAssertFalse(detector.isSilent(rms: 0.1))    // -20 dB
    }

    func testMeterFraction() {
        XCTAssertEqual(AudioLevel.meterFraction(-80), 0)
        XCTAssertEqual(AudioLevel.meterFraction(-60), 0)
        XCTAssertEqual(AudioLevel.meterFraction(-30), 0.5, accuracy: 1e-6)
        XCTAssertEqual(AudioLevel.meterFraction(0), 1)
        XCTAssertEqual(AudioLevel.meterFraction(6), 1)
    }

    // MARK: Trimming

    func testTrimAllSilentReturnsNil() {
        let levels = [Float](repeating: -90, count: 20)
        XCTAssertNil(SilenceTrimmer.keepRange(levelsDB: levels, windowFrames: 100, totalFrames: 2000, thresholdDB: -50, paddingFrames: 0))
    }

    func testTrimRemovesLeadingAndTrailingSilence() {
        // windows 0-4 silent, 5-9 loud, 10-19 silent
        let levels = (0..<20).map { (5..<10).contains($0) ? Float(-10) : Float(-90) }
        let range = SilenceTrimmer.keepRange(levelsDB: levels, windowFrames: 100, totalFrames: 2000, thresholdDB: -50, paddingFrames: 0)
        XCTAssertEqual(range, 500..<1000)
    }

    func testTrimKeepsPaddingAndClampsToFile() {
        let levels = (0..<20).map { (5..<10).contains($0) ? Float(-10) : Float(-90) }
        XCTAssertEqual(SilenceTrimmer.keepRange(levelsDB: levels, windowFrames: 100, totalFrames: 2000, thresholdDB: -50, paddingFrames: 50),
                       450..<1050)
        let edges = [Float(-10)] + [Float](repeating: -90, count: 3) + [Float(-10)]
        XCTAssertEqual(SilenceTrimmer.keepRange(levelsDB: edges, windowFrames: 100, totalFrames: 480, thresholdDB: -50, paddingFrames: 50),
                       0..<480)
    }

    func testTrimKeepsQuietGapsInTheMiddle() {
        let levels: [Float] = [-90, -10, -90, -90, -10, -90]
        XCTAssertEqual(SilenceTrimmer.keepRange(levelsDB: levels, windowFrames: 10, totalFrames: 60, thresholdDB: -50, paddingFrames: 0),
                       10..<50)
    }
}
