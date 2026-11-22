import AVFoundation

struct RecordingItem: Identifiable, Hashable {
    let url: URL
    let date: Date
    let size: Int64
    let duration: TimeInterval?

    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }
    var fileExtension: String { url.pathExtension.lowercased() }
}

enum RecordingLibrary {
    /// WAV and M4A files in the folder, newest first.
    static func scan(folder: URL) -> [RecordingItem] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .creationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                                       options: [.skipsHiddenFiles]) else { return [] }
        return urls
            .filter { OutputFormat.recordingExtensions.contains($0.pathExtension.lowercased()) }
            .compactMap { url -> RecordingItem? in
                let values = try? url.resourceValues(forKeys: Set(keys))
                guard values?.isRegularFile ?? true else { return nil }
                let date = values?.creationDate ?? values?.contentModificationDate ?? .distantPast
                return RecordingItem(url: url, date: date, size: Int64(values?.fileSize ?? 0), duration: duration(of: url))
            }
            .sorted { $0.date > $1.date }
    }

    static func duration(of url: URL) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: url), file.fileFormat.sampleRate > 0 else { return nil }
        return Double(file.length) / file.fileFormat.sampleRate
    }
}
