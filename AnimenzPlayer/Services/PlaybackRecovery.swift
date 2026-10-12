import Foundation

/// Playback intent and retry policy, independent of AVPlayer and the system clock.
/// Attempts are bounded across sleep/wake and reset only for a new user request/track.
@MainActor
final class PlaybackRecovery {
    private(set) var wantsPlayback = false
    private(set) var isSleeping = false
    private(set) var isRecovering = false
    private(set) var isAttempting = false
    private(set) var attempts = 0
    var onRetry: ((Int, Int) -> Void)?
    var onChange: (() -> Void)?
    var onCancelAttempt: (() -> Void)?
    var onExhausted: ((Error) -> Void)?
    private var work: Task<Void, Never>?
    private var revision = 0
    private var lastError: Error?
    private let delays: [Double]
    private let timeout: Double
    private let wait: (Double) async throws -> Void

    var preventsIdleSleep: Bool { wantsPlayback && !isSleeping && (!isRecovering || isAttempting) }

    init(delays: [Double] = [1, 2, 4], timeout: Double = 8,
         wait: @escaping (Double) async throws -> Void = { seconds in
             try await Task.sleep(for: .seconds(seconds))
         }) {
        self.delays = delays
        self.timeout = timeout
        self.wait = wait
    }

    deinit { work?.cancel() }

    func play(needsRecovery: Bool = false) {
        invalidate()
        wantsPlayback = true
        attempts = 0
        lastError = nil
        isRecovering = needsRecovery || isSleeping
        onChange?()
        if isRecovering && !isSleeping { schedule() }
    }

    func pause() {
        wantsPlayback = false
        isRecovering = false
        invalidate()
        onChange?()
    }

    func failed(_ error: Error) {
        lastError = error
        guard wantsPlayback else { return }
        // Status KVO and failed-to-finish may report the same failure. A failure
        // while already waiting must not consume another retry or reset its delay.
        guard !isRecovering || isAttempting else { return }
        isRecovering = true
        schedule()
    }

    func willSleep() {
        isSleeping = true
        if wantsPlayback { isRecovering = true }
        invalidate()
        onChange?()
    }

    func didWake() {
        guard isSleeping else { return }
        isSleeping = false
        onChange?()
        if wantsPlayback && isRecovering { schedule() }
    }

    /// Called only after real media time advances during an attempt, not merely
    /// because AVPlayer reports .playing (which the captured failure also did).
    func madeProgress() {
        guard wantsPlayback, !isSleeping, isRecovering, isAttempting else { return }
        isRecovering = false
        invalidate()
        PlaybackDiagnostics.record("recovery.succeeded", ["attempt": String(attempts)])
        onChange?()
    }

    func isCurrentAttempt(_ ticket: Int) -> Bool {
        revision == ticket && wantsPlayback && !isSleeping && isRecovering && isAttempting
    }

    private func invalidate() {
        revision &+= 1
        work?.cancel()
        work = nil
        isAttempting = false
        onCancelAttempt?()
    }

    private func schedule() {
        invalidate()
        onChange?()
        guard wantsPlayback, !isSleeping else { return }
        guard attempts < delays.count else {
            wantsPlayback = false
            isRecovering = false
            onChange?()
            let error = lastError ?? NSError(domain: "PlaybackRecovery", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Playback did not resume after three attempts. Press Play to retry."])
            PlaybackDiagnostics.record("recovery.exhausted", ["attempts": String(attempts)])
            onExhausted?(error)
            return
        }
        let ticket = revision
        let delay = delays[attempts]
        let wait = self.wait
        PlaybackDiagnostics.record("recovery.scheduled", ["attempt": String(attempts + 1), "delay": String(delay)])
        work = Task { [weak self] in
            do { try await wait(delay) } catch { return }
            guard !Task.isCancelled else { return }
            self?.attempt(ticket)
        }
    }

    private func attempt(_ ticket: Int) {
        guard ticket == revision, wantsPlayback, !isSleeping else { return }
        attempts += 1
        isAttempting = true
        onChange?()
        PlaybackDiagnostics.record("recovery.attempt", ["attempt": String(attempts)])
        onRetry?(attempts, ticket)
        guard isCurrentAttempt(ticket) else { return }
        let wait = self.wait
        let timeout = self.timeout
        work = Task { [weak self] in
            do { try await wait(timeout) } catch { return }
            guard !Task.isCancelled, let self, self.isCurrentAttempt(ticket) else { return }
            PlaybackDiagnostics.record("recovery.timeout", ["attempt": String(self.attempts)])
            self.schedule()
        }
    }
}

/// Paired, idempotent power assertion. Explicit sleep and display sleep remain
/// available; the assertion is released on pause, sleep, retry wait, and failure.
@MainActor
final class PlaybackActivity {
    private var token: NSObjectProtocol?
    private let begin: () -> NSObjectProtocol
    private let end: (NSObjectProtocol) -> Void

    init(begin: @escaping () -> NSObjectProtocol = {
        #if os(macOS)
        return ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled], reason: "Playing music")
        #else
        return NSObject()
        #endif
    }, end: @escaping (NSObjectProtocol) -> Void = { token in
        #if os(macOS)
        ProcessInfo.processInfo.endActivity(token)
        #endif
    }) {
        self.begin = begin
        self.end = end
    }

    deinit { if let token { end(token) } }

    func setActive(_ active: Bool) {
        if active, token == nil {
            token = begin()
            PlaybackDiagnostics.record("power.idle_sleep_prevented")
        } else if !active, let token {
            end(token)
            self.token = nil
            PlaybackDiagnostics.record("power.idle_sleep_allowed")
        }
    }
}
