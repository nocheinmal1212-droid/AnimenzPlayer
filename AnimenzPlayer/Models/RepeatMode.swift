import Foundation

/// Playback repeat behavior. Persisted via `PersistenceStore.State`.
///
/// Semantics:
/// - `.off`: when the last track finishes, stop playback.
/// - `.all`: when the last track finishes, wrap to the first track.
/// - `.one`: when the current track finishes, restart the same track.
enum RepeatMode: String, Codable, CaseIterable, Identifiable {
    case off
    case all
    case one

    var id: String { rawValue }

    /// The next mode when the user taps the repeat button. Matches iOS Music:
    /// off → all → one → off.
    var cycled: RepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }

    var systemImageName: String {
        switch self {
        case .off, .all: return "repeat"
        case .one:       return "repeat.1"
        }
    }

    /// Used by the UI to tint the repeat button.
    var isActive: Bool {
        self != .off
    }
}
