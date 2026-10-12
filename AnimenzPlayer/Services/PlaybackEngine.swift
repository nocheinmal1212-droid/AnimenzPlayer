import Foundation
import AVFoundation
#if os(macOS)
import AppKit
#endif

/// The audio-playback surface the rest of the app sees. Pure callbacks (no
/// Combine, no SwiftUI) keep the protocol trivially mockable for unit tests.
///
/// Callers MUST expect callbacks on the main thread — implementations are
/// responsible for hopping if their underlying framework doesn't deliver there.
protocol PlaybackEngine: AnyObject {
    var currentTime: Double { get }
    var duration: Double { get }
    var isPlaying: Bool { get }

    func load(url: URL) async throws
    func play()
    func pause()
    func seek(to time: Double) async
    func stop()
    func captureDiagnostics()

    var onTimeChange: ((Double) -> Void)? { get set }
    var onDurationChange: ((Double) -> Void)? { get set }
    var onPlayingChange: ((Bool) -> Void)? { get set }
    var onFinish: (() -> Void)? { get set }
    var onError: ((PlayerError) -> Void)? { get set }
}

extension PlaybackEngine {
    func captureDiagnostics() {}
}

// MARK: - AVPlayer implementation

@MainActor
final class AVPlayerEngine: PlaybackEngine {
    var onTimeChange: ((Double) -> Void)?
    var onDurationChange: ((Double) -> Void)?
    var onPlayingChange: ((Bool) -> Void)?
    var onFinish: (() -> Void)?
    var onError: ((PlayerError) -> Void)?

    private(set) var duration: Double = 0
    var currentTime: Double {
        let time = player.currentTime().seconds
        return time.isFinite ? time : 0
    }
    // Keep Pause available while recovering so the user can cancel a retry.
    // Actual AVPlayer state remains separately recorded in diagnostics.
    var isPlaying: Bool {
        #if os(macOS)
        return recovery.wantsPlayback
        #else
        return player.timeControlStatus != .paused
        #endif
    }

    private var player: AVPlayer
    private var timeObserver: Any?
    private var playerObservations: [NSKeyValueObservation] = []
    private var itemStatusObservation: NSKeyValueObservation?
    private var itemTokens: [NSObjectProtocol] = []
    private var loadGeneration = 0
    private var currentURL: URL?
    private var recoveryPosition = 0.0
    private var attemptStartPosition = 0.0
    private let recovery: PlaybackRecovery
    private let activity: PlaybackActivity
    #if os(macOS)
    private var diagnostics: PlayerStateDiagnostics?
    private let workspaceCenter: NotificationCenter
    private var workspaceTokens: [NSObjectProtocol] = []
    #endif

