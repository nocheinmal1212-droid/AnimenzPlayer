import Foundation

/// Ordered queue of tracks with an active position. Owns shuffle state but
/// exposes a pure interface — no publishing, no AVFoundation, no SwiftUI.
///
/// Value-type semantics make this trivially testable and cheap to copy for
/// snapshots. The coordinator (`PlayerViewModel`) wraps mutations in
/// `@Published` updates so SwiftUI picks up changes.
///
/// Design note: indices are stored in `orderedIndices` rather than the tracks
/// themselves being shuffled. This keeps the source-of-truth order intact,
/// makes shuffle/unshuffle reversible, and avoids ambiguity about "what list
/// are we in".
struct PlayQueue: Equatable {
    private(set) var tracks: [Track] = []
    private(set) var orderedIndices: [Int] = []
    private(set) var position: Int = 0
    private(set) var isShuffled: Bool = false

    var current: Track? {
        guard orderedIndices.indices.contains(position) else { return nil }
        let trackIndex = orderedIndices[position]
        guard tracks.indices.contains(trackIndex) else { return nil }
        return tracks[trackIndex]
    }

    var isEmpty: Bool { orderedIndices.isEmpty }
    var count: Int { orderedIndices.count }

    // MARK: - Mutation

    mutating func setTracks(_ new: [Track], preservingCurrent: Bool = true) {
        let previousCurrent = current
        tracks = new
        rebuildOrder(preservingCurrent: preservingCurrent ? previousCurrent : nil)
    }

    mutating func setShuffled(_ shuffled: Bool) {
        guard shuffled != isShuffled else { return }
        let previousCurrent = current
        isShuffled = shuffled
        rebuildOrder(preservingCurrent: previousCurrent)
    }

    /// Jumps the play head to `track` if it exists in the queue. Returns the
    /// new current track (or nil if the track wasn't found).
    @discardableResult
    mutating func jump(to track: Track) -> Track? {
        guard let trackIdx = tracks.firstIndex(of: track),
              let newPos = orderedIndices.firstIndex(of: trackIdx) else {
            return nil
        }
        position = newPos
        return current
    }

    @discardableResult
    mutating func advance() -> Track? {
        guard !isEmpty else { return nil }
        position = (position + 1) % orderedIndices.count
        return current
    }

    @discardableResult
    mutating func retreat() -> Track? {
        guard !isEmpty else { return nil }
        position = (position - 1 + orderedIndices.count) % orderedIndices.count
        return current
    }

    // MARK: - Private

    private mutating func rebuildOrder(preservingCurrent track: Track?) {
        let base = Array(tracks.indices)
        orderedIndices = isShuffled ? base.shuffled() : base
        if let track,
           let trackIdx = tracks.firstIndex(of: track),
           let newPos = orderedIndices.firstIndex(of: trackIdx) {
            position = newPos
        } else {
            position = 0
        }
    }
}
