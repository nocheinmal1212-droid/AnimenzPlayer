import Foundation

/// What subset of the library the player is currently listening through.
///
/// Scope is separate from the view's *filter* (what's visible) and from the
/// search box (what's typed). See WAVE3_PLAN §4.3 for the full interaction
/// table. Briefly:
///
/// - Scope is set only when the user explicitly starts playback from a
///   filtered / searched context.
/// - Clearing the search box does NOT reset scope — only the "X" on the
///   scope chip (or the filter-picker's equivalent) does.
/// - Next / previous / shuffle / repeat all act within the current scope's
///   track list, without requiring any engine or queue changes.
enum PlaybackScope: Equatable, Hashable {
    /// The whole library. The default, and the behavior of Waves 1–2.
    case all

    /// Only favorited tracks.
    case favorites

    /// Only recently-played tracks.
    case recent

    /// The result of a search, captured at the moment the user pressed play.
    /// `query` is kept so the chip can display it and persistence can
    /// re-apply scope on relaunch; `results` is the snapshot of tracks that
    /// matched at that time.
    case search(query: String, results: [Track])

    /// Label shown in the scope indicator chip.
    var displayName: String {
        switch self {
        case .all:                  return "All Tracks"
        case .favorites:            return "Favorites"
        case .recent:               return "Recently Played"
        case .search(let query, _): return "\"\(query)\""
        }
    }

    /// True when scope is restricting playback to a subset.
    var isRestricted: Bool {
        if case .all = self { return false }
        return true
    }
}