    init(player: AVPlayer = AVPlayer(), recovery: PlaybackRecovery? = nil,
         activity: PlaybackActivity? = nil, workspaceCenter: NotificationCenter? = nil) {
        self.player = player
        self.recovery = recovery ?? PlaybackRecovery()
        self.activity = activity ?? PlaybackActivity()
        #if os(macOS)
        self.workspaceCenter = workspaceCenter ?? NSWorkspace.shared.notificationCenter
        self.recovery.onChange = { [weak self] in
            guard let self else { return }
            self.activity.setActive(self.recovery.preventsIdleSleep)
            self.diagnostics?.setRequestedPlaying(self.recovery.wantsPlayback)
            self.onPlayingChange?(self.isPlaying)
        }
        self.recovery.onCancelAttempt = { [weak self] in self?.player.currentItem?.cancelPendingSeeks() }
        self.recovery.onRetry = { [weak self] attempt, ticket in self?.retry(attempt, ticket: ticket) }
        self.recovery.onExhausted = { [weak self] error in
            self?.player.pause()
            self?.onError?(.playbackFailed(error: error))
        }
        workspaceTokens = [
            self.workspaceCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    // A rebuilt item may still be seeking from zero. Keep the
                    // saved position if sleep interrupts that recovery attempt.
                    if !self.recovery.isRecovering { self.recoveryPosition = self.currentTime }
                    self.recovery.willSleep()
                    self.player.pause() // Preserve intent, but do not play during dark wakes.
                    self.diagnostics?.snapshot("recovery.sleep_suspended")
                }
            },
            self.workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.recovery.didWake() }
            }
        ]
        #endif
        configureAudioSession()
        observePlayer()
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        playerObservations.forEach { $0.invalidate() }
        itemStatusObservation?.invalidate()
        itemTokens.forEach { NotificationCenter.default.removeObserver($0) }
        #if os(macOS)
        workspaceTokens.forEach { workspaceCenter.removeObserver($0) }
        #endif
    }

    func load(url: URL) async throws {
        loadGeneration &+= 1
        let generation = loadGeneration
        #if os(macOS)
        recovery.pause() // Invalidate every retry for the previous track.
        #endif
        player.pause()
        let context = ["generation": String(generation), "track": PlaybackDiagnostics.trackID(url)]
        PlaybackDiagnostics.record("engine.load_started", context)
        let asset = AVURLAsset(url: url)
        let cmDuration: CMTime
        do {
            cmDuration = try await asset.load(.duration)
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            PlaybackDiagnostics.record("engine.load_failed", context.merging(PlaybackDiagnostics.errorFields(error)) { _, new in new })
            throw PlayerError.loadFailed(url: url, error: error)
        }
        guard generation == loadGeneration else {
            PlaybackDiagnostics.record("engine.load_superseded", context)
            throw CancellationError()
        }
        // Everything after the await is serialized on MainActor, including the
        // generation check and installation, so an older load cannot win later.
        currentURL = url
        recoveryPosition = 0
        let seconds = cmDuration.seconds
        duration = seconds.isFinite ? seconds : 0
        if player.status == .failed { replacePlayer() }
        install(AVPlayerItem(asset: asset), generation: generation)
        onDurationChange?(duration)
        onTimeChange?(0)
        PlaybackDiagnostics.record("engine.load_completed", context)
    }

    private func install(_ item: AVPlayerItem, generation: Int) {
        detachItem()
        player.replaceCurrentItem(with: item)
        #if os(macOS)
        diagnostics?.installed(item, generation: generation)
        #endif
        itemTokens = [
            NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self, weak item] _ in
                MainActor.assumeIsolated {
                    guard let self, let item, self.player.currentItem === item else { return }
                    #if os(macOS)
                    guard !self.recovery.isSleeping, self.recovery.wantsPlayback else { return }
                    self.recovery.pause()
                    #endif
                    self.onFinish?()
                }
            },
            NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self, weak item] note in
                let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                    ?? NSError(domain: "AVPlayerEngine", code: -1)
                MainActor.assumeIsolated {
                    guard let self, let item, self.player.currentItem === item else { return }
                    self.handleFailure(error)
                }
            }
        ]
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self, weak item] observed, _ in
            guard observed.status == .failed else { return }
            let error = observed.error ?? NSError(domain: "AVPlayerEngine", code: -1)
            Self.dispatchMain { [weak self, weak item] in
                guard let self, let item, self.player.currentItem === item else { return }
                self.handleFailure(error)
            }
        }
    }

    private func detachItem() {
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        itemTokens.forEach { NotificationCenter.default.removeObserver($0) }
        itemTokens.removeAll()
    }

    func play() {
        guard player.currentItem != nil else { return }
        #if os(macOS)
        let needsRecovery = recovery.isRecovering || player.status == .failed || player.currentItem?.status == .failed
        recovery.play(needsRecovery: needsRecovery)
        diagnostics?.command("play")
        guard !recovery.isSleeping, !needsRecovery else { return }
        #endif
        player.play()
    }

    func pause() {
        #if os(macOS)
        recovery.pause()
        diagnostics?.command("pause")
        #endif
        player.pause()
    }

    func captureDiagnostics() {
        #if os(macOS)
        diagnostics?.snapshot("export.player_state")
        #endif
    }

    func seek(to time: Double) async {
        let generation = loadGeneration
        let item = player.currentItem
        let request = UUID().uuidString
        #if os(macOS)
        diagnostics?.seekStarted(request, target: time)
        #endif
        let finished = await player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        #if os(macOS)
        diagnostics?.seekFinished(request, finished: finished)
        #endif
        guard finished, !Task.isCancelled, generation == loadGeneration, player.currentItem === item else { return }
        recoveryPosition = time
        onTimeChange?(time)
    }

    func stop() {
        loadGeneration &+= 1
        pause()
        detachItem()
        player.replaceCurrentItem(with: nil)
        currentURL = nil
        duration = 0
        onDurationChange?(0)
        onTimeChange?(0)
        onPlayingChange?(false)
    }

    private func handleFailure(_ error: Error) {
        PlaybackDiagnostics.record("engine.playback_failure", PlaybackDiagnostics.errorFields(error))
        #if os(macOS)
        if !recovery.isRecovering { recoveryPosition = currentTime }
        if recovery.wantsPlayback {
            player.pause()
            recovery.failed(error)
        }
        else { onError?(.playbackFailed(error: error)) }
        #else
        onError?(.playbackFailed(error: error))
        #endif
    }

    #if os(macOS)
    private func retry(_ attempt: Int, ticket: Int) {
        guard recovery.isCurrentAttempt(ticket), let url = currentURL else { return }
        attemptStartPosition = currentTime
        if attempt == 1, player.status != .failed, player.currentItem?.status == .readyToPlay {
            // The recorded CannotStart failure kept both statuses ready. Give the
            // recovered output device one chance before rebuilding audio objects.
            player.play()
            diagnostics?.snapshot("recovery.replay")
            return
        }
        let position = recoveryPosition
        replacePlayer()
        install(AVPlayerItem(url: url), generation: loadGeneration)
        diagnostics?.setRequestedPlaying(recovery.wantsPlayback)
        let candidate = player
        let generation = loadGeneration
        candidate.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak candidate] finished in
            Self.dispatchMain { [weak self, weak candidate] in
                guard let self, let candidate, candidate === self.player,
                      generation == self.loadGeneration, self.recovery.isCurrentAttempt(ticket) else { return }
                guard finished else {
                    self.recovery.failed(NSError(domain: "PlaybackRecovery", code: 2))
                    return
                }
                self.attemptStartPosition = self.currentTime
                candidate.play()
                self.diagnostics?.snapshot("recovery.rebuilt")
            }
        }
    }
    #endif

    private func replacePlayer() {
        detachItem()
        if let timeObserver { player.removeTimeObserver(timeObserver); self.timeObserver = nil }
        playerObservations.forEach { $0.invalidate() }
        playerObservations.removeAll()
        #if os(macOS)
        diagnostics = nil
        #endif
        player.pause()
        player.replaceCurrentItem(with: nil)
        let replacement = AVPlayer()
        replacement.volume = player.volume
        replacement.isMuted = player.isMuted
        player = replacement
        observePlayer()
    }

    private func observePlayer() {
        #if os(macOS)
        diagnostics = PlayerStateDiagnostics(player: player)
        #endif
        let observedPlayer = player
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self, weak observedPlayer] _ in
            MainActor.assumeIsolated {
                guard let self, let observedPlayer, observedPlayer === self.player else { return }
                let seconds = observedPlayer.currentTime().seconds
                self.onTimeChange?(seconds.isFinite ? seconds : 0)
                #if os(macOS)
                if seconds.isFinite, observedPlayer.timeControlStatus == .playing,
                   seconds > self.attemptStartPosition + 0.5 {
                    self.recovery.madeProgress()
                }
                #endif
            }
        }
        playerObservations = [
            player.observe(\.timeControlStatus, options: [.new]) { [weak self, weak observedPlayer] _, _ in
                Self.dispatchMain { [weak self, weak observedPlayer] in
                    guard let self, let observedPlayer, observedPlayer === self.player else { return }
                    self.onPlayingChange?(self.isPlaying)
                }
            },
            player.observe(\.status, options: [.new]) { [weak self, weak observedPlayer] observed, _ in
                guard observed.status == .failed else { return }
                let error = observed.error ?? NSError(domain: "AVPlayerEngine", code: -1)
                Self.dispatchMain { [weak self, weak observedPlayer] in
                    guard let self, let observedPlayer, observedPlayer === self.player else { return }
                    self.handleFailure(error)
                }
            }
        ]
    }

    nonisolated private static func dispatchMain(_ work: @escaping @MainActor () -> Void) {
        if Thread.isMainThread { MainActor.assumeIsolated { work() } }
        else { DispatchQueue.main.async { work() } }
    }

    private func configureAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        #endif
    }
}
