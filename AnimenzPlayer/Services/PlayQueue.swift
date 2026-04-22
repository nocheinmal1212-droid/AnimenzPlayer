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

    // MARK: - Wave 2 — Repeat-aware advance

    /// Result of a natural "track finished" event, given a repeat mode.
    enum FinishOutcome: Equatable {
        /// Play a new track (could be the same one on `.one`, or a wrap on `.all`).
        case play(Track)
        /// Stop playback. Happens on `.off` when the last track finishes.
        case stop
    }

    /// Advances the queue per `repeatMode` and returns what the player should
    /// do. Unlike `advance()` which is used by the user's "next" intent and
    /// always wraps, this encodes the subtler rules for automatic advancement
    /// at end-of-track:
    ///
    /// - `.off`: advance, but stop at the end rather than wrapping.
    /// - `.all`: advance, wrapping to the first track.
    /// - `.one`: stay on the current track.
    mutating func advanceForFinish(repeatMode: RepeatMode) -> FinishOutcome {
        guard !isEmpty else { return .stop }

        switch repeatMode {
        case .one:
            guard let t = current else { return .stop }
            return .play(t)

        case .all:
            position = (position + 1) % orderedIndices.count
            return current.map(FinishOutcome.play) ?? .stop

        case .off:
            let isLast = position == orderedIndices.count - 1
            if isLast { return .stop }
            position += 1
            return current.map(FinishOutcome.play) ?? .stop
        }
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
