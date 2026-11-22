import AVFoundation
import XCTest

/// End-to-end tests of writing, splitting, trimming and exporting, using generated audio
/// instead of a live ScreenCaptureKit stream.
final class RecordingPipelineTests: XCTestCase {
    private var folder: URL!
    private let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false)!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("AudioGrabTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func buffer(seconds: Double, amplitude: Float) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(seconds * 48_000)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for c in 0..<2 {
            for i in 0..<Int(frames) {
                buffer.floatChannelData![c][i] = amplitude * Float(sin(2 * Double.pi * 440 * Double(i) / 48_000))
            }
        }
        return buffer
    }

    /// Splits a description like [(1.0, 0.5), (1.0, 0)] into 0.1 s buffers.
    private func buffers(_ parts: [(Double, Float)]) -> [AVAudioPCMBuffer] {
        parts.flatMap { seconds, amplitude in
            (0..<Int((seconds * 10).rounded())).map { _ in buffer(seconds: 0.1, amplitude: amplitude) }
        }
    }

    private func writeSource(_ parts: [(Double, Float)]) throws -> URL {
        let writer = SegmentWriter(tempFolder: folder)
        for b in buffers(parts) { try writer.write(b) }
        writer.close()
        return writer.tempURL
    }

    private func seconds(_ url: URL) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        return Double(file.length) / file.fileFormat.sampleRate
    }

    func testWAVExportIs48kHz16BitStereo() throws {
        let source = try writeSource([(1.0, 0.5)])
        let out = folder.appendingPathComponent("out.wav")
        XCTAssertTrue(try RecordingExporter.export(source: source, to: out, options: .init(format: .wav, trimSilence: false, thresholdDB: -50)))
        let file = try AVAudioFile(forReading: out)
        let asbd = file.fileFormat.streamDescription.pointee
        XCTAssertEqual(asbd.mFormatID, kAudioFormatLinearPCM)
        XCTAssertEqual(asbd.mSampleRate, 48_000)
        XCTAssertEqual(asbd.mChannelsPerFrame, 2)
        XCTAssertEqual(asbd.mBitsPerChannel, 16)
        XCTAssertEqual(file.length, 48_000)
    }

    func testM4AExportIsAAC() throws {
        let source = try writeSource([(1.0, 0.5)])
        let out = folder.appendingPathComponent("out.m4a")
        XCTAssertTrue(try RecordingExporter.export(source: source, to: out, options: .init(format: .m4a, trimSilence: false, thresholdDB: -50)))
        let file = try AVAudioFile(forReading: out)
        XCTAssertEqual(file.fileFormat.streamDescription.pointee.mFormatID, kAudioFormatMPEG4AAC)
        XCTAssertEqual(file.fileFormat.sampleRate, 48_000)
        XCTAssertEqual(file.fileFormat.channelCount, 2)
        XCTAssertEqual(try seconds(out), 1.0, accuracy: 0.1)
    }

    func testTrimRemovesSilenceAtBothEnds() throws {
        let source = try writeSource([(1.0, 0), (1.0, 0.5), (1.0, 0)])
        let out = folder.appendingPathComponent("trim.wav")
        XCTAssertTrue(try RecordingExporter.export(source: source, to: out, options: .init(format: .wav, trimSilence: true, thresholdDB: -50)))
        // 1 s of sound + 0.15 s padding on each side
        XCTAssertEqual(try seconds(out), 1.3, accuracy: 0.06)
    }

    func testTrimOfSilentFileSavesNothing() throws {
        let source = try writeSource([(1.0, 0)])
        let out = folder.appendingPathComponent("silent.wav")
        XCTAssertFalse(try RecordingExporter.export(source: source, to: out, options: .init(format: .wav, trimSilence: true, thresholdDB: -50)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.path))
    }

    private func runSession(autoSplit: Bool, trim: Bool, parts: [(Double, Float)]) throws -> [String] {
        let output = folder.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let config = RecordingSession.Configuration(baseName: "Show", outputFolder: output,
                                                    tempFolder: folder.appendingPathComponent("tmp", isDirectory: true),
                                                    format: .wav, autoSplit: autoSplit, thresholdDB: -50,
                                                    splitAfterSilence: 2, trimSilence: trim, minimumFreeBytes: 0)
        let session = try RecordingSession(configuration: config, queue: DispatchQueue(label: "test"))
        var errors: [AppError] = []
        session.onError = { errors.append($0) }
        for b in buffers(parts) { session.handle(b) }
        let done = expectation(description: "finished")
        Task {
            await session.finish()
            done.fulfill()
        }
        wait(for: [done], timeout: 30)
        XCTAssertTrue(errors.isEmpty, "\(errors.map(\.title))")
        return try FileManager.default.contentsOfDirectory(atPath: output.path).sorted()
    }

    func testSessionWithoutSplitMakesOneFile() throws {
        let files = try runSession(autoSplit: false, trim: false, parts: [(1, 0.5), (3, 0), (1, 0.5)])
        XCTAssertEqual(files, ["Show.wav"])
        XCTAssertEqual(try seconds(folder.appendingPathComponent("out/Show.wav")), 5, accuracy: 0.01)
    }

    func testSessionAutoSplitsOnSilence() throws {
        let files = try runSession(autoSplit: true, trim: false, parts: [(0.5, 0), (1, 0.5), (3, 0), (1, 0.5), (1, 0), (0.5, 0.5)])
        // Leading silence dropped; 3 s gap splits; 1 s gap does not.
        XCTAssertEqual(files, ["Show 01.wav", "Show 02.wav"])
        XCTAssertEqual(try seconds(folder.appendingPathComponent("out/Show 01.wav")), 3.0, accuracy: 0.15)
        XCTAssertEqual(try seconds(folder.appendingPathComponent("out/Show 02.wav")), 2.5, accuracy: 0.15)
    }

    func testSessionAutoSplitWithTrim() throws {
        let files = try runSession(autoSplit: true, trim: true, parts: [(1, 0.5), (3, 0), (1, 0.5), (2.5, 0)])
        XCTAssertEqual(files, ["Show 01.wav", "Show 02.wav"])
        for name in files {
            XCTAssertEqual(try seconds(folder.appendingPathComponent("out/\(name)")), 1.15, accuracy: 0.06)
        }
    }

    func testSessionDoesNotOverwriteExistingFiles() throws {
        let output = folder.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try Data().write(to: output.appendingPathComponent("Show.wav"))
        let files = try runSession(autoSplit: false, trim: false, parts: [(0.5, 0.5)])
        XCTAssertEqual(files, ["Show (2).wav", "Show.wav"])
    }

    func testLibraryListsRecordingsNewestFirst() throws {
        _ = try runSession(autoSplit: true, trim: false, parts: [(0.5, 0.5), (2.5, 0), (0.5, 0.5)])
        let items = RecordingLibrary.scan(folder: folder.appendingPathComponent("out"))
        XCTAssertEqual(Set(items.map(\.name)), ["Show 01", "Show 02"])
        XCTAssertNotNil(items.first?.duration)
    }
}
