import Foundation

/// Builds and cleans up recording file names.
enum FileNaming {
    /// Characters that are not allowed (or cause trouble) in file names on macOS and common disk formats.
    static let illegalCharacters: Set<Character> = ["/", ":", "\\", "<", ">", "\"", "|", "?", "*"]
    static let maxLength = 200

    /// "Recording YYYY-MM-DD HH-mm-ss"
    static func defaultBaseName(for date: Date = Date(), timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return "Recording \(formatter.string(from: date))"
    }

    /// Removes illegal and control characters, collapses whitespace, strips leading dots
    /// (which would hide the file) and limits the length. May return an empty string.
    static func sanitize(_ raw: String) -> String {
        var cleaned = ""
        var lastWasSpace = false
        for character in raw {
            if illegalCharacters.contains(character) { continue }
            let isControl = character.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
            let isSpace = isControl || character.isWhitespace
            if isSpace {
                if !lastWasSpace && !cleaned.isEmpty { cleaned.append(" ") }
                lastWasSpace = true
            } else {
                cleaned.append(character)
                lastWasSpace = false
            }
        }
        while cleaned.hasPrefix(".") || cleaned.hasPrefix(" ") { cleaned.removeFirst() }
        if cleaned.count > maxLength { cleaned = String(cleaned.prefix(maxLength)) }
        while cleaned.hasSuffix(" ") { cleaned.removeLast() }
        return cleaned
    }

    /// The sanitized name the user typed, or the default name when nothing usable is left.
    static func baseName(from input: String, date: Date = Date(), timeZone: TimeZone = .current) -> String {
        let cleaned = sanitize(input)
        return cleaned.isEmpty ? defaultBaseName(for: date, timeZone: timeZone) : cleaned
    }

    /// "<base> 01", "<base> 02", ...
    static func segmentName(base: String, index: Int) -> String {
        let number = index < 10 && index >= 0 ? "0\(index)" : "\(index)"
        return "\(base) \(number)"
    }

    /// Returns a URL that doesn't exist yet, adding " (2)", " (3)" ... when needed.
    static func uniqueFileURL(in directory: URL,
                              name: String,
                              fileExtension: String,
                              exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        var candidate = directory.appendingPathComponent(name).appendingPathExtension(fileExtension)
        var counter = 2
        while exists(candidate) {
            candidate = directory.appendingPathComponent("\(name) (\(counter))").appendingPathExtension(fileExtension)
            counter += 1
        }
        return candidate
    }
}
