import Foundation

enum OutputFormat: String, CaseIterable, Identifiable {
    case wav
    case m4a

    var id: String { rawValue }
    var fileExtension: String { rawValue }

    var displayName: String {
        switch self {
        case .wav: return "WAV"
        case .m4a: return "M4A (AAC)"
        }
    }

    var detail: String {
        switch self {
        case .wav: return "48 kHz, 16-bit stereo, uncompressed"
        case .m4a: return "AAC 256 kbps, 48 kHz stereo"
        }
    }

    static let recordingExtensions: Set<String> = Set(allCases.map(\.fileExtension))
}
