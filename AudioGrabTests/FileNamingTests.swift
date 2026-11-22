import XCTest

final class FileNamingTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    func testDefaultNameUsesDateAndTime() {
        let date = Date(timeIntervalSince1970: 1_795_000_000) // 2026-11-18 11:06:40 UTC
        XCTAssertEqual(FileNaming.defaultBaseName(for: date, timeZone: utc), "Recording 2026-11-18 11-06-40")
    }

    func testDefaultNameHasNoIllegalCharacters() {
        let name = FileNaming.defaultBaseName()
        XCTAssertFalse(name.contains(":"))
        XCTAssertFalse(name.contains("/"))
        XCTAssertTrue(name.hasPrefix("Recording "))
    }

    func testSanitizeStripsSlashesAndColons() {
        XCTAssertEqual(FileNaming.sanitize("Interview 10:30 a/b"), "Interview 1030 ab")
    }

    func testSanitizeStripsOtherIllegalCharacters() {
        XCTAssertEqual(FileNaming.sanitize(#"a\b<c>d"e|f?g*h"#), "abcdefgh")
    }

    func testSanitizeRemovesControlCharactersAndCollapsesWhitespace() {
        XCTAssertEqual(FileNaming.sanitize("  Morning\t\tshow \n part\u{0}  2  "), "Morning show part 2")
    }

    func testSanitizeRemovesLeadingDotsSoFilesArentHidden() {
        XCTAssertEqual(FileNaming.sanitize("..hidden"), "hidden")
        XCTAssertEqual(FileNaming.sanitize(". . name"), "name")
    }

    func testSanitizeKeepsUnicodeAndPunctuation() {
        XCTAssertEqual(FileNaming.sanitize("Café – Episode #3 (live)!"), "Café – Episode #3 (live)!")
    }

    func testSanitizeLimitsLength() {
        let long = String(repeating: "a", count: 500)
        XCTAssertEqual(FileNaming.sanitize(long).count, FileNaming.maxLength)
    }

    func testBaseNameFallsBackToDefaultWhenEmpty() {
        let date = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(FileNaming.baseName(from: " /:: ", date: date, timeZone: utc), "Recording 1970-01-01 00-00-00")
        XCTAssertEqual(FileNaming.baseName(from: "", date: date, timeZone: utc), "Recording 1970-01-01 00-00-00")
        XCTAssertEqual(FileNaming.baseName(from: "My Mix", date: date, timeZone: utc), "My Mix")
    }

    func testSegmentNamesAreZeroPadded() {
        XCTAssertEqual(FileNaming.segmentName(base: "Show", index: 1), "Show 01")
        XCTAssertEqual(FileNaming.segmentName(base: "Show", index: 2), "Show 02")
        XCTAssertEqual(FileNaming.segmentName(base: "Show", index: 10), "Show 10")
        XCTAssertEqual(FileNaming.segmentName(base: "Show", index: 123), "Show 123")
    }

    func testUniqueURLAddsCounterWhenFileExists() {
        let folder = URL(fileURLWithPath: "/tmp/ag", isDirectory: true)
        let taken: Set<String> = ["Take.wav", "Take (2).wav"]
        let url = FileNaming.uniqueFileURL(in: folder, name: "Take", fileExtension: "wav") { taken.contains($0.lastPathComponent) }
        XCTAssertEqual(url.lastPathComponent, "Take (3).wav")
    }

    func testUniqueURLKeepsNameWhenFree() {
        let folder = URL(fileURLWithPath: "/tmp/ag", isDirectory: true)
        let url = FileNaming.uniqueFileURL(in: folder, name: "v1.2 final", fileExtension: "m4a") { _ in false }
        XCTAssertEqual(url.lastPathComponent, "v1.2 final.m4a")
    }

    func testTimeFormat() {
        XCTAssertEqual(TimeFormat.clock(0), "0:00")
        XCTAssertEqual(TimeFormat.clock(7.9), "0:07")
        XCTAssertEqual(TimeFormat.clock(754), "12:34")
        XCTAssertEqual(TimeFormat.clock(3723), "1:02:03")
    }

    func testDiskFullErrorsAreRecognized() {
        XCTAssertTrue(DiskSpace.isOutOfSpace(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)))
        XCTAssertTrue(DiskSpace.isOutOfSpace(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))))
        XCTAssertTrue(DiskSpace.isOutOfSpace(NSError(domain: NSOSStatusErrorDomain, code: -34)))
        let wrapped = NSError(domain: "x", code: 1, userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))])
        XCTAssertTrue(DiskSpace.isOutOfSpace(wrapped))
        XCTAssertFalse(DiskSpace.isOutOfSpace(NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))))
    }
}
