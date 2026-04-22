import Foundation

/// User-facing player errors. Identifiable so they can drive a single-slot
/// banner or alert that auto-replaces when a new error arrives.
enum PlayerError: LocalizedError, Identifiable, Equatable {
    case loadFailed(url: URL, underlying: String)
    case playbackFailed(underlying: String)
    case noTracksAvailable

    var id: String {
        switch self {
        case .loadFailed(let url, _): return "load-\(url.absoluteString)"
        case .playbackFailed: return "playback"
        case .noTracksAvailable: return "no-tracks"
        }
    }

    var errorDescription: String? {
        switch self {
        case .loadFailed(let url, _):
            return "Couldn't load \(url.deletingPathExtension().lastPathComponent)."
        case .playbackFailed:
            return "Playback was interrupted."
        case .noTracksAvailable:
            return "No tracks available."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .loadFailed:
            return "The file may be missing or in an unsupported format."
        case .playbackFailed:
            return "Try playing the track again."
        case .noTracksAvailable:
            return "Add audio files to the Music folder in the app bundle."
        }
    }

    /// Factory for wrapping arbitrary errors while preserving Equatable. The
    /// underlying error's `localizedDescription` is stored as a string so we
    /// don't have to deal with the non-Equatable `Error` existential.
    static func loadFailed(url: URL, error: Error) -> PlayerError {
        .loadFailed(url: url, underlying: error.localizedDescription)
    }

    static func playbackFailed(error: Error) -> PlayerError {
        .playbackFailed(underlying: error.localizedDescription)
    }
}
