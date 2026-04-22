import Foundation
import AVFoundation

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

    var onTimeChange: ((Double) -> Void)? { get set }
    var onDurationChange: ((Double) -> Void)? { get set }
    var onPlayingChange: ((Bool) -> Void)? { get set }
    var onFinish: (() -> Void)? { get set }
    var onError: ((PlayerError) -> Void)? { get set }
}

// MARK: - AVPlayer implementation

final class AVPlayerEngine: PlaybackEngine {
    // MARK: Callbacks
    var onTimeChange: ((Double) -> Void)?
    var onDurationChange: ((Double) -> Void)?
    var onPlayingChange: ((Bool) -> Void)?
    var onFinish: (() -> Void)?
    var onError: ((PlayerError) -> Void)?

    // MARK: State
    private(set) var duration: Double = 0
    var currentTime: Double {
        let t = player.currentTime().seconds
        return t.isFinite ? t : 0
    }
    var isPlaying: Bool { player.timeControlStatus != .paused }

    // MARK: AVPlayer plumbing
    private let player = AVPlayer()
    private var timeObserver: Any?
    private var timeControlObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?

    // Tracks the most recent load so stale async results don't overwrite
    // state for a track the user has already skipped past.
    private var loadGeneration: Int = 0

    init() {
        configureAudioSession()
        addPeriodicObserver()
        observeTimeControlStatus()
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeControlObservation?.invalidate()
        itemStatusObservation?.invalidate()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    // MARK: - PlaybackEngine

    func load(url: URL) async throws {
        loadGeneration &+= 1
        let generation = loadGeneration

        let asset = AVURLAsset(url: url)

        // Pre-load duration so UI gets it in one shot (avoid the "0:00 → snap"
        // moment the old AVAudioPlayer code got for free because duration was
        // synchronous). If the asset can't be read at all, surface as a load
        // failure rather than a silent stall.
        let cmDuration: CMTime
        do {
            cmDuration = try await asset.load(.duration)
        } catch {
            throw PlayerError.loadFailed(url: url, error: error)
        }

        // If another load superseded us while we were awaiting, abort.
        guard generation == loadGeneration else { return }

        let item = AVPlayerItem(asset: asset)

        await MainActor.run {
            // Tear down observers bound to the previous item, if any.
            if let endObserver {
                NotificationCenter.default.removeObserver(endObserver)
                self.endObserver = nil
            }
            itemStatusObservation?.invalidate()

            player.replaceCurrentItem(with: item)

            let seconds = cmDuration.seconds
            duration = seconds.isFinite ? seconds : 0
            onDurationChange?(duration)
            onTimeChange?(0)

            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                self?.onFinish?()
            }

            itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                guard item.status == .failed else { return }
                let underlying = item.error ?? NSError(
                    domain: "AVPlayerEngine",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Unknown playback error"]
                )
                Self.dispatchMain {
                    self?.onError?(.playbackFailed(error: underlying))
                }
            }
        }
    }

    func play() { player.play() }
    func pause() { player.pause() }

    func seek(to time: Double) async {
        let cm = CMTime(seconds: time, preferredTimescale: 600)
        await player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
        onTimeChange?(time)
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        duration = 0
        onDurationChange?(0)
        onTimeChange?(0)
        onPlayingChange?(false)
    }

    // MARK: - Observers

    private func addPeriodicObserver() {
        // 0.25s matches the original Timer cadence. The time observer runs on
        // main, so callbacks are already correctly threaded.
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] cmTime in
            guard let self else { return }
            let t = cmTime.seconds
            self.onTimeChange?(t.isFinite ? t : 0)
        }
    }

    private func observeTimeControlStatus() {
        // `timeControlStatus` (iOS 10+/macOS 10.12+) is the modern way to ask
        // "is this thing playing right now". Unlike `rate`, it distinguishes
        // genuine paused state from "trying to play but buffering", and fires
        // reliably whenever AVPlayer transitions between them.
        timeControlObservation = player.observe(
            \.timeControlStatus,
            options: [.new]
        ) { [weak self] player, _ in
            let playing = player.timeControlStatus != .paused
            Self.dispatchMain {
                self?.onPlayingChange?(playing)
            }
        }
    }

    // MARK: - Helpers

    private static func dispatchMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private func configureAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        #endif
    }
}
