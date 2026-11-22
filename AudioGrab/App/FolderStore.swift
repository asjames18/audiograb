import Foundation

/// Remembers the output folder between launches with a security-scoped bookmark.
final class FolderStore {
    private let key = "outputFolderBookmark"
    private let defaults: UserDefaults
    private var accessedURL: URL?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static var defaultFolder: URL {
        let music = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music", isDirectory: true)
        return music.appendingPathComponent("AudioGrab", isDirectory: true)
    }

    /// The saved folder, or ~/Music/AudioGrab.
    func resolve() -> URL {
        guard let data = defaults.data(forKey: key) else { return Self.defaultFolder }
        var stale = false
        var resolved = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
        if resolved == nil {
            resolved = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        }
        guard let url = resolved else { return Self.defaultFolder }
        beginAccess(url)
        if stale { save(url) }
        return url
    }

    func set(_ url: URL) {
        save(url)
        beginAccess(url)
    }

    func reset() {
        defaults.removeObject(forKey: key)
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
    }

    private func save(_ url: URL) {
        let data = (try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil))
            ?? (try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil))
        if let data { defaults.set(data, forKey: key) }
    }

    private func beginAccess(_ url: URL) {
        guard accessedURL != url else { return }
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = url.startAccessingSecurityScopedResource() ? url : nil
    }
}
