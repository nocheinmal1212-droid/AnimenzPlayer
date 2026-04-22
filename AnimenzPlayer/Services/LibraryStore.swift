import Foundation
import Combine

/// Owns the set of tracks available to the player. Currently only scans the
/// app's bundled `Music/` folder (or bundle root as a fallback), matching the
/// original app's behavior. Designed to be the single place future Wave 3
/// collection/album logic plugs into.
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var tracks: [Track] = []

    private let fileManager: FileManager
    private let audioExtensions: Set<String> = [
        "m4a", "mp3", "aac", "wav", "flac", "aiff", "caf"
    ]

    init(autoload: Bool = true, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if autoload { reload() }
    }

    /// Re-scan the bundle. Exposed so future features (user import, file-picker
    /// drop, iCloud) can trigger a refresh without re-creating the store.
    func reload() {
        tracks = discoverTracks()
    }

    /// For tests: inject a known list without touching the filesystem.
    func setTracks(_ tracks: [Track]) {
        self.tracks = tracks
    }

    // MARK: - Private

    private func discoverTracks() -> [Track] {
        var audioURLs: [URL] = []

        // Preferred: a folder reference called "Music" inside the bundle.
        if let musicURL = Bundle.main.url(forResource: "Music", withExtension: nil),
           let urls = try? fileManager.contentsOfDirectory(
            at: musicURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
           ) {
            audioURLs = urls
        } else if let resourceURL = Bundle.main.resourceURL,
                  let urls = try? fileManager.contentsOfDirectory(
                    at: resourceURL,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                  ) {
            // Fallback: flat bundle resources.
            audioURLs = urls
        }

        return audioURLs
            .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
            .map(Track.init)
            .sorted { $0.index < $1.index }
    }
}
