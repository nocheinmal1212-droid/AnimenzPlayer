import Foundation
import MediaPlayer
import AVFoundation

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Intents that a remote control can trigger. Pure enum so the receiver
/// (the view model) doesn't need to import MediaPlayer.
enum NowPlayingIntent: Equatable {
    case play
    case pause
    case toggle
    case next
    case previous
    case seek(Double)
}

/// Intents emitted by `AVAudioSession` interruptions on iOS. On macOS
/// these never fire; the type still exists for a unified API.
enum InterruptionIntent: Equatable {
    case began       // lost audio — pause immediately
    case endedResume // got it back and system says "resume"
    case endedHold   // got it back but system does not want us to resume
}

/// Wraps `MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`, and (on iOS)
/// `AVAudioSession` interruption observation behind a small interface the
/// view model can depend on without pulling in MediaPlayer.
///
/// The controller is passive — it only translates system events into
/// `NowPlayingIntent` / `InterruptionIntent` callbacks and pushes
/// state changes into the system. All decisions about what to *do* stay
/// in the view model.
@MainActor
final class NowPlayingController {
    var onCommand: ((NowPlayingIntent) -> Void)?
    var onInterruption: ((InterruptionIntent) -> Void)?

    private let info = MPNowPlayingInfoCenter.default()
    private let commands = MPRemoteCommandCenter.shared()

    private var observerTokens: [NSObjectProtocol] = []
    private var commandTargets: [(MPRemoteCommand, Any)] = []

    init() {
        registerCommands()
        #if os(iOS)
        observeInterruptions()
        #endif
    }

    deinit {
        // Detach remote-command targets so they don't retain us after
        // teardown. (`commandTargets` holds the opaque tokens returned by
        // `addTarget`; re-invoking removeTarget on the matching command
        // clears the handler.)
        for (command, token) in commandTargets {
            command.removeTarget(token)
        }
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // MARK: - Public: state sync

    /// Pushes the current track's metadata into Now Playing. Call on every
    /// track change.
    func update(track: Track?, artwork: PlatformImage?, duration: Double) {
        guard let track else {
            info.nowPlayingInfo = nil
            info.playbackState = .stopped
            return
        }

        var dict: [String: Any] = [:]
        dict[MPMediaItemPropertyTitle] = track.title
        dict[MPMediaItemPropertyAlbumTitle] = "Animenz"
        dict[MPMediaItemPropertyArtist] = "Animenz"
        dict[MPMediaItemPropertyPlaybackDuration] = duration

        if let artwork {
            // The modern initializer takes a `boundsSize` and a closure that
            // returns an appropriately-sized image. We cheat (and it's the
            // idiomatic cheat) by ignoring `requestedSize` and returning the
            // image we have — the system will scale it.
            let mpArtwork = MPMediaItemArtwork(boundsSize: artwork.size) { _ in
                artwork
            }
            dict[MPMediaItemPropertyArtwork] = mpArtwork
        }

        info.nowPlayingInfo = dict
    }

    /// Updates the playback state and current time without replacing the
    /// whole info dict — cheap enough to call on every progress tick but
    /// we only actually call it on play/pause/seek transitions.
    func updatePlaybackState(isPlaying: Bool, elapsedTime: Double, rate: Double) {
        var dict = info.nowPlayingInfo ?? [:]
        dict[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsedTime
        dict[MPNowPlayingInfoPropertyPlaybackRate] = rate
        info.nowPlayingInfo = dict
        info.playbackState = isPlaying ? .playing : .paused
    }

    // MARK: - Remote commands

    private func registerCommands() {
        // Toggle, rather than separate play/pause, because our UI is a
        // single toggle button. The sample code Apple ships (and the
        // glucode.com post the search returned) both recommend this for
        // toggle-style UIs — it prevents the system from showing two
        // separate play and pause buttons.
        add(commands.togglePlayPauseCommand)  { [weak self] _ in
            self?.onCommand?(.toggle); return .success
        }
        add(commands.playCommand)  { [weak self] _ in
            self?.onCommand?(.play); return .success
        }
        add(commands.pauseCommand) { [weak self] _ in
            self?.onCommand?(.pause); return .success
        }
        add(commands.nextTrackCommand) { [weak self] _ in
            self?.onCommand?(.next); return .success
        }
        add(commands.previousTrackCommand) { [weak self] _ in
            self?.onCommand?(.previous); return .success
        }

        // Enabling this adds the scrubber to Lock Screen / Control Center.
        add(commands.changePlaybackPositionCommand) { [weak self] event in
            guard let ev = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self?.onCommand?(.seek(ev.positionTime))
            return .success
        }
    }

    private func add(
        _ command: MPRemoteCommand,
        handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
    ) {
        command.isEnabled = true
        let token = command.addTarget(handler: handler)
        commandTargets.append((command, token))
    }

    // MARK: - Interruptions (iOS only)

    #if os(iOS)
    private func observeInterruptions() {
        let token = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleInterruption(note)
        }
        observerTokens.append(token)
    }

    private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else {
            return
        }

        switch type {
        case .began:
            onInterruption?(.began)
        case .ended:
            // The `shouldResume` option tells us whether the system thinks
            // it's appropriate for us to start playing again. For phone
            // calls this is typically true; for Siri sometimes not.
            let optsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let opts = AVAudioSession.InterruptionOptions(rawValue: optsRaw)
            onInterruption?(opts.contains(.shouldResume) ? .endedResume : .endedHold)
        @unknown default:
            break
        }
    }
    #endif
}
