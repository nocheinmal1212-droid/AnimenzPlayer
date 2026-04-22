import Foundation
import Combine

/// Coordinates the library, playback engine, play queue, and persistence.
/// This class is deliberately thin — all the real logic lives in the
/// collaborators so each can be tested and evolved independently.
///
/// All `@Published` state is consumed directly by SwiftUI views.
@MainActor
final class PlayerViewModel: ObservableObject {
    // MARK: - UI state

    @Published private(set) var currentTrack: Track?
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var currentError: PlayerError?

    @Published var isShuffled: Bool = false {
        didSet {
            guard isShuffled != queue.isShuffled else { return }
            queue.setShuffled(isShuffled)
            persistence.update { $0.isShuffled = isShuffled }
        }
    }

    var tracks: [Track] { library.tracks }

    // MARK: - Collaborators

    private let library: LibraryStore
    private let engine: PlaybackEngine
    private let persistence: PersistenceStore
    private var queue = PlayQueue()

    private var cancellables: Set<AnyCancellable> = []
    private var positionWriteThrottle: Int = -1

    // MARK: - Init

    /// Designated initializer. Takes every collaborator explicitly — no
    /// default values, because default-argument expressions are evaluated in
    /// a synchronous nonisolated context and would refuse to call the
    /// `@MainActor`-isolated inits of `LibraryStore` / `PersistenceStore`.
    init(
        library: LibraryStore,
        engine: PlaybackEngine,
        persistence: PersistenceStore
    ) {
        self.library = library
        self.engine = engine
        self.persistence = persistence

        bindEngine()
        bindLibrary()
        restoreFromPersistence()
    }

    /// Convenience initializer for the standard runtime configuration. The
    /// body runs in `@MainActor` context, so it *can* construct the
    /// main-actor-isolated stores — which is what lets us avoid the
    /// default-argument problem above.
    convenience init() {
        self.init(
            library: LibraryStore(),
            engine: AVPlayerEngine(),
            persistence: PersistenceStore()
        )
    }

    // MARK: - Intents

    func play(_ track: Track) {
        guard !queue.isEmpty else {
            currentError = .noTracksAvailable
            return
        }
        guard queue.jump(to: track) != nil else {
            currentError = .noTracksAvailable
            return
        }
        Task { await loadAndPlay(track, autoStart: true) }
    }

    func togglePlayPause() {
        if engine.isPlaying {
            engine.pause()
        } else if currentTrack != nil {
            engine.play()
        } else if let first = queue.current ?? tracks.first {
            _ = queue.jump(to: first)
            Task { await loadAndPlay(first, autoStart: true) }
        }
    }

    func next() {
        guard let track = queue.advance() else { return }
        Task { await loadAndPlay(track, autoStart: true) }
    }

    func previous() {
        // >3s in: restart current track instead of going back — matches
        // iOS Music and the original app's behavior.
        if progress > 3 {
            Task { await engine.seek(to: 0) }
            progress = 0
            return
        }
        guard let track = queue.retreat() else { return }
        Task { await loadAndPlay(track, autoStart: true) }
    }

    func seek(to time: Double) {
        // Update the local progress optimistically so the slider feels glued
        // to the thumb; the real seek lands a moment later.
        progress = time
        Task { await engine.seek(to: time) }
    }

    // MARK: - Lifecycle hooks

    /// Call from `ScenePhase == .background` (or app termination on macOS) to
    /// make sure last-position state hits disk before the process is snapshotted.
    func flushPendingState() {
        persistence.update {
            $0.lastTrackURL = currentTrack?.url
            $0.lastPosition = progress
        }
        persistence.flush()
    }

    // MARK: - Engine wiring

    private func bindEngine() {
        engine.onTimeChange = { [weak self] time in
            guard let self else { return }
            self.progress = time
            self.persistPositionIfDue(time)
        }
        engine.onDurationChange = { [weak self] dur in
            self?.duration = dur
        }
        engine.onPlayingChange = { [weak self] playing in
            self?.isPlaying = playing
        }
        engine.onFinish = { [weak self] in
            self?.next()
        }
        engine.onError = { [weak self] err in
            self?.currentError = err
        }
    }

    private func bindLibrary() {
        // When the library finishes (re-)scanning, refresh the queue while
        // preserving the currently-playing track if it survived the rescan.
        library.$tracks
            .sink { [weak self] tracks in
                self?.queue.setTracks(tracks, preservingCurrent: true)
            }
            .store(in: &cancellables)
    }

    private func restoreFromPersistence() {
        let state = persistence.state

        // Setting this triggers didSet, which updates the queue and writes
        // the same value back to persistence (harmless — debounced, identical).
        if isShuffled != state.isShuffled {
            isShuffled = state.isShuffled
        }

        guard let url = state.lastTrackURL,
              let track = tracks.first(where: { $0.url == url }) else {
            return
        }

        // Prime the player with the last track at its last position, paused.
        // The UI shows the player bar with the track ready to resume.
        queue.jump(to: track)
        let position = state.lastPosition

        Task { [weak self, engine] in
            do {
                try await engine.load(url: track.url)
                await engine.seek(to: position)
                await MainActor.run {
                    guard let self else { return }
                    self.currentTrack = track
                    self.progress = position
                }
            } catch {
                // Restore is best-effort. Silent failure is acceptable.
            }
        }
    }

    // MARK: - Playback helper

    private func loadAndPlay(_ track: Track, autoStart: Bool) async {
        do {
            try await engine.load(url: track.url)
            if autoStart { engine.play() }
            currentTrack = track
            progress = 0
            persistence.update {
                $0.lastTrackURL = track.url
                $0.lastPosition = 0
            }
        } catch let error as PlayerError {
            currentError = error
        } catch {
            currentError = .loadFailed(url: track.url, error: error)
        }
    }

    /// Persist playback position about once per 5 seconds. Cheap enough that
    /// losing the app to a crash still leaves the user within 5s of where
    /// they were.
    private func persistPositionIfDue(_ time: Double) {
        let bucket = Int(time) / 5
        guard bucket != positionWriteThrottle else { return }
        positionWriteThrottle = bucket
        persistence.update { $0.lastPosition = time }
    }
}
