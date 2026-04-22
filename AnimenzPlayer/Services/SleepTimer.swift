import Foundation
import Combine

/// A sleep timer. Fires a single callback after its duration elapses, or when
/// the currently-playing track finishes if configured for "end of track".
///
/// The timer is restartable and cancellable from the UI. `remaining` is
/// published so the UI can show a countdown.
@MainActor
final class SleepTimer: ObservableObject {
    enum Mode: Equatable {
        case duration(TimeInterval)   // fires after `duration`
        case endOfTrack               // fires on the next track-finished event
    }

    @Published private(set) var mode: Mode?
    @Published private(set) var remaining: TimeInterval = 0

    /// Called on the main actor when the timer expires.
    var onExpire: (() -> Void)?

    private var timer: Timer?
    private var deadline: Date?

    // MARK: - Control

    func start(_ mode: Mode) {
        stop()
        self.mode = mode

        switch mode {
        case .duration(let d):
            deadline = Date().addingTimeInterval(d)
            remaining = d
            scheduleTicker()
        case .endOfTrack:
            remaining = 0  // unknown; UI shows "until current track ends"
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        deadline = nil
        mode = nil
        remaining = 0
    }

    /// Called by the view model when a track finishes. If we're in
    /// `.endOfTrack` mode, this is our signal to fire.
    func handleTrackFinished() {
        guard case .endOfTrack = mode else { return }
        expire()
    }

    // MARK: - Private

    private func scheduleTicker() {
        // Tick every second; precision here is for the visible countdown,
        // not for the actual expiration (which is checked against deadline).
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    private func tick() {
        guard let deadline else { return }
        let r = deadline.timeIntervalSinceNow
        if r <= 0 {
            remaining = 0
            expire()
        } else {
            remaining = r
        }
    }

    private func expire() {
        let callback = onExpire
        stop()
        callback?()
    }
}
