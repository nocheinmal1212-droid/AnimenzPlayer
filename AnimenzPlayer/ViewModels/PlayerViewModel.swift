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
    
    /// Playback progress carrier. Kept on a dedicated observable so 4 Hz
    /// engine ticks don't invalidate every view that observes `self`.
    /// See `PlaybackProgressModel` for rationale.
    let progressModel = PlaybackProgressModel()

    /// Read-only forwarder for existing call sites (tests, persistence,
    /// `previous()`'s "restart if >3s in" check). Writes must go through
    /// `progressModel.progress` directly so SwiftUI subscribes correctly.
    var progress: Double {
        get { progressModel.progress }
        set { progressModel.progress = newValue }
    }

    // MARK: - Wave 2 state

    /// Repeat mode. Persisted.
    @Published var repeatMode: RepeatMode = .off {
        didSet {
            guard oldValue != repeatMode else { return }
            persistence.update { $0.repeatMode = repeatMode }
        }
    }

    /// Favorited track URLs. `@Published` so the UI updates when favorites change.
    @Published private(set) var favorites: Set<URL> = []

    /// Most-recently-played URLs, newest first. Mirrored from persistence.
    @Published private(set) var recentlyPlayed: [URL] = []

    /// Exposed so views can observe the countdown / start / stop.
    let sleepTimer: SleepTimer

    /// The Wave 2 cap on `recentlyPlayed` entries.
    private let recentlyPlayedCap = 50

    // MARK: - Wave 3 state

    /// What subset of the library playback is currently traversing. Default
    /// is `.all`. Changed by `play(_:inScope:)` (set) and `clearScope()`
    /// (reset). Persisted to disk as `lastScopeQuery` — only `.search` is
    /// serialized because the others are re-derivable.
    @Published private(set) var currentScope: PlaybackScope = .all

    // MARK: - Collaborators

    private let library: LibraryStore
    private let engine: PlaybackEngine
    private let persistence: PersistenceStore
    private var queue = PlayQueue()

    // MARK: - Wave 2 collaborators

    private let nowPlaying: NowPlayingController

    private var cancellables: Set<AnyCancellable> = []
    private var positionWriteThrottle: Int = -1
    private var playbackTask: Task<Void, Never>?
    private var playbackRequest = 0
    private var shouldAutoplay = false

    // MARK: - Init

    /// Designated initializer. Takes every collaborator explicitly — no
    /// default values, because default-argument expressions are evaluated in
    /// a synchronous nonisolated context and would refuse to call the
    /// `@MainActor`-isolated inits of the stores.
    init(
        library: LibraryStore,
        engine: PlaybackEngine,
        persistence: PersistenceStore,
        nowPlaying: NowPlayingController,
        sleepTimer: SleepTimer
    ) {
        self.library = library
        self.engine = engine
        self.persistence = persistence
        self.nowPlaying = nowPlaying
        self.sleepTimer = sleepTimer

        bindEngine()
        bindLibrary()
        bindWave2()
        bindWave3()
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
            persistence: PersistenceStore(),
            nowPlaying: NowPlayingController(),
            sleepTimer: SleepTimer()
        )
    }

    /// Wave-1-compatible convenience init. Kept so existing call sites
    /// (previews, early tests) that don't care about Wave 2 collaborators
    /// continue to compile. New code should use the designated init.
    convenience init(
        library: LibraryStore,
        engine: PlaybackEngine,
        persistence: PersistenceStore
    ) {
        self.init(
            library: library,
            engine: engine,
            persistence: persistence,
            nowPlaying: NowPlayingController(),
            sleepTimer: SleepTimer()
        )
    }

    // MARK: - Intents

    /// Backward-compatible play entry point. Equivalent to playing within
    /// `.all` scope (the Wave 1–2 behavior).
    func play(_ track: Track) {
        play(track, inScope: .all)
    }

    func togglePlayPause(source: String = "interface") {
        logContext("intent.toggle", ["source": source])
        if shouldAutoplay || engine.isPlaying {
            pausePlayback()
        } else {
            requestPlay()
        }
    }

    private func pausePlayback() {
        shouldAutoplay = false
        engine.pause()
        isPlaying = false
    }

    private func requestPlay() {
        shouldAutoplay = true
        if playbackTask != nil {
            isPlaying = true // The load may finish, but only this intent can start it.
        } else if currentTrack != nil {
            engine.play()
        } else if let first = queue.current ?? tracks.first {
            _ = queue.jump(to: first)
            startPlayback(first)
        } else {
            shouldAutoplay = false
        }
    }

    func next(source: String = "interface") {
        logContext("intent.next", ["source": source])
        guard let track = queue.advance() else { return }
        startPlayback(track)
    }

    func previous(source: String = "interface") {
        logContext("intent.previous", ["source": source])
        // >3s in: restart current track instead of going back — matches
        // iOS Music and the original app's behavior.
        if progress > 3 {
            Task { await engine.seek(to: 0) }
            progressModel.progress = 0              // was: progress = 0
            return
        }
        guard let track = queue.retreat() else { return }
        startPlayback(track)
    }

    func seek(to time: Double, source: String = "interface") {
        logContext("intent.seek", ["source": source, "target": String(time)])
        progressModel.progress = time           // was: progress = time
        Task { await engine.seek(to: time) }
    }

    // MARK: - Wave 2 intents

    /// Cycle repeat mode: off → all → one → off.
    func cycleRepeatMode() {
        repeatMode = repeatMode.cycled
    }

    func isFavorite(_ track: Track) -> Bool {
        favorites.contains(track.url)
    }

    func toggleFavorite(_ track: Track) {
        if favorites.contains(track.url) {
            favorites.remove(track.url)
        } else {
            favorites.insert(track.url)
            Haptics.play(.success)
        }
        let snapshot = favorites
        persistence.update { $0.favorites = snapshot }
    }

    /// Convenience accessor: Tracks whose URL is in `favorites`, in library order.
    var favoriteTracks: [Track] {
        tracks.filter { favorites.contains($0.url) }
    }

    /// Recently-played tracks that still resolve against the current library,
    /// newest first, deduplicated.
    var recentlyPlayedTracks: [Track] {
        let byURL = Dictionary(uniqueKeysWithValues: tracks.map { ($0.url, $0) })
        return recentlyPlayed.compactMap { byURL[$0] }
    }

    func startSleepTimer(_ mode: SleepTimer.Mode) {
        logContext("sleep_timer.start", ["mode": String(describing: mode)])
        sleepTimer.start(mode)
    }

    func cancelSleepTimer() {
        logContext("sleep_timer.cancel")
        sleepTimer.stop()
    }

    // MARK: - Wave 3 intents

    /// Play `track`, restricting the queue to `scope`'s tracks. Next /
    /// previous / shuffle / repeat subsequently act within scope.
    ///
    /// If `scope`'s track list is empty or doesn't contain `track`,
    /// surfaces `.noTracksAvailable` and leaves the queue untouched.
    func play(_ track: Track, inScope newScope: PlaybackScope) {
        logContext("intent.select_track", ["source": "interface", "targetTrack": PlaybackDiagnostics.trackID(track.url)])
        let scopeTracks = tracksForScope(newScope)
        guard !scopeTracks.isEmpty, scopeTracks.contains(track) else {
            currentError = .noTracksAvailable
            return
        }
        // `preservingCurrent: false` resets position to 0 and rebuilds the
        // shuffle order for the new list; jump(to:) then lands the play
        // head on the requested track.
        queue.setTracks(scopeTracks, preservingCurrent: false)
        if currentScope != newScope {
            currentScope = newScope
        }
        guard queue.jump(to: track) != nil else {
            currentError = .noTracksAvailable
            return
        }
        startPlayback(track)
    }

    /// Reset scope to `.all`, preserving the currently-playing track.
    /// Called by the ScopeIndicator's "X" button.
    func clearScope() {
        guard currentScope != .all else { return }
        queue.setTracks(tracks, preservingCurrent: true)
        currentScope = .all
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
            self.progressModel.progress = time     // was: self.progress = time
            self.persistPositionIfDue(time)
        }
        engine.onDurationChange = { [weak self] dur in
            self?.duration = dur
        }
        engine.onPlayingChange = { [weak self] playing in
            guard let self else { return }
            if self.playbackTask == nil { self.shouldAutoplay = playing }
            self.isPlaying = playing || (self.playbackTask != nil && self.shouldAutoplay)
        }
        engine.onFinish = { [weak self] in
            self?.next()
        }
        engine.onError = { [weak self] err in
            self?.logContext("coordinator.error", ["type": Self.errorKind(err)])
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

    // MARK: - Wave 2 bindings

    /// Wires the Wave 2 collaborators. This method is deliberately additive:
    /// it doesn't mutate the existing Wave 1 bindings but *does* replace the
    /// engine's `onFinish` callback to make it repeat-aware. The Wave 1
    /// `bindEngine` above sets `onFinish = next` as a default; we override
    /// here because the semantics genuinely change in Wave 2.
    private func bindWave2() {
        // Override Wave 1's onFinish with repeat-aware logic.
        engine.onFinish = { [weak self] in
            self?.handleTrackFinished()
        }

        // Route remote-control events (headphones, lock screen, Control Center,
        // etc.) into the existing intents.
        nowPlaying.onCommand = { [weak self] intent in
            guard let self else { return }
            self.logContext("intent.remote", ["command": String(describing: intent)])
            switch intent {
            case .play:        self.requestPlay()
            case .pause:       self.pausePlayback()
            case .toggle:      self.togglePlayPause(source: "remote")
            case .next:        self.next(source: "remote")
            case .previous:    self.previous(source: "remote")
            case .seek(let t): self.seek(to: t, source: "remote")
            }
        }

        // Interruption handling (iOS only at runtime; callback fires never on macOS).
        nowPlaying.onInterruption = { [weak self] intent in
            guard let self else { return }
            switch intent {
            case .began:
                // System took the audio focus — pause so we don't try to
                // play silently underneath a phone call.
                self.engine.pause()
            case .endedResume:
                // System says it's OK to resume. Only do so if we were
                // mid-track (avoid a surprise playback start after cold launch).
                if self.currentTrack != nil {
                    self.engine.play()
                }
            case .endedHold:
                break  // User can hit play themselves.
            }
        }

        // When the sleep timer expires, pause playback and notify haptically.
        sleepTimer.onExpire = { [weak self] in
            self?.logContext("sleep_timer.expired")
            self?.pausePlayback()
            Haptics.play(.warning)
        }

        // When the now-playing state changes, keep the MediaPlayer data
        // dict in sync. We observe @Published properties via Combine rather
        // than sprinkling calls at every state-change site. Throttled to 1Hz
        // because the engine's time observer fires at 4Hz and Lock Screen
        // scrub accuracy doesn't benefit from more than once per second.
        Publishers.CombineLatest($isPlaying, progressModel.$progress)
            .throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] playing, time in
                self?.nowPlaying.updatePlaybackState(
                    isPlaying: playing,
                    elapsedTime: time,
                    rate: playing ? 1.0 : 0.0
                )
            }
            .store(in: &cancellables)

        // When the current track changes, push new metadata (with artwork)
        // into Now Playing.
        $currentTrack
            .removeDuplicates()
            .sink { [weak self] track in
                guard let self else { return }
                Task { await self.refreshNowPlayingMetadata(for: track) }
            }
            .store(in: &cancellables)
    }

    // MARK: - Wave 3 bindings

    /// Wires the Wave 3 behaviors. Additive per chokepoint rule #4:
    /// this method does not edit Wave 1 or Wave 2 bindings.
    ///
    /// Two responsibilities:
    /// 1. Persist scope changes to disk (query only; results are re-derived).
    /// 2. Re-apply scope if the library is reloaded mid-session (e.g. a
    ///    future user-triggered refresh). Uses `dropFirst()` to skip the
    ///    initial library value, which is already handled by
    ///    `restoreFromPersistence()`.
    private func bindWave3() {
        $currentScope
            .dropFirst()
            .sink { [weak self] scope in
                guard let self else { return }
                let query: String? = {
                    if case .search(let q, _) = scope { return q }
                    return nil
                }()
                self.persistence.update { $0.lastScopeQuery = query }
            }
            .store(in: &cancellables)

        library.$tracks
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.reapplyScopeAfterLibraryChange()
            }
            .store(in: &cancellables)
    }

    /// Called when a track finishes naturally. Consults repeat mode and the
    /// sleep timer. Sleep-timer expiration takes precedence — if the user set
    /// "end of track", we don't start the next one even if repeat mode would
    /// normally advance.
    private func handleTrackFinished() {
        logContext("queue.track_finished")
        let wasEndOfTrackTimer: Bool
        if case .endOfTrack = sleepTimer.mode { wasEndOfTrackTimer = true }
        else { wasEndOfTrackTimer = false }

        // Let the sleep timer fire first (synchronous onExpire → engine.pause).
        sleepTimer.handleTrackFinished()

        if wasEndOfTrackTimer {
            // User explicitly asked to stop at end of track. Respect that
            // instead of advancing per repeat mode.
            return
        }

        let outcome = queue.advanceForFinish(repeatMode: repeatMode)
        switch outcome {
        case .stop:
            logContext("queue.stop_at_end")
            pausePlayback()
            // Leave `currentTrack` where it is so the player bar persists
            // with the "paused at the end" state.
        case .play(let track):
            logContext("queue.autoplay", ["targetTrack": PlaybackDiagnostics.trackID(track.url)])
            startPlayback(track)
        }
    }

    private func refreshNowPlayingMetadata(for track: Track?) async {
        guard let track else {
            nowPlaying.update(track: nil, artwork: nil, duration: 0)
            return
        }
        let artwork = await ArtworkCache.image(for: track, size: .full)
        // Racing: another track-change may have fired while we were loading.
        guard currentTrack?.id == track.id else { return }
        nowPlaying.update(track: track, artwork: artwork, duration: duration)
    }

    /// Records a track in recently-played, newest first, deduplicated, capped.
    private func recordPlay(_ track: Track) {
        var list = recentlyPlayed
        list.removeAll(where: { $0 == track.url })
        list.insert(track.url, at: 0)
        if list.count > recentlyPlayedCap {
            list = Array(list.prefix(recentlyPlayedCap))
        }
        recentlyPlayed = list
        let snapshot = list
        persistence.update { $0.recentlyPlayed = snapshot }
    }

    private func restoreFromPersistence() {
        let state = persistence.state

        // Setting this triggers didSet, which updates the queue and writes
        // the same value back to persistence (harmless — debounced, identical).
        if isShuffled != state.isShuffled {
            isShuffled = state.isShuffled
        }

        // --- Wave 2 restoration ---
        if repeatMode != state.repeatMode {
            repeatMode = state.repeatMode  // triggers didSet; same harmless self-write
        }
        favorites = state.favorites
        recentlyPlayed = state.recentlyPlayed
        // --- end Wave 2 ---

        // --- Wave 3 restoration ---
        // Re-apply a saved search scope, if any. If the query no longer
        // resolves to any tracks (e.g. the library changed), fall back to
        // `.all` silently. Non-search scopes (.favorites, .recent) are
        // ephemeral per session by design — scope persistence is about the
        // restricted-playback experience not being lost on relaunch, and
        // those two scopes are fully derivable from other saved state.
        if let query = state.lastScopeQuery {
            let results = SearchEngine.rank(query, in: library.tracks)
            if !results.isEmpty {
                queue.setTracks(results, preservingCurrent: true)
                currentScope = .search(query: query, results: results)
            }
        }
        // --- end Wave 3 ---

        guard let url = state.lastTrackURL,
              let track = tracks.first(where: { $0.url == url }) else {
            return
        }

        // Prime the player with the last track at its last position, paused.
        // The UI shows the player bar with the track ready to resume.
        queue.jump(to: track)
        let position = state.lastPosition

        playbackRequest &+= 1
        let revision = playbackRequest
        playbackTask = Task { [weak self, engine] in
            defer { if self?.playbackRequest == revision { self?.playbackTask = nil } }
            let request = UUID().uuidString
            self?.logContext("restore.started", ["request": request, "targetTrack": PlaybackDiagnostics.trackID(track.url), "position": String(position)])
            do {
                try await engine.load(url: track.url)
                guard !Task.isCancelled, self?.playbackRequest == revision else { return }
                await engine.seek(to: position)
                guard !Task.isCancelled, self?.playbackRequest == revision else { return }
                await MainActor.run {
                    guard let self else { return }
                    self.currentTrack = track
                    self.progress = position
                    if self.shouldAutoplay { engine.play() }
                    self.logContext("restore.completed", ["request": request])
                }
            } catch {
                self?.logContext("restore.failed", ["request": request].merging(PlaybackDiagnostics.errorFields(error)) { _, new in new })
                // Restore is best-effort. Silent failure is acceptable.
            }
        }
    }

    // MARK: - Wave 3 helpers

    /// Resolve a scope to its ordered list of tracks. Search scopes carry
    /// their own snapshot; the other cases derive from current state.
    private func tracksForScope(_ scope: PlaybackScope) -> [Track] {
        switch scope {
        case .all:                       return tracks
        case .favorites:                 return favoriteTracks
        case .recent:                    return recentlyPlayedTracks
        case .search(_, let results):    return results
        }
    }

    /// Called from `bindWave3` when the library's tracks change after init.
    /// Rebuilds the queue from the current scope so playback never points at
    /// stale URLs. For `.search`, re-ranks with the new library; if nothing
    /// matches any more, silently drops back to `.all`.
    private func reapplyScopeAfterLibraryChange() {
        switch currentScope {
        case .all:
            // Handled by the Wave 1 bindLibrary sink; nothing to do.
            return
        case .favorites, .recent:
            queue.setTracks(tracksForScope(currentScope), preservingCurrent: true)
        case .search(let query, _):
            let fresh = SearchEngine.rank(query, in: library.tracks)
            if fresh.isEmpty {
                clearScope()
            } else {
                queue.setTracks(fresh, preservingCurrent: true)
                currentScope = .search(query: query, results: fresh)
            }
        }
    }

    // MARK: - Diagnostics

    private static func errorKind(_ error: PlayerError) -> String {
        switch error {
        case .loadFailed: return "loadFailed"
        case .playbackFailed: return "playbackFailed"
        case .noTracksAvailable: return "noTracksAvailable"
        }
    }

    private func logContext(_ event: String, _ extra: [String: String] = [:]) {
        PlaybackDiagnostics.record(event, [
            "displayedTrack": PlaybackDiagnostics.trackID(currentTrack?.url),
            "queueTrack": PlaybackDiagnostics.trackID(queue.current?.url),
            "queuePosition": String(queue.position), "queueCount": String(queue.count),
            "repeatMode": String(describing: repeatMode), "shuffled": String(isShuffled),
            "reportedPlaying": String(isPlaying), "position": String(progress),
            "sleepTimer": String(describing: sleepTimer.mode)
        ].merging(extra) { _, new in new })
    }

    #if os(macOS)
    func exportDebugLog() {
        logContext("export.requested")
        engine.captureDiagnostics()
        MacPlaybackDiagnostics.shared.exportLog()
    }
    #endif

    // MARK: - Playback helper

    private func startPlayback(_ track: Track) {
        playbackRequest &+= 1
        let revision = playbackRequest
        playbackTask?.cancel()
        engine.pause() // Cancel recovery before the replacement load starts.
        shouldAutoplay = true
        isPlaying = true
        playbackTask = Task { [weak self] in
            await self?.loadAndPlay(track, revision: revision)
        }
    }

    private func loadAndPlay(_ track: Track, revision: Int) async {
        defer { if playbackRequest == revision { playbackTask = nil } }
        guard revision == playbackRequest, !Task.isCancelled else { return }
        let request = UUID().uuidString
        let context = ["request": request, "targetTrack": PlaybackDiagnostics.trackID(track.url), "autoStart": String(shouldAutoplay)]
        logContext("coordinator.load_started", context)
        do {
            try await engine.load(url: track.url)
            guard revision == playbackRequest, !Task.isCancelled else { return }
            logContext("coordinator.load_returned", context)
            if shouldAutoplay { engine.play() }
            currentTrack = track
            progress = 0
            persistence.update {
                $0.lastTrackURL = track.url
                $0.lastPosition = 0
            }
            // Wave 2: record this in the recently-played list.
            recordPlay(track)
            logContext("coordinator.load_committed", context)
        } catch is CancellationError {
            logContext("coordinator.load_cancelled", context)
        } catch let error as PlayerError {
            guard revision == playbackRequest else { return }
            shouldAutoplay = false
            isPlaying = false
            logContext("coordinator.load_failed", context.merging(["type": Self.errorKind(error)]) { _, new in new })
            currentError = error
        } catch {
            guard revision == playbackRequest else { return }
            shouldAutoplay = false
            isPlaying = false
            logContext("coordinator.load_failed", context.merging(PlaybackDiagnostics.errorFields(error)) { _, new in new })
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
