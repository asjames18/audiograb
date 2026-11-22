import XCTest

final class AutoSplitTests: XCTestCase {
    /// Runs a pattern like "SSS..." (S = sound, . = silence) through the splitter.
    private func run(_ pattern: String, silence: TimeInterval, step: TimeInterval = 0.5) -> [AutoSplitter.Action] {
        var splitter = AutoSplitter(silenceDuration: silence)
        return pattern.map { splitter.process(bufferDuration: step, isSilent: $0 == ".") }
    }

    func testLeadingSilenceIsDroppedUntilSoundStarts() {
        XCTAssertEqual(run("..S", silence: 2), [.drop, .drop, .startSegmentAndWrite])
    }

    func testShortSilenceDoesNotSplit() {
        // 1.5 s of silence with a 2 s split time
        let actions = run("SS...S", silence: 2)
        XCTAssertEqual(actions, [.startSegmentAndWrite, .write, .write, .write, .write, .write])
    }

    func testLongSilenceClosesTheFile() {
        // 4 silent buffers = 2 s
        let actions = run("SS....", silence: 2)
        XCTAssertEqual(actions, [.startSegmentAndWrite, .write, .write, .write, .write, .closeSegment])
    }

    func testSilenceAfterSplitIsDroppedAndSoundStartsNextFile() {
        let actions = run("S....,..S".replacingOccurrences(of: ",", with: ""), silence: 2)
        XCTAssertEqual(actions, [.startSegmentAndWrite, .write, .write, .write, .closeSegment, .drop, .drop, .startSegmentAndWrite])
    }

    func testCountsSegments() {
        var splitter = AutoSplitter(silenceDuration: 1)
        for isSilent in [false, true, true, false, true, true, false] {
            _ = splitter.process(bufferDuration: 0.5, isSilent: isSilent)
        }
        XCTAssertEqual(splitter.segmentsStarted, 3)
        XCTAssertTrue(splitter.inSegment)
    }

    func testSoundResetsTheSilenceTimer() {
        // silence 1.5 s, sound, silence 1.5 s: never reaches 2 s in a row
        let actions = run("S...S...", silence: 2)
        XCTAssertFalse(actions.contains(.closeSegment))
    }

    func testFloatingPointBufferDurationsStillSplit() {
        var splitter = AutoSplitter(silenceDuration: 2)
        _ = splitter.process(bufferDuration: 0.1, isSilent: false)
        var closedAfter = 0
        for i in 1...30 where closedAfter == 0 {
            if splitter.process(bufferDuration: 0.1, isSilent: true) == .closeSegment { closedAfter = i }
        }
        XCTAssertTrue((20...21).contains(closedAfter), "closed after \(closedAfter) buffers")
    }
}
